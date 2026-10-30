#!/usr/bin/env python3
"""Offline verifier for the 2026-10-30 completion S3 package record.

Checks this record's inventory, the package-set bindings, the Linux archive
bytes and members, the rejected Windows artifact row, and the S3 ledger states.
It never executes a packaged binary, never contacts a service, and never
modifies a retained artifact. Negative controls prove that missing and tampered
artifacts are refused.
"""
import hashlib, json, re, sys, tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
SECRETS = [re.compile(rb'-----BEGIN ' + rb'[A-Z0-9 ]*PRIVATE KEY-----'),
           re.compile(rb'PuTTY-User-Key' + rb'-File'),
           re.compile(rb'AKIA' + rb'[0-9A-Z]{16}'), re.compile(rb'gh[pousr]' + rb'_[A-Za-z0-9]{36}')]

def sha(raw): return hashlib.sha256(raw).hexdigest()
def read(path): return json.loads(path.read_text(encoding='utf-8'))
def require(ok, message):
    if not ok: raise ValueError(message)

def handle_read_build(archive):
    with tarfile.open(archive) as handle:
        for member in handle.getmembers():
            if member.isfile() and member.name.endswith('/BUILD.json'):
                return handle.extractfile(member).read()
    raise ValueError('embedded BUILD.json missing')

def check_inventory(entries, base=ROOT):
    require(type(entries) is list and entries, 'empty inventory')
    seen = set()
    for entry in entries:
        name = entry['path']
        require(isinstance(name, str) and name not in seen and not Path(name).is_absolute()
                and '..' not in Path(name).parts, 'invalid or duplicate inventory path')
        seen.add(name)
        path = base/name
        require(path.is_file() and not path.is_symlink(), 'missing or escaping record file: '+name)
        raw = path.read_bytes()
        require(len(raw) == entry['bytes'] and sha(raw) == entry['sha256'], 'record identity differs: '+name)
        for pattern in SECRETS:
            require(not pattern.search(raw), 'private credential material in: '+name)
    return len(entries)

def check_artifact(path, entry):
    require(path.is_file() and not path.is_symlink(), 'missing retained artifact: '+str(path))
    raw = path.read_bytes()
    require(len(raw) == entry['bytes'] and sha(raw) == entry['sha256'], 'retained artifact identity differs: '+str(path))
    return raw

def check_linux(package_set):
    entry = next((a for a in package_set['artifacts'] if a['id'] == 'linux-x86_64'), None)
    require(entry is not None, 'linux artifact row missing')
    require(entry['sourceBinding']['state'] == 'bound', 'linux artifact is not bound to S2')
    require(entry['sourceBinding']['commit'] == package_set['source']['commit'] == 'd737aa0886b9d406e391955756922d9d735d7ec1',
            'linux artifact commit differs from S2')
    archive = REPO/entry['retentionLocation']
    check_artifact(archive, entry)
    audit = read(ROOT/'logs/s3.5-archive-member-audit.json')
    require(not audit['secretFindings'], 'credential material inside the linux archive')
    with tarfile.open(archive) as handle:
        members = {m.name: m for m in handle.getmembers()}
        require(len(members) == entry['validation']['archiveEntries'], 'linux archive entry count differs')
        files = [m for m in members.values() if m.isfile()]
        require(len(files) == entry['validation']['archiveFiles'], 'linux archive file count differs')
        require(all(m.isfile() or m.isdir() for m in members.values()), 'linux archive contains links or specials')
        for name, recorded in audit['linuxMembers'].items():
            require(name in members, 'recorded linux member missing: '+name)
            require(recorded['type'] == ('dir' if members[name].isdir() else 'file'), 'linux member type differs: '+name)
            if recorded['type'] == 'file':
                raw = handle.extractfile(members[name]).read()
                require(len(raw) == recorded['bytes'] and sha(raw) == recorded['sha256'], 'linux member bytes differ: '+name)
                require(not name.endswith(('.lean', '.olean')), 'Lean source shipped in archive: '+name)
        build_member = next(m for m in files if m.name.endswith('/BUILD.json'))
        build = json.loads(handle.extractfile(build_member).read())
    external = REPO/entry['externalBuildManifest']['path']
    external_raw = external.read_bytes()
    require(sha(external_raw) == entry['externalBuildManifest']['sha256'], 'external build manifest identity differs')
    require(handle_read_build(archive) == external_raw, 'embedded and external BUILD.json differ')
    require(build['tag'] == package_set['tag']['name'] and build['commit'] == package_set['source']['commit'],
            'embedded BUILD.json does not bind the expected tag/commit')
    require(sha((REPO/'tools/release/release.py').read_bytes()) == package_set['releaseTooling']['sha256'],
            'release tooling digest differs from the recorded build input')
    require(build['embeddedVersion'] == package_set['source']['embeddedVersion'], 'embedded version differs')
    for name, recorded in entry['binaries'].items():
        require(build['binaries'][name]['sha256'] == recorded['sha256'], 'binary digest differs from manifest: '+name)
    return entry

