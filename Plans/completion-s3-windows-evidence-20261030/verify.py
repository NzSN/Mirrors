#!/usr/bin/env python3
"""Offline verifier for the 2026-10-30 completion S3 Windows rebuild record.

Checks this record's inventory, the exact-tag source manifest, the raw host
receipts, the retained Windows ZIP and external manifest, gate logs, production
observation and PE import closure. Missing/tampered negative controls run
against temporary copies. It never executes a packaged binary, starts a model
checker, contacts a service or modifies a retained artifact.
"""
import hashlib
import json
import re
import shutil
import struct
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
PREFIX = 'mirrors-v0.2.0-rc.1-windows-x86_64'
GATES = ('fixtures_replay', 'diff_cross', 'model_interface_spec', 'stdio_smoke',
         'transport_spec', 'jobstore_spec', 'async_resource_spec', 'dpm_sync_spec')
SYSTEM_DLLS = {
    'ADVAPI32.dll', 'IPHLPAPI.DLL', 'KERNEL32.dll', 'SHELL32.dll', 'USER32.dll',
    'USERENV.dll', 'WS2_32.dll', 'bcrypt.dll', 'dbghelp.dll', 'icu.dll',
    'ole32.dll', 'ucrtbase.dll', 'msvcrt.dll', 'CRYPT32.dll',
}
FORBIDDEN_SUFFIXES = ('.lean', '.olean', '.tar', '.gz', '.tgz', '.pem', '.key', '.p12', '.pfx')
SECRETS = (
    re.compile(rb'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----'),
    re.compile(rb'PuTTY-User-Key-File'),
    re.compile(rb'AKIA[0-9A-Z]{16}'),
    re.compile(rb'gh[pousr]_[A-Za-z0-9]{36}'),
)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def require(ok, message):
    if not ok:
        raise ValueError(message)


def pe_imports(data):
    """Return sorted imported DLL names from a PE32+ image."""
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    require(data[pe:pe + 4] == b'PE\0\0', 'not a PE image')
    coff = pe + 4
    sections = struct.unpack_from('<H', data, coff + 2)[0]
    opt_size = struct.unpack_from('<H', data, coff + 16)[0]
    opt = coff + 20
    require(struct.unpack_from('<H', data, opt)[0] == 0x20b, 'not PE32+')
    directories = opt + 112
    table = []
    for index in range(sections):
        offset = opt + opt_size + 40 * index
        virtual_size, virtual_address, raw_size, raw_pointer = struct.unpack_from('<IIII', data, offset + 8)
        table.append((virtual_address, virtual_size, raw_pointer, raw_size))

    def file_offset(rva):
        for virtual_address, virtual_size, raw_pointer, raw_size in table:
            if virtual_address <= rva < virtual_address + max(virtual_size, raw_size):
                return raw_pointer + (rva - virtual_address)
        raise ValueError('unmapped RVA 0x%x' % rva)

    names = set()
    for index, name_field in ((1, 12), (13, 4)):
        rva, _size = struct.unpack_from('<II', data, directories + 8 * index)
        if not rva:
            continue
        cursor = file_offset(rva)
        while True:
            descriptor = data[cursor:cursor + 20]
            if len(descriptor) < 20 or descriptor == b'\0' * 20:
                break
            name_rva = struct.unpack_from('<I', descriptor, name_field)[0]
            start = file_offset(name_rva)
            names.add(data[start:data.index(b'\0', start)].decode('ascii'))
            cursor += 20
    return sorted(names)


def check_inventory(entries, base=ROOT):
    require(type(entries) is list and entries, 'empty inventory')
    seen = set()
    for entry in entries:
        name = entry['path']
        require(isinstance(name, str) and name not in seen and not Path(name).is_absolute()
                and '..' not in Path(name).parts, 'invalid or duplicate inventory path')
        seen.add(name)
        path = base / name
        require(path.is_file() and not path.is_symlink(), 'missing record file: ' + name)
        raw = path.read_bytes()
        require(len(raw) == entry['bytes'] and sha(raw) == entry['sha256'], 'record identity differs: ' + name)
        if name != 'verify.py':
            for pattern in SECRETS:
                require(not pattern.search(raw), 'credential material in: ' + name)
    return len(entries)


