import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
parser=argparse.ArgumentParser()
parser.add_argument('--installed',type=Path,required=True)
parser.add_argument('--out',type=Path,required=True)
args=parser.parse_args()
args.out.mkdir()
ctypes.CDLL(None,use_errno=True).prctl(36,1,0,0,0)
rows=[]
for scenario in ['empty-argument','single-cancellation','repeated-cancellation']:
    root=args.out/scenario
    shutil.copytree(args.installed/'cpp',root,ignore=shutil.ignore_patterns('devkit'))
    runner=root/'counter_runner.py'
    runner.write_text('''import json,os,signal,sys,time
from pathlib import Path
request=Path(sys.argv[sys.argv.index('--request')+1])
mode=sys.argv[1]
signal.signal(signal.SIGTERM,signal.SIG_IGN)
ready=request.parent/'runner-control.json'
temp=ready.with_suffix('.tmp')
temp.write_text(json.dumps({'pid':os.getpid(),'pgid':os.getpgrp(),'hostPid':os.getppid(),'argv':sys.argv[1:]}))
temp.replace(ready)
print('public-runner-ready',flush=True)
time.sleep(0.1 if mode=='' else 10)
''')
    project=root/'project.json'
    data=json.loads(project.read_text())
    data['command']['args']=[{'literal':'' if scenario=='empty-argument' else scenario}]
    for ref in data['artifacts']:
        if ref['path']=='counter_runner.py':ref['sha256']=sha(runner)
    project.write_text(json.dumps(data,sort_keys=True,separators=(',',':'))+'\n')
    binary=root/'bin/mirrors-dpm'
    doctor=subprocess.run([str(binary),'doctor','--project',str(project),'--project-sha256',sha(project)],capture_output=True,text=True,timeout=20)
    (root/'doctor.log').write_text(doctor.stdout+doctor.stderr)
    assert doctor.returncode==0,(scenario,doctor.stderr)
    output=root/'public-run'
    child=subprocess.Popen([str(binary),'replay','--project',str(project),'--project-sha256',sha(project),
        '--candidate',data['baseline'],'--out',str(output)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
    runner_identity=None
    try:
        deadline=time.monotonic()+10
        while runner_identity is None:
            for ready in output.rglob('runner-control.json') if output.exists() else []:
                runner_identity=json.loads(ready.read_text())
                break
            if child.poll() is not None or time.monotonic()>deadline:raise RuntimeError('public runner not reached: '+scenario)
            time.sleep(.005)
        if scenario!='empty-argument':
            os.kill(runner_identity['hostPid'],signal.SIGTERM)
            if scenario=='repeated-cancellation':
                time.sleep(.025)
                for signum in [signal.SIGTERM,signal.SIGINT,signal.SIGTERM]:os.kill(runner_identity['hostPid'],signum)
        stdout,stderr=child.communicate(timeout=5)
        (root/'public.stdout.log').write_bytes(stdout)
        (root/'public.stderr.log').write_bytes(stderr)
        assert child.returncode==2,(scenario,child.returncode)
        assert not Path('/proc/'+str(runner_identity['pid'])).exists(),runner_identity
        if scenario=='empty-argument':assert runner_identity['argv'][0]==''
        else:assert b'operation cancelled' in stderr,stderr
        rows.append({'scenario':scenario,'status':'passed','doctorExit':doctor.returncode,
                     'exit':child.returncode,'runner':runner_identity,'runnerAbsentAfterReturn':True})
    finally:
        if child.poll() is None:
            os.killpg(child.pid,signal.SIGKILL);child.wait()
        if runner_identity is not None:
            try:os.killpg(runner_identity['pgid'],signal.SIGKILL)
            except ProcessLookupError:pass
        while True:
            try:
                pid,_=os.waitpid(-1,os.WNOHANG)
                if not pid:break
            except ChildProcessError:break
(args.out/'acceptance.json').write_text(json.dumps(rows,indent=2)+'\n')
print(json.dumps(rows),flush=True)
