import json
from pathlib import Path
import subprocess

build=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/followup-20261014')
ctest='/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/cmake-python/cmake/data/bin/ctest'
raw=subprocess.check_output([ctest,'--test-dir',str(build/'sdk-cpp'),'--show-only=json-v1'])
(build/'ctest-metadata.json').write_bytes(raw)
data=json.loads(raw)
tests=[test for test in data['tests'] if any('mirrorcpp_schedule_sync_test' in part for part in test.get('command',[]))]
assert len(tests)==27,len(tests)
assert all(any(prop['name']=='TIMEOUT' and prop['value']==30.0 for prop in test['properties']) for test in tests),tests
(build/'ctest-timeout-check.json').write_text(json.dumps({'status':'passed','tests':tests},indent=2)+'\n')
print('CTEST_SYNC_TIMEOUT_30_SECONDS_VERIFIED')
