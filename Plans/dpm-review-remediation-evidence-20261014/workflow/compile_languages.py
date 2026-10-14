import json
from pathlib import Path
import shutil
import subprocess

root=Path('/home/jlc/Tools/mirrors-dpm-remediation-20261013')
sources=root/'source'
build=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build')
node=Path('/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/node/bin/node')
typescript=root/'prerequisites/node_modules/typescript'
def run(command,name,**kwargs):
    with (build/'logs'/name).open('xb') as log:
        subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True,**kwargs)
ecma=root/'ecma'
shutil.copytree(sources/'Mirrors/tools/deterministic-scheduling/languages/ecma',ecma)
modules=ecma/'node_modules'
modules.mkdir()
sdk=modules/'mirrorecma';sdk.mkdir()
for name in ['package.json','scheduling-capabilities.json']:
    source=sources/'MirrorECMA'/name
    if source.exists():shutil.copy2(source,sdk/name)
for name in ['@types/node','undici-types']:
    shutil.copytree(root/'prerequisites/node_modules'/name,modules/name)
run([str(node),str(typescript/'bin/tsc'),'-p',str(sources/'MirrorECMA/tsconfig.json'),
     '--outDir',str(sdk/'dist')],'ecma-sdk-build.log',timeout=300)
run([str(node),str(typescript/'bin/tsc'),'-p',str(ecma/'tsconfig.json')],'ecma-consumer-build.log',timeout=300)
for path in (ecma/'compiled/generated').rglob('*.js'):
    shutil.copy2(path,ecma/path.relative_to(ecma/'compiled'))
regression=root/'ecma-regression'
regression.mkdir();(regression/'package.json').write_text('{"type":"module"}\n')
shutil.copytree(sdk/'dist',regression/'dist')
shutil.copytree(sources/'MirrorECMA/test/schedule',regression/'test/schedule')
for name in ['schedule','binding','exploration']:
    run([str(node),str(regression/'test/schedule'/(name+'.test.mjs'))],
        'ecma-'+name+'-tests.log',timeout=180)
rust=root/'rust'
shutil.copytree(sources/'Mirrors/tools/deterministic-scheduling/languages/rust/src',rust/'src')
sdk=rust/'sdk';sdk.mkdir()
shutil.copytree(sources/'MirrorRust/src',sdk/'src')
for name in ['Cargo.toml','Cargo.lock','scheduling-capabilities.json']:
    shutil.copy2(sources/'MirrorRust'/name,sdk/name)
text=(sources/'Mirrors/tools/deterministic-scheduling/languages/rust/Cargo.toml').read_text()
(rust/'Cargo.toml').write_text(text.replace('mirrorrust = "=1.0.0"','mirrorrust = { path = "sdk" }'))
shutil.copy2(sdk/'Cargo.lock',rust/'Cargo.lock')
run(['cargo','build','--offline','--manifest-path',str(rust/'Cargo.toml')],
    'rust-consumer-build.log',timeout=900)
with (build/'logs/rust-vendor.log').open('xb') as log:
    subprocess.run(['cargo','vendor','--offline','--locked','--manifest-path',str(rust/'Cargo.toml'),
        str(root/'rust-vendor')],cwd=rust,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=300)
print('REMOTE_LANGUAGE_PHASE_PASSED',flush=True)