def check_windows(package_set, binding):
    entry = next((a for a in package_set['artifacts'] if a['id'] == 'windows-x86_64'), None)
    require(entry is not None, 'windows artifact row missing')
    require(entry['sourceBinding']['state'] == 'rejected-rebuild-required', 'rejected Windows row was credited')
    require(binding['verdict'] == 'rebuild-required', 'windows binding verdict was softened')
    require(binding['compiledBuildInputsIdentical'] is True and len(binding['diff']) == 20
            and binding['identical'] == 8790 and binding['totalManifestFiles'] == 8810,
            'windows comparison counts differ from the recorded audit')
    require(binding['reuseCondition'] == 'not-met', 'windows reuse condition was credited')
    archive = REPO/entry['retentionLocation']
    check_artifact(archive, entry)
    return entry

def check_ledger():
    rows = {row['id']: row for row in read(ROOT/'s3-ledger.json')['rows']}
    require(set(rows) == {'S3.%d' % n for n in range(1, 10)}, 'unexpected S3 row set')
    for ident in ('S3.1', 'S3.2', 'S3.3', 'S3.4', 'S3.5', 'S3.8'):
        require(rows[ident]['currentState'] == 'passed', ident+' is not passed')
    require(rows['S3.6']['currentState'] == 'awaiting-external-input', 'S3.6 claimed a runtime it did not observe')
    require(rows['S3.7']['currentState'] == 'failed', 'S3.7 rejection was converted into acceptance')
    require(rows['S3.9']['currentState'] == 'partial', 'S3.9 claimed a complete package set')
    return len(rows)

def main():
    manifest = read(ROOT/'inventory.json')
    count = check_inventory(manifest['files'])
    package_set = read(ROOT/'package-set.json')
    binding = read(ROOT/'windows-binding.json')
    require(package_set['schema'] == 'mirrors.s3.package-set/v1', 'unexpected package-set schema')
    require(package_set['tag']['pushed'] is False and package_set['tag']['remoteAbsent'] is True,
            'local tag record claims a remote tag')
    linux = check_linux(package_set)
    windows = check_windows(package_set, binding)
    rows = check_ledger()
    original = manifest['files'][0]
    controls = [dict(original, path='missing-control-artifact'), dict(original, sha256='0'*64)]
    for bad in controls:
        try: check_inventory([bad])
        except ValueError: pass
        else: raise ValueError('inventory negative control was accepted')
    import tempfile
    with tempfile.TemporaryDirectory(prefix='mirrors-s3-control-') as temporary:
        fake = Path(temporary)/'tampered'
        fake.write_bytes(b'tampered artifact bytes')
        for bad in (dict(linux, retentionLocation=str(fake)), dict(linux, sha256='0'*64)):
            try: check_artifact(REPO/bad['retentionLocation'] if not Path(bad['retentionLocation']).is_absolute() else Path(bad['retentionLocation']), bad)
            except ValueError: pass
            else: raise ValueError('artifact negative control was accepted')
    print(json.dumps({'status':'passed','inventoryFiles':count,'ledgerRows':rows,
                      'linuxArtifact':linux['sha256'],'windowsArtifactState':windows['sourceBinding']['state'],
                      'negativeControls':['missing-record-file','tampered-record-digest','tampered-artifact-bytes','tampered-artifact-digest'],
                      'claim':'local package construction only; no publication, deployment or platform qualification'},
                     sort_keys=True))

if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, TypeError) as error:
        print('Completion S3 package record refused: '+str(error), file=sys.stderr)
        raise SystemExit(1)
