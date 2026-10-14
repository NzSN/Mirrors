import hashlib
import json
from pathlib import Path
import shutil
import sys
import tarfile

build=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/followup-20261014')
source=Path('/home/jlc/Tools/mirrors-dpm-followup-20261014/source')
archive=build/'workflow'/sys.argv[1]
stage=build/(archive.stem+'-extracted')
stage.mkdir()
with tarfile.open(archive) as bundle:
    for member in bundle.getmembers():
        assert not Path(member.name).is_absolute() and '..' not in Path(member.name).parts
        assert member.isfile() or member.isdir()
    bundle.extractall(stage)
rows=json.loads((stage/'selection.json').read_text())
for row in rows:
    local=stage/row['repository']/row['path']
    destination=source/row['repository']/row['path']
    assert hashlib.sha256(local.read_bytes()).hexdigest()==row['sha256']
    destination.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(local,destination)
    assert hashlib.sha256(destination.read_bytes()).hexdigest()==row['sha256']
(build/(archive.stem+'-verification.json')).write_text(json.dumps({'status':'verified','files':rows},indent=2)+'\n')
print('VERIFIED_PATCH_FILES',len(rows),flush=True)
