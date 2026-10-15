import hashlib,json,os,subprocess
from pathlib import Path
root=Path('/home/jlc/Tools/mirrors-client-fixes-20261015')
build=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015')
selected=json.loads((build/'ready-source-manifest.json').read_text())
records={}
for name in ['Mirrors','MirrorECMA']:
    source=root/'source'/name
    before=subprocess.check_output(['git','rev-parse','HEAD'],cwd=source,text=True).strip()
    names=sorted(selected[name])
    pathspec=build/(name+'-validation-pathspec')
    pathspec.write_bytes(b'\0'.join(path.encode() for path in names)+b'\0')
    subprocess.run(['git','add','-f','--pathspec-from-file='+str(pathspec),'--pathspec-file-nul'],cwd=source,check=True)
    staged=subprocess.check_output(['git','diff','--cached','--name-only','-z'],cwd=source).split(b'\0')
    assert all(path.decode() in names for path in staged if path)
    result=subprocess.run(['git','-c','core.hooksPath=/dev/null','-c','gc.auto=0',
        '-c','user.name=Mirrors WSL validation','-c','user.email=validation@invalid.example',
        'commit','--allow-empty','-m','validation snapshot: client conformance repairs'],cwd=source,capture_output=True,text=True,check=True)
    after=subprocess.check_output(['git','rev-parse','HEAD'],cwd=source,text=True).strip()
    current={path:hashlib.sha256((source/path).read_bytes()).hexdigest() for path in names}
    records[name]={'baseHead':before,'validationSnapshotCommit':after,'sourceFiles':current,
                   'commitStdout':result.stdout,'commitStderr':result.stderr,
                   'originalCheckoutModified':False,'pushed':False,
                   'purpose':'only ephemeral remote Git identity required by non-live coordinated CI'}
(build/'validation-commits.json').write_text(json.dumps(records,indent=2)+'\n')
print(json.dumps({name:{'baseHead':row['baseHead'],'validationSnapshotCommit':row['validationSnapshotCommit']} for name,row in records.items()},indent=2),flush=True)
