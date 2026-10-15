import json,shutil
from pathlib import Path
root=Path('/home/jlc/Tools/mirrors-client-fixes-20261015')
build=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015')
old=Path('/home/jlc/Tools/mirrors-dpm-remediation-20261013/source/Mirrors/.lake')
source=root/'source/Mirrors'
shutil.copytree(old/'packages',build/'lean-packages',symlinks=False)
shutil.copytree(old/'build',build/'lean-build',symlinks=False)
lake=source/'.lake';lake.mkdir()
(lake/'packages').symlink_to(build/'lean-packages',target_is_directory=True)
ordinary=lake/'build';ordinary.mkdir()
for entry in (build/'lean-build').iterdir():
    if entry.name in ['bin','ir','lib'] or entry.is_file():
        (ordinary/entry.name).symlink_to(entry,target_is_directory=entry.is_dir())
    elif entry.name=='share':shutil.copytree(entry,ordinary/entry.name)
record={'status':'copied','oldCachesWritten':False,'sourceRoot':str(source),'buildRoot':str(build/'lean-build'),
        'ordinarySourceBuildRoot':str(ordinary),'largeOutputs':['bin','ir','lib'],'compilerInputsMustRebuildNormally':True}
(build/'mirror-cache-copy.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record),flush=True)
