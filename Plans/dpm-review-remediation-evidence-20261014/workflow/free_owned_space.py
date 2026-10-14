import json
from pathlib import Path
import shutil
root=Path('/home/jlc/Tools/mirrors-dpm-remediation-20261013')
destination=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/relocated-prerequisites')
destination.mkdir(exist_ok=False)
rows=[]
for name in ['cpp-prefix','prerequisites']:
    source=root/name
    if source.is_symlink() or not source.is_dir():raise RuntimeError('unexpected owned directory: '+name)
    target=destination/name
    shutil.move(str(source),target)
    source.symlink_to(target,target_is_directory=True)
    rows.append({'ownedPath':str(source),'preservedAt':str(target)})
(destination.parent/'prerequisite-placement.json').write_text(json.dumps(rows,indent=2)+'\n')
print(json.dumps(rows))
