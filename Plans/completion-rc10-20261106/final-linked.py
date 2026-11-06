"""Create new R1 reproductions from fresh, finalized rc.10 R0 bytes."""
from evidence_final import *
def result(cid):return json.loads((BASE/'producer-runs'/(cid+'.json')).read_text())
def artifact(cid,aid):
 bundle=Path(result(cid)['bundle']);idx=json.loads((bundle/'bundle-index.json').read_text());return bundle/next(x['path'] for x in idx['records'] if x.get('artifactId')==aid)
def main():
 runtime,_=installed('checked-replay-local');gate,_=installed('checked-replay-gate');env=base_environment();env['TMPDIR']='/tmp/mrc10-final-linked';Path(env['TMPDIR']).mkdir(mode=0o700,exist_ok=False);env['MIRRORS_INSTALLED_RUNTIME']=str(runtime);env['MIRRORS_INSTALLED_GATE_RUNTIME']=str(gate)
 cid='framework.lease-origin-installed';root=BASE/'outputs'/cid;plan=attachment_for(cid,root);collect('rc10-c0-final-lease-origin',cid,cwd=runtime,tail=[root],env=env,attachment_plan=plan,expected_exit=1)
 for cid,origin,aid,project in [('framework.reproduction','framework.replay-faulty','replay-faulty','reference-project'),('framework.reproduction-lease','framework.lease-origin-installed','lease-origin','lease-project')]:
  root=BASE/'outputs'/cid;existing={'r0-envelope.json':Path(result(origin)['bundle'])/'envelope.json','r0-suite-result.json':artifact(origin,aid)};plan=attachment_for(cid,root,existing)
  tail=[root/'reproduction-bundle.json','--evidence-envelope',root/'r0-envelope.json','--artifact-store',root.parent/(cid+'-artifact-store'),'--output-root',root]
  collect('rc10-c0-final-linked-'+cid,cid,cwd=runtime,tail=tail,env=env,attachment_plan=plan)
 cid='framework.recovery-origin-installed';root=BASE/'outputs'/(cid+'-prepared');plan=attachment_for(cid,root,{'recovery-manifest.json':gate/'examples/counter-suite/public-manifest.json'})
 env['PYTHONPATH']=str(gate/'gate/mirrorgate-supervisor')
 origin=collect('rc10-c0-final-prepared-recovery-origin',cid,cwd=gate,tail=[root],env=env,attachment_plan=plan,expected_exit=74,require_qualified=False)
 cid='mirrorgate.recovery';target=BASE/'outputs'/cid;plan=attachment_for(cid,target,{'recovery-origin-envelope.json':Path(origin['bundle'])/'envelope.json','recovery-origin.json':artifact('framework.recovery-origin-installed','recovery-origin')})
 tail=[root/'fixture/state','--run-ref',origin['privateRunRef']['runId'],'--envelope-sha256',origin['privateRunRef']['envelopeSha256'],'--original-behavior','failed','--original-cleanup','unconfirmed','--receipt',target/'recovery-receipt.json']
 collect('rc10-c0-final-prepared-recovery-reclaim',cid,cwd=gate/'gate/mirrorgate-supervisor',tail=tail,env=env,attachment_plan=plan)
 print('RC10 R1 AND PREPARED RECOVERY GREEN',flush=True)
if __name__=='__main__':main()
