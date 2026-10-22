#!/usr/bin/env python3
"""Supplied-trace Gate/C++/Rust composition against the exact 0.1 server."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
from check import source_snapshot


def digest(path: Path) -> str:
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    work = args.work.resolve()
    gate = work / 'MirrorGate'
    mirror = work / 'Mirrors-baseline/.lake/build/bin/mirror'
    worker = gate / 'runtimes/rust/target/debug/mirrorgate-counter-worker'
    drivers = {
        'MirrorCPP': work / 'gate-cpp-integration/mirrorgate_mirrorcpp_counter',
        'MirrorRust': gate / 'integrations/mirrorrust/target/debug/mirrorgate-mirrorrust-counter',
    }
    env = {**os.environ, 'APALACHE_MC': str(work / 'forbidden-apalache'),
           'MIRRORGATE_REQUIRE_SANDBOX': '1',
           'MIRRORGATE_NODE_RUNTIME_ROOT': str(work / 'toolchains/node-v24.15.0-linux-x64')}
    for name in ('APALACHE_JAR', 'TLA2TOOLS_JAR'):
        env.pop(name, None)
    identities = {name: source_snapshot(work / name) for name in ('MirrorGate', 'MirrorCPP', 'MirrorRust')}
    rows = []
    with tempfile.TemporaryDirectory(prefix='mirrors-v01-gate-') as temporary:
        scratch = Path(temporary)
        submissions = scratch / 'submissions'
        for variant in ('correct', 'faulty', 'rust'):
            (submissions / variant).mkdir(parents=True)
        shutil.copyfile(gate / 'runtimes/node/examples/counter.mjs', submissions / 'correct/adapter.mjs')
        shutil.copyfile(gate / 'runtimes/node/examples/faulty-counter.mjs', submissions / 'faulty/adapter.mjs')
        shutil.copyfile(gate / 'runtimes/node/examples/counter.mjs', submissions / 'faulty/counter.mjs')
        shutil.copy2(worker, submissions / 'rust/worker')
        for evaluator, driver in drivers.items():
            for mode in ('owned', 'attached'):
                for runtime in ('node-v1', 'rust-v1'):
                    for case in ('correct', 'faulty', 'wrong-digest'):
                        name = f'{evaluator}-{mode}-{runtime}-{case}'
                        policy = scratch / f'{name}.json'
                        policy_id = 'compat.' + name.lower()
                        profile = 'mirrorcpp-v1' if evaluator == 'MirrorCPP' else 'mirrorrust-counter-fixture-v1'
                        argv = ['python3', str(gate / 'tests/control_policy_fixture.py'), str(policy), str(submissions),
                                '--policy-id', policy_id, '--adapter-id', 'mirrorgate/' + runtime,
                                '--target-profile', profile, '--state-computer-contract-version', 'mirrors.state-computer/v1']
                        if runtime == 'node-v1':
                            relative = 'faulty' if case == 'faulty' else 'correct'
                            argv += ['--runtime', 'node', '--artifact-entry', 'adapter.mjs']
                        else:
                            relative = 'rust'
                            argv += ['--runtime', 'rust', '--artifact-entry', 'worker']
                            if case == 'faulty':
                                argv += ['--faulty']
                        subprocess.run(argv, env=env, check=True, capture_output=True, timeout=30)
                        endpoint = gate / 'bin/mirrorgate'
                        daemon = None
                        daemon_log = None
                        if mode == 'attached':
                            socket_dir = scratch / name
                            socket_dir.mkdir(mode=0o700)
                            endpoint = socket_dir / 'c.sock'
                            daemon_log = (work / 'logs' / f'gate-{name}-controller.log').open('w')
                            daemon = subprocess.Popen([str(gate / 'bin/mirrorgate'), 'control', '--unix-socket', str(endpoint),
                                                       '--policy-file', str(policy)], env=env, stdout=daemon_log, stderr=subprocess.STDOUT)
                            for _ in range(200):
                                if endpoint.is_socket():
                                    break
                                if daemon.poll() is not None:
                                    raise RuntimeError('attached controller exited before creating its socket')
                                time.sleep(.025)
                            else:
                                daemon.terminate()
                                raise RuntimeError('attached controller did not create its socket')
                        try:
                            argv = [str(driver), mode, str(endpoint), str(policy), policy_id,
                                    str(gate / 'conformance/manifests/counter.json'), relative, runtime,
                                    str(mirror), str(work / 'Mirrors-baseline/specs/Counter.tla'),
                                    str(gate / 'conformance/control-v1/counter.itf.json'), case]
                            result = subprocess.run(argv, cwd=gate, env=env, capture_output=True, text=True, timeout=60)
                            log = work / 'logs' / f'gate-{name}.log'
                            log.write_text(result.stdout + result.stderr)
                            if result.returncode:
                                raise RuntimeError(f'{name} failed with exit {result.returncode}; inspect {log}')
                            row = json.loads(result.stdout)
                            expected = {'correct': 'passed', 'faulty': 'mismatch', 'wrong-digest': 'negotiation-rejected'}[case]
                            if row['resultStatus'] != expected or row['cleanup'] != 'succeeded' or row['controlShutdown'] != 'confirmed':
                                raise RuntimeError(f'unexpected outcome or unconfirmed cleanup: {row}')
                            if case == 'wrong-digest' and (row['bindingFactoryCalls'] or row['workerAcquisitions']):
                                raise RuntimeError('failed negotiation acquired a binding or worker')
                            rows.append({'evaluator': evaluator, **row, 'logSha256': digest(log)})
                            print(name, 'passed', flush=True)
                        finally:
                            if daemon:
                                daemon.terminate()
                                try:
                                    daemon.wait(timeout=10)
                                except subprocess.TimeoutExpired:
                                    daemon.kill()
                                    daemon.wait(timeout=5)
                                daemon_log.close()
    if (work / 'unexpected-model-invocation').exists():
        raise RuntimeError('a supplied-trace composition invoked a local model checker')
    if any(source_snapshot(work / name) != identity for name, identity in identities.items()):
        raise RuntimeError('a Gate or evaluator source input changed during the matrix')
    receipt = {'schema': 'mirrors.v01-gate-composition/v1',
               'serverCommit': 'ea8091c0c723f3f561044a5c1efb91d12e7aaf5f', 'serverSha256': digest(mirror),
               'liveModelChecking': False, 'scope': 'actual C++/Rust evaluators, owned/attached Gate, Node/Rust workers, supplied-trace match/mismatch and wrong-digest zero-acquisition',
               'drivers': {name: digest(path) for name, path in drivers.items()},
               'sourceInputs': identities, 'rows': rows}
    (work / 'gate-composition.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('All 24 Gate/C++/Rust supplied-trace composition rows passed')


if __name__ == '__main__':
    main()
