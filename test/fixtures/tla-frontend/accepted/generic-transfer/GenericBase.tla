---- MODULE GenericBase ----

EXTENDS Integers

VARIABLES
    sourceRecords,
    sourceCursor,
    sourceLimit,
    targetRecords,
    targetCursor,
    targetLimit,
    transferJournal,
    transferCursor,
    auditTrail,
    auditCursor,
    batchBuffer,
    batchCount

BaseInit ==
    /\ sourceRecords = {}
    /\ sourceCursor = 0
    /\ sourceLimit = 0
    /\ targetRecords = {}
    /\ targetCursor = 0
    /\ targetLimit = 0
    /\ transferJournal = {}
    /\ transferCursor = 0
    /\ auditTrail = {}
    /\ auditCursor = 0
    /\ batchBuffer = {}
    /\ batchCount = 0

BaseUnchanged ==
    UNCHANGED <<sourceRecords, sourceCursor, sourceLimit, targetRecords,
                targetCursor, targetLimit, transferJournal, transferCursor,
                auditTrail, auditCursor, batchBuffer, batchCount>>

====
