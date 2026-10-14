import hashlib
import json
from pathlib import Path

root=Path('/home/jlc/Tools/mirrors-dpm-followup-20261014')
build=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/followup-20261014')
selection=json.loads((build/'local-source-selection.json').read_text())
repositories=[]
count=0
for repository in selection['repositories']:
    files={}
    for name,row in repository['workingFiles'].items():
        file=root/'source'/repository['name']/name
        actual={'sha256':hashlib.sha256(file.read_bytes()).hexdigest(),'bytes':file.stat().st_size,
                'executable':bool(file.stat().st_mode&0o111)} if file.is_file() else None
        matches=actual is not None and all(row[key]==actual[key] for key in ['sha256','bytes','executable'])
        if row['scope']=='implementation':assert matches,(repository['name'],name,row,actual)
        count+= row['scope']=='implementation'
        files[name]={**row,'remoteSource':actual,'matchesCompiledSnapshot':matches}
    repositories.append({'name':repository['name'],'baseHead':repository['head'],
                         'localPath':repository['localPath'],'qualifiedRemoteRoot':str(root/'source'/repository['name']),
                         'workingFiles':files})
record={'schema':'mirrors.dpm-followup-source-manifest/v1','repositories':repositories,
        'status':'verified','implementationFilesVerified':count,
        'documentationScope':'local snapshot only; final acceptance documentation recorded separately'}
(build/'source-manifest.json').write_text(json.dumps(record,indent=2)+'\n')
print('SOURCE_PARITY_VERIFIED_IMPLEMENTATION_FILES',count)
