import os,json,zipfile,hashlib
from pathlib import Path,PurePosixPath
root=Path(os.environ['COMPLETION_PYTHON_ROOT']);site=root/'Lib/site-packages';site.mkdir(parents=True)
manifest=json.loads(Path(r'D:\ModelMirrors\staging\qualification-rc7-20261105\20261106-iteration-pure-wheels.json').read_text())
for item in manifest:
 wheel=root/'wheels'/item['name'];assert hashlib.sha256(wheel.read_bytes()).hexdigest()==item['sha256']
 with zipfile.ZipFile(wheel) as archive:
  names=set()
  for row in archive.infolist():
   name=PurePosixPath(row.filename)
   assert not name.is_absolute() and '..' not in name.parts and '\\' not in row.filename and ':' not in row.filename
   assert row.filename not in names;names.add(row.filename)
   if row.is_dir():continue
   assert name.suffix not in ['.pyd','.dll','.exe','.so']
   output=site/name;output.parent.mkdir(parents=True,exist_ok=True)
   with output.open('xb') as stream:stream.write(archive.read(row))
print('Exact retained pure-Python wheel closure installed into task-owned runtime')
