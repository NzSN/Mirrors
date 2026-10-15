import json,subprocess
from pathlib import Path
root=Path('/home/jlc/Tools/mirrors-client-fixes-20261015')
build=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015')
for name in ['npm','npx']:
    destination=root/'tools/bin'/name
    assert not destination.exists()
    destination.symlink_to(root/'tools/node/bin'/name)
versions={name:subprocess.check_output([str(root/'tools/node/bin/node'),str(root/'tools/node/bin'/name),'--version'],text=True).strip() for name in ['npm','npx']}
(build/'node-cli-paths.json').write_text(json.dumps({'status':'private-tool-paths-fixed','versions':versions,'systemToolsModified':False},indent=2)+'\n')
print(json.dumps(versions),flush=True)
