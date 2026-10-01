---- MODULE WriteSentryMBTRun ----
EXTENDS WriteSentryMBT
RunConstInit ==
 /\ Threads = {"t1", "t2"}
 /\ Addresses = {"A1", "A2"}
 /\ Values = {"good", "bad"}
 /\ WriterKinds = {"allowed", "other"}
 /\ Budget = 4
 /\ Plan = <<
    [action |-> "ArmStart", thread |-> "t1", address |-> "A1", entry |-> 1, slot |-> 2, value |-> "good", writer |-> "allowed"],
    [action |-> "ArmSeqOdd", thread |-> "t1", address |-> "A1", entry |-> 1, slot |-> 2, value |-> "good", writer |-> "allowed"],
    [action |-> "ArmPayload", thread |-> "t1", address |-> "A1", entry |-> 1, slot |-> 2, value |-> "good", writer |-> "allowed"],
    [action |-> "ArmSeqEvenRelease", thread |-> "t1", address |-> "A1", entry |-> 1, slot |-> 2, value |-> "good", writer |-> "allowed"],
    [action |-> "ArmApplyAll", thread |-> "t1", address |-> "A1", entry |-> 1, slot |-> 2, value |-> "good", writer |-> "allowed"],
    [action |-> "ForeignStomp", thread |-> "t2", address |-> "A1", entry |-> 1, slot |-> 2, value |-> "good", writer |-> "allowed"],
    [action |-> "ArmStart", thread |-> "t1", address |-> "A1", entry |-> 1, slot |-> 2, value |-> "good", writer |-> "allowed"],
    [action |-> "ArmSeqOdd", thread |-> "t1", address |-> "A1", entry |-> 1, slot |-> 2, value |-> "good", writer |-> "allowed"],
    [action |-> "ArmPayload", thread |-> "t1", address |-> "A1", entry |-> 1, slot |-> 2, value |-> "good", writer |-> "allowed"],
    [action |-> "ArmSeqEvenRelease", thread |-> "t1", address |-> "A1", entry |-> 1, slot |-> 2, value |-> "good", writer |-> "allowed"],
    [action |-> "ArmApplyAll", thread |-> "t1", address |-> "A1", entry |-> 1, slot |-> 2, value |-> "good", writer |-> "allowed"]
    >>
====
