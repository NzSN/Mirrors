#!/usr/bin/env python3
"""Compare fresh native processes against independently captured model traces."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shlex
import subprocess


def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def require(test, why):
    if not test: raise RuntimeError(why)
def normalize(value):
    if isinstance(value, dict):
        if set(value) == {'#bigint'}: return int(value['#bigint'])
        return {k: normalize(v) for k, v in value.items() if k != 'nativeIdentity'}
    if isinstance(value, list): return [normalize(v) for v in value]
    return value


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--runner', type=Path, required=True)
    p.add_argument('--mirror', type=Path, required=True)
    p.add_argument('--prepared', type=Path, required=True)
    p.add_argument('--oracles', type=Path, required=True)
    p.add_argument('--worker-root', type=Path, required=True)
    p.add_argument('--generated', type=Path, required=True)
    p.add_argument('--case', choices=['stable-t1','stable-t2','overlap-t1','overlap-t2'])
    p.add_argument('--out', type=Path, required=True)
    args = p.parse_args(); args.out.mkdir(parents=True, exist_ok=False)
    digest = re.search(r'WriteSentryMBTSemanticDigest = "([0-9a-f]{64})"', args.generated.read_text()).group(1)
    baseline, identities, rows = {}, set(), []
    runs = [(name, 'normal-v3', 'ok') for name in ['stable-t1', 'stable-t2', 'overlap-t1', 'overlap-t2'] for _ in range(2)]
    runs += [('stable-t1', name, 'ok') for name in ['duplicate-sink-call', 'skip-hit-release']]
    runs += [('stable-t1', 'normal-v3', mode) for mode in ['cancel', 'wrong-image', 'crash-peer', 'unexpected-phase']]
    if args.case: runs = [r for r in runs if r[0] == args.case]
    before = {str(x): sha(x) for x in [args.runner, args.mirror, args.generated]}
    for index, (name, build, mode) in enumerate(runs):
        label = f'{index:02d}-{name}-{build}-{mode}'; directory = args.out / label; directory.mkdir()
        model_dir = args.prepared / name; mapping_path = model_dir / 'mapping.json'
        mapping = json.loads(mapping_path.read_text()); trace = args.oracles / name / 'trace-0.itf.json'
        states = json.loads(trace.read_text())['states']
        require(len(states) == len(mapping['modelSteps']) + 1, 'fresh oracle ended before all mapped phases')
        require([normalize(s['parameters']) for s in states[1:]] == [s['parameters'] for s in mapping['modelSteps']], 'oracle schedule differs')
        if mode == 'unexpected-phase':
            # Negative control only: demand ArmSelect when the real worker is
            # about to report ArmLock. Never count this modified trace as an oracle.
            require(mapping['modelSteps'][1]['parameters']['action'] == 'ArmLock', 'phase control fixture changed')
            mapping['modelSteps'][1]['parameters']['action'] = 'ArmSelect'
            mapping_path = directory/'negative-mapping.json'; mapping_path.write_text(json.dumps(mapping, indent=2)+'\n')
            negative = json.loads(trace.read_text())
            negative['states'][2]['action_taken'] = 'ArmSelect'
            negative['states'][2]['parameters']['action'] = 'ArmSelect'
            trace = directory/'negative-trace.itf.json'; trace.write_text(json.dumps(negative, indent=2)+'\n')
        worker = args.worker_root / build / 'build/dpm_native_worker.exe'
        build_receipt = json.loads((args.worker_root / build / 'build-receipt.json').read_text(encoding='utf-8-sig'))
        require(sha(worker) == build_receipt['executableSha256'], 'native image differs from build receipt')
        launcher = directory / 'launch'; launcher.write_text('#!/bin/sh\ncd ' + shlex.quote(str(worker.resolve().parent)) + ' || exit 98\nexec ' + shlex.quote(str(worker.resolve())) + '\n'); launcher.chmod(0o700)
        if mode == 'crash-peer':
            helper = Path(__file__).with_name('terminate_peer.py').resolve()
            launcher.write_text('#!/bin/sh\ncd ' + shlex.quote(str(worker.resolve().parent)) + ' || exit 98\nexec /usr/bin/python3 ' + shlex.quote(str(helper)) + ' ' +
                                shlex.quote(str(worker.resolve())) + ' ' + shlex.quote(str((directory/'terminated.json').resolve())) + '\n')
        implementation = hashlib.sha256(('mirrors.dpm-native-implementation/v1\n' + sha(args.runner) + '\n' + sha(worker) + '\n' + sha(launcher) + '\n').encode()).hexdigest()
        steps = []
        for s in mapping['modelSteps']:
            steps.append({'actor': s['role'], 'checkpoint': s['parameters']['action']})
            if s['parameters']['action'] == 'CallDone': steps.append({'actor': s['role'], 'checkpoint': '$done'})
        schedule = {'schema': 'mirrors.checkpoint-schedule/v1', 'profile': 'mirrorcpp.cooperative-checkpoints/v1',
                    'identity': {'modelSemanticDigest': digest, 'mappingSha256': sha(mapping_path), 'implementationSha256': implementation},
                    'inputs': {}, 'steps': steps}
        schedule_path = directory / 'schedule.json'; schedule_path.write_text(json.dumps(schedule, indent=2) + '\n')
        report = directory / 'receipt.json'
        command = [str(args.runner.resolve()), '--mirror', str(args.mirror.resolve()), '--model', str((model_dir/'WriteSentryMBT.tla').resolve()),
                   '--trace', str(trace.resolve()), '--mapping', str(mapping_path.resolve()), '--schedule', str(schedule_path.resolve()),
                   '--launcher', str(launcher.resolve()), '--worker', str(worker.resolve()), '--out', str(report.resolve()), '--mode', 'ok' if mode in ['crash-peer', 'unexpected-phase'] else mode]
        with (directory/'run.log').open('w') as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        require(result.returncode == 0, label + ': runner failed')
        receipt = json.loads(report.read_text()); native = receipt['native']; binding = receipt['binding']
        require(native['acquisitions'] == native['cleanups'] == 1 and native['closed'] is True, label + ': ownership count differs')
        require(binding['disposed'] is True and binding['disposals'] == 1, label + ': binding not disposed once')
        if mode != 'wrong-image':
            identity = native['identity']; require(isinstance(identity, dict), label + ': native identity unavailable; inspect run.log')
            unique = (identity['processId'], identity['createdFileTime'])
            require(unique not in identities and identity['actors']['t1'] != identity['actors']['t2'], 'native process/actor identity reused')
            identities.add(unique)
            require(identity['imageSha256'] == sha(worker), 'running image differs')
        if mode == 'ok' and build == 'normal-v3':
            require(receipt['passed'] is True and receipt['comparison'] == 'matched', label + ': comparison not matched')
            require(native['quitAcknowledged'] is True and native['exitCode'] == 0, 'native cleanup not confirmed')
            require(len(binding['executions']) == 1 and binding['executions'][0]['scheduleCompleted'] is True, 'schedule incomplete')
            actual = normalize(native['transcript'])
            if name in baseline: require(actual == baseline[name], 'fresh-process replay changed normalized observations')
            else: baseline[name] = actual
        elif build != 'normal-v3':
            require(receipt['passed'] is False and receipt['comparison'] == 'step_mismatch', label + ': production mutation not detected by real comparer')
            require(receipt['client'].get('expected') != receipt['client'].get('actual') and receipt['client']['orderedHints'], 'mutation lacks state difference evidence')
        elif mode == 'unexpected-phase':
            require(receipt['passed'] is False and receipt['comparison'] == 'incomplete', 'native phase mismatch accepted')
            require(binding['executions'][0]['outcome'] == 'unexpected_checkpoint', 'actual native phase mismatch misclassified')
            require(native['quitAcknowledged'] is True and native['exitCode'] == 0, 'divergent native phase cleanup not confirmed')
        elif mode == 'crash-peer':
            require(receipt['passed'] is False and receipt['comparison'] == 'incomplete', 'terminated native peer accepted')
            require((directory/'terminated.json').is_file(), 'owned native termination not confirmed')
            require(native['exitCode'] == 41 and native['quitAcknowledged'] is False, 'termination hidden as clean exit')
            require(binding['executions'][0]['cleanup'] == 'teardown_failed', 'native failure cleanup hidden')
        elif mode == 'cancel':
            require(receipt['passed'] is False and receipt['comparison'] == 'incomplete', 'cancel accepted')
            require(binding['executions'][0]['outcome'] == 'cancelled', 'cancel misclassified')
            require(native['quitAcknowledged'] is True and native['exitCode'] == 0, 'paused native cancellation did not clean up')
        else:
            require(receipt['passed'] is False and receipt['comparison'] == 'incomplete', 'wrong native image accepted')
        rows.append({'case': label, 'status': 'passed', 'receipt': str(report.relative_to(args.out)), 'sha256': sha(report),
                     'workerSha256': sha(worker), 'mappingSha256': sha(mapping_path), 'traceSha256': sha(trace)})
        print(label + ': passed', flush=True)
    compatibility = []
    if args.case is None:
        source = args.prepared / 'stable-t1'
        for mode in ['unknown-profile', 'extra-operation', 'unknown-actor']:
            directory = args.out / mode; directory.mkdir()
            mapping = json.loads((source/'mapping.json').read_text())
            if mode == 'unknown-profile': mapping['profile'] = 'unsupported/v99'
            elif mode == 'unknown-actor': mapping['roles']['arm']['nativeActor'] = 't3'
            else: mapping['modelSteps'].append(mapping['modelSteps'][0])
            mapping_path = directory/'mapping.json'; mapping_path.write_text(json.dumps(mapping))
            sentinel = directory/'acquired'
            launcher = directory/'launch'
            launcher.write_text('#!/bin/sh\n: > ' + shlex.quote(str(sentinel.resolve())) + '\nexit 99\n'); launcher.chmod(0o700)
            report = directory/'receipt.json'
            command = [str(args.runner.resolve()), '--mirror', str(args.mirror.resolve()),
                '--model', str((source/'WriteSentryMBT.tla').resolve()), '--trace', str((args.oracles/'stable-t1/trace-0.itf.json').resolve()),
                '--mapping', str(mapping_path.resolve()), '--schedule', str((args.out/rows[0]['case']/'schedule.json').resolve()),
                '--launcher', str(launcher.resolve()), '--worker', str((args.worker_root/'normal-v3/build/dpm_native_worker.exe').resolve()),
                '--out', str(report.resolve())]
            result = subprocess.run(command, capture_output=True, text=True, timeout=20)
            (directory/'run.log').write_text(result.stdout + result.stderr)
            require(result.returncode == 2 and not sentinel.exists() and not report.exists(), mode + ': incompatible native input acquired worker')
            compatibility.append({'case': mode, 'status': 'passed', 'nativeAcquisitions': 0})
            print(mode + ': rejected before native acquisition', flush=True)
    require(before == {str(x): sha(x) for x in [args.runner, args.mirror, args.generated]}, 'controller/runtime/generated binding changed')
    (args.out/'acceptance.json').write_text(json.dumps({'schema': 'mirrors.dpm3-native-acceptance/v1', 'status': 'passed',
        'profile': 'dpm-writesentry-two-operation/v1', 'rows': rows, 'compatibilityControls': compatibility, 'inputHashes': before,
        'scope': 'four named schedules, two fresh-process replays each, two production mutants, actual phase divergence, cancellation, verified peer termination and native image refusal',
        'selectedCase': args.case, 'fullProductionQualified': False}, indent=2) + '\n')


if __name__ == '__main__': main()
