"""Collect/finalize both strict D audits under the exact refreshed registry."""
import copy,json,os,shutil
from common import *

def main():
 freeze=json.loads((PLAN/'rc8-freeze-manifest.json').read_text());source=ROOT/freeze['taskOwnedSource'];out=OUT/'refreshed'
 store=out/'evidence';store.mkdir(mode=0o700,exist_ok=True)
 registry=source/'tools/evidence/commands.json';entries={c['commandId']:c for c in json.loads(registry.read_text())['commands']}
 results=[]
 for profile,command_id,env_name in [('checked-replay-local','framework.install-diagnostics','MIRRORS_INSTALLED_RUNTIME'),('checked-replay-gate','framework.install-diagnostics-gate','MIRRORS_INSTALLED_GATE_RUNTIME')]:
  prefix=out/'install'/profile;active=json.loads((prefix/'active.json').read_text());version=prefix/active['versionDirectory'];runtime=version/'runtime'
  entry=entries[command_id];audit=out/'audit'/profile;audit.mkdir(mode=0o700,parents=True,exist_ok=False)
  specs=copy.deepcopy(entry['attachmentOutputs'])
  for spec in specs:
   if spec['captureMode']=='existing-input':
    target=audit/spec['relativePath'];shutil.copyfile(version/'cache'/spec['relativePath'],target);target.chmod(0o600);spec['expectedSha256']=identity(target)['sha256']
  adapter=entry['attachmentAdapter'];plan={'schemaVersion':'mirrors.evidence-attachment-plan/v1','sourceRoot':str(audit),'application':adapter['application'],'adapter':{'kind':adapter['kind'],'artifactId':adapter['artifactId']},'attachments':specs}
  plan_path=out/(profile+'-audit-attachment-plan.json');write(plan_path,plan);plan_path.chmod(0o600)
  argv=entry['argvPrefix']+[str(audit/specs[0]['relativePath'])]
  env=environment();env['TMPDIR']='/tmp';env['PYTHONDONTWRITEBYTECODE']='1';env[env_name]=str(runtime)
  for key in ['LD_LIBRARY_PATH','LD_PRELOAD']:env.pop(key,None)
  collector=['/usr/bin/python3',source/'tools/evidence/collect.py','--store',store,'--registry',registry,'--command-id',command_id,'--cwd',runtime,'--component','mirrors='+str(source),'--component','mirrorecma='+str(ECMA),'--component','mirrorgate='+str(GATE),'--catalog-selection-kind','sha256','--catalog-selection-value',freeze['families']['wsl2']['selectionSha256'],'--attachment-plan',plan_path,'--',*argv]
  staging=store/'staging';before=set(staging.iterdir()) if staging.exists() else set()
  run('rc8-'+profile+'-registered-audit-no-bytecode',collector,cwd=source,env=env,timeout=2400)
  fresh=set(staging.iterdir())-before;assert len(fresh)==1
  final=json.loads(run('rc8-'+profile+'-finalize-no-bytecode',['/usr/bin/python3',source/'tools/evidence/finalize.py',fresh.pop(),'--store',store],cwd=source,env=env))
  run('rc8-'+profile+'-offline-verify-no-bytecode',['/usr/bin/python3',source/'tools/evidence/verify.py','--offline',final['bundle']],cwd=source,env=env)
  results.append({'profile':profile,'commandId':command_id,'runtime':str(runtime),'manifestDigest':active['manifestDigest'],'finalized':final,'audit':identity(audit/specs[0]['relativePath'])})
 write(PLAN/'rc8-registered-installed-audits.json',{'status':'both-registered-installed-audits-finalized-and-offline-verified','sourceRevision':freeze['freezeRevision'],'c0':freeze['families']['wsl2']['selectionSha256'],'registry':identity(registry),'results':results,'frameworkQualificationGranted':False})
 print('RC8 REGISTERED D AUDITS GREEN',flush=True)

if __name__=='__main__':main()
