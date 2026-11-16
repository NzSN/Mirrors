"""Retain explicit native results for the new identity and installer regressions."""
import base64
from common import *


def main():
    code = r'''
import hashlib,io,json,sys,unittest
from pathlib import Path
root=Path(r'D:\ModelMirrors\staging\completion-rc12-20261116\source')
sys.path[:0]=[str(root/'tools/deterministic-scheduling/tests'),str(root/'tools/distribution')]
names=['test_dpm_host.OracleAdmissionTests.test_remote_oracle_identity_preserves_boolean_and_integer_types',
'test_install.InstallTransactionTests.test_restart_recovers_selector_and_journal_write_temporaries',
'test_install.InstallTransactionTests.test_restart_refuses_unsafe_or_unknown_transaction_temporaries']
suite=unittest.defaultTestLoader.loadTestsFromNames(names)
assert suite.countTestCases()==3
log=io.StringIO();result=unittest.TextTestRunner(stream=log,verbosity=2).run(suite)
discovered=unittest.defaultTestLoader.discover(str(root/'tools/deterministic-scheduling/tests'))
value={'status':'passed' if result.wasSuccessful() else 'failed','testsRun':result.testsRun,'skipped':len(result.skipped),'failures':len(result.failures),'errors':len(result.errors),'caseIds':names,'nativeDpmDiscoveryCount':discovered.countTestCases(),'python':sys.version,'log':log.getvalue(),'sourceCommit':'6882d5b8b4787977e847e5a77467b30bfdac19a2'}
print(json.dumps(value,indent=2));raise SystemExit(0 if result.wasSuccessful() else 1)
'''
    encoded = base64.b64encode(code.encode()).decode()
    script = r'''
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$stage='D:\ModelMirrors\staging\completion-rc12-20261116'
$driver=$stage+'\native-new-regressions.py'
$log=$stage+'\native-new-regressions.json'
if((Test-Path -LiteralPath $driver) -or (Test-Path -LiteralPath $log)){throw 'retain native regression attempt'}
[IO.File]::WriteAllBytes($driver,[Convert]::FromBase64String('PYTHON_BASE64'))
$python='D:\ModelMirrors\staging\windows-fixes-20261106\python312-completion\python3.exe'
$env:PYTHONUTF8='1';$env:PYTHONIOENCODING='utf-8'
$line='"'+$python+'" -I -S -B "'+$driver+'" > "'+$log+'" 2>&1'
& cmd.exe /d /s /c $line
if($LASTEXITCODE -ne 0){throw 'native new regressions failed; log retained'}
[IO.File]::ReadAllText($log)
'''.replace('PYTHON_BASE64', encoded)
    value = json.loads(remote('native-new-review-regressions', script, timeout=180))
    assert value['testsRun'] == 3 and value['skipped'] == 0 and value['status'] == 'passed'
    assert value['nativeDpmDiscoveryCount'] >= 90
    write(PLAN / 'native-new-regressions.json', value)
    print(json.dumps({key: item for key, item in value.items() if key not in ['log', 'python']}, indent=2))


if __name__ == '__main__':
    main()
