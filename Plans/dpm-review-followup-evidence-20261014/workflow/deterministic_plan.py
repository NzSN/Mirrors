import hashlib
import json
from pathlib import Path
import subprocess

build=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/followup-20261014')
binary=Path('/home/jlc/Tools/mirrors-dpm-followup-20261014/source/Mirrors/.lake/build/bin/mirrors_dpm')
project=build/'prepared-final/cpp/project.json'
outputs=[subprocess.check_output([str(binary),'_plan',str(project)],timeout=20) for _ in range(2)]
assert outputs[0]==outputs[1]
for index,output in enumerate(outputs):(build/('pure-plan-'+str(index)+'.json')).write_bytes(output)
(build/'pure-plan-determinism.json').write_text(json.dumps({'status':'passed','runs':2,
    'projectSha256':hashlib.sha256(project.read_bytes()).hexdigest(),
    'outputSha256':hashlib.sha256(outputs[0]).hexdigest(),'identicalBytes':True},indent=2)+'\n')
print('PURE_PLAN_TWO_RUNS_IDENTICAL')
