import json,shutil
from pathlib import Path
root=Path('/home/jlc/Tools/mirrors-client-fixes-20261015')
build=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015')
old=Path('/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/python-evidence')
copied=root/'tools/python-evidence'
shutil.copytree(old,copied)
launcher=root/'tools/bin/python3'
assert launcher.is_symlink()
launcher.unlink()
launcher.write_text('''#!/bin/sh
export PYTHONDONTWRITEBYTECODE=1
if [ "${PYTHONPATH:-}" = "/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/python-evidence" ]; then
  export PYTHONPATH="/home/jlc/Tools/mirrors-client-fixes-20261015/tools/python-evidence"
fi
exec /home/jlc/.local/share/uv/python/cpython-3.12.14-linux-x86_64-gnu/bin/python3.12 "$@"
''')
launcher.chmod(0o755)
record={'status':'private-launcher-installed','runtimeVersionUnchanged':'3.12.14',
        'oldDependencyTreeReadOnly':str(old),'copiedDependencyTree':str(copied),
        'suppressBytecodeWrites':True,'productionOrOldToolBytesModified':False}
(build/'python-environment-guard.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record),flush=True)
