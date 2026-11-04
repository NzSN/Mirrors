#!/usr/bin/env python3
"""Verify a blocked S5-A observation record, not S5-A admission."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLAN = Path(__file__).resolve().parent


def main():
    inventory = json.loads((PLAN / 'inventory.json').read_text())
    for record in inventory['files']:
        path = ROOT / record['path']
        data = path.read_bytes()
        assert len(data) == record['bytes'], f"size changed: {path}"
        assert hashlib.sha256(data).hexdigest() == record['sha256'], f"hash changed: {path}"
    result = json.loads((PLAN / 'result.json').read_text())
    assert result['status'] == 'blocked-missing-exact-carrier'
    assert result['s5aAccepted'] is False and result['completedDAudits'] == 0
    assert result['cacheBuildPerformed'] is False and result['installPerformed'] is False
    inputs = json.loads((PLAN / 'build-inputs.json').read_text())
    assert inputs['cacheBuildReady'] is False
    carrier = next(v for v in inputs['dependencies'] if v['artifactId'] == 'lean-batteries-source')
    assert carrier['admitted'] is False and carrier['expectedBytes'] == 3739542
    assert carrier['expectedSha256'] == '73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a'
    assert '[Errno 2]' in carrier['error']
    host = ROOT / '.golden-build/mainwork-s5a-rc6-20261104/host'
    preflight = json.loads((host / 'result.json').read_text())
    assert preflight['straceProbePassed'] is True
    assert all(v['matchesFrozen'] for v in preflight['tracerFiles'])
    assert all(v['bindListen'] for v in preflight['socketProbes'])
    assert all(v['locksValidated'] and v['snapshotValidated'] and v['builderMatchesSnapshot']
               for v in preflight['locks'])
    for name in ('unshare-probe', 'bwrap-probe', 'strace-probe'):
        assert json.loads((host / (name + '.json')).read_text())['exitCode'] == 0
    remote_receipt = json.loads((PLAN / 'remote-probe-corrected.json').read_text())
    assert remote_receipt['exitCode'] == 0
    remote = json.loads(remote_receipt['stdout'])
    assert remote['s5aAccepted'] is False and remote['host'] == 'DESKTOP-6DKB5JD'
    assert result['remoteQualificationGranted'] is False
    print('S5-A PREFLIGHT RECORD VERIFIED; S5-A REMAINS BLOCKED')


if __name__ == '__main__':
    main()
