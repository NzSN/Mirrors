import sys, tempfile, json, os
from pathlib import Path
sys.path.insert(0,r'D:\ModelMirrors\staging\windows-fixes-20261106')
import winfs
result=[]
with tempfile.TemporaryDirectory(dir=r'D:\ModelMirrors\staging\windows-fixes-20261106') as directory:
 root=Path(directory)/'private';winfs.create_directory(root);winfs.check_private(root);result.append('private-directory')
 winfs.write_exclusive(root/'temporary',b'hello');winfs.check_private(root/'temporary');result.append('private-file')
 assert winfs.read_regular(root/'temporary')[0]==b'hello';result.append('read')
 fd=winfs.open_directory(root)
 try:assert list(winfs.listdir(fd))==['temporary']
 finally:os.close(fd)
 result.append('directory-enumeration')
 winfs.fsync_directory(root);result.append('directory-flush')
 winfs.publish_exclusive(root,'temporary','committed');assert not (root/'temporary').exists();assert winfs.read_regular(root/'committed')[0]==b'hello';result.append('exclusive-publication')
 try:winfs.write_exclusive(root/'committed',b'overwrite')
 except FileExistsError:result.append('overwrite-refused')
 else:raise AssertionError('overwrite')
print(json.dumps(result))
