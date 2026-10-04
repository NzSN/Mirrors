#!/usr/bin/env python3
"""Package both SDKs and qualify fresh consumers with checkout paths hidden."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

ROOT=Path(__file__).resolve().parents[3]

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def run(command,log,**kwargs):
    with Path(log).open('w') as stream:subprocess.run(command,stdout=stream,stderr=subprocess.STDOUT,check=True,**kwargs)
def inventory(root):return {str(p.relative_to(root)):sha(p) for p in sorted(root.rglob('*')) if p.is_file()}
def verify(root,rows):
    for name,digest in rows.items():
        path=root/name
        if path.is_symlink() or not path.is_file() or sha(path)!=digest:raise RuntimeError('missing or changed admitted artifact: '+name)
def extract(archive,destination):
    destination.mkdir(parents=True)
    with tarfile.open(archive) as tar:
        for entry in tar.getmembers():
            if entry.issym() or entry.islnk() or Path(entry.name).is_absolute() or '..' in Path(entry.name).parts:raise RuntimeError('unsafe package archive member')
        tar.extractall(destination,filter='data')

def inside():
    admitted=Path('/tmp/admitted');work=Path('/tmp/work');manifest=json.loads((admitted/'manifest.json').read_text());verify(admitted,manifest)
    assert not any(Path('/home').iterdir()),'source-home mount is not empty'
    ecma=work/'ecma';shutil.copytree(admitted/'kit/languages/ecma',ecma)
    (ecma/'node_modules').symlink_to(admitted/'node_modules',target_is_directory=True)
    run(['/usr/local/bin/node',str(admitted/'typescript/bin/tsc'),'-p',str(ecma/'tsconfig.json')],work/'ecma-compile.log',timeout=180)
    for source in (ecma/'compiled/generated').rglob('*.js'):
        target=ecma/'generated'/source.relative_to(ecma/'compiled/generated');shutil.copy2(source,target)
    run(['/usr/local/bin/node',str(ecma/'codec-test.mjs'),str(admitted/'prepared/stable-t1/native-probe.json')],work/'ecma-codec.log',timeout=60)
    rust=work/'rust';shutil.copytree(admitted/'kit/languages/rust',rust)
    (rust/'.cargo').mkdir(exist_ok=True)
    config='''[source.crates-io]
replace-with = "vendored-sources"
[source.vendored-sources]
directory = "/tmp/admitted/vendor"
[patch.crates-io]
mirrorrust = { path = "/tmp/admitted/rust-sdk" }
'''
    (rust/'.cargo/config.toml').write_text(config)
    env=dict(os.environ,CARGO_HOME=str(work/'cargo-home'),CARGO_TARGET_DIR=str(work/'rust-build'),CARGO_NET_OFFLINE='true',RUSTC='/tmp/toolchain/bin/rustc')
    run(['/tmp/toolchain/bin/cargo','build','--offline','--locked','--manifest-path',str(rust/'Cargo.toml')],work/'rust-compile.log',cwd=rust,env=env,timeout=300)
    run(['/tmp/toolchain/bin/cargo','test','--offline','--locked','--manifest-path',str(rust/'Cargo.toml')],work/'rust-codec.log',cwd=rust,env=env,timeout=180)
    metadata=subprocess.check_output(['/tmp/toolchain/bin/cargo','metadata','--offline','--locked','--format-version','1','--manifest-path',str(rust/'Cargo.toml')],cwd=rust,env=env,text=True)
    (work/'rust-metadata.json').write_text(metadata)
    package=next(p for p in json.loads(metadata)['packages'] if p['name']=='mirrorrust')
    assert package['manifest_path']=='/tmp/admitted/rust-sdk/Cargo.toml','consumer bypassed installed Rust crate'
    capabilities={}
    script="import {SCHEDULING_CAPABILITIES as c} from 'mirrorecma'; console.log(JSON.stringify(c));"
    capabilities['ecma']=json.loads(subprocess.check_output(['/usr/local/bin/node','--input-type=module','-e',script],cwd=ecma,text=True))
    capabilities['rust']=json.loads((admitted/'rust-sdk/scheduling-capabilities.json').read_text())
    for value in capabilities.values():assert value['schema']=='mirrors.scheduling-capabilities/v1' and value['claims']['genericNativeScheduler'] is False
    (work/'capabilities.json').write_text(json.dumps(capabilities,indent=2)+'\n')
    workers=json.loads((admitted/'settings.json').read_text())['workers']
    rows=[]
    for language,runner in [('ecma',ecma/'runner.mjs'),('rust',work/'rust-build/debug/mirrors-dpm-rust-consumer')]:
        out=work/(language+'-acceptance')
        command=['/usr/bin/python3',str(admitted/'kit/languages/check.py'),'--language',language,'--runner',str(runner),'--node','/usr/local/bin/node','--mirror',str(admitted/'runtime/mirror'),'--fixture',str(admitted/'fixture'),'--counter-oracles',str(admitted/'counter-oracles'),'--prepared',str(admitted/'prepared'),'--native-oracles',str(admitted/'native-oracles'),'--workers',workers,'--out',str(out)]
        run(command,work/(language+'-acceptance.log'),timeout=600)
        for scope,count in [('counter',60),('exploration',11),('native',14)]:
            report=out/scope/'acceptance.json';value=json.loads(report.read_text());assert value['status']=='passed' and len(value['rows'])==count
            rows.append({'language':language,'scope':scope,'cases':count,'report':str(report.relative_to(work)),'sha256':sha(report)})
    # Exercise artifact admission independently from SDK behavior.
    control=work/'artifact-controls';control.mkdir();sample=control/'declaration.json';shutil.copy2(admitted/'rust-sdk/scheduling-capabilities.json',sample);expected={'declaration.json':sha(sample)};verify(control,expected);controls=[]
    sample.write_text('{}\n')
    for kind in ['tampered','missing']:
        if kind=='missing':sample.unlink()
        try:verify(control,expected)
        except RuntimeError:controls.append(kind)
        else:raise RuntimeError('artifact admission accepted '+kind)
    verify(admitted,manifest)
    result={'schema':'mirrors.dpm-language-installed-acceptance/v1','status':'passed','sourceHidden':True,'networkNamespaceIsolated':True,'hostScope':'Linux controllers and existing Windows workers via local WSL carrier; Windows workers are not namespace-sandboxed','rows':rows,'artifactControls':controls,'manifestSha256':sha(admitted/'manifest.json'),'capabilitySha256':sha(work/'capabilities.json'),'externalPublication':False}
    (work/'acceptance.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))

def main():
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);p.add_argument('--vendor',type=Path,required=True);p.add_argument('--counter-oracles',type=Path,default=ROOT/'Plans/dpm2-dpm5-qualified-20261004/counter-oracles');p.add_argument('--native-oracles',type=Path,default=ROOT/'Plans/dpm2-dpm5-qualified-20261004/native-oracles');p.add_argument('--prepared',type=Path,default=ROOT/'Plans/dpm2-dpm5-qualified-20261004/native-prepared');p.add_argument('--workers',type=Path,default=Path('/mnt/c/Users/ayden/Desktop/Workspace/MirrorsRemote/dpm-20261004'));args=p.parse_args()
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False);admitted=out/'admitted';admitted.mkdir();work=out/'work';work.mkdir();packages=out/'packages';packages.mkdir()
    ecma=ROOT.parent/'MirrorECMA';rust=ROOT.parent/'MirrorRust'
    # Build is explicit; packaging does not run arbitrary lifecycle scripts.
    run(['pnpm','run','build'],out/'ecma-sdk-build.log',cwd=ecma,timeout=180)
    result=subprocess.run(['npm','pack','--ignore-scripts','--json','--pack-destination',str(packages),'--cache',str(out/'npm-cache')],cwd=ecma,capture_output=True,text=True,check=True,timeout=120)
    (out/'npm-pack.json').write_text(result.stdout);archive=packages/json.loads(result.stdout)[0]['filename'];extract(archive,out/'ecma-extract');(admitted/'node_modules').mkdir();shutil.move(str(out/'ecma-extract/package'),admitted/'node_modules/mirrorecma')
    (admitted/'node_modules/@types').mkdir();shutil.copytree((ecma/'node_modules/@types/node').resolve(),admitted/'node_modules/@types/node');shutil.copytree((ecma/'node_modules/undici-types').resolve(),admitted/'node_modules/undici-types');shutil.copytree((ecma/'node_modules/typescript').resolve(),admitted/'typescript')
    env=dict(os.environ,CARGO_TARGET_DIR=str(out/'rust-package-build'))
    run(['cargo','package','--offline','--locked','--allow-dirty','--no-verify'],out/'rust-package.log',cwd=rust,env=env,timeout=180)
    crate=next((out/'rust-package-build/package').glob('mirrorrust-*.crate'));shutil.copy2(crate,packages/crate.name);extract(crate,out/'rust-extract');crate_root=next((out/'rust-extract').iterdir());shutil.move(str(crate_root),admitted/'rust-sdk')
    shutil.copytree(args.vendor,admitted/'vendor')
    source=ROOT/'tools/deterministic-scheduling';shutil.copytree(source/'languages',admitted/'kit/languages',ignore=shutil.ignore_patterns('__pycache__','target'))
    (admitted/'kit/native').mkdir();shutil.copy2(source/'native/terminate_peer.py',admitted/'kit/native/terminate_peer.py');shutil.copy2(source/'check_exploration.py',admitted/'kit/check_exploration.py')
    shutil.copytree(ROOT/'test/fixtures/deterministic-scheduling',admitted/'fixture')
    for src,name in [(args.counter_oracles,'counter-oracles'),(args.native_oracles,'native-oracles'),(args.prepared,'prepared')]:shutil.copytree(src,admitted/name)
    (admitted/'runtime').mkdir();shutil.copy2(ROOT/'.lake/build/bin/mirror',admitted/'runtime/mirror');(admitted/'settings.json').write_text(json.dumps({'workers':str(args.workers.resolve())})+'\n')
    rows=inventory(admitted);(admitted/'manifest.json').write_text(json.dumps(rows,indent=2)+'\n')
    toolchain=subprocess.check_output(['rustc','--print','sysroot'],text=True).strip()
    command=['bwrap','--die-with-parent','--unshare-net','--ro-bind','/','/','--tmpfs','/home','--tmpfs','/tmp','--ro-bind',str(admitted),'/tmp/admitted','--ro-bind',toolchain,'/tmp/toolchain','--bind',str(work),'/tmp/work','--proc','/proc','--dev','/dev','--clearenv','--setenv','PATH','/tmp/toolchain/bin:/usr/local/bin:/usr/bin:/bin','--setenv','HOME','/tmp/work','--setenv','LC_ALL','C.UTF-8']
    for key in ['WSL_INTEROP','WSL_DISTRO_NAME']:
        if key in os.environ:command+=['--setenv',key,os.environ[key]]
    command+=['--chdir','/tmp/work','/usr/bin/python3','/tmp/admitted/kit/languages/check_installed.py','--inside']
    (out/'command.json').write_text(json.dumps(command,indent=2)+'\n');run(command,out/'installed.log',timeout=1500);verify(admitted,rows)
    print('Installed DPM acceptance:',work/'acceptance.json')

if __name__=='__main__':
    if sys.argv[1:]==['--inside']:inside()
    else:main()
