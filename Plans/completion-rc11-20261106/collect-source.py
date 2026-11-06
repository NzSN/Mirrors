from evidence_rc11 import *
def main():
 env=base_environment();env['TMPDIR']=str(ROOT/'tmp/c11source');Path(env['TMPDIR']).mkdir(mode=0o700,exist_ok=True)
 env.update(MIRRORS_ROOT=str(SOURCE),MIRROR_BIN=str(SOURCE/'.lake/build/bin/mirror'),MODEL_INTERFACE_GEN=str(SOURCE/'.lake/build/bin/model_interface_gen'),MIRRORCPP_PREFIX=str(ROOT/'.golden-build/qualification-rc7-20261105/cpp-prefix-windows-fix'),MIRRORGATE_ROOT=str(GATE),MIRRORGATE_NODE_RUNTIME_ROOT=str(ROOT/'.golden-build/version-0.1/toolchains/node-v24.15.0-linux-x64'),MIRRORGATE_TSC=str(GATE/'node_modules/typescript/bin/tsc'),MIRRORGATE_NLOHMANN_JSON_INCLUDE_DIR=str(ROOT/'.golden-build/qualification-rc7-20261105/cpp-prefix-windows-fix/include'),RUST_REPO=str(ROOT/'.golden-build/completion-20261029/MirrorRust'))
 STORE.mkdir(mode=0o700,parents=True,exist_ok=True);(STORE/'staging').mkdir(mode=0o700,exist_ok=True)
 for cid,cwd in [('mirrorecma.project-check',ECMA),('mirrorecma.test',ECMA),('mirrorgate.required',GATE),('mirrors.local-no-model',SOURCE)]:
  collect('rc11-final-source-'+cid,cid,cwd=cwd,env=env,timeout=3600)
 print('RC11 FINAL C0 ALL REQUIRED SOURCE GATES GREEN',flush=True)
if __name__=='__main__':main()
