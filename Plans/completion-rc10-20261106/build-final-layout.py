"""Construct both admitted rc.10 caches and installations from frozen snapshots."""
import json
from common_final import *
C3=ROOT/FREEZE['frameworkCatalog']['path'];C3_SHA=FREEZE['frameworkCatalog']['sha256']

def main():
 freeze=FREEZE;review=json.loads((PLAN/'rc10-freeze-review.json').read_text())
 assert review['status']=='RC10 SOURCE FREEZE VERIFY GREEN'
 selected=freeze['families']['wsl2'];catalog=ROOT/selected['catalog']['path'];locks=ROOT/selected['locksRoot'];snapshot=(ROOT/selected['snapshotIndex']['path']).parent
 source=ROOT/freeze['taskOwnedSource'];out=OUT/'qualification-final';env=environment()
 for profile in ['checked-replay-local','checked-replay-gate']:
  cache=out/'cache-admitted'/profile;prefix=OUT/'qualification/install'/profile
  run('rc10-final-layout-'+profile+'-build',['python3',source/'tools/distribution/build.py','--profile',profile,'--locks-root',locks,'--catalog',catalog,'--out',cache,'--snapshot-root',snapshot,'--lake-bin','/home/lsz/.elan/bin/lake','--node-archive',ROOT/'.golden-build/version-0.1/toolchains/node-v24.15.0-linux-x64.tar.xz','--batteries-bundle',ROOT/'third_party/batteries/batteries-v4.33.0.bundle','--git-bin','/usr/bin/git','--ldd-bin','/usr/bin/ldd','--typescript-node-modules',ROOT/'.golden-build/rc3-s5-20261031/ts-deps','--evidence-wheels',ROOT/'.golden-build/rc3-s5-20261031/prepared/evidence-wheels','--framework-catalog-bin',C3,'--framework-catalog-sha256',C3_SHA],cwd=source,env=env,timeout=3600)
  run('rc10-final-layout-'+profile+'-install',['python3',source/'tools/distribution/install.py','--cache',cache,'--prefix',prefix,'--framework-catalog-bin',C3,'--framework-catalog-sha256',C3_SHA],cwd=source,env=env,timeout=1800)
 print('RC10 BOTH DISTRIBUTIONS CONSTRUCTED',flush=True)

if __name__=='__main__':main()
