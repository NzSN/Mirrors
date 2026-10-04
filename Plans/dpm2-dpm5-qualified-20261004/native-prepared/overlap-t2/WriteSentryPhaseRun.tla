---- MODULE WriteSentryPhaseRun ----
EXTENDS WriteSentryMBT
RunConstInit ==
  /\ Threads={"t1","t2"} /\ Addresses={"A1","A2","A3"}
  /\ Values={"good","bad"} /\ WriterKinds={"allowed","other"}
  /\ SlotCount=4 /\ Budget=10
  /\ Plan = <<
    [action |-> "Reserve", thread |-> "t2", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"],
    [action |-> "ArmLock", thread |-> "t2", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"],
    [action |-> "ArmSelect", thread |-> "t2", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 0, target |-> "noThread"],
    [action |-> "PublishOdd", thread |-> "t2", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 0, target |-> "noThread"],
    [action |-> "WriteBegin", thread |-> "t1", command |-> "Write", address |-> "A1", value |-> "bad", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"],
    [action |-> "WriteDone", thread |-> "t1", command |-> "Write", address |-> "A1", value |-> "bad", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"],
    [action |-> "CallDone", thread |-> "t1", command |-> "Write", address |-> "A1", value |-> "bad", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"],
    [action |-> "PublishPayload", thread |-> "t2", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 0, target |-> "noThread"],
    [action |-> "PublishEven", thread |-> "t2", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 0, target |-> "noThread"],
    [action |-> "ArmUnlock", thread |-> "t2", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"],
    [action |-> "ArmTarget", thread |-> "t2", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 4, target |-> "t2"],
    [action |-> "ArmTarget", thread |-> "t2", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 4, target |-> "t1"],
    [action |-> "ArmFinishLock", thread |-> "t2", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"],
    [action |-> "ArmFinishUnlock", thread |-> "t2", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"],
    [action |-> "ArmOutcome", thread |-> "t2", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 1, slot |-> 0, target |-> "noThread"],
    [action |-> "Release", thread |-> "t2", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"],
    [action |-> "CallDone", thread |-> "t2", command |-> "Arm", address |-> "A1", value |-> "good", writer |-> "allowed", span |-> 1, entry |-> 0, slot |-> 0, target |-> "noThread"]
    >>
====
