#!/usr/bin/env python3
"""Independent DPM acceptance for ECMA/Rust consumers; no local model checking."""
import argparse
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess

ROOT=Path(__file__).resolve().parents[3]

def require(ok,message):
    if not ok: raise RuntimeError(message)
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def load(path):return json.loads(Path(path).read_text())
def write(path,value):Path(path).write_text(json.dumps(value,indent=2)+'\n')
def cmd(args):return [args.node,str(args.runner.resolve())] if args.language=='ecma' else [str(args.runner.resolve())]
def run(command,log,timeout=90,env=None):
    with Path(log).open('w') as stream:return subprocess.run(command,stdout=stream,stderr=subprocess.STDOUT,timeout=timeout,env=env)
def describe(args,mapping,extra=()):
    result=subprocess.run([*cmd(args),'--describe','--mapping',str(mapping),*extra],capture_output=True,text=True,timeout=30)
    require(result.returncode==0,'consumer description failed: '+result.stderr[-1000:]);return json.loads(result.stdout)
def counter_mapping(profile):return {'schema':'mirrors.dpm-counter-mapping/v1','profile':profile,'actors':[{'actor':'a','operation':'increment-a'},{'actor':'b','operation':'increment-b'}],'actions':{'read':'read','write':'write','finish':'$done'}}
def forbidden(out):
    sentinel=out/'forbidden-model-check';sentinel.write_text('#!/usr/bin/env python3\nfrom pathlib import Path\n(Path(__file__).parent/"model-check-invoked").write_text("unexpected")\nraise SystemExit(97)\n');sentinel.chmod(0o700)
    env=dict(os.environ,APALACHE_MC=str(sentinel.resolve()));env.pop('APALACHE_JAR',None);env.pop('TLA2TOOLS_JAR',None);return env

def peers(out,mirror):
    done=out/'empty-peer';done.write_text('''#!/usr/bin/env python3
import json,sys
request=json.loads(sys.stdin.readline());mi=request['modelInterface']
print(json.dumps({'proto_step':'spec_validated','result':'valid','modelInterface':{'schema':'mirrors.model-interface-negotiation/v1','status':'matched','descriptorSchema':'mirrors.model-interface-descriptor/v1','semanticDigest':mi['expectedSemanticDigest']}}),flush=True)
print('{"proto_step":"all_steps_done"}',flush=True)
''');done.chmod(0o700)
    for name in ['early-eof','malformed-input']:
        path=out/(name+'-peer')
        path.write_text('''#!/usr/bin/env python3
import json,sys,subprocess
from pathlib import Path
peer=subprocess.Popen(['''+repr(str(mirror.resolve()))+'''],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
try:
 peer.stdin.write(sys.stdin.readline());peer.stdin.flush()
 for _ in range(2):
  line=peer.stdout.readline()
  if not line:raise RuntimeError('peer closed before initialization')
  print(line.rstrip('\\n'),flush=True)
 initial=sys.stdin.readline()
 if json.loads(initial).get('proto_step')!='report_state':raise RuntimeError('actual initial report missing')
 peer.stdin.write(initial);peer.stdin.flush()
 if '''+repr(name)+'''=='malformed-input':
  for _ in range(3):
   line=peer.stdout.readline()
   if not line:raise RuntimeError('peer closed before next action')
   message=json.loads(line)
   if message.get('proto_step')=='next_step':
    message['parameters']={'parameters':{'actor':{'#bigint':'7'}}}
    print(json.dumps(message),flush=True)
    sys.stdin.readline()
    break
   print(line.rstrip('\\n'),flush=True)
finally:
 peer.stdin.close()
 try:peer.wait(timeout=3)
 except subprocess.TimeoutExpired:peer.terminate();peer.wait(timeout=3)
 (Path(__file__).parent/('''+repr(name)+'''+'-child-reaped')).write_text(str(peer.returncode))
''');path.chmod(0o700)

