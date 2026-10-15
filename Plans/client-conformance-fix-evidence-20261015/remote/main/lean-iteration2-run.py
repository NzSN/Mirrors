from pathlib import Path
import hashlib,json,os,subprocess,tarfile,time
base=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015')
archive=base/'lean-update-2.tar.gz'
assert hashlib.sha256(archive.read_bytes()).hexdigest()=='58b998c45dbfc36f0265e27800b6958403a0df153d2df4b404fbe1c88d97c700'
root=base/'lean-first'
root.mkdir(exist_ok=True)
with tarfile.open(archive) as t:
 for item in t.getmembers():
  assert not item.name.startswith('/') and '..' not in Path(item.name).parts
 t.extractall(root)
env=os.environ.copy()
env['PATH']='/home/jlc/.elan/toolchains/leanprover--lean4---v4.33.0/bin:/usr/bin:/bin'
env['ELAN_TOOLCHAIN']='leanprover/lean4:v4.33.0'
env['LC_ALL']='C.UTF-8'
env['TMPDIR']='/tmp/mirrors-client-fixes-20261015-tests'
Path(env['TMPDIR']).mkdir(exist_ok=True)
for k in ['MIRROR_BIN','APALACHE_MC','APALACHE_JAR','TLA2TOOLS_JAR']:env.pop(k,None)
results=[]
for label,cmd in [('lean-version',['lean','--version']),('native-tls-build',['lake','build','server-mode-test']),('native-tls-test',['.lake/build/bin/server-mode-test'])]:
 start=time.monotonic();log=base/('lean-iteration2-'+label+'.log')
 with log.open('w') as f:
  try:
   p=subprocess.run(cmd,cwd=root/'MirrorLean/server-mode',env=env,stdout=f,stderr=subprocess.STDOUT,timeout=1200)
   code=p.returncode
  except subprocess.TimeoutExpired:code=124
 row={'label':label,'command':cmd,'exitCode':code,'seconds':round(time.monotonic()-start,3),'log':str(log)}
 results.append(row)
 (base/'lean-iteration2-results.json').write_text(json.dumps(results,indent=2)+'\n')
 print(json.dumps(row),flush=True)
 if code:
  print(log.read_text()[-7000:],flush=True)
  raise SystemExit(code)
