#!/usr/bin/env python3
"""Preflight loopback and an ext4 task-owned temporary root before local gates."""
import json, socket, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
temp = ROOT/'tmp/completion-20261030'
temp.mkdir(parents=True, exist_ok=True)
s = socket.socket(); s.bind(('127.0.0.1', 0)); port = s.getsockname()[1]; s.listen(1)
try:
    peer = socket.create_connection(('127.0.0.1', port), timeout=2); peer.close()
finally:
    s.close()
fs = subprocess.run(['stat','-f','-c','%T',str(temp)], text=True, capture_output=True, check=True).stdout.strip()
prefix = ROOT/'.golden-build/completion-20261029/cpp-prefix'
data = {'schema':'mirrors.completion-gate-preflight/v1','date':'2026-10-30',
 'loopback':{'bind':'127.0.0.1','ephemeralPort':port,'connect':'ok'},
 'tempRoot':str(temp),'filesystem':fs,'ext4':fs in ('ext4','ext2/ext3'),
 'mirrorcppPrefix':str(prefix),'mirrorcppPrefixValid':(prefix/'include').is_dir() and (prefix/'lib').is_dir(),
 'mirrorsDpmPython':subprocess.run(['python3','-c','import sys;print(sys.executable)'],text=True,capture_output=True).stdout.strip(),
 'liveTierPolicy':'live model tiers stay skipped; no local Apalache/TLC'}
out = ROOT/'Plans/completion-release-evidence-20261030/s1-gate-preflight.json'
out.write_text(json.dumps(data, indent=2, sort_keys=True)+'\n')
print(json.dumps(data, indent=1))
raise SystemExit(0 if data['loopback']['connect']=='ok' and data['ext4'] and data['mirrorcppPrefixValid'] else 1)
