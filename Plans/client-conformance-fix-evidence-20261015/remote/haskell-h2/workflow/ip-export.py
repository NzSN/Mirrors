from pathlib import Path
import tarfile,json,hashlib
r=Path('/home/jlc/Tools/mirrors-client-fixes-20261015/tools/haskell/cabal/packages/hackage.haskell.org');d=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015/haskell-h2');rows=json.loads((d/'dependency-source-manifest.json').read_text())
for pkg,ver,ends in [('iproute','1.7.15',['Data/IP.hs','Data/IP/Addr.hs']),('crypton-x509','1.9.1',['Data/X509.hs','Data/X509/AlgorithmIdentifier.hs'])]:
 p=r/pkg/ver/(pkg+'-'+ver+'.tar.gz')
 with tarfile.open(p) as t:
  for m in t.getmembers():
   if m.isfile() and any(m.name.endswith(e) for e in ends):
    data=t.extractfile(m).read();o=d/'dependency-source'/m.name;o.parent.mkdir(parents=True,exist_ok=True);o.write_bytes(data);rows.append({'path':str(o.relative_to(d)),'archive':str(p),'sha256':hashlib.sha256(data).hexdigest()})
(d/'dependency-source-manifest.json').write_text(json.dumps(rows,indent=2)+'\n')
with tarfile.open(d/'api-source.tar','w') as t:
 for p in sorted((d/'dependency-source').rglob('*')):
  if p.is_file():t.add(p,arcname=str(p.relative_to(d)),recursive=False)
 t.add(d/'dependency-source-manifest.json',arcname='dependency-source-manifest.json')
print('source files',len(rows))
