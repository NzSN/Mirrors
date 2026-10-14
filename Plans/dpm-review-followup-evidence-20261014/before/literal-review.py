import hashlib, json, subprocess
from pathlib import Path
base=Path('/home/jlc/Tools/mirrors-dpm-remediation-20261013/installed-final/cpp')
out=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/new-review/literal-spec')
out.mkdir(parents=True,exist_ok=True)
project=json.loads((base/'project.json').read_text())
rows=[]
for name,literal in [('normal','placeholder'),('empty','')]:
    value=json.loads(json.dumps(project))
    value['command']['args'].append({'literal':literal})
    path=out/(name+'.json');path.write_text(json.dumps(value)+'\n')
    p=subprocess.run([str(base/'bin/mirrors-dpm'),'_plan',str(path)],capture_output=True,text=True,timeout=30)
    rows.append({'name':name,'exit':p.returncode,'stderr':p.stderr,'stdout':p.stdout})
report={'test':'closed-v2-literal-argv-admission','rows':rows}
(out/'result.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
