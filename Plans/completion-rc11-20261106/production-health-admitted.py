"""Bounded live controls using existing host-local production client credentials."""
import hashlib,json,os,subprocess,sys
from pathlib import Path
STAGE=Path(r'D:\ModelMirrors\staging\completion-rc11-20261106')
CLIENT=STAGE/'mirrors-v0.2.0-rc.11-windows-x86_64/bin/ModelMirrors.exe'
WRAPPER=Path(r'D:\ModelMirrors\staging\qualification-rc7-20261105\runtime-inputs\native-test-job-detached.exe')
PKI=Path(r'D:\ModelMirrors\certs');PIN='b2fc7265145cf2b89a1a248b0932885df8d300121b47f7854317ece4bac9ce67'
assert hashlib.sha256(CLIENT.read_bytes()).hexdigest()=='5bfb5248a7ab74bfbe6c86361146daa20b0e5e864699c820269279747ef81fd4'
label=sys.argv[1];assert label in ['baseline','baseline-admitted','deployed','rollback','post-reboot']
root=STAGE/('production-health-'+label);root.mkdir(exist_ok=False)
common=[str(WRAPPER),str(CLIENT),'validate','--host','192.168.150.219','--port','8999','--tls','--cert',str(PKI/'client.crt'),'--key',str(PKI/'client.key'),'--ca',str(PKI/'ca.crt'),'--pin',PIN,'--spec',str(STAGE/'source/test/specs/HourClock.tla'),'--init','Init','--next','Next']
rows=[]
for asynchronous in [False,True]:
 for case,inv,bound,expected in [('valid','Inv',3,0),('invalid','TraceComplete',13,1)]:
  name=('async' if asynchronous else 'sync')+'-'+case
  result=subprocess.run(common+['--inv',inv,'--bound',str(bound)]+(['--async'] if asynchronous else []),capture_output=True,timeout=180)
  raw=result.stdout+result.stderr;(root/(name+'.log')).write_bytes(raw)
  assert result.returncode==expected and result.stdout.splitlines()[0]==case.upper().encode() and b'TASK JOB CLEANUP active=0' in raw,name
  rows.append({'case':name,'exitCode':result.returncode,'logSha256':hashlib.sha256(raw).hexdigest()})
args=list(common);args[args.index('--pin')+1]='0'*64
result=subprocess.run(args+['--inv','Inv','--bound','3'],capture_output=True,timeout=60);raw=result.stdout+result.stderr;(root/'wrong-pin.log').write_bytes(raw)
assert result.returncode==2 and b'certificate fingerprint mismatch' in raw.lower() and b'VALID' not in raw and b'TASK JOB CLEANUP active=0' in raw
value={'status':'passed','scope':label,'clientSha256':hashlib.sha256(CLIENT.read_bytes()).hexdigest(),'serverCertificateSha256':PIN,'cases':rows,'wrongPinRejected':True,'credentialsExported':False}
(root/'result.json').write_text(json.dumps(value,indent=2)+'\n');print(json.dumps(value))
