#!/usr/bin/env python3
"""Offline verifier for the 2026-10-30 completion S3 reconciled package record.

Rechecks this record's inventory, the versioned package-set bindings, both
retained platform archives, their embedded/external BUILD.json manifests, the
retained rejected October 29 Windows row and the reconciled S3 ledger. Missing,
tampered and escalated negative controls run in a temporary directory. It never
executes a packaged binary, starts a model checker, contacts a service or
modifies a retained artifact.
"""
import hashlib
import json
import re
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
COMMIT = 'd737aa0886b9d406e391955756922d9d735d7ec1'
TREE = '8d2de2561d25c219e685bb46980080c03d7d1c98'
TAG = 'v0.2.0-rc.1'
SECRETS = (
    re.compile(rb'-----BEGIN ' + rb'[A-Z0-9 ]*PRIVATE KEY-----'),
    re.compile(rb'PuTTY-User-Key' + rb'-File'),
    re.compile(rb'AKIA' + rb'[0-9A-Z]{16}'),
    re.compile(rb'gh[pousr]' + rb'_[A-Za-z0-9]{36}'),
)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def require(ok, message):
    if not ok:
        raise ValueError(message)


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
        require(len(raw) == entry['bytes'] and sha(raw) == entry['sha256'],
                'record identity differs: ' + name)
        if name != 'verify.py':
            for pattern in SECRETS:
                require(not pattern.search(raw), 'credential material in: ' + name)
    return len(entries)


def check_artifact(path, entry):
    path = Path(path)
    require(path.is_file() and not path.is_symlink(), 'missing retained artifact: ' + str(path))
    raw = path.read_bytes()
    require(len(raw) == entry['bytes'] and sha(raw) == entry['sha256'],
            'retained artifact identity differs: ' + str(path))
    return raw


def find(names, suffix):
    hits = [name for name in names if name == suffix or name.endswith('/' + suffix)]
    require(len(hits) == 1, 'expected exactly one member ending in ' + suffix)
    return hits[0]


def scan_text(raw, label):
    for pattern in SECRETS:
        require(not pattern.search(raw), 'credential material in: ' + label)


def check_linux(entry):
    archive = REPO / entry['retentionLocation']
    check_artifact(archive, entry)
    with tarfile.open(archive) as handle:
        members = {m.name: m for m in handle.getmembers()}
        require(all(m.isfile() or m.isdir() for m in members.values()),
                'linux archive contains links or specials')
        files = {name: m for name, m in members.items() if m.isfile()}
        require(len(members) == entry['archiveEntries'] == 6, 'linux archive entry count differs')
        require(len(files) == entry['archiveFiles'] == 4, 'linux archive file count differs')
        for name, row in entry['binaries'].items():
            member = members[find(members, name)]
            raw = handle.extractfile(member).read()
            require(len(raw) == row['bytes'] and sha(raw) == row['sha256'],
                    'linux binary differs: ' + name)
        build_member = members[find(members, 'BUILD.json')]
        build_raw = handle.extractfile(build_member).read()
        scan_text(handle.extractfile(members[find(members, 'README.txt')]).read(), 'linux README')
        scan_text(build_raw, 'linux BUILD.json')
    require(not any(name.lower().endswith(('.lean', '.olean')) for name in members),
            'Lean source shipped in linux archive')
    external = REPO / entry['externalBuildManifest']['path']
    external_raw = external.read_bytes()
    require(len(external_raw) == entry['externalBuildManifest']['bytes']
            and sha(external_raw) == entry['externalBuildManifest']['sha256'],
            'linux external manifest identity differs')
    require(build_raw == external_raw, 'linux embedded and external BUILD.json differ')
    build = json.loads(build_raw)
    require(build['tag'] == TAG and build['commit'] == COMMIT, 'linux manifest tag/commit differs')
    require(build['embeddedVersion'] == '0.2.0-rc.1', 'linux embedded version differs')
    for name, row in entry['binaries'].items():
        require(build['binaries'][name.split('/', 1)[1]]['sha256'] == row['sha256'],
                'linux binary digest differs from manifest: ' + name)
    return build


