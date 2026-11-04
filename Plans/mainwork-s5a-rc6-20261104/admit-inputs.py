#!/usr/bin/env python3
"""Check the selected local build inputs without starting a cache build."""
import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/distribution'))
from distribution_lib import runtime_tree, sha256_file
from install import check_case_sensitive, reject_symlink_chain

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--batteries-bundle', type=Path, default=ROOT / (
    '.golden-build/batteries-repin-20261031/artifacts/sha256/'
    '73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a/batteries-v4.33.0.bundle'))
args = parser.parse_args()
if args.out.exists():
    raise SystemExit('output already exists')
lock = json.loads((ROOT / 'distribution/reference-node-wsl2-26.04/dependency-lock.json').read_text())
deps = {v['artifactId']: v for v in lock['dependencies']}
rows = []
for name, path in [
    ('node-runtime', ROOT / '.golden-build/version-0.1/toolchains/node-v24.15.0-linux-x64.tar.xz'),
    ('lean-batteries-source', args.batteries_bundle),
]:
    expected = deps[name]
    row = {'artifactId': name, 'path': str(path), 'expectedBytes': expected['bytes'],
           'expectedSha256': expected['sha256'], 'admitted': False}
    try:
        size, digest = sha256_file(path)
        row.update(bytes=size, sha256=digest,
                   admitted=(size == expected['bytes'] and digest == expected['sha256']))
    except OSError as error:
        row['error'] = str(error)
    rows.append(row)
trees = []
for name, rel in [('typescript-node-modules', '.golden-build/rc3-s5-20261031/ts-deps'),
                  ('evidence-wheels', '.golden-build/rc3-s5-20261031/prepared/evidence-wheels')]:
    path = ROOT / rel
    trees.append({'inputId': name, 'path': str(path), **runtime_tree(path),
                  'selection': 'operator-explicit retained input; digest recorded, no historical qualification transferred'})
tools = []
for name, path in [('lean', Path.home() / '.elan/bin/lean'),
                   ('lake', Path.home() / '.elan/bin/lake'), ('python', Path('/usr/bin/python3')),
                   ('git', Path('/usr/bin/git')), ('ldd', Path('/usr/bin/ldd'))]:
    result = subprocess.run([str(path), '--version'], capture_output=True, text=True, timeout=30, cwd=ROOT)
    size, digest = sha256_file(path.resolve())
    tools.append({'tool': name, 'path': str(path), 'resolved': str(path.resolve()),
                  'bytes': size, 'sha256': digest, 'exitCode': result.returncode,
                  'stdout': result.stdout, 'stderr': result.stderr})
stage = ROOT / '.golden-build/mainwork-s5a-rc6-20261104/host'
reject_symlink_chain(stage.resolve())
check_case_sensitive(stage)
value = {'schema': 'mirrors.s5a-rc6.build-input-admission/v1',
         'observedAt': datetime.now(timezone.utc).isoformat(), 'dependencies': rows,
         'operatorInputTrees': trees, 'tools': tools, 'caseSensitiveStage': True,
         'stageUid': stage.stat().st_uid, 'stageMode': oct(stage.stat().st_mode & 0o777),
         'cacheBuildReady': all(r['admitted'] for r in rows), 'cacheBuildPerformed': False,
         's5aAccepted': False}
with args.out.open('x') as stream:
    stream.write(json.dumps(value, indent=2) + '\n')
print(json.dumps({'cacheBuildReady': value['cacheBuildReady'], 'dependencies': rows}, indent=2))
raise SystemExit(0 if value['cacheBuildReady'] else 2)
