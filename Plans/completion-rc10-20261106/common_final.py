"""Task-local S3 constants and retained-command receipts."""
import hashlib
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLAN = Path(__file__).resolve().parent
OUT = ROOT / '.golden-build/completion-rc10-20261106'
FREEZE = json.loads((PLAN/'rc10-final-freeze.json').read_text())
SOURCE = ROOT/FREEZE['taskOwnedSource']
TAG = 'v0.2.0-rc.10'
COMMIT = FREEZE['freezeRevision']
TREE = FREEZE['freezeTree']
STAGE = r'D:\ModelMirrors\staging\completion-rc10-20261106'
WINDOWS_SOURCE = STAGE + r'\source'
SSH = ['ssh', '-F', str(Path.home() / '.ssh/config'), '-o', 'BatchMode=yes',
       '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=20', 'win10']


def identity(path):
    p = Path(path)
    h = hashlib.sha256()
    with p.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return {'path': p.relative_to(ROOT).as_posix(), 'bytes': p.stat().st_size,
            'sha256': h.hexdigest()}


def write(path, value):
    with Path(path).open('x', encoding='utf-8') as stream:
        stream.write(json.dumps(value, indent=2) + '\n')


def run(name, argv, *, cwd=ROOT, env=None, stdin=None, timeout=3600, ok=(0,)):
    logs = OUT / 'logs'
    logs.mkdir(mode=0o700, exist_ok=True)
    stdout = logs / (name + '.stdout')
    stderr = logs / (name + '.stderr')
    record = logs / (name + '.json')
    if any(p.exists() for p in [stdout, stderr, record]):
        raise ValueError('retain previous attempt: ' + name)
    started = datetime.now(timezone.utc).isoformat()
    with stdout.open('xb') as out, stderr.open('xb') as err:
        p = subprocess.run(list(map(str, argv)), cwd=cwd, env=env,
                           input=stdin.encode('utf-8') if stdin is not None else None,
                           stdout=out, stderr=err, timeout=timeout)
    write(record, {'name': name, 'argv': list(map(str, argv)), 'cwd': str(cwd),
                   'startedAt': started, 'finishedAt': datetime.now(timezone.utc).isoformat(),
                   'exitCode': p.returncode, 'stdout': identity(stdout), 'stderr': identity(stderr)})
    print(name + ' exit=' + str(p.returncode), flush=True)
    if p.returncode not in ok:
        raise ValueError(name + ' failed; logs retained')
    return stdout.read_text(encoding='utf-8').strip()


def remote(name, script, *, timeout=60):
    return run(name, SSH + ["powershell -NoProfile -NonInteractive -Command '$code = [Console]::In.ReadToEnd(); Invoke-Expression $code'"],
               stdin=script, timeout=timeout)


def environment():
    value=dict(os.environ);value['TMPDIR']=str(OUT/'tmp')
    for key in ['APALACHE_MC','APALACHE_JAR','TLA2TOOLS_JAR']:value.pop(key,None)
    return value

ECMA=ROOT/'.golden-build/mw12-20261103/inputs/companions/MirrorECMA'
GATE=ROOT/ FREEZE['companionOrderingFix']['source']
C3=ROOT/FREEZE['frameworkCatalog']['path']
C3_SHA=FREEZE['frameworkCatalog']['sha256']
