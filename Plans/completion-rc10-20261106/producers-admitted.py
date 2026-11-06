"""Resume retained attempts with required host inputs; expected origin exit is one."""
from evidence_rc10 import *
import re

def main():
 runtime,_=installed('checked-replay-local');gate,_=installed('checked-replay-gate')
 env=base_environment();env['TMPDIR']='/tmp/mrc10-producers';Path(env['TMPDIR']).mkdir(mode=0o700,exist_ok=False);env['MIRROR_BIN']=str(runtime/'bin/ModelMirrors');env['MODEL_INTERFACE_GEN']=str(runtime/'bin/model_interface_gen');env['MIRRORS_INSTALLED_RUNTIME']=str(runtime);env['MIRRORS_INSTALLED_GATE_RUNTIME']=str(gate)
 for command,gate_mode in [('framework.mutation-local',False),('framework.mutation-gate',True),('framework.recovery-origin-installed',True)]:
  root=BASE/'outputs'/(command+'-retry');plan=attachment_for(command,root,{'recovery-manifest.json':gate/'gate/mirrorgate-runtime/runtimes/node/examples/counter.manifest.json'} if command=='framework.recovery-origin-installed' else {})
  e=dict(env)
  if gate_mode:e['PYTHONPATH']=str(gate/'gate/mirrorgate-supervisor')
  tail=[root/'local-application-campaigns.json'] if command=='framework.mutation-local' else [root]
  collect('rc10-retry-installed-'+command,command,cwd=gate if gate_mode else runtime,tail=tail,env=e,attachment_plan=plan,expected_exit=74 if command=='framework.recovery-origin-installed' else 0,require_qualified=command!='framework.recovery-origin-installed')
 print('RC10 REPLAY ORIGIN MUTATION RESUMED',flush=True)
if __name__=='__main__':main()
