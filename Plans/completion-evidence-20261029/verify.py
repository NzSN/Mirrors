#!/usr/bin/env python3
"""Offline campaign integrity and claim checks; never execute retained payloads."""
import hashlib
import json
import re
from pathlib import Path
import sys
import tarfile

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def require(ok, message):
    if not ok:
        raise ValueError(message)

def check_inventory(root, entries):
    require(type(entries) is list and entries, 'empty artifact inventory')
    seen = set()
    for entry in entries:
        name = entry['path']
        path = root/name
        require(name not in seen and not Path(name).is_absolute() and '..' not in Path(name).parts,
                'invalid or duplicate inventory path')
        seen.add(name)
        require(path.is_file() and not path.is_symlink() and path.resolve().is_relative_to(root.resolve()),
                'missing or escaping artifact: '+name)
        raw = path.read_bytes()
        require(len(raw) == entry['bytes'] and sha(raw) == entry['sha256'], 'artifact identity differs: '+name)

def check_frontend(directory, passing):
    report = read(directory/'report.json')
    require(report['inputs']['implementationStable'], 'frontend implementation drift')
    require(len(report['observations']) == 183 and all(o['execution'] == 'completed' for o in report['observations']),
            'frontend observations incomplete')
    require(report['verdict'] == ('pass' if passing else 'fail'), 'frontend verdict differs')
    if passing:
        require(not any(c['status'] in ['fail','incomplete','oracle_disagreement'] for c in report['comparisons']),
                'unresolved frontend findings')
        require(report['coverage']['comparisons'] == {'match':564,'reviewed_difference':14,'unsupported':292},
                'frontend comparison scope differs')
    index = {r['path']:r for r in read(directory/'artifact-index.json')['files']}
    contents = {}
    with tarfile.open(directory/'raw-evidence.tar.gz','r:gz') as archive:
        for member in archive.getmembers():
            if member.isdir():
                continue
            require(member.isfile() and member.name.startswith(directory.name+'/'), 'archive member escapes its scope')
            name = member.name[len(directory.name)+1:]
            require(name in index and name not in contents and '..' not in Path(name).parts, 'unexpected archive artifact')
            raw = archive.extractfile(member).read()
            require(sha(raw) == index[name]['sha256'] and len(raw) == index[name]['bytes'], 'archive bytes differ: '+name)
            contents[name] = raw
    require(set(contents) == set(index), 'archive is incomplete')
    for name in ['report.json','semantic.json','summary.md','captured-inputs.json']:
        require(contents[name] == (directory/name).read_bytes(), 'extracted archive metadata differs')
    for observation in report['observations']:
        for artifact in observation['rawArtifacts']:
            require(artifact['path'] in contents and sha(contents[artifact['path']]) == artifact['sha256'],
                    'observation raw artifact differs')
    require(read(directory/'semantic.json')['verdict'] == report['verdict'], 'semantic verdict differs')
    return sha((directory/'semantic.json').read_bytes())

def check_comparisons():
    root = ROOT/'controlled-model'
    acceptance = read(root/'acceptance.json')
    require(acceptance['status'] == 'remote-comparison-passed' and acceptance['modelComparison'] is True,
            'remote controlled comparison incomplete')
    require(acceptance['freshExecutions'] == 13, 'native execution count differs')
    require(acceptance['reduction']['scope'] == 'two-declared-actor-order-policies' and
            acceptance['reduction']['claim'] == 'minimal_in_admitted_catalog' and
            acceptance['reduction']['freshBest']['comparison'] == 'rejected', 'reduction claim differs')
    results = list(root.glob('*/comparison/result.json'))
    require(len(results) == 11, 'controlled model verdict inventory differs')
    ids = set()
    for path in results:
        result = read(path)
        require(result['schema'] == 'mirrors.controlled-sync-model-comparison/v1' and
                result['profile'] == 'mirrors.controlled-mutex-fifo-model/v1' and
                result['modelComparison'] is True and result['cleanup'] == 'confirmed', 'invalid composite result')
        require(result['executionId'] not in ids, 'reused native execution identity')
        ids.add(result['executionId'])
        for name, expected in result['artifacts'].items():
            file = path.parent/name
            require(not Path(name).is_absolute() and '..' not in Path(name).parts and file.is_file() and
                    not file.is_symlink() and file.resolve().is_relative_to(path.parent.resolve()) and
                    sha(file.read_bytes()) == expected, 'controlled artifact differs: '+name)
        raw = read(path.parent/'native-receipt.json')
        require(raw['modelComparison'] is False and raw['executionId'] == result['executionId'], 'raw SDK meaning changed')
        output = (path.parent/'validation/stdout.log').read_text(encoding='utf-8-sig')
        oracle = result['oracle']
        if result['comparison'] == 'matched':
            require(oracle['exitCode'] == 0 and oracle['verdict'] == 'valid' and output.strip() == 'VALID', 'invalid match verdict')
        else:
            require(result['comparison'] == 'rejected' and oracle['exitCode'] == 1 and
                    oracle['verdict'] == 'invalid' and output.startswith('INVALID') and
                    'invariant' in output.lower(), 'rejection lacks actual invariant violation')
    return len(results)

