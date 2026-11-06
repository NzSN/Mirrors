import ctypes as c, json, os, tempfile, msvcrt
from ctypes import wintypes as w
from pathlib import Path
api=c.WinDLL('kernel32',use_last_error=True)
api.CreateFileW.argtypes=[w.LPCWSTR,w.DWORD,w.DWORD,c.c_void_p,w.DWORD,w.DWORD,w.HANDLE];api.CreateFileW.restype=w.HANDLE
api.FlushFileBuffers.argtypes=[w.HANDLE];api.FlushFileBuffers.restype=w.BOOL
api.CloseHandle.argtypes=[w.HANDLE];api.CloseHandle.restype=w.BOOL
rows=[]
with tempfile.TemporaryDirectory(dir=r'D:\ModelMirrors\staging\windows-fixes-20261106') as directory:
 for access in [0x80|0x100000,0x80000000,0xc0000000]:
  handle=api.CreateFileW(directory,access,7,None,3,0x02000000|0x00200000,None)
  row={'access':access,'opened':handle != c.c_void_p(-1).value}
  if row['opened']:
   try:
    row['flushed']=bool(api.FlushFileBuffers(handle));row['flushError']=c.get_last_error()
    fd=msvcrt.open_osfhandle(handle,os.O_RDONLY|os.O_BINARY);handle=None
    try:
     try: row['fstatMode']=os.fstat(fd).st_mode
     except OSError as error:row['fstatError']=str(error)
     try:os.fsync(fd);row['fsync']=True
     except OSError as error:row['fsyncError']=str(error)
    finally:os.close(fd)
   finally:
    if handle:api.CloseHandle(handle)
  else:row['openError']=c.get_last_error()
  rows.append(row)
print(json.dumps(rows))
