from common import *
def main():
 gate=OUT/'MirrorGate-ordering-fix';sdk=gate/'sdk/node/control.mjs';fixed=sdk.read_bytes();original=(GATE/'sdk/node/control.mjs').read_bytes();env=environment()
 try:
  sdk.write_bytes(original)
  run('gate-ordering-red',[OUT/'tool-bin/node','--test','--test-name-pattern=observes coalesced response','tests/node/control-v2.test.mjs'],cwd=gate,env=env,ok=(1,))
 finally:sdk.write_bytes(fixed)
 run('gate-ordering-green',[OUT/'tool-bin/node','--test','tests/node/control-v2.test.mjs'],cwd=gate,env=env)
 print('DETERMINISTIC HOSTING FRAME ORDERING RED/GREEN CONFIRMED',flush=True)
if __name__=='__main__':main()
