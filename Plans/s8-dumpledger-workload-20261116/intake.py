"""Discover the deployed workload source without reading configuration secrets or dump bytes."""
from common import *


def main():
    stage=r'D:\ModelMirrors\staging\s8-dumpledger-workload-20261116'
    remote('workload-helper-stage',"$ErrorActionPreference='Stop';if(-not(Test-Path -LiteralPath '"+stage+"')){New-Item -ItemType Directory -Path '"+stage+"'|Out-Null};Write-Output 'OWNED HELPER STAGE READY'")
    scp=['scp','-F',str(Path.home()/'.ssh/config'),'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes']
    run('workload-observer-transfer',scp+[PLAN/'observe-deployment.ps1','win10:'+stage.replace('\\','/')+'/'],timeout=180)
    value=json.loads(run('dumpledger-deployment-intake',SSH+['powershell','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',stage.replace('\\','/')+'/observe-deployment.ps1']))
    assert value['host']=='DESKTOP-6DKB5JD' and not value['serviceOrDataMutated']
    write(PLAN/'deployment-intake.json',value)
    print(json.dumps(value,indent=2))


if __name__=='__main__':main()
