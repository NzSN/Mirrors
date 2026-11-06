import os,sys,time,ctypes as c
from ctypes import wintypes as w
from pathlib import Path
sys.path.insert(0,r'D:\ModelMirrors\staging\windows-fixes-20261106\Mirrors\tools\deterministic-scheduling')
from dpm_host import _WindowsJob
api=c.WinDLL('kernel32',use_last_error=True)
api.OpenProcess.argtypes=[w.DWORD,w.BOOL,w.DWORD];api.OpenProcess.restype=w.HANDLE
api.QueryFullProcessImageNameW.argtypes=[w.HANDLE,w.DWORD,w.LPWSTR,c.POINTER(w.DWORD)];api.QueryFullProcessImageNameW.restype=w.BOOL
api.CloseHandle.argtypes=[w.HANDLE];api.CloseHandle.restype=w.BOOL
for mode in ['hidden-console','detached']:
 job=_WindowsJob();pipes=[]
 if mode=='hidden-console':
  create=job.api.CreateProcessW
  def hidden(*args):
   changed=list(args);changed[5]=(changed[5]&~0x8)|0x8000000
   return create(*changed)
  job.api.CreateProcessW=hidden
 try:
  with open(os.devnull,'rb') as null:pipes=job.start([sys.executable,'-c','import time;time.sleep(.5)'],Path.cwd(),null)
  time.sleep(.1);names=[]
  for pid in sorted(job.members()):
   handle=api.OpenProcess(0x1000,False,pid)
   if not handle: names.append([pid,'unavailable']);continue
   try:
    size=w.DWORD(32768);buffer=c.create_unicode_buffer(size.value)
    names.append([pid,Path(buffer.value).name if api.QueryFullProcessImageNameW(handle,0,buffer,c.byref(size)) else 'query-failed'])
   finally:api.CloseHandle(handle)
  print(mode,'root',job.pid,'members',names,flush=True)
 finally:
  job.terminate();job.close()
  for p in pipes:p.close()
