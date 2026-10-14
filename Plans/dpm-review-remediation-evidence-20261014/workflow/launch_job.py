import json
import os
from pathlib import Path
import re
import subprocess
import sys
root=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013')
name=sys.argv[1]
if not re.fullmatch(r'[a-z0-9-]{1,40}',name):raise ValueError('invalid owned job name')
script=root/sys.argv[2]
if script.parent!=root or not script.is_file():raise ValueError('job must use transferred script')
record=root/'build'/(name+'.job.json')
if record.exists():raise RuntimeError('existing job record preserved')
with (root/'build/logs'/(name+'.launcher.log')).open('xb') as output:
    child=subprocess.Popen(['/usr/bin/timeout','--signal=TERM','--kill-after=10s','3600',
        '/bin/bash',str(script)],stdin=subprocess.DEVNULL,stdout=output,stderr=subprocess.STDOUT,
        cwd=root,start_new_session=True)
data={'schema':'mirrors.dpm-owned-remote-build/v1','name':name,'pid':child.pid,'pgid':child.pid,
      'script':str(script),'timeoutSeconds':3600,'host':'remote-windows-dev-wsl'}
record.write_text(json.dumps(data,indent=2)+'\n')
print(json.dumps(data))
