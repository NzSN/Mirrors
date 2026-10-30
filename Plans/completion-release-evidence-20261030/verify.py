#!/usr/bin/env python3
"""Offline verifier for the 2026-10-30 completion execution record.

Verifies this directory's inventory, the S2 delivery manifest, the candidate
freeze, the S1 gate snapshot, the stage ledger and the payload audit. It never
executes retained payloads and never contacts a service.
"""
import hashlib, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
SECRETS = [re.compile(rb'-----BEGIN ' + rb'[A-Z0-9 ]*PRIVATE KEY-----'),
           re.compile(rb'PuTTY-User-Key' + rb'-File'),
           re.compile(rb'AKIA' + rb'[0-9A-Z]{16}'), re.compile(rb'gh[pousr]' + rb'_[A-Za-z0-9]{36}')]

def sha(raw): return hashlib.sha256(raw).hexdigest()
def blob(raw): return hashlib.sha1(b'blob %d\0' % len(raw) + raw).hexdigest()
def read(path): return json.loads(path.read_text(encoding='utf-8'))
def require(ok, message):
    if not ok: raise ValueError(message)

def check_inventory(entries):
    require(type(entries) is list and entries, 'empty inventory')
    seen = set()
    for entry in entries:
        name = entry['path']
        require(isinstance(name, str) and name not in seen and not Path(name).is_absolute()
                and '..' not in Path(name).parts, 'invalid or duplicate inventory path')
        seen.add(name)
        path = ROOT/name
        require(path.is_file() and not path.is_symlink() and path.resolve().is_relative_to(ROOT.resolve()),
                'missing or escaping artifact: '+name)
        raw = path.read_bytes()
        require(len(raw) == entry['bytes'] and sha(raw) == entry['sha256'], 'artifact identity differs: '+name)
        for pattern in SECRETS:
            require(not pattern.search(raw), 'private credential material in: '+name)

def check_delivery():
    freeze = read(ROOT/'candidate-freeze.json')
    delivery = read(ROOT/'s2-delivery-payload.json')
    files = delivery['files']
    require(delivery['deliveryManifestSha256'] == freeze['identities']['deliveryManifestSha256'],
            'freeze/delivery manifest identity differs')
    digest = hashlib.sha256()
    for entry in sorted(files, key=lambda item: item['path']):
        path = REPO/entry['path']
        require(path.is_file() and not path.is_symlink(), 'missing delivery file: '+entry['path'])
        raw = path.read_bytes()
        require(len(raw) == entry['bytes'] and sha(raw) == entry['sha256']
                and blob(raw) == entry['gitBlobSha1'], 'delivery bytes differ: '+entry['path'])
        require(not entry['path'].startswith('Plans/completion-release-evidence-20261030/'),
                'execution record leaked into the S2 payload')
        require(entry['path'] != '.projectile-cache.eld', 'unrelated editor cache in delivery')
        digest.update(entry['path'].encode()+b'\0'+entry['sha256'].encode()+b'\n')
    require(digest.hexdigest() == delivery['deliveryManifestSha256'], 'recomputed delivery manifest differs')
    require(len(files) == freeze['identities']['deliveryFileCount'], 'delivery file count differs')
    require({e['path'] for e in delivery['exclusions']} >=
            {'.projectile-cache.eld'} | {e['path'] for e in files if e['path'].startswith('Plans/completion-release-evidence-20261030/')},
            'required exclusions missing')
    return len(files)

def check_ledger():
    ledger = read(ROOT/'s0-stage-ledger.json')
    rows = {row['id']: row for row in ledger['rows']}
    for ident in ['S0.1','S0.2','S0.3','S0.4','S1.1','S1.2','S1.3','S1.4','S1.5','S1.6']:
        require(rows[ident]['currentState'] == 'passed', ident+' is not passed')
        require(rows[ident]['claimLevel'] == 'source-validated', ident+' claim broadened')
    require(rows['S1.7']['currentState'] != 'passed', 'S1.7 approval was claimed without a user approval')
    for ident, row in rows.items():
        if ident.startswith(('S2','S3','S4','S5','S6','S7','S8')) or ident == 'S1.7':
            require(row['currentState'] != 'passed', ident+' was credited without authorization')
    return len(rows)

def check_checks():
    checks = read(ROOT/'s1-checks.json')
    ids = {item['id']: item for item in checks['commands']}
    require(ids['local-no-model']['exit'] == 0 and 'ALL LOCAL NON-MODEL GATES GREEN' in ids['local-no-model']['result'],
            'local no-model gate is not green')
    require(ids['native-rebuild']['exit'] == 0, 'native rebuild gate did not pass')
    require(ids['october29-verifier']['exit'] == 0, 'October 29 verifier did not pass')
    for item in checks['commands']:
        if 'log' in item:
            log = REPO/item['log']['path']
            raw = log.read_bytes()
            require(len(raw) == item['log']['bytes'] and sha(raw) == item['log']['sha256'],
                    'retained log differs: '+item['log']['path'])
    audit = read(ROOT/'s1-payload-audit.json')
    require(audit['verdict'] == 'pass' and not audit['secretFindings'], 'payload audit did not pass')
    require(audit['evidenceTracking']['october29IgnoredFiles'] == [] and
            audit['evidenceTracking']['newRecordIgnoredFiles'] == [], 'intended evidence is ignored')
    return len(checks['commands'])

def main():
    manifest = read(ROOT/'inventory.json')
    check_inventory(manifest['files'])
    count = check_delivery()
    rows = check_ledger()
    commands = check_checks()
    original = manifest['files'][0]
    for bad in [dict(original, path='missing-control-artifact'), dict(original, sha256='0'*64)]:
        try:
            check_inventory([bad])
        except ValueError:
            pass
        else:
            raise ValueError('inventory negative control was accepted')
    print(json.dumps({'status':'passed','inventoryFiles':len(manifest['files']),
                      'deliveryFiles':count,'ledgerRows':rows,'checkedCommands':commands,
                      'negativeControls':['missing-artifact','tampered-digest'],
                      'claim':'source-validated only','publicationOrDeployment':False}, sort_keys=True))

if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, TypeError) as error:
        print('Completion execution record refused: '+str(error), file=sys.stderr)
        raise SystemExit(1)
