"""Task-owned Windows oracle with an inherited, kill-on-close Job boundary."""
from pathlib import Path
from datetime import datetime, timezone
import base64,hashlib,importlib.util,json,os,subprocess,time,zipfile

stage=Path(__file__).resolve().parent
selection=json.loads((stage/'matrix-selection.json').read_text(encoding='utf-8'))
source=stage/'source'
run=stage/selection['attempt'];run.mkdir(exist_ok=False)

def digest(path):
 h=hashlib.sha256()
 with path.open('rb') as stream:
  while chunk:=stream.read(1024*1024):h.update(chunk)
 return h.hexdigest()

def stamp():return datetime.now(timezone.utc).isoformat(timespec='milliseconds').replace('+00:00','Z')
def save(path,value):
 temporary=path.with_suffix('.new')
 temporary.write_text(json.dumps(value,sort_keys=True,indent=2)+'\n',encoding='utf-8',newline='\n')
 temporary.replace(path)

def powershell(script):
 command=base64.b64encode(('$ProgressPreference="SilentlyContinue";'+script).encode('utf-16-le')).decode()
 result=subprocess.run(['C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe','-NoProfile','-NonInteractive','-EncodedCommand',command],capture_output=True,timeout=15)
 if result.returncode:raise RuntimeError('owned oracle observation failed')
 return json.loads(result.stdout.decode('utf-8-sig'))

manifest_path=stage/'matrix-source-manifest.json'
assert digest(manifest_path)==selection['sourceManifestSha256']
manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
def verify_sources():
 for row in manifest['files']:
  path=source/row['path']
  assert path.is_file() and not path.is_symlink() and path.resolve().is_relative_to(source.resolve())
  assert path.stat().st_size==row['bytes'] and digest(path)==row['sha256'],'source changed: '+row['path']
verify_sources()
for path,expected in selection['runtimeFiles'].items():assert digest(Path(path))==expected,path
binary=stage/'candidate-v0.2.0-rc.1/bin/ModelMirrors.exe'
assert digest(binary)==selection['binarySha256']
job_path=source/'tools/tla-differential/windows_job.py'
assert digest(job_path)==selection['windowsJobSha256']
spec=importlib.util.spec_from_file_location('qualified_windows_job',job_path)
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
fixtures=stage/'matrix-interop';fixtures.mkdir(exist_ok=True)
for name,expected in selection['interopFiles'].items():
 public=stage/name;assert digest(public)==expected
 target=fixtures/name
 if target.exists():assert digest(target)==expected
 else:target.write_bytes(public.read_bytes())
assert str(fixtures)==selection['interopRoot']
java='D:/Programs/jdk-25.0.4+7/bin/java.exe'
jar='D:/Programs/apalache/lib/apalache.jar'
for name,argv,expected in [('java',[java,'-version'],'25.0.4+7-LTS')]:
 result=subprocess.run(argv,capture_output=True,timeout=30)
 (run/(name+'-version.stdout')).write_bytes(result.stdout);(run/(name+'-version.stderr')).write_bytes(result.stderr)
 assert result.returncode==0 and expected.encode() in result.stdout+result.stderr
with zipfile.ZipFile(jar) as archive:
 metadata=archive.read('META-INF/MANIFEST.MF')
 assert len(metadata)<=8192 and b'Implementation-Version: 0.62.2' in metadata
 (run/'apalache-manifest.txt').write_bytes(metadata)
pki=stage/'matrix-pki'
assert digest(pki/'server.crt')==selection['serverCertificateFileSha256']
openssl='D:/Programs/msys2/ucrt64/bin/openssl.exe'
leaf=subprocess.check_output([openssl,'x509','-in',str(pki/'server.crt'),'-outform','DER'],timeout=10)
assert hashlib.sha256(leaf).hexdigest()==selection['serverPin']
assert not powershell("@(Get-NetTCPConnection -LocalPort 19131 -State Listen -ErrorAction SilentlyContinue).Count|ConvertTo-Json")
env=dict(os.environ)
for key in ['JAVA_TOOL_OPTIONS','JDK_JAVA_OPTIONS','_JAVA_OPTIONS','JAVA_OPTS','JVM_OPTS','SBT_OPTS','CLASSPATH']:
 env.pop(key,None)
env.update(PATH='D:\\Programs\\jdk-25.0.4+7\\bin;D:\\Programs\\msys2\\ucrt64\\bin;C:\\Windows\\System32',
 JAVA_HOME='D:\\Programs\\jdk-25.0.4+7',APALACHE_MC='D:\\ModelMirrors\\bin\\apalache-mc.exe',
 LEAN_NUM_THREADS='2',TEMP=str(run),TMP=str(run))
job=module.WindowsJob();process=None;observed_java={};failure=None;ready=False
runtime_manifest={'files':selection['runtimeFiles'],'selectedApalacheArchiveSha256':selection['apalacheArchiveSha256'],
 'apalacheArchiveBytesReobserved':False,'javaArchiveBytesReobserved':True,
 'scope':'actual executable JAR, Java executable and launcher hashes; Apalache archive pin is selection metadata'}
