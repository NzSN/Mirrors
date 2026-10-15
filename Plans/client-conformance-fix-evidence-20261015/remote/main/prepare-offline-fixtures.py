import hashlib
import json
from pathlib import Path
import tarfile

handoff=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013')
build=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015')
source=Path('/home/jlc/Tools/mirrors-client-fixes-20261015/source/Mirrors')
pins=json.loads((source/'tools/tla-differential/toolchain.lock.json').read_text())['tools']
def digest(path):
    result=hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):result.update(block)
    return result.hexdigest()
cache=build/'offline-fixture-toolchain'
cache.mkdir(exist_ok=False)
(cache/'downloads').mkdir()
rows={}
for tool in ['apalache','sany']:
    pin=pins[tool];name=Path(pin['path']).name
    artifact=handoff/name
    actual=digest(artifact)
    assert actual==pin['sha256'],(name,actual)
    (cache/pin['path']).symlink_to(artifact)
    rows[name]={'sha256':actual,'bytes':artifact.stat().st_size,'purpose':'offline acquisition fixture; no Java/modelchecker invocation'}
with tarfile.open(handoff/'apalache-0.61.0.tgz') as archive:
    for member in archive.getmembers():
        path=Path(member.name)
        if path.is_absolute() or '..' in path.parts or not (member.isfile() or member.isdir()):
            raise RuntimeError('unexpected archive member '+member.name)
    archive.extractall(cache)
jar=cache/'apalache-0.61.0/lib/apalache.jar'
assert digest(jar)==pins['apalache']['jarSha256']
link=source/'.golden-build/tla-differential/toolchain'
link.parent.mkdir(parents=True,exist_ok=True)
assert not link.exists() and not link.is_symlink()
link.symlink_to(cache,target_is_directory=True)
(build/'offline-fixture-artifacts.json').write_text(json.dumps({'schema':'mirrors.dpm-offline-fixture-artifacts/v1',
    'artifacts':rows,'extractedApalacheJarSha256':digest(jar),'sourceCache':str(link),
    'ownedCache':str(cache),'modelCheckerExecuted':False},indent=2)+'\n')
print(json.dumps(rows,indent=2))
