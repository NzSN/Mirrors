#!/usr/bin/env python3
"""Independently verify rc.7 source/C0 freeze and real negative controls."""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLAN = Path(__file__).resolve().parent
OUT = ROOT / '.golden-build/source-freeze-rc7-20261104'
sys.path.insert(0, str(ROOT / 'tools/distribution'))
from build import verify_source_snapshots
from distribution_lib import sha256_file
from manifest_check import digest_json, validate_locks
from refresh_identity import selected_refs
from snapshot_sources import snapshot


def check_file(record):
    path = ROOT / record['path']
    if sha256_file(path) != (record['bytes'], record['sha256']):
        raise ValueError('file identity differs: ' + record['path'])


def hashes(root):
    return {p.relative_to(root).as_posix(): sha256_file(p)
            for p in root.rglob('*') if p.is_file()}


def main():
    os.environ['TMPDIR'] = str(OUT / 'tmp')
    manifest = json.loads((PLAN / 'freeze-manifest.json').read_text())
    intake = json.loads((PLAN / 'intake.json').read_text())
    gate = json.loads((PLAN / 'gate-result.json').read_text())
    source = ROOT / manifest['taskOwnedSource']
    c3 = ROOT / manifest['frameworkCatalog']['path']
    c3_sha = manifest['frameworkCatalog']['sha256']
    ecma = ROOT / '.golden-build/mw12-20261103/inputs/companions/MirrorECMA'
    gate_root = ROOT / '.golden-build/mw12-20261103/inputs/companions/MirrorGate'

    def git(repo, *args):
        return subprocess.run(['git', '-C', str(repo), *args], capture_output=True,
                              text=True, check=True).stdout.strip()

    assert gate['passed'] and gate['sourceAndCompanionsStable'] and gate['exitCode'] == 0
    check_file(manifest['gateResult'])
    check_file(gate['log'])
    assert (ROOT / gate['log']['path']).read_bytes().splitlines()[-1] == b'ALL LOCAL NON-MODEL GATES GREEN'
    assert selected_refs(ecma, gate_root) == gate['after']
    assert git(ROOT, 'rev-parse', 'HEAD') == intake['baseRevision']
    assert git(source, 'rev-parse', 'HEAD') == manifest['freezeRevision']
    assert git(source, 'rev-parse', 'HEAD^{tree}') == manifest['freezeTree']
    assert git(source, 'rev-parse', 'HEAD^') == intake['baseRevision']
    assert git(source, 'status', '--porcelain=v1') == ''
    for value in [manifest['frameworkCatalog'], manifest['carrier'], manifest['validatedSourceIndex']]:
        check_file(value)
    for value in manifest['preservedSharedInputs'].values():
        check_file(value)
    for value in intake['sourceEdits'] + intake['preservedUnrelatedFiles']:
        check_file(value)
    assert 'def version : String := "0.2.0-rc.7"' in (source / 'Shell/Version.lean').read_text()
    version = subprocess.run([str(ROOT / '.lake/build/bin/mirror'), '--version'],
                             capture_output=True, text=True, check=True).stdout
    assert version == 'v0.2.0-rc.7\n'
    fixed_points = []
    controls = []

    def reject(name, action, expected=None):
        try:
            action()
        except (AssertionError, ValueError, OSError) as error:
            if expected is not None and expected not in str(error):
                raise ValueError(name + ' rejected for an unintended reason: ' + str(error))
            controls.append(name)
            return
        raise ValueError('negative control accepted: ' + name)

    with tempfile.TemporaryDirectory(prefix='rc7-independent-') as temporary:
        work = Path(temporary)
        # Regenerate the source tree from the clean commit, independently of the
        # initial snapshot producer, and compare it with the gate-validated tree.
        regenerated = snapshot(source, {'componentId': 'mirrors',
            'repository': git(source, 'config', '--get', 'remote.origin.url'),
            'revision': manifest['freezeRevision'], 'dirty': False}, work / 'source')
        assert regenerated['treeIndexSha256'] == manifest['validatedSourceTreeIndexSha256']
        for family, spec in manifest['families'].items():
            catalog = ROOT / spec['catalog']['path']
            locks = ROOT / spec['locksRoot']
            check_file(spec['catalog'])
            check_file(spec['snapshotIndex'])
            document = json.loads(catalog.read_text())
            assert digest_json(document) == spec['selectionSha256']
            catalog_refs = {v['componentRef']['componentId']: v['componentRef']
                            for v in document['components']}
            expected_refs = dict(gate['after'])
            expected_refs['mirrors'] = {'componentId': 'mirrors',
                'repository': git(source, 'config', '--get', 'remote.origin.url'),
                'revision': manifest['freezeRevision'], 'dirty': False}
            assert catalog_refs == expected_refs
            mirrors = next(v for v in document['components']
                           if v['componentRef']['componentId'] == 'mirrors')
            assert mirrors['product']['version'] == '0.2.0-rc.7'
            for value in spec['candidateFiles'].values():
                check_file(value)
            assert spec['selectedForExecution'] == (family == 'wsl2')
            contract = validate_locks(locks, c3, c3_sha, catalog)
            dependency = contract['dependencies']['lean-batteries-source']
            assert (dependency['bytes'], dependency['sha256']) == (
                manifest['carrier']['bytes'], manifest['carrier']['sha256'])
            snapshot_root = (ROOT / spec['snapshotIndex']['path']).parent
            verify_source_snapshots(snapshot_root, contract)
            assert spec['sourceTreeIndexSha256'] == regenerated['treeIndexSha256']
            original_root = catalog.parents[1]
            repeat = work / family
            shutil.copytree(original_root, repeat)
            copied_catalog = repeat / 'catalog' / catalog.name
            copied_locks = repeat / 'distribution' / locks.name
            before = hashes(repeat)
            process = subprocess.run([sys.executable, str(source / 'tools/distribution/refresh_identity.py'),
                '--mirrorecma', str(ecma), '--mirrorgate', str(gate_root),
                '--framework-catalog-bin', str(c3), '--catalog', str(copied_catalog),
                '--locks-root', str(copied_locks), '--skip-component-records', '--skip-render'],
                cwd=source, capture_output=True, text=True, timeout=60)
            assert process.returncode == 0, process.stderr
            assert hashes(repeat) == before
            fixed_points.append({'family': family, 'byteStableThirdRefresh': True,
                                 'selectionSha256': spec['selectionSha256']})
            document = json.loads(copied_catalog.read_text())
            document['catalogId'] += '-tampered'
            copied_catalog.write_text(json.dumps(document))
            reject(family + '-changed-catalog',
                   lambda: validate_locks(copied_locks, c3, c3_sha, copied_catalog))
            bad_snapshot = work / (family + '-wrong-snapshot')
            bad_snapshot.mkdir()
            index = json.loads((snapshot_root / 'snapshot-index.json').read_text())
            index['components'][0]['componentRef']['revision'] = '0' * 40
            (bad_snapshot / 'snapshot-index.json').write_text(json.dumps(index))
            reject(family + '-substituted-snapshot-component',
                   lambda: verify_source_snapshots(bad_snapshot, contract), 'componentRef mismatch')
        missing = dict(manifest['carrier'], path=(work / 'absent.bundle').as_posix())
        reject('missing-carrier', lambda: check_file(missing))
        damaged = work / 'damaged.bundle'
        raw = (ROOT / manifest['carrier']['path']).read_bytes()
        damaged.write_bytes(bytes([raw[0] ^ 1]) + raw[1:])
        damaged_record = dict(manifest['carrier'], path=damaged.as_posix())
        reject('same-size-carrier-corruption', lambda: check_file(damaged_record))
    result = {'status': 'RC7 SOURCE FREEZE VERIFY GREEN', 'versionOutput': version.strip(),
              'cleanTaskOwnedRevision': manifest['freezeRevision'],
              'validatedLiveSourceEqualsCleanSource': True, 'fixedPoints': fixed_points,
              'negativeControlsRejected': controls, 'sharedMainUnchanged': True,
              'installedDOrM5QOrReleaseQualificationGranted': False}
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
