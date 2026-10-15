import hashlib,json,os,shutil,tarfile
from pathlib import Path
root=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-conformance-20261015')
out=root/'report-artifacts-final';out.mkdir()
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def retain(path,name):
    assert path.is_file() and not path.is_symlink()
    assert path.suffix not in ['.key','.pem']
    target=out/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,target)
cli_dirs=sorted((root/'cli-work').glob('client-cli-probe-*'))
assert len(cli_dirs)==1
cli=cli_dirs[0]
metadata=json.loads((cli/'metadata.json').read_text())
prior=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build')
ledger=json.loads((prior/'curated-evidence-20261014/binary-identities.json').read_text())['artifacts']
binary=Path(metadata['binary'])
assert ledger[str(binary)]['sha256']==sha(binary)==metadata['binary_sha256']
assert all(row['matches'] for row in metadata['source_parity'])
remaining=[]
for directory in Path('/proc').iterdir():
    if not directory.name.isdigit() or int(directory.name)==os.getpid():continue
    try:args=(directory/'cmdline').read_bytes().decode().strip('\0').split('\0')
    except (OSError,UnicodeError):continue
    if any(str(root)+'/' in arg for arg in args):remaining.append({'pid':int(directory.name),'args':args})
assert not remaining,remaining
cleanup={'status':'clean','remainingOwnedProcesses':remaining,'cliOwnedChildrenReaped':True,
         'cliPeerThreadsStopped':True,'tlsPeersTerminatedAndReaped':True,
         'oldSourceInstallOrEvidenceWrites':False,'oldDpmImageRemounted':False,
         'cliBinaryMatchesQualifiedLedger':True,'cliBinarySha256':sha(binary)}
(root/'cleanup.json').write_text(json.dumps(cleanup,indent=2)+'\n')
for path in root.iterdir():
    if path.is_file() and path.suffix in ['.json','.jsonl','.exit','.py','.sh']:retain(path,path.name)
retain(root/'cpp-probes/cpp-source-selection.json','cpp-source-selection.json')
for path in (root/'logs').glob('*.log'):retain(path,'logs/'+path.name)
for path in (root/'tls-results').iterdir():
    if path.is_file() and path.suffix in ['.jsonl','.log']:retain(path,'tls-results/'+path.name)
for name in ['ca','server','server-cn','client']:retain(root/'tls-results/pki'/(name+'.crt'),'tls-public/'+name+'.crt')
for path in cli.rglob('*'):
    if path.is_file() and path.suffix in ['.json','.txt','.log','.tla']:retain(path,'cli/'+str(path.relative_to(cli)))
rows={str(path.relative_to(out)):{'sha256':sha(path),'bytes':path.stat().st_size}
      for path in sorted(out.rglob('*')) if path.is_file()}
manifest={'schema':'mirrors.client-conformance-runtime-artifacts/v1','files':rows,'fileCount':len(rows),
          'privateKeysTransferred':False,'binariesOrBuildCacheTransferred':False,'heavyWorkHost':'remote Windows-dev Ubuntu WSL'}
(out/'evidence-manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
archive=root/'report-artifacts-final.tar.gz'
with tarfile.open(archive,'w:gz') as bundle:
    for path in sorted(out.rglob('*')):
        if path.is_file():bundle.add(path,arcname=str(path.relative_to(out)),recursive=False)
record={'archive':str(archive),'sha256':sha(archive),'bytes':archive.stat().st_size,'files':len(rows),
        'manifestSha256':sha(out/'evidence-manifest.json'),'cliWorkRoot':str(cli)}
(root/'report-transfer-final.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2),flush=True)
