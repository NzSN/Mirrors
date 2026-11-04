#!/usr/bin/env python3
"""Create and independently verify an offline carrier at the pinned source revision."""
from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / '.golden-build/batteries-recovery-20261104'
REVISION = '4488d40d070b9700d4d5a6aa342f0d40c31b2a2d'
TREE = '5a1de86f7997958aaffec998882c29006b688d1e'
OLD_SHA = '73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a'


def identity(path: Path) -> dict:
    raw = path.read_bytes()
    return {'path': path.relative_to(ROOT).as_posix(), 'bytes': len(raw),
            'sha256': hashlib.sha256(raw).hexdigest()}


def main():
    receipts = []

    def run(name, argv):
        p = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True, timeout=60)
        row = {'name': name, 'argv': list(map(str, argv)), 'exitCode': p.returncode,
               'stdout': p.stdout, 'stderr': p.stderr}
        with (OUT / (name + '.json')).open('x') as f:
            f.write(json.dumps(row, indent=2) + '\n')
        receipts.append(identity(OUT / (name + '.json')))
        if p.returncode:
            raise ValueError(f'{name} failed; receipt retained')
        return p.stdout.strip()

    selected = ROOT / '.lake/packages/batteries'
    assert run('input-revision', ['git', '-C', selected, 'rev-parse', 'HEAD']) == REVISION
    assert run('input-tree', ['git', '-C', selected, 'rev-parse', 'HEAD^{tree}']) == TREE
    assert run('input-status', ['git', '--no-optional-locks', '-C', selected, 'status', '--porcelain=v1']) == ''
    assert run('input-shallow', ['git', '-C', selected, 'rev-parse', '--is-shallow-repository']) == 'false'
    run('input-fsck', ['git', '-C', selected, 'fsck', '--full'])
    git_version = run('git-version', ['git', '--version'])
    source = OUT / 'generation-source'
    run('generation-clone', ['git', 'clone', '--no-hardlinks', str(selected), str(source)])
    run('generation-checkout', ['git', '-C', source, 'checkout', '--detach', REVISION])
    candidate = OUT / 'candidate.bundle'
    generation_argv = ['git', '-C', source, '-c', 'pack.threads=1', '-c', 'pack.compression=9',
                       'bundle', 'create', candidate, 'HEAD']
    run('generation', generation_argv)
    candidate_identity = identity(candidate)
    run('bundle-verify', ['git', '-C', source, 'bundle', 'verify', candidate])
    heads = run('bundle-heads', ['git', 'bundle', 'list-heads', candidate])
    assert heads.splitlines() == [REVISION + ' HEAD']
    clone = OUT / 'independent-clone'
    run('independent-clone', ['git', 'clone', '--no-local', str(candidate), str(clone)])
    assert run('independent-revision', ['git', '-C', clone, 'rev-parse', 'HEAD']) == REVISION
    assert run('independent-tree', ['git', '-C', clone, 'rev-parse', 'HEAD^{tree}']) == TREE
    assert run('independent-status', ['git', '--no-optional-locks', '-C', clone, 'status', '--porcelain=v1']) == ''
    assert run('independent-shallow', ['git', '-C', clone, 'rev-parse', '--is-shallow-repository']) == 'false'
    run('independent-fsck', ['git', '-C', clone, 'fsck', '--full'])
    history_count = run('independent-history-count', ['git', '-C', clone, 'rev-list', '--count', 'HEAD'])
    assert int(history_count) == 1309
    assert (clone / 'LICENSE').read_bytes() == (ROOT / 'third_party/batteries/LICENSE').read_bytes()
    destination = ROOT / 'third_party/batteries/batteries-v4.33.0.bundle'
    with candidate.open('rb') as src, destination.open('xb') as dst:
        shutil.copyfileobj(src, dst)
    destination.chmod(0o444)
    assert identity(destination)['sha256'] == candidate_identity['sha256']
    candidate.chmod(0o444)
    result = {'schema': 'mirrors.batteries-carrier-recovery/v1',
              'recordedAt': datetime.now(timezone.utc).isoformat(),
              'outcome': 'regenerated-from-verified-source',
              'originalBytesReproduced': candidate_identity['sha256'] == OLD_SHA,
              'previousSha256': OLD_SHA, 'artifact': identity(destination),
              'source': {'revision': REVISION, 'tree': TREE, 'clean': True,
                         'completeHistory': True, 'historyCount': int(history_count)},
              'generation': {'argv': list(map(str, generation_argv)), 'gitVersion': git_version,
                             'reproducibleCarrierClaim': False},
              'license': identity(ROOT / 'third_party/batteries/LICENSE'), 'receipts': receipts,
              'dependencyLocksUpdated': False, 'frameworkQualificationGranted': False}
    with (ROOT / 'Plans/batteries-recovery-20261104/carrier.json').open('x') as f:
        f.write(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: result[k] for k in ('outcome', 'originalBytesReproduced', 'artifact', 'source')}, indent=2))


if __name__ == '__main__':
    main()
