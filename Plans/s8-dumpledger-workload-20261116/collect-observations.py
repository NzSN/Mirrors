"""Collect only pseudonymous observed frames and receipts; original dump bytes stay on win10."""
from common import *
import sys


def main():
    approval=json.loads((PLAN/'processing-approved.json').read_text())
    assert approval['approved'] and approval['destination']==str(OUT)
    expected={'c95341bf4cb42031','1a619a5600db6051','c57ec0cde7b7e01a'}
    assert set(approval['aliases'])==expected and not approval['rawDumpBytesMayLeaveWin10']
    suffix='-v2' if '--attempt-v2' in sys.argv else ''
    stage='D:/ModelMirrors/staging/s8-dumpledger-workload-20261116'
    scp=['scp','-F',str(Path.home()/'.ssh/config'),'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes']
    run('observation-producer-transfer'+suffix,scp+[PLAN/('produce-observations'+suffix+'.mjs'),PLAN/('produce-observations'+suffix+'.ps1'),'win10:'+stage+'/'],timeout=180)
    value=json.loads(run('isolated-observation-producer'+suffix,SSH+['powershell','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',stage+'/produce-observations'+suffix+'.ps1'],timeout=180))
    assert value['totalObservationFrames']==21 and not value['rawDumpBytesExported']
    assert not value['expectedTraceReadByProducer'] and not value['productionDatabaseOpenedByReplay']
    folder=OUT/'observations';folder.mkdir(mode=0o700)
    for candidate in value['selectedCandidates']:
        artifact=candidate['artifact'];name=artifact['name']
        assert Path(name).name==name and name.endswith('.json')
        run('retain-observations-'+candidate['alias'],scp+['win10:'+stage+'/private/observations'+suffix+'/'+name,folder/name],timeout=120)
        (folder/name).chmod(0o600)
        assert identity(folder/name)['sha256']==artifact['sha256']
    value['ownedJobCleanupActive']=0
    write(OUT/'observation-producer.json',value)
    print(json.dumps({'status':value['status'],'selectedInputs':len(value['selectedCandidates']),
          'observations':value['totalObservationFrames'],'rawDumpBytesExported':False,
          'productionDataMutated':False,'ownedJobCleanupActive':0},indent=2))


if __name__=='__main__':main()
