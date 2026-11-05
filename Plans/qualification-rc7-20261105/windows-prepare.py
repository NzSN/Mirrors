"""Runs only in the owned qualification stage on Windows; no production writes."""
import hashlib
import json
import subprocess
import zipfile
from pathlib import Path, PurePosixPath

STAGE = Path(r'D:\ModelMirrors\staging\qualification-rc7-20261105')
GIT = r'C:\Program Files\Git\cmd\git.exe'


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1048576), b''):
            h.update(chunk)
    return h.hexdigest()


def git(*args):
    return subprocess.run([GIT, '-c', 'core.autocrlf=false', '-c', 'core.filemode=false',
        *map(str, args)], capture_output=True, text=True, check=True).stdout.strip()


def main():
    record = json.loads((STAGE / 'windows-inputs.json').read_text())
    for entry in record['artifacts']:
        path = STAGE / Path(entry['path']).name
        assert path.stat().st_size == entry['bytes'] and sha(path) == entry['sha256']
    for name, revision in [('Mirrors', record['sourceRevision']), ('MirrorCPP', record['cppRevision']),
                           ('MirrorRust', record['rustRevision'])]:
        source = STAGE / name
        assert not source.exists()
        git('clone', STAGE / (name + '.bundle'), source)
        git('-C', source, 'remote', 'set-url', 'origin',
            'https://github.com/NzSN/' + name + '.git')
        assert git('-C', source, 'rev-parse', 'HEAD') == revision
        assert git('-C', source, 'status', '--porcelain=v1') == ''
    mirrors = STAGE / 'Mirrors'
    package = mirrors / '.lake/packages/batteries'
    package.parent.mkdir(parents=True)
    git('clone', mirrors / 'third_party/batteries/batteries-v4.33.0.bundle', package)
    git('-C', package, 'remote', 'set-url', 'origin', 'https://github.com/leanprover-community/batteries')
    assert git('-C', package, 'rev-parse', 'HEAD') == '4488d40d070b9700d4d5a6aa342f0d40c31b2a2d'
    prefix = STAGE / 'cpp-prefix'
    prefix.mkdir()
    with zipfile.ZipFile(STAGE / 'cpp-dependencies.zip') as archive:
        for name in archive.namelist():
            path = PurePosixPath(name)
            assert not path.is_absolute() and '..' not in path.parts and ':' not in name
        archive.extractall(prefix)
    tmp = STAGE / 'tmp'
    tmp.mkdir()
    with (STAGE / 'prepared.json').open('x') as f:
        f.write(json.dumps({'sourceRevision': record['sourceRevision'], 'cppRevision': record['cppRevision'],
            'sourcesCleanBeforeBuild': True, 'offlineInputsVerified': True}, indent=2) + '\n')
    print('WINDOWS QUALIFICATION SOURCES PREPARED')


if __name__ == '__main__':
    main()
