from pathlib import Path
import shutil
r=Path('/home/jlc/Tools/mirrors-client-fixes-20261015');d=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015');p=r/'tools/haskell/cabal/config';s=p.read_text().replace('secure: False','secure: True');p.write_text(s)
c=r/'tools/haskell/cabal/packages/hackage.haskell.org'
shutil.copyfile(c/'00-index.tar',c/'01-index.tar')
shutil.copyfile(d/'downloads/hackage-ustc-index.tar.gz',c/'01-index.tar.gz')
(r/'source/ModelMirros/cabal.project.local').write_text('index-state: 2026-09-01T00:00:00Z\n')
print(s)
