#!/usr/bin/env python3
"""Optional live validate E2E: local CLI -> supplied relay -> real Mirrors server.

--relay-argv is a JSON command array. The relay must consume one JSONL request
on stdin and emit only the server's JSONL reply on stdout. Credentials and
endpoint setup belong to the operator; no credentials are copied by this test.
"""
import argparse
import json
import pathlib
import socket
import subprocess
import tempfile
import threading


def run_case(binary, relay, step, expected, async_mode=False):
    with tempfile.TemporaryDirectory(prefix='mirrors-remote-closure-') as directory:
        root = pathlib.Path(directory)
        (root / 'Main.tla').write_text(
            '---- MODULE Main ----\nEXTENDS Naturals, Helper\n'
            'VARIABLE\n  \\* @type: Int;\n  count\nInit == count = 0\n'
            "Next == count' = count + Step\nSafe == count >= 0\n====\n")
        (root / 'Helper.tla').write_text('---- MODULE Helper ----\nEXTENDS Leaf\n====\n')
        (root / 'Leaf.tla').write_text(f'---- MODULE Leaf ----\nEXTENDS Integers\nStep == {step}\n====\n')
        errors, replies = [], []
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            listener.listen()
            listener.settimeout(15)

            def forward():
                try:
                    with listener.accept()[0] as connection:
                        connection.settimeout(60)
                        stream = connection.makefile('rb')
                        request = stream.readline(65537)
                        parsed = json.loads(request)
                        assert parsed['spec']['sources'] == [
                            (root / name).read_text() for name in
                            ['Main.tla', 'Helper.tla', 'Leaf.tla']]
                        assert directory not in request.decode()
                        if async_mode:
                            process = subprocess.Popen(relay, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
                            try:
                                for _ in range(6):
                                    process.stdin.write(request)
                                    process.stdin.flush()
                                    response = process.stdout.readline(65537)
                                    reply = json.loads(response)
                                    replies.append(reply)
                                    connection.sendall(response)
                                    if reply['proto_step'] in ('job_result', 'register_error', 'protocol_error'):
                                        break
                                    request = stream.readline(65537)
                                    assert request, 'CLI disconnected before its async result'
                                else:
                                    raise AssertionError('async probe exceeded its poll budget')
                            finally:
                                process.stdin.close()
                                try:
                                    process.wait(timeout=10)
                                except subprocess.TimeoutExpired:
                                    process.kill()
                                    process.wait()
                        else:
                            result = subprocess.run(relay, input=request, capture_output=True, timeout=55)
                            # Interactive TLS relays may wait after the reply and
                            # exit via their operator-supplied timeout.
                            assert result.returncode in (0, 124), result.stderr.decode(errors='replace')
                            reply = json.loads(result.stdout)
                            replies.append(reply)
                            connection.sendall(result.stdout)
                        stream.close()
                except Exception as error:
                    errors.append(str(error))

            thread = threading.Thread(target=forward, daemon=True)
            thread.start()
            result = subprocess.run([
                str(binary), 'validate', '--host', '127.0.0.1', '--port',
                str(listener.getsockname()[1]), '--spec', str(root / 'Main.tla'),
                '--inv', 'Safe', '--init', 'Init', '--next', 'Next', '--bound', '3',
            ] + (['--async'] if async_mode else []), capture_output=True, text=True, timeout=70)
            thread.join(60)
            assert not errors and not thread.is_alive(), errors
            assert result.returncode == expected, (result.returncode, result.stdout, result.stderr)
            if async_mode:
                assert replies[0]['proto_step'] == 'job_accepted', replies
                assert replies[-1]['proto_step'] == 'job_result', replies
                assert replies[-1]['jobId'] == replies[0]['jobId'], replies
                verdict = replies[-1]['outcome']['validate']
            else:
                assert replies[0]['proto_step'] == 'spec_validated', replies
                verdict = replies[0]['result']
            if expected == 0:
                assert verdict == 'valid' and result.stdout.strip() == 'VALID'
            else:
                assert 'invalid' in verdict and result.stdout.startswith('INVALID\n')
            print(json.dumps({'leafStep': step, 'modulesSent': 3,
                              'remoteVerdict': 'valid' if expected == 0 else 'invalid',
                              'cliExit': result.returncode, 'async': async_mode}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--async', dest='async_mode', action='store_true',
                        help='test async submission and awaits; requires an interactive JSONL relay')
    parser.add_argument('--relay-argv', required=True, type=json.loads)
    parser.add_argument('--binary', type=pathlib.Path,
                        default=pathlib.Path(__file__).resolve().parents[1] / '.lake/build/bin/mirror')
    args = parser.parse_args()
    if not isinstance(args.relay_argv, list) or not args.relay_argv or not all(
            isinstance(value, str) for value in args.relay_argv):
        parser.error('--relay-argv must be a nonempty JSON array of strings')
    run_case(args.binary.resolve(), args.relay_argv, 1, 0, args.async_mode)
    run_case(args.binary.resolve(), args.relay_argv, -1, 1, args.async_mode)
    print('REMOTE VALIDATE CLOSURE E2E GREEN')


if __name__ == '__main__':
    main()
