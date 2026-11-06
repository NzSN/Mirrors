import sys,tempfile,os,json,ctypes as c
from pathlib import Path
sys.path.insert(0,r'D:\ModelMirrors\staging\windows-fixes-20261106\Mirrors\tools\evidence')
import winfs as f
rows=[]
with tempfile.TemporaryDirectory(dir=r'D:\ModelMirrors\staging\windows-fixes-20261106') as directory:
 root=Path(directory);parent=f.open_directory(root,write=True)
 try:
  for method in ['native-relative','native-absolute','win32-relative','win32-absolute','os-after-close']:
   source=method+'.tmp';target=method+'.json';fd=f.open_at(parent,source,create=True,exclusive=True,write=True,delete=True,private=True)
   os.write(fd,b'json');os.fsync(fd)
   try:
    if method=='os-after-close':
     os.close(fd);fd=None;os.rename(root/source,root/target)
    else:
     name=str(root/target) if method.endswith('absolute') else target
     if method=='native-absolute':name='\\??\\'+name
     class Rename(c.Structure):
      _fields_=[('replace',f.w.BOOLEAN),('root',f.w.HANDLE),('length',f.w.DWORD),('name',f.w.WCHAR*len(name))]
     value=Rename();value.replace=True;value.root=None if method.endswith('absolute') else f._handle(parent);value.length=len(name.encode('utf-16-le'));value.name=name
     if method.startswith('native'):
      io=f.IoStatus();f._ntcheck(f.n.NtSetInformationFile(f._handle(fd),c.byref(io),c.byref(value),c.sizeof(value),10))
     else:f._check(f.k.SetFileInformationByHandle(f._handle(fd),3,c.byref(value),c.sizeof(value)))
    rows.append([method,'success'])
   except OSError as error:rows.append([method,str(error)])
   finally:
    if fd is not None:os.close(fd)
 finally:os.close(parent)
print(json.dumps(rows))
