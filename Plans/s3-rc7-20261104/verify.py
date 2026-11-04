#!/usr/bin/env python3
"""Independent source, Linux/Windows archive, gate-log and PE verification."""
import copy
import hashlib
import importlib.util
import json
import subprocess
import tarfile
import zipfile
from pathlib import Path

from common import COMMIT, OUT, PLAN, ROOT, SOURCE, TAG, TREE, identity

WINDOWS_GATES = ['fixtures_replay', 'diff_cross', 'model_interface_spec', 'stdio_smoke',
                 'transport_spec', 'jobstore_spec', 'async_resource_spec', 'dpm_sync_spec']
LINUX_GATES = WINDOWS_GATES[:5] + ['check-client-framing.py', 'relocated-binary-cli-smoke']


def require(value, message):
    if not value:
        raise ValueError(message)


def load(path):
    return json.loads(Path(path).read_text())


def git(*args):
    return subprocess.run(['git', '-C', str(SOURCE), *args],
                          capture_output=True, check=True).stdout.decode().strip()


def linux_manifest(value):
    require(value['tag'] == TAG and value['commit'] == COMMIT, 'Linux tag/source mismatch')
    require(value['embeddedVersion'] == '0.2.0-rc.7', 'Linux version mismatch')
    require(value['passedGates'] == LINUX_GATES, 'Linux gate set mismatch')
    require(set(value['binaries']) == {'mirror', 'model_interface_gen'}, 'Linux binary set mismatch')
    require('focused non-model' in value['qualification'], 'Linux scope missing')


def windows_manifest(value, source):
    require(value['tag'] == TAG and value['tagObject'] == source['tagObject'], 'Windows tag mismatch')
    require(value['sourceCommit'] == COMMIT and value['sourceTree'] == TREE, 'Windows source mismatch')
    require(value['sourceArchiveSha256'] == source['sourceArchive']['sha256'], 'Windows archive source mismatch')
    require(value['sourceFileCount'] == source['fileCount'] and value['sourceOverlay'] is False,
            'Windows source count/overlay mismatch')
    require(value['embeddedVersion'] == '0.2.0-rc.7', 'Windows version mismatch')
    require(set(value['files']) == {'bin/ModelMirrors.exe', 'bin/model_interface_gen.exe',
            'bin/libcrypto-3-x64.dll', 'bin/libssl-3-x64.dll', 'bin/zlib1.dll'}, 'Windows payload set')
    require([v['gate'] for v in value['gates']] == WINDOWS_GATES and
            all(v['exit'] == 0 for v in value['gates']), 'Windows gate set/result mismatch')
    require(not any(value[k] for k in ['published', 'deployed', 'fullLakeTest',
            'reproducibleCompilation', 'releaseAdmission']), 'Windows qualification overclaim')


