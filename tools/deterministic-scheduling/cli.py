#!/usr/bin/env python3
"""Installed DPM orchestration; the Lean launcher owns pure policy admission."""
import sys
if __name__ == '__main__' and not (sys.flags.isolated and sys.flags.no_site and sys.dont_write_bytecode):
    print('DPM Python entrypoint requires python3 -I -S -B', file=sys.stderr)
    raise SystemExit(2)

import argparse
import hashlib
import types
import ctypes
import os
import signal
import json
from pathlib import Path
import subprocess
import time
# The trusted Lean launcher supplies these pins before any caller arguments.
if len(sys.argv) < 3 or sys.argv[1] != '--host-identities':
    raise SystemExit('DPM host requires launcher-selected identities')
HOST_IDENTITIES = json.loads(sys.argv[2])
del sys.argv[1:3]
if len(sys.argv) < 3 or sys.argv[1] != '--policy':
    raise SystemExit('DPM host requires launcher-selected policy')
SELECTED_POLICY = Path(sys.argv[2])
del sys.argv[1:3]
source = Path(__file__).with_name('dpm_host.py')
raw = source.read_bytes()
if len(raw) > 1048576 or hashlib.sha256(raw).hexdigest() != HOST_IDENTITIES.get(source.name):
    raise SystemExit('DPM host helper differs from launcher selection')
host = types.ModuleType('dpm_host')
host.__file__ = str(source)
sys.modules[host.__name__] = host
exec(compile(raw, str(source), 'exec'), host.__dict__)
Project, Refusal, reduce, strict, write, validate_exploration, sha = (
    getattr(host, name) for name in
    ['Project', 'Refusal', 'reduce', 'strict', 'write', 'validate_exploration', 'sha'])


ACTIVE_PROJECT = None


def controlled_model():
    source = Path(__file__).with_name('controlled_model.py')
    raw = source.read_bytes()
    if len(raw) > 1048576 or hashlib.sha256(raw).hexdigest() != HOST_IDENTITIES.get(source.name):
        raise Refusal('controlled model helper differs from launcher selection')
    module = types.ModuleType('controlled_model')
    module.__file__ = str(source)
    exec(compile(raw, str(source), 'exec'), module.__dict__)
    return module

