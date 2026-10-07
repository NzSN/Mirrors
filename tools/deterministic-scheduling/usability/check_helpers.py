from pathlib import Path
import subprocess,json,shutil,hashlib
import argparse,os
parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path,required=True);parser.add_argument('--cpp-deps',type=Path,required=True);args=parser.parse_args()
root=Path(__file__).resolve().parents[3];out=args.out.resolve();out.mkdir(exist_ok=False)
gen=root/'.lake/build/bin/model_interface_gen';lock=root/'test/fixtures/deterministic-scheduling/ScheduledCounter.lock.json';plan=root/'test/fixtures/deterministic-scheduling/dpm-kit-plan.json'
for language,target in [('ecma','mirrorecma-async-v1'),('rust','mirrorrust-v1'),('cpp','mirrorcpp-v1')]:
 kit=out/language;subprocess.run([str(gen),'generate-dpm','--lock',str(lock),'--mapping',str(plan),'--target',target,'--out',str(kit)],check=True)
 if language=='ecma':
  (kit/'package.json').write_text('{"type":"module"}\n');(kit/'node_modules').mkdir();(kit/'node_modules/mirrorecma').symlink_to(root.parent/'MirrorECMA')
  (kit/'tsconfig.json').write_text(json.dumps({'compilerOptions':{'target':'es2022','module':'node16','moduleResolution':'node16','strict':True,'skipLibCheck':True,'outDir':'compiled'},'include':['*.ts']})+'\n')
  subprocess.run(['/usr/local/bin/node',str(root.parent/'MirrorECMA/node_modules/typescript/bin/tsc'),'-p',str(kit/'tsconfig.json')],check=True)
  test="import {stepFor} from './compiled/DpmKit.generated.js'; import assert from 'node:assert/strict'; assert.deepEqual(stepFor('Read','a'),{actor:'a',checkpoint:'read'}); assert.deepEqual(stepFor('Finish','b'),{actor:'b',checkpoint:'$done'}); assert.throws(()=>stepFor('Read','foreign')); assert.throws(()=>stepFor('unknown','a')); console.log('ECMA generated helper + application seed compiled; controls passed');"
  (kit/'helper-test.mjs').write_text(test);subprocess.run(['/usr/local/bin/node',str(kit/'helper-test.mjs')],check=True)
 if language=='rust':
  (kit/'src').mkdir();shutil.copy2(kit/'DpmKit.generated.rs',kit/'src/dpm_kit.rs');shutil.copy2(kit/'DpmKit.application.example.rs',kit/'src/application.rs')
  (kit/'Cargo.toml').write_text('[package]\nname="dpm-kit-consumer"\nversion="0.1.0"\nedition="2021"\n[dependencies]\nmirrorrust={path='+json.dumps(str(root.parent/'MirrorRust'))+'}\n')
  (kit/'src/main.rs').write_text('mod dpm_kit; mod application; fn main(){assert_eq!(dpm_kit::step_for("Read",Some("a")).unwrap().checkpoint,"read");assert_eq!(dpm_kit::step_for("Finish",Some("b")).unwrap().checkpoint,"$done");assert!(dpm_kit::step_for("Read",Some("foreign")).is_err());assert!(dpm_kit::step_for("unknown",Some("a")).is_err());println!("Rust generated helper + application seed compiled; controls passed");}\n')
  env=__import__('os').environ.copy();env['CARGO_TARGET_DIR']=str(out/'rust-target');subprocess.run(['cargo','run','--offline','--manifest-path',str(kit/'Cargo.toml')],env=env,check=True)
cpp=out/'cpp';meta=json.loads((cpp/'DpmKit.metadata.json').read_text());namespace=meta['cppNamespace']
(cpp/'helper-test.cpp').write_text('#include "DpmKit.generated.hpp"\n#include "DpmKit.application.example.hpp"\n#include <cassert>\nint main(){auto s='+namespace+'::step_for("Read","a");assert(s.checkpoint=="read");bool denied=false;try{(void)'+namespace+'::step_for("Read","foreign");}catch(const std::invalid_argument&){denied=true;}assert(denied); }\n')
deps=args.cpp_deps.resolve();include=['-I'+str(root.parent/'MirrorCPP/include'),'-I'+str(deps),'-I'+str(cpp)]+['-I'+str(p/'include') for p in deps.iterdir() if p.is_dir() and (p/'include').is_dir()]
subprocess.run(['g++','-std=c++23','-Wall','-Wextra',*include,str(cpp/'helper-test.cpp'),'-o',str(cpp/'helper-test')],check=True)
subprocess.run([str(cpp/'helper-test')],check=True)
node=out/'ecma';shutil.copy2(root/'tools/deterministic-scheduling/usability/node-replay.mjs',node/'actual-replay.mjs')
for mode in ['ok','mutate']:subprocess.run(['/usr/local/bin/node',str(node/'actual-replay.mjs'),mode,str(root)],check=True)
report={'schema':'mirrors.dpm-kit-source-acceptance/v1','status':'passed','languages':['cpp','ecma','rust'],'actualNodeComparisons':['matched','step_mismatch'],'scope':'source SDK helper/seed compile and real generated Node comparison; not installed/release qualification','helperSha256':{str(p.relative_to(out)):hashlib.sha256(p.read_bytes()).hexdigest() for lang in ['cpp','ecma','rust'] for p in (out/lang).glob('DpmKit.generated.*')}}
(out/'acceptance.json').write_text(json.dumps(report,indent=2)+'\n')
print('Source native/helper/real replay acceptance:',out/'acceptance.json')