def check_counter(args,out):
    out.mkdir();profile='mirrorecma.worker-checkpoints/v1' if args.language=='ecma' else 'mirrorrust.cooperative-checkpoints/v1';mapping=out/'mapping.json';write(mapping,counter_mapping(profile));identity=describe(args,mapping)['identity'];peers(out,args.mirror);env=forbidden(out)
    modes=['ok','mutate','teardown-fail','mutate-and-teardown-fail','wrong-identity','denied-negotiation','unexpected-checkpoint','cancel','bad-observation','malformed-input','reentrant','early-done','early-eof','repeat','oracle-init-not-adopted'];rows=[]
    for case,initial,final in [('serial',0,2),('overlap',0,1),('serial-five',5,7),('overlap-five',5,6)]:
        trace=args.counter_oracles/case/'trace-0.itf.json';model=load(trace);require(model['states'][0]['count']=={'#bigint':str(initial)} and model['states'][-1]['count']=={'#bigint':str(final)},'oracle scenario does not implement declared schedule')
        steps=[{'actor':s['parameters']['actor'],'checkpoint':counter_mapping(profile)['actions'][s['action_taken']]}for s in model['states'][1:]]
        for mode in modes:
            name=case+'-'+mode;directory=out/name;directory.mkdir();fixture_mode='ok' if mode in ['wrong-identity','early-done','early-eof','repeat','oracle-init-not-adopted','malformed-input'] else mode
            schedule={'schema':'mirrors.checkpoint-schedule/v1','profile':profile,'identity':copy.deepcopy(identity),'inputs':{'initial':initial,'mode':fixture_mode},'steps':steps}
            if mode=='wrong-identity':schedule['identity']['mappingSha256']='f'*64
            schedule_path=directory/'schedule.json';write(schedule_path,schedule);report=directory/'receipt.json'
            selected=trace
            if mode=='oracle-init-not-adopted':value=copy.deepcopy(model);value['states'][0]['count']={'#bigint':str(initial+100)};value.setdefault('#meta',{})['negativeControl']='Deliberately corrupted initial state; not an oracle capture';selected=directory/'wrong-initial.itf.json';write(selected,value)
            peer=out/'empty-peer' if mode=='early-done' else out/(mode+'-peer') if mode in ['early-eof','malformed-input'] else args.mirror
            repeats=2 if mode=='repeat' else 1
            command=[*cmd(args),'--kind','counter','--mirror',str(peer.resolve()),'--spec',str((args.fixture/'ScheduledCounter.tla').resolve()),'--trace',str(selected.resolve()),'--mapping',str(mapping.resolve()),'--schedule',str(schedule_path.resolve()),'--out',str(report.resolve()),'--repeats',str(repeats)]
            result=run(command,directory/'run.log',env=env);require(result.returncode==0,name+': runner failed; see run.log');value=load(report);binding=value['binding'];executions=binding['executions'];sut=value['sut']
            if mode in ['denied-negotiation','early-done','wrong-identity']:
                require(value['passed'] is False and sut=={'acquisitions':0,'enteredWorkers':0,'teardowns':0},name+': refusal acquired SUT or passed')
                if mode=='wrong-identity':require(len(executions)==1 and executions[0]['outcome']=='incompatible_identity',name+': identity refusal missing')
            else:
                require(binding['disposals']==1 and binding['disposed'] is True and binding['receiptComplete'] is True,name+': binding ownership differs')
                require(sut['acquisitions']==sut['teardowns']==repeats and len(executions)==repeats,name+': acquisition/cleanup denominator differs')
                require(all(e['remainingActors']==[] for e in executions),name+': unjoined actors')
                if mode in ['ok','repeat']:
                    require(value['passed'] is True and value['comparison']=='matched' and all(e['passed'] for e in executions),name+': actual generated replay did not match')
                    require(sut['enteredWorkers']==2*repeats,name+': worker denominator differs')
                else:
                    require(value['passed'] is False,name+': negative passed')
                    if mode in ['mutate','mutate-and-teardown-fail','oracle-init-not-adopted']:
                        require(value['comparison']=='step_mismatch' and value['client']['kind']=='step_mismatch' and value['client']['expected']!=value['client']['actual'] and value['client']['orderedHints'],name+': real comparison failure missing')
                    elif mode=='teardown-fail':require(value['comparison']=='matched',name+': peer verdict lost')
                    else:require(value['comparison']=='incomplete',name+': non-comparison failure mislabeled')
                    if mode in ['malformed-input','reentrant']:require(sut['enteredWorkers']==0 and executions[0]['events']==[],name+': invalid/reentrant callback released an actor')
                    if mode=='malformed-input':require(value['client'].get('code')=='input_shape_mismatch',name+': input codec changed')
                    if mode=='unexpected-checkpoint':require(executions[0]['outcome']=='unexpected_checkpoint',name+': phase mismatch missing')
                    if mode=='cancel':require(executions[0]['outcome']=='cancelled',name+': cancellation missing')
                    if mode=='oracle-init-not-adopted':require(value['client']['actual']['count']=={'#bigint':str(initial)},name+': expected state leaked into implementation')
                cleanup='teardown_failed' if mode in ['teardown-fail','mutate-and-teardown-fail'] else 'confirmed'
                require(all(e['cleanup']==cleanup for e in executions),name+': cleanup evidence differs')
            if mode in ['early-eof','malformed-input']:require((out/(mode+'-child-reaped')).exists(),name+': comparison child not reaped')
            rows.append({'case':name,'status':'passed','receipt':str(report.relative_to(out)),'sha256':sha(report),'traceSha256':sha(selected)})
        print(args.language,case,'15 counter cases passed',flush=True)
    require(not (out/'model-check-invoked').exists(),'offline replay invoked a model checker');write(out/'acceptance.json',{'schema':'mirrors.dpm-language-counter/v1','language':args.language,'status':'passed','rows':rows,'freshOracles':False,'oracleProvenance':'inspect supplied capture manifests; no new capture is inferred by replay'})

