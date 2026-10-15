import pathlib,tarfile,json,hashlib,shutil
r=pathlib.Path('/home/jlc/Tools/mirrors-client-fixes-20261015');d=pathlib.Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015/haskell-h2');s=r/'source/ModelMirros-h2';s.mkdir(exist_ok=True)
with tarfile.open(d/'h2-source.tar') as t:t.extractall(s)
m=json.loads((d/'h2-source-manifest.json').read_text())
for row in m['files']:assert hashlib.sha256((s/row['path']).read_bytes()).hexdigest()==row['sha256'],row['path']
(s/'cabal.project.local').write_text('index-state: 2026-09-01T00:00:00Z\n')
b=r/'source/ModelMirros-h2-baseline'
shutil.copytree(r/'source/ModelMirros',b)
for name in ['ModelMirrors.cabal','test/TlsPolicySpec.hs','test/TransportTestSupport.hs']:
 shutil.copyfile(s/name,b/name)
old=b/'src-tls/Protocol/Transport/Tls.hs';new=s/'src-tls/Protocol/Transport/Tls.hs'
receipt={'verifiedCandidateFiles':len(m['files']),'candidateArchiveSha256':hashlib.sha256((d/'h2-source.tar').read_bytes()).hexdigest(),'baseline':'H1 qualified source with only new Cabal and test overlays; actual pre-H2 TLS implementation retained','baselineTlsSha256':hashlib.sha256(old.read_bytes()).hexdigest(),'candidateTlsSha256':hashlib.sha256(new.read_bytes()).hexdigest(),'baselineOverlays':['ModelMirrors.cabal','test/TlsPolicySpec.hs','test/TransportTestSupport.hs']}
(d/'source-verification.json').write_text(json.dumps(receipt,indent=2)+'\n');print(receipt)
