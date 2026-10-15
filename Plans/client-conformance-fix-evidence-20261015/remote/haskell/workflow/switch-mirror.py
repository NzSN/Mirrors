from pathlib import Path
p=Path('/home/jlc/Tools/mirrors-client-fixes-20261015/tools/haskell/cabal/config');s=p.read_text().replace('url: https://hackage.haskell.org/','url: https://mirrors.ustc.edu.cn/hackage/');p.write_text(s)
print(s)