def check_exploration(args,out):
    out.mkdir();profile='mirrorecma.worker-checkpoints/v1' if args.language=='ecma' else 'mirrorrust.cooperative-checkpoints/v1';mapping=out/'mapping.json';write(mapping,counter_mapping(profile))
    helper=Path(__file__).parents[1]/'check_exploration.py';spec=importlib.util.spec_from_file_location('independent_exploration',helper);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    cases=[('all',[],64),('zero-preemptions',['--preemptions','0'],0),('one-preemption',['--preemptions','1'],1),('two-preemptions',['--preemptions','2'],2),('run-limit',['--max-runs','3'],None),('enumeration-limit',['--max-enumerated','3'],None),('evidence-limit',['--evidence-bytes','1'],None),('cleanup-failure',['--fixture-mode','teardown-fail'],None),('schedule-failure',['--fixture-mode','unexpected-checkpoint'],None),('cancel',['--fixture-mode','cancel'],None),('comparison-required',['--require-comparison','true'],None)]
    rows=[]
    for name,extra,bound in cases:
        report=out/(name+'.json');result=run([*cmd(args),'--kind','explore','--mapping',str(mapping.resolve()),'--out',str(report.resolve()),*extra],out/(name+'.log'),timeout=120);require(result.returncode==0,name+': exploration runner failed');value=load(report)
        if bound is not None:module.positive(value,bound)
        else:
            require(value['complete'] is False,name+': false completeness')
            if name=='run-limit':require(value['stopReason']=='run_limit' and value['attemptedRuns']==3 and value['eligibleRuns']==40,'run cap differs')
            if name=='enumeration-limit':require(value['denominatorKnown'] is False and value['eligibleRuns'] is None and value['stopReason']=='enumeration_limit','unknown denominator hidden')
            if name=='evidence-limit':require(value['stopReason']=='evidence_limit','evidence cap hidden')
            if name=='cleanup-failure':require(value['stopReason']=='unconfirmed_cleanup' and value['attemptedRuns']==1,'unconfirmed cleanup did not halt')
            if name=='schedule-failure':require(value['categories']=={'schedule_failed':40} and value['firstCounterexample'] is None,'schedule failure misclassified')
            if name=='cancel':require(value['stopReason']=='cancelled' and value['attemptedRuns']==1,'cancellation differs')
            if name=='comparison-required':require(value['categories']=={'comparison_missing':40} and value['comparisonRuns']==0,'missing comparison accepted')
        require(sum(value['categories'].values())==value['attemptedRuns'],'attempt accounting differs');rows.append({'case':name,'status':'passed','report':report.name,'sha256':sha(report)});print(args.language,name,'exploration passed',flush=True)
    write(out/'acceptance.json',{'schema':'mirrors.dpm-language-exploration/v1','language':args.language,'status':'passed','rows':rows,'fullScopeRuns':40,'partialOrderReduction':'disabled','scope':'finite local execution and semantic coverage'})

