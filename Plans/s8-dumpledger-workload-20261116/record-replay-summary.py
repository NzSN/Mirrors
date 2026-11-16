"""Record aggregate status only; private observations, source timestamps and hashes stay in OUT."""
from common import *


def main():
    audit=json.loads((OUT/'approved-replay-audit.json').read_text())
    after=json.loads((OUT/'after-replay-observation.json').read_text())
    assert audit['status']=='approved-bounded-production-input-replay-verified'
    assert audit['approvedInputCount']==3 and audit['unexplainedWireDivergences']==0
    assert after['ownedProducerCleanupConfirmed'] and after['selectedSourceAndModelBytesUnchanged']
    summary={'schema':'mirrors.s8.bounded-workload-replay-summary/v1',
        'status':'approved-three-input-engine-replay-and-paired-comparison-passed',
        'recordedAtUtc':datetime.now(timezone.utc).isoformat(),
        'inputScope':'three production-retained one-shot partial-dump lifecycle slices from deployed DumpLedger',
        'inputCount':3,'distinctInputs':3,'totalInputBytes':audit['inputBytes'],
        'freshEngineSessions':3,'closedEngineSessions':3,'lifecycleTransitions':18,
        'modelContextSetupCommands':12,'observedStateFrames':21,'distinctModeledObservationFrames':7,
        'byteIdenticalSuccessPairs':3,'tamperedObservationControlsRejectedByBoth':3,
        'knownC10MismatchTailCases':3,'unexplainedWireDivergences':0,
        'comparisonMode':'recorded observed state reports replayed against reviewed corpus prefix; not live coupled HTTP or a fresh model check',
        'expectedModelStateUsedAsActual':False,'realInspectorUsed':True,'sqliteMode':'fresh :memory: for each run',
        'implementationFilesIndexed':84,'sourceOverlaysAndSelectedCodeModelBytesPreserved':True,
        'ownedJobCleanupActive':0,'ownedProducerProcessesRemaining':0,'backendHealthAfterReplay':'HTTP 200',
        'rawDumpBytesExported':False,'productionDataOrServiceMutated':False,
        'privateEvidenceDirectory':str(OUT),
        'privateEvidenceFiles':['observation-producer.json','implementation-index.json',
            'observations/*.json','production-input-replay/result.json',
            'production-input-replay/*.input.jsonl','production-input-replay/*.stdout',
            'approved-replay-audit.json','after-replay-observation.json'],
        'privateProductionFieldsIncludedInThisSummary':False,'publicPublicationApproved':False,
        'fullSoakOrHistoricalWireAcceptanceClaimed':False,'completeCompatibilityCyclesGranted':0,
        'excludedCoverage':['HTTP and authentication','streaming upload byte admission','multi-slot/batch grants',
            'full-memory, unknown and rejected input classes','case workflows and later source actions','long-running or shipped-cycle soak'],
        'stillRequired':['declared per-consumer/transport coverage and owners',
            'broader real-workload and complete two-shipped-cycle records',
            'consumer migration acknowledgements and tested application fallback'],
        'retirementAdmitted':False}
    write(PLAN/'replay-summary.json',summary)
    write(PLAN/'lifecycle-progress.json',{'schema':'mirrors.s8.lifecycle-progress/v1',
        'workloadSourceProvided':True,'boundedPrivateProcessingApproved':True,'boundedRealInputReplayComplete':True,
        'scope':'three admitted one-shot partial-dump inputs; engine-level modeled projection only',
        'actualCompleteCompatibilityCyclesAccepted':0,'namedConsumerOwnersProvided':False,
        'migrationAcknowledgementsReceived':False,'fullHistoricalOrLongRunningSoakCreditGranted':False,
        'realVersusTestCustomerOriginIndependentlyCertified':False,'retirementAdmitted':False,
        'rawPrivateEvidencePublished':False})
    print(json.dumps({key:summary[key] for key in ['status','inputCount','observedStateFrames',
          'byteIdenticalSuccessPairs','tamperedObservationControlsRejectedByBoth','unexplainedWireDivergences',
          'rawDumpBytesExported','productionDataOrServiceMutated','completeCompatibilityCyclesGranted']},indent=2))


if __name__=='__main__':main()