def check_source(source, manifest):
    require(manifest['commit'] == source['commit'] == 'd737aa0886b9d406e391955756922d9d735d7ec1', 'source commit differs')
    require(manifest['tree'] == source['tree'] == '8d2de2561d25c219e685bb46980080c03d7d1c98', 'source tree differs')
    require(manifest['tag'] == source['tag'] == 'v0.2.0-rc.1', 'source tag differs')
    require(manifest['tagObject'] == source['tagObject'] == 'f135f2809e6612d158c5be176c7ea6429b9d51f3', 'tag object differs')
    files = manifest['files']
    require(len(files) == source['fileCount'] == 9207, 'source file count differs')
    names = [entry['path'] for entry in files]
    require(len(set(names)) == len(names), 'duplicate source path')
    require(all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in names), 'escaping source path')
    body = ''.join('%s\t%d\t%s\n' % (e['path'], e['bytes'], e['sha256'])
                   for e in sorted(files, key=lambda e: e['path'])).encode()
    require(sha(body) == source['contentTreeDigest'], 'source content tree digest differs')
    archive = REPO / source['archiveRetention']
    require(archive.is_file(), 'retained source archive missing')
    raw = archive.read_bytes()
    require(len(raw) == source['archiveBytes'] and sha(raw) == source['archiveSha256'], 'source archive identity differs')
    verification = read(ROOT / 'receipts/source-verification.json')
    require(verification['contentTreeDigest'] == source['contentTreeDigest'], 'host extraction digest differs')
    require(verification['fileCount'] == source['fileCount'] and verification['gitDirectoryPresent'] is False, 'host extraction identity differs')
    require(verification['embeddedVersion'] == '0.2.0-rc.1', 'embedded version differs')
    post = read(ROOT / 'receipts/post-source-check.json')
    require(post['checkedFiles'] == source['fileCount'] == 9207, 'post-build source file count differs')
    require(post['changedOrMissing'] == [] and post['extraFilesOutsideLake'] == [], 'post-build source tree changed')


def audit_zip(archive_path, external_path, receipt):
    archive_path = Path(archive_path)
    require(archive_path.is_file() and not archive_path.is_symlink(), 'missing Windows ZIP')
    raw = archive_path.read_bytes()
    artifact = receipt['artifact']
    require(len(raw) == artifact['bytes'] and sha(raw) == artifact['sha256'], 'Windows ZIP identity differs')
    expected = {m['path']: m for m in artifact['members']}
    require(len(expected) == artifact['memberCount'] == 7, 'recorded member count differs')
    with zipfile.ZipFile(archive_path) as handle:
        infos = handle.infolist()
        names = [i.filename for i in infos]
        require(len(names) == len(set(names)) and set(names) == set(expected), 'ZIP member set differs')
        require(all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in names), 'escaping ZIP member')
        require(all(n.startswith(PREFIX + '/') for n in names), 'unexpected ZIP prefix')
        require(all(i.is_dir() is False for i in infos), 'ZIP contains directories or specials')
        for info in infos:
            row = expected[info.filename]
            data = handle.read(info.filename)
            require(len(data) == row['bytes'] and sha(data) == row['sha256'], 'ZIP member differs: ' + info.filename)
            require(list(info.date_time) == [2026, 10, 30, 0, 0, 0], 'ZIP timestamp differs: ' + info.filename)
            require(oct(info.external_attr >> 16) == row['externalAttr'] == '0o600', 'ZIP mode differs: ' + info.filename)
            require(not info.filename.lower().endswith(FORBIDDEN_SUFFIXES), 'forbidden member: ' + info.filename)
            for pattern in SECRETS:
                require(not pattern.search(data), 'credential material in: ' + info.filename)
        embedded = handle.read(PREFIX + '/BUILD.json')
        executable = handle.read(PREFIX + '/bin/ModelMirrors.exe')
        readme = handle.read(PREFIX + '/README.txt')
        imports = {Path(n).name: pe_imports(handle.read(n)) for n in names if n.endswith(('.exe', '.dll'))}
    external_raw = Path(external_path).read_bytes()
    require(sha(external_raw) == artifact['externalBuildManifest']['sha256'], 'external manifest identity differs')
    require(len(external_raw) == artifact['externalBuildManifest']['bytes'], 'external manifest size differs')
    require(embedded == external_raw, 'embedded BUILD.json differs from external manifest')
    build = json.loads(embedded)
    require(build['version'] == '0.2.0-rc.1' and build['tag'] == 'v0.2.0-rc.1', 'BUILD.json version/tag differs')
    require(build['sourceCommit'] == receipt['source']['commit'], 'BUILD.json commit differs')
    require(build['sourceArchiveSha256'] == receipt['source']['archiveSha256'], 'BUILD.json source archive differs')
    require(build['sourceContentTreeDigest'] == receipt['source']['contentTreeDigest'], 'BUILD.json source digest differs')
    require(build['published'] is False and build['deployed'] is False, 'BUILD.json publication state differs')
    for name, path_info in build['files'].items():
        row = artifact['members']
        match = next(m for m in row if m['path'] == PREFIX + '/' + name)
        require(match['sha256'] == path_info['sha256'] and match['bytes'] == path_info['bytes'], 'BUILD.json file binding differs: ' + name)
    require([row['gate'] for row in build['gates']] == list(GATES), 'BUILD.json gate list differs')
    require(all(row['exit'] == 0 for row in build['gates']), 'BUILD.json records a failing gate')
    require(b'0.2.0-rc.1' in executable, 'executable version string missing')
    require(readme.startswith(b'Mirrors v0.2.0-rc.1 native Windows package') and b'Not published or deployed.' in readme,
            'README.txt content differs')
    bundled = {Path(m['path']).name for m in artifact['members'] if m['path'].endswith('.dll')}
    for name, names_imported in imports.items():
        unresolved = [n for n in names_imported if n not in SYSTEM_DLLS and not n.lower().startswith('api-ms-win-') and n not in bundled]
        require(not unresolved, 'unresolved import for %s: %s' % (name, unresolved))
        recorded = artifact['peImports'][name]
        require(names_imported == recorded['imports'] and recorded['unresolved'] == [], 'recorded PE imports differ: ' + name)
    return {'archiveSha256': sha(raw), 'members': len(expected), 'imports': imports}


