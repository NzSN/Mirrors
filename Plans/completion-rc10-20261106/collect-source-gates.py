"""Collect fresh required source gates; all commands use the frozen registry."""
from evidence_rc10 import *

def main():
 runtime,_=installed('checked-replay-local');tools=OUT/'tool-bin';tools.mkdir(mode=0o700,exist_ok=False)
 (tools/'node').symlink_to(runtime/'runtimes/node/bin/node')
 env=base_environment();env['MIRRORS_ROOT']=str(SOURCE);env['MIRROR_BIN']=str(SOURCE/'.lake/build/bin/mirror')
 env['MODEL_INTERFACE_GEN']=str(SOURCE/'.lake/build/bin/model_interface_gen')
 env['MIRRORCPP_PREFIX']=str(ROOT/'.golden-build/qualification-rc7-20261105/cpp-prefix-windows-fix')
 env['MIRRORGATE_ROOT']=str(GATE)
 (BASE/'producer-runs').mkdir(mode=0o700,exist_ok=True)
 for command,cwd in [('mirrorecma.project-check',ECMA),('mirrorecma.test',ECMA),('mirrorgate.required',GATE),('mirrors.local-no-model',SOURCE)]:
  collect('rc10-source-'+command,command,cwd=cwd,env=env,timeout=3600)
 print('RC10 ALL REQUIRED SOURCE GATES COLLECTED',flush=True)
if __name__=='__main__':main()
