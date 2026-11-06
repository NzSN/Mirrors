"""Fresh installed correct/faulty replay, lease origin and mutation controls."""
from evidence_rc11 import *

def main():
 runtime,_=installed('checked-replay-local');gate,_=installed('checked-replay-gate')
 for command,target,gate_mode in [
     ('framework.replay-correct','framework.replay-correct',False),
     ('framework.replay-faulty','framework.replay-faulty',False),
     
     ('framework.mutation-local','framework.mutation-local',False),
     ('framework.mutation-gate','framework.mutation-gate',True),
     ]:
  root=BASE/'outputs'/target;plan=attachment_for(command,root)
  env=base_environment();env['TMPDIR']='/tmp';env['MIRROR_BIN']=str(runtime/'bin/ModelMirrors');env['MODEL_INTERFACE_GEN']=str(runtime/'bin/model_interface_gen');env['MIRRORS_INSTALLED_RUNTIME']=str(runtime);env['MIRRORS_INSTALLED_GATE_RUNTIME']=str(gate)
  if gate_mode:env['PYTHONPATH']=str(gate/'gate/mirrorgate-supervisor')
  tail=[root/'local-application-campaigns.json'] if command=='framework.mutation-local' else [root]
  expected=1 if command=='framework.replay-faulty' else 0
  collect('rc11-c0-final-installed-'+command,command,cwd=gate if gate_mode else runtime,
          tail=tail,env=env,attachment_plan=plan,expected_exit=expected,timeout=2400)
 print('RC10 INSTALLED ORIGIN/REPLAY/MUTATION GATES COLLECTED',flush=True)
if __name__=='__main__':main()
