"""Move only the failed attempt's exact known staging files out of production bin."""
from pathlib import Path
import hashlib,json
stage=Path(r'D:\ModelMirrors\staging\completion-rc11-20261106');root=stage/'failed-deployment-staging';root.mkdir(exist_ok=False)
expected={'.ModelMirrors-rc11-staged.exe':'5bfb5248a7ab74bfbe6c86361146daa20b0e5e864699c820269279747ef81fd4','.ModelMirrors-rc11-rollback.exe':'8173ddea65f78a88b1a303f8a233dd7113b28e7dc8aefd8916a5add25a3687cc'}
rows=[]
for name,wanted in expected.items():
 source=Path(r'D:\ModelMirrors\bin')/name;assert source.is_file() and not source.is_symlink();assert hashlib.sha256(source.read_bytes()).hexdigest()==wanted
 target=root/name;assert not target.exists();source.rename(target);assert hashlib.sha256(target.read_bytes()).hexdigest()==wanted
 rows.append({'name':name,'sha256':wanted,'retainedAt':str(target)})
active=Path(r'D:\ModelMirrors\bin\ModelMirrors.exe');assert hashlib.sha256(active.read_bytes()).hexdigest()=='5bfb5248a7ab74bfbe6c86361146daa20b0e5e864699c820269279747ef81fd4'
value={'status':'failed-staging-retained-outside-production-bin','files':rows,'activeBinaryUnchanged':True}
(stage/'failed-staging-retention.json').write_text(json.dumps(value,indent=2)+'\n');print(json.dumps(value))
