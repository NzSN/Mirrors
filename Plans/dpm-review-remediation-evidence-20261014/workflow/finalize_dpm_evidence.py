from pathlib import Path,PurePosixPath
import hashlib,json,shutil,tarfile
handoff=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013');build=handoff/'build'
root=build/'curated-evidence-20261014'
def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):h.update(block)
    return h.hexdigest()
with tarfile.open(handoff/'dpm-final-metadata.tar') as archive:
    for item in archive.getmembers():
        p=PurePosixPath(item.name)
        assert item.isfile() and not p.is_absolute() and '..' not in p.parts
        destination=root/item.name;destination.parent.mkdir(parents=True,exist_ok=True)
        destination.write_bytes(archive.extractfile(item).read())
shutil.copy2(handoff/'finalize_dpm_evidence.py',root/'workflow/finalize_dpm_evidence.py')
for path in (build/'logs').iterdir():
    if path.is_file() and path.name!='finalize-evidence.log':shutil.copy2(path,root/'logs'/path.name)
rows={}
for path in sorted(root.rglob('*')):
    if path.is_file() and path.name!='evidence-manifest.json':
        assert not path.is_symlink()
        rows[str(path.relative_to(root))]={'sha256':digest(path),'bytes':path.stat().st_size}
manifest={'schema':'mirrors.dpm-remediation-evidence-manifest/v1','date':'2026-10-14','files':rows,
          'fileCount':len(rows),'totalBytes':sum(row['bytes'] for row in rows.values()),
          'excluded':['evidence-manifest.json (self)'],'hashingHost':'windows-dev remote Ubuntu WSL'}
(root/'evidence-manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
archive=build/'final-evidence-20261014.tar.gz'
with tarfile.open(archive,'w:gz') as output:
    for path in sorted(root.rglob('*')):
        if path.is_file():output.add(path,arcname=str(path.relative_to(root)),recursive=False)
result={'evidenceManifestSha256':digest(root/'evidence-manifest.json'),'fileCount':len(rows),
        'totalBytes':manifest['totalBytes'],'archiveSha256':digest(archive),'archiveBytes':archive.stat().st_size,
        'archive':str(archive)}
(build/'final-evidence-transfer.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2),flush=True)
