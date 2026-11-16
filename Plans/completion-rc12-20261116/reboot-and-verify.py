"""Issue the approved reboot once, then verify new boot, auto-start and native mTLS."""
import time
from common import *


def main():
    deployed=json.loads((PLAN/'deployment-result.json').read_text())
    assert deployed['status']=='renewed-trust-and-rc12-deployed-live-verified'
    before=deployed['observation']
    scp=['scp','-F',str(Path.home()/'.ssh/config'),'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes']
    run('reboot-helper-transfer',scp+[PLAN/'reboot-approved.ps1','win10:D:/ModelMirrors/staging/completion-rc12-20261116/'],timeout=180)
    parser="$tokens=$null;$errors=$null;[void][System.Management.Automation.Language.Parser]::ParseFile('"+STAGE+"\\reboot-approved.ps1',[ref]$tokens,[ref]$errors);if($errors.Count -ne 0){throw ($errors|Out-String)};Write-Output 'POWERSHELL PARSER GREEN'"
    remote('reboot-helper-parser',parser)
    run('reboot-approved-request',SSH+['powershell','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
        '-File',STAGE.replace('\\','/')+'/reboot-approved.ps1','-Apply'],timeout=90,ok=(0,255))
    ssh=['ssh','-F',str(Path.home()/'.ssh/config'),'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes',
         '-o','ConnectTimeout=5','-o','ConnectionAttempts=1','win10']
    command=ssh+['powershell','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
                 '-File',STAGE.replace('\\','/')+'/deploy-production.ps1','-Mode','Observe']
    deadline=time.monotonic()+900
    attempts=[];after=None
    while time.monotonic()<deadline:
        number=len(attempts);started=datetime.now(timezone.utc).isoformat()
        try:
            process=subprocess.run(command,capture_output=True,timeout=45)
        except subprocess.TimeoutExpired:
            attempts.append({'attempt':number,'at':started,'timeout':True})
            print('Post-boot observation pending '+str(number),flush=True)
            time.sleep(8);continue
        (OUT/('reboot-observation-'+str(number)+'.stdout')).write_bytes(process.stdout)
        (OUT/('reboot-observation-'+str(number)+'.stderr')).write_bytes(process.stderr)
        attempts.append({'attempt':number,'at':started,'exitCode':process.returncode})
        if process.returncode==0:
            value=json.loads(process.stdout.decode('utf-8-sig'))
            if value['lastBootUpTimeUtc']!=before['lastBootUpTimeUtc']:
                after=value;break
        else:
            error=process.stderr.decode('utf-8','replace')
            for marker in ['production configuration drifted','private key or ACL drifted','production DLL changed',
                           'configured runtime pins differ','active certificate bytes differ','certificate ACL changed',
                           'renewed certificate identity or validity differs','deployed executable differs']:
                if marker in error:raise ValueError('post-reboot identity refusal; inspect retained observation: '+marker)
        print('Post-boot observation pending '+str(number),flush=True)
        time.sleep(8)
    write(OUT/'reboot-poll-receipt.json',attempts)
    assert after is not None,'new boot not observed before deadline'
    assert datetime.fromisoformat(after['lastBootUpTimeUtc'].replace('Z','+00:00'))>datetime.fromisoformat(before['lastBootUpTimeUtc'].replace('Z','+00:00'))
    assert after['binary']['sha256']==deployed['newSha256'] and after['service']['state']=='Running' and after['service']['startMode']=='Auto'
    assert after['configurationPreserved'] and after['privateKeysAndAclsPreserved']
    assert after['certificates']==before['certificates'] and after['runtime']==before['runtime']
    write(OUT/'post-reboot-observation.json',after)
    script=r'''
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$stage='D:\ModelMirrors\staging\completion-rc12-20261116'
$python='D:\ModelMirrors\staging\windows-fixes-20261106\python312-completion\python3.exe'
$job='D:\ModelMirrors\staging\qualification-rc7-20261105\runtime-inputs\native-test-job-detached.exe'
$log=$stage+'\production-renewal\health-driver-post-reboot.log'
if(Test-Path -LiteralPath $log){throw 'retain post-reboot health attempt'}
$env:PYTHONUTF8='1';$env:PYTHONIOENCODING='utf-8'
$line='"'+$job+'" "'+$python+'" -I -S -B "'+$stage+'\production-health.py" post-reboot > "'+$log+'" 2>&1'
& cmd.exe /d /s /c $line
if($LASTEXITCODE -ne 0){throw 'post-reboot native health failed'}
if([IO.File]::ReadAllText($log) -notmatch 'TASK JOB CLEANUP active=0'){throw 'post-reboot health job cleanup unconfirmed'}
[IO.File]::ReadAllText($stage+'\production-health-post-reboot\result.json')
'''
    health=json.loads(remote('post-reboot-native-health',script,timeout=1200))
    assert health['status']=='passed' and len(health['cases'])==4 and health['wrongPinRejected']
    assert health['clientSha256']==deployed['newSha256'] and health['serverCertificateSha256']==after['certificates']['server']['sha256']
    final=json.loads(run('post-reboot-final-identity',command,timeout=90))
    assert final['lastBootUpTimeUtc']==after['lastBootUpTimeUtc'] and final['binary']==after['binary']
    write(PLAN/'reboot-result.json',{'schema':'mirrors.rc12.reboot-result/v1','status':'reboot-auto-start-and-mtls-verified',
        'beforeBootUtc':before['lastBootUpTimeUtc'],'afterBootUtc':after['lastBootUpTimeUtc'],
        'after':final,'health':health,'nativeHealthJobCleanupActive':0,'pollAttempts':len(attempts),
        'configurationDllRuntimeAndPrivateKeysPreserved':True,'renewedCertificatesPreserved':True,
        'otherHostOrPlatformAcceptanceInferred':False})
    print('APPROVED REBOOT, AUTOMATIC SERVICE START AND FOUR-WAY MTLS VERIFIED',flush=True)


if __name__=='__main__':main()
