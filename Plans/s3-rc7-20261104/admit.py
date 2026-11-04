#!/usr/bin/env python3
"""Admit exact published rc.7 source and a new local-only packaging tag."""
import gzip
import hashlib
import json
import os
import subprocess
import sys
import tarfile
from pathlib import Path

from common import COMMIT, OUT, PLAN, ROOT, SOURCE, TAG, TREE, identity, run, write


def main():
    assert (OUT / 'remote-refs.txt').read_text().splitlines() == [
        '679b2ebfb8801eacae319ebf503960aa0539b389\trefs/heads/main']
    sys.path.insert(0, str(ROOT / 'tools/evidence'))
    from source_policy import is_planning_documentation
    delta = run('publication-delta', ['git', 'diff', '--name-only', COMMIT, 'HEAD']).splitlines()
    assert delta and all(is_planning_documentation('mirrors', p) for p in delta)
    tags_before = subprocess.run(['git', 'show-ref', '--tags'], capture_output=True, check=True).stdout
    assert b'refs/tags/v0.2.0-rc.7' not in tags_before
    (OUT / 'shared-tags-before.txt').write_bytes(tags_before)
    run('source-clone', ['git', 'clone', '--no-hardlinks', ROOT, SOURCE])
    run('source-checkout', ['git', '-C', SOURCE, 'checkout', '--detach', COMMIT])
    assert run('source-tree', ['git', '-C', SOURCE, 'rev-parse', 'HEAD^{tree}']) == TREE
    assert run('source-status', ['git', '-C', SOURCE, 'status', '--porcelain=v1']) == ''
    author = run('tag-author-name', ['git', 'config', 'user.name'])
    email = run('tag-author-email', ['git', 'config', 'user.email'])
    run('tag-create', ['git', '-c', 'user.name=' + author, '-c', 'user.email=' + email,
                       '-C', SOURCE, 'tag', '-a', TAG, COMMIT,
                       '-m', 'Local-only rc.7 package construction; no release publication'])
    tag_object = run('tag-object', ['git', '-C', SOURCE, 'rev-parse', 'refs/tags/' + TAG])
    assert run('tag-type', ['git', '-C', SOURCE, 'cat-file', '-t', tag_object]) == 'tag'
    assert run('tag-peel', ['git', '-C', SOURCE, 'rev-parse', TAG + '^{commit}']) == COMMIT
    sys.path.insert(0, str(ROOT / 'tools/release'))
    import release
    release_identity = release.identity(SOURCE, TAG)
    assert release_identity['embeddedVersion'] == '0.2.0-rc.7'
    archive_root = OUT / 'archive'
    archive_root.mkdir(mode=0o700)
    tar_path = archive_root / 'source.tar'
    archive = archive_root / ('mirrors-' + TAG + '-source.tar.gz')
    with tar_path.open('xb') as output:
        subprocess.run(['git', '-C', str(SOURCE), 'archive', '--format=tar',
                        '--prefix=mirrors-' + TAG + '/', TAG], stdout=output, check=True)
    with tar_path.open('rb') as src, archive.open('xb') as dst:
        with gzip.GzipFile(filename='', fileobj=dst, mode='wb', mtime=0) as gz:
            import shutil
            shutil.copyfileobj(src, gz)
    rows = []
    prefix = 'mirrors-' + TAG + '/'
    with tarfile.open(archive, 'r:gz') as handle:
        for member in handle:
            assert member.name.startswith(prefix) or member.name == prefix.rstrip('/')
            assert member.isdir() or member.isfile()
            if member.isfile():
                data = handle.extractfile(member).read()
                rows.append({'path': member.name[len(prefix):], 'bytes': len(data),
                             'sha256': hashlib.sha256(data).hexdigest()})
    rows.sort(key=lambda r: r['path'])
    write(archive_root / 'source-manifest.json', {'commit': COMMIT, 'tree': TREE,
        'tag': TAG, 'tagObject': tag_object, 'fileCount': len(rows), 'files': rows})
    package = SOURCE / '.lake/packages/batteries'
    package.parent.mkdir(mode=0o700, parents=True)
    bundle = SOURCE / 'third_party/batteries/batteries-v4.33.0.bundle'
    assert identity(bundle)['sha256'] == 'f6efbfeb6353195c3318e3ef6e46d3e4e87897659989cd7322156d9e8a5f1cd3'
    run('batteries-offline-clone', ['git', 'clone', bundle, package])
    run('batteries-origin', ['git', '-C', package, 'remote', 'set-url', 'origin',
                           'https://github.com/leanprover-community/batteries'])
    assert run('batteries-revision', ['git', '-C', package, 'rev-parse', 'HEAD']) == '4488d40d070b9700d4d5a6aa342f0d40c31b2a2d'
    assert run('batteries-tree', ['git', '-C', package, 'rev-parse', 'HEAD^{tree}']) == '5a1de86f7997958aaffec998882c29006b688d1e'
    run('batteries-fsck', ['git', '-C', package, 'fsck', '--full'])
    assert run('batteries-status', ['git', '-C', package, 'status', '--porcelain=v1']) == ''
    assert subprocess.run(['git', 'show-ref', '--tags'], capture_output=True, check=True).stdout == tags_before
    write(PLAN / 'source-identity.json', {'schema': 'mirrors.s3-rc7.source/v1',
        'published': False, 'deployed': False, 'tag': TAG, 'tagObject': tag_object,
        'tagScope': 'annotated local-only tag in task-owned clone', 'commit': COMMIT,
        'tree': TREE, 'releaseIdentity': release_identity, 'sourceArchive': identity(archive),
        'sourceManifest': identity(archive_root / 'source-manifest.json'), 'fileCount': len(rows),
        'offlineBatteries': {'revision': '4488d40d070b9700d4d5a6aa342f0d40c31b2a2d',
                            'tree': '5a1de86f7997958aaffec998882c29006b688d1e', 'bundle': identity(bundle)},
        'sharedTagRefsUnchanged': True, 'remoteRc7TagObservedAbsent': True})
    print('SOURCE/TAG ADMISSION GREEN files=' + str(len(rows)), flush=True)


if __name__ == '__main__':
    main()
