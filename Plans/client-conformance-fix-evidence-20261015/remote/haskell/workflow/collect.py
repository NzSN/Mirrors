import pathlib,json,hashlib,subprocess,shutil,tarfile,os
R=pathlib.Path('/home/jlc/Tools/mirrors-client-fixes-20261015');D=pathlib.Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015');H=D/'haskell';E=H/'evidence';E.mkdir(exist_ok=True)
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  while b:=f.read(1048576):h.update(b)
 return h.hexdigest()
def cp(p,target=None):
 if p.is_file():
  q=E/(target or p.name);q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q)
for p in H.glob('*.log'):cp(p,'diagnostics/'+p.name)
for p in H.glob('*.json'):cp(p)
for p in H.glob('*.py'):cp(p,'workflow/'+p.name)
for p in H.glob('*.sh'):cp(p,'workflow/'+p.name)
for n in ['haskell-download.sh','haskell-setup.py','haskell-ghc-install.sh','haskell-segmented.py'] :cp(D/n,'workflow/'+n)
for p in (H/'logs').glob('*.log'):cp(p,'logs/'+p.name)
for n in ['ghc-SHA256SUMS','cabal-SHA256SUMS','ghc-download.log','ghc-ustc.log','segmented.log','hackage-index-download.log','hackage-ustc.log','hackage-tuna.log','ustc-list.html']:cp(D/'downloads'/n,'diagnostics/'+n)
cp(D/'source-manifest.json');cp(H/'RedCoreProbe.hs','workflow/RedCoreProbe.hs')
cp(R/'tools/haskell/cabal/config','workflow/cabal-config');cp(R/'source/ModelMirros/cabal.project.local','workflow/cabal.project.local');cp(H/'dist/cache/plan.json','dependency-plan.json')
original=json.loads((D/'source-manifest.json').read_text());rows=[]
for row in original['files']:
 p=R/'source/ModelMirros'/row['path'];actual=sha(p);assert actual==row['sha256'],row['path'];rows.append({'path':row['path'],'sha256':actual})
(E/'source-verification-final.json').write_text(json.dumps({'verifiedFiles':len(rows),'files':rows,'validationOverlay':['cabal.project.local']},indent=2)+'\n')
cache=R/'tools/haskell/cabal/packages/hackage.haskell.org';packages=[{'path':str(p.relative_to(cache)),'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(cache.rglob('*.tar.gz')) if p.name not in ['00-index.tar.gz','01-index.tar.gz']]
(E/'dependency-archives.json').write_text(json.dumps({'secureIndex':True,'indexState':'2026-09-01T00:00:00Z','packages':packages},indent=2)+'\n')
for n in ['root.json','timestamp.json','snapshot.json','mirrors.json']:cp(cache/n,'signed-index/'+n)
tools=[]
for p in [R/'tools/haskell/ghc/lib/ghc-9.14.1/bin/ghc-9.14.1',R/'tools/haskell/bin/cabal',pathlib.Path('/usr/bin/openssl')]:
 tools.append({'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p)})
bins=[{'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p)} for p in (H/'dist').rglob('ModelMirrors-test') if p.is_file()]
for name in ['baseline','fixed']:
 p=H/('red-'+name)/'probe'
 if p.exists():bins.append({'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p)})
(E/'artifacts.json').write_text(json.dumps({'tools':tools,'binaries':bins,'baselineArchiveSha256':sha(H/'baseline.tar'),'baselineCoreSha256':sha(R/'source/ModelMirros-baseline/src/Protocol/Transport/Core.hs')},indent=2)+'\n')
# Only retained text/JSON/workflows; never copy private keys, binaries or caches.
files=[{'path':str(p.relative_to(E)),'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(E.rglob('*')) if p.is_file() and p.name!='evidence-manifest.json']
(E/'evidence-manifest.json').write_text(json.dumps({'files':files},indent=2)+'\n')
with tarfile.open(H/'evidence.tar','w') as tar:
 for p in sorted(E.rglob('*')):
  if p.is_file():tar.add(p,arcname=str(p.relative_to(E)),recursive=False)
print('evidence',len(files),'bytes',sum(f['bytes'] for f in files),'tarSha256',sha(H/'evidence.tar'))
