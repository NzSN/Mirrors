#!/usr/bin/env python3
"""Independent finite-scope accounting gate; no model checker is invoked."""
import argparse
from collections import Counter
import hashlib
import itertools
import json
from pathlib import Path
import subprocess


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def canonical(value):
    if value is None: return ['null']
    if type(value) is bool: return ['boolean', value]
    if type(value) is int: return ['integer', str(value)]
    if type(value) is str: return ['string', value]
    if type(value) is list: return ['sequence', [canonical(x) for x in value]]
    if type(value) is not dict: raise ValueError('unsupported fixture observation')
    if set(value) == {'#bigint'}: return ['integer', str(int(value['#bigint']))]
    if set(value) == {'#set'}:
        entries = {compact(canonical(x)): canonical(x) for x in value['#set']}
        return ['set', [entries[key] for key in sorted(entries)]]
    if set(value) == {'#map'}:
        entries = {}
        for key, item in value['#map']:
            normalized = canonical(key); identity = compact(normalized)
            require(identity not in entries, 'duplicate map key in actual fixture observation')
            entries[identity] = [normalized, canonical(item)]
        return ['map', [entries[key] for key in sorted(entries)]]
    if set(value) == {'#tup'}: return ['tuple', [canonical(x) for x in value['#tup']]]
    if set(value) == {'tag', 'value'}: return ['variant', value['tag'], canonical(value['value'])]
    return ['record', [[key, canonical(value[key])] for key in sorted(value)]]


def compact(value): return json.dumps(value, separators=(',', ':'), ensure_ascii=False)


def state_key(state):
    return compact(['mirrors.canonical-state/v1', [[key, canonical(state[key])] for key in sorted(state)]])


def eligible(bound):
    result = set()
    for positions in itertools.combinations(range(6), 3):
        order = tuple('a' if i in positions else 'b' for i in range(6))
        prior, used, preemptions = None, Counter(), 0
        for actor in order:
            if prior is not None and actor != prior and used[prior] < 3: preemptions += 1
            used[actor] += 1; prior = actor
        if preemptions <= bound: result.add(order)
    return result


