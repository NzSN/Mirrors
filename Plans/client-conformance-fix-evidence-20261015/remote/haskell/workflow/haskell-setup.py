import pathlib,tarfile,json,hashlib
r=pathlib.Path('/home/jlc/Tools/mirrors-client-fixes-20261015')
d=pathlib.Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015')
s=r/'source/ModelMirros';s.mkdir(parents=True,exist_ok=True)
with tarfile.open(d/'source.tar') as t:t.extractall(s)
m=json.loads((d/'source-manifest.json').read_text())
for row in m['files']:
 p=s/row['path'];assert hashlib.sha256(p.read_bytes()).hexdigest()==row['sha256'],row
out=d/'haskell';out.mkdir(exist_ok=True)
(out/'source-verification.json').write_text(json.dumps({'verifiedFiles':len(m['files']),'archiveSha256':hashlib.sha256((d/'source.tar').read_bytes()).hexdigest()},indent=2)+'\n')
print('verified',len(m['files']))
