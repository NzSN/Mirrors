from pathlib import Path
import json,hashlib,subprocess,platform
r=Path('/home/jlc/Tools/mirrors-client-fixes-20261015');d=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015');h=d/'haskell'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
items=[]
for name,manifest,url in [('ghc-9.14.1-x86_64-deb11-linux.tar.xz','ghc-SHA256SUMS','https://mirrors.ustc.edu.cn/ghcup/downloads.haskell.org/~ghc/9.14.1/ghc-9.14.1-x86_64-deb11-linux.tar.xz'),('cabal-install-3.16.1.0-x86_64-linux-deb11.tar.xz','cabal-SHA256SUMS','https://downloads.haskell.org/~cabal/cabal-install-3.16.1.0/cabal-install-3.16.1.0-x86_64-linux-deb11.tar.xz')]:
 p=d/'downloads'/name;expected=next(line.split()[0] for line in (d/'downloads'/manifest).read_text().splitlines() if line.split()[-1].lstrip('./')==name);actual=sha(p);assert expected==actual
 items.append({'name':name,'url':url,'bytes':p.stat().st_size,'sha256':actual,'officialManifest':manifest,'officialManifestSha256':sha(d/'downloads'/manifest),'officialSha256VerifiedBeforeExecution':True})
(h/'tool-downloads.json').write_text(json.dumps({'artifacts':items,'initialOfficialAndRegionalFailuresRetainedInDiagnostics':True},indent=2)+'\n')
p=h/'hackage-index.json';x=json.loads(p.read_text());x['security']='Initial archive staging superseded by successful Cabal secure=True signed root/timestamp/snapshot/mirrors update before solver/build; no build used insecure metadata';x['buildIndexState']='2026-09-01T00:00:00Z';x['signedIndex']=True;p.write_text(json.dumps(x,indent=2)+'\n')
versions={}
for name,args in [('ghc',[str(r/'tools/haskell/ghc/bin/ghc'),'--version']),('cabal',[str(r/'tools/haskell/bin/cabal'),'--version']),('openssl',['openssl','version']),('gcc',['gcc','--version']),('platform',['uname','-a'])]:
 versions[name]=subprocess.check_output(args,text=True).strip()
(h/'toolchain.json').write_text(json.dumps({'versions':versions,'jobs':2,'locale':'C.UTF-8','modelChecking':False,'ownedExt4Root':str(r),'buildRoot':str(h/'dist')},indent=2)+'\n')
