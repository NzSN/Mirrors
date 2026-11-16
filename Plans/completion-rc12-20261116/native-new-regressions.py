
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
