import os,sys,time
from pathlib import Path
sys.path.insert(0,r'D:\ModelMirrors\staging\windows-fixes-20261106\Mirrors\tools\deterministic-scheduling')
from dpm_host import _WindowsJob
job=_WindowsJob()
try:
 with open(os.devnull,'rb') as null:pipes=job.start([sys.executable,'-c','import os,time;print(os.getpid());time.sleep(.2)'],Path.cwd(),null)
 print('ROOT',job.pid,flush=True)
 for i in range(40):
  code=job.poll();print('SAMPLE',i,'exit',code,'active',job.active(),'members',sorted(job.members()),flush=True)
  time.sleep(.01)
 print('STDOUT',pipes[0].read(),flush=True)
finally:
 job.terminate();job.close()
 for p in pipes:p.close()