def check_windows(entry):
    archive = REPO / entry['retentionLocation']
    check_artifact(archive, entry)
    prefix = entry['fileName'][:-len('.zip')]
    with zipfile.ZipFile(archive) as handle:
        infos = handle.infolist()
        names = [info.filename for info in infos]
        require(len(names) == len(set(names)) == entry['archiveEntries'] == 7,
                'windows ZIP member count differs')
        require(all(not info.is_dir() for info in infos), 'windows ZIP contains directories')
        require(all(name.startswith(prefix + '/') for name in names),
                'unexpected windows ZIP prefix')
        require(not any(name.lower().endswith(('.lean', '.olean')) for name in names),
                'Lean source shipped in windows ZIP')
        for name, row in entry['binaries'].items():
            raw = handle.read(find(names, name))
            require(len(raw) == row['bytes'] and sha(raw) == row['sha256'],
                    'windows binary differs: ' + name)
        build_raw = handle.read(find(names, 'BUILD.json'))
        scan_text(build_raw, 'windows BUILD.json')
        scan_text(handle.read(find(names, 'README.txt')), 'windows README')
    external = REPO / entry['externalBuildManifest']['path']
    external_raw = external.read_bytes()
    require(len(external_raw) == entry['externalBuildManifest']['bytes']
            and sha(external_raw) == entry['externalBuildManifest']['sha256'],
            'windows external manifest identity differs')
    require(build_raw == external_raw, 'windows embedded and external BUILD.json differ')
    build = json.loads(build_raw)
    require(build['tag'] == TAG and build['sourceCommit'] == COMMIT
            and build['sourceTree'] == TREE, 'windows manifest tag/commit/tree differs')
    require(build['version'] == '0.2.0-rc.1', 'windows embedded version differs')
    require(build['sourceOverlay'] is False, 'windows manifest claims an overlay')
    require(build['published'] is False and build['deployed'] is False,
            'windows manifest claims publication or deployment')
    for name, row in entry['binaries'].items():
        require(build['files'][name]['sha256'] == row['sha256'],
                'windows binary digest differs from manifest: ' + name)
    source_archive = REPO / entry['sourceBinding']['sourceArchiveRetention']
    require(source_archive.is_file(), 'retained windows source archive missing')
    raw = source_archive.read_bytes()
    require(len(raw) == entry['sourceBinding']['sourceArchiveBytes']
            and sha(raw) == entry['sourceBinding']['sourceArchiveSha256'],
            'windows source archive identity differs')
    return build


def check_package_set(package_set):
    require(package_set['schema'] == 'mirrors.s3.package-set/v2',
            'unexpected package-set schema')
    require(package_set['version'] == '0.2.0-rc.1', 'package-set version differs')
    require(package_set['tag']['pushed'] is False and package_set['tag']['remoteAbsent'] is True,
            'package-set claims a remote tag')
    require(package_set['tag']['commit'] == package_set['source']['commit'] == COMMIT,
            'package-set commit differs')
    require(package_set['source']['tree'] == TREE
            and package_set['source']['embeddedVersion'] == '0.2.0-rc.1',
            'package-set source identity differs')
    rows = {artifact['id']: artifact for artifact in package_set['artifacts']}
    require(set(rows) == {'linux-x86_64', 'windows-x86_64'}, 'artifact id set differs')
    for ident in rows:
        require(rows[ident]['sourceBinding']['state'] == 'bound', ident + ' is not bound')
        require(rows[ident]['sourceBinding']['commit'] == COMMIT, ident + ' commit differs')
        require(rows[ident]['retentionIntegrity']['archivePresent'] is True,
                ident + ' retention is not present')
    linux = check_linux(rows['linux-x86_64'])
    windows = check_windows(rows['windows-x86_64'])
    require(windows['sourceFileCount'] == 9207
            and windows['sourceContentTreeDigest']
            == 'e54a22e0ca262b236973db2412f7b7e46fdc5d9489bcfc95e15822005d3b3b40',
            'windows source tree receipt differs')
    superseded = package_set['supersededArtifacts']
    require(len(superseded) == 1, 'superseded artifact row missing')
    old = superseded[0]
    require(old['status'] == 'rejected-rebuild-required'
            and old['comparison']['reuseCondition'] == 'not-met'
            and old['comparison']['identical'] == 8790
            and old['comparison']['totalManifestFiles'] == 8810,
            'rejected October 29 Windows attempt was softened or removed')
    check_artifact(REPO / old['retentionLocation'], old)
    aggregate = package_set['aggregate']
    require(aggregate['state'] == 'partial', 'S3.9 was converted into completion')
    require(aggregate['artifactSetComplete'] is True
            and aggregate['exitCriterionMet'] is True,
            'reconciled artifact set is not recorded as complete')
    require([item['stage'] for item in aggregate['openExternalInputs']] == ['S3.6'],
            'S3.9 partial reason is not limited to S3.6')
    require('S3 completion' in package_set['notClaimed'], 'notClaimed list was weakened')
    return rows['linux-x86_64'], rows['windows-x86_64'], old


def check_inputs(package_set):
    """Confirm the input records still exist and match their recorded digests."""
    reconciliation = package_set['reconciliation']
    record = reconciliation['supersedes']
    original = read(REPO / record['record'])
    require(original['schema'] == record['schema'] == 'mirrors.s3.package-set/v1',
            'superseded package-set schema differs')
    require(sha((REPO / record['record']).read_bytes()) == record['sha256'],
            'superseded package-set record changed')
    checked = 0
    for item in reconciliation['inputs']:
        base = REPO / item['record']
        require(base.is_dir(), 'input record missing: ' + item['record'])
        for key, name in (('ledgerSha256', 's3-ledger.json'),
                          ('windowsBindingSha256', 'windows-binding.json'),
                          ('receiptSha256', 'package-receipt.json')):
            if key in item:
                raw = (base / name).read_bytes()
                require(sha(raw) == item[key], 'input record changed: ' + item['record'] + name)
                checked += 1
    return checked


