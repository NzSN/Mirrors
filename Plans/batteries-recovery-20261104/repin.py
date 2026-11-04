#!/usr/bin/env python3
"""Bind both selected lock roots to the independently verified recovery carrier."""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLAN = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'tools/distribution'))
from distribution_lib import sha256_file
from manifest_check import digest_json, validate_locks
from refresh_identity import update_locks


def main():
    carrier = json.loads((PLAN / 'carrier.json').read_text())
    artifact = carrier['artifact']
    assert sha256_file(ROOT / artifact['path']) == (artifact['bytes'], artifact['sha256'])
    before = PLAN / 'before'
    before.mkdir(exist_ok=False)
    verifier = ROOT / '.lake/build/bin/framework_catalog'
    verifier_sha = sha256_file(verifier)[1]
    assert verifier_sha == '5a64a5bd40e999b20dd8268f2846c0f5ad5359067db9f014379c150e27d76126'
    outcomes = []
    for name, catalog_name in [('reference-node', 'framework-catalog.json'),
                                ('reference-node-wsl2-26.04', 'framework-catalog-wsl2-26.04.json')]:
        locks = ROOT / 'distribution' / name
        catalog_path = ROOT / 'catalog' / catalog_name
        validate_locks(locks, verifier, verifier_sha, catalog_path)
        tracked = [locks / n for n in ('profiles.json', 'component-lock.json', 'dependency-lock.json')]
        tracked += list(sorted((locks / 'fixtures').glob('*.valid.json')))
        original = {p: p.read_bytes() for p in tracked}
        for path, data in original.items():
            dest = before / path.relative_to(ROOT)
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)
        catalog_before = catalog_path.read_bytes()
        value = json.loads((locks / 'dependency-lock.json').read_text())
        old = next(x for x in value['dependencies'] if x['artifactId'] == 'lean-batteries-source')
        old_identity = dict(old)
        assert old['version'] == carrier['source']['revision']
        assert old['sha256'] == carrier['previousSha256']
        old.update(bytes=artifact['bytes'], sha256=artifact['sha256'])
        (locks / 'dependency-lock.json').write_text(json.dumps(value, indent=2) + '\n')
        components = json.loads(original[locks / 'component-lock.json'])
        refs = {v['componentRef']['componentId']: v['componentRef'] for v in components['components']}
        catalog = json.loads(catalog_before)
        update_locks(refs, digest_json(catalog), root=locks, catalog_path=catalog_path)
        assert (locks / 'profiles.json').read_bytes() == original[locks / 'profiles.json']
        assert (locks / 'component-lock.json').read_bytes() == original[locks / 'component-lock.json']
        assert catalog_path.read_bytes() == catalog_before
        validate_locks(locks, verifier, verifier_sha, catalog_path)
        changed = [{'path': p.relative_to(ROOT).as_posix(),
                    'beforeSha256': hashlib.sha256(data).hexdigest(),
                    'afterSha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                   for p, data in original.items() if p.read_bytes() != data]
        outcomes.append({'profileRoot': locks.relative_to(ROOT).as_posix(),
                         'previousDependency': old_identity, 'dependency': old,
                         'catalogAndComponentAndProfileIdentitiesPreserved': True,
                         'locksValidated': True, 'changedFiles': changed})
    with (PLAN / 'lock-update.json').open('x') as stream:
        stream.write(json.dumps({'verifierSha256': verifier_sha, 'roots': outcomes,
                                'frameworkQualificationGranted': False}, indent=2) + '\n')
    print('RECOVERY DEPENDENCY LOCKS VERIFIED; SOURCE RE-FREEZE STILL REQUIRED')


if __name__ == '__main__':
    main()
