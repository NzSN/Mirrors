"""Runs on Windows: exact source extraction, offline dependency, and source checks."""
import hashlib
import json
import os
import subprocess
import sys
import tarfile
from pathlib import Path, PurePosixPath

STAGE = Path(r'D:\ModelMirrors\staging\s3-rc7-20261104-f525c63')
SOURCE = STAGE / 'mirrors-v0.2.0-rc.7'
GIT = r'C:\Program Files\Git\cmd\git.exe'
REV = '4488d40d070b9700d4d5a6aa342f0d40c31b2a2d'
TREE = '5a1de86f7997958aaffec998882c29006b688d1e'


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def save(path, data):
    with path.open('x', encoding='utf-8') as stream:
        stream.write(json.dumps(data, indent=2) + '\n')


def git(*args):
    return subprocess.run([GIT, '-c', 'core.autocrlf=false', '-c', 'core.filemode=false',
                           *map(str, args)], capture_output=True, text=True, check=True).stdout.strip()


def manifest(label):
    expected = json.loads((STAGE / 'source-manifest.json').read_text())
    wanted = {row['path']: row for row in expected['files']}
    rows = []
    for directory, dirs, files in os.walk(SOURCE):
        if Path(directory) == SOURCE:
            dirs[:] = [d for d in dirs if d != '.lake']
        for name in files:
            path = Path(directory) / name
            if path.is_symlink():
                raise ValueError('linked source file')
            rows.append({'path': path.relative_to(SOURCE).as_posix(),
                         'bytes': path.stat().st_size, 'sha256': sha(path)})
    rows.sort(key=lambda row: row['path'])
    seen = {row['path']: row for row in rows}
    missing = sorted(set(wanted) - set(seen))
    changed = sorted(name for name in wanted if name in seen and wanted[name] != seen[name])
    extras = sorted(set(seen) - set(wanted))
    allowed = [] if label == 'before' else [
        '.golden-build/model-interface-rust/CorpusMirror.generated.rs',
        '.golden-build/model-interface-rust/MultiMirror.generated.rs']
    passed = not missing and not changed and extras == allowed
    with (STAGE / ('source-' + label + '.jsonl')).open('x', encoding='utf-8') as f:
        for row in rows:
            f.write(json.dumps(row, separators=(',', ':')) + '\n')
    record = {'label': label, 'expectedFiles': len(wanted), 'observedFiles': len(rows),
              'missing': missing, 'changed': changed, 'extraOutsideLake': extras,
              'matched': passed}
    save(STAGE / ('windows-source-' + label + '.json'), record)
    if not passed:
        raise ValueError(json.dumps(record))
    print('SOURCE ' + label + ' VERIFIED ' + str(len(wanted)))


def prepare():
    identity = json.loads((STAGE / 'source-identity.json').read_text())
    archive = STAGE / 'mirrors-v0.2.0-rc.7-source.tar.gz'
    assert sha(archive) == identity['sourceArchive']['sha256']
    assert not SOURCE.exists()
    expected = json.loads((STAGE / 'source-manifest.json').read_text())
    assert expected['fileCount'] == identity['fileCount']
    paths = [row['path'].casefold() for row in expected['files']]
    assert len(paths) == len(set(paths))
    prefix = 'mirrors-v0.2.0-rc.7/'
    with tarfile.open(archive) as handle:
        for member in handle.getmembers():
            path = PurePosixPath(member.name)
            assert not path.is_absolute() and '..' not in path.parts
            assert ':' not in member.name and '\\' not in member.name
            assert member.isdir() or member.isfile()
            assert member.name == prefix.rstrip('/') or member.name.startswith(prefix)
        handle.extractall(STAGE)
    assert not (SOURCE / '.git').exists()
    manifest('before')
    bundle = SOURCE / 'third_party/batteries/batteries-v4.33.0.bundle'
    assert sha(bundle) == 'f6efbfeb6353195c3318e3ef6e46d3e4e87897659989cd7322156d9e8a5f1cd3'
    package = SOURCE / '.lake/packages/batteries'
    package.parent.mkdir(parents=True)
    git('clone', bundle, package)
    git('-C', package, 'remote', 'set-url', 'origin', 'https://github.com/leanprover-community/batteries')
    assert git('-C', package, 'rev-parse', 'HEAD') == REV
    assert git('-C', package, 'rev-parse', 'HEAD^{tree}') == TREE
    assert git('-C', package, 'status', '--porcelain=v1') == ''
    git('-C', package, 'fsck', '--full')
    save(STAGE / 'windows-offline-dependency.json', {
        'revision': REV, 'tree': TREE, 'sha256': sha(bundle), 'bytes': bundle.stat().st_size,
        'gitClean': True, 'gitFsckPassed': True, 'networkAcquisitionPerformed': False})
    print('OFFLINE BATTERIES VERIFIED')


if __name__ == '__main__':
    if sys.argv[1] == 'prepare':
        prepare()
    elif sys.argv[1] == 'after':
        manifest('after')
    else:
        raise SystemExit('unknown operation')
