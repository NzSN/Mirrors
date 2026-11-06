"""Shared rc.10 registered evidence orchestration; no unregistered substitutions."""
import json,os,sys
from common_final import *
FREEZE=json.loads((PLAN/'rc10-final-freeze.json').read_text())
SOURCE=ROOT/FREEZE['taskOwnedSource']
BASE=OUT/'qualification-final'
STORE=BASE/'evidence'
REGISTRY=SOURCE/'tools/evidence/commands.json'
ENTRIES={c['commandId']:c for c in json.loads(REGISTRY.read_text())['commands']}
SELECTION=FREEZE['families']['wsl2']['selectionSha256']

def installed(profile):
 prefix=OUT/'qualification/install'/profile;active=json.loads((prefix/'active.json').read_text());version=prefix/active['versionDirectory']
 return version/'runtime',version/'cache'

def base_environment():
 env=environment();env['PYTHONDONTWRITEBYTECODE']='1';env['CARGO_NET_OFFLINE']='true'
 for key in ['NODE_OPTIONS','NODE_PATH','NODE_COMPILE_CACHE']:env.pop(key,None)
 env['PATH']=str(OUT/'tool-bin')+':'+env['PATH'];env['RUSTUP_TOOLCHAIN']='1.96.0';env['MIRRORGATE_RUST_TOOLCHAIN']='1.96.0'
 return env

def collect(label,command_id,*,cwd,argv=None,tail=(),env=None,attachment_plan=None,expected_exit=0,timeout=2400,require_qualified=True):
 entry=ENTRIES[command_id];command=list(entry['argvPrefix'])+list(tail) if argv is None else list(argv)
 sys.path.insert(0,str(SOURCE/'tools/evidence'))
 from qualification_scope import SOURCE_COMMAND_COMPONENTS
 if command_id=='evidence.offline-verify':
  ids={'mirrors','mirrorecma','mirrorgate'}
 elif command_id in SOURCE_COMMAND_COMPONENTS:
  ids=SOURCE_COMMAND_COMPONENTS[command_id]
 else:
  framework=Path((env or {}).get(entry.get('requiredCwdEnvironmentName',''),cwd))/'framework-input.json'
  assert framework.is_file(),'installed command needs its admitted framework input'
  ids={c['componentId'] for c in json.loads(framework.read_text())['observed']['componentRefs']}
 roots={'mirrors':SOURCE,'mirrorecma':ECMA,'mirrorgate':GATE}
 args=['/usr/bin/python3',SOURCE/'tools/evidence/collect.py','--store',STORE,'--registry',REGISTRY,'--command-id',command_id,'--cwd',cwd]
 for component in sorted(ids):args+=['--component',component+'='+str(roots[component])]
 args+=['--catalog-selection-kind','sha256','--catalog-selection-value',SELECTION]
 if attachment_plan:args+=['--attachment-plan',attachment_plan]
 args+=['--',*command]
 before=set((STORE/'staging').iterdir());env=env or base_environment()
 run(label+'-collect',args,cwd=SOURCE,env=env,timeout=timeout,ok=(expected_exit,))
 import re
 paths=re.findall(r'^evidence staging: (.+)$',(OUT/'logs'/(label+'-collect.stderr')).read_text(),re.MULTILINE);assert len(paths)==1
 selected=Path(paths[0]);assert selected.parent==STORE/'staging'
 fresh={selected}
 result=json.loads(run(label+'-finalize',['/usr/bin/python3',SOURCE/'tools/evidence/finalize.py',fresh.pop(),'--store',STORE],cwd=SOURCE,env=env))
 run(label+'-verify',['/usr/bin/python3',SOURCE/'tools/evidence/verify.py','--offline',result['bundle']],cwd=SOURCE,env=env)
 envelope=json.loads((Path(result['bundle'])/'envelope.json').read_text());assert not require_qualified or envelope['qualification']['status']=='qualified',envelope['qualification']
 output=BASE/'producer-runs';output.mkdir(mode=0o700,exist_ok=True)
 write(output/(command_id+'.json'),result)
 return result

def attachment_for(command_id,root,existing=None):
 import copy,shutil
 entry=ENTRIES[command_id];root.mkdir(mode=0o700,parents=True,exist_ok=False)
 specs=copy.deepcopy(entry['attachmentOutputs']);existing=existing or {}
 for spec in specs:
  if spec['captureMode']=='existing-input':
   selected=existing[spec['relativePath']];target=root/spec['relativePath'];shutil.copyfile(selected,target);target.chmod(0o600);spec['expectedSha256']=identity(target)['sha256']
 adapter=entry['attachmentAdapter']
 plan={'schemaVersion':'mirrors.evidence-attachment-plan/v1','sourceRoot':str(root),'application':adapter['application'],'adapter':{'kind':adapter['kind'],'artifactId':adapter['artifactId']},'attachments':specs}
 path=root.parent/(root.name+'-attachment-plan.json');write(path,plan);path.chmod(0o600)
 return path
