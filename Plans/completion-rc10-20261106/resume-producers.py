"""Resume retained attempts with required host inputs; expected origin exit is one."""
from evidence_rc10 import *
import re

def main():
 label='rc10-installed-framework.lease-origin-installed'
 text=(OUT/'logs'/(label+'-collect.stderr')).read_text();paths=re.findall(r'^evidence staging: (.+)$',text,re.MULTILINE);assert len(paths)==1
 env=base_environment();result=json.loads(run(label+'-finalize',['/usr/bin/python3',SOURCE/'tools/evidence/finalize.py',paths[0],'--store',STORE],env=env))
 run(label+'-verify',['/usr/bin/python3',SOURCE/'tools/evidence/verify.py','--offline',result['bundle']],env=env)
 envelope=json.loads((Path(result['bundle'])/'envelope.json').read_text());assert envelope['qualification']['status']=='qualified',envelope['qualification']
 write(BASE/'producer-runs/framework.lease-origin-installed.json',result)
 runtime,_=installed('checked-replay-local');gate,_=installed('checked-replay-gate')
 env['MIRRORS_INSTALLED_RUNTIME']=str(runtime);env['MIRRORS_INSTALLED_GATE_RUNTIME']=str(gate)
 for command,gate_mode in [('framework.mutation-local',False),('framework.mutation-gate',True),('framework.recovery-origin-installed',True)]:
  root=BASE/'outputs'/command;plan=attachment_for(command,root)
  e=dict(env)
  if gate_mode:e['PYTHONPATH']=str(gate/'gate/mirrorgate-supervisor')
  tail=[root/'local-application-campaigns.json'] if command=='framework.mutation-local' else [root]
  collect('rc10-installed-'+command,command,cwd=gate if gate_mode else runtime,tail=tail,env=e,attachment_plan=plan,expected_exit=2 if command=='framework.recovery-origin-installed' else 0,require_qualified=command!='framework.recovery-origin-installed')
 print('RC10 REPLAY ORIGIN MUTATION RESUMED',flush=True)
if __name__=='__main__':main()
