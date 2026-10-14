import json
from pathlib import Path
import shutil
source=Path('/home/jlc/Tools/mirrors-dpm-remediation-20261013/source/Mirrors')
output=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/lean-build')
directory=source/'.lake/build'
if not directory.is_symlink() or directory.resolve()!=output:
    raise RuntimeError('expected owned build-output link missing')
directory.unlink();directory.mkdir()
for name in ['bin','ir','lib']:
    (directory/name).symlink_to(output/name,target_is_directory=True)
for path in output.iterdir():
    if path.is_file():(directory/path.name).symlink_to(path)
shutil.copytree(output/'share',directory/'share')
record={'schema':'mirrors.dpm-remote-build-layout/v1','sourceBuildRoot':str(directory),
        'ordinaryRoot':True,'largeCompiledOutputs':str(output),'compiledSubdirectories':['bin','ir','lib']}
(output.parent/'build-layout.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record))
