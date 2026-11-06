"""Use the admitted exact Node runtime root for required sandbox controls."""
from evidence_rc10 import *
def main():
 env=base_environment();env['MIRRORS_ROOT']=str(SOURCE);env['MIRROR_BIN']=str(SOURCE/'.lake/build/bin/mirror');env['MODEL_INTERFACE_GEN']=str(SOURCE/'.lake/build/bin/model_interface_gen')
 env['MIRRORCPP_PREFIX']=str(ROOT/'.golden-build/qualification-rc7-20261105/cpp-prefix-windows-fix');env['MIRRORGATE_ROOT']=str(GATE)
 env['MIRRORGATE_NODE_RUNTIME_ROOT']=str(ROOT/'.golden-build/version-0.1/toolchains/node-v24.15.0-linux-x64')
 for command,cwd in [('mirrorgate.required',GATE),('mirrors.local-no-model',SOURCE)]:
  collect('rc10-resume-source-'+command,command,cwd=cwd,env=env,timeout=3600)
 print('RC10 SOURCE GATES RESUMED',flush=True)
if __name__=='__main__':main()