def check_matrix():
    root = ROOT/'client-matrix'
    receipt = read(root/'receipt.json')
    require(receipt['schema'] == 'mirrors.remote-interop/v2' and
            receipt['profile'] == 'remote-five-client-mtls/v1', 'wrong client matrix profile')
    protocol_cases = ['register','mismatch','register_traces','register_trace_gen',
                      'register_explore','register_explore_session','inline_multimodule']
    expected = {(client, case) for client in ['cpp','haskell','rust','lean','ecma']
                for case in ['valid','invalid','wrong-pin']} | {('ecma', case) for case in protocol_cases}
    rows = receipt['rows']
    require(len(rows) == 22 and {(row['client'], row['case']) for row in rows} == expected,
            'client matrix membership is incomplete or duplicated')
    pin_exits = {'cpp':2,'haskell':2,'rust':2,'lean':1,'ecma':1}
    for row in rows:
        path = root/row['log']
        require(Path(row['log']).name == row['log'] and not path.is_symlink() and
                sha(path.read_bytes()) == row['logSha256'], 'matrix log differs')
        text = path.read_text(encoding='utf-8')
        markers = [line for line in text.splitlines() if re.match(r'^(VALID|INVALID)(\s|$)|^spec invalid:', line)]
        if row['case'] == 'valid':
            require(row['exitCode'] == 0 and markers == ['VALID'], 'invalid positive client verdict')
        elif row['case'] == 'invalid':
            require(row['exitCode'] == 1 and len(markers) == 1 and markers[0] != 'VALID',
                    'missing negative client verdict')
        elif row['case'] == 'wrong-pin':
            require(row['exitCode'] == pin_exits[row['client']] and not markers and
                    'certificate fingerprint mismatch' in text.lower(), 'pin rejection differs')
        else:
            require(row['exitCode'] == 0, 'protocol scenario failed')
    protocol = read(root/'ecma-protocol-receipt.json')
    require(protocol['rows'] == [{'case':case,'status':'passed'} for case in protocol_cases],
            'protocol scenario evidence differs')
    before = read(ROOT/'receipts/matrix-observation-before.json')
    after = read(ROOT/'receipts/matrix-observation-after.json')
    require(sha((ROOT/'receipts/matrix-observation-before.json').read_bytes()) == receipt['deploymentObservationSha256'],
            'matrix observation binding differs')
    require({k:v for k,v in before.items() if k != 'observedAt'} ==
            {k:v for k,v in after.items() if k != 'observedAt'}, 'oracle or fixture identity drift')
    require(before['interopFixtures']['files'] == receipt['windowsFixtureSha256'], 'fixture binding differs')
    cleanup = read(ROOT/'receipts/matrix-cleanup.json')
    require(cleanup['ownedServerPresent'] is False and cleanup['lifecycle']['jobCleanup'] == 'confirmed' and
            cleanup['lifecycle']['failure'] is None and cleanup['lifecycle']['sourceAndRuntimeUnchanged'],
            'owned oracle cleanup or stability is incomplete')
    observed = cleanup['lifecycle']['observedJava']
    require(bool(observed) and all(row['sha256'] == before['runtime']['javaExecutableSha256'] for row in observed),
            'actual backend Java identity differs')
    return len(rows)

def main():
    manifest = read(ROOT/'inventory.json')
    check_inventory(ROOT, manifest['files'])
    base = REPO/'test/fixtures/tla-frontend/differential/evidence'
    check_frontend(base/'profile6-20261029-probe-portable', False)
    left = check_frontend(base/'profile6-20261029-t', True)
    right = check_frontend(base/'profile6-20261029-u', True)
    require(left == right, 'independent frontend semantic payloads differ')
    count = check_comparisons()
    matrix_rows = check_matrix()
    installed = read(ROOT/'receipts/installed-dpm-acceptance.json')
    require(installed['status'] == 'passed' and installed['sourceHidden'] and installed['networkNamespaceIsolated'] and
            {p['language'] for p in installed['profiles']} == {'cpp','ecma','rust'} and
            all(p['status'] == 'passed' and p['freshModelCheck'] is False for p in installed['profiles']),
            'installed acceptance scope differs')
    preflight = read(ROOT/'receipts/m4-selected-preflight.json')
    require(preflight['nativeLinuxHost'] is False and preflight['kernelEnforcementTested'] is False and
            preflight['postRestartProcessRecoveryTested'] is False, 'native M4 claim was broadened')
    # Explicit missing/tampered controls prove the inventory check fails closed.
    original = manifest['files'][0]
    for bad in [dict(original, path='missing-control-artifact'), dict(original, sha256='0'*64)]:
        try:
            check_inventory(ROOT, [bad])
        except ValueError:
            pass
        else:
            raise ValueError('inventory negative control was accepted')
    print(json.dumps({'status':'passed','profile6SemanticSha256':left,'controlledModelVerdicts':count,
                      'currentClientMatrixRows':matrix_rows,
                      'installedProfiles':3,'negativeControls':['missing-artifact','tampered-digest'],
                      'fullFrameworkQualification':False,'nativeM4Acceptance':False},sort_keys=True))

if __name__ == '__main__':
    try:
        main()
    except (ValueError,KeyError,OSError,TypeError) as error:
        print('Completion evidence refused: '+str(error),file=sys.stderr)
        raise SystemExit(1)