save(run/'runtime-manifest.json',runtime_manifest)
try:
 with (run/'server.stdout.log').open('xb') as stdout,(run/'server.stderr.log').open('xb') as stderr:
  process=subprocess.Popen([str(binary),'--server','19131','--tls','--cert',str(pki/'server.crt'),'--key',str(pki/'server.key'),'--ca',str(pki/'ca.crt'),'--bind','127.0.0.1','--jobs','4'],cwd=binary.parent,env=env,stdin=subprocess.DEVNULL,stdout=stdout,stderr=stderr,close_fds=True,creationflags=0x4|subprocess.CREATE_NEW_PROCESS_GROUP)
  try:
   job.assign_and_resume(process)
  except BaseException:
   process.kill();process.wait(timeout=5);raise
  deadline=time.monotonic()+7200
  while process.poll() is None and time.monotonic()<deadline:
   script="""$all=@(Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId,Name,ExecutablePath,CreationDate);$owned=@{};$owned[%d]=$true;for($i=0;$i -lt 8;$i++){foreach($p in $all){if($owned.ContainsKey([int]$p.ParentProcessId)){$owned[[int]$p.ProcessId]=$true}}};$p=$all|Where-Object {$_.ProcessId -eq %d};[ordered]@{serverPath=$p.ExecutablePath;created=$p.CreationDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ');listener=@(Get-NetTCPConnection -LocalPort 19131 -State Listen -ErrorAction SilentlyContinue|Select-Object -ExpandProperty OwningProcess);java=@($all|Where-Object {$_.Name -eq 'java.exe' -and $_.ExecutablePath -and $owned.ContainsKey([int]$_.ProcessId)}|ForEach-Object {[ordered]@{pid=$_.ProcessId;path=$_.ExecutablePath;created=$_.CreationDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')}})}|ConvertTo-Json -Depth 5 -Compress"""%(process.pid,process.pid)
   observed=powershell(script)
   assert Path(observed['serverPath']).resolve()==binary.resolve()
   for row in observed['java']:
    row['sha256']=digest(Path(row['path']))
    assert row['sha256']==selection['javaExecutableSha256'],'unselected Java executed'
    observed_java[str(row['pid'])+':'+row['created']]=row
   for name,expected in selection['interopFiles'].items():assert digest(fixtures/name)==expected
   if process.pid in observed['listener']:
    observation={'schema':'mirrors.windows-deployment-observation/v1','endpoint':{'host':'127.0.0.1','port':19131},
     'deploymentMode':'owned-native-console','processId':process.pid,'binarySha256':selection['binarySha256'],
     'sourceBaseRevision':manifest['base'],'sourceTreeSha256':manifest['treeSha256'],
     'sourceManifestSha256':selection['sourceManifestSha256'],'runtimeManifestSha256':digest(run/'runtime-manifest.json'),
     'observedAt':stamp(),'processCreatedAt':observed['created'],'mtls':{'serverLeafSha256':selection['serverPin']},
     'runtime':{'apalacheVersion':'0.62.2','apalacheArchiveSha256':selection['apalacheArchiveSha256'],
      'apalacheJarSha256':selection['apalacheJarSha256'],'javaVersion':'25.0.4+7-LTS',
      'javaArchiveSha256':selection['javaArchiveSha256'],'javaExecutableSha256':selection['javaExecutableSha256']},
     'interopFixtures':{'root':str(fixtures),'files':selection['interopFiles']},'runtimeArchiveVerification':runtime_manifest['scope']}
    save(run/'observation-latest.json',observation)
    if not ready:print('OWNED MATRIX ORACLE READY',process.pid,flush=True);ready=True
   if not ready and time.monotonic()>deadline-7170:raise RuntimeError('oracle readiness expired')
   if (run/'stop-request').exists():break
   if sum((run/name).stat().st_size for name in ['server.stdout.log','server.stderr.log'])>4*1024*1024:raise RuntimeError('oracle log budget exceeded')
   save(run/'observed-java.json',list(observed_java.values()))
   time.sleep(2)
  if process.poll() is not None:raise RuntimeError('oracle exited unexpectedly')
except BaseException as error:
 failure=type(error).__name__+': '+str(error)
 raise
finally:
 try:
  if process is not None:job.terminate()
 finally:
  job.close()
 verify_sources()
 for path,expected in selection['runtimeFiles'].items():assert digest(Path(path))==expected,path
 save(run/'lifecycle.json',{'schema':'mirrors.owned-matrix-oracle-lifecycle/v1','jobCleanup':'confirmed','sourceAndRuntimeUnchanged':True,'failure':failure,'observedJava':list(observed_java.values()),'endedAt':stamp()})
 print('OWNED MATRIX ORACLE STOPPED',flush=True)
