"""Retain exact deployed/rollback/public archive bytes outside task staging."""
from pathlib import Path
import hashlib,json,shutil
stage=Path(r'D:\ModelMirrors\staging\completion-rc11-20261106');root=Path(r'D:\ModelMirrors\releases\20261106-v0.2.0-rc.11-19c31bf');root.mkdir(exist_ok=False)
inputs=[(stage/'rollback/ModelMirrors.exe','previous-ModelMirrors.exe','8173ddea65f78a88b1a303f8a233dd7113b28e7dc8aefd8916a5add25a3687cc'),(stage/'mirrors-v0.2.0-rc.11-windows-x86_64.zip','mirrors-v0.2.0-rc.11-windows-x86_64.zip','f5ec1c9ba3204be04f797acb9086c3a6edd00dce81d7f478c5292b377b7c7df0'),(Path(r'D:\ModelMirrors\bin\ModelMirrors.exe'),'deployed-ModelMirrors.exe','5bfb5248a7ab74bfbe6c86361146daa20b0e5e864699c820269279747ef81fd4')]
rows=[]
for source,name,wanted in inputs:
 assert hashlib.sha256(source.read_bytes()).hexdigest()==wanted
 target=root/name;shutil.copyfile(source,target);assert hashlib.sha256(target.read_bytes()).hexdigest()==wanted
 rows.append({'path':str(target),'bytes':target.stat().st_size,'sha256':wanted})
for name in ['deployment-prepared.json','deployment-result-v2.json','reboot-request.json']:
 shutil.copyfile(stage/name,root/name)
value={'status':'release-and-rollback-retained','sourceCommit':'19c31bf09b58e27c2942ca123a2017c30b638216','files':rows,'credentialsIncluded':False,'priorCopiesPreserved':True}
(root/'retention.json').write_text(json.dumps(value,indent=2)+'\n');print(json.dumps(value))
