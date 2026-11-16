"""Record current admission facts without changing historical evidence."""
import hashlib
import json
import platform
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLAN = Path(__file__).resolve().parent
OUT = ROOT / '.golden-build/completion-rc12-20261116'


def identity(path):
    raw = path.read_bytes()
    return {'path': path.relative_to(ROOT).as_posix(), 'bytes': len(raw),
            'sha256': hashlib.sha256(raw).hexdigest()}


def main():
    OUT.mkdir(mode=0o700, parents=True, exist_ok=True)
    (OUT / 'tmp').mkdir(mode=0o700, exist_ok=True)
    unrelated = subprocess.check_output(
        ['git', 'ls-files', '--others', '--exclude-standard', '-z'], cwd=ROOT
    ).decode().split('\0')
    unrelated = [p for p in unrelated if p and not p.startswith('Plans/completion-rc12-20261116/')]
    retained = [identity(ROOT / p) for p in unrelated]
    usage = shutil.disk_usage(ROOT)
    value = {
        'schema': 'mirrors.rc12.continuation-intake/v1',
        'observedAt': datetime.now(timezone.utc).isoformat(),
        'baseRevision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'trackedDiff': subprocess.check_output(['git', 'diff', 'HEAD', '--name-only'], cwd=ROOT, text=True).splitlines(),
        'osRelease': Path('/etc/os-release').read_text(),
        'kernel': platform.release(), 'python': platform.python_version(),
        'storage': {'totalBytes': usage.total, 'freeBytes': usage.free},
        'preservedUnrelatedFiles': retained,
        'selectedEnvironmentObserved': 'Ubuntu 26.04.1 WSL2',
        'authorization': 'user requested resuming and iterating through remaining work',
        'qualificationGranted': False,
    }
    with (PLAN / 'intake.json').open('x') as stream:
        stream.write(json.dumps(value, indent=2) + '\n')
    command = ['ssh', '-F', str(Path.home() / '.ssh/config'), '-o', 'BatchMode=yes',
               '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=10', 'win10',
               "powershell -NoProfile -NonInteractive -Command '$code = [Console]::In.ReadToEnd(); Invoke-Expression $code'"]
    result = subprocess.run(command, input=(PLAN / 'observe-windows.ps1').read_bytes(),
                            capture_output=True, timeout=90)
    (OUT / 'windows-intake.stdout').write_bytes(result.stdout)
    (OUT / 'windows-intake.stderr').write_bytes(result.stderr)
    receipt = {'argv': command, 'exitCode': result.returncode,
               'stdout': identity(OUT / 'windows-intake.stdout'),
               'stderr': identity(OUT / 'windows-intake.stderr')}
    if result.returncode == 0:
        receipt['observation'] = json.loads(result.stdout.decode('utf-8-sig'))
    with (PLAN / 'windows-intake.json').open('x') as stream:
        stream.write(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'unrelatedFilesPreserved': len(retained),
                      'freeBytes': usage.free, 'windows': receipt.get('observation', receipt)}, indent=2))
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
