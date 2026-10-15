from pathlib import Path
import tarfile,json,hashlib
r=Path('/home/jlc/Tools/mirrors-client-fixes-20261015/tools/haskell/cabal/packages/hackage.haskell.org');d=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015/haskell-h2');d.mkdir(exist_ok=True)
rows=[]
for pkg,ver,ends in [('crypton-x509-validation','1.9.1',['Data/X509/Validation.hs','Data/X509/Validation/Types.hs','Data/X509/Validation/Cache.hs']),('tls','2.4.3',['Network/TLS/Parameters.hs']),('crypton-x509','1.9.1',['Data/X509/ExtensionRaw.hs','Data/X509/Ext.hs','Data/X509/CertificateChain.hs','Data/X509/Cert.hs'])]:
 archive=r/pkg/ver/(pkg+'-'+ver+'.tar.gz')
 with tarfile.open(archive) as t:
  for m in t.getmembers():
   if m.isfile() and any(m.name.endswith(e) for e in ends):
    data=t.extractfile(m).read();p=d/'dependency-source'/m.name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data);rows.append({'path':str(p.relative_to(d)),'archive':str(archive),'sha256':hashlib.sha256(data).hexdigest()})
   if pkg=='crypton-x509' and m.isfile() and m.name.endswith('.hs'):
    s=t.extractfile(m).read().decode()
    if 'data ExtSubjectAltName' in s or 'data AltName' in s or 'newtype ExtSubjectAltName' in s:
     print('FILE',m.name)
     for i,line in enumerate(s.splitlines()):
      if any(v in line for v in ['ExtSubjectAltName','data AltName','AltNameDNS','AltNameIP','extensionGet','extensionDecode']): print(i+1,line)
(d/'dependency-source-manifest.json').write_text(json.dumps(rows,indent=2)+'\n')
with tarfile.open(d/'api-source.tar','w') as t:
 for p in sorted(d.rglob('*')):
  if p.is_file() and p.name!='api-source.tar':t.add(p,arcname=str(p.relative_to(d)),recursive=False)
print('exported',len(rows))
