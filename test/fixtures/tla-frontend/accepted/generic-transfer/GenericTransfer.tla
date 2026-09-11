---- MODULE GenericTransfer ----

EXTENDS GenericBase

VARIABLES
    activeBatch,
    batchStage,
    stagedKey,
    stagedValue,
    retryCount,
    commitPending,
    verifyPending

TransferInit ==
    /\ BaseInit
    /\ activeBatch = {}
    /\ batchStage = "idle"
    /\ stagedKey = 0
    /\ stagedValue = 0
    /\ retryCount = 0
    /\ commitPending = FALSE
    /\ verifyPending = FALSE

TransferNext ==
    \/ ( UNCHANGED <<sourceRecords, sourceCursor, sourceLimit, targetRecords,
                     targetCursor, targetLimit, transferJournal, transferCursor,
                     auditTrail, auditCursor, batchBuffer, batchCount>>
         /\ activeBatch' = activeBatch
         /\ batchStage' = "staged"
         /\ UNCHANGED <<stagedKey, stagedValue, retryCount, commitPending, verifyPending>> )
    \/ ( BaseUnchanged
         /\ UNCHANGED <<activeBatch, batchStage, stagedKey, stagedValue,
                       retryCount, commitPending, verifyPending>> )

====