def check_gates(receipt):
    rows = receipt['gates']['rows']
    require(len(rows) == receipt['gates']['count'] == 8, 'gate count differs')
    require([row['gate'] for row in rows] == list(GATES), 'gate order/set differs')
    require(all(row['exit'] == 0 for row in rows) and receipt['gates']['allExitZero'] is True, 'a gate is not exit 0')
    for row in rows:
        path = ROOT / 'logs' / (row['gate'] + '.log')
        require(path.is_file(), 'gate log missing: ' + row['gate'])
        raw = path.read_bytes()
        require(len(raw) == row['logBytes'] and sha(raw) == row['logSha256'], 'gate log identity differs: ' + row['gate'])
    initial = receipt['gates']['transportInitialFailure']
    path = ROOT / 'logs/transport_spec-initial-failure.log'
    raw = path.read_bytes()
    require(len(raw) == initial['bytes'] and sha(raw) == initial['sha256'], 'transport initial-failure log differs')
    require(b'FAIL: pki: server cert signed' in raw, 'retained transport failure is not the recorded environmental failure')


def check_production(receipt):
    production = receipt['production']
    before = production['before']
    require(len(before['processes']) == 1, 'production process count differs')
    require(production['pid'] == before['processes'][0]['pid'] == 9920, 'production PID differs')
    require(production['sha256'] == '8173ddea65f78a88b1a303f8a233dd7113b28e7dc8aefd8916a5add25a3687cc', 'production binary differs')
    require(production['unchanged'] is True and production['pidUnchanged'] is True, 'production change recorded')
    require(production['serviceStatus'] == 'Running', 'production service is not running')
    require(production['taskOwnedDescendantCount'] == 0, 'task-owned descendant remains')
    observed = read(ROOT / 'receipts/final-observation.json')
    require(observed['productionExecutableUnchanged'] is True and observed['productionPidUnchanged'] is True, 'final observation disagrees')
    require(observed['taskOwnedDescendantCount'] == 0, 'final descendant count differs')
    require(observed['configurationHashes'] == production['configurationHashes'], 'configuration hash binding differs')


