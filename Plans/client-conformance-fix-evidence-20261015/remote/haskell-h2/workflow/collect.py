import pathlib,os,json,hashlib,shutil,tarfile
R=pathlib.Path('/home/jlc/Tools/mirrors-client-fixes-20261015');D=pathlib.Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015');H=D/'haskell-h2';E=H/'evidence';E.mkdir(exist_ok=True)
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  while b:=f.read(1048576):h.update(b)
 return h.hexdigest()
def cp(p,target=None):
 if p.is_file():
  q=E/(target or p.name);q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q)
rows=[]
for p in pathlib.Path('/proc').iterdir():
 if not p.name.isdigit() or int(p.name)==os.getpid():continue
 try:exe=os.readlink(p/'exe');cmd=(p/'cmdline').read_bytes().replace(b'\0',b' ').decode(errors='replace')
 except OSError:continue
 if (str(R/'tools/haskell') in exe or ('/haskell-h2/' in exe and 'ModelMirrors-test' in exe)):
  rows.append({'pid':int(p.name),'exe':exe,'command':cmd})
temps=[str(p) for p in pathlib.Path('/tmp/fix-tests').glob('modelmirrors-*')];assert not rows;assert not temps
(H/'cleanup.json').write_text(json.dumps({'activeOwnedHaskellProcesses':rows,'remainingModelMirrorsTempDirectories':temps,'toolsAndSourcesAndBinariesPreserved':True,'modelChecking':False},indent=2)+'\n')
original=json.loads((H/'h2-source-manifest.json').read_text());verified=[]
for row in original['files']:
 p=R/'source/ModelMirros-h2'/row['path'];actual=sha(p);assert actual==row['sha256'],row['path'];verified.append({'path':row['path'],'sha256':actual})
(H/'source-verification-final.json').write_text(json.dumps({'verifiedFiles':len(verified),'files':verified,'validationOverlay':['cabal.project.local']},indent=2)+'\n')
h1=json.loads((D/'haskell/evidence/source-manifest.json').read_text())
for row in h1['files']:assert sha(R/'source/ModelMirros'/row['path'])==row['sha256'],row['path']
h1artifact=json.loads((D/'haskell/evidence/artifacts.json').read_text())
for a in h1artifact['binaries']:assert sha(pathlib.Path(a['path']))==a['sha256'],a['path']
(H/'preserved-h1.json').write_text(json.dumps({'verifiedSourceFiles':len(h1['files']),'verifiedBinaries':h1artifact['binaries'],'h1EvidenceManifestSha256':sha(D/'haskell/evidence/evidence-manifest.json'),'unchanged':True},indent=2)+'\n')
for p in H.glob('*.json'):cp(p)
for p in H.glob('*.py'):cp(p,'workflow/'+p.name)
for p in H.glob('*.log'):cp(p,'diagnostics/'+p.name)
for p in (H/'logs').glob('*.log'):cp(p,'logs/'+p.name)
cp(R/'source/ModelMirros-h2/cabal.project.local','workflow/cabal.project.local');cp(R/'tools/haskell/cabal/config','workflow/cabal-config')
for n in ['dist','baseline-dist']:cp(H/n/'cache/plan.json',n+'-dependency-plan.json')
for n in ['toolchain.json','tool-downloads.json','dependency-archives.json']:cp(D/'haskell/evidence'/n,'inherited-h1/'+n)
for n in ['root.json','timestamp.json','snapshot.json','mirrors.json']:cp(R/'tools/haskell/cabal/packages/hackage.haskell.org'/n,'signed-index/'+n)
accept=json.loads((H/'acceptance.json').read_text());bins=[]
for name in ['candidateBinary','baselineBinary']:
 p=pathlib.Path(accept[name]);bins.append({'kind':name,'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p)})
(E/'artifacts.json').write_text(json.dumps({'binaries':bins},indent=2)+'\n')
files=[{'path':str(p.relative_to(E)),'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(E.rglob('*')) if p.is_file() and p.name!='evidence-manifest.json']
(E/'evidence-manifest.json').write_text(json.dumps({'files':files},indent=2)+'\n')
with tarfile.open(H/'evidence.tar','w') as tar:
 for p in sorted(E.rglob('*')):
  if p.is_file():tar.add(p,arcname=str(p.relative_to(E)),recursive=False)
print('H2 evidence',len(files),sum(f['bytes'] for f in files),'archiveSha256',sha(H/'evidence.tar'),'manifestSha256',sha(E/'evidence-manifest.json'))
