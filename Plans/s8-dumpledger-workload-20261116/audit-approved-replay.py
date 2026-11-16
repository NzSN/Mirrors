"""Audit the approved private replay and retain exact input streams without rerunning the SUT."""
import copy
from collections import Counter
from common import *


def main():
    approval=json.loads((PLAN/'processing-approved.json').read_text())
    producer=json.loads((OUT/'observation-producer.json').read_text())
    paired_path=OUT/'production-input-replay/result.json'
    paired=json.loads(paired_path.read_text())
    index_path=OUT/'implementation-index.json'
    index=json.loads(index_path.read_text())
    assert approval['approved'] and approval['destination']==str(OUT)
    assert paired['mode']=='production-input-replay' and not paired['expectedStatesSuppliedAsActual']
    assert paired['datasets']==3 and len(paired['rows'])==6 and paired['unexplainedWireDivergences']==0
    assert producer['totalObservationFrames']==21 and producer['ownedJobCleanupActive']==0
    assert producer['implementationFileCount']==len(index)==84
    assert hashlib.sha256(index_path.read_bytes()).hexdigest()==producer['implementationTreeIndexSha256']
    assert not producer['rawDumpBytesExported'] and not producer['productionDatabaseOpenedByReplay']
    assert not producer['expectedTraceReadByProducer']
    positives=[row for row in paired['rows'] if not row['tamperedObservationControl']]
    controls=[row for row in paired['rows'] if row['tamperedObservationControl']]
    assert len(positives)==len(controls)==3
    assert all(row['rawRepliesByteIdentical'] and row['documentedDifference'] is None for row in positives)
    assert all(row['repliesEqualThroughClientTerminal'] and row['documentedDifference'].startswith('documented C10:') for row in controls)
    assert {row['alias'] for row in positives}==set(approval['aliases'])
    registration={'proto_step':'register_traces','apalacheConfig':{
        'specPath':'/home/lsz/Codebase/DumpLedger/specs/DumpLedger.tla','invariant':'SafetyInvariant',
        'lengthBound':6,'paramVars':'parameters'},'itfTracePaths':[str(ROOT/paired['derivedPrefixTrace']['path'])]}
    state_hashes=set();input_hashes=set();input_bytes=0;engine_calls=0;artifacts=[]
    allowed={'analysisRecorded','blobState','caseStatus','coverage','digestRecorded','downloadable',
             'dumpCase','dumpPhase','dumpToken','symbolRegistered','tokenState','tokenUploads','validation'}
    for item in producer['selectedCandidates']:
        path=OUT/'observations'/item['artifact']['name']
        assert identity(path)['sha256']==item['artifact']['sha256']
        value=json.loads(path.read_text())
        assert value['productionInspectionUsed'] and not value['expectedTraceReadByProducer']
        assert not value['previousExpectedStateSupplied'] and not value['payloadBytesIncluded']
        assert value['sessionsCreated']==value['sessionsClosed']==1
        input_hashes.add(value['inputSha256']);input_bytes+=value['inputBytes'];engine_calls+=value['engineCalls']
        for frame in value['frames']:
            report=json.loads(frame['report']);assert report['proto_step']=='report_state'
            assert set(report['state'])==allowed
            state_hashes.add(hashlib.sha256(frame['report'].encode()).hexdigest())
        for row in [row for row in paired['rows'] if row['alias']==item['alias']]:
            reports=[frame['report'] for frame in value['frames']]
            if row['tamperedObservationControl']:
                changed=json.loads(reports[-1]);changed['state']['downloadable']={'#set':[]}
                reports[-1]=json.dumps(changed,separators=(',',':'))
            raw=('\n'.join([json.dumps(registration,separators=(',',':')),*reports])+'\n').encode()
            assert hashlib.sha256(raw).hexdigest()==row['inputFramesSha256']
            name=item['alias']+('-tampered' if row['tamperedObservationControl'] else '-actual')
            retained=paired_path.parent/(name+'.input.jsonl')
            with retained.open('xb') as stream:stream.write(raw)
            retained.chmod(0o600);artifacts.append(identity(retained))
            for comparator in ['lean','haskell']:
                stdout=paired_path.parent/(name+'-'+comparator+'.stdout')
                stderr=paired_path.parent/(name+'-'+comparator+'.stderr')
                assert identity(stdout)['sha256']==row['replySha256'][comparator]
                assert stderr.stat().st_size==0
                stdout.chmod(0o600);stderr.chmod(0o600)
    assert len(input_hashes)==3 and input_bytes==approval['totalInputBytes']==5889824
    assert len(state_hashes)==7 and engine_calls==30
    assert not (paired_path.parent/'unexpected-model-execution').exists()
    old=json.loads((ROOT/'Plans/completion-rc12-20261116/rc12-intake-final.json').read_text())['preservedUnrelatedFiles']
    for entry in old:assert identity(ROOT/entry['path'])==entry
    result={'schema':'mirrors.s8.approved-replay-audit/v1','status':'approved-bounded-production-input-replay-verified',
        'at':datetime.now(timezone.utc).isoformat(),'approvedInputCount':3,'distinctInputHashes':3,'inputBytes':input_bytes,
        'freshEngineSessions':3,'closedEngineSessions':3,'actualLifecycleTransitions':18,
        'syntheticModelContextSetupCommands':12,'totalEngineCommands':engine_calls,
        'observedStateFrames':21,'distinctModeledObservationFrames':7,
        'successfulPairedComparisons':3,'byteIdenticalSuccessPairs':3,'rejectedTamperedObservationControls':3,
        'receiverProcessExecutions':12,'documentedC10TailDifferences':3,'unexplainedWireDivergences':0,
        'immutableImplementationFilesIndexed':len(index),'productionDatabaseOpenedByReplay':False,
        'productionServiceOrDataMutated':False,'rawDumpBytesExported':False,'expectedStateUsedAsActual':False,
        'ownedJobCleanupActive':0,'freshModelChecking':False,
        'scope':'three production-retained one-shot partial-dump lifecycle slices; normalized finite IDs/timestamps; fresh in-memory SQLite and production parser; HTTP/auth/streaming/batch/other lifecycle paths excluded',
        'customerRealVersusTestOriginIndependentlyCertified':False,
        'historicalWireOrLongRunningSoakAcceptanceClaimed':False,'completeCompatibilityCyclesGranted':0,
        'consumerOwnershipOrMigrationAcknowledgementInferred':False,'publicPublicationApproved':False,
        'approval':identity(PLAN/'processing-approved.json'),'producer':identity(OUT/'observation-producer.json'),
        'pairedReplay':identity(paired_path),'implementationIndex':identity(index_path),'retainedExactInputStreams':artifacts,
        'preservedUnrelatedFiles':len(old)}
    write(OUT/'approved-replay-audit.json',result)
    print(json.dumps({key:item for key,item in result.items() if key not in ['approval','producer','pairedReplay','implementationIndex','retainedExactInputStreams']},indent=2))


if __name__=='__main__':main()
