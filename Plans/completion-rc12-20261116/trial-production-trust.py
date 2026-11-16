"""Exercise candidate and old rollback binaries with the renewed chain before activation."""
import hashlib
import json
import os
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path
from production_health import STAGE,KEYS,health,RENEWED


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def no_listener(port):
    query="if(@(Get-NetTCPConnection -State Listen -LocalPort "+str(port)+" -ErrorAction SilentlyContinue).Count -ne 0){exit 17};exit 0"
    result=subprocess.run([r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe','-NoProfile','-NonInteractive','-Command',query],capture_output=True,timeout=30)
    assert result.returncode==0,'trial port already has a listener or listener observation failed'


def main():
    suffix=sys.argv[1] if len(sys.argv)>1 else ''
    work=STAGE/'production-renewal'
    candidate=STAGE/'mirrors-v0.2.0-rc.12-windows-x86_64/bin/ModelMirrors.exe'
    rollback=work/'rollback/ModelMirrors.exe'
    assert digest(candidate)==RENEWED['candidateBinarySha256'] and digest(rollback)==RENEWED['oldBinarySha256']
    assert digest(Path(r'D:\ModelMirrors\bin\ModelMirrors.exe'))==RENEWED['oldBinarySha256']
    for name,expected in RENEWED['dllHashes'].items():
        original=Path(r'D:\ModelMirrors\bin')/name
        assert digest(original)==expected
        target=rollback.parent/name
        if target.exists():assert digest(target)==expected
        else:shutil.copy2(original,target)
        assert digest(target)==expected
    env=dict(os.environ)
    env['PATH']=str(candidate.parent)+r';D:\Programs\jdk-25.0.4+7\bin;D:\Programs\msys2\ucrt64\bin;'+env['PATH']
    env['JAVA_HOME']=r'D:\Programs\jdk-25.0.4+7'
    env['APALACHE_MC']=r'D:\ModelMirrors\bin\apalache-mc.exe'
    env['TEMP']=str(work/('tmp'+suffix));env['TMP']=env['TEMP'];Path(env['TEMP']).mkdir(exist_ok=False)
    rows=[]
    for label,server,wanted,port in [('trust-trial-candidate',candidate,RENEWED['candidateBinarySha256'],19100),
                                     ('trust-trial-rollback',rollback,RENEWED['oldBinarySha256'],19101)]:
        label+=suffix
        root=work/label;root.mkdir(exist_ok=False)
        no_listener(port)
        args=[str(server),'--server',str(port),'--bind','192.168.150.219','--tls',
              '--cert',str(work/'server.crt'),'--key',str(KEYS/'server.key'),'--ca',str(work/'ca.crt'),'--jobs','4']
        with (root/'server.stdout').open('xb') as out,(root/'server.stderr').open('xb') as err:
            process=subprocess.Popen(args,cwd=STAGE,env=env,stdin=subprocess.DEVNULL,stdout=out,stderr=err,
                                     creationflags=subprocess.CREATE_NO_WINDOW)
            try:
                for _ in range(100):
                    if process.poll() is not None:raise ValueError('trial server exited before admission')
                    try:
                        with socket.create_connection(('192.168.150.219',port),timeout=.2):break
                    except OSError:time.sleep(.1)
                else:raise ValueError('trial listener unavailable')
                result=health(label,port,work)
                assert digest(server)==wanted
                rows.append({'label':label,'serverSha256':wanted,'health':result,'ownedPid':process.pid})
            finally:
                if process.poll() is None:process.terminate()
                process.wait(timeout=15)
        no_listener(port)
    assert digest(Path(r'D:\ModelMirrors\bin\ModelMirrors.exe'))==RENEWED['oldBinarySha256']
    value={'schema':'mirrors.rc12.renewed-trust-trials/v1','status':'candidate-and-rollback-renewed-chain-trials-passed',
           'cases':rows,'privateKeysExported':False,'productionModified':False,'trialPortsNotListeningAfterward':True}
    (work/'trial-result.json').write_text(json.dumps(value,indent=2)+'\n')
    print(json.dumps(value,indent=2))


if __name__=='__main__':main()
