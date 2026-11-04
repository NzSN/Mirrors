#!/usr/bin/env python3
"""Independently verify the recovered carrier and lock bindings, with negative controls."""
import copy
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLAN = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'tools/distribution'))
from distribution_lib import sha256_file
from manifest_check import digest_json, validate_locks

REVISION = '4488d40d070b9700d4d5a6aa342f0d40c31b2a2d'
TREE = '5a1de86f7997958aaffec998882c29006b688d1e'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check_file(path, record):
    require(sha256_file(path) == (record['bytes'], record['sha256']), 'artifact bytes differ: ' + str(path))


def check_source(record):
    require(record['revision'] == REVISION and record['tree'] == TREE,
            'source identity differs')


def main():
    carrier = json.loads((PLAN / 'carrier.json').read_text())
    artifact = carrier['artifact']
    path = ROOT / artifact['path']
    check_file(path, artifact)
    check_source(carrier['source'])
    require(carrier['originalBytesReproduced'] is False, 'unearned original-byte recovery claim')
    require(carrier['generation']['reproducibleCarrierClaim'] is False, 'unearned reproducibility claim')
    for receipt in carrier['receipts']:
        check_file(ROOT / receipt['path'], receipt)
        require(json.loads((ROOT / receipt['path']).read_text())['exitCode'] == 0, 'carrier command failed')
    update = json.loads((PLAN / 'lock-update.json').read_text())
    verifier = ROOT / '.lake/build/bin/framework_catalog'
    for entry in update['roots']:
        locks = ROOT / entry['profileRoot']
        before = PLAN / 'before' / entry['profileRoot']
        current = json.loads((locks / 'dependency-lock.json').read_text())
        expected = json.loads((before / 'dependency-lock.json').read_text())
        dependency = next(d for d in expected['dependencies'] if d['artifactId'] == 'lean-batteries-source')
        require(dependency['sha256'] == carrier['previousSha256'], 'previous selection differs')
        dependency.update(bytes=artifact['bytes'], sha256=artifact['sha256'])
        require(current == expected, 'unrelated dependency change')
        for name in ('profiles.json', 'component-lock.json'):
            require((locks / name).read_bytes() == (before / name).read_bytes(), 'unrelated lock change')
        catalog = ROOT / 'catalog' / ('framework-catalog-wsl2-26.04.json'
                   if locks.name.endswith('wsl2-26.04') else 'framework-catalog.json')
        contract = validate_locks(locks, verifier, update['verifierSha256'], catalog)
        for profile in ('checked-replay-local', 'checked-replay-gate'):
            manifest = json.loads((locks / f'fixtures/distribution-manifest.{profile}.valid.json').read_text())
            index = json.loads((locks / f'fixtures/cache-index.{profile}.valid.json').read_text())
            require({v['inputId']: v for v in manifest['buildInputs']} == contract['buildInputs'],
                    'fixture lock inputs differ')
            require(index['distributionManifestSha256'] == digest_json(manifest), 'fixture digest differs')
    os.environ['TMPDIR'] = str(ROOT / '.golden-build/batteries-recovery-20261104/tmp')
    with tempfile.TemporaryDirectory(prefix='independent-recovery-') as temporary:
        work = Path(temporary)

        def git(*args):
            p = subprocess.run(['git', *map(str, args)], capture_output=True, text=True, timeout=60)
            require(p.returncode == 0, p.stderr)
            return p.stdout.strip()

        clone = work / 'clone'
        git('clone', '--no-local', path, clone)
        require(git('-C', clone, 'rev-parse', 'HEAD') == REVISION, 'cloned revision differs')
        require(git('-C', clone, 'rev-parse', 'HEAD^{tree}') == TREE, 'cloned tree differs')
        require(git('-C', clone, 'status', '--porcelain=v1') == '', 'clone is dirty')
        require(git('-C', clone, 'rev-parse', '--is-shallow-repository') == 'false', 'incomplete history')
        require(git('-C', clone, 'rev-list', '--count', 'HEAD') == '1309', 'history count differs')
        git('-C', clone, 'fsck', '--full')
        bundle_check = subprocess.run(['git', '-C', str(clone), 'bundle', 'verify', str(path)],
                                      capture_output=True, text=True, timeout=60)
        require(bundle_check.returncode == 0 and 'complete history' in (bundle_check.stdout + bundle_check.stderr),
                'bundle integrity or complete-history check failed')
        require((clone / 'LICENSE').read_bytes() == (ROOT / 'third_party/batteries/LICENSE').read_bytes(),
                'upstream license differs')
        rejected = []

        def reject(name, action):
            try:
                action()
            except (ValueError, OSError):
                rejected.append(name)
                return
            raise ValueError('negative control accepted: ' + name)

        reject('missing-carrier', lambda: check_file(work / 'absent', artifact))
        damaged = work / 'damaged.bundle'
        raw = path.read_bytes()
        damaged.write_bytes(bytes([raw[0] ^ 1]) + raw[1:])
        reject('same-size-damaged-carrier', lambda: check_file(damaged, artifact))
        reject('previous-pin-on-replacement', lambda: check_file(path,
               {'bytes': 3739542, 'sha256': carrier['previousSha256']}))
        changed = copy.deepcopy(carrier['source'])
        changed['revision'] = '0' * 40
        reject('changed-source-revision', lambda: check_source(changed))
    print(json.dumps({'status': 'RECOVERY VERIFY GREEN', 'negativeControlsRejected': rejected,
                      'sourceRevisionChanged': False, 'newCandidateRequired': True,
                      'frameworkQualificationGranted': False}, indent=2))


if __name__ == '__main__':
    main()
