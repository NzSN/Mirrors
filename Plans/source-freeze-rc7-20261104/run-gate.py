#!/usr/bin/env python3
"""Run the authorized local no-model aggregate and bind stable source identities."""
import hashlib
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLAN = Path(__file__).resolve().parent
OUT = ROOT / '.golden-build/source-freeze-rc7-20261104'
sys.path.insert(0, str(ROOT / 'tools/distribution'))
from refresh_identity import selected_refs

ECMA = ROOT / '.golden-build/mw12-20261103/inputs/companions/MirrorECMA'
GATE = ROOT / '.golden-build/mw12-20261103/inputs/companions/MirrorGate'


def main():
    log = OUT / 'full-local-no-model.log'
    receipt = PLAN / 'gate-result.json'
    if log.exists() or receipt.exists():
        raise SystemExit('retain the earlier attempt; select new output paths before retrying')
    before = selected_refs(ECMA, GATE)
    assert before['mirrors']['dirty'] is True
    assert before['mirrorecma']['dirty'] is False and before['mirrorgate']['dirty'] is False
    environment = dict(os.environ)
    environment['TMPDIR'] = str(OUT / 'tmp')
    started_at = datetime.now(timezone.utc).isoformat()
    started = time.monotonic()
    print('Starting authorized full local non-model gate; log: ' + str(log), flush=True)
    with log.open('xb') as output:
        p = subprocess.run(['bash', 'tools/run-local-no-model-check.sh'], cwd=ROOT,
                           env=environment, stdout=output, stderr=subprocess.STDOUT,
                           stdin=subprocess.DEVNULL)
    after = selected_refs(ECMA, GATE)
    data = log.read_bytes()
    passed = p.returncode == 0 and b'ALL LOCAL NON-MODEL GATES GREEN' in data and before == after
    value = {'schema': 'mirrors.rc7-source-freeze-gate/v1', 'startedAt': started_at,
             'finishedAt': datetime.now(timezone.utc).isoformat(), 'seconds': time.monotonic() - started,
             'argv': ['bash', 'tools/run-local-no-model-check.sh'], 'cwd': str(ROOT),
             'tmpdir': environment['TMPDIR'], 'exitCode': p.returncode, 'passed': passed,
             'sourceAndCompanionsStable': before == after, 'before': before, 'after': after,
             'log': {'path': log.relative_to(ROOT).as_posix(), 'bytes': len(data),
                     'sha256': hashlib.sha256(data).hexdigest()},
             'nativePrefixSet': bool(environment.get('MIRRORCPP_PREFIX')),
             'liveModelOrWindowsQualificationGranted': False}
    with receipt.open('x') as stream:
        stream.write(json.dumps(value, indent=2) + '\n')
    print(json.dumps({'passed': passed, 'exitCode': p.returncode, 'seconds': value['seconds'],
                      'sourceAndCompanionsStable': value['sourceAndCompanionsStable']}, indent=2), flush=True)
    raise SystemExit(0 if passed else 1)


if __name__ == '__main__':
    main()
