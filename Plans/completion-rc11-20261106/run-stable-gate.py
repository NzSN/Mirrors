"""Bind the final rc.11 local non-model gate to exact stable source inputs."""
import hashlib,json,os,subprocess,sys,time
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];PLAN=Path(__file__).resolve().parent
OUT=ROOT/'.golden-build/completion-rc11-20261106'
sys.path.insert(0,str(ROOT/'tools/distribution'))
from refresh_identity import selected_refs
ECMA=ROOT/'.golden-build/mw12-20261103/inputs/companions/MirrorECMA'
GATE=ROOT/'.golden-build/completion-rc10-20261106/MirrorGate-ordering-fix'
def record(path):
 data=path.read_bytes();return {'path':path.relative_to(ROOT).as_posix(),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
def main():
 log=OUT/'rc11-stable-local-no-model-final.log';receipt=PLAN/'rc11-gate-result.json'
 if log.exists() or receipt.exists():raise ValueError('retain old attempt')
 before=selected_refs(ECMA,GATE)
 assert before['mirrors']['dirty'] and not before['mirrorecma']['dirty'] and not before['mirrorgate']['dirty']
 preserved=json.loads((ROOT/'Plans/source-freeze-rc7-20261104/intake.json').read_text())['preservedUnrelatedFiles']
 for entry in preserved:assert record(ROOT/entry['path'])==entry
 env=dict(os.environ);env['TMPDIR']=str(ROOT/'tmp/c11');Path(env['TMPDIR']).mkdir(mode=0o700,exist_ok=True);env['RUST_REPO']=str(ROOT/'.golden-build/completion-20261029/MirrorRust');env['RUSTUP_TOOLCHAIN']='1.96.0';env['MIRRORCPP_PREFIX']=str(ROOT/'.golden-build/qualification-rc7-20261105/cpp-prefix-windows-fix')
 start=datetime.now(timezone.utc).isoformat();clock=time.monotonic()
 with log.open('xb') as stream:p=subprocess.run(['bash','tools/run-local-no-model-check.sh'],cwd=ROOT,env=env,stdin=subprocess.DEVNULL,stdout=stream,stderr=subprocess.STDOUT)
 after=selected_refs(ECMA,GATE)
 for entry in preserved:assert record(ROOT/entry['path'])==entry
 passed=p.returncode==0 and before==after and log.read_bytes().splitlines()[-1]==b'ALL LOCAL NON-MODEL GATES GREEN'
 value={'status':'passed-stable-rc11-source' if passed else 'failed','startedAt':start,'finishedAt':datetime.now(timezone.utc).isoformat(),'seconds':time.monotonic()-clock,'exitCode':p.returncode,'before':before,'after':after,'sourceAndCompanionsStable':before==after,'log':record(log),'nativeCppPrefix':env['MIRRORCPP_PREFIX'],'preservedUnrelatedFiles':len(preserved),'frameworkOrReleaseAcceptance':False}
 with receipt.open('x') as stream:stream.write(json.dumps(value,indent=2)+'\n')
 print(json.dumps({'passed':passed,'exitCode':p.returncode,'sourceAndCompanionsStable':before==after,'seconds':value['seconds']}),flush=True)
 raise SystemExit(0 if passed else 1)
if __name__=='__main__':main()
