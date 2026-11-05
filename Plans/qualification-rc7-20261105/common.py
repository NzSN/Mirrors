"""Task-local qualification constants, hashing and exclusive command receipts."""
import hashlib
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLAN = Path(__file__).resolve().parent
OUT = ROOT / '.golden-build/qualification-rc7-20261105'
FREEZE = json.loads((ROOT / 'Plans/source-freeze-rc7-20261104/freeze-manifest.json').read_text())
SELECTED = FREEZE['families']['wsl2']
CATALOG = ROOT / SELECTED['catalog']['path']
LOCKS = ROOT / SELECTED['locksRoot']
SNAPSHOT = (ROOT / SELECTED['snapshotIndex']['path']).parent
C3 = ROOT / FREEZE['frameworkCatalog']['path']
C3_SHA = FREEZE['frameworkCatalog']['sha256']
STRACE = ROOT / '.golden-build/mw12-20261103/integration-runtime/strace-pinned'
STRACE_SHA = '0d677426d0a518cf7f3c4f9b6527d1b313752eabb0e3a96d4ec8fa799b4265c7'
ECMA = ROOT / '.golden-build/mw12-20261103/inputs/companions/MirrorECMA'
GATE = ROOT / '.golden-build/mw12-20261103/inputs/companions/MirrorGate'


def identity(path):
    p = Path(path)
    h = hashlib.sha256()
    with p.open('rb') as f:
        for chunk in iter(lambda: f.read(1048576), b''):
            h.update(chunk)
    return {'path': str(p), 'bytes': p.stat().st_size, 'sha256': h.hexdigest()}


def write(path, value):
    with Path(path).open('x') as stream:
        stream.write(json.dumps(value, indent=2) + '\n')


def run(name, argv, *, cwd=ROOT, env=None, timeout=3600, ok=(0,)):
    logs = OUT / 'logs'
    logs.mkdir(mode=0o700, exist_ok=True)
    stdout, stderr = logs / (name + '.stdout'), logs / (name + '.stderr')
    if stdout.exists() or stderr.exists():
        raise ValueError('retain previous command output: ' + name)
    start = datetime.now(timezone.utc).isoformat()
    with stdout.open('xb') as out, stderr.open('xb') as err:
        p = subprocess.run(list(map(str, argv)), cwd=cwd, env=env,
                           stdout=out, stderr=err, timeout=timeout,
                           stdin=subprocess.DEVNULL)
    write(logs / (name + '.json'), {'argv': list(map(str, argv)), 'cwd': str(cwd),
          'startedAt': start, 'finishedAt': datetime.now(timezone.utc).isoformat(),
          'exitCode': p.returncode, 'stdout': identity(stdout), 'stderr': identity(stderr)})
    print(name + ' exit=' + str(p.returncode), flush=True)
    if p.returncode not in ok:
        raise ValueError(name + ' failed; receipt retained')
    return stdout.read_text().strip()


def environment():
    env = dict(os.environ)
    env['TMPDIR'] = str(OUT / 'tmp')
    for key in ['APALACHE_MC', 'APALACHE_JAR', 'TLA2TOOLS_JAR']:
        env.pop(key, None)
    return env
