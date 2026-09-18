#!/usr/bin/env python3
"""Linux live mTLS async soak. Requires real Apalache; never silently skips.

RSS is a bounded-growth regression signal, not a heap-leak proof. Checks exact
job eviction, descriptor recovery, child exit, and owned temporary cleanup.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import ssl
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def require(condition, detail):
    if not condition:
        raise AssertionError(detail)


class Client:
    def __init__(self, context, port):
        self.sock = context.wrap_socket(socket.create_connection(('127.0.0.1', port), timeout=5), server_hostname='localhost')
        self.sock.settimeout(40)
        self.stream = self.sock.makefile('rb')

    def call(self, message):
        self.sock.sendall((json.dumps(message) + '\n').encode())
        line = self.stream.readline(65537)
        require(line.endswith(b'\n') and len(line) <= 65536, line[:200])
        return json.loads(line)

    def close(self):
        self.stream.close()
        self.sock.close()


def snapshot(pid):
    proc = Path('/proc') / str(pid)
    status = dict(line.split(':', 1) for line in (proc / 'status').read_text().splitlines())
    children = set()
    for task in (proc / 'task').iterdir():
        try:
            children.update((task / 'children').read_text().split())
        except FileNotFoundError:
            pass
    return {'rssKiB': int(status['VmRSS'].split()[0]),
            'fds': len(list((proc / 'fd').iterdir())), 'children': sorted(children)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--batches', type=int, default=6)
    parser.add_argument('--concurrency', type=int, default=3)
    parser.add_argument('--rss-budget-mib', type=int, default=16)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    require(args.batches >= 3 and args.concurrency >= 2 and args.rss_budget_mib >= 0, 'need >=3 batches, >=2 concurrent jobs, nonnegative RSS budget')
    apalache = os.environ.get('APALACHE_MC', str(Path.home() / '.local/bin/apalache/bin/apalache-mc'))
    require(Path(apalache).is_file(), 'APALACHE_MC must point to real apalache-mc')
    require(Path('/proc/self/status').exists(), 'Linux /proc required')
    evidence = {'transport': 'mTLS', 'backend': apalache, 'concurrency': args.concurrency,
                'rssBudgetMiB': args.rss_budget_mib, 'samples': [], 'passed': False,
                'binarySha256': hashlib.sha256((ROOT / '.lake/build/bin/mirror').read_bytes()).hexdigest()}
    with tempfile.TemporaryDirectory(prefix='mirrors-async-soak-') as directory:
        root = Path(directory)
        scratch = root / 'scratch'
        scratch.mkdir()
        cert, key = root / 'cert.pem', root / 'key.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                        '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost',
                        '-keyout', str(key), '-out', str(cert)], check=True, capture_output=True)
        context = ssl.create_default_context(cafile=str(cert))
        context.minimum_version = ssl.TLSVersion.TLSv1_3
        context.load_cert_chain(cert, key)
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', 0))
            port = probe.getsockname()[1]
        with (root / 'server.log').open('w+') as log:
            server = subprocess.Popen([str(ROOT / '.lake/build/bin/mirror'), '--server', str(port), '--tls',
                                       '--jobs', str(args.concurrency + 1), '--cert', str(cert), '--key', str(key),
                                       '--ca', str(cert)], cwd=ROOT, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                      env={**os.environ, 'APALACHE_MC': apalache, 'TMPDIR': str(scratch)}, start_new_session=True)
            observer = None
            clients = []
            try:
                deadline = time.monotonic() + 15
                while observer is None:
                    require(server.poll() is None, 'server exited during startup')
                    try:
                        observer = Client(context, port)
                    except OSError:
                        if time.monotonic() >= deadline:
                            raise
                        time.sleep(.1)
                request = {'proto_step': 'register_validate_async', 'bound': 3,
                           'apalacheConfig': {'constInit': None, 'initPredicate': 'Init', 'invariant': 'Safe',
                                              'lengthBound': 3, 'nextPredicate': 'Next', 'paramVars': '', 'specPath': 'Main.tla'},
                           'spec': {'sources': ['---- MODULE Main ----\nEXTENDS Naturals\nVARIABLE\n  \\* @type: Int;\n  x\nInit == x = 0\nNext == x\' = x + 1\nSafe == x >= 0\n====\n']}}
                for batch in range(args.batches + 2):
                    mode = 'complete' if batch < 2 else ['complete', 'cancel', 'disconnect'][(batch - 2) % 3]
                    for _ in range(args.concurrency):
                        clients.append(Client(context, port))
                    ids = []
                    for client in clients:
                        reply = client.call(request)
                        require(reply.get('proto_step') == 'job_accepted', reply)
                        ids.append(reply['jobId'])
                    require(len(set(ids)) == len(ids), ids)
                    # Observe real overlapping backend processes, not just accepted metadata.
                    deadline = time.monotonic() + 15
                    peak = 0
                    while time.monotonic() < deadline:
                        peak = max(peak, len(snapshot(server.pid)['children']))
                        if peak >= args.concurrency:
                            break
                        time.sleep(.02)
                    require(peak >= args.concurrency, f'backend concurrency not observed: {peak}')
                    if mode == 'complete':
                        for client, jid in zip(clients, ids):
                            deadline = time.monotonic() + 120
                            while True:
                                reply = client.call({'proto_step': 'await_job', 'jobId': jid, 'timeoutSecs': 30})
                                require(reply.get('jobId') == jid, reply)
                                if reply.get('proto_step') == 'job_result':
                                    require(reply['outcome'] == {'validate': 'valid'}, reply)
                                    break
                                require(reply.get('phase') in ('pending', 'running') and time.monotonic() < deadline, reply)
                    elif mode == 'cancel':
                        for client, jid in zip(clients, ids):
                            reply = client.call({'proto_step': 'cancel_job', 'jobId': jid})
                            require(reply.get('phase') == 'cancelled', reply)
                    for client in clients:
                        client.close()
                    clients = []
                    deadline = time.monotonic() + 30
                    while True:
                        sample = snapshot(server.pid)
                        evicted = all(observer.call({'proto_step': 'query_job', 'jobId': jid}).get('phase') == 'unknown' for jid in ids)
                        temporary = list(scratch.glob('modelmirrors-*'))
                        if evicted and not sample['children'] and not temporary:
                            break
                        require(time.monotonic() < deadline, {'sample': sample, 'evicted': evicted, 'temporary': [str(p) for p in temporary]})
                        time.sleep(.1)
                    sample.update(batch=batch, mode=mode, peakChildren=peak)
                    evidence['samples'].append(sample)
                    if batch == 1:
                        baseline = sample
                    elif batch > 1:
                        require(sample['fds'] <= baseline['fds'], ('descriptor growth', baseline, sample))
                        require(sample['rssKiB'] <= baseline['rssKiB'] + args.rss_budget_mib * 1024, ('RSS growth', baseline, sample))
                    print(json.dumps(sample), flush=True)
                evidence['passed'] = True
            finally:
                for client in clients:
                    client.close()
                if observer:
                    observer.close()
                try:
                    os.killpg(server.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    server.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(server.pid, signal.SIGKILL)
                    server.wait()
                log.seek(0)
                evidence['serverLogTail'] = log.read()[-8000:]
                args.evidence.write_text(json.dumps(evidence, indent=2) + '\n')
    print('ASYNC SERVER RESOURCE E2E GREEN')


if __name__ == '__main__':
    main()
