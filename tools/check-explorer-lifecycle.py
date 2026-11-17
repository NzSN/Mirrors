#!/usr/bin/env python3
"""Exercise production explorer cleanup with a scripted backend, never Apalache."""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def fixture(audit):
    from explorer_test_server import Server, Handler
    port = int(next(arg.split('=', 1)[1] for arg in os.sys.argv if arg.startswith('--port=')))
    with Server(('127.0.0.1', port), Handler) as server:
        server.mode, server.audit = 'clean', audit
        server.steps = server.health_calls = 0
        server.serve_forever()


def main():
    if os.name != 'posix' or not Path('/proc/self/fd').is_dir():
        print('SKIP explorer descriptor lifecycle: requires Linux /proc')
        return
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mirror', type=Path, default=ROOT / '.lake/build/bin/mirror')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='mirrors-explorer-lifecycle-') as directory:
        scratch = Path(directory)
        audit = scratch / 'rpc.jsonl'
        shim = scratch / 'scripted-backend'
        shim.write_text('#!' + os.sys.executable + '\nimport sys\n'
                        + 'sys.path.insert(0, ' + repr(str(ROOT / 'tools')) + ')\n'
                        + 'from importlib.machinery import SourceFileLoader\n'
                        + 'm = SourceFileLoader("lifecycle", ' + repr(str(Path(__file__).resolve()))
                        + ').load_module()\nm.fixture(' + repr(str(audit)) + ')\n')
        shim.chmod(0o700)
        with socket.socket() as reserve:
            reserve.bind(('127.0.0.1', 0))
            port = reserve.getsockname()[1]
        child = subprocess.Popen([str(args.mirror.resolve()), '--serve', str(port), '--bind',
                                  '127.0.0.1', '--jobs', '1'], stdout=subprocess.DEVNULL,
                                 stderr=subprocess.PIPE, env={**os.environ, 'APALACHE_MC': str(shim)})
        try:
            for _ in range(100):
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=.2):
                        break
                except OSError:
                    assert child.poll() is None, 'daemon exited'
                    time.sleep(.05)
            else:
                raise AssertionError('daemon did not start')

            def descriptors():
                return len(list(Path(f'/proc/{child.pid}/fd').iterdir()))

            def session(kind, report):
                registration = {'proto_step': kind, 'spec': {'sources': ['fixture']},
                                'invariants': [], 'exports': [], 'maxSteps': 1}
                with socket.create_connection(('127.0.0.1', port), timeout=10) as conn:
                    conn.sendall((json.dumps(registration) + '\n').encode())
                    with conn.makefile('rb') as stream:
                        first = json.loads(stream.readline())
                        assert first['proto_step'] in ('spec_validated', 'explorer_ready'), first
                        if kind == 'register_explore':
                            assert json.loads(stream.readline())['proto_step'] == 'initial_state'
                        if report is not None:
                            conn.sendall(report + b'\n')
                            list(stream)  # Wait for production session teardown.
                assert child.poll() is None, 'daemon exited during explorer session'

            # Warm up the worker/task runtime before counting handles.
            session('register_explore_session', b'{"proto_step":"explore_done"}')
            time.sleep(.1)
            before = descriptors()
            for _ in range(3):
                for kind, report in [
                    ('register_explore', b'{"proto_step":"report_state","state":{"x":1}}'),
                    ('register_explore_session', b'{"proto_step":"explore_done"}'),
                    ('register_explore', b'{bad-json'),
                    ('register_explore_session', None)]:
                    session(kind, report)
            deadline = time.monotonic() + 3
            while descriptors() > before and time.monotonic() < deadline:
                time.sleep(.05)
            after = descriptors()
            assert after <= before, f'explorer sockets leaked: {before} -> {after} over 12 sessions'
            print(f'EXPLORER LIFECYCLE GREEN: 12 sessions, descriptors {before} -> {after}')
        finally:
            child.terminate()
            child.communicate(timeout=10)


if __name__ == '__main__':
    main()
