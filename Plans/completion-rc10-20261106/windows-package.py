"""Package only the exact source-built native rc.10 bytes after the full gate."""
import hashlib,json,os,shutil,subprocess,zipfile
from pathlib import Path
STAGE=Path(r'D:\ModelMirrors\staging\completion-rc10-20261106');SOURCE=STAGE/'source'
NAME='mirrors-v0.2.0-rc.10-windows-x86_64';TAG='v0.2.0-rc.10';REV='a53fa332f7c8e150e2559ae31ea32b47c23ecf4b'
GIT=r'C:\Program Files\Git\cmd\git.exe'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def save(path,value):
 with path.open('x',encoding='utf-8',newline='\n') as stream:stream.write(json.dumps(value,indent=2)+'\n')
def main():
 verification=json.loads((STAGE/'source-verification.json').read_text())
 assert verification['status']=='passed' and verification['commit']==REV and not verification['sourceOverlay']
 full=json.loads((STAGE/'rc10-clean-full-test.json').read_text(encoding='utf-8-sig'))
 log=STAGE/'rc10-clean-full-test.log';assert full['exitCode']==0 and sha(log)==full['sha256']
 assert b'ALL LAKE TESTS GREEN' in log.read_bytes() and b'TASK JOB CLEANUP active=0' in log.read_bytes()
 assert not subprocess.check_output([GIT,'-C',str(SOURCE),'status','--porcelain'],text=True).strip()
 package=STAGE/NAME;binary=package/'bin';binary.mkdir(parents=True,exist_ok=False)
 shutil.copyfile(SOURCE/'.lake/build/bin/mirror.exe',binary/'ModelMirrors.exe')
 shutil.copyfile(SOURCE/'.lake/build/bin/model_interface_gen.exe',binary/'model_interface_gen.exe')
 sources={
 'libcrypto-3-x64.dll':(r'D:\Programs\msys2\ucrt64\bin\libcrypto-3-x64.dll','7909ab97fd1226890af8448a43cb9acd0e9758bfd595298c46c125211c3e61c7'),
 'libssl-3-x64.dll':(r'D:\Programs\msys2\ucrt64\bin\libssl-3-x64.dll','85377317f9fbc5a0b8264ba25c87670dbce2fe0988d186eb98d107460d8b416c'),
 'zlib1.dll':(r'D:\ModelMirrors\releases\20261029-completion-7e9a27d\candidate-v0.2.0-rc.1\bin\zlib1.dll','93e9243a44c29200eeacaf9658efe2558581770e4b11ca4b500e18e424a6e3b5')}
 for name,(path,wanted) in sources.items():
  assert sha(Path(path))==wanted,(name,'dependency changed');shutil.copyfile(path,binary/name)
 files={path.relative_to(package).as_posix():{'bytes':path.stat().st_size,'sha256':sha(path)} for path in sorted(binary.iterdir())}
 assert files['bin/ModelMirrors.exe']['sha256']==verification['sourceBuiltMirrorSha256']
 assert files['bin/model_interface_gen.exe']['sha256']==verification['sourceBuiltCompilerSha256']
 record={'schema':'mirrors.rc10.windows-package/v1','sourceCommit':REV,'sourceTree':verification['tree'],'tag':TAG,
         'version':'0.2.0-rc.10','sourceOverlay':False,'sourceGitBlobsVerified':verification['gitBlobsVerified'],
         'fullLakeTest':True,'fullLakeTestLogSha256':full['sha256'],'files':files,
         'dllSources':{key:{'path':path,'sha256':wanted} for key,(path,wanted) in sources.items()},
         'published':False,'deployed':False,'reproducibleCompilation':False,'releaseAdmission':False}
 save(package/'BUILD.json',record)
 (package/'README.txt').write_text('Mirrors '+TAG+' native Windows x64\nSource: '+REV+'\nFull native test driver and declared model tiers pass on Windows 10 build 19045.\nSee BUILD.json for exact bytes and scope. DPM is distributed separately.\n',encoding='utf-8',newline='\n')
 paths=sorted((path for path in package.rglob('*') if path.is_file()),key=lambda path:path.relative_to(package).as_posix())
 for suffix in ['', '-repeat']:
  output=STAGE/(NAME+suffix+'.zip')
  with zipfile.ZipFile(output,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
   for path in paths:
    item=zipfile.ZipInfo(NAME+'/'+path.relative_to(package).as_posix(),date_time=(2026,11,6,0,0,0));item.compress_type=zipfile.ZIP_DEFLATED;item.external_attr=0o644<<16
    archive.writestr(item,path.read_bytes(),compresslevel=9)
 assert sha(STAGE/(NAME+'.zip'))==sha(STAGE/(NAME+'-repeat.zip'))
 environment=dict(os.environ);environment['PATH']=str(binary)+r';C:\Windows\System32';environment.pop('PYTHONPATH',None)
 version=subprocess.run([str(binary/'ModelMirrors.exe'),'--version'],capture_output=True,text=True,env=environment,timeout=30)
 assert version.returncode==0 and version.stdout.strip()==TAG and not version.stderr
 protocol=subprocess.run([str(binary/'ModelMirrors.exe')],input=b'{"proto_step":"report_state","state":{}}\n',capture_output=True,env=environment,timeout=30)
 assert protocol.returncode==0 and json.loads(protocol.stdout)['proto_step']=='protocol_error'
 from importlib.util import spec_from_file_location,module_from_spec
 spec=spec_from_file_location('windows_pe',STAGE/'windows-pe.py');module=module_from_spec(spec);spec.loader.exec_module(module);module.main()
 save(STAGE/'windows-package-result.json',{'status':'verified-exact-source-native-package','package':record,'archive':{'name':NAME+'.zip','sha256':sha(STAGE/(NAME+'.zip')),'bytes':(STAGE/(NAME+'.zip')).stat().st_size},'repeatIdentical':True,'restrictedPathSmoke':True,'peClosurePassed':True})
 print('RC10 WINDOWS PACKAGE VERIFIED',sha(STAGE/(NAME+'.zip')))
if __name__=='__main__':main()
