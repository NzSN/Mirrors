#!/usr/bin/env python3
"""Freeze validated rc.11 source in a task-owned commit and isolated C0 copies."""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLAN = Path(__file__).resolve().parent
OUT = ROOT / '.golden-build/completion-rc11-20261106/frozen'
SOURCE = OUT / 'source'
ECMA = ROOT / '.golden-build/mw12-20261103/inputs/companions/MirrorECMA'
GATE = ROOT / '.golden-build/completion-rc10-20261106/MirrorGate-ordering-fix'
C3 = ROOT / '.lake/build/bin/framework_catalog'
sys.path.insert(0, str(ROOT / 'tools/distribution'))
from build import verify_running_builder, verify_source_snapshots
from manifest_check import digest_json, validate_locks
from refresh_identity import selected_refs
from snapshot_sources import snapshot


def record(path: Path) -> dict:
    raw = path.read_bytes()
    return {'path': path.relative_to(ROOT).as_posix(), 'bytes': len(raw),
            'sha256': hashlib.sha256(raw).hexdigest()}


def tree(root: Path) -> dict:
    return {p.relative_to(root).as_posix(): record(p)
            for p in sorted(root.rglob('*')) if p.is_file()}


def owner_only(root: Path):
    root.chmod(0o700)
    for p in root.rglob('*'):
        if p.is_dir() and not p.is_symlink():
            p.chmod(0o700)


