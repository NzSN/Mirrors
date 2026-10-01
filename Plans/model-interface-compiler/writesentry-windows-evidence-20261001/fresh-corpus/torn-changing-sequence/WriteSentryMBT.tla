---- MODULE WriteSentryMBT ----
(* Trace instrumentation for WriteSentry.tla. Plan selects concrete action *)
(* inputs; every scheduled transition is also an action of the base model. *)
EXTENDS WriteSentry, Sequences

CONSTANT
  \* @type: Seq({ action: Str, thread: Str, address: Str, entry: Int, slot: Int, value: Str, writer: Str });
  Plan

VARIABLES
  \* @type: Str;
  action_taken,
  \* @type: { action: Str, thread: Str, address: Str, entry: Int, slot: Int, value: Str, writer: Str };
  parameters,
  \* @type: Int;
  step_count

MBTInit ==
  /\ Init
  /\ action_taken = "init"
  /\ parameters = [action |-> "init", thread |-> "t1", address |-> NoAddr,
                    entry |-> 0, slot |-> 0, value |-> "good", writer |-> "allowed"]
  /\ step_count = 0

\* @type: ({ action: Str, thread: Str, address: Str, entry: Int, slot: Int, value: Str, writer: Str }) => Bool;
ScheduledWrite(p) ==
  /\ WrStart(p.thread)
  /\ mem' = [mem EXCEPT ![p.address] = p.value]
  /\ LET slots == {s \in 1..NumSlots :
                     dr[p.thread][s].enabled /\ dr[p.thread][s].addr = p.address}
     IN IF slots = {}
        THEN /\ p.slot = 0
             /\ pc' = pc /\ tmp' = tmp
             /\ flags' = [flags EXCEPT !.silent = TRUE]
        ELSE /\ p.slot \in slots
             /\ LET gov == {i \in 1..NumSlots : reg[i].dr = p.slot}
                IN IF gov = {}
                   THEN /\ pc' = pc /\ tmp' = tmp
                        /\ flags' = [flags EXCEPT !.foreignTrap = TRUE]
                   ELSE /\ p.entry \in gov
                        /\ tmp' = [tmp EXCEPT ![p.thread].addr = p.address,
                                     ![p.thread].v = p.value,
                                     ![p.thread].wk = p.writer,
                                     ![p.thread].slot = p.slot,
                                     ![p.thread].ei = p.entry]
                        /\ pc' = [pc EXCEPT ![p.thread] = "wr2"]
                        /\ flags' = flags

\* @type: ({ action: Str, thread: Str, address: Str, entry: Int, slot: Int, value: Str, writer: Str }) => Bool;
ScheduledAction(p) ==
  \/ /\ p.action = "ArmStart"
     /\ ArmStart(p.thread)
     /\ tmp'[p.thread].addr = p.address /\ tmp'[p.thread].ei = p.entry
  \/ /\ p.action = "ArmStartRejected"
     /\ ArmStartRejected(p.thread)
     /\ {i \in 1..NumSlots : reg[i].active /\ reg[i].owner = p.thread
                              /\ reg[i].address = p.address} = {}
     /\ {i \in 1..NumSlots : ~reg[i].active} = {}
  \/ /\ p.action = "ArmSeqOdd" /\ ArmSeqOdd(p.thread)
  \/ /\ p.action = "ArmPayload" /\ ArmPayload(p.thread)
  \/ /\ p.action = "ArmSeqEvenRelease" /\ ArmSeqEvenRelease(p.thread)
  \/ /\ p.action = "ArmApplyAll" /\ ArmApplyAll(p.thread)
  \/ /\ p.action = "DisStart"
     /\ DisStart(p.thread)
     /\ tmp'[p.thread].addr = p.address /\ tmp'[p.thread].ei = p.entry
  \/ /\ p.action = "DisReleaseRegistry" /\ DisReleaseRegistry(p.thread)
  \/ /\ p.action = "DisApplyAll" /\ DisApplyAll(p.thread)
  \/ /\ p.action = "DisSeqOdd" /\ DisSeqOdd(p.thread)
  \/ /\ p.action = "DisDeactivate" /\ DisDeactivate(p.thread)
  \/ /\ p.action = "DisSeqEvenRelease" /\ DisSeqEvenRelease(p.thread)
  \/ /\ p.action = "WrStart" /\ ScheduledWrite(p)
  \/ /\ p.action = "WrReadSeq1" /\ WrReadSeq1(p.thread)
  \/ /\ p.action = "WrReadPayload" /\ WrReadPayload(p.thread)
  \/ /\ p.action = "WrReadSeq2" /\ WrReadSeq2(p.thread)
  \/ /\ p.action = "WrDecide" /\ WrDecide(p.thread)
  \/ /\ p.action = "ForeignStomp"
     /\ ForeignStomp
     /\ dr' = [dr EXCEPT ![p.thread][p.slot] =
                [addr |-> ForeignAddr, enabled |-> TRUE]]

MBTNext ==
  /\ step_count < Len(Plan)
  /\ LET p == Plan[step_count + 1]
     IN /\ ScheduledAction(p)
        /\ action_taken' = p.action
        /\ parameters' = p
  /\ step_count' = step_count + 1

MBTSafety ==
  TypeOK /\ MutexOK /\ OperationOwnerOK /\ LifecycleReservationOK
  /\ OperationOwnsMutex /\ SlotIntegrity /\ ActiveWellFormed
  /\ Coherence /\ QuiescentCoverage

(* A complete plan produces a counterexample used as the oracle test trace. *)
MBTTraceIncomplete == MBTSafety /\ step_count < Len(Plan)
====