def main():
    global ACTIVE_PROJECT
    def cancelled(_signal, _frame): host.cancel_operation(_signal, _frame)
    signal.signal(signal.SIGTERM, cancelled)
    signal.signal(signal.SIGINT, cancelled)
    # The runner owner must clean up if its Lean launcher is terminated.
    parent = os.getppid()
    libc = ctypes.CDLL(None, use_errno=True)
    if hasattr(libc, 'prctl'):
        if libc.prctl(1, signal.SIGTERM, 0, 0, 0) != 0: raise Refusal('parent-death notification unavailable')
        if os.getppid() != parent: raise Refusal('launcher exited during startup')
    parser = argparse.ArgumentParser(prog='mirrors-dpm')
    sub = parser.add_subparsers(dest='operation', required=True)
    for operation in ['doctor', 'replay', 'explore', 'reduce']:
        command = sub.add_parser(operation)
        command.add_argument('--project', type=Path, required=True)
        command.add_argument('--project-sha256', required=True)
        if operation != 'doctor': command.add_argument('--out', type=Path, required=True)
        if operation == 'replay': command.add_argument('--candidate')
        if operation == 'explore': command.add_argument('--space', choices=['catalog', 'sdk'], default='catalog')
    report = sub.add_parser('report')
    report.add_argument('--receipt', type=Path, required=True)
    report.add_argument('--format', choices=['text', 'json'], default='text')
    report.add_argument('--expected-sha256', required=True)
    compare = sub.add_parser('compare-sync')
    for name in ['receipt', 'mapping', 'mirror', 'remote']:
        compare.add_argument('--' + name, type=Path, required=True)
        compare.add_argument('--' + name + '-sha256', required=True)
    compare.add_argument('--model', type=Path, required=True)
    compare.add_argument('--implementation', type=Path, required=True)
    compare.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    if args.operation == 'compare-sync':
        result, code = controlled_model().compare(args, SELECTED_POLICY, host)
        print(json.dumps(result, sort_keys=True))
        return code
    if args.operation == 'report':
        if sha(args.receipt) != args.expected_sha256: raise Refusal('receipt digest differs')
        receipt = strict(args.receipt)
        if receipt.get('schema') == 'mirrors.controlled-sync-model-comparison/v1':
            controlled_model().validate_result(receipt)
            for name, digest in receipt['artifacts'].items():
                artifact = host.regular(args.receipt.parent / name)
                if sha(artifact) != digest: raise Refusal('controlled comparison artifact differs')
            print(json.dumps(receipt, sort_keys=True) if args.format == 'json' else
                  receipt['comparison'] + ': finite controlled mutex/FIFO model; cleanup=' + receipt['cleanup'])
            return 0
        if receipt.get('schema') in ['mirrors.dpm-reduction/v1', 'mirrors.dpm-exploration/v1', 'mirrors.controlled-sync-replay/v1', 'mirrors.controlled-sync-exploration/v1']:
            if receipt.get('schema') == 'mirrors.dpm-reduction/v1':
                if receipt.get('claim') not in ['best_observed','minimal_in_admitted_catalog'] or receipt.get('scope') != 'admitted-catalog-only': raise Refusal('unknown reduction claim')
                if receipt.get('claim') == 'minimal_in_admitted_catalog' and (receipt.get('status') != 'completed' or receipt.get('failure') is not None or receipt.get('bestReplay') != 'confirmed'): raise Refusal('contradictory minimality claim')
                if not isinstance(receipt.get('trials'), list) or len(receipt['trials']) > 4096: raise Refusal('invalid reduction evidence bound')
            if receipt.get('schema', '').startswith('mirrors.controlled-sync') and receipt.get('modelComparison') is not False: raise Refusal('controlled-resource report cannot imply model comparison')
            if receipt.get('schema', '').startswith('mirrors.controlled-sync') and 'budgetExceeded' in receipt:
                flags = receipt['budgetExceeded']
                expected = {'execution', 'cleanup'} if receipt['schema'] == 'mirrors.controlled-sync-replay/v1' else {'total'}
                if not isinstance(flags, dict) or set(flags) != expected or any(type(value) is not bool for value in flags.values()): raise Refusal('malformed synchronization budget facts')
            if receipt.get('schema') == 'mirrors.controlled-sync-replay/v1':
                if receipt.get('profile') != 'mirrorcpp.controlled-sync-experimental/v1': raise Refusal('unknown synchronization profile')
                if receipt.get('passed') is True and (receipt.get('outcome') != 'completed' or receipt.get('finished') is not True or receipt.get('cleanup') != 'confirmed' or any(receipt.get('budgetExceeded', {}).values())): raise Refusal('contradictory synchronization verdict')
            if receipt.get('schema') == 'mirrors.controlled-sync-exploration/v1' and receipt.get('complete') is True and (any(receipt.get('budgetExceeded', {}).values()) or receipt.get('evidenceComplete') is False or receipt.get('stopReason')): raise Refusal('contradictory synchronization exploration verdict')
            print(json.dumps(receipt, sort_keys=True) if args.format == 'json' else '\n'.join(str(k)+': '+json.dumps(v, sort_keys=True) for k,v in receipt.items() if k not in ['rows','trials','events','observations']))
            return 0
        return subprocess.run([sys.executable, '-I', '-S', '-B', str(Path(__file__).with_name('timeline.py')),
            '--receipt', str(args.receipt), '--format', args.format,
            '--expected-sha256', args.expected_sha256], check=False).returncode
    project = Project(args.project, args.project_sha256, SELECTED_POLICY)
    if args.operation == 'doctor':
        for candidate in project.candidates.values(): project.oracle(candidate)
        project.check()
        print(json.dumps({'schema': 'mirrors.dpm-doctor/v1', 'status': 'accepted',
            'profile': project.data['profile'], 'candidateCount': len(project.candidates),
            'projectSha256': project.digest, 'scope': 'admitted-catalog-only'}))
        return 0
    output = args.out.absolute()
    output.mkdir(parents=True, exist_ok=False)
    project.begin(output)
    ACTIVE_PROJECT = project
    if args.operation == 'reduce': result, code = reduce(project, output)
    elif args.operation == 'replay':
        candidate = args.candidate or project.data['baseline']
        if candidate not in project.candidates: raise Refusal('unknown candidate')
        verdict, signature, receipt = project.replay(candidate, output / 'execution',
            time.monotonic() + project.data['limits']['totalTimeoutMs']/1000)
        result = {'schema': 'mirrors.dpm-operation/v1', 'operation': 'replay',
            'comparison': verdict, 'signature': signature, 'cleanup': 'confirmed',
            'projectSha256': project.digest, 'candidateId': candidate}
        project.write(output / 'receipt.json', receipt)
        code = 0 if verdict == 'matched' else 1
    elif args.operation == 'explore' and args.space == 'sdk':
        if project.data['explorerIdentity'] is None: raise Refusal('project has no selected SDK explorer identity')
        deadline = time.monotonic() + project.data['limits']['totalTimeoutMs']/1000
        receipt = project.request('explore', project.data['baseline'], output / 'sdk', deadline)
        validate_exploration(receipt, lambda pairs: project.values(pairs, deadline), project.seen,
            project.data['profile'], project.data['explorerIdentity'])
        project.write(output / 'receipt.json', receipt)
        result = {'schema':'mirrors.dpm-exploration/v1','scope':'sdk-finite-actor-chain-merges', 'complete':receipt['complete'],
                  'modelComparison':False,'executed':receipt['attemptedRuns'],'total':receipt['eligibleRuns'],'projectSha256':project.digest}
        code = 0 if receipt['complete'] else 2
    else:
        deadline = time.monotonic() + project.data['limits']['totalTimeoutMs']/1000
        rows = []
        complete = True
        for row in project.plan['order']:
            if (len(rows) >= project.data['limits']['attempts'] or time.monotonic() >= deadline or
                    project.budget.available() < 3 * project.data['limits']['outputBytes']):
                complete = False; break
            verdict, _, _ = project.replay(row['id'], output / ('candidate-' + str(len(rows))), deadline)
            rows.append({'candidateId': row['id'], 'comparison': verdict, 'cleanup': 'confirmed'})
        result = {'schema': 'mirrors.dpm-exploration/v1', 'scope': 'admitted-catalog-only',
            'complete': complete, 'total': len(project.candidates), 'executed': len(rows),
            'modelComparison': 'actual-supplied-trace', 'rows': rows, 'projectSha256': project.digest}
        code = 0 if complete and all(r['comparison'] == 'matched' for r in rows) else 1 if complete else 2
    project.check()
    project.budget.audit(final=True)
    project.write(output / 'result.json', result, final=True)
    print(json.dumps(result, sort_keys=True))
    return code


if __name__ == '__main__':
    try: raise SystemExit(main())
    except (Refusal, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        if ACTIVE_PROJECT is not None: ACTIVE_PROJECT.record_failure(error)
        print('DPM operation refused: ' + str(error), file=sys.stderr)
        raise SystemExit(2)
