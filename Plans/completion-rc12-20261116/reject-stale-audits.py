"""Reject actual sealed mixed-candidate D attempts using both independent paths."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];PLAN=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'tools/evidence'))
import collect,qualification_scope
prior=ROOT/'Plans/completion-iteration-20261106'
results=json.loads((prior/'rc9-registered-installed-audits.json').read_text())['results']
controls=[]
for item in results:
 profile=item['profile'];audit=ROOT/'.golden-build/completion-iteration-20261106/qualification/audit'/profile
 filename='install-diagnostics-gate.json' if profile.endswith('gate') else 'install-diagnostics.json'
 captured={'install-diagnostics':(audit/filename).read_bytes(),'distribution-manifest':(audit/'distribution-manifest.json').read_bytes(),'cache-index':(audit/'cache-index.json').read_bytes()}
 manifest=json.loads(captured['distribution-manifest']);selection=manifest['catalogSelectionRef']
 plan=type('Plan',(),{'adapter_artifact_id':'install-diagnostics'})()
 try:collect._installed_audit_outcomes(plan,captured,collect.ChildObservation(0,False,False,b'',b'',False,False),selection,manifest['componentRefs'])
 except ValueError as error:
  assert 'does not bind' in str(error);controls.append({'profile':profile,'validator':'collector','reason':str(error)})
 else:raise AssertionError('collector admitted stale audit')
 bundle=Path(item['finalized']['bundle']);envelope=json.loads((bundle/'envelope.json').read_text())
 try:qualification_scope._distribution_binding(bundle,envelope,selection)
 except ValueError as error:
  assert 'does not bind' in str(error);controls.append({'profile':profile,'validator':'independent-scope','reason':str(error)})
 else:raise AssertionError('independent scope admitted stale audit')
with (PLAN/'stale-audit-negative-controls.json').open('x') as stream:stream.write(json.dumps({'status':'all-four-real-mixed-audit-controls-rejected','controls':controls},indent=2)+'\n')
print('REAL STALE AUDIT CONTROLS REJECTED',len(controls))
