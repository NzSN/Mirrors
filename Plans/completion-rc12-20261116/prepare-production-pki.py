"""Transfer and run approved host-local key-preserving production certificate preparation."""
from common import *
import sys


def main():
    approval=json.loads((PLAN/'shipping-approved.json').read_text())
    assert 'renew production CA/server/default-client certificates preserving existing keys/subjects/SAN with 90-day validity' in approval['scopeIncludes']
    suffix=sys.argv[1] if len(sys.argv)>1 else ''
    name='renew-production-pki'+suffix+'.ps1'
    scp=['scp','-F',str(Path.home()/'.ssh/config'),'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes']
    run('production-pki-helper-transfer'+suffix,scp+[PLAN/name,PLAN/'production-renewal-prerequisites.json','win10:D:/ModelMirrors/staging/completion-rc12-20261116/'],timeout=180)
    parser="$tokens=$null;$errors=$null;[void][System.Management.Automation.Language.Parser]::ParseFile('"+STAGE+'\\'+name+"',[ref]$tokens,[ref]$errors);if($errors.Count -ne 0){throw ($errors|Out-String)};Write-Output 'POWERSHELL PARSER GREEN'"
    remote('production-pki-parser'+suffix,parser)
    raw=run('production-pki-renewal'+suffix,SSH+['powershell','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',STAGE.replace('\\','/')+'/'+name],timeout=240)
    value=json.loads(raw)
    assert value['existingKeysAndAclsPreserved'] and value['caChainAndPurposeChecksPassed']
    assert not value['productionModified'] and not value['privateKeysExported']
    write(PLAN/'production-pki-renewal.json',value)
    print('RENEWED PRODUCTION CA/SERVER/CLIENT PREPARED; EXISTING KEYS AND ACTIVE PRODUCTION UNCHANGED',flush=True)


if __name__=='__main__':main()
