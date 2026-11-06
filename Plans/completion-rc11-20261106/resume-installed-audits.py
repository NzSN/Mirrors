"""Collect/finalize both strict D audits under the exact refreshed registry."""
import copy,json,os,shutil
from common import *

def main():
 freeze=json.loads((PLAN/'rc11-freeze-manifest.json').read_text());source=ROOT/freeze['taskOwnedSource'];out=OUT/'qualification'
 store=out/'evidence';store.mkdir(mode=0o700,exist_ok=True)
 registry=source/'tools/evidence/commands.json';entries={c['commandId']:c for c in json.loads(registry.read_text())['commands']}
 results=[]
 for profile,command_id,env_name in [('checked-replay-local','framework.install-diagnostics','MIRRORS_INSTALLED_RUNTIME'),('checked-replay-gate','framework.install-diagnostics-gate','MIRRORS_INSTALLED_GATE_RUNTIME')]:
  prefix=out/'install'/profile;active=json.loads((prefix/'active.json').read_text());version=prefix/active['versionDirectory'];runtime=version/'runtime'
  entry=entries[command_id];audit=out/'audit'/profile;audit.mkdir(mode=0o700,parents=True,exist_ok=True)
  specs=copy.deepcopy(entry['attachmentOutputs'])
  for spec in specs:
   if spec['captureMode']=='existing-input':
    target=audit/spec['relativePath'];shutil.copyfile(version/'cache'/spec['relativePath'],target);target.chmod(0o600);spec['expectedSha256']=identity(target)['sha256']
  adapter=entry['attachmentAdapter'];plan={'schemaVersion':'mirrors.evidence-attachment-plan/v1','sourceRoot':str(audit),'application':adapter['application'],'adapter':{'kind':adapter['kind'],'artifactId':adapter['artifactId']},'attachments':specs}
  plan_path=out/(profile+'-audit-attachment-plan.json');
  if plan_path.exists():assert json.loads(plan_path.read_text())==plan
  else:write(plan_path,plan)
  plan_path.chmod(0o600)
  argv=entry['argvPrefix']+[str(audit/specs[0]['relativePath'])]
  env=environment();env['TMPDIR']='/tmp';env['PYTHONDONTWRITEBYTECODE']='1';env[env_name]=str(runtime)
  for key in ['LD_LIBRARY_PATH','LD_PRELOAD']:env.pop(key,None)
  collector=['/usr/bin/python3',source/'tools/evidence/collect.py','--store',store,'--registry',registry,'--command-id',command_id,'--cwd',runtime,'--component','mirrors='+str(source),'--component','mirrorecma='+str(ECMA),'--component','mirrorgate='+str(GATE),'--catalog-selection-kind','sha256','--catalog-selection-value',freeze['families']['wsl2']['selectionSha256'],'--attachment-plan',plan_path,'--',*argv]
  staging=store/'staging';label='rc11-'+profile+'-registered-audit-no-bytecode';receipt=OUT/'logs'/(label+'.json')
  if receipt.exists():
   saved=json.loads(receipt.read_text());assert saved['exitCode']==0 and saved['argv']==list(map(str,collector))
  else:run(label,collector,cwd=source,env=env,timeout=2400)
  import re
  selected=re.findall(r'^evidence staging: (.+)$',(OUT/'logs'/(label+'.stderr')).read_text(),re.MULTILINE);assert len(selected)==1
  selected=Path(selected[0]);assert selected.parent==staging
  fresh={selected}
  final=json.loads(run('rc11-'+profile+'-finalize-no-bytecode',['/usr/bin/python3',source/'tools/evidence/finalize.py',fresh.pop(),'--store',store],cwd=source,env=env))
  run('rc11-'+profile+'-offline-verify-no-bytecode',['/usr/bin/python3',source/'tools/evidence/verify.py','--offline',final['bundle']],cwd=source,env=env)
  results.append({'profile':profile,'commandId':command_id,'runtime':str(runtime),'manifestDigest':active['manifestDigest'],'finalized':final,'audit':identity(audit/specs[0]['relativePath'])})
 write(PLAN/'rc11-registered-installed-audits.json',{'status':'both-registered-installed-audits-finalized-and-offline-verified','sourceRevision':freeze['freezeRevision'],'c0':freeze['families']['wsl2']['selectionSha256'],'registry':identity(registry),'results':results,'frameworkQualificationGranted':False})
 print('RC10 REGISTERED D AUDITS GREEN',flush=True)

if __name__=='__main__':main()
