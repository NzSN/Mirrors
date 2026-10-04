#!/usr/bin/env python3
"""Capture the declared counter/native oracle cases through an approved service."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[3]

def main():
    p=argparse.ArgumentParser();p.add_argument('--context',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--host',default='172.20.208.1');p.add_argument('--port',default='8999');p.add_argument('--mirror',type=Path,default=ROOT/'.lake/build/bin/mirror');p.add_argument('--prepared',type=Path,default=ROOT/'Plans/dpm2-dpm5-qualified-20261004/native-prepared');p.add_argument('--fixture',type=Path,default=ROOT/'test/fixtures/deterministic-scheduling');p.add_argument('--shared-server-root',default=r'C:\Users\ayden\Desktop\Workspace\MirrorsRemote\trace-artifacts');p.add_argument('--shared-local-root',default='/mnt/c/Users/ayden/Desktop/Workspace/MirrorsRemote/trace-artifacts');a=p.parse_args();a.out.mkdir(parents=True,mode=0o700,exist_ok=False)
    context=json.loads(a.context.read_text());connection=['--host',a.host,'--port',a.port,'--tls','--cert',context['MIRRORS_REMOTE_CLIENT_CERT'],'--key',context['MIRRORS_REMOTE_CLIENT_KEY'],'--ca',context['MIRRORS_REMOTE_CA'],'--pin',context['MIRRORS_REMOTE_SERVER_PIN']]
    before=hashlib.sha256(a.mirror.read_bytes()).hexdigest();rows=[]
    for folder in ['counter','native','validation']:(a.out/folder).mkdir()
    def invoke(command,log):
        with log.open('w') as stream:result=subprocess.run([str(a.mirror.resolve()),*command],stdout=stream,stderr=subprocess.STDOUT,timeout=360)
        if result.returncode:raise RuntimeError('oracle operation failed; inspect '+str(log))
    for name,init,next_ in [('serial','Init','NextSerial'),('overlap','Init','NextOverlap'),('serial-five','InitFive','NextSerial'),('overlap-five','InitFive','NextOverlap')]:
        target=a.out/'counter'/name
        invoke(['trace-gen',*connection,'--spec',str((a.fixture/'ScheduledCounter.tla').resolve()),'--bound','6','--param-var','parameters','--init',init,'--next',next_,'--inv','TraceComplete','--num-traces','1','--out',str(target.resolve())],a.out/'counter'/(name+'.log'))
        value=json.loads((target/'trace-0.itf.json').read_text());initial=5 if name.endswith('five') else 0;final=initial+(1 if name.startswith('overlap') else 2)
        assert value['states'][0]['count']=={'#bigint':str(initial)} and value['states'][-1]['count']=={'#bigint':str(final)},'capture does not implement declared counter scenario'
        rows.append({'scope':'counter','case':name,'capture':str(target.relative_to(a.out))});print(name,'fresh capture checked',flush=True)
    for init in ['Init','InitFive']:
        log=a.out/'validation'/('counter-'+init+'.log');invoke(['validate',*connection,'--spec',str((a.fixture/'ScheduledCounter.tla').resolve()),'--bound','6','--init',init,'--next','Next','--inv','Safety'],log)
        assert 'VALID' in log.read_text().splitlines();rows.append({'scope':'counter-safety','initializer':init,'bound':6,'verdict':'VALID'})
    for name in ['stable-t1','stable-t2','overlap-t1','overlap-t2']:
        directory=a.prepared/name;count=len(json.loads((directory/'mapping.json').read_text())['modelSteps']);model=directory/'WriteSentryPhaseRun.tla';base=[*connection,'--spec',str(model.resolve()),'--bound',str(count),'--cinit','RunConstInit','--init','MBTInit','--next','MBTNext']
        target=a.out/'native'/name
        invoke(['trace-gen',*base,'--inv','MBTTraceIncomplete','--param-var','parameters','--num-traces','1','--out',str(target.resolve()),'--shared-server-root',a.shared_server_root,'--shared-local-root',a.shared_local_root],a.out/'native'/(name+'.log'))
        assert len(json.loads((target/'trace-0.itf.json').read_text())['states'])==count+1,'native capture stopped before complete plan'
        log=a.out/'validation'/(name+'.log');invoke(['validate',*base,'--inv','MBTSafety'],log);assert 'VALID' in log.read_text().splitlines()
        rows.append({'scope':'native','case':name,'capture':str(target.relative_to(a.out)),'bound':count,'invariant':'MBTSafety','verdict':'VALID'});print(name,'fresh capture and bounded safety checked',flush=True)
    assert hashlib.sha256(a.mirror.read_bytes()).hexdigest()==before,'CLI binary changed during capture'
    (a.out/'acceptance.json').write_text(json.dumps({'schema':'mirrors.dpm-language-oracles/v1','status':'passed','cliSha256':before,'rows':rows,'scope':'four counter and four fixed native cases; six bounded safety checks','localModelCheckerInvocations':0},indent=2)+'\n')

if __name__=='__main__':main()
