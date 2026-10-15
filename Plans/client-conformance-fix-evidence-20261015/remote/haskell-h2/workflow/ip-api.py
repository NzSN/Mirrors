from pathlib import Path
import tarfile
r=Path('/home/jlc/Tools/mirrors-client-fixes-20261015/tools/haskell/cabal/packages/hackage.haskell.org')
for pkg,ver in [('iproute','1.7.15'),('crypton-x509','1.9.1')]:
 with tarfile.open(r/pkg/ver/(pkg+'-'+ver+'.tar.gz')) as t:
  for m in t.getmembers():
   if not m.isfile() or not m.name.endswith('.hs'):continue
   s=t.extractfile(m).read().decode();ls=s.splitlines();keep=set()
   for i,l in enumerate(ls):
    if ('fromIPv4' in l or 'fromIPv6' in l or 'data HashALG' in l or 'HashALG (' in l or 'HashSHA256' in l or (m.name.endswith('Data/IP.hs') and i<100)):
     keep.update(range(max(0,i-2),min(len(ls),i+8)))
   if keep:
    print('FILE',m.name)
    for i in sorted(keep):print(f'{i+1}: {ls[i]}')
