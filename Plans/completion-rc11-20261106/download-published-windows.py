"""Download the public GitHub asset independently on the target host and hash it."""
from pathlib import Path
import hashlib,json,urllib.request
from datetime import datetime,timezone
root=Path(r'D:\ModelMirrors\staging\completion-rc11-20261106\published-asset-verification');root.mkdir(exist_ok=False)
name='mirrors-v0.2.0-rc.11-windows-x86_64.zip';url='https://github.com/NzSN/Mirrors/releases/download/v0.2.0-rc.11/'+name
started=datetime.now(timezone.utc).isoformat();digest=hashlib.sha256();size=0
with urllib.request.urlopen(url,timeout=90) as response,(root/(name+'.partial')).open('xb') as output:
 assert response.status==200
 while True:
  chunk=response.read(1024*1024)
  if not chunk:break
  output.write(chunk);digest.update(chunk);size+=len(chunk)
assert size==73727146 and digest.hexdigest()=='f5ec1c9ba3204be04f797acb9086c3a6edd00dce81d7f478c5292b377b7c7df0'
(root/(name+'.partial')).rename(root/name)
value={'status':'downloaded-and-hash-verified','url':url,'bytes':size,'sha256':digest.hexdigest(),'startedAt':started,'completedAt':datetime.now(timezone.utc).isoformat()}
(root/'download.json').write_text(json.dumps(value,indent=2)+'\n');print(json.dumps(value))