def check_environment(receipt):
    env = read(ROOT / 'receipts/build-environment.json')
    require(env['host'] == receipt['environment']['host'] == 'DESKTOP-6DKB5JD', 'host differs')
    labels = [tool['label'] for tool in env['tools']]
    require(labels == ['lake', 'lean', 'gcc', 'python', 'git'], 'tool set differs')
    require(receipt['environment']['tools'][1]['version'].startswith('Lean (version 4.33.0,'), 'Lean version differs')
    require(receipt['environment']['tools'][0]['version'].startswith('Lake version 5.0.0'), 'Lake version differs')
    require(receipt['build']['exit'] == 0, 'build did not exit 0')
    require(receipt['build']['logBytes'] == (ROOT / 'logs/build.log').stat().st_size, 'build log size differs')
    require(sha((ROOT / 'logs/build.log').read_bytes()) == receipt['build']['logSha256'], 'build log identity differs')
    dependency = receipt['offlineDependency']
    require(dependency['manifestRev'] == '4488d40d070b9700d4d5a6aa342f0d40c31b2a2d', 'dependency revision differs')
    require(dependency['fileCount'] == 3962, 'dependency file count differs')


def negative_controls(receipt, work):
    archive = REPO / receipt['artifact']['retentionLocation']
    external = REPO / receipt['artifact']['externalBuildManifest']['path']
    # missing artifact
    try:
        audit_zip(work / 'missing.zip', external, receipt)
        raise AssertionError('missing artifact was accepted')
    except ValueError:
        pass
    # tampered archive bytes
    tampered = work / 'tampered.zip'
    raw = bytearray(archive.read_bytes())
    raw[len(raw) // 2] ^= 1
    tampered.write_bytes(raw)
    try:
        audit_zip(tampered, external, receipt)
        raise AssertionError('tampered archive was accepted')
    except ValueError:
        pass
    # tampered member inside a structurally valid ZIP
    rebuilt = work / 'member-tampered.zip'
    with zipfile.ZipFile(archive) as source, zipfile.ZipFile(rebuilt, 'w', compression=zipfile.ZIP_DEFLATED) as target:
        for info in source.infolist():
            data = source.read(info.filename)
            if info.filename.endswith('bin/ModelMirrors.exe'):
                data = data[:-1] + bytes([data[-1] ^ 1])
            target.writestr(info, data)
    try:
        audit_zip(rebuilt, external, receipt)
        raise AssertionError('tampered member was accepted')
    except ValueError:
        pass
    # tampered external manifest
    manifest = work / 'tampered.build.json'
    manifest.write_bytes(external.read_bytes().replace(b'0.2.0-rc.1', b'0.2.0-rc.9'))
    try:
        audit_zip(archive, manifest, receipt)
        raise AssertionError('tampered manifest was accepted')
    except ValueError:
        pass
    # tampered inventory
    entry = {'path': 'README.md', 'bytes': (ROOT / 'README.md').stat().st_size + 1,
             'sha256': sha((ROOT / 'README.md').read_bytes())}
    try:
        check_inventory([entry])
        raise AssertionError('tampered inventory was accepted')
    except ValueError:
        pass


def main():
    receipt = read(ROOT / 'package-receipt.json')
    inventory = read(ROOT / 'inventory.json')
    checked = check_inventory(inventory['files'])
    source = read(ROOT / 'receipts/source-manifest.json')
    check_source(receipt['source'], source)
    artifact = audit_zip(REPO / receipt['artifact']['retentionLocation'],
                         REPO / receipt['artifact']['externalBuildManifest']['path'], receipt)
    check_gates(receipt)
    check_environment(receipt)
    check_production(receipt)
    require(receipt['artifact']['repeatedPackagingIdentical'] is True, 'repeat packaging claim differs')
    require(receipt['artifact']['repeatSha256'] == receipt['artifact']['sha256'], 'repeat archive hash differs')
    with tempfile.TemporaryDirectory() as tmp:
        negative_controls(receipt, Path(tmp))
    print('WINDOWS EVIDENCE VERIFIED')
    print('  inventory files: %d' % checked)
    print('  source: %s @ %s (%d files)' % (receipt['source']['tag'], receipt['source']['commit'], receipt['source']['fileCount']))
    print('  artifact: %s  sha256=%s  bytes=%d  members=%d' % (
        receipt['artifact']['name'], artifact['archiveSha256'], receipt['artifact']['bytes'], artifact['members']))
    print('  gates: %d/8 exit 0; no unresolved PE imports' % receipt['gates']['count'])
    print('  production: pid 9920 unchanged; task-owned descendants: 0')
    print('  negative controls: missing artifact, tampered archive, tampered member, tampered manifest, tampered inventory all refused')
    print('  scope: staged native build and eight non-model suites only')
    return 0


if __name__ == '__main__':
    sys.exit(main())
