import json
from pathlib import Path
import shutil

old = Path('/home/jlc/Tools/mirrors-dpm-remediation-20261013')
root = Path('/home/jlc/Tools/mirrors-dpm-followup-20261014')
build = Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/followup-20261014')
assert (root/'source').is_dir()
for name in ['Mirrors', 'MirrorCPP', 'MirrorECMA', 'MirrorRust']:
    shutil.copytree(old/'source'/name, root/'source'/name,
                    ignore=shutil.ignore_patterns('.lake', 'node_modules', '.golden-build', 'target'), symlinks=False)
shutil.copytree(old/'prerequisites', root/'prerequisites', symlinks=False)
shutil.copytree(old/'rust-vendor', root/'rust-vendor', symlinks=False)
shutil.copytree(old/'source/Mirrors/.lake/packages', build/'lean-packages', symlinks=False)
shutil.copytree(old/'source/Mirrors/.lake/build', build/'lean-build', symlinks=False)
lake = root/'source/Mirrors/.lake'
lake.mkdir()
(lake/'packages').symlink_to(build/'lean-packages', target_is_directory=True)
output = lake/'build'
output.mkdir()
for entry in (build/'lean-build').iterdir():
    if entry.name in ['bin','lib','ir'] or entry.is_file():
        (output/entry.name).symlink_to(entry, target_is_directory=entry.is_dir())
    elif entry.name == 'share':
        shutil.copytree(entry, output/entry.name)
(root/'source/MirrorECMA/node_modules').symlink_to(root/'prerequisites/node_modules', target_is_directory=True)
record = {'schema':'mirrors.dpm-followup-baseline-copy/v1', 'oldInputsMutated':False,
          'sourceRoot':str(root/'source'), 'buildRoot':str(build), 'ordinaryExt4SourceRoot':True,
          'ordinaryLeanBuildRoot':True, 'immutableDependencyCopies':['prerequisites','rust-vendor'],
          'independentMutableCacheCopies':['lean-packages','lean-build'], 'status':'copied'}
(build/'baseline-copy.json').write_text(json.dumps(record, indent=2)+'\n')
print(json.dumps(record), flush=True)
