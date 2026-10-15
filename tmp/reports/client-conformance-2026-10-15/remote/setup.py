import hashlib,json,os,subprocess,tarfile
from pathlib import Path
root=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-conformance-20261015')
with tarfile.open(root/'mirrorlean-client-audit-20261015.tar') as archive:
    for item in archive.getmembers():
        path=Path(item.name)
        assert item.isfile() and not path.is_absolute() and '..' not in path.parts
        assert not (root/path).exists()
    archive.extractall(root)
selected=json.loads((root/'lean-source-manifest.json').read_text())
for name,row in selected['files'].items():
    file=root/'MirrorLean'/name
    assert hashlib.sha256(file.read_bytes()).hexdigest()==row['sha256']
current=json.loads((root/'ecma-source-selection.json').read_text())
old=Path('/home/jlc/Tools/mirrors-dpm-remediation-20261013/source/MirrorECMA')
mismatches=[]
for name,digest in current.items():
    file=old/name
    if not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest()!=digest:mismatches.append(name)
commands={'kernel':['uname','-a'],'disk':['df','-h','/','/mnt/d'],'memory':['free','-h'],
    'lean':['/home/jlc/.elan/bin/lean','--version'],'cc':['cc','--version'],
    'openssl':['openssl','version'],'node':['/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/node/bin/node','--version']}
versions={}
for name,command in commands.items():
    value=subprocess.run(command,cwd=root/'MirrorLean',capture_output=True,text=True,check=True)
    versions[name]={'command':command,'stdout':value.stdout,'stderr':value.stderr}
result={'status':'lean-source-verified','sourceHead':selected['head'],'sourceFilesVerified':len(selected['files']),
    'sourceRoot':str(root/'MirrorLean'),'versions':versions,
    'ecmaSourceFilesCompared':len(current),'ecmaSourceMismatches':mismatches,
    'ecmaPreparedRoot':'/home/jlc/Tools/mirrors-dpm-remediation-20261013/ecma/node_modules/mirrorecma',
    'oldSourcesOrInstallsMutated':False,'modelCheckerExecuted':False}
(root/'preflight.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2),flush=True)
