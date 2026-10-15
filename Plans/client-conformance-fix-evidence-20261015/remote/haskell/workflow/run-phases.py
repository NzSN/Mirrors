import os,pathlib,subprocess,time,json,hashlib,tarfile
r=pathlib.Path('/home/jlc/Tools/mirrors-client-fixes-20261015');d=pathlib.Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015');out=d/'haskell';logs=out/'logs';logs.mkdir(exist_ok=True)
env=dict(os.environ,PATH=f'{r}/tools/haskell/bin:{r}/tools/haskell/ghc/bin:/usr/bin:/bin',TMPDIR='/tmp/fix-tests',CABAL_DIR=str(r/'tools/haskell/cabal'),LC_ALL='C.UTF-8')
cabal=[str(r/'tools/haskell/bin/cabal'),'--config-file='+str(r/'tools/haskell/cabal/config')]
builddir='--builddir='+str(out/'dist');source=r/'source/ModelMirros'
results=[]
def run(name,args,cwd=source,timeout=1800,expected=0):
 started=time.time()
 with (logs/(name+'.log')).open('wb') as w:
  try:p=subprocess.run(args,cwd=cwd,env=env,stdout=w,stderr=subprocess.STDOUT,timeout=timeout);code=p.returncode
  except subprocess.TimeoutExpired:code=124
 result={'name':name,'command':args,'cwd':str(cwd),'exit':code,'seconds':round(time.time()-started,3)};results.append(result)
 (out/'phases.json').write_text(json.dumps(results,indent=2)+'\n');print(name,code,flush=True)
 if code!=expected:raise SystemExit(code or 1)
run('build',cabal+['build','ModelMirrors-test',builddir,'-j2'],timeout=3600)
run('test-list',cabal+['test','ModelMirrors-test',builddir,'--test-show-details=direct','--test-options=--list-tests --pattern NonModel'])
run('test-non-model',cabal+['test','ModelMirrors-test',builddir,'--test-show-details=direct','--test-options=--pattern NonModel --num-threads=1'],timeout=300)
bins=list((out/'dist').rglob('ModelMirrors-test')); before={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in bins if p.is_file()}
run('incremental',cabal+['build','ModelMirrors-test',builddir,'-j2'])
after={p:hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest() for p in before}; assert before==after
(out/'incremental-binaries.json').write_text(json.dumps({'before':before,'after':after,'unchanged':before==after},indent=2)+'\n')
# Compile only the actual baseline Core plus API probe using candidate dependency env.
baseline=r/'source/ModelMirros-baseline';baseline.mkdir(exist_ok=True)
with tarfile.open(out/'baseline.tar') as t:t.extractall(baseline)
for name,src in [('baseline',baseline),('fixed',source)]:
 target=out/('red-'+name);target.mkdir(exist_ok=True)
 run('probe-compile-'+name,cabal+['exec',builddir,'--','ghc','-XGHC2024','-i'+str(src/'src'),'-odir',str(target),'-hidir',str(target),str(out/'RedCoreProbe.hs'),'-o',str(target/'probe')])
 run('probe-run-'+name,[str(target/'probe')])
run('probe-run-fixed-repeat',[str(out/'red-fixed/probe')])
assert (logs/'probe-run-fixed.log').read_bytes()==(logs/'probe-run-fixed-repeat.log').read_bytes()
assert 'BASELINE_OVERSIZE_WRITE_CONFIRMED' in (logs/'probe-run-baseline.log').read_text()
assert 'FIXED_ZERO_WRITE_REFUSAL' in (logs/'probe-run-fixed.log').read_text()
print('HASKELL_PHASES_PASSED',flush=True)
