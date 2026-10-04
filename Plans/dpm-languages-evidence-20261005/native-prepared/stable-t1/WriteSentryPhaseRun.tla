---- MODULE WriteSentryPhaseRun ----
EXTENDS WriteSentryMBT
RunConstInit ==
  /\ Threads={"t1","t2"} /\ Addresses={"A1","A2","A3"}
  /\ Values={"good","bad"} /\ WriterKinds={"allowed","other"}
  /\ SlotCount=4 /\ Budget=10
  /\ Plan = <<
    [action |-> "Reserve", thread |-> "t1", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"],
    [action |-> "ArmLock", thread |-> "t1", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"],
    [action |-> "ArmSelect", thread |-> "t1", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 0, target |-> "noThread"],
    [action |-> "PublishOdd", thread |-> "t1", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 0, target |-> "noThread"],
    [action |-> "PublishPayload", thread |-> "t1", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 0, target |-> "noThread"],
    [action |-> "PublishEven", thread |-> "t1", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 0, target |-> "noThread"],
    [action |-> "ArmUnlock", thread |-> "t1", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"],
    [action |-> "ArmTarget", thread |-> "t1", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 4, target |-> "t1"],
    [action |-> "ArmTarget", thread |-> "t1", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 4, target |-> "t2"],
    [action |-> "ArmFinishLock", thread |-> "t1", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"],
    [action |-> "ArmFinishUnlock", thread |-> "t1", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"],
    [action |-> "ArmOutcome", thread |-> "t1", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 0, target |-> "noThread"],
    [action |-> "Release", thread |-> "t1", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"],
    [action |-> "CallDone", thread |-> "t1", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"],
    [action |-> "WriteBegin", thread |-> "t1", command |-> "Write", address |-> "A1", value |-> "bad", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"],
    [action |-> "TrapEntry", thread |-> "t1", command |-> "Write", address |-> "A1", value |-> "bad", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"],
    [action |-> "SnapshotProbe", thread |-> "t1", command |-> "Write", address |-> "A1", value |-> "bad", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 4, target |-> "noThread"],
    [action |-> "SnapshotAdmissionChecked", thread |-> "t1", command |-> "Write", address |-> "A1", value |-> "bad", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 4, target |-> "noThread"],
    [action |-> "SnapshotLease", thread |-> "t1", command |-> "Write", address |-> "A1", value |-> "bad", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 4, target |-> "noThread"],
    [action |-> "SnapshotAdmissionValidated", thread |-> "t1", command |-> "Write", address |-> "A1", value |-> "bad", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 4, target |-> "noThread"],
    [action |-> "SnapshotSeq1", thread |-> "t1", command |-> "Write", address |-> "A1", value |-> "bad", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 4, target |-> "noThread"],
    [action |-> "SnapshotPayload", thread |-> "t1", command |-> "Write", address |-> "A1", value |-> "bad", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 4, target |-> "noThread"],
    [action |-> "SnapshotSeq2", thread |-> "t1", command |-> "Write", address |-> "A1", value |-> "bad", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 4, target |-> "noThread"],
    [action |-> "SnapshotAccepted", thread |-> "t1", command |-> "Write", address |-> "A1", value |-> "bad", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 4, target |-> "noThread"],
    [action |-> "Hit", thread |-> "t1", command |-> "Write", address |-> "A1", value |-> "bad", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 4, target |-> "noThread"],
    [action |-> "HitReleased", thread |-> "t1", command |-> "Write", address |-> "A1", value |-> "bad", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 4, target |-> "noThread"],
    [action |-> "WriteDone", thread |-> "t1", command |-> "Write", address |-> "A1", value |-> "bad", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"],
    [action |-> "CallDone", thread |-> "t1", command |-> "Write", address |-> "A1", value |-> "bad", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"]
    >>
====
