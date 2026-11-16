"""Apply the approved renewal/deployment only after trial and published-artifact admission."""
from common import *


def main():
    release=json.loads((PLAN/'release-publication.json').read_text())
    package=json.loads((PLAN/'windows-package.json').read_text())
    assert release['workflowSucceeded'] and release['prerelease'] and not release['isLatest']
    assert next(asset for asset in release['assets'] if asset['name']==package['archive']['name'])['sha256']==package['archive']['sha256']
    trial=json.loads((PLAN/'production-trust-trials.json').read_text())
    assert trial['ownedJobCleanupActive']==0 and len(trial['cases'])==2
    scp=['scp','-F',str(Path.home()/'.ssh/config'),'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes']
    run('production-deploy-helper-transfer',scp+[PLAN/'deploy-production.ps1',PLAN/'production-trust-trials.json','win10:D:/ModelMirrors/staging/completion-rc12-20261116/'],timeout=180)
    parser="$tokens=$null;$errors=$null;[void][System.Management.Automation.Language.Parser]::ParseFile('"+STAGE+"\\deploy-production.ps1',[ref]$tokens,[ref]$errors);if($errors.Count -ne 0){throw ($errors|Out-String)};Write-Output 'POWERSHELL PARSER GREEN'"
    remote('production-deploy-parser',parser)
    base=SSH+['powershell','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',STAGE.replace('\\','/')+'/deploy-production.ps1','-Mode']
    prepared=json.loads(run('production-deploy-prepare',base+['Prepare'],timeout=180))
    assert prepared['status']=='prepared' and not prepared['activeProductionModified']
    run('production-deploy-apply',base+['Apply'],timeout=1200)
    result=json.loads(remote('production-deploy-result-read',"[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false);[IO.File]::ReadAllText('"+STAGE+"\\production-renewal\\deployment-result.json')"))
    assert result['status']=='renewed-trust-and-rc12-deployed-live-verified'
    assert result['health']['wrongPinRejected'] and len(result['health']['cases'])==4
    assert result['existingKeysAndAclsPreserved'] and result['configurationAndDllsPreserved']
    write(PLAN/'deployment-result.json',result)
    write(OUT/'deployed-observation.json',result['observation'])
    print('PRODUCTION TRUST RENEWED AND EXACT RC12 DEPLOYED; LIVE MTLS AND ROLLBACK BASELINE VERIFIED',flush=True)


if __name__=='__main__':main()
