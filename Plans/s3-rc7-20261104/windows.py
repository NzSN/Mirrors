#!/usr/bin/env python3
"""Stage, build and collect approved rc.7 Windows packages without production writes."""
import json
from pathlib import Path

from common import OUT, PLAN, ROOT, SSH, STAGE, identity, remote, run, write

SCP = ['scp', '-F', str(Path.home() / '.ssh/config'), '-o', 'BatchMode=yes',
       '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=20']
REMOTE_DIR = 'win10:D:/ModelMirrors/staging/s3-rc7-20261104-f525c63/'


def main():
    observation = (OUT / 'logs/windows-preflight.stdout').read_text()
    assert 'STAGE_EXISTS False' in observation
    for label in ('lake', 'lean', 'gcc', 'git', 'openssl'):
        assert any(('TOOL\t' + label + '\tpresent=True') in row for row in observation.splitlines()), label
    remote('windows-create-task-stage', "$ErrorActionPreference='Stop'; $stage='" + STAGE + "'; $tmp='D:\\ModelMirrors\\tmp\\s3-rc7-20261104-f525c63'; if((Test-Path -LiteralPath $stage) -or (Test-Path -LiteralPath $tmp)){throw 'task path already exists'}; New-Item -ItemType Directory -Path $stage,$tmp | Out-Null; Write-Output 'TASK STAGE CREATED'")
    source = json.loads((PLAN / 'source-identity.json').read_text())
    paths = [ROOT / source['sourceArchive']['path'], ROOT / source['sourceManifest']['path'],
             PLAN / 'source-identity.json', *[PLAN / name for name in [
                'windows-input.py', 'windows-build.ps1', 'windows-package.ps1',
                'windows-zip.py', 'windows-pe.py', 'windows-final.ps1']]]
    run('windows-transfer-inputs', SCP + [*map(str, paths), REMOTE_DIR], timeout=300)
    python = "& 'D:\\Programs\\Python310\\python.exe' -I -S -B '" + STAGE + "\\windows-input.py' "
    remote('windows-extract-and-dependency', python + 'prepare; exit $LASTEXITCODE', timeout=180)
    remote('windows-build-and-eight-gates', "& '" + STAGE + "\\windows-build.ps1'; exit $LASTEXITCODE", timeout=2400)
    remote('windows-source-after', python + 'after; exit $LASTEXITCODE', timeout=180)
    remote('windows-package', "& '" + STAGE + "\\windows-package.ps1'; exit $LASTEXITCODE", timeout=180)
    remote('windows-final-observation', "& '" + STAGE + "\\windows-final.ps1'; exit $LASTEXITCODE", timeout=60)
    task_count = remote('windows-owned-process-cleanup', "$ErrorActionPreference='Stop'; $rows=@(Get-CimInstance Win32_Process | Where-Object {$_.ExecutablePath -like '" + STAGE + "*'}); Write-Output $rows.Count; if($rows.Count -ne 0){exit 1}")
    assert task_count.strip() == '0'
    dest = OUT / 'windows'
    dest.mkdir(mode=0o700)
    names = ['mirrors-v0.2.0-rc.7-windows-x86_64.zip',
             'mirrors-v0.2.0-rc.7-windows-x86_64-repeat.zip',
             'mirrors-v0.2.0-rc.7-windows-x86_64.build.json',
             'windows-build-record.json', 'windows-gates.json', 'windows-build-environment.json',
             'windows-offline-dependency.json', 'windows-source-before.json', 'windows-source-after.json',
             'source-before.jsonl', 'source-after.jsonl', 'windows-package-archive.json',
             'windows-pe.json', 'windows-final-observation.json']
    for name in names:
        run('windows-download-' + name.replace('.', '-'), SCP + [REMOTE_DIR + name, dest], timeout=300)
    run('windows-download-build-logs', SCP + ['-r', REMOTE_DIR + 'logs', dest], timeout=120)
    sums = ''.join(identity(dest / name)['sha256'] + '  ' + name + '\n' for name in names[:3])
    (dest / 'SHA256SUMS').write_text(sums)
    write(PLAN / 'windows-collected.json', {'published': False, 'deployed': False,
        'stage': STAGE, 'artifacts': [identity(dest / name) for name in names],
        'checksums': identity(dest / 'SHA256SUMS'), 'ownedProcessesRemaining': 0})
    print('WINDOWS BUILD/PACKAGE COLLECTED', flush=True)


if __name__ == '__main__':
    main()
