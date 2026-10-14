import hashlib
import json
from pathlib import Path
import shutil

build=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build')
source=Path('/home/jlc/Tools/mirrors-dpm-remediation-20261013/source/Mirrors/.golden-build/mirrorrust-target')
target=build/'non-model-rust-target'
assert (build/'local-gates-qualified-phase.exit').read_text().strip()=='0'
assert source.is_dir() and not source.is_symlink() and not target.exists()
def inventory(root):
    rows={}
    for path in root.rglob('*'):
        name=str(path.relative_to(root))
        if path.is_symlink():rows[name]={'symlink':str(path.readlink())}
        elif path.is_file():
            value=hashlib.sha256()
            with path.open('rb') as stream:
                for block in iter(lambda:stream.read(1024*1024),b''):value.update(block)
            rows[name]={'sha256':value.hexdigest(),'bytes':path.stat().st_size}
    return rows
before=inventory(source)
shutil.copytree(source,target,symlinks=True)
assert before==inventory(target),'generated target copy differs'
shutil.rmtree(source)
source.symlink_to(target,target_is_directory=True)
record={'schema':'mirrors.dpm-owned-output-relocation/v1','originalPath':str(source),
        'retainedAt':str(target),'files':before,'contentVerifiedBeforeSourceRemoval':True}
(build/'non-model-rust-target-placement.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps({'files':len(before),'retainedAt':str(target),'sourceReference':'symlink'}))