def check_native(args,out):
    out.mkdir();env=forbidden(out);baseline={};identities=set();rows=[]
    cases=[(name,'normal-v3','ok')for name in ['stable-t1','stable-t2','overlap-t1','overlap-t2']for _ in range(2)]
    cases += [('stable-t1',build,'ok')for build in ['duplicate-sink-call','skip-hit-release']]
    cases += [('stable-t1','normal-v3',mode)for mode in ['cancel','wrong-image','crash-peer','unexpected-phase']]
    for index,(name,build,mode)in enumerate(cases):
        label=f'{index:02d}-{name}-{build}-{mode}';directory=out/label;directory.mkdir();model=args.prepared/name;mapping_path=model/'mapping.json';mapping=load(mapping_path);trace=args.native_oracles/name/'trace-0.itf.json'
        def norm(v):
            if isinstance(v,list):return [norm(x)for x in v]
            if isinstance(v,dict):
                if set(v)=={'#bigint'}:return int(v['#bigint'])
                return {k:norm(x)for k,x in v.items()if k!='nativeIdentity'}
            return v
        states=load(trace)['states'];require(len(states)==len(mapping['modelSteps'])+1 and [norm(s['parameters'])for s in states[1:]]==[s['parameters']for s in mapping['modelSteps']],'native oracle schedule differs')
        if mode=='unexpected-phase':
            require(mapping['modelSteps'][1]['parameters']['action']=='ArmLock','native control fixture changed');mapping['modelSteps'][1]['parameters']['action']='ArmSelect';mapping_path=directory/'negative-mapping.json';write(mapping_path,mapping)
            value=load(trace);value['states'][2]['action_taken']='ArmSelect';value['states'][2]['parameters']['action']='ArmSelect';value.setdefault('#meta',{})['negativeControl']='Deliberately incompatible phase; not an oracle capture';trace=directory/'negative-trace.itf.json';write(trace,value)
        worker=args.workers/build/'build/dpm_native_worker.exe';require(sha(worker)==load(args.workers/build/'build-receipt.json')['executableSha256'],'native image differs from build receipt')
        launcher=directory/'launch';script='#!/bin/sh\ncd '+shlex.quote(str(worker.resolve().parent))+' || exit 98\nexec '+shlex.quote(str(worker.resolve()))+'\n'
        if mode=='crash-peer':script='#!/bin/sh\ncd '+shlex.quote(str(worker.resolve().parent))+' || exit 98\nexec /usr/bin/python3 '+shlex.quote(str((Path(__file__).parents[1]/'native/terminate_peer.py').resolve()))+' '+shlex.quote(str(worker.resolve()))+' '+shlex.quote(str((directory/'terminated.json').resolve()))+'\n'
        launcher.write_text(script);launcher.chmod(0o700);extra=['--kind','native','--worker',str(worker.resolve()),'--launcher',str(launcher.resolve())];identity=describe(args,mapping_path,extra);steps=[]
        for s in mapping['modelSteps']:
            steps.append({'actor':s['role'],'checkpoint':s['parameters']['action']})
            if s['parameters']['action']=='CallDone':steps.append({'actor':s['role'],'checkpoint':'$done'})
        schedule=directory/'schedule.json';write(schedule,{'schema':'mirrors.checkpoint-schedule/v1','profile':identity['profile'],'identity':identity['identity'],'inputs':{},'steps':steps});report=directory/'receipt.json'
        result=run([*cmd(args),*extra,'--mirror',str(args.mirror.resolve()),'--spec',str((model/'WriteSentryMBT.tla').resolve()),'--trace',str(trace.resolve()),'--mapping',str(mapping_path.resolve()),'--schedule',str(schedule.resolve()),'--out',str(report.resolve()),'--mode','ok' if mode in ['crash-peer','unexpected-phase'] else mode],directory/'run.log',timeout=180,env=env)
        require(result.returncode==0,label+': native runner failed');value=load(report);native=value['native'];binding=value['binding'];require(native['acquisitions']==native['cleanups']==1 and native['closed'] is True,label+': native ownership differs');require(binding['disposals']==1 and binding['disposed'] is True,label+': disposal differs')
        if mode!='wrong-image':
            require(isinstance(native['identity'],dict),label+': native identity unavailable');ident=native['identity'];key=(ident['processId'],ident['createdFileTime']);require(key not in identities and ident['actors']['t1']!=ident['actors']['t2'] and ident['imageSha256']==sha(worker),'native identities invalid/reused');identities.add(key)
        execution=binding['executions'][0]
        if mode=='ok' and build=='normal-v3':
            require(value['passed'] is True and value['comparison']=='matched' and execution['scheduleCompleted'] is True,label+': native comparison failed');normalized=norm(native['transcript'])
            if name in baseline:require(normalized==baseline[name],label+': fresh-process replay changed')
            else:baseline[name]=normalized
        elif build!='normal-v3':require(value['passed'] is False and value['comparison']=='step_mismatch' and value['client']['kind']=='step_mismatch' and value['client']['expected']!=value['client']['actual'] and value['client']['orderedHints'],label+': production mutation not detected by actual comparer')
        else:
            require(value['passed'] is False and value['comparison']=='incomplete',label+': native failure accepted')
            if mode=='cancel':require(execution['outcome']=='cancelled',label+': cancellation missing')
            if mode=='unexpected-phase':require(execution['outcome']=='unexpected_checkpoint',label+': actual phase refusal missing')
            if mode=='crash-peer':require((directory/'terminated.json').exists() and execution['cleanup']=='teardown_failed' and native['exitCode']==41 and native['quitAcknowledged'] is False,label+': owned termination hidden')
        if mode not in ['wrong-image','crash-peer']:require(native['quitAcknowledged'] is True and native['exitCode']==0 and execution['cleanup']=='confirmed',label+': native cleanup not confirmed')
        rows.append({'case':label,'status':'passed','receipt':str(report.relative_to(out)),'sha256':sha(report),'workerSha256':sha(worker),'mappingSha256':sha(mapping_path),'traceSha256':sha(trace)});print(args.language,label,'passed',flush=True)
    compatibility=[]
    for mode in ['unknown-profile','extra-operation','unknown-actor']:
        directory=out/mode;directory.mkdir();mapping=load(args.prepared/'stable-t1/mapping.json')
        if mode=='unknown-profile':mapping['profile']='unsupported/v99'
        elif mode=='unknown-actor':mapping['roles']['arm']['nativeActor']='t3'
        else:mapping['modelSteps'].append(mapping['modelSteps'][0])
        mapping_path=directory/'mapping.json';write(mapping_path,mapping);sentinel=directory/'acquired';launcher=directory/'launch';launcher.write_text('#!/bin/sh\n: > '+shlex.quote(str(sentinel.resolve()))+'\nexit 99\n');launcher.chmod(0o700);report=directory/'receipt.json'
        result=run([*cmd(args),'--kind','native','--mapping',str(mapping_path.resolve()),'--schedule',str((out/rows[0]['case']/'schedule.json').resolve()),'--worker',str((args.workers/'normal-v3/build/dpm_native_worker.exe').resolve()),'--launcher',str(launcher.resolve()),'--mirror',str(args.mirror.resolve()),'--spec',str((args.prepared/'stable-t1/WriteSentryMBT.tla').resolve()),'--trace',str((args.native_oracles/'stable-t1/trace-0.itf.json').resolve()),'--out',str(report.resolve())],directory/'run.log',env=env)
        require(result.returncode!=0 and not sentinel.exists() and not report.exists(),mode+': incompatible mapping acquired SUT');compatibility.append({'case':mode,'status':'passed','nativeAcquisitions':0})
    require(not(out/'model-check-invoked').exists(),'native replay invoked local model checker');write(out/'acceptance.json',{'schema':'mirrors.dpm-language-native/v1','language':args.language,'status':'passed','profile':'dpm-writesentry-two-operation/v1','rows':rows,'compatibilityControls':compatibility,'fullProductionQualified':False})

