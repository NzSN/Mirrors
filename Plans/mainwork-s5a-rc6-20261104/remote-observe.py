#!/usr/bin/env python3
"""Observe the owned Windows host without writing files or changing services."""
import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

plan = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', type=Path, required=True)
args = parser.parse_args()
if args.out.exists():
    raise SystemExit('output already exists; retain the earlier observation')
argv = ['ssh', '-F', str(Path.home() / '.ssh/config'), '-o', 'BatchMode=yes',
        '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=15', 'win10',
        "powershell -NoProfile -NonInteractive -Command '$code = [Console]::In.ReadToEnd(); Invoke-Expression $code'"]
try:
    result = subprocess.run(argv, input=(plan / 'windows-observe.ps1').read_text(),
                            text=True, capture_output=True, timeout=55)
    record = {'observedAt': datetime.now(timezone.utc).isoformat(), 'argv': argv,
              'exitCode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}
except (OSError, subprocess.TimeoutExpired) as error:
    record = {'observedAt': datetime.now(timezone.utc).isoformat(), 'argv': argv,
              'exitCode': None, 'error': str(error)}
with args.out.open('x') as stream:
    stream.write(json.dumps(record, indent=2) + '\n')
print(json.dumps(record, indent=2))
