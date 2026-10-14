import hashlib
import json
from pathlib import Path

root=Path('/home/jlc/Tools/mirrors-dpm-followup-20261014')
build=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/followup-20261014')
rows=[]
for name in ['dpm-followup-t2-t3-verification.json','dpm-followup-t1-verification.json']:
    rows.extend(json.loads((build/name).read_text())['files'])
identities=json.loads((build/'identity-refresh.json').read_text())['selectedGeneratedFiles']
rows.extend({'repository':'Mirrors','path':name,'sha256':digest} for name,digest in identities.items())
for row in rows:
    file=root/'source'/row['repository']/row['path']
    assert hashlib.sha256(file.read_bytes()).hexdigest()==row['sha256']
record={'schema':'mirrors.dpm-followup-frozen-inputs/v1','status':'verified',
        'sourceRoot':str(root/'source'),'selectedChanges':rows,
        'baselineCopy':'baseline-copy.json','identityRefresh':'identity-refresh.json',
        'sourceMutationsAfterFreezeAllowed':False}
(build/'frozen-inputs.json').write_text(json.dumps(record,indent=2)+'\n')
print('FROZEN_SELECTED_INPUTS_VERIFIED',len(rows))