def validate_ledger(ledger):
    rows = {row['id']: row for row in ledger['rows']}
    require(ledger['schema'] == 'mirrors.s3.reconciled-ledger/v1',
            'unexpected reconciled ledger schema')
    require(set(rows) == {'S3.%d' % n for n in range(1, 10)}, 'unexpected S3 row set')
    for ident in ('S3.1', 'S3.2', 'S3.3', 'S3.4', 'S3.5', 'S3.7', 'S3.8'):
        require(rows[ident]['currentState'] == 'passed', ident + ' is not passed')
    require(rows['S3.6']['currentState'] == 'awaiting-external-input',
            'S3.6 claimed a runtime that was not observed')
    require(rows['S3.9']['currentState'] == 'partial',
            'S3.9 claimed a complete stage')
    require(rows['S3.9']['openDependencies'] == ['S3.6'],
            'S3.9 partial reason is not limited to S3.6')
    attempt = rows['S3.7'].get('supersededAttempt') or {}
    require(attempt.get('state') == 'failed' and attempt.get('record') ==
            'Plans/completion-s3-package-evidence-20261030/',
            'original S3.7 rejection was not retained as a failed attempt')
    prior = rows['S3.8'].get('supersedes') or {}
    require(prior.get('previousClaimLevel') == 'packaging-only-unbound',
            'S3.8 does not identify the superseded packaging-only row')
    return len(rows)


def main():
    manifest = read(ROOT / 'inventory.json')
    count = check_inventory(manifest['files'])
    package_set = read(ROOT / 'package-set.json')
    ledger = read(ROOT / 's3-ledger.json')
    linux, windows, old = check_package_set(package_set)
    rows = validate_ledger(ledger)
    inputs = check_inputs(package_set)

    # Negative controls: records, artifacts and ledger escalation.
    original = manifest['files'][0]
    for bad in (dict(original, path='missing-control-file'), dict(original, sha256='0' * 64)):
        try:
            check_inventory([bad])
        except ValueError:
            pass
        else:
            raise ValueError('inventory negative control was accepted')
    with tempfile.TemporaryDirectory(prefix='mirrors-s3-reconciled-control-') as temporary:
        temporary = Path(temporary)
        fake = temporary / 'missing-artifact'
        for bad in (dict(linux, retentionLocation=str(fake)),):
            try:
                check_artifact(fake, bad)
            except ValueError:
                pass
            else:
                raise ValueError('missing-artifact control was accepted')
        sparse = temporary / 'tampered-artifact'
        sparse.write_bytes(b'')
        with open(sparse, 'wb') as handle:
            handle.truncate(windows['bytes'])
        try:
            check_artifact(sparse, windows)
        except ValueError:
            pass
        else:
            raise ValueError('same-size tampered artifact control was accepted')
        for bad in (dict(windows, sha256='0' * 64),):
            try:
                check_artifact(REPO / windows['retentionLocation'], bad)
            except ValueError:
                pass
            else:
                raise ValueError('tampered artifact digest control was accepted')
    escalated = json.loads(json.dumps(ledger))
    for row in escalated['rows']:
        if row['id'] == 'S3.6':
            row['currentState'] = 'passed'
    try:
        validate_ledger(escalated)
    except ValueError:
        pass
    else:
        raise ValueError('S3.6 escalation control was accepted')
    escalated = json.loads(json.dumps(ledger))
    for row in escalated['rows']:
        if row['id'] == 'S3.9':
            row['currentState'] = 'passed'
    try:
        validate_ledger(escalated)
    except ValueError:
        pass
    else:
        raise ValueError('S3.9 escalation control was accepted')
    ungated = json.loads(json.dumps(package_set))
    ungated['artifacts'][1]['sourceBinding']['state'] = 'rejected-rebuild-required'
    try:
        check_package_set(ungated)
    except (ValueError, KeyError):
        pass
    else:
        raise ValueError('unbound Windows row control was accepted')

    print(json.dumps({
        'status': 'passed',
        'inventoryFiles': count,
        'ledgerRows': rows,
        'inputRecordsVerified': inputs,
        'linuxArtifact': linux['sha256'],
        'windowsArtifact': windows['sha256'],
        'supersededWindowsAttempt': old['sha256'],
        'states': {'S3.6': 'awaiting-external-input', 'S3.9': 'partial'},
        'negativeControls': ['missing-record-file', 'tampered-record-digest',
                             'missing-artifact', 'same-size-tampered-artifact',
                             'tampered-artifact-digest', 's3.6-escalation',
                             's3.9-escalation', 'unbound-windows-row'],
        'claim': 'evidence reconciliation only; no S3 completion, Ubuntu 24.04 '
                 'qualification, publication, deployment or reboot',
    }, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, TypeError) as error:
        print('Completion S3 reconciled record refused: ' + str(error), file=sys.stderr)
        raise SystemExit(1)
