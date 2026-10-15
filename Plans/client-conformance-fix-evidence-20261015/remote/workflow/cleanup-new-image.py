import json,os,signal,subprocess,time
from pathlib import Path
B=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015');R=Path('/home/jlc/Tools/mirrors-client-fixes-20261015');image=B/'fix-workspace.ext4'
def run(*args):
 p=subprocess.run(args,text=True,capture_output=True)
 return {'args':list(args),'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
def cmd(pid):
 try:return Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0',b' ').decode().strip()
 except FileNotFoundError:return None
assert os.geteuid()==0
assert cmd(814)==f'bash {B}/setup-mount.sh',cmd(814)
assert cmd(1029)=='sleep 14400',cmd(1029)
assert Path('/proc/1029/status').read_text().split('PPid:\t')[1].splitlines()[0]=='814'
# Inspect command lines and resolved cwd/exe, excluding this short-lived cleanup command.
owned=[]
for p in Path('/proc').iterdir():
 if not p.name.isdigit() or int(p.name) in {os.getpid(),os.getppid(),814,1029}:continue
 try:
  c=cmd(int(p.name)) or '';links=[]
  for k in ['cwd','exe']:
   try:links.append(str((p/k).resolve()))
   except OSError:pass
  if str(R) in c or str(B) in c or any(x.startswith(str(R)+'/') for x in links):owned.append({'pid':int(p.name),'command':c,'links':links})
 except (OSError,PermissionError):pass
assert not owned,owned
record={'schema':'client-fixes-cleanup/v1','ownedProcessesBeforeExceptKeeper':owned,'keeperBefore':{'pid':814,'command':cmd(814),'sleepPid':1029},'image':str(image),'imageBytes':image.stat().st_size,'sourceRoot':str(R),'oldImagesTouched':False,'commands':[]}
# Confirm exact new loop backing file; do not unmount any previous qualification filesystem.
q=run('findmnt','-rn','-o','SOURCE','--mountpoint',str(R));assert q['exit']==0,q
device=q['stdout'].strip();back=run('losetup','-n','-O','BACK-FILE',device);assert back['stdout'].strip()==str(image),back
record['loopDeviceBefore']=device
for args in [('sync','-f',str(R)),('umount','/tmp/fix-tests'),('umount',str(R)),('sync','-f',str(image))]:
 row=run(*args);record['commands'].append(row);assert row['exit']==0,row
# Only verified exact owned keeper and its sole sleep child are terminated.
os.kill(1029,signal.SIGTERM)
for _ in range(30):
 if cmd(814) is None:break
 time.sleep(.1)
if cmd(814) is not None:
 assert cmd(814)==f'bash {B}/setup-mount.sh';os.kill(814,signal.SIGTERM)
 time.sleep(.2)
record['keeperAfter']=cmd(814);record['sleepAfter']=cmd(1029)
record['mountAfter']=run('findmnt','-rn','--mountpoint',str(R))
record['testBindAfter']=run('findmnt','-rn','--mountpoint','/tmp/fix-tests')
record['loopAfter']=run('losetup','-j',str(image))
record['preservedImage']=image.exists();record['recoveryWorkflow']=str(B/'recover-new-image.sh')
assert record['keeperAfter'] is None and record['sleepAfter'] is None
assert record['mountAfter']['exit']==1 and record['testBindAfter']['exit']==1
assert not record['loopAfter']['stdout'].strip()
record['status']='closed-cleanly-image-preserved'
(B/'cleanup-receipt.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record),flush=True)
