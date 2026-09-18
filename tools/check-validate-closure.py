#!/usr/bin/env python3
"""Exercise the actual validate CLI against a server without shared source files."""
import json
import pathlib
import socket
import subprocess
import tempfile
import threading

ROOT = pathlib.Path(__file__).resolve().parents[1]
BINARY = ROOT / '.lake/build/bin/mirror'


def main():
    with tempfile.TemporaryDirectory(prefix='validate-closure-') as directory:
        root = pathlib.Path(directory)
        (root / 'Main.tla').write_text('---- MODULE Main ----\nEXTENDS Helper, Naturals\nI == INSTANCE Leaf\n====\n')
        (root / 'Helper.tla').write_text('---- MODULE Helper ----\nEXTENDS Leaf\n====\n')
        (root / 'Leaf.tla').write_text('---- MODULE Leaf ----\nValue == 1\n====\n')
        with socket.socket() as server:
            server.bind(('127.0.0.1', 0))
            server.listen()
            server.settimeout(10)
            received, failures = [], []

            def serve():
                try:
                    with server.accept()[0] as connection:
                        connection.settimeout(10)
                        with connection.makefile('rb') as stream:
                            received.append(json.loads(stream.readline(65537)))
                        connection.sendall(b'{"proto_step":"spec_validated","result":"valid"}\n')
                except Exception as error:
                    failures.append(error)

            thread = threading.Thread(target=serve, daemon=True)
            thread.start()
            command = [str(BINARY), 'validate', '--host', '127.0.0.1', '--port',
                       str(server.getsockname()[1]), '--spec', str(root / 'Main.tla')]
            result = subprocess.run(command, cwd='/', capture_output=True, text=True, timeout=15)
            thread.join(11)
            assert not failures and not thread.is_alive(), failures
            assert result.returncode == 0 and result.stdout.strip() == 'VALID', result
            request = received[0]
            assert request['proto_step'] == 'register_validate', request
            sources = request['spec']['sources']
            assert sources == [(root / name).read_text() for name in ['Main.tla', 'Helper.tla', 'Leaf.tla']], request
            assert directory not in json.dumps(request), request
            # Neither failure may connect to the still-listening server.
            (root / 'Leaf.tla').unlink()
            result = subprocess.run(command, capture_output=True, text=True, timeout=10)
            assert result.returncode == 2 and 'missing sibling' in result.stderr, result
            (root / 'Leaf.tla').write_text('---- MODULE Leaf ----\n(*' + 'x' * 66000 + '*)\n====\n')
            result = subprocess.run(command, capture_output=True, text=True, timeout=10)
            assert result.returncode == 2 and '65535-byte' in result.stderr, result
            server.settimeout(0.1)
            try:
                connection, _ = server.accept()
            except TimeoutError:
                pass
            else:
                connection.close()
                raise AssertionError('local failure opened a server connection')
    print('VALIDATE CLOSURE CLI GREEN')


if __name__ == '__main__':
    main()
