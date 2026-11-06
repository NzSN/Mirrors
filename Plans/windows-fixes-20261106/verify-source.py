import hashlib,io,json,subprocess
from pathlib import Path
stage=Path(r'D:\ModelMirrors\staging\windows-fixes-20261106')
source=stage/'Mirrors'
old=Path(r'D:\ModelMirrors\staging\qualification-rc7-20261105\Mirrors-rc8-f328e32')
git=r'C:\Program Files\Git\cmd\git.exe'
manifest=json.loads((stage/'final-source-overlay.json').read_text())
expected={row['path']:row['sha256'] for row in manifest}
paths=subprocess.check_output([git,'-C',str(source),'ls-tree','-r','--name-only','HEAD']).decode().splitlines()
payload=subprocess.check_output([git,'-C',str(source),'cat-file','--batch'],input=''.join('HEAD:'+p+'\n' for p in paths).encode())
blobs=io.BytesIO(payload);mismatches=[];old_mismatches=[]
for p in paths:
 header=blobs.readline().split();size=int(header[-1]);raw=blobs.read(size);assert blobs.read(1)==b'\n'
 digest=hashlib.sha256(raw).hexdigest()
 if hashlib.sha256((source/p).read_bytes()).hexdigest()!=expected.get(p,digest):mismatches.append(p)
 if hashlib.sha256((old/p).read_bytes()).hexdigest()!=digest:old_mismatches.append(p)
for p,digest in expected.items():
 if p not in paths and hashlib.sha256((source/p).read_bytes()).hexdigest()!=digest:mismatches.append(p)
binary=source/'.lake/build/bin/mirrors_dpm.exe';alias=binary.with_suffix('')
result={'status':'passed' if not mismatches and not old_mismatches else 'failed',
 'frozenBase':subprocess.check_output([git,'-C',str(source),'rev-parse','HEAD']).decode().strip(),
 'trackedFilesVerified':len(paths),'overlayFilesVerified':len(expected),'sourceMismatches':mismatches,
 'originalCheckoutMismatches':old_mismatches,
 'originalCheckoutStatus':subprocess.check_output([git,'-C',str(old),'status','--porcelain']).decode().splitlines(),
 'modifiedCheckoutStatus':subprocess.check_output([git,'-C',str(source),'status','--porcelain']).decode().splitlines(),
 'launcherSha256':hashlib.sha256(binary.read_bytes()).hexdigest(),
 'launcherAliasMatches':binary.read_bytes()==alias.read_bytes()}
(stage/'source-verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
assert result['status']=='passed' and result['originalCheckoutStatus']==[] and result['launcherAliasMatches']