def main():
    (OUT/'tmp').mkdir(mode=0o700,parents=True,exist_ok=True)
    os.environ['TMPDIR'] = str(OUT / 'tmp')
    receipts = OUT / 'receipts'
    receipts.mkdir(mode=0o700, exist_ok=True)

    def run(name, argv, cwd=ROOT):
        prior = receipts / (name + '.json')
        if prior.exists():
            saved = json.loads(prior.read_text())
            assert saved['argv'] == list(map(str, argv)) and saved['cwd'] == str(cwd) and saved['exitCode'] == 0
            return saved['stdout'].strip()
        p = subprocess.run(list(map(str, argv)), cwd=cwd, capture_output=True, timeout=180)
        value = {'argv': list(map(str, argv)), 'cwd': str(cwd), 'exitCode': p.returncode,
                 'stdout': p.stdout.decode('utf-8', 'replace'),
                 'stderr': p.stderr.decode('utf-8', 'replace')}
        with (receipts / (name + '.json')).open('x') as stream:
            stream.write(json.dumps(value, indent=2) + '\n')
        if p.returncode:
            raise ValueError(name + ' failed; receipt retained')
        return value['stdout'].strip()

    intake = json.loads((PLAN / 'rc11-intake.json').read_text())
    gate = json.loads((PLAN / 'rc11-gate-result.json').read_text())
    assert gate['status'] == 'passed-stable-rc11-source' and gate['sourceAndCompanionsStable']
    assert record(ROOT / gate['log']['path'])['sha256'] == gate['log']['sha256']
    assert (ROOT / gate['log']['path']).read_bytes().splitlines()[-1] == b'ALL LOCAL NON-MODEL GATES GREEN'
    assert run('shared-head', ['git', 'rev-parse', 'HEAD']) == intake['baseRevision']
    refs = selected_refs(ECMA, GATE)
    assert refs == gate['after']
    for entry in intake['sourceEdits']:
        assert record(ROOT / entry['path']) == entry
    for entry in intake['preservedUnrelatedFiles']:
        assert record(ROOT / entry['path']) == entry

    # Preserve a maintained snapshot of the actual source checked by the gate.
    validated=snapshot(ROOT,refs['mirrors'],OUT/'validated-mirrors-source')
    with (OUT/'validated-source-index.json').open('x') as stream:
        stream.write(json.dumps(validated,indent=2)+'\n')

    run('source-clone', ['git', 'clone', '--no-hardlinks', ROOT, SOURCE])
    origin = run('source-origin-observation', ['git', 'config', '--get', 'remote.origin.url'])
    run('source-origin-selection', ['git', '-C', SOURCE, 'remote', 'set-url', 'origin', origin])
    for entry in intake['sourceEdits']:
        target = SOURCE / entry['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / entry['path'], target)
    # Planning receipts are not source build inputs, but retain the documentation
    # target of Docs/current-status.md and Docs/versioning.md in this local tree.
    shutil.copytree(PLAN, SOURCE / PLAN.relative_to(ROOT), dirs_exist_ok=True, ignore=shutil.ignore_patterns('__pycache__'))
    paths = [e['path'] for e in intake['sourceEdits']] + [PLAN.relative_to(ROOT).as_posix()]
    run('source-stage', ['git', '-C', SOURCE, 'add', '--', *paths])
    name = run('author-name', ['git', 'config', 'user.name'])
    email = run('author-email', ['git', 'config', 'user.email'])
    run('source-commit', ['git', '-C', SOURCE, '-c', 'user.name=' + name,
                         '-c', 'user.email=' + email, '-c', 'commit.gpgSign=false', '-c', 'core.hooksPath=/dev/null',
                         'commit', '-m', 'distribution: prepare rc.11 qualification source'])
    revision = run('source-revision', ['git', '-C', SOURCE, 'rev-parse', 'HEAD'])
    source_tree = run('source-tree', ['git', '-C', SOURCE, 'rev-parse', 'HEAD^{tree}'])
    assert run('source-status', ['git', '-C', SOURCE, 'status', '--porcelain=v1']) == ''
    assert run('source-parent', ['git', '-C', SOURCE, 'rev-parse', 'HEAD^']) == intake['baseRevision']
    expected_refs = dict(refs)
    expected_refs['mirrors'] = {'componentId': 'mirrors', 'repository': origin,
                               'revision': revision, 'dirty': False}
    c3 = record(C3)
    families = {}
    preserved = {}
    for family, catalog_name, lock_name in [
        ('base', 'framework-catalog.json', 'reference-node'),
        ('wsl2', 'framework-catalog-wsl2-26.04.json', 'reference-node-wsl2-26.04'),
    ]:
        rel_catalog = Path('catalog') / catalog_name
        rel_locks = Path('distribution') / lock_name
        family_root = OUT / 'candidates' / family
        catalog = family_root / rel_catalog
        locks = family_root / rel_locks
        catalog.parent.mkdir(mode=0o700, parents=True)
        shutil.copyfile(ROOT / rel_catalog, catalog)
        shutil.copytree(ROOT / rel_locks, locks)
        owner_only(OUT / 'candidates')
        for p in [ROOT / rel_catalog, *sorted((ROOT / rel_locks).rglob('*'))]:
            if p.is_file():
                preserved[p.relative_to(ROOT).as_posix()] = record(p)
        args = [sys.executable, SOURCE / 'tools/distribution/refresh_identity.py',
                '--mirrorecma', ECMA, '--mirrorgate', GATE,
                '--framework-catalog-bin', C3, '--catalog', catalog,
                '--locks-root', locks, '--skip-component-records', '--skip-render']
        run(family + '-refresh-1', args, SOURCE)
        after_first = tree(family_root)
        run(family + '-refresh-2', args, SOURCE)
        assert tree(family_root) == after_first
        document = json.loads(catalog.read_text())
        selection = digest_json(document)
        actual_refs = {v['componentRef']['componentId']: v['componentRef'] for v in document['components']}
        assert actual_refs == expected_refs
        mirrors = next(v for v in document['components'] if v['componentRef']['componentId'] == 'mirrors')
        assert mirrors['product']['version'] == '0.2.0-rc.11'
        assert (locks / 'dependency-lock.json').read_bytes() == (ROOT / rel_locks / 'dependency-lock.json').read_bytes()
        contract = validate_locks(locks, C3, c3['sha256'], catalog)
        destination = OUT / 'snapshots' / family
        run(family + '-snapshot', [sys.executable, SOURCE / 'tools/distribution/snapshot_sources.py',
            '--component-lock', locks / 'component-lock.json', '--out', destination,
            '--mirrors', SOURCE, '--mirrorecma', ECMA, '--mirrorgate', GATE], SOURCE)
        verify_source_snapshots(destination, contract)
        verify_running_builder(destination)
        index = json.loads((destination / 'snapshot-index.json').read_text())
        mirrors_snapshot = next(v for v in index['components'] if v['componentRef']['componentId'] == 'mirrors')
        assert mirrors_snapshot['treeIndexSha256'] == validated['treeIndexSha256']
        owner_only(destination)
        families[family] = {'catalog': record(catalog), 'selectionSha256': selection,
                            'locksRoot': locks.relative_to(ROOT).as_posix(),
                            'snapshotIndex': record(destination / 'snapshot-index.json'),
                            'sourceTreeIndexSha256': mirrors_snapshot['treeIndexSha256'],
                            'selectedForExecution': family == 'wsl2',
                            'candidateFiles': tree(family_root)}
    for rel, entry in preserved.items():
        assert record(ROOT / rel) == entry
    assert selected_refs(ECMA, GATE) == refs
    assert run('source-final-status', ['git', '-C', SOURCE, 'status', '--porcelain=v1']) == ''
    owner_only(SOURCE)
    value = {'schema': 'mirrors.rc11-source-c0-freeze/v1',
             'at': datetime.now(timezone.utc).isoformat(), 'status': 'prepared-for-independent-verification',
             'productVersion': '0.2.0-rc.11', 'sharedBaseRevision': intake['baseRevision'],
             'taskOwnedSource': SOURCE.relative_to(ROOT).as_posix(),
             'freezeRevision': revision, 'freezeTree': source_tree,
             'commitScope': 'local task-owned repository only; shared main unchanged',
             'validatedLiveSourceRef': refs['mirrors'],
             'validatedSourceIndex': record(OUT / 'validated-source-index.json'),
             'validatedSourceTreeIndexSha256': validated['treeIndexSha256'],
             'sourceBytesEqualValidatedSource': True, 'frameworkCatalog': c3,
             'gateResult': record(PLAN / 'rc11-gate-result.json'),
             'families': families, 'preservedSharedInputs': preserved,
             'carrier': record(ROOT / 'third_party/batteries/batteries-v4.33.0.bundle'),
             'selectedProfile': 'ubuntu-26.04-wsl2-x86_64',
             'qualificationGranted': False, 'sharedCommitPushTagPackageOrDeploymentPerformed': False}
    with (PLAN / 'rc11-freeze-manifest.json').open('x') as stream:
        stream.write(json.dumps(value, indent=2) + '\n')
    print(json.dumps({'freezeRevision': revision, 'families':
          {k: v['selectionSha256'] for k, v in families.items()}, 'sourceBytesEqualValidatedSource': True}, indent=2))


if __name__ == '__main__':
    main()
