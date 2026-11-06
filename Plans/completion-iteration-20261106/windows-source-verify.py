"""Runs on the owned Windows clean checkout; compares every blob with Git."""
import hashlib,io,json,subprocess
from pathlib import Path
STAGE=Path(r'D:\ModelMirrors\staging\completion-rc9-20261106');SOURCE=STAGE/'source'
GIT=r'C:\Program Files\Git\cmd\git.exe';REV='0f7d94eabe19d75172164708fd2e46b1d185f260'
assert subprocess.check_output([GIT,'-C',str(SOURCE),'rev-parse','HEAD'],text=True).strip()==REV
paths=subprocess.check_output([GIT,'-C',str(SOURCE),'ls-tree','-r','--name-only','HEAD']).decode().splitlines()
blobs=io.BytesIO(subprocess.check_output([GIT,'-C',str(SOURCE),'cat-file','--batch'],input=''.join('HEAD:'+p+'\n' for p in paths).encode()))
mismatches=[]
for name in paths:
 head=blobs.readline().split();data=blobs.read(int(head[-1]));assert blobs.read(1)==b'\n'
 path=SOURCE/name
 if not path.is_file() or hashlib.sha256(path.read_bytes()).digest()!=hashlib.sha256(data).digest():mismatches.append(name)
status=subprocess.check_output([GIT,'-C',str(SOURCE),'status','--porcelain'],text=True).splitlines()
result={'status':'passed' if not mismatches and not status else 'failed','commit':REV,'tree':subprocess.check_output([GIT,'-C',str(SOURCE),'rev-parse','HEAD^{tree}'],text=True).strip(),'gitBlobsVerified':len(paths),'mismatches':mismatches,'sourceStatus':status,'sourceOverlay':False,'sourceBuiltMirrorSha256':hashlib.sha256((SOURCE/'.lake/build/bin/mirror.exe').read_bytes()).hexdigest(),'sourceBuiltCompilerSha256':hashlib.sha256((SOURCE/'.lake/build/bin/model_interface_gen.exe').read_bytes()).hexdigest()}
with (STAGE/'source-verification.json').open('x') as stream:stream.write(json.dumps(result,indent=2)+'\n')
print(json.dumps(result));assert result['status']=='passed'
