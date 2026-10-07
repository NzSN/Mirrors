#!/usr/bin/env python3
"""Bounded, read-only view of actual checkpoint/model-comparison receipts."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

MAX_BYTES = 32 * 1024 * 1024
MAX_STEPS = 65_536
OUTCOMES = {'completed','invalid_schedule','incompatible_identity','cancelled','timed_out',
            'unexpected_checkpoint','uncontrolled_actor','application_failed','observation_failed','resource_failed'}
CLEANUPS = {'not_started','confirmed','incomplete','teardown_failed'}

class TimelineError(ValueError):
    pass


def require(value: bool, message: str) -> None:
    if not value:
        raise TimelineError(message)


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate receipt key: ' + key)
        result[key] = value
    return result


def decode(raw: bytes) -> dict[str, Any]:
    require(len(raw) <= MAX_BYTES, 'receipt exceeds byte bound')
    try:
        value = json.loads(raw.decode('utf-8'), object_pairs_hook=_pairs,
                           parse_constant=lambda value: (_ for _ in ()).throw(TimelineError('nonfinite JSON')))
    except (UnicodeError, json.JSONDecodeError, RecursionError, ValueError) as error:
        raise TimelineError('invalid receipt JSON: ' + str(error)) from error
    require(type(value) is dict, 'receipt object required')
    pending = [(value, 0)]; count = 0
    while pending:
        item, depth = pending.pop(); count += 1
        require(depth <= 64 and count <= 1_000_000, 'receipt structure exceeds bound')
        if isinstance(item, dict): pending.extend((v, depth + 1) for v in item.values())
        elif isinstance(item, list): pending.extend((v, depth + 1) for v in item)
    return value


def _int(value, message):
    require(type(value) is int and value >= 0, message)
    return value


def execution_rows(execution: dict[str, Any], ordinal: int) -> dict[str, Any]:
    require(type(execution) is dict and execution.get('schema') in {'mirrors.checkpoint-replay/v1','mirrors.checkpoint-execution/v1'}, 'unknown execution receipt')
    require(execution.get('outcome') in OUTCOMES and execution.get('cleanup') in CLEANUPS, 'unknown execution/cleanup outcome')
    remaining = execution.get('remainingActors'); require(type(remaining) is list and len(remaining)<=64 and all(type(x) is str for x in remaining), 'invalid remaining actor list')
    schedule = execution.get('schedule'); require(type(schedule) is dict, 'missing admitted schedule')
    steps = schedule.get('steps'); require(type(steps) is list and len(steps) <= MAX_STEPS, 'invalid step array')
    events = execution.get('events'); observations = execution.get('observations')
    require(type(events) is list and len(events) <= 2 * len(steps) and type(observations) is list, 'invalid event/observation arrays')
    for step in steps:
        require(type(step) is dict and set(step) == {'actor','checkpoint'} and all(type(v) is str for v in step.values()), 'invalid schedule step')
    arrivals = {}; permits = set()
    for index, event in enumerate(events):
        require(type(event) is dict and event.get('ordinal') == index and type(event.get('ordinal')) is int, 'event ordinal mismatch')
        step = _int(event.get('step'), 'invalid event step')
        require(step < len(steps) and event.get('actor') == steps[step]['actor'], 'event actor/step mismatch')
        require(step == index // 2 and event.get('kind') == ('permit' if index % 2 == 0 else 'arrival'), 'permit/arrival order mismatch')
        require(type(event.get('checkpoint')) is str, 'event checkpoint string required')
        if event['kind'] == 'permit': permits.add(step)
        else: arrivals[step] = event['checkpoint']
    by_after = {}; previous = -1
    for observation in observations:
        require(type(observation) is dict and 'state' in observation, 'observation state missing')
        after = _int(observation.get('afterSteps'), 'invalid observation index')
        require(after > previous and after <= len(steps), 'observation index/order mismatch')
        if after:
            require(after - 1 in arrivals and arrivals[after - 1] == steps[after - 1]['checkpoint'], 'observation without verified arrival')
        by_after[after] = observation['state']; previous = after
    if execution.get('passed') is True:
        require(execution.get('scheduleCompleted') is True and execution['outcome'] == 'completed' and execution['cleanup'] == 'confirmed', 'contradictory execution pass')
        require(not remaining and len(arrivals) == len(steps) and set(by_after) == set(range(len(steps) + 1)), 'incomplete passing execution evidence')
    rows = [{'afterSteps':0,'actor':None,'expectedCheckpoint':'$start','actualCheckpoint':'$start' if 0 in by_after else None,
             'permit':False,'observation':by_after.get(0),'observationRetained':0 in by_after,'comparison':'unknown','modelAction':None}]
    for index, step in enumerate(steps):
        rows.append({'afterSteps':index+1,'actor':step['actor'],'expectedCheckpoint':step['checkpoint'],
                     'actualCheckpoint':arrivals.get(index),'permit':index in permits,
                     'observation':by_after.get(index+1),'observationRetained':index+1 in by_after,
                     'comparison':'unknown','modelAction':None})
    return {'ordinal':ordinal,'executionId':execution.get('executionId'),'generation':execution.get('generation'),
            'identity':schedule.get('identity'),'profile':schedule.get('profile'),'outcome':execution['outcome'],
            'detail':execution.get('detail'),'scheduleCompleted':execution.get('scheduleCompleted') is True,
            'cleanup':execution['cleanup'],'remainingActors':execution.get('remainingActors',[]),
            'rows':rows,'receiptPassed':execution.get('passed') is True}


def build_timeline(raw: bytes, expected_sha256: str | None = None, kit_metadata: bytes | None = None, kit_sha256: str | None = None) -> dict[str, Any]:
    digest = hashlib.sha256(raw).hexdigest()
    if expected_sha256 is not None:
        require(re.fullmatch('[0-9a-f]{64}', expected_sha256) is not None and expected_sha256 == digest, 'receipt hash mismatch')
    receipt = decode(raw); schema = receipt.get('schema')
    require(schema in {'mirrors.scheduled-comparison/v1','mirrors.scheduled-binding/v1','mirrors.checkpoint-replay/v1','mirrors.checkpoint-execution/v1'}, 'unknown receipt schema')
    binding = receipt.get('binding',{}) if schema == 'mirrors.scheduled-comparison/v1' else receipt
    if schema in {'mirrors.checkpoint-replay/v1','mirrors.checkpoint-execution/v1'}: executions = [receipt]; complete = True
    else:
        require(type(binding) is dict and binding.get('schema') == 'mirrors.scheduled-binding/v1', 'invalid binding receipt')
        executions = binding.get('executions'); complete = binding.get('receiptComplete') is True
    require(type(executions) is list and len(executions) <= 64, 'invalid execution list')
    views = []
    for index, execution in enumerate(executions):
        if type(execution) is dict and 'evidenceError' in execution:
            complete = False; views.append({'ordinal':index,'evidenceError':execution['evidenceError'],'rows':[],'cleanup':'unknown'});continue
        views.append(execution_rows(execution,index))
    execution_ids=[v.get('executionId') for v in views if 'evidenceError' not in v]
    require(all(type(x) is str and x for x in execution_ids) and len(set(execution_ids))==len(execution_ids),'missing or repeated execution identity')
    require(sum(len(v['rows']) for v in views) <= MAX_STEPS + 64, 'timeline row bound exceeded')
    comparison = receipt.get('comparison','unknown'); client = receipt.get('client',{}); peer = receipt.get('peerTerminal','')
    require(type(client) is dict, 'invalid client result')
    require(comparison in {'matched','step_mismatch','incomplete','unknown'}, 'unknown comparison classification')
    peer_data = None
    if receipt.get('peerTerminalRaw'):
        require(type(receipt['peerTerminalRaw']) is str, 'raw terminal must be text')
        peer_data = decode(receipt['peerTerminalRaw'].encode('utf-8'))
    if comparison == 'matched':
        require(peer == 'all_steps_done' and peer_data is not None and peer_data.get('proto_step') == peer, 'unconfirmed matched terminal')
    if comparison == 'step_mismatch':
        require(peer == 'step_mismatch' and peer_data is not None and peer_data.get('proto_step') == peer and client.get('kind') == 'step_mismatch', 'unconfirmed mismatch terminal')
        require('expected' in peer_data and 'actual' in peer_data, 'mismatch states absent')
    kit_source = None
    if kit_metadata is not None:
        require(kit_sha256 is not None and re.fullmatch('[0-9a-f]{64}',kit_sha256) is not None and hashlib.sha256(kit_metadata).hexdigest()==kit_sha256, 'kit metadata requires matching trusted SHA-256')
        kit = decode(kit_metadata)
        require(kit.get('schema')=='mirrors.dpm-kit-metadata/v1', 'unknown kit metadata schema')
        relations = kit.get('relations');require(type(relations) is list and len(relations)<=256, 'invalid kit relation list')
        for relation in relations:
            require(type(relation) is dict and set(relation)=={'actionId','wireAction','checkpoint'} and all(type(x) is str for x in relation.values()), 'invalid kit action relation')
        for view in views:
            if 'evidenceError' in view:continue
            identity=view['identity'];require(type(identity) is dict and identity.get('modelSemanticDigest')==kit.get('modelSemanticDigest') and identity.get('mappingSha256')==kit.get('mappingSha256') and view['profile']==kit.get('schedulingProfile'), 'kit/receipt identity or execution profile mismatch')
            for row in view['rows']:
                candidates=[x for x in relations if x['checkpoint']==row['expectedCheckpoint']]
                if len(candidates)==1:
                    row['modelAction']=candidates[0]['wireAction'];row['modelActionSource']='trusted kit relation'
        kit_source=kit_sha256
    elif kit_sha256 is not None:
        raise TimelineError('kit hash without metadata')
    failure_location = None
    if comparison == 'step_mismatch' and views:
        state_index = client.get('stateIndex'); trace_index = client.get('traceIndex')
        if type(state_index) is int and state_index >= 0 and type(trace_index) is int and 0 <= trace_index < len(views):
            candidates = [(trace_index,r) for r in views[trace_index]['rows'] if r['afterSteps']==state_index and r['observationRetained'] and r['observation']==peer_data['actual']]
            basis = 'explicit client trace/state indices and matching actual observation'
        else:
            candidates = [(len(views)-1,r) for r in views[-1]['rows'] if r['observationRetained'] and r['observation']==peer_data['actual']]
            basis = 'unique matching actual observation in final execution; model action may remain unknown'
        if len(candidates)==1:
            execution,row=candidates[0];row['comparison']='step_mismatch'
            if client.get('action') is not None:row['modelAction']=client['action'];row['modelActionSource']='retained client result'
            failure_location={'execution':execution,'afterSteps':row['afterSteps'],'basis':basis}
    if comparison == 'matched':
        for view in views:
            if view.get('scheduleCompleted'):
                for row in view['rows']:
                    if row['observationRetained']:row['comparison']='matched_by_terminal'
    source_passed = receipt.get('passed') is True
    passed = source_passed and schema == 'mirrors.scheduled-comparison/v1'
    if passed:
        require(comparison == 'matched' and complete and bool(views) and all(v.get('receiptPassed') for v in views), 'contradictory overall pass')
    hints = client.get('orderedHints',[]);require(type(hints) is list and len(hints)<=4096, 'invalid hint array')
    return {'schema':'mirrors.dpm-timeline/v1','sourceSha256':digest,'inputSchema':schema,'comparison':comparison,
            'passed':passed,'sourcePassed':source_passed,'receiptComplete':complete,'peerTerminal':peer,'clientFailure':{k:v for k,v in client.items() if k not in {'expected','actual','report'}},
            'mismatch':({'expected':peer_data['expected'],'actual':peer_data['actual'],'orderedHints':hints,'location':failure_location} if comparison=='step_mismatch' else None),
            'executions':views,'kitMetadataSha256':kit_source,'scope':'read-only diagnostic correlation; no fresh replay or model qualification'}


def _display(value) -> str:
    return '-' if value is None else json.dumps(value,ensure_ascii=True,separators=(',',':')) if not isinstance(value,str) else value.encode('unicode_escape').decode('ascii')


def render_text(timeline: dict[str, Any]) -> str:
    lines=['DPM timeline',f"Comparison: {timeline['comparison']}; passed: {str(timeline['passed']).lower()}; receipt complete: {str(timeline['receiptComplete']).lower()}"]
    for execution in timeline['executions']:
        lines += ['',f"Execution {execution['ordinal']}: {_display(execution.get('executionId'))}; outcome: {_display(execution.get('outcome'))}",
                  f"Cleanup: {execution['cleanup']}; remaining actors: {_display(execution.get('remainingActors',[]))}"]
        if 'evidenceError' in execution:lines.append('Evidence error: '+_display(execution['evidenceError']));continue
        lines.append('Step | Model action | Actor | Permit | Expected point | Actual point | Observation | Comparison')
        for row in execution['rows']:
            lines.append(' | '.join([str(row['afterSteps']),_display(row['modelAction']),_display(row['actor']),'yes' if row['permit'] else 'no',_display(row['expectedCheckpoint']),_display(row['actualCheckpoint']),'retained' if row['observationRetained'] else 'absent',row['comparison']]))
    if timeline['mismatch']:
        lines += ['', 'Model mismatch (retained peer verdict):']
        for hint in timeline['mismatch']['orderedHints']:lines.append('  '+_display(hint))
        if not timeline['mismatch']['location']:lines.append('  Execution/step attribution: unknown')
        lines += ['  expected: '+_display(timeline['mismatch']['expected']),'  actual:   '+_display(timeline['mismatch']['actual'])]
    if not timeline['receiptComplete']:lines.append('\nEvidence incomplete; no completion/pass inferred.')
    return '\n'.join(lines)+'\n'


def main() -> int:
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--receipt',type=Path,required=True);p.add_argument('--expected-sha256');p.add_argument('--format',choices=['text','json'],default='text');p.add_argument('--out',type=Path);p.add_argument('--kit-metadata',type=Path);p.add_argument('--kit-sha256');args=p.parse_args()
    try:
        require(not args.receipt.is_symlink() and args.receipt.is_file(),'receipt must be a regular nonsymlink file')
        if args.out:require(args.out.resolve()!=args.receipt.resolve(),'output must not replace input receipt')
        with args.receipt.open('rb') as stream:raw=stream.read(MAX_BYTES+1)
        kit_raw = None
        if args.kit_metadata:
            require(not args.kit_metadata.is_symlink() and args.kit_metadata.is_file(), 'kit metadata regular file required')
            with args.kit_metadata.open('rb') as stream:kit_raw=stream.read(MAX_BYTES+1)
        result=build_timeline(raw,args.expected_sha256,kit_raw,args.kit_sha256)
        text=json.dumps(result,indent=2,ensure_ascii=True)+'\n' if args.format=='json' else render_text(result)
        if args.out:
            with args.out.open('x',encoding='utf-8') as stream:stream.write(text)
        else:print(text,end='')
        return 0
    except (OSError,TimelineError,TypeError,KeyError) as error:
        p.exit(2,'timeline: '+str(error)+'\n')

if __name__=='__main__':raise SystemExit(main())
