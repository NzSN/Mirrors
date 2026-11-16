"""Transfer and run native renewed-chain trials inside the tested Windows Job wrapper."""
from common import *
import sys


def main():
    suffix=sys.argv[1] if len(sys.argv)>1 else ''
    # Native Python isolated mode omits the script directory; use an explicit
    # trusted module path in the task-owned driver, never ambient PYTHONPATH.
    trial=(PLAN/'trial-production-trust.py').read_text()
    trial=trial.replace('from production_health import',"import sys\nsys.path.insert(0,r'D:\\ModelMirrors\\staging\\completion-rc12-20261116')\nfrom production_health import")
    generated=OUT/('trial-production-trust'+suffix+'.py')
    with generated.open('x') as stream:stream.write(trial)
    health=OUT/'production_health.py'
    if health.exists():assert health.read_text()==(PLAN/'production-health.py').read_text()
    else:
        with health.open('x') as stream:stream.write((PLAN/'production-health.py').read_text())
    scp=['scp','-F',str(Path.home()/'.ssh/config'),'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes']
    wrapper='trial-production-trust'+suffix+'.ps1'
    run('production-trial-helper-transfer'+suffix,scp+[generated,health,PLAN/'production-health.py',PLAN/wrapper,'win10:D:/ModelMirrors/staging/completion-rc12-20261116/'],timeout=180)
    raw=run('production-renewed-trust-trials'+suffix,SSH+['powershell','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',STAGE.replace('\\','/')+'/'+wrapper],timeout=1200)
    value,end=json.JSONDecoder().raw_decode(raw)
    assert raw[end:].strip()=='TASK JOB CLEANUP active=0'
    assert len(value['cases'])==2 and all(c['health']['status']=='passed' for c in value['cases'])
    assert value['trialPortsNotListeningAfterward'] and not value['productionModified']
    value['ownedJobCleanupActive']=0
    write(PLAN/'production-trust-trials.json',value)
    print('CANDIDATE AND ROLLBACK PASS FOUR-WAY MTLS AND WRONG-PIN CONTROLS UNDER RENEWED CHAIN',flush=True)


if __name__=='__main__':main()
