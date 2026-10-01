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
    [action |-> "WrStart", thread |-> "t1", address |-> "A1", entry |-> 1, slot |-> 2, value |-> "bad", writer |-> "allowed"],
    [action |-> "WrReadSeq1", thread |-> "t1", address |-> "A1", entry |-> 1, slot |-> 2, value |-> "good", writer |-> "allowed"],
    [action |-> "WrReadPayload", thread |-> "t1", address |-> "A1", entry |-> 1, slot |-> 2, value |-> "good", writer |-> "allowed"],
    [action |-> "WrReadSeq2", thread |-> "t1", address |-> "A1", entry |-> 1, slot |-> 2, value |-> "good", writer |-> "allowed"],
    [action |-> "WrDecide", thread |-> "t1", address |-> "A1", entry |-> 1, slot |-> 2, value |-> "good", writer |-> "allowed"]
    >>
====
