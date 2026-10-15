from pathlib import Path
import shutil
h=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015/haskell')
for a,b in [('logs/build.log','first-build.log'),('phases.json','first-phases.json'),('run-phases.log','first-run-phases.log')]:
 t=h/b
 if not t.exists():shutil.copyfile(h/a,t)
print('first failure preserved')
