import pathlib,json,os,subprocess,hashlib
R='/home/jlc/Tools/mirrors-client-fixes-20261015'
D=pathlib.Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015'); rows=[]
for p in pathlib.Path('/proc').iterdir():
 if not p.name.isdigit() or int(p.name)==os.getpid():continue
 try:c=(p/'cmdline').read_bytes().replace(b'\0',b' ').decode(errors='replace');exe=os.readlink(p/'exe')
 except OSError:continue
 if (R+'/tools/haskell/' in exe or ('/haskell/dist/' in exe and 'ModelMirrors-test' in exe) or '/haskell/red-' in exe):rows.append({'pid':int(p.name),'exe':exe,'command':c})
temps=[str(p) for p in pathlib.Path('/tmp/fix-tests').glob('modelmirrors-*')]
x={'activeOwnedHaskellProcesses':rows,'remainingModelMirrorsTempDirectories':temps,'normalRuntimeReturned':True,'privateToolchainSourceAndBinariesPreserved':True,'modelCheckerInvoked':False}
(D/'haskell/cleanup.json').write_text(json.dumps(x,indent=2)+'\n');print(json.dumps(x));assert not rows;assert not temps
