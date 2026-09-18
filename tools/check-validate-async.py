#!/usr/bin/env python3
"""Async validation CLI protocol, correlation, and exit-code regressions."""
import json
import pathlib
import socket
import subprocess
import tempfile
import threading

BINARY = pathlib.Path(__file__).resolve().parents[1] / '.lake/build/bin/mirror'
ACCEPTED = {'proto_step': 'job_accepted', 'jobId': 'owned-job', 'kind': 'validate'}


def status(phase, job='owned-job'):
    return {'proto_step': 'job_status', 'jobId': job, 'phase': phase}


def result(outcome, job='owned-job'):
    return {'proto_step': 'job_result', 'jobId': job, 'outcome': outcome}


def run_case(root, label, replies, expected_exit, expected_text):
    failures = []
    with socket.socket() as server:
        server.bind(('127.0.0.1', 0))
        server.listen()
        server.settimeout(5)

        def serve():
            try:
                with server.accept()[0] as connection:
                    connection.settimeout(5)
                    with connection.makefile('rb') as stream:
                        for index, reply in enumerate(replies):
                            request = json.loads(stream.readline(65537))
                            if index == 0:
                                assert request['proto_step'] == 'register_validate_async', request
                                assert request['spec']['sources'] == [
                                    (root / name).read_text() for name in ['Main.tla', 'Child.tla']]
                            else:
                                assert request == {'proto_step': 'await_job', 'jobId': 'owned-job', 'timeoutSecs': 30}, request
                            if reply is None:
                                break
                            connection.sendall((json.dumps(reply) + '\n').encode())
            except Exception as error:
                failures.append(repr(error))

        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
        completed = subprocess.run([
            str(BINARY), 'validate', '--async', '--host', '127.0.0.1',
            '--port', str(server.getsockname()[1]), '--spec', str(root / 'Main.tla'),
        ], capture_output=True, text=True, timeout=10)
        thread.join(6)
        assert not thread.is_alive() and not failures, (label, failures)
        assert completed.returncode == expected_exit, (label, completed)
        output = completed.stdout if expected_exit < 2 else completed.stderr
        assert expected_text in output, (label, completed)


def main():
    with tempfile.TemporaryDirectory(prefix='validate-async-') as directory:
        root = pathlib.Path(directory)
        (root / 'Main.tla').write_text('---- MODULE Main ----\nEXTENDS Child\n====\n')
        (root / 'Child.tla').write_text('---- MODULE Child ----\n====\n')
        cases = [
            ('long poll', [ACCEPTED, status('pending'), status('running'), result({'validate': 'valid'})], 0, 'VALID\n'),
            ('invalid', [ACCEPTED, result({'validate': {'invalid': 'deliberate violation'}})], 1, 'INVALID\ndeliberate violation'),
            ('worker error', [ACCEPTED, result({'error': 'worker failed'})], 2, 'worker failed'),
            ('denied', [{'proto_step': 'register_error', 'error': 'queue full'}], 2, 'queue full'),
            ('wrong accepted kind', [{**ACCEPTED, 'kind': 'gen_traces'}], 2, 'expected validation job_accepted'),
            ('empty job', [{**ACCEPTED, 'jobId': ''}], 2, 'empty async validation job id'),
            ('wrong result job', [ACCEPTED, result({'validate': 'valid'}, 'other')], 2, 'job id mismatch'),
            ('wrong status job', [ACCEPTED, status('running', 'other')], 2, 'job id mismatch'),
            ('wrong result kind', [ACCEPTED, result({'genTraces': {'itfTracePaths': [], 'itfTraces': []}})], 2, 'unexpected trace-generation'),
            ('unknown', [ACCEPTED, status('unknown')], 2, 'unknown or evicted'),
            ('cancelled', [ACCEPTED, status('cancelled')], 2, 'cancelled'),
            ('no terminal result', [ACCEPTED, status('done')], 2, 'ended without a result'),
            ('disconnect', [ACCEPTED, None], 2, 'connection closed'),
        ]
        for case in cases:
            run_case(root, *case)
    print(f'ASYNC VALIDATE CLI GREEN ({len(cases)} cases)')


if __name__ == '__main__':
    main()
