from evidence_rc10 import *
def main():
 env=base_environment();env['TMPDIR']='/tmp/mrc10-trace';Path(env['TMPDIR']).mkdir(mode=0o700,exist_ok=False)
 env['MIRRORGATE_NODE_RUNTIME_ROOT']=str(ROOT/'.golden-build/version-0.1/toolchains/node-v24.15.0-linux-x64');env['MIRRORGATE_REQUIRE_SANDBOX']='1';env['MIRRORGATE_TSC']=str(ECMA/'node_modules/.bin/tsc')
 env['MRC10_GATE_DIAGNOSTIC']=str(OUT/'gate-observe-diagnostic.jsonl')
 tests=sorted(GATE.glob('tests/node/*.test.mjs'))
 for i in range(3):
  run('gate-full-ordering-trace-'+str(i),[OUT/'tool-bin/node','--import',OUT/'gate-observe-diagnostic.mjs','--test','--test-concurrency=1',*tests],cwd=GATE,env=env,ok=(0,1),timeout=180)
  if (OUT/'gate-observe-diagnostic.jsonl').exists():break
if __name__=='__main__':main()
