"""Task-local S3 constants and retained-command receipts."""
import hashlib
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLAN = Path(__file__).resolve().parent
OUT = ROOT / '.golden-build/s3-rc7-20261104'
SOURCE = OUT / 'source'
TAG = 'v0.2.0-rc.7'
COMMIT = 'f525c6349dc5a5e457757fa040c89312c6703e3a'
TREE = '7b8bd98ac69a94497aa66cfe85885e15638d30db'
STAGE = r'D:\ModelMirrors\staging\s3-rc7-20261104-f525c63'
WINDOWS_SOURCE = STAGE + r'\mirrors-v0.2.0-rc.7'
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
