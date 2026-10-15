import hashlib,json,os,shutil,subprocess
from pathlib import Path
root=Path('/home/jlc/Tools/mirrors-client-fixes-20261015')
build=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015')
frozen=json.loads((build/'frozen-mirror-producer.json').read_text())
binary=Path(frozen['mirrorPath']);assert hashlib.sha256(binary.read_bytes()).hexdigest()==frozen['mirrorSha256']
script=root/'source/Mirrors/tools/check-client-framing.py'
assert hashlib.sha256(script.read_bytes()).hexdigest()=='fe2b77b8e24bdff58f9b08dc1b594174ce2b0ece765fab76a382e4fbc7df0dca'
env={**os.environ,'TMPDIR':'/tmp/fix-tests','PYTHONDONTWRITEBYTECODE':'1'}
command=[str(root/'tools/bin/python3'),str(script),'--mirror',str(binary)]
with (build/'logs/framing-final-producer.log').open('wb') as output:
    completed=subprocess.run(command,cwd=root/'source/Mirrors',env=env,stdout=output,stderr=subprocess.STDOUT,timeout=180)
assert completed.returncode==0,completed.returncode
probe=build/'frozen-cli-original-probe';shutil.copytree(build/'postfix-probes/cli-probes',probe)
reference=probe/'source-reference.json';selection=json.loads(reference.read_text())
for row in selection['files']:row['sha256']=hashlib.sha256((root/'source/Mirrors'/row['path']).read_bytes()).hexdigest()
reference.write_text(json.dumps(selection,indent=2)+'\n')
work=build/'frozen-cli-original-work';work.mkdir()
audit_command=[str(root/'tools/bin/python3'),str(probe/'probe.py'),'--mirror',str(binary),
    '--source-root',str(root/'source/Mirrors'),'--work-root',str(work)]
result=subprocess.run(audit_command,capture_output=True,env=env,timeout=90)
(build/'logs/frozen-original-cli.stdout.json').write_bytes(result.stdout)
(build/'logs/frozen-original-cli.stderr.log').write_bytes(result.stderr)
assert result.returncode==0,result.stderr.decode()
raw=json.loads(result.stdout)
assert raw['valid_lf_control_passed'] and raw['all_owned_processes_reaped']
assert not raw['missing_lf_finding_reproduced'] and not raw['post_terminal_cancel_finding_reproduced']
assert hashlib.sha256(binary.read_bytes()).hexdigest()==frozen['mirrorSha256']
record={'status':'passed','mirrorPath':str(binary),'mirrorSha256':frozen['mirrorSha256'],
    'framingGateCommand':command,'framingGateSha256':hashlib.sha256(script.read_bytes()).hexdigest(),
    'framingGatePostCiTestOnlyPortabilityDelta':True,'auditProbeCommand':audit_command,
    'sourceReferenceOverlaySha256':hashlib.sha256(reference.read_bytes()).hexdigest(),
    'auditWorkRoot':raw['work_root'],'noFurtherWritesToProducer':True}
(build/'frozen-cli-checks.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2),flush=True)
