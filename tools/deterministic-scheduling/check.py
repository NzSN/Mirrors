#!/usr/bin/env python3
"""DPM-2 generated callback/replay acceptance. No local model checker is run."""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / 'test/fixtures/deterministic-scheduling'
SDK = ROOT.parent / 'MirrorCPP'


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def unique(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate JSON field')
        result[key] = value
    return result


def load(path):
    path = Path(path)
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 16 * 1024 * 1024,
            'expected bounded ordinary JSON file')
    return json.loads(path.read_text(), object_pairs_hook=unique)


def write(path, value):
    with path.open('x') as stream:
        stream.write(json.dumps(value, indent=2, sort_keys=True) + '\n')
    path.chmod(0o600)


def classify(row, mode, repeats=1):
    sut, binding = row['sut'], row['binding']
    executions = binding['executions']
    if mode == 'denied-negotiation':
        require(row['passed'] is False and row['comparison'] == 'incomplete', 'denial accepted')
        require(sut == {'acquisitions': 0, 'enteredWorkers': 0, 'teardowns': 0}, 'denial acquired SUT')
        require(binding['initializations'] == 0 and not executions, 'denial initialized session')
        return
    if mode == 'early-done':
        require(row['passed'] is False and not executions, 'empty replay earned credit')
        require(sut['acquisitions'] == 0, 'empty replay acquired SUT')
        return
    require(binding['disposals'] == 1 and binding['disposed'] is True and binding['receiptComplete'] is True,
            'binding ownership/disposal evidence differs')
    require(len(executions) == repeats, 'unexpected execution denominator')
    if mode == 'wrong-identity':
        require(sut['acquisitions'] == 0 and sut['enteredWorkers'] == 0 and sut['teardowns'] == 0,
                'incompatible mapping acquired SUT')
        require(executions[0]['outcome'] == 'incompatible_identity', 'missing identity rejection')
        return
    require(sut['acquisitions'] == repeats and sut['teardowns'] == repeats, 'SUT acquisition/teardown denominator differs')
    for execution in executions:
        require(execution['remainingActors'] == [], 'unjoined actor')
    if mode in ['malformed-input', 'reentrant']:
        require(row['firstError'] == ('input_shape_mismatch' if mode == 'malformed-input' else 'adapter_failure'),
                'wrong binding failure classification')
        require(row['secondError'] == 'binding_poisoned' and row['cleanupSucceeded'] is True, 'binding was not poisoned/disposed')
        require(not executions[0]['events'] and sut['enteredWorkers'] == 0, 'rejected callback released an actor')
        return
    if mode == 'ok':
        require(row['passed'] is True and row['comparison'] == 'matched', 'positive replay did not match')
        require(all(e['passed'] is True and e['scheduleCompleted'] is True and e['cleanup'] == 'confirmed' for e in executions),
                'incomplete positive schedule')
        require(sut['enteredWorkers'] == 2 * repeats, 'positive actor count differs')
    else:
        require(row['passed'] is False, 'negative run earned credit')
        if mode in ['mutate', 'mutate-and-teardown-fail', 'oracle-init-not-adopted']:
            require(row['comparison'] == 'step_mismatch' and row['client']['kind'] == 'step_mismatch',
                    'mutation did not produce a real comparison failure')
            require(row['client'].get('expected') != row['client'].get('actual') and row['client']['orderedHints'],
                    'comparison failure lacks actual state/hints')
        elif mode == 'teardown-fail':
            require(row['comparison'] == 'matched' and row['client'].get('code') == 'adapter_dispose_failed',
                    'teardown failure erased peer success or was ignored')
        else:
            require(row['comparison'] == 'incomplete', 'non-comparison error labelled mismatch/match')
        if mode in ['teardown-fail', 'mutate-and-teardown-fail']:
            require(executions[0]['cleanup'] == 'teardown_failed', 'missing cleanup failure')
        else:
            require(executions[0]['cleanup'] == 'confirmed', 'negative cleanup not confirmed')
        if mode == 'unexpected-checkpoint':
            require(executions[0]['outcome'] == 'unexpected_checkpoint', 'missing scheduler divergence')
        if mode == 'cancel':
            require(executions[0]['outcome'] == 'cancelled', 'missing cancellation')
        if mode == 'bad-observation':
            require(row['client'].get('code') == 'observation_shape_mismatch', 'observer codec was weakened')
        if mode == 'early-eof':
            require(row['client']['kind'] in ['io', 'spawn'], 'early EOF misclassified')


