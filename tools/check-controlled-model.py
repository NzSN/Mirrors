#!/usr/bin/env python3
"""Fresh native controlled-resource witnesses and optional required remote comparison.

No local model checker is started. Without --remote this establishes only
native execution, pure admission and source preparation, with no model match.
"""
import sys
if __name__ == '__main__' and not (sys.flags.isolated and sys.flags.no_site and sys.dont_write_bytecode):
    print('controlled model gate requires python3 -I -S -B', file=sys.stderr)
    raise SystemExit(2)

import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('controlled_model', ROOT/'tools/deterministic-scheduling/controlled_model.py')
MODEL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODEL)


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write(path, value):
    with Path(path).open('x', encoding='utf-8') as stream:
        json.dump(value, stream, sort_keys=True, separators=(',', ':')); stream.write('\n')


def run(command, log, expected=0, timeout=180, maximum=4*1024*1024):
    with Path(log).open('xb') as stream:
        result = subprocess.run([str(value) for value in command], cwd=ROOT,
                                stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
    if Path(log).stat().st_size > maximum:
        raise RuntimeError('tool log exceeds its retained bound: ' + str(log))
    if result.returncode != expected:
        raise RuntimeError('unexpected exit ' + str(result.returncode) + ': ' + str(log))
    return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--remote', type=Path)
    parser.add_argument('--mirror', type=Path, default=ROOT/'.lake/build/bin/mirror')
    parser.add_argument('--remote-sha256')
    parser.add_argument('--require-remote', action='store_true')
    parser.add_argument('--reduce-count', action='store_true')
    args = parser.parse_args()
    if args.require_remote and not args.remote: parser.error('required remote comparison has no selected endpoint')
    if args.remote and not args.remote_sha256: parser.error('remote configuration requires its independently selected digest')
    if args.reduce_count and not args.remote: parser.error('count reduction requires actual remote model verdicts')
    args.prefix = args.prefix.resolve(strict=True)
    args.out = args.out.absolute(); args.out.mkdir(parents=True, exist_ok=False)
    policy = ROOT/'.lake/build/bin/mirrors_dpm'
    mirror = args.mirror.resolve(strict=True)
    model = ROOT/'specs/ControlledMutexFifo.tla'
    fixture = ROOT/'tools/deterministic-scheduling/controlled-model'
    inputs = [policy, mirror, model, fixture/'native.cpp', fixture/'CMakeLists.txt',
              args.prefix/'lib/libmirrorcpp.a', ROOT/'tools/deterministic-scheduling/controlled_model.py', Path(__file__)]
    frozen = {str(path): sha(path) for path in inputs}
    build = args.out/'build'
    run(['cmake', '-S', fixture, '-B', build, '-DCMAKE_BUILD_TYPE=Release',
         '-DCMAKE_PREFIX_PATH='+str(args.prefix)], args.out/'configure.log')
    run(['cmake', '--build', build, '-j2'], args.out/'build.log')
    binary = build/'controlled_model_runner'
    selected = {'schema': 'mirrors.controlled-model-mapping/v1', 'profile': MODEL.PROFILE,
                'modelSourceSha256': sha(model), 'implementationSha256': sha(binary),
                'actors': ['consumer', 'producer'], 'resources': [
                    {'id':'mutex','kind':'mutex','capacity':0}, {'id':'queue','kind':'queue','capacity':1}],
                'observations': ['count', 'received'], 'maxDecisions': 32}
    MODEL.mapping(selected)
    mapping = args.out/'mapping.json'; write(mapping, selected)
    mapping_sha = sha(mapping)
    execution_ids = set()
    deadline = time.monotonic()+1200

    def case(name, order, mutation, remote=True):
        if time.monotonic() >= deadline: raise RuntimeError('controlled campaign deadline expired')
        directory = args.out/name; directory.mkdir()
        native = directory/'native.json'
        run([binary, '--order', order, '--mutation', mutation,
             '--model-digest', selected['modelSourceSha256'], '--mapping-sha256', mapping_sha,
             '--implementation-sha256', selected['implementationSha256']], native,
            expected=2 if mutation in ['cleanup','deadline'] else 0, timeout=15, maximum=65536)
        receipt = json.loads(native.read_text())
        if receipt['executionId'] in execution_ids: raise RuntimeError('native factory execution identity reused')
        execution_ids.add(receipt['executionId'])
        request = {'schema': 'mirrors.controlled-sync-check/v1', 'identity': receipt['identity'], 'receipt': receipt}
        request_path = directory/'request.json'; write(request_path, request)
        witness_path = directory/'witness.json'
        run([policy, '_sync-check', request_path], witness_path,
            expected=2 if mutation in ['cleanup','deadline'] else 0, timeout=30)
        if mutation in ['cleanup','deadline']:
            return {'case':name,'native':'non-passing','admission':'refused','modelComparison':False}
        witness = json.loads(witness_path.read_text())
        MODEL.witness_module(witness)
        generated = directory/'model'; generated.mkdir()
        shutil.copyfile(model, generated/'ControlledMutexFifo.tla')
        (generated/'ControlledWitnessCase.tla').write_text(MODEL.witness_module(witness))
        run([ROOT/'.lake/build/bin/tla_frontend', 'parse', '--spec', generated/'ControlledWitnessCase.tla',
             '--format', 'json'], directory/'frontend.json')
        result = {'case':name,'native':'completed','admission':'accepted','cost':witness['cost'],
                  'executionId':receipt['executionId'],'modelComparison':False}
        if args.remote and remote:
            comparison = directory/'comparison'
            expected = 0 if mutation == 'none' else 1
            run([policy, 'compare-sync', '--receipt', native, '--receipt-sha256', sha(native),
                 '--mapping', mapping, '--mapping-sha256', mapping_sha, '--model', model,
                 '--implementation', binary, '--mirror', mirror, '--mirror-sha256', sha(mirror),
                 '--remote', args.remote.resolve(), '--remote-sha256', args.remote_sha256,
                 '--out', comparison], directory/'comparison.log', expected=expected, timeout=120)
            actual = json.loads((comparison/'result.json').read_text())
            MODEL.validate_result(actual)
            if actual['comparison'] != ('matched' if expected == 0 else 'rejected'):
                raise RuntimeError('unexpected remote comparison category')
            if expected and ('invariant' not in (comparison/'validation/stdout.log').read_text().lower()
                             or 'violat' not in (comparison/'validation/stdout.log').read_text().lower()):
                raise RuntimeError('remote negative lacks an actual invariant violation: '+name)
            run([policy, 'report', '--receipt', comparison/'result.json', '--expected-sha256',
                 sha(comparison/'result.json'), '--format', 'json'], directory/'report.json')
            result.update(modelComparison=True, comparison=actual['comparison'])
        if mutation == 'count' and receipt['observations'][-1]['state'] != {'count':3,'received':[10,20]}:
            raise RuntimeError('count mutation signature differs')
        return result

    cases = [case('correct-first','first','none'), case('correct-last','last','none'),
             case('count-first','first','count'), case('count-last','last','count'),
             case('fifo-last','last','fifo'), case('early-unlock-first','first','early-unlock'),
             case('cleanup-refusal','first','cleanup'), case('deadline-refusal','first','deadline')]
    original = json.loads((args.out/'correct-first/native.json').read_text())
    mutants = []
    def control(name, receipt):
        directory = args.out/('control-'+name); directory.mkdir()
        path = directory/'request.json'
        write(path, {'schema':'mirrors.controlled-sync-check/v1','identity':original['identity'],'receipt':receipt})
        run([policy,'_sync-check',path],directory/'refusal.log',expected=2)
        mutants.append({'control':name,'status':'refused','remoteContacted':False})
    bad = copy.deepcopy(original); bad['observations'].pop(); control('missing-observation',bad)
    bad = copy.deepcopy(original); bad['events'][0]['ordinal']=1; control('event-ordinal',bad)
    bad = copy.deepcopy(original); bad['cleanup']='incomplete'; control('cleanup',bad)
    bad = copy.deepcopy(original); bad['budgetExceeded']['execution']=True; control('deadline',bad)
    bad = copy.deepcopy(original); bad['modelComparison']=True; control('preclaimed-model-match',bad)
    bad = copy.deepcopy(original); bad['identity']['implementationSha256']='0'*64; control('implementation-identity',bad)
    reduction = None
    if args.reduce_count:
        counts = [row for row in cases if row['case'].startswith('count-')]
        ordered = sorted(counts,key=lambda row:(row['cost'],row['case']))
        baseline = ordered[-1]
        baseline_order = baseline['case'].split('-')[-1]
        baselines = [case('reduction-baseline-'+str(i),baseline_order,'count') for i in range(2)]
        trials = [case('reduction-trial-'+str(i),row['case'].split('-')[-1],'count') for i,row in enumerate(ordered)]
        best = ordered[0]
        final = case('reduction-fresh-best',best['case'].split('-')[-1],'count')
        reduction = {'claim':'minimal_in_admitted_catalog','scope':'two-declared-actor-order-policies',
                     'signature':'controlled-terminal-count-delta-1/v1','baselineCost':baseline['cost'],
                     'bestCost':best['cost'],'baselines':baselines,'trials':trials,'freshBest':final,
                     'cleanup':'confirmed','modelComparison':True}
        write(args.out/'reduction.json',reduction)
    for path, expected in frozen.items():
        if sha(path) != expected: raise RuntimeError('selected implementation changed during campaign: '+path)
    if sha(binary) != selected['implementationSha256']: raise RuntimeError('native executable changed during campaign')
    acceptance = {'schema':'mirrors.controlled-model-acceptance/v1',
                  'status':'remote-comparison-passed' if args.remote else 'local-preparation-passed',
                  'profile':MODEL.PROFILE,'modelComparison':bool(args.remote),'freshExecutions':len(execution_ids),
                  'cases':cases,'controls':mutants,'reduction':reduction,'frozenInputs':frozen,
                  'nativeExecutableSha256':sha(binary),'mappingSha256':mapping_sha,
                  'scope':'finite declared producer/consumer mapping; no generic or exhaustive scheduling claim'}
    write(args.out/'acceptance.json',acceptance)
    print(json.dumps({key:value for key,value in acceptance.items() if key not in ['cases','controls','frozenInputs','reduction']},indent=2))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print('controlled model gate failed: '+str(error),file=sys.stderr)
        raise SystemExit(2)
