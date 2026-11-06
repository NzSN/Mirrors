import sys,tempfile,json,os
from pathlib import Path
sys.path.insert(0,r'D:\ModelMirrors\staging\windows-fixes-20261106\Mirrors\tools\evidence')
import winfs
rows=[]
original=winfs.n.NtCreateFile
for sharing in [1,3,7]:
 with tempfile.TemporaryDirectory(dir=r'D:\ModelMirrors\staging\windows-fixes-20261106') as directory:
  root=Path(directory)/'private';winfs.create_directory(root)
  def opened(*args):
   values=list(args)
   if values[6]==1:values[6]=sharing
   return original(*values)
  winfs.n.NtCreateFile=opened
  try:
   with winfs.pin_directory(root):
    try:winfs.atomic_write(root/'value',b'value');result='success'
    except OSError as error:result=str(error)
   rows.append({'sharing':sharing,'atomicWrite':result})
  finally:winfs.n.NtCreateFile=original
print(json.dumps(rows))
