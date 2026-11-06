"""Construct the actual nineteen-node graph and collect its Q verification."""
import json
from evidence_rc10 import *

def main():
 audits=json.loads((PLAN/'rc10-registered-installed-audits.json').read_text())['results']
 dlocal=audits[0]['finalized'];dgate=audits[1]['finalized'];nodes=[]
 def add(result,phase,binding=None,dependencies=(),credit=True):
  node={'phase':phase,'evidenceUse':'qualification-credit' if credit else 'retained-attempt','privateRunRef':result['privateRunRef'],'publicRunRef':result['publicRunRef'],'distributionRunId':binding['privateRunRef']['runId'] if binding else None,'dependsOnRunIds':[r['privateRunRef']['runId'] for r in dependencies]}
  nodes.append(node)
 def result(command):return json.loads((BASE/'producer-runs'/(command+'.json')).read_text())
 add(dlocal,'distribution');add(dgate,'distribution')
 for command in ['mirrors.local-no-model','mirrors.remote-model-check','mirrors.interop','mirrorecma.project-check','mirrorecma.test','mirrorgate.required']:
  add(result(command),'source-gate',dependencies=[dgate] if command in ['mirrorgate.required','mirrors.interop'] else [dlocal])
 for command in ['framework.replay-correct','framework.replay-faulty']:add(result(command),'replay',dlocal,[dlocal])
 add(result('framework.lease-origin-installed'),'origin',dlocal,[dlocal])
 add(result('framework.reproduction'),'reproduction',dlocal,[dlocal,result('framework.replay-faulty')])
 add(result('framework.reproduction-lease'),'reproduction',dlocal,[dlocal,result('framework.lease-origin-installed')])
 add(result('framework.reduction-prefix'),'reduction',dlocal,[dlocal,result('framework.reproduction')])
 add(result('framework.reduction'),'reduction',dlocal,[dlocal,result('framework.reproduction-lease'),result('mirrors.remote-model-check')])
 add(result('framework.mutation-local'),'mutation',dlocal,[dlocal]);add(result('framework.mutation-gate'),'mutation',dgate,[dgate])
 add(result('framework.recovery-origin-installed'),'origin',dgate,[dgate],credit=False)
 add(result('mirrorgate.recovery'),'recovery',dgate,[dgate,result('framework.recovery-origin-installed')])
 assert len(nodes)==19
 scope={'schemaVersion':'mirrors.qualification-scope/v2','scopeId':'rc10-wsl-windows-remote-20261106','qualificationClass':'local-candidate','selectedCatalogRef':{'schemaVersion':'mirrors.framework-catalog/v1','selectionKind':'sha256','selectionValue':SELECTION},'distributionBindingRunIds':[dlocal['privateRunRef']['runId'],dgate['privateRunRef']['runId']],'nodes':nodes}
 support=BASE/'qualification';support.mkdir(mode=0o700);scope_path=support/'qualification-scope.json';write(scope_path,scope);scope_path.chmod(0o600)
 env=base_environment();runtime,_=installed('checked-replay-local');env['MIRRORS_INSTALLED_RUNTIME']=str(runtime)
 run('rc10-scope-independent-preverify',['/usr/bin/python3',SOURCE/'tools/evidence/qualification_scope.py','--scope',scope_path,'--store',STORE],env=env,timeout=600)
 root=BASE/'outputs/evidence.offline-verify';plan=attachment_for('evidence.offline-verify',root,{'qualification-scope.json':scope_path})
 q=collect('rc10-q1-offline-scope','evidence.offline-verify',cwd=runtime,tail=[root/'qualification-scope.json','--store',STORE],env=env,attachment_plan=plan,timeout=900)
 catalog=json.loads((ROOT/FREEZE['families']['wsl2']['catalog']['path']).read_text());evidence_id='rc10.m5.q.20261106'
 catalog['evidenceRefs'].append({'evidenceId':evidence_id,'runRef':q['publicRunRef']})
 combination=next(c for c in catalog['combinations'] if c['combinationId']=='candidate.node-gate');combination['evidenceIds'].append(evidence_id)
 profiles={p['profileId']:p for p in catalog['distributionProfiles']};capabilities={c['capabilityId']:c for c in catalog['capabilities']}
 for profile_id in combination['distributionProfileIds']:
  for capability_id in profiles[profile_id]['requiredCapabilityIds']:
   for dimension in ['installedConsumerAccepted','locallyAccepted','sourceTested']:capabilities[capability_id]['observations'][dimension]={'state':'accepted','evidenceId':evidence_id}
 catalog.setdefault('extensions',{})['org.nzsn.catalog-lineage']={'previousSelectionRef':scope['selectedCatalogRef']}
 final_catalog=support/'qualified-catalog.json';write(final_catalog,catalog)
 run('rc10-qualified-catalog-c3',[C3,'validate',final_catalog],env=env)
 run('rc10-q1-complete-profile-link',['/usr/bin/python3',SOURCE/'tools/evidence/verify.py','--offline','--catalog',final_catalog,'--profile','m5-wsl-windows-remote',q['bundle']],env=env,timeout=900)
 write(PLAN/'rc10-q1-result.json',{'status':'linked-q1-complete-profile-accepted','sourceRevision':FREEZE['freezeRevision'],'c0':SELECTION,'q':q,'scope':identity(scope_path),'catalog':identity(final_catalog),'independentInstalledQ2Pending':True,'fullWindowsAcceptance':False,'releaseOrProductionAdmission':False})
 print('RC10 LINKED Q1 GREEN',flush=True)

if __name__=='__main__':main()
