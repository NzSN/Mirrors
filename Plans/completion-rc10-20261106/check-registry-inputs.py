"""Admit machine-specific registered producers before final identity freeze."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];PLAN=Path(__file__).resolve().parent
registry=json.loads((ROOT/'tools/evidence/commands.json').read_text());rows=[]
for command in registry['commands']:
 if command['commandId'] not in ['framework.install-diagnostics','framework.install-diagnostics-gate']:continue
 argv=command['argvPrefix'];profile='checked-replay-gate' if command['commandId'].endswith('-gate') else 'checked-replay-local'
 expected=ROOT/'.golden-build/completion-rc10-20261106/qualification/install'/profile
 assert argv[argv.index('--prefix')+1]==str(expected)
 for flag,pin in [('--framework-catalog-bin','--framework-catalog-sha256'),('--strace','--strace-sha256')]:
  path=Path(argv[argv.index(flag)+1]);sha=hashlib.sha256(path.read_bytes()).hexdigest()
  assert sha==argv[argv.index(pin)+1],(flag,path)
  rows.append({'commandId':command['commandId'],'input':flag,'path':str(path),'sha256':sha})
rows.append({'installedPrefixesBoundBeforeFreeze':True,'receiptManifestBindingRequired':True})
with (PLAN/'registry-input-admission.json').open('x') as stream:stream.write(json.dumps(rows,indent=2)+'\n')
print('REGISTERED RUNTIME/TRACER INPUTS ADMITTED')