def positive(value, bound):
    expected = eligible(bound)
    require(value['complete'] is True and value['denominatorKnown'] is True, 'positive exploration incomplete')
    require(value['eligibleRuns'] == value['attemptedRuns'] == value['completedRuns'] == len(expected) * 2,
            'independent denominator differs')
    require(value['categories'] == {'passed': len(expected) * 2}, 'positive categories differ')
    require(value['sut'] == {'acquisitions': len(expected) * 2, 'enteredWorkers': len(expected) * 4,
                             'teardowns': len(expected) * 2}, 'actual factory/worker/cleanup denominator differs')
    seen, states, edges, ids = set(), set(), Counter(), set()
    for row in value['runs']:
        schedule, execution = row['schedule'], row['execution']
        require(execution['schedule'] == schedule and execution['passed'] is True and execution['cleanup'] == 'confirmed',
                'execution is not bound and cleaned up')
        require(execution['executionId'] not in ids, 'reused execution identity')
        ids.add(execution['executionId'])
        order = tuple(step['actor'] for step in schedule['steps'])
        initial = schedule['inputs']['initial']
        require(order in expected and initial in [0, 5], 'unexpected schedule/input')
        require((order, initial) not in seen, 'duplicate candidate')
        seen.add((order, initial))
        for actor in ['a', 'b']:
            require([step['checkpoint'] for step in schedule['steps'] if step['actor'] == actor] == ['read', 'write', '$done'],
                    'actor-local order changed')
        observations = execution['observations']
        require(len(observations) == 7, 'wrong actual observation count')
        require(int(observations[-1]['state']['count']['#bigint']) in [initial + 1, initial + 2],
                'fixture final actual count outside known outcomes')
        keys = [state_key(item['state']) for item in observations]
        states.update(keys); edges.update(zip(keys, keys[1:]))
    require(seen == {(order, initial) for order in expected for initial in [0, 5]}, 'omitted eligible candidate')
    published = {item['id']: compact(item['canonical']) for item in value['states']}
    require(set(published.values()) == states and len(published) == len(states), 'canonical state set differs')
    actual_edges = Counter({(published[item['from']], published[item['to']]): item['count'] for item in value['transitions']})
    require(actual_edges == edges, 'semantic transition counts differ')
    require(value['comparisonRuns'] == 0 and value['comparison'] == 'not_requested', 'local scope claims model comparison')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runner', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args(); args.out.mkdir(parents=True, mode=0o700, exist_ok=False)
    before = sha(args.runner)
    cases = [('all', [], 64), ('zero-preemptions', ['--preemptions', '0'], 0),
             ('one-preemption', ['--preemptions', '1'], 1), ('two-preemptions', ['--preemptions', '2'], 2),
             ('run-limit', ['--max-runs', '3'], None), ('enumeration-limit', ['--max-enumerated', '3'], None),
             ('evidence-limit', ['--evidence-bytes', '1'], None), ('cleanup-failure', ['--mode', 'teardown-fail'], None),
             ('schedule-failure', ['--mode', 'unexpected-checkpoint'], None), ('cancel', ['--mode', 'cancel'], None),
             ('comparison-required', ['--require-comparison'], None)]
    rows = []
    for name, extra, bound in cases:
        path = args.out / (name + '.json')
        command = [str(args.runner.resolve()), '--out', str(path.resolve()), *extra]
        result = subprocess.run(command, capture_output=True, text=True, timeout=40)
        (args.out / (name + '.log')).write_text(result.stdout + result.stderr)
        require(result.returncode == 0, name + ': runner failed')
        value = json.loads(path.read_text())
        require(value['schema'] == 'mirrors.finite-exploration/v1', 'wrong exploration schema')
        if bound is not None: positive(value, bound)
        else:
            require(value['complete'] is False, name + ': partial work credited')
            if name == 'run-limit': require(value['stopReason'] == 'run_limit' and value['attemptedRuns'] == 3 and value['eligibleRuns'] == 40, 'run cap differs')
            if name == 'enumeration-limit': require(value['stopReason'] == 'enumeration_limit' and value['denominatorKnown'] is False and value['eligibleRuns'] is None, 'unknown denominator hidden')
            if name == 'evidence-limit': require(value['stopReason'] == 'evidence_limit', 'evidence cap differs')
            if name == 'cleanup-failure': require(value['stopReason'] == 'unconfirmed_cleanup' and value['attemptedRuns'] == 1, 'cleanup failure did not stop further acquisition')
            if name == 'schedule-failure': require(value['categories'] == {'schedule_failed': 40} and value['firstCounterexample'] is None, 'schedule failure labelled a model defect')
            if name == 'cancel': require(value['stopReason'] == 'cancelled' and value['attemptedRuns'] == 1, 'cancellation count differs')
            if name == 'comparison-required': require(value['categories'] == {'comparison_missing': 40} and value['comparisonRuns'] == 0, 'missing model checks credited')
        require(sum(value['categories'].values()) == value['attemptedRuns'], 'attempt accounting differs')
        rows.append({'case': name, 'status': 'passed', 'report': path.name, 'sha256': sha(path)})
        print(name + ': passed', flush=True)
    require(sha(args.runner) == before, 'explorer executable changed')
    manifest = {'schema': 'mirrors.dpm4-acceptance/v1', 'status': 'passed', 'rows': rows, 'runnerSha256': before,
                'unboundedPreemptionFixtureSchedules': 20, 'declaredInputAssignments': 2, 'fullScopeRuns': 40,
                'scope': 'finite local schedule execution and semantic coverage; no model/property proof inferred',
                'freshModelCheck': False, 'partialOrderReduction': 'disabled'}
    (args.out / 'acceptance.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__': main()
