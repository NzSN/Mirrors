"""Native mTLS acceptance using host-local production keys and selected public certificates."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

STAGE=Path(r'D:\ModelMirrors\staging\completion-rc12-20261116')
KEYS=Path(r'D:\ModelMirrors\certs')
CLIENT=STAGE/'mirrors-v0.2.0-rc.12-windows-x86_64/bin/ModelMirrors.exe'
RENEWED=json.loads((STAGE/'production-renewal/renewed-public.json').read_text())
PIN=RENEWED['renewedCertificates']['server']['sha256']


def health(label,port=8999,pki=None):
    pki=Path(pki) if pki else KEYS
    root=STAGE/('production-health-'+label)
    root.mkdir(exist_ok=False)
    argv=[str(CLIENT),'validate','--host','192.168.150.219','--port',str(port),'--tls',
          '--cert',str(pki/'client.crt'),'--key',str(KEYS/'client.key'),'--ca',str(pki/'ca.crt'),
          '--pin',PIN,'--spec',str(STAGE/'source/test/specs/HourClock.tla'),'--init','Init','--next','Next']
    rows=[]
    for asynchronous in [False,True]:
        for case,inv,bound,expected in [('valid','Inv',3,0),('invalid','TraceComplete',13,1)]:
            name=('async' if asynchronous else 'sync')+'-'+case
            command=argv+['--inv',inv,'--bound',str(bound)]+(['--async'] if asynchronous else [])
            result=subprocess.run(command,capture_output=True,timeout=180)
            raw=result.stdout+result.stderr
            (root/(name+'.log')).write_bytes(raw)
            assert len(raw)<=262144 and result.returncode==expected and result.stdout.splitlines()[0]==case.upper().encode(),name
            rows.append({'case':name,'exitCode':result.returncode,'logSha256':hashlib.sha256(raw).hexdigest()})
    command=list(argv);command[command.index('--pin')+1]='0'*64
    result=subprocess.run(command+['--inv','Inv','--bound','3'],capture_output=True,timeout=60)
    raw=result.stdout+result.stderr;(root/'wrong-pin.log').write_bytes(raw)
    assert result.returncode==2 and b'certificate fingerprint mismatch' in raw.lower() and b'VALID' not in raw
    value={'schema':'mirrors.rc12.production-health/v1','status':'passed','scope':label,
           'endpoint':{'host':'192.168.150.219','port':port},'clientSourceCommit':'6882d5b8b4787977e847e5a77467b30bfdac19a2',
           'clientSha256':hashlib.sha256(CLIENT.read_bytes()).hexdigest(),'serverCertificateSha256':PIN,
           'cases':rows,'wrongPinRejected':True,'credentialsExported':False}
    (root/'result.json').write_text(json.dumps(value,indent=2)+'\n')
    return value


if __name__=='__main__':
    print(json.dumps(health(sys.argv[1]),indent=2))
