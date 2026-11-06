"""Prepare fresh read-only Q2 inputs, then verify with installed-only runtime."""
from evidence_rc11 import *
import shutil,zipfile

def main():
 q=json.loads((BASE/'producer-runs/evidence.offline-verify.json').read_text());scope=BASE/'qualification/qualification-scope.json';catalog=BASE/'qualification/qualified-catalog.json';inputs=OUT/'q2-inputs';inputs.mkdir(mode=0o700)
 shutil.copy2(PLAN/'independent-q2.py',inputs/'independent-q2.py');shutil.copy2(scope,inputs/'qualification-scope.json');shutil.copy2(catalog,inputs/'qualified-catalog.json')
 shutil.copytree(STORE,inputs/'evidence',ignore=shutil.ignore_patterns('staging'))
 source_runs=list((inputs/'evidence/runs').iterdir());assert len(source_runs)==20
 # Only the schema dependency wheels admitted by this installed cache are used.
 runtime,cache=installed('checked-replay-local');wheels=runtime/'verification/wheels';site=inputs/'python-site';site.mkdir(mode=0o700)
 found=list(wheels.glob('*.whl'))
 if not found:found=list(runtime.glob('verification/**/**.whl'))
 assert found,'installed verifier dependency wheels absent'
 for wheel in found:
  with zipfile.ZipFile(wheel) as archive:
   for name in archive.namelist():
    assert not name.startswith('/') and '..' not in Path(name).parts and '\\' not in name
   archive.extractall(site)
 digests={json.loads((b/'envelope.json').read_text())['runId']:hashlib.sha256((b/'envelope.json').read_bytes()).hexdigest() for b in source_runs}
 hidden=[ROOT,SOURCE,ECMA,GATE,OUT,ROOT.parent/'MirrorCPP',ROOT.parent/'MirrorECMA',ROOT.parent/'MirrorRust']
 write(inputs/'config.json',{'qRunId':q['privateRunRef']['runId'],'runIds':sorted(digests),'expectedPrivateDigests':digests,'c3Sha256':C3_SHA,'parentNetworkNamespace':os.readlink('/proc/self/ns/net'),'hiddenRoots':list(map(str,hidden))})
 command=['/usr/bin/bwrap','--die-with-parent','--unshare-net','--ro-bind','/','/','--tmpfs','/home','--tmpfs','/mnt','--tmpfs','/tmp','--ro-bind',inputs,'/tmp/q2','--ro-bind',runtime,'/tmp/runtime','--proc','/proc','--dev','/dev','--clearenv','--setenv','PATH','/usr/bin:/bin','--setenv','HOME','/tmp','--setenv','TMPDIR','/tmp','--setenv','PYTHONDONTWRITEBYTECODE','1','--setenv','MIRRORS_FRAMEWORK_CATALOG_VALIDATOR','/tmp/runtime/bin/framework_catalog','--chdir','/tmp/q2','/usr/bin/python3','-I','-S','-B','/tmp/q2/independent-q2.py']
 result=json.loads(run('rc11-independent-installed-q2',command,timeout=1800));assert result['status']=='independent-installed-Q2-accepted' and len(result['negativeControls'])==6
 write(PLAN/'independent-q2-result.json',result);write(OUT/'q2-command.json',list(map(str,command)))
 print('RC11 INDEPENDENT Q2 AND SIX NEGATIVE CONTROLS GREEN',flush=True)
if __name__=='__main__':main()