def main():
    global FIXTURE
    parser = argparse.ArgumentParser()
    parser.add_argument('--runner', type=Path, required=True)
    parser.add_argument('--mirror', type=Path, default=ROOT / '.lake/build/bin/mirror')
    parser.add_argument('--trace', type=Path, default=FIXTURE / 'type-evidence.itf.json')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--fixture', type=Path, default=FIXTURE)
    parser.add_argument('--installed-prefix', type=Path)
    parser.add_argument('--initial', type=int, choices=[0, 5], default=0)
    args = parser.parse_args()
    args.out.mkdir(mode=0o700, parents=True, exist_ok=False)
    FIXTURE = args.fixture.resolve()
    trace = load(args.trace)
    lock = load(FIXTURE / 'ScheduledCounter.lock.json')
    mapping = {'schema': 'mirrors.dpm-counter-mapping/v1', 'profile': 'mirrorcpp.cooperative-checkpoints/v1',
               'actors': [{'actor': 'a', 'operation': 'increment-a'}, {'actor': 'b', 'operation': 'increment-b'}],
               'actions': {'read': 'read', 'write': 'write', 'finish': '$done'}}
    mapping_path = args.out / 'mapping.json'; write(mapping_path, mapping)
    # Only stimuli and caller-declared initial input form the schedule. Expected
    # oracle state is never supplied to the implementation factory or observer.
    initial = args.initial
    steps = [{'actor': state['parameters']['actor'], 'checkpoint': mapping['actions'][state['action_taken']]}
             for state in trace['states'][1:]]
    plan = {'schema': 'mirrors.checkpoint-schedule/v1', 'profile': mapping['profile'],
            'identity': {'modelSemanticDigest': lock['semanticDigest'], 'mappingSha256': sha(mapping_path),
                         'implementationSha256': sha(args.runner)},
            'inputs': {'initial': initial, 'mode': 'ok'}, 'steps': steps}
    source_paths = [FIXTURE / 'ScheduledCounter.tla', FIXTURE / 'ScheduledCounter.mirror-interface.json',
                    FIXTURE / 'ScheduledCounter.lock.json', FIXTURE / 'generated-cpp/ScheduledCounterMirror.generated.hpp',
                    ROOT / 'tools/deterministic-scheduling/counter.cpp', ROOT / 'tools/deterministic-scheduling/counter_support.hpp', Path(__file__),
                    SDK / 'include/mirrorcpp/schedule.hpp', SDK / 'src/schedule.cpp',
                    SDK / 'include/mirrorcpp/schedule_binding.hpp', SDK / 'src/schedule_binding.cpp',
                    args.runner, args.mirror, args.trace]
    if args.installed_prefix:
        source_paths = [p for p in args.installed_prefix.rglob('*') if p.is_file()]
        source_paths += [p for p in FIXTURE.rglob('*') if p.is_file()]
        source_paths += [args.runner, args.mirror, args.trace, Path(__file__)]
    inputs = {str(path.resolve()): sha(path) for path in source_paths}
    sentinel = args.out / 'forbidden-model-check'
    sentinel.write_text('#!/usr/bin/env python3\nfrom pathlib import Path\n(Path(__file__).parent/"model-check-invoked").write_text("unexpected")\nraise SystemExit(97)\n')
    sentinel.chmod(0o700)
    env = dict(os.environ, APALACHE_MC=str(sentinel.resolve()))
    for name in ['APALACHE_JAR', 'TLA2TOOLS_JAR']:
        env.pop(name, None)
    fake_done = args.out / 'empty-peer'
    fake_done.write_text('''#!/usr/bin/env python3
import sys,json
request=json.loads(sys.stdin.readline())
mi=request['modelInterface']
print(json.dumps({'proto_step':'spec_validated','result':'valid','modelInterface':{'schema':'mirrors.model-interface-negotiation/v1','status':'matched','descriptorSchema':'mirrors.model-interface-descriptor/v1','semanticDigest':mi['expectedSemanticDigest']}}),flush=True)
print('{"proto_step":"all_steps_done"}',flush=True)
''')
    fake_done.chmod(0o700)
    early_eof = args.out / 'early-eof-peer'
    early_eof.write_text('''#!/usr/bin/env python3
import sys,json,subprocess
from pathlib import Path
peer=subprocess.Popen([''' + repr(str(args.mirror.resolve())) + '''],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
try:
 peer.stdin.write(sys.stdin.readline());peer.stdin.flush()
 for _ in range(2):
  line=peer.stdout.readline()
  if not line:raise RuntimeError('comparison peer ended early')
  print(line.rstrip('\\n'),flush=True)
 reply=json.loads(sys.stdin.readline())
 if reply.get('proto_step')!='report_state':raise RuntimeError('expected actual initial report')
finally:
 peer.stdin.close()
 try:peer.wait(timeout=3)
 except subprocess.TimeoutExpired:peer.terminate();peer.wait(timeout=3)
 (Path(__file__).parent/'early-eof-child-reaped').write_text(str(peer.returncode))
''')
    early_eof.chmod(0o700)
    modes = ['ok', 'mutate', 'teardown-fail', 'mutate-and-teardown-fail', 'wrong-identity',
             'denied-negotiation', 'unexpected-checkpoint', 'cancel', 'bad-observation',
             'malformed-input', 'reentrant', 'early-done', 'early-eof', 'repeat', 'oracle-init-not-adopted']
    rows = []
    for mode in modes:
        current = copy.deepcopy(plan)
        current['inputs']['mode'] = 'ok' if mode in ['early-done', 'early-eof', 'repeat', 'oracle-init-not-adopted'] else mode
        if mode == 'wrong-identity': current['identity']['mappingSha256'] = 'f' * 64
        schedule = args.out / (mode + '.schedule.json'); write(schedule, current)
        report = args.out / (mode + '.receipt.json')
        peer = fake_done if mode == 'early-done' else early_eof if mode == 'early-eof' else args.mirror
        repeats = 2 if mode == 'repeat' else 1
        selected_trace = args.trace
        if mode == 'oracle-init-not-adopted':
            corrupted = copy.deepcopy(trace)
            corrupted['states'][0]['count'] = {'#bigint': str(initial + 100)}
            selected_trace = args.out / 'wrong-oracle-initial.itf.json'
            write(selected_trace, corrupted)
        argv = [str(args.runner.resolve()), '--mirror', str(peer.resolve()), '--spec', str(FIXTURE / 'ScheduledCounter.tla'),
                '--trace', str(selected_trace.resolve()), '--schedule', str(schedule.resolve()), '--mapping', str(mapping_path.resolve()),
                '--out', str(report.resolve()), '--repeats', str(repeats)]
        result = subprocess.run(argv, cwd=args.out.resolve(), env=env, capture_output=True, text=True, timeout=40)
        (args.out / (mode + '.log')).write_text(result.stdout + result.stderr)
        require(result.returncode == 0, mode + ': runner failed; see retained log')
        row = load(report)
        classify(row, 'ok' if mode == 'repeat' else mode, repeats)
        if mode == 'oracle-init-not-adopted':
            require(row['client']['actual']['count'] == {'#bigint': str(initial)} and
                    row['client']['expected']['count'] == {'#bigint': str(initial + 100)},
                    'implementation adopted oracle initial state')
        if mode == 'early-eof': require((args.out / 'early-eof-child-reaped').exists(), 'comparison child not reaped')
        rows.append({'case': mode, 'receipt': report.name, 'sha256': sha(report), 'status': 'passed'})
        print(mode + ': passed', flush=True)
    require(not (args.out / 'model-check-invoked').exists(), 'offline gate invoked a local model checker')
    require(inputs == {str(path.resolve()): sha(path) for path in source_paths}, 'source or artifact changed during acceptance')
    write(args.out / 'acceptance.json', {'schema': 'mirrors.dpm2-acceptance/v1', 'status': 'passed', 'rows': rows,
          'inputs': inputs, 'localModelCheckerInvocations': 0, 'semanticDigest': lock['semanticDigest'],
          'traceOrigin': trace.get('#meta', {}).get('origin', 'supplied trace; inspect its capture provenance'),
          'comparison': 'actual Mirrors for positive and mutation cases; synthetic peers only for negative protocol controls'})


if __name__ == '__main__':
    main()
