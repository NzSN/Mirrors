import pathlib,os,subprocess,json,time,hashlib,re
R=pathlib.Path('/home/jlc/Tools/mirrors-client-fixes-20261015');D=pathlib.Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015/haskell-h2');L=D/'logs';L.mkdir(exist_ok=True)
env=dict(os.environ,PATH=f'{R}/tools/haskell/bin:{R}/tools/haskell/ghc/bin:/usr/bin:/bin',TMPDIR='/tmp/fix-tests',CABAL_DIR=str(R/'tools/haskell/cabal'),LC_ALL='C.UTF-8')
C=[str(R/'tools/haskell/bin/cabal'),'--config-file='+str(R/'tools/haskell/cabal/config')];results=[]
def run(name,args,source,expected=0,timeout=300):
 start=time.time()
 with (L/(name+'.log')).open('wb') as f:
  try:p=subprocess.run(args,cwd=source,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=timeout);code=p.returncode
  except subprocess.TimeoutExpired:code=124
 results.append({'name':name,'command':args,'cwd':str(source),'exit':code,'expectedExit':expected,'seconds':round(time.time()-start,3)});(D/'phases.json').write_text(json.dumps(results,indent=2)+'\n');print(name,code,flush=True)
 if code!=expected:raise SystemExit(code or 1)
def binpath(source,build):return pathlib.Path(subprocess.check_output(C+['list-bin','ModelMirrors-test','--builddir='+str(build)],cwd=source,env=env,text=True).strip())
baseline=R/'source/ModelMirros-h2-baseline';bd=D/'baseline-dist';B='--builddir='+str(bd)
run('baseline-build',C+['build','ModelMirrors-test',B,'-j2'],baseline,timeout=900)
bb=binpath(baseline,bd)
run('baseline-cn-red',[str(bb),'--pattern','/SAN-only rejects CN-only before protocol bytes/','--num-threads=1'],baseline,expected=1)
s=(L/'baseline-cn-red.log').read_text();m=re.search(r'TLS_REJECTION_RECEIPT protocolWrites=(\d+) protocolBytes=(\d+)',s);assert m and int(m[1])>0 and int(m[2])>0,s;assert 'TLS identity accepted and the client sent protocol bytes' in s;assert 'PeerTimeout' not in s
run('baseline-ip-red',[str(bb),'--pattern','/SAN-only accepts correct IP SAN with a different CN/','--num-threads=1'],baseline,expected=1)
assert 'PeerTimeout' not in (L/'baseline-ip-red.log').read_text()
source=R/'source/ModelMirros-h2';build=D/'dist';B='--builddir='+str(build)
run('candidate-build',C+['build','ModelMirrors-test',B,'-j2'],source,timeout=900)
run('candidate-test-list',C+['test','ModelMirrors-test',B,'--test-show-details=direct','--test-options=--list-tests --pattern NonModel'],source)
run('candidate-non-model',C+['test','ModelMirrors-test',B,'--test-show-details=direct','--test-options=--pattern NonModel --num-threads=1'],source)
b=binpath(source,build);before=hashlib.sha256(b.read_bytes()).hexdigest()
run('candidate-incremental',C+['build','ModelMirrors-test',B,'-j2'],source)
after=hashlib.sha256(b.read_bytes()).hexdigest();assert before==after
run('candidate-non-model-repeat',C+['test','ModelMirrors-test',B,'--test-show-details=direct','--test-options=--pattern NonModel --num-threads=1'],source)
text=(L/'candidate-non-model.log').read_text();receipts=[list(map(int,m)) for m in re.findall(r'TLS_REJECTION_RECEIPT protocolWrites=(\d+) protocolBytes=(\d+)',text)];assert receipts and all(x==[0,0] for x in receipts)
(D/'acceptance.json').write_text(json.dumps({'baselineCN':{'protocolWrites':int(m[1]),'protocolBytes':int(m[2]),'expectedTestFailure':True},'candidateTLSRejectionReceipts':receipts,'candidateBinarySha256BeforeIncremental':before,'candidateBinarySha256AfterIncremental':after,'unchanged':before==after,'candidateBinary':str(b),'baselineBinary':str(bb)},indent=2)+'\n')
print('H2_PHASES_PASSED',flush=True)
