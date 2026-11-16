"""Run a bounded read-only aggregate collector in an owner-controlled host stage."""
from common import *


def main():
    stage=r'D:\ModelMirrors\staging\s8-dumpledger-workload-20261116'
    script=r'''
$ErrorActionPreference='Stop'
$path='D:\ModelMirrors\staging\s8-dumpledger-workload-20261116\private'
if(Test-Path -LiteralPath $path){throw 'retain existing private workload stage'}
New-Item -ItemType Directory -Path $path|Out-Null
$acl=New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true,$false)
foreach($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,'S-1-5-18','S-1-5-32-544')){$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)),'FullControl','ContainerInherit,ObjectInherit','None','Allow')))}
Set-Acl -LiteralPath $path -AclObject $acl
Write-Output 'PRIVATE WORKLOAD STAGE READY'
'''
    remote('private-workload-stage',script)
    scp=['scp','-F',str(Path.home()/'.ssh/config'),'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes']
    run('domain-inventory-helper-transfer',scp+[PLAN/'domain-inventory.py','win10:'+stage.replace('\\','/')+'/'],timeout=180)
    value=json.loads(run('domain-inventory-readonly',SSH+['D:/ModelMirrors/staging/windows-fixes-20261106/python312-completion/python3.exe',
        '-I','-S','-B',stage.replace('\\','/')+'/domain-inventory.py'],timeout=180))
    assert value['databaseOpenedReadOnly'] and value['queryOnly'] and value['databaseChangesByCollector']==0
    assert not value['authDatabaseOrEnvRead'] and not value['dumpBytesRead']
    write(OUT/'domain-inventory.json',value)
    print(json.dumps({key:item for key,item in value.items() if key not in ['pythonVersion','domainColumnNames','sampledDetailFieldNames']},indent=2))


if __name__=='__main__':main()
