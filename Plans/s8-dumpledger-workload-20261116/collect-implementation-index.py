from common import *


def main():
    approval=json.loads((PLAN/'processing-approved.json').read_text())
    assert approval['approved'] and approval['destination']==str(OUT)
    stage='D:/ModelMirrors/staging/s8-dumpledger-workload-20261116'
    scp=['scp','-F',str(Path.home()/'.ssh/config'),'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes']
    run('implementation-index-helper-transfer',scp+[PLAN/'retain-implementation-index.mjs','win10:'+stage+'/'],timeout=120)
    value=json.loads(run('implementation-index-read',SSH+['D:/Services/node24/node.exe',stage+'/retain-implementation-index.mjs'],timeout=120))
    target=OUT/'implementation-index.json'
    run('implementation-index-retain',scp+['win10:'+stage+'/private/observations-v2/implementation-index.json',target],timeout=120)
    target.chmod(0o600)
    assert identity(target)['sha256']==value['artifact']['sha256']
    write(OUT/'implementation-index-receipt.json',value)
    print(json.dumps({'status':value['status'],'files':value['files'],'productionModified':False},indent=2))


if __name__=='__main__':main()