def source_archive(source):
    manifest = load(ROOT / source['sourceManifest']['path'])
    require(identity(ROOT / source['sourceManifest']['path']) == source['sourceManifest'], 'source manifest hash')
    rows = {v['path']: v for v in manifest['files']}
    require(len(rows) == len(manifest['files']) == source['fileCount'], 'duplicate or missing source path')
    require(identity(ROOT / source['sourceArchive']['path']) == source['sourceArchive'], 'source archive hash')
    prefix = 'mirrors-' + TAG + '/'
    with tarfile.open(ROOT / source['sourceArchive']['path']) as handle:
        files = [m for m in handle if m.isfile()]
        require(len(files) == len(rows), 'source member count')
        for member in files:
            require(member.name.startswith(prefix), 'source prefix')
            data = handle.extractfile(member).read()
            row = rows[member.name[len(prefix):]]
            require((len(data), hashlib.sha256(data).hexdigest()) == (row['bytes'], row['sha256']), 'source payload hash')
    # Check each archived file against its actual immutable Git blob, using a
    # single batch reader rather than trusting the producer's manifest alone.
    tree = subprocess.run(['git', '-C', str(SOURCE), 'ls-tree', '-rz', '--full-tree', COMMIT],
                           capture_output=True, check=True).stdout.split(b'\0')
    entries = {}
    for raw in tree:
        if raw:
            metadata, name = raw.split(b'\t', 1)
            mode, kind, oid = metadata.decode().split()
            require(kind == 'blob' and mode in {'100644', '100755'}, 'unsupported Git source entry')
            entries[name.decode()] = oid
    require(set(entries) == set(rows), 'Git/archive source membership differs')
    process = subprocess.Popen(['git', '-C', str(SOURCE), 'cat-file', '--batch'],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        for name, oid in entries.items():
            process.stdin.write((oid + '\n').encode()); process.stdin.flush()
            header = process.stdout.readline().decode().split()
            require(header[:2] == [oid, 'blob'], 'Git blob header')
            size = int(header[2]); data = process.stdout.read(size)
            require(process.stdout.read(1) == b'\n', 'Git blob delimiter')
            row = rows[name]
            require((size, hashlib.sha256(data).hexdigest()) == (row['bytes'], row['sha256']), 'Git/source payload differs')
        process.stdin.close()
        require(process.wait(timeout=30) == 0, 'Git blob reader failed')
    finally:
        if process.poll() is None:
            process.kill(); process.wait()
    return rows


def main():
    source = load(PLAN / 'source-identity.json')
    package_set = load(PLAN / 'package-set.json')
    require(package_set['tag'] == TAG and package_set['tagObject'] == source['tagObject'] and
            package_set['commit'] == COMMIT and package_set['tree'] == TREE, 'unified source identity')
    require(not any(package_set[k] for k in ['published', 'deployed', 'releaseAdmission',
            'fullWindowsLakeTest', 'installedDOrM5OrQ', 'remoteModelQualification']), 'unified scope overclaim')
    require(subprocess.run(['git', 'show-ref', '--tags'], cwd=ROOT, capture_output=True,
            check=True).stdout == (OUT / 'shared-tags-before.txt').read_bytes(), 'shared tag refs changed')
    require(git('rev-parse', 'HEAD') == COMMIT and git('rev-parse', 'HEAD^{tree}') == TREE, 'source tree drift')
    require(git('rev-parse', 'refs/tags/' + TAG) == source['tagObject'], 'tag object drift')
    require(git('rev-parse', TAG + '^{commit}') == COMMIT and git('status', '--porcelain=v1') == '', 'tag peel/clean state')
    expected = source_archive(source)
    linux = load(PLAN / 'linux-package.json')
    require(package_set['linux']['archive'] == linux['archive'], 'unified Linux identity')
    require(identity(ROOT / linux['archive']['path']) == linux['archive'], 'Linux archive identity')
    external = ROOT / linux['externalManifest']['path']
    lm = load(external); linux_manifest(lm)
    name = 'mirrors-' + TAG + '-linux-x86_64'
    with tarfile.open(ROOT / linux['archive']['path']) as handle:
        members = handle.getmembers()
        require(len(members) == 6 and {m.name for m in members} == {
            name, name + '/bin', name + '/BUILD.json', name + '/README.txt',
            name + '/bin/mirror', name + '/bin/model_interface_gen'}, 'Linux package member set')
        require(handle.extractfile(name + '/BUILD.json').read() == external.read_bytes(), 'Linux manifest identity')
        for binary, row in lm['binaries'].items():
            require(hashlib.sha256(handle.extractfile(name + '/bin/' + binary).read()).hexdigest()
                    == row['sha256'], 'Linux binary identity')
    isolation = linux['isolatedSmoke']
    require(isolation['path'] == '/usr/bin:/bin' and isolation['sourceHidden'] and isolation['leanUnavailable'],
            'Linux isolation missing')
    require(linux['mirrorVersion'] == TAG, 'Linux isolated version')
    for label in ['release-tests', 'linux-release-build', 'linux-maintained-archive-check',
                  'linux-isolation-check', 'linux-isolated-version', 'linux-isolated-protocol']:
        require(load(OUT / ('logs/' + label + '.json'))['exitCode'] == 0, label)
    help_receipt = load(OUT / 'logs/linux-isolated-compiler-help.json')
    require(help_receipt['exitCode'] == 2 and 'usage:' in
            (ROOT / help_receipt['stderr']['path']).read_text(), 'Linux compiler help')
    for directory in [OUT / 'linux-dist', OUT / 'windows']:
        for line in (directory / 'SHA256SUMS').read_text().splitlines():
            sha, filename = line.split('  ', 1)
            require(identity(directory / filename)['sha256'] == sha, 'checksum listing ' + filename)
    win = OUT / 'windows'
    wname = 'mirrors-' + TAG + '-windows-x86_64'
    archive = win / (wname + '.zip'); repeat = win / (wname + '-repeat.zip')
    require(package_set['windows']['archive'] == identity(archive), 'unified Windows identity')
    require(package_set['windows']['repeatArchive'] == identity(repeat), 'unified repeat ZIP identity')
    require(archive.read_bytes() == repeat.read_bytes(), 'Windows repeat ZIP mismatch')
    wm = load(win / (wname + '.build.json')); windows_manifest(wm, source)
    build = load(win / 'windows-build-record.json')
    require(build['exit'] == 0 and build['fullLakeTest'] is False, 'Windows build result')
    for packed, built in [('bin/ModelMirrors.exe', 'mirror'),
                          ('bin/model_interface_gen.exe', 'model_interface_gen')]:
        require(wm['files'][packed]['sha256'] == build['binaries'][built]['sha256'],
                'Windows packaged/source binary mismatch')
    environment = load(win / 'windows-build-environment.json')
    for dll, key in [('libcrypto-3-x64.dll', 'libcrypto'), ('libssl-3-x64.dll', 'libssl'),
                     ('zlib1.dll', 'zlib1')]:
        require(wm['files']['bin/' + dll]['sha256'] == environment['openssl'][key],
                'Windows DLL/build-environment mismatch')
    runtime = load(win / 'windows-review-inputs.json')
    require(runtime['sourceAndLeanAbsentFromPath'] and runtime['packageBytesUnchanged'],
            'Windows packaged runtime isolation/stability missing')
    require([v['exitCode'] for v in runtime['observations']] == [0, 0, 2], 'Windows runtime smoke results')
    require(runtime['observations'][0]['stdout'] == TAG + '\n', 'Windows packaged version')
    require(json.loads(runtime['observations'][1]['stdout'])['proto_step'] == 'protocol_error',
            'Windows packaged protocol smoke')
    require('usage:' in runtime['observations'][2]['stderr'], 'Windows packaged compiler help')
    for gate in wm['gates']:
        require(identity(win / 'logs' / (gate['gate'] + '.log'))['sha256'] == gate['logSha256'], 'Windows gate log hash')
    require(identity(win / 'logs/build.log')['sha256'] == build['logSha256'], 'Windows build log hash')
    old = ROOT / 'Plans/mainwork-s3-rc6-20261103/verify_s3.py'
    spec = importlib.util.spec_from_file_location('reviewed_pe_parser', old)
    pe = importlib.util.module_from_spec(spec); spec.loader.exec_module(pe)
    allowed = pe.SYSTEM_DLLS | {'libcrypto-3-x64.dll', 'libssl-3-x64.dll', 'zlib1.dll'}
    imports = {}; binary_for_control = None
    with zipfile.ZipFile(archive) as handle:
        wanted = {wname + '/BUILD.json', wname + '/README.txt',
                  *[wname + '/' + rel for rel in wm['files']]}
        require(len(handle.namelist()) == len(wanted) and set(handle.namelist()) == wanted, 'Windows member set')
        require(not any((v.external_attr >> 16) & 0o170000 == 0o120000
                        for v in handle.infolist()), 'linked Windows package member')
        require(handle.namelist() == sorted(handle.namelist()), 'Windows POSIX member order')
        require(handle.read(wname + '/BUILD.json') == (win / (wname + '.build.json')).read_bytes(), 'Windows manifest identity')
        for rel, row in wm['files'].items():
            data = handle.read(wname + '/' + rel)
            require((len(data), hashlib.sha256(data).hexdigest()) == (row['bytes'], row['sha256']), 'Windows payload hash')
            found = pe.pe_imports(data)
            require(all(v.lower() in allowed or v.lower().startswith('api-ms-win-') for v in found), 'unreviewed PE import')
            imports[rel] = sorted(found)
            if rel == 'bin/ModelMirrors.exe':
                binary_for_control = data
    for label in ['before', 'after']:
        rows = [json.loads(line) for line in (win / ('source-' + label + '.jsonl')).read_text().splitlines()]
        seen = {v['path']: v for v in rows}
        require(len(rows) == len(seen), 'duplicate Windows source row')
        require(all(seen.get(name) == value for name, value in expected.items()), 'Windows original source changed')
        extras = sorted(set(seen) - set(expected))
        wanted = [] if label == 'before' else ['.golden-build/model-interface-rust/CorpusMirror.generated.rs',
                    '.golden-build/model-interface-rust/MultiMirror.generated.rs']
        require(extras == wanted, 'unexpected Windows generated source')
    observation = load(win / 'windows-final-observation.json')
    require(observation['allBaselineFilesUnchanged'] and observation['productionPidUnchanged'], 'production observation drift')
    controls = []

    def reject(label, action):
        try:
            action()
        except (ValueError, pe.S3Error):
            controls.append(label); return
        raise ValueError('negative control accepted: ' + label)

    wrong = copy.deepcopy(lm); wrong['tag'] = 'v0.2.0-wrong'
    reject('wrong-linux-tag', lambda: linux_manifest(wrong))
    wrong_source = copy.deepcopy(source); wrong_source['sourceArchive']['sha256'] = '0' * 64
    reject('wrong-source-archive-hash', lambda: source_archive(wrong_source))
    missing = copy.deepcopy(wm); missing['gates'].pop()
    reject('missing-windows-gate', lambda: windows_manifest(missing, source))
    kernel_name = next(v for v in pe.pe_imports(binary_for_control) if v.lower() == 'kernel32.dll')
    poisoned = binary_for_control.replace(kernel_name.encode() + b'\0', b'EVILBAD0.dll\0')
    require('EVILBAD0.dll' in pe.pe_imports(poisoned), 'PE control target missing')
    reject('unreviewed-pe-import', lambda: require(all(v.lower() in allowed or
        v.lower().startswith('api-ms-win-') for v in pe.pe_imports(poisoned)), 'unreviewed PE import'))
    print(json.dumps({'status': 'S3 RC7 PACKAGE VERIFY GREEN', 'sourceFiles': len(expected),
        'sourceArchiveCheckedAgainstGitBlobs': True, 'linuxSha256': linux['archive']['sha256'],
        'windowsArchive': identity(archive), 'windowsGateCount': len(wm['gates']),
        'windowsRepeatZipIdentical': True, 'peImports': imports, 'negativeControlsRejected': controls,
        'published': False, 'deployed': False, 'releaseAdmission': False}, indent=2))


if __name__ == '__main__':
    main()
