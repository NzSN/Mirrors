from pathlib import Path
import hashlib,json,zipfile
root=Path(__file__).parent
source=root/'candidate-v0.2.0-rc.1'
outputs=[root/'mirrors-v0.2.0-rc.1-windows-x86_64.zip',root/'mirrors-v0.2.0-rc.1-windows-x86_64-repeat.zip']
for output in outputs:
 with zipfile.ZipFile(output,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
  for path in sorted(source.rglob('*')):
   if not path.is_file():continue
   assert not path.is_symlink()
   entry=zipfile.ZipInfo('mirrors-v0.2.0-rc.1-windows-x86_64/'+path.relative_to(source).as_posix(),date_time=(2026,10,29,0,0,0))
   entry.compress_type=zipfile.ZIP_DEFLATED
   archive.writestr(entry,path.read_bytes(),compresslevel=9)
values=[hashlib.sha256(path.read_bytes()).hexdigest() for path in outputs]
assert values[0]==values[1]
(root/'windows-candidate-archive.json').write_text(json.dumps({'schema':'mirrors.candidate-archive/v1','archive':outputs[0].name,'sha256':values[0],'bytes':outputs[0].stat().st_size,'repeatedPackagingIdentical':True,'scope':'identical packaging of selected binaries; no reproducible-compilation claim'},indent=2)+'\n',encoding='utf-8')
print('WINDOWS CANDIDATE PACKAGE:',values[0])
