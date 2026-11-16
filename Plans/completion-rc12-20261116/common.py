"""Owned rc.12 execution paths and append-only command receipts."""
import hashlib
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLAN = Path(__file__).resolve().parent
OUT = ROOT / '.golden-build/completion-rc12-20261116'
TAG = 'v0.2.0-rc.12'
STAGE = r'D:\ModelMirrors\staging\completion-rc12-20261116'
ECMA = ROOT / '.golden-build/mw12-20261103/inputs/companions/MirrorECMA'
GATE = ROOT / '.golden-build/completion-rc10-20261106/MirrorGate-ordering-fix'
SSH = ['ssh', '-F', str(Path.home() / '.ssh/config'), '-o', 'BatchMode=yes',
       '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=20', 'win10']


def identity(path):
    p = Path(path)
    digest = hashlib.sha256()
    with p.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return {'path': p.relative_to(ROOT).as_posix(), 'bytes': p.stat().st_size,
            'sha256': digest.hexdigest()}


def write(path, value):
    with Path(path).open('x', encoding='utf-8') as stream:
        stream.write(json.dumps(value, indent=2) + '\n')


def environment():
    result = dict(os.environ)
    result['TMPDIR'] = str(OUT / 'tmp')
    Path(result['TMPDIR']).mkdir(mode=0o700, parents=True, exist_ok=True)
    result['PYTHONDONTWRITEBYTECODE'] = '1'
    result['RUST_REPO'] = str(ROOT / '.golden-build/completion-20261029/MirrorRust')
    result['RUSTUP_TOOLCHAIN'] = '1.96.0'
    result['MIRRORCPP_PREFIX'] = str(ROOT / '.golden-build/qualification-rc7-20261105/cpp-prefix-windows-fix')
    for key in ['APALACHE_MC', 'APALACHE_JAR', 'TLA2TOOLS_JAR', 'MIRRORS_ASYNC_RESOURCE_E2E']:
        result.pop(key, None)
    return result


def run(name, argv, *, cwd=ROOT, env=None, stdin=None, timeout=3600, ok=(0,)):
    logs = OUT / 'logs'
    logs.mkdir(mode=0o700, parents=True, exist_ok=True)
    stdout, stderr, receipt = [logs / (name + suffix) for suffix in ['.stdout', '.stderr', '.json']]
    if any(path.exists() for path in [stdout, stderr, receipt]):
        raise ValueError('retain previous attempt: ' + name)
    started = datetime.now(timezone.utc).isoformat()
    timed_out = False
    with stdout.open('xb') as out, stderr.open('xb') as err:
        try:
            process = subprocess.run(list(map(str, argv)), cwd=cwd, env=env,
                                     input=stdin.encode('utf-8') if stdin is not None else None,
                                     stdout=out, stderr=err, timeout=timeout)
            code = process.returncode
        except subprocess.TimeoutExpired:
            code = 124
            timed_out = True
    write(receipt, {'name': name, 'argv': list(map(str, argv)), 'cwd': str(cwd),
                    'startedAt': started, 'finishedAt': datetime.now(timezone.utc).isoformat(),
                    'exitCode': code, 'timedOut': timed_out,
                    'stdout': identity(stdout), 'stderr': identity(stderr)})
    print(name + ' exit=' + str(code), flush=True)
    if code not in ok:
        raise ValueError(name + ' failed; logs retained')
    return stdout.read_text(encoding='utf-8-sig').strip()


def remote(name, script, *, timeout=90):
    return run(name, SSH + ["powershell -NoProfile -NonInteractive -Command '$code = [Console]::In.ReadToEnd(); Invoke-Expression $code'"],
               stdin=script, timeout=timeout)


freeze_path = PLAN / 'rc12-freeze-manifest.json'
if freeze_path.exists():
    FREEZE = json.loads(freeze_path.read_text())
    SOURCE = ROOT / FREEZE['taskOwnedSource']
    COMMIT = FREEZE['freezeRevision']
    TREE = FREEZE['freezeTree']
    C3 = ROOT / FREEZE['frameworkCatalog']['path']
    C3_SHA = FREEZE['frameworkCatalog']['sha256']
