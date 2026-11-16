"""Compare authentic Lean/Haskell replay receivers; synthetic plumbing and real input modes stay distinct."""
import copy
import tarfile
import sys
from common import *

APP=Path('/home/lsz/Codebase/DumpLedger')
HSROOT=ROOT/'.golden-build/completion-20261029/ModelMirrors'
HSBIN=HSROOT/'dist-newstyle/build/x86_64-linux/ghc-9.14.1/ModelMirrors-0.1.1.0/x/ModelMirrors/build/ModelMirrors/ModelMirrors'
SOURCE_REF='6882d5b8b4787977e847e5a77467b30bfdac19a2'
HS_REF='4aa693f86e18349bb97c050dd33aecbf730b6fa2'
ACTIONS=['Init','IssueToken','BeginUpload','SealUpload','PromoteObject','MarkQuarantined','AcceptDump']


def main():
    plumbing='--plumbing-only' in sys.argv
    kind='synthetic-plumbing' if plumbing else 'production-input-replay'
    suffix='-v2' if '--attempt-v2' in sys.argv else ''
    out=OUT/(kind+suffix);out.mkdir(mode=0o700,parents=True)
    original=APP/'test/fixtures/mbt/traces/01-accepted-partial-delete.itf.json'
    source_raw=original.read_bytes();template=json.loads(source_raw)
    assert [state['action_taken'] for state in template['states'][:7]]==ACTIONS
    template['states']=template['states'][:7]
    trace=out/'accepted-partial-prefix.itf.json'
    trace.write_text(json.dumps(template,sort_keys=True,separators=(',',':'))+'\n')
    assert original.read_bytes()==source_raw
    hosted=ROOT/'.golden-build/completion-rc12-20261116/published-release'
    manifest=json.loads((hosted/'mirrors-v0.2.0-rc.12-linux-x86_64.build.json').read_text())
    assert manifest['commit']==SOURCE_REF
    lean=out/'mirror'
    with tarfile.open(hosted/'mirrors-v0.2.0-rc.12-linux-x86_64.tar.gz') as bundle:
        raw=bundle.extractfile('mirrors-v0.2.0-rc.12-linux-x86_64/bin/mirror').read()
    assert hashlib.sha256(raw).hexdigest()==manifest['binaries']['mirror']['sha256']
    with lean.open('xb') as stream:stream.write(raw)
    lean.chmod(0o700)
    assert subprocess.check_output(['git','-C',str(HSROOT),'rev-parse','HEAD'],text=True).strip()==HS_REF
    hs_sha=hashlib.sha256(HSBIN.read_bytes()).hexdigest()
    assert hs_sha=='843327b28f18c20608d8b56855ccba6e88ea406986ac1f17eb576bb8036a4b37'
    sentinel=out/'forbidden-model-backend'
    marker=out/'unexpected-model-execution'
    sentinel.write_text('#!/bin/sh\ntouch '+str(marker)+"\nexit 97\n")
    sentinel.chmod(0o700)
    env=dict(os.environ);env['APALACHE_MC']=str(sentinel)
    for name in ['APALACHE_JAR','TLA2TOOLS_JAR']:env.pop(name,None)
    if plumbing:
        reports=[]
        for state in template['states']:
            actual={key:value for key,value in state.items() if not key.startswith('#') and key not in ['action_taken','parameters']}
            reports.append(json.dumps({'proto_step':'report_state','state':actual},separators=(',',':')))
        datasets=[{'alias':'synthetic-expected-state-plumbing-only','reports':reports}]
    else:
        approval=json.loads((PLAN/'processing-approved.json').read_text())
        assert approval['approved'] and approval['destination']==str(OUT)
        producer=json.loads((OUT/'observation-producer.json').read_text())
        assert producer['totalObservationFrames']==21 and not producer['expectedTraceReadByProducer']
        datasets=[]
        for item in producer['selectedCandidates']:
            path=OUT/'observations'/item['artifact']['name']
            assert identity(path)['sha256']==item['artifact']['sha256']
            value=json.loads(path.read_text())
            assert value['alias']==item['alias'] and [frame['action'] for frame in value['frames']]==ACTIONS
            assert value['productionInspectionUsed'] and not value['previousExpectedStateSupplied']
            assert value['sessionsCreated']==value['sessionsClosed']==1 and value['engineCalls']==10
            datasets.append({'alias':value['alias'],'reports':[frame['report'] for frame in value['frames']]})
    registration={'proto_step':'register_traces','apalacheConfig':{'specPath':str(APP/'specs/DumpLedger.tla'),
        'invariant':'SafetyInvariant','lengthBound':6,'paramVars':'parameters'},'itfTracePaths':[str(trace)]}
    rows=[]
    for dataset in datasets:
        for negative in [False,True]:
            reports=list(dataset['reports'])
            if negative:
                changed=json.loads(reports[-1]);changed['state']['downloadable']={'#set':[]}
                reports[-1]=json.dumps(changed,separators=(',',':'))
            input_bytes=('\n'.join([json.dumps(registration,separators=(',',':')),*reports])+'\n').encode()
            outputs={}
            for name,binary in [('lean',lean),('haskell',HSBIN)]:
                label=dataset['alias']+('-tampered' if negative else '-actual')+'-'+name
                process=subprocess.run([str(binary)],input=input_bytes,capture_output=True,env=env,timeout=30)
                (out/(label+'.stdout')).write_bytes(process.stdout)
                (out/(label+'.stderr')).write_bytes(process.stderr)
                assert process.returncode==0,(label,process.returncode)
                messages=[json.loads(line) for line in process.stdout.splitlines() if line.strip()]
                verdicts=[message.get('proto_step') for message in messages]
                expected=['spec_validated','initial_state']
                for index in range(7):
                    expected.append('step_mismatch' if negative and index==6 else 'step_ok')
                    if index<6:expected.append('next_step')
                if not negative or name=='haskell':expected.append('all_steps_done')
                assert verdicts==expected,(label,verdicts)
                if negative:
                    assert verdicts.count('step_mismatch')==1,(label,verdicts)
                    mismatch=verdicts.index('step_mismatch')
                    assert verdicts[mismatch+1:]==(['all_steps_done'] if name=='haskell' else []),(label,verdicts)
                else:assert verdicts[-1]=='all_steps_done' and verdicts.count('step_ok')==7 and 'step_mismatch' not in verdicts,(label,verdicts)
                assert not process.stderr,(label,'unexpected stderr')
                outputs[name]={'raw':process.stdout,'messages':messages,'stdoutSha256':hashlib.sha256(process.stdout).hexdigest()}
            difference=None
            if negative:
                assert outputs['lean']['messages']==outputs['haskell']['messages'][:-1]
                tail=b'{"proto_step":"all_steps_done"}\n'
                assert outputs['haskell']['raw']==outputs['lean']['raw']+tail
                difference='documented C10: Haskell adds terminal all_steps_done after step_mismatch; Lean omits it'
            else:
                assert outputs['lean']['messages']==outputs['haskell']['messages'],'structured protocol divergence'
                assert outputs['lean']['raw']==outputs['haskell']['raw'],'unexplained wire byte divergence'
            rows.append({'alias':dataset['alias'],'tamperedObservationControl':negative,
                'inputFramesSha256':hashlib.sha256(input_bytes).hexdigest(),
                'repliesEqualThroughClientTerminal':True,'documentedDifference':difference,
                'rawRepliesByteIdentical':outputs['lean']['raw']==outputs['haskell']['raw'],
                'replyCounts':{name:len(value['messages']) for name,value in outputs.items()},
                'replySha256':{name:value['stdoutSha256'] for name,value in outputs.items()}})
    assert not marker.exists(),'a local model backend was invoked'
    assert hashlib.sha256(lean.read_bytes()).hexdigest()==manifest['binaries']['mirror']['sha256']
    assert hashlib.sha256(HSBIN.read_bytes()).hexdigest()==hs_sha
    assert original.read_bytes()==source_raw
    value={'schema':'mirrors.s8.paired-workload-replay/v1','mode':kind,
        'status':'paired-replay-outcomes-verified','datasets':len(datasets),'rows':rows,
        'leanSource':SOURCE_REF,'leanBinarySha256':manifest['binaries']['mirror']['sha256'],
        'haskellSource':HS_REF,'haskellBinarySha256':hs_sha,'reviewedTraceSourceSha256':hashlib.sha256(source_raw).hexdigest(),
        'derivedPrefixTrace':identity(trace),'expectedStatesSuppliedAsActual':plumbing,
        'realInputEvidenceClaimed':not plumbing,'freshModelChecking':False,'modelBackendInvoked':False,
        'unexplainedWireDivergences':0,'knownDifferenceContract':'Docs/client-implementation-guide.md C10 and Docs/interface-reference.md section 5',
        'fullWorkloadSoakOrCompatibilityCycleClaimed':False}
    write(out/'result.json',value)
    print(json.dumps(value,indent=2))


if __name__=='__main__':main()
