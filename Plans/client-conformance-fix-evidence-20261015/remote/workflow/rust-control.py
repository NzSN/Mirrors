import hashlib,json,os,subprocess,tarfile,tomllib
from pathlib import Path
root=Path('/home/jlc/Tools/mirrors-client-fixes-20261015')
build=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015')
source=root/'source/MirrorRust';source.mkdir()
with tarfile.open(build/'rust-control-source.tar') as archive:archive.extractall(source)
selection=json.loads((build/'rust-control-source.json').read_text())
for name,digest in selection['files'].items():assert hashlib.sha256((source/name).read_bytes()).hexdigest()==digest
vendor=root/'tools/rust-control-vendor';vendor.mkdir()
registry_cache=Path('/home/jlc/.cargo/registry/cache')
rows={}
for package in tomllib.loads((source/'Cargo.lock').read_text())['package']:
    if 'checksum' not in package:continue
    name=package['name']+'-'+package['version'];matches=list(registry_cache.glob('*/'+name+'.crate'))
    assert len(matches)==1,('missing locked cached crate',name)
    archive=matches[0];assert hashlib.sha256(archive.read_bytes()).hexdigest()==package['checksum'],name
    with tarfile.open(archive) as bundle:bundle.extractall(vendor)
    directory=vendor/name
    files={str(path.relative_to(directory)):hashlib.sha256(path.read_bytes()).hexdigest() for path in directory.rglob('*') if path.is_file() and path.name!='.cargo-checksum.json'}
    (directory/'.cargo-checksum.json').write_text(json.dumps({'package':package['checksum'],'files':files}))
    rows[name]=package['checksum']
config=source/'.cargo';config.mkdir(exist_ok=True)
(config/'config.toml').write_text('[source.crates-io]\nreplace-with="owned-vendor"\n[source.owned-vendor]\ndirectory="'+str(vendor)+'"\n')
environment={**os.environ,'PATH':'/home/jlc/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin:/usr/bin:/bin',
             'CARGO_HOME':str(root/'tools/rust-control-cargo'),'CARGO_TARGET_DIR':str(build/'rust-control-target'),
             'CARGO_BUILD_JOBS':'2','TMPDIR':'/tmp/fix-tests','CC':'/usr/bin/gcc-12','CXX':'/usr/bin/g++-12'}
command=['cargo','test','--locked','--offline','--test','transport','--','--test-threads=1']
with (build/'logs/rust-control.log').open('wb') as output:
    completed=subprocess.run(command,cwd=source,env=environment,stdout=output,stderr=subprocess.STDOUT,timeout=600)
record={'status':'passed' if completed.returncode==0 else 'failed','exit':completed.returncode,'sourceHead':selection['head'],
        'sourceFilesVerified':len(selection['files']),'command':command,'lockedCratesVerified':rows,
        'rustc':subprocess.check_output(['rustc','--version'],env=environment,text=True).strip(),
        'cargo':subprocess.check_output(['cargo','--version'],env=environment,text=True).strip(),
        'oldCacheAccess':'only read and verify locked .crate archives; own Cargo home/vendor/targets',
        'modelCheckerExecuted':False}
(build/'rust-control-result.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2),flush=True)
raise SystemExit(completed.returncode)
