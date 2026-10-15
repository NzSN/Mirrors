#!/usr/bin/env python3
"""Bounded remote-WSL-only scripted peers for shipped Mirrors CLI paths.

No server, compiler, Apalache, TLC, or model operation is launched. Run this
only on the approved remote Ubuntu WSL host, using an existing mirror binary.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import socket
import subprocess
import tempfile
import threading
import time
from datetime import datetime, timezone

MAX_PAYLOAD = 65535
PEER_DEADLINE = 8.0
PROCESS_DEADLINE = 12.0
FOLLOWUP_DEADLINE = 2.0
# Exact minimal source bytes already used by tools/check-validate-async.py.
SOURCES = {
    'Main.tla': '---- MODULE Main ----\nEXTENDS Child\n====\n',
    'Child.tla': '---- MODULE Child ----\n====\n',
}
JOB_ID = 'probe-owned'
TERMINAL_ERROR = 'deliberate scripted terminal protocol error'


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def save_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n', encoding='utf-8')


class Peer:
    def __init__(self, mode):
        self.mode = mode
        self.requests = []
        self.events = []
        self.error = None
        self.connection = None
        self.stop = threading.Event()
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.listener.bind(('127.0.0.1', 0))
        self.listener.listen(1)
        self.listener.settimeout(PEER_DEADLINE)
        self.port = self.listener.getsockname()[1]
        self.thread = threading.Thread(target=self.serve, name='owned-scripted-peer', daemon=True)

    def receive(self, stream, optional=False):
        try:
            line = stream.readline(MAX_PAYLOAD + 2)
        except (socket.timeout, TimeoutError):
            if optional:
                self.events.append('bounded follow-up wait expired')
                return None
            raise
        if not line:
            self.events.append('client EOF')
            return None
        if not line.endswith(b'\n') or len(line) - 1 > MAX_PAYLOAD:
            raise ValueError('client emitted an unterminated or oversized frame')
        value = json.loads(line.decode('utf-8'))
        if not isinstance(value, dict):
            raise ValueError('client frame is not an object')
        self.requests.append({'bytes': len(line) - 1, 'json': value})
        return value

    def send(self, value, terminated=True):
        raw = json.dumps(value, separators=(',', ':')).encode('utf-8')
        assert len(raw) <= MAX_PAYLOAD
        self.connection.sendall(raw + (b'\n' if terminated else b''))
        self.events.append({'reply': value, 'terminated': terminated})

    def serve(self):
        try:
            connection, _ = self.listener.accept()
            self.connection = connection
            with connection:
                connection.settimeout(PEER_DEADLINE)
                with connection.makefile('rb') as stream:
                    first = self.receive(stream)
                    if first is None:
                        raise ValueError('client closed before registration')
                    expected = 'register_trace_gen_async' if self.mode == 'terminal-cancel' else 'register_validate'
                    if first.get('proto_step') != expected:
                        raise ValueError(f'expected {expected}, got {first!r}')
                    if first.get('spec', {}).get('sources') != list(SOURCES.values()):
                        raise ValueError('registration did not include the exact source closure')
                    if self.mode != 'terminal-cancel':
                        self.send({'proto_step': 'spec_validated', 'result': 'valid'},
                                  terminated=self.mode == 'valid-lf')
                        connection.shutdown(socket.SHUT_WR)
                        self.receive(stream, optional=True)
                    else:
                        self.send({'proto_step': 'job_accepted', 'jobId': JOB_ID, 'kind': 'gen_traces'})
                        second = self.receive(stream)
                        expected_await = {'proto_step': 'await_job', 'jobId': JOB_ID, 'timeoutSecs': 30}
                        if second != expected_await:
                            raise ValueError(f'expected exact await request, got {second!r}')
                        self.send({'proto_step': 'protocol_error', 'error': TERMINAL_ERROR})
                        connection.settimeout(FOLLOWUP_DEADLINE)
                        third = self.receive(stream, optional=True)
                        if third is not None:
                            expected_cancel = {'proto_step': 'cancel_job', 'jobId': JOB_ID}
                            self.events.append({'unwanted_followup': third,
                                                'is_expected_cancel': third == expected_cancel})
                            # Defensive bounded acknowledgement; current cancelOwned
                            # writes without waiting for any reply.
                            try:
                                self.send({'proto_step': 'job_status', 'jobId': JOB_ID, 'phase': 'cancelled'})
                            except (BrokenPipeError, ConnectionResetError):
                                self.events.append('client closed before optional cancel acknowledgement')
        except Exception as error:
            if not self.stop.is_set():
                self.error = f'{type(error).__name__}: {error}'
        finally:
            self.connection = None
            self.listener.close()

    def close(self):
        self.stop.set()
        if self.connection is not None:
            try:
                self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.connection.close()
        self.listener.close()
        self.thread.join(PEER_DEADLINE + 1)
        if self.thread.is_alive():
            raise RuntimeError('owned scripted peer did not stop within its bound')


def stop_child(process):
    """Terminate and reap only the owned CLI process group."""
    if process is None:
        return
    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=2)
    else:
        process.wait(timeout=2)


def run_case(binary, root, name, mode):
    case = root / name
    case.mkdir()
    for filename, text in SOURCES.items():
        (case / filename).write_text(text, encoding='utf-8')
    peer = Peer(mode)
    command = [str(binary), 'trace-gen' if mode == 'terminal-cancel' else 'validate',
               '--host', '127.0.0.1', '--port', str(peer.port), '--spec', str(case / 'Main.tla')]
    if mode == 'terminal-cancel':
        command.extend(['--async', '--max-polls', '1', '--out', str(case / 'capture')])
    process = None
    timed_out = False
    result = None
    start = time.monotonic()
    peer.thread.start()
    try:
        with (case / 'stdout.txt').open('wb') as stdout, (case / 'stderr.txt').open('wb') as stderr:
            process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr,
                                       start_new_session=True, cwd=case)
            try:
                process.wait(timeout=PROCESS_DEADLINE)
            except subprocess.TimeoutExpired:
                timed_out = True
            finally:
                stop_child(process)
        # The peer waits at most FOLLOWUP_DEADLINE after the terminal error.
        peer.thread.join(PEER_DEADLINE + 1)
    finally:
        stop_child(process)
        peer.close()
        stdout_text = (case / 'stdout.txt').read_text(encoding='utf-8', errors='replace')
        stderr_text = (case / 'stderr.txt').read_text(encoding='utf-8', errors='replace')
        result = {'name': name, 'mode': mode, 'command': command,
                  'exit_code': None if process is None else process.returncode,
                  'timed_out': timed_out, 'elapsed_seconds': round(time.monotonic() - start, 6),
                  'peer_error': peer.error, 'requests': peer.requests, 'peer_events': peer.events,
                  'stdout': stdout_text, 'stderr': stderr_text,
                  'child_reaped': process is not None and process.poll() is not None,
                  'peer_thread_stopped': not peer.thread.is_alive(),
                  'capture_published': (case / 'capture').exists()}
        if mode == 'valid-lf':
            result['control_passed'] = (not timed_out and peer.error is None and result['exit_code'] == 0
                                        and stdout_text == 'VALID\n' and len(peer.requests) == 1)
        elif mode == 'valid-eof':
            result['finding_reproduced'] = (not timed_out and peer.error is None and result['exit_code'] == 0
                                            and stdout_text == 'VALID\n' and len(peer.requests) == 1)
            result['required_behavior'] = 'Reject the nonempty EOF frame lacking LF; no VALID success.'
        else:
            result['finding_reproduced'] = (not timed_out and peer.error is None and result['exit_code'] == 2
                                            and TERMINAL_ERROR in stderr_text and len(peer.requests) == 3
                                            and peer.requests[-1]['json'] == {'proto_step': 'cancel_job', 'jobId': JOB_ID})
            result['required_behavior'] = 'Return the original terminal protocol error without sending cancel_job.'
        save_json(case / 'result.json', result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mirror', type=Path, required=True, help='Existing remote mirror binary; never built by this script')
    parser.add_argument('--source-root', type=Path, required=True, help='Corresponding remote source tree for relevant-file parity')
    parser.add_argument('--work-root', type=Path, required=True, help='Existing task-owned remote scratch parent; contents retained')
    args = parser.parse_args()
    release = Path('/proc/sys/kernel/osrelease').read_text().strip()
    if 'microsoft' not in release.lower() and 'wsl' not in release.lower():
        parser.error('This probe is reserved for the approved remote WSL environment.')
    binary = args.mirror.resolve(strict=True)
    source_root = args.source_root.resolve(strict=True)
    scratch = args.work_root.resolve(strict=True)
    if not binary.is_file() or not os.access(binary, os.X_OK):
        parser.error('--mirror must be an existing executable file')
    if not scratch.is_dir():
        parser.error('--work-root must already be an owned directory')
    root = Path(tempfile.mkdtemp(prefix='client-cli-probe-', dir=scratch))
    references = json.loads(Path(__file__).with_name('source-reference.json').read_text())
    parity = []
    for entry in references['files']:
        path = source_root / entry['path']
        observed = sha256(path) if path.is_file() else None
        parity.append({**entry, 'observed_sha256': observed, 'matches': observed == entry['sha256']})
    metadata = {'started_utc': datetime.now(timezone.utc).isoformat(), 'host': platform.node(),
                'kernel_release': release, 'python': platform.python_version(), 'binary': str(binary),
                'binary_sha256': sha256(binary), 'source_root': str(source_root),
                'source_reference': references, 'source_parity': parity,
                'work_root': str(root), 'probe_sha256': sha256(Path(__file__)),
                'no_builds_or_model_operations': True}
    save_json(root / 'metadata.json', metadata)
    if not all(entry['matches'] for entry in parity):
        save_json(root / 'summary.json', {'status': 'not-run-source-mismatch', 'metadata': metadata})
        print(root)
        return 2
    version = subprocess.run([str(binary), '--version'], stdin=subprocess.DEVNULL,
                             capture_output=True, text=True, timeout=5, cwd=root)
    metadata['binary_version'] = {'exit_code': version.returncode, 'stdout': version.stdout, 'stderr': version.stderr}
    save_json(root / 'metadata.json', metadata)
    cases = [run_case(binary, root, 'valid-lf-control', 'valid-lf'),
             run_case(binary, root, 'missing-lf-eof', 'valid-eof'),
             run_case(binary, root, 'terminal-protocol-error-cancel', 'terminal-cancel')]
    summary = {'status': 'completed', 'metadata': metadata, 'cases': cases,
               'valid_lf_control_passed': cases[0]['control_passed'],
               'missing_lf_finding_reproduced': cases[1]['finding_reproduced'],
               'post_terminal_cancel_finding_reproduced': cases[2]['finding_reproduced'],
               'all_owned_processes_reaped': all(c['child_reaped'] and c['peer_thread_stopped'] for c in cases)}
    save_json(root / 'summary.json', summary)
    print(json.dumps({'work_root': str(root), **{k: v for k, v in summary.items() if isinstance(v, bool)}}, sort_keys=True))
    # Exit describes probe completion/control health, not whether defects remain.
    return 0 if summary['valid_lf_control_passed'] and summary['all_owned_processes_reaped'] and not any(c['peer_error'] or c['timed_out'] for c in cases) else 1


if __name__ == '__main__':
    raise SystemExit(main())
