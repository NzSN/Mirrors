from pathlib import Path
import json
r=Path('/home/jlc/Tools/mirrors-client-fixes-20261015');d=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015')
for p in (d/'haskell/dist').rglob('*prettyprinter*'): print(p, 'DIR' if p.is_dir() else p.stat().st_size)
for p in (r/'tools/haskell/cabal/packages/hackage.haskell.org/prettyprinter').rglob('*'):print('cache',p,p.stat().st_size)
for p in (d/'haskell/dist').rglob('prettyprinter-1.7.2'):
 if p.is_dir():print('files',[(str(q.relative_to(p)),q.stat().st_size) for q in p.iterdir()])
