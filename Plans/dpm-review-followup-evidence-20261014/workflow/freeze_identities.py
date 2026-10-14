import hashlib
import json
from pathlib import Path
import shutil
import subprocess

source=Path('/home/jlc/Tools/mirrors-dpm-followup-20261014/source/Mirrors')
build=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/followup-20261014')
directory=build/'generated-identities'
directory.mkdir()
names=['Shell/Dpm/HostIdentity.lean','tools/deterministic-scheduling/install_cli.py','tools/deterministic-scheduling/check_cli_installed.py']
rows={}
for name in names:
    file=source/name
    shutil.copy2(file,directory/file.name)
    rows[name]=hashlib.sha256(file.read_bytes()).hexdigest()
old_launcher=Path('/home/jlc/Tools/mirrors-dpm-remediation-20261013/source/Mirrors/.lake/build/bin/mirrors_dpm')
control=build/'stale-launcher-control'
(control/'bin').mkdir(parents=True)
helpers=control/'share/mirrors-dpm';helpers.mkdir(parents=True)
shutil.copy2(old_launcher,control/'bin/mirrors-dpm')
for name in ['cli.py','dpm_host.py','timeline.py']:shutil.copy2(source/'tools/deterministic-scheduling'/name,helpers/name)
completed=subprocess.run([str(control/'bin/mirrors-dpm'),'--help'],capture_output=True,timeout=20)
(control/'stdout.log').write_bytes(completed.stdout)
(control/'stderr.log').write_bytes(completed.stderr)
assert completed.returncode==2 and b'DPM host artifact differs' in completed.stderr
record={'status':'passed','exit':completed.returncode,'oldLauncherSha256':hashlib.sha256(old_launcher.read_bytes()).hexdigest(),
        'oldInstallationMutated':False,'selectedGeneratedFiles':rows}
(build/'identity-refresh.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record),flush=True)
