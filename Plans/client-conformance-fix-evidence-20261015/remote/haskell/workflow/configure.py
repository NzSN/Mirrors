from pathlib import Path
import shutil,os
r=Path('/home/jlc/Tools/mirrors-client-fixes-20261015')
d=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015')
p=r/'tools/haskell/cabal/config';p.write_text(p.read_text()+'http-transport: curl\n')
shutil.copyfile(d/'haskell/curl-wrapper.py',r/'tools/haskell/bin/curl');os.chmod(r/'tools/haskell/bin/curl',0o755)
print('\n'.join(x for x in (r/'tools/haskell/cabal/example-config').read_text().splitlines() if any(k in x for k in ['http-transport','curl','remote-repo-cache'])))
