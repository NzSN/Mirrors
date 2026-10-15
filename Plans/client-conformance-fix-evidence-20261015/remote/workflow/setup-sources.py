import hashlib,json,shutil,tarfile
from pathlib import Path
build=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015')
root=Path('/home/jlc/Tools/mirrors-client-fixes-20261015')
manifest=json.loads((build/'ready-source-manifest.json').read_text())
with tarfile.open(build/'ready-sources.tar') as archive:
    for member in archive.getmembers():
        path=Path(member.name)
        assert not path.is_absolute() and '..' not in path.parts
        assert member.isfile() or member.isdir() or member.issym() or member.islnk()
    archive.extractall(root)
for repository,files in manifest.items():
    for name,row in files.items():
        file=root/'source'/repository/name
        assert hashlib.sha256(file.read_bytes()).hexdigest()==row['sha256'],(repository,name)
with tarfile.open(build/'ecma-dependencies.tar') as archive:
    archive.extractall(root/'dependency-copy')
shutil.move(root/'dependency-copy/node_modules',root/'source/MirrorECMA/node_modules')
shutil.move(root/'dependency-copy/pnpm',root/'tools/pnpm-cache-11.5.1')
result={'status':'verified','repositories':{name:len(files) for name,files in manifest.items()},
        'sourceRoot':str(root/'source'),'oldSourcesOrCachesMutated':False,
        'dependencyMode':'copied installed dependency tree; original and staged package/lock bytes must match before use'}
(build/'source-transfer-ready.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result),flush=True)
