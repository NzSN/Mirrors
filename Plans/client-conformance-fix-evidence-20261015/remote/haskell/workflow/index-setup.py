import pathlib,gzip,shutil,hashlib,json,time
r=pathlib.Path('/home/jlc/Tools/mirrors-client-fixes-20261015');d=pathlib.Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015')
s=d/'downloads/hackage-ustc-index.tar.gz';assert s.stat().st_size==139438910
p=r/'tools/haskell/cabal/packages/hackage.haskell.org/00-index.tar'
with gzip.open(s,'rb') as f,p.open('wb') as o:shutil.copyfileobj(f,o)
(d/'haskell/hackage-index.json').write_text(json.dumps({'url':'https://mirrors.ustc.edu.cn/hackage/01-index.tar.gz','downloadBytes':s.stat().st_size,'downloadSha256':hashlib.sha256(s.read_bytes()).hexdigest(),'uncompressedBytes':p.stat().st_size,'security':'HTTPS mirror snapshot; Cabal secure index disabled only in owned private config; artifact bytes retained remote'},indent=2)+'\n')
print(p,p.stat().st_size)
