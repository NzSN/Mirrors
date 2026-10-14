"""Merge coordinator metadata into completed raw evidence, hash/archive remotely."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tarfile

build=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/followup-20261014')
root=build/'curated-followup-final'
metadata=build/sys.argv[1]
def digest(path):
    value=hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):value.update(chunk)
    return value.hexdigest()
assert digest(metadata)==sys.argv[2]
with tarfile.open(metadata) as bundle:
    for member in bundle.getmembers():
        path=Path(member.name)
        assert member.isfile() and not path.is_absolute() and '..' not in path.parts
        destination=root/path;destination.parent.mkdir(parents=True,exist_ok=True)
        destination.write_bytes(bundle.extractfile(member).read())
shutil.copy2(build/'workflow/finalize_evidence.py',root/'workflow/finalize_evidence.py')
files={}
for path in sorted(root.rglob('*')):
    if path.is_file() and path.name!='evidence-manifest.json':
        assert not path.is_symlink()
        files[str(path.relative_to(root))]={'sha256':digest(path),'bytes':path.stat().st_size}
manifest={'schema':'mirrors.dpm-followup-evidence-manifest/v1','date':'2026-10-14',
          'files':files,'fileCount':len(files),'totalBytes':sum(row['bytes'] for row in files.values()),
          'excluded':['evidence-manifest.json (self)'],'hashingHost':'windows-dev remote Ubuntu WSL'}
(root/'evidence-manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
archive=build/'final-evidence.tar.gz'
assert not archive.exists()
with tarfile.open(archive,'w:gz') as bundle:
    for path in sorted(root.rglob('*')):
        if path.is_file():bundle.add(path,arcname=str(path.relative_to(root)),recursive=False)
record={'fileCount':len(files),'totalBytes':manifest['totalBytes'],
        'evidenceManifestSha256':digest(root/'evidence-manifest.json'),
        'archive':str(archive),'archiveBytes':archive.stat().st_size,'archiveSha256':digest(archive)}
(build/'final-transfer.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2),flush=True)
