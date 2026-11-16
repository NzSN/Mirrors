"""Verify all clean Windows blobs, package native bytes, and retain bounded receipts."""
from common import *


def main():
    native = json.loads((OUT / 'logs/native-clean-build-full-test.json').read_text())
    assert native['exitCode'] == 0
    assert 'RC12 FULL WINDOWS INCLUDING NATIVE RUST GREEN' in (OUT / 'logs/native-clean-build-full-test.stdout').read_text()
    scp = ['scp', '-F', str(Path.home() / '.ssh/config'), '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes']
    helpers = [PLAN / name for name in ['windows-source-verify.py', 'windows-package.py', 'windows-pe.py']]
    run('native-package-helper-transfer', scp + helpers + ['win10:D:/ModelMirrors/staging/completion-rc12-20261116/'], timeout=180)
    script = r'''
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$stage='D:\ModelMirrors\staging\completion-rc12-20261116'
$python='D:\ModelMirrors\staging\windows-fixes-20261106\python312-completion\python3.exe'
$env:PYTHONUTF8='1';$env:PYTHONIOENCODING='utf-8'
foreach($name in @('windows-source-verify','windows-package')) {
 $log=$stage+'\'+$name+'.log'
 if(Test-Path -LiteralPath $log){throw 'retain prior package attempt'}
 $line='"'+$python+'" "'+$stage+'\'+$name+'.py" > "'+$log+'" 2>&1'
 & cmd.exe /d /s /c $line
 if($LASTEXITCODE -ne 0){throw ('native package helper failed: '+$name)}
 Write-Output ($name+' EXIT 0')
}
'''
    remote('native-verify-and-package', script, timeout=900)
    receipts = OUT / 'windows-receipts'
    receipts.mkdir(mode=0o700)
    names = ['rc12-clean-build.json', 'rc12-clean-full-test.json', 'rc12-clean-full-test.log',
             'source-verification.json', 'windows-package-result.json', 'windows-pe.json',
             'mirrors-' + TAG + '-windows-x86_64.zip']
    for name in names:
        run('native-retain-' + name, scp + ['win10:D:/ModelMirrors/staging/completion-rc12-20261116/' + name, receipts / name], timeout=300)
    package = json.loads((receipts / 'windows-package-result.json').read_text())
    verification = json.loads((receipts / 'source-verification.json').read_text())
    full = json.loads((receipts / 'rc12-clean-full-test.json').read_text(encoding='utf-8-sig'))
    full_log = identity(receipts / 'rc12-clean-full-test.log')
    assert full['exitCode'] == 0 and full['sha256'] == full_log['sha256']
    raw = (receipts / 'rc12-clean-full-test.log').read_bytes()
    for marker in [b'NATIVE RUST GENERATED BINDING EXECUTION GREEN', b'ALL LAKE TESTS GREEN', b'TASK JOB CLEANUP active=0']:
        assert marker in raw
    assert b'SKIP Rust generated binding execution' not in raw
    assert verification['status'] == 'passed' and verification['commit'] == COMMIT and verification['tree'] == TREE
    assert verification['gitBlobsVerified'] == json.loads((PLAN / 'source-identity.json').read_text())['fileCount']
    archive = identity(receipts / package['archive']['name'])
    assert archive['sha256'] == package['archive']['sha256'] and archive['bytes'] == package['archive']['bytes']
    assert package['repeatIdentical'] and package['restrictedPathSmoke'] and package['peClosurePassed']
    assert package['package']['sourceCommit'] == COMMIT and not package['package']['sourceOverlay']
    write(PLAN / 'windows-package.json', package)
    write(PLAN / 'windows-full-result.json', {'schema': 'mirrors.rc12.windows-full-validation/v1',
          'status': 'exact-source-full-native-driver-passed', 'sourceCommit': COMMIT, 'sourceTree': TREE,
          'gitBlobsVerified': verification['gitBlobsVerified'], 'sourceOverlay': False,
          'fullLakeTest': True, 'actualNativeRustExecution': True, 'ownedJobCleanupActive': 0,
          'fullLog': full_log, 'nativeReceipt': identity(receipts / 'rc12-clean-full-test.json'),
          'sourceVerification': identity(receipts / 'source-verification.json'),
          'published': False, 'deployed': False})
    print('EXACT SOURCE, FULL WINDOWS DRIVER AND REPEATABLE WINDOWS PACKAGE VERIFIED', flush=True)


if __name__ == '__main__':
    main()
