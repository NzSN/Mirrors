"""Bind the complete local non-model result to stable rc.8 source inputs."""
import json,sys
from common import *
sys.path.insert(0,str(ROOT/'tools/distribution'))
from refresh_identity import selected_refs

def main():
 before=selected_refs(ECMA,GATE)
 assert before['mirrors']['dirty'] and not before['mirrorecma']['dirty'] and not before['mirrorgate']['dirty']
 preserved=json.loads((ROOT/'Plans/source-freeze-rc7-20261104/intake.json').read_text())['preservedUnrelatedFiles']
 for entry in preserved:
  current=identity(ROOT/entry['path']);assert current['sha256']==entry['sha256'] and current['bytes']==entry['bytes']
 env=environment();env['MIRRORCPP_PREFIX']=str(OUT/'cpp-prefix-windows-fix')
 run('rc8-final-source-local-no-model',['bash','tools/run-local-no-model-check.sh'],env=env,timeout=3600)
 after=selected_refs(ECMA,GATE);assert after==before,'source changed during gate'
 assert (OUT/'logs/rc8-final-source-local-no-model.stdout').read_text().splitlines()[-1]=='ALL LOCAL NON-MODEL GATES GREEN'
 for entry in preserved:
  current=identity(ROOT/entry['path']);assert current['sha256']==entry['sha256'] and current['bytes']==entry['bytes']
 write(PLAN/'rc8-final-gate-result.json',{'status':'passed-stable-rc8-source','before':before,'after':after,'sourceAndCompanionsStable':True,'preservedUnrelatedFiles':len(preserved),'nativeCppPrefix':str(OUT/'cpp-prefix-windows-fix'),'log':identity(OUT/'logs/rc8-final-source-local-no-model.stdout'),'fullWindowsOrFrameworkCredit':False})
 print('RC8 STABLE LOCAL GATE GREEN',flush=True)

if __name__=='__main__':main()
