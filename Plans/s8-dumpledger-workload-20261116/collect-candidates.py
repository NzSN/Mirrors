from common import *


def main():
    stage='D:/ModelMirrors/staging/s8-dumpledger-workload-20261116'
    scp=['scp','-F',str(Path.home()/'.ssh/config'),'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes']
    run('candidate-selector-transfer',scp+[PLAN/'select-workload.py','win10:'+stage+'/'],timeout=180)
    value=json.loads(run('candidate-selector-readonly',SSH+['D:/ModelMirrors/staging/windows-fixes-20261106/python312-completion/python3.exe','-I','-S','-B',stage+'/select-workload.py'],timeout=180))
    assert value['productionDomainRowsChanged']==0 and not value['payloadBytesExported']
    write(OUT/'candidate-summary.json',value)
    print(json.dumps(value,indent=2))


if __name__=='__main__':main()
