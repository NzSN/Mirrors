import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import tarfile

handoff=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013')
root=Path('/home/jlc/Tools/mirrors-dpm-remediation-20261013')
tools=Path('/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013')
build=handoff/'build'
def digest(path):
    value=hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):value.update(block)
    return value.hexdigest()
selection=json.loads((handoff/'transfer-manifest.json').read_text())
for name,row in selection.items():
    path=handoff/name
    assert path.stat().st_size==row['bytes'] and digest(path)==row['sha256'], name
root.mkdir(parents=True,exist_ok=True)
build.mkdir(parents=True,exist_ok=True)
tools.mkdir(parents=True,exist_ok=True)
def extract(name,destination):
    if destination.exists():raise RuntimeError('existing extraction preserved: '+str(destination))
    destination.mkdir()
    with tarfile.open(handoff/name) as archive:
        for entry in archive.getmembers():
            path=PurePosixPath(entry.name)
            if path.is_absolute() or '..' in path.parts or not (entry.isfile() or entry.isdir() or entry.islnk()):
                raise RuntimeError('unsafe archive member')
            if entry.islnk():
                target=PurePosixPath(entry.linkname)
                if target.is_absolute() or '..' in target.parts:raise RuntimeError('unsafe hard link')
        archive.extractall(destination)
extract('sources.tar',root/'source')
extract('prerequisites.tar',root/'prerequisites')
source=json.loads((root/'source/source-transfer.json').read_text())
count=0
for repository in source['repositories']:
    for name,row in repository['files'].items():
        path=root/'source'/repository['name']/name
        assert path.is_file() and not path.is_symlink() and path.stat().st_size==row['bytes'] and digest(path)==row['sha256'], name
        count+=1
shutil.move(str(root/'prerequisites/node'),tools/'node')
mirrors=root/'source/Mirrors'
(mirrors/'.lake').mkdir()
shutil.copytree('/home/jlc/Repos/Mirrors/.lake/packages',build/'lean-packages',symlinks=True)
(mirrors/'.lake/packages').symlink_to(build/'lean-packages',target_is_directory=True)
(build/'lean-build').mkdir()
(mirrors/'.lake/build').symlink_to(build/'lean-build',target_is_directory=True)
(root/'source/MirrorECMA/node_modules').symlink_to(root/'prerequisites/node_modules',target_is_directory=True)
(build/'logs').mkdir()
record={'schema':'mirrors.dpm-remote-input-verification/v1','status':'verified','files':count,
        'archives':selection,'sourceRoot':str(root/'source'),'buildRoot':str(build),'toolRoot':str(tools),
        'localBuildsRequested':False}
(build/'input-verification.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2),flush=True)