def main():
    p=argparse.ArgumentParser();p.add_argument('--language',choices=['ecma','rust'],required=True);p.add_argument('--runner',type=Path,required=True);p.add_argument('--node',default='node');p.add_argument('--mirror',type=Path,default=ROOT/'.lake/build/bin/mirror');p.add_argument('--fixture',type=Path,default=ROOT/'test/fixtures/deterministic-scheduling');p.add_argument('--counter-oracles',type=Path,default=ROOT/'Plans/dpm2-dpm5-qualified-20261004/counter-oracles');p.add_argument('--prepared',type=Path,default=ROOT/'Plans/dpm2-dpm5-qualified-20261004/native-prepared');p.add_argument('--native-oracles',type=Path,default=ROOT/'Plans/dpm2-dpm5-qualified-20261004/native-oracles');p.add_argument('--workers',type=Path,default=Path('/mnt/c/Users/ayden/Desktop/Workspace/MirrorsRemote/dpm-20261004'));p.add_argument('--scope',choices=['counter','exploration','native','all'],default='all');p.add_argument('--out',type=Path,required=True);args=p.parse_args();args.out.mkdir(parents=True,exist_ok=False)
    for scope,check in [('counter',check_counter),('exploration',check_exploration),('native',check_native)]:
        if args.scope in [scope,'all']:check(args,args.out/scope)

if __name__=='__main__':main()
