import hashlib,json,shutil,subprocess
from pathlib import Path
root=Path('/home/jlc/Tools/mirrors-client-fixes-20261015')
build=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015')
snapshots=json.loads((build/'validation-commits.json').read_text())
verified={}
for name in ['Mirrors','MirrorECMA']:
    source=root/'source'/name;selected=snapshots[name]
    changes=[]
    for path,expected in selected['sourceFiles'].items():
        actual=hashlib.sha256((source/path).read_bytes()).hexdigest()
        if actual!=expected:changes.append(path)
    assert not changes,(name,changes)
    verified[name]={'validationSnapshotCommit':selected['validationSnapshotCommit'],'sourceFilesVerified':len(selected['sourceFiles'])}
source=root/'source/Mirrors'
binary=source/'.lake/build/bin/mirror'
digest=hashlib.sha256(binary.read_bytes()).hexdigest()
directory=build/'cpp-gate/immutable';directory.mkdir(parents=True,exist_ok=True)
frozen=directory/'mirror'
assert not frozen.exists()
shutil.copy2(binary,frozen);frozen.chmod(0o555)
assert hashlib.sha256(frozen.read_bytes()).hexdigest()==digest
native={name:hashlib.sha256((source/name).read_bytes()).hexdigest() for name in ['Ffi/socket_shim.c','Ffi/tls_shim.c','lakefile.lean']}
objects={name:hashlib.sha256((source/'.lake/build'/name).read_bytes()).hexdigest() for name in ['socket_shim.o','tls_shim.o']}
record={'status':'source-verified-immutable-producer','mirrorPath':str(frozen),'mirrorSha256':digest,
        'sourceMirrorBinary':str(binary),'sourceSnapshots':verified,'nativeInputs':native,'nativeObjects':objects,
        'compiler':subprocess.check_output(['/usr/bin/gcc-12','--version'],text=True),'mode':'0555',
        'noFurtherWritesToProducer':True,'actualOriginalCheckoutsCommitted':False}
(build/'frozen-mirror-producer.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2),flush=True)
