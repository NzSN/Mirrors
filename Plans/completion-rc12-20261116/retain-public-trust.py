"""Retain the public renewal material for the requesting operator, with no key export."""
import zipfile
from common import *


def main():
    scp=['scp','-F',str(Path.home()/'.ssh/config'),'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes']
    run('public-trust-helper-transfer',scp+[PLAN/'make-public-trust-bundle.py','win10:D:/ModelMirrors/staging/completion-rc12-20261116/'],timeout=180)
    script="$env:PYTHONUTF8='1';$env:PYTHONIOENCODING='utf-8';& 'D:\\ModelMirrors\\staging\\windows-fixes-20261106\\python312-completion\\python3.exe' -I -S -B '"+STAGE+"\\make-public-trust-bundle.py';if($LASTEXITCODE -ne 0){throw 'public trust packaging failed'}"
    value=json.loads(remote('public-trust-bundle-create',script,timeout=180))
    assert not value['privateKeysIncluded'] and len(value['members'])==5
    folder=OUT/'operator-trust'
    folder.mkdir(mode=0o700)
    archive=folder/value['archive']['name']
    run('public-trust-bundle-retain',scp+['win10:D:/ModelMirrors/staging/completion-rc12-20261116/production-renewal/'+archive.name,archive],timeout=180)
    archive.chmod(0o600)
    assert identity(archive)['sha256']==value['archive']['sha256']
    with zipfile.ZipFile(archive) as handle:
        assert set(handle.namelist())=={record['name'] for record in value['members']}
        for record in value['members']:
            raw=handle.read(record['name']);assert len(raw)==record['bytes'] and hashlib.sha256(raw).hexdigest()==record['sha256']
    value['localArchive']=identity(archive)
    value['deliveryScope']='available to the requesting operator; no message to another consumer was sent'
    write(PLAN/'public-trust-bundle.json',value)
    print('PUBLIC TRUST BUNDLE RETAINED FOR THE REQUESTING OPERATOR; NO PRIVATE KEY INCLUDED',flush=True)


if __name__=='__main__':main()
