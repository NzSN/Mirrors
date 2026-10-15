import base64,hashlib,json,os,subprocess,tarfile
from pathlib import Path
build=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015')
root=Path('/home/jlc/Tools/mirrors-client-fixes-20261015')
download=build/'downloads'
node_archive=download/'node-v24.15.0-linux-x64.tar.xz'
matches=[line.split()[0] for line in (download/'node-SHASUMS256.txt').read_text().splitlines() if line.split()[-1]=='node-v24.15.0-linux-x64.tar.xz']
assert len(matches)==1
assert hashlib.sha256(node_archive.read_bytes()).hexdigest()==matches[0]
with tarfile.open(node_archive) as archive:archive.extractall(root/'tools')
(root/'tools/node-v24.15.0-linux-x64').rename(root/'tools/node')
metadata=json.loads((download/'pnpm-metadata.json').read_text())
assert metadata['version']=='11.22.0'
pnpm_archive=download/'pnpm-11.22.0.tgz'
algorithm,expected=metadata['dist']['integrity'].split('-',1)
assert base64.b64encode(hashlib.new(algorithm,pnpm_archive.read_bytes()).digest()).decode()==expected
destination=root/'tools/pnpm-11.22.0';destination.mkdir()
with tarfile.open(pnpm_archive) as archive:archive.extractall(destination)
package=destination/'package'
bin_rel=json.loads((package/'package.json').read_text())['bin']['pnpm']
bin_dir=root/'tools/bin';bin_dir.mkdir(exist_ok=True)
(bin_dir/'node').symlink_to(root/'tools/node/bin/node')
(bin_dir/'python3').symlink_to('/home/jlc/.local/share/uv/python/cpython-3.12.14-linux-x86_64-gnu/bin/python3.12')
wrapper=bin_dir/'pnpm'
wrapper.write_text('#!/bin/sh\nexec '+str(root/'tools/node/bin/node')+' '+str(package/bin_rel)+' "$@"\n');wrapper.chmod(0o755)
env={**os.environ,'PATH':str(bin_dir)+':/usr/bin:/bin','COREPACK_ENABLE_AUTO_PIN':'0'}
versions={name:subprocess.check_output([str(bin_dir/name),'--version'],env=env,text=True).strip() for name in ['node','pnpm','python3']}
record={'status':'verified-installed','nodeArchiveSha256':matches[0],'nodeRoot':str(root/'tools/node'),
        'pnpmIntegrity':metadata['dist']['integrity'],'pnpmTarSha256':hashlib.sha256(pnpm_archive.read_bytes()).hexdigest(),
        'versions':versions,'systemOrOldToolsModified':False}
(build/'node-pnpm-install.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2),flush=True)
