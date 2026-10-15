from pathlib import Path
import json, os, shutil, subprocess
out=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015')
out.mkdir(exist_ok=True)
def run(args):
 try:
  p=subprocess.run(args,capture_output=True,text=True,timeout=20)
  return {'command':args,'exitCode':p.returncode,'stdout':p.stdout[-5000:],'stderr':p.stderr[-2000:]}
 except Exception as e:return {'command':args,'error':str(e)}
r={'schema':'mirrors.client-remediation-preflight/v1','storage':run(['df','-h','/','/mnt/d']),'memory':run(['free','-h']),'kernel':run(['uname','-a']),'tools':{}}
for name in ['python3','cc','g++','cmake','ninja','openssl','node','pnpm','ghc','cabal','cargo','rustc','bwrap']:
 path=shutil.which(name)
 r['tools'][name]=run([path,'--version']) if path else None
for item in ['/home/jlc/.elan/bin/lean','/home/jlc/.ghcup/bin/ghc','/home/jlc/.ghcup/bin/cabal','/home/jlc/.cargo/bin/cargo','/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/node/bin/node']:
 if Path(item).is_file():r['tools'][item]=run([item,'--version'])
r['availableElanToolchains']=[x.name for x in Path('/home/jlc/.elan/toolchains').glob('*')]
r['knownDependencyRoots']={x:Path(x).exists() for x in ['/home/jlc/Tools/mirrors-dpm-remediation-20261013','/home/jlc/Tools/mirrors-dpm-followup-20261014','/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013','/mnt/d/Desktop/Workspaces/Mirrors-client-conformance-20261015','/home/jlc/.ghcup/ghc']}
(out/'preflight.json').write_text(json.dumps(r,indent=2)+'\n')
print(json.dumps(r))
