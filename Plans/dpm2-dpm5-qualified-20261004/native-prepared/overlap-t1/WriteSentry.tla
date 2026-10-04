---- MODULE WriteSentry ----
(* Production protocol observation, native-runtime-phase/v3. *)
(* Four slots for native acceptance; smaller SlotCount is an explicit profile. *)
(* Effects follow source publication, exact revalidation, target ownership, *)
(* trap admission/leases and verified-clear handles retained until retirement. *)
(* The VEH excludes debug-register restoration from its stale saved context. *)
(* Verified-clear handles remain retained through in-flight partial disarm. *)
EXTENDS Integers, FiniteSets
CONSTANTS
  \* @type: Set(Str);
  Threads,
  \* @type: Set(Str);
  Addresses,
  \* @type: Set(Str);
  Values,
  \* @type: Set(Str);
  WriterKinds,
  \* @type: Int;
  SlotCount,
  \* @type: Int;
  Budget
VARIABLES
  \* @type: Int -> { active: Bool, seq: Int, address: Str, owner: Str, baseline: Str, dr: Int, accept: Bool, inflight: Int, newThreads: Bool };
  reg,
  \* @type: Str -> (Int -> { addr: Str, enabled: Bool });
  dr,
  \* @type: Str -> (Int -> Str);
  tls,
  \* @type: Str -> (Int -> Int);
  targets,
  \* @type: Str -> Str;
  mem,
  \* @type: Str -> Str;
  pc,
  \* @type: Str;
  operation,
  \* @type: Str;
  mutex,
  \* @type: Str -> { entry: Int, slot: Int, s1: Int, s2: Int, address: Str, baseline: Str, owner: Str, active: Bool };
  locals,
  \* @type: Str -> Str;
  result,
  \* @type: Str -> { command: Str, address: Str, value: Str, writer: Str, span: Int, baseline: Str };
  calls,
  \* @type: Str -> Int;
  selected,
  \* @type: Str -> (Int -> { addr: Str, enabled: Bool });
  trap,
  \* @type: Int;
  budget,
  \* @type: { hit: Bool, filtered: Bool, rejected: Bool, torn: Bool, inactive: Bool, admissionRejected: Bool, contextRejected: Bool, ownerRejected: Bool };
  flags,
  \* @type: Str -> Bool;
  disarm_conflict,
  \* @type: Str -> { asserted: Int, unclaimed: Int, count: Int, mask: Int, order: Int, fallback: Bool };
  progress
vars == <<reg, dr, tls, targets, mem, pc, operation, mutex, locals, result,
          calls, selected, trap, budget, flags, disarm_conflict, progress>>
NumSlots == SlotCount
NoThread == "noThread"
NoAddr == "noAddr"
ForeignAddr == "foreign"
DrOf(i) == SlotCount + 1 - i
EmptyDR == [addr |-> NoAddr, enabled |-> FALSE]
NullEntry == [active |-> FALSE, seq |-> 0, address |-> NoAddr, owner |-> NoThread,
  baseline |-> NoAddr, dr |-> 0, accept |-> FALSE, inflight |-> 0, newThreads |-> FALSE]
NullLocal == [entry |-> 0, slot |-> 0, s1 |-> 0, s2 |-> 0, address |-> NoAddr,
  baseline |-> NoAddr, owner |-> NoThread, active |-> FALSE]
NullCall == [command |-> "none", address |-> NoAddr, value |-> "good", writer |-> "allowed",span |-> 1,baseline |-> NoAddr]
NullProgress == [asserted |-> 0, unclaimed |-> 0, count |-> 0, mask |-> 0, order |-> 0, fallback |-> FALSE]
Init ==
  /\ reg = [i \in 1..SlotCount |-> NullEntry]
  /\ dr = [t \in Threads |-> [s \in 1..SlotCount |-> EmptyDR]]
  /\ tls = [t \in Threads |-> [s \in 1..SlotCount |-> NoAddr]]
  /\ targets = [t \in Threads |-> [s \in 1..SlotCount |-> 0]]
  /\ mem = [a \in Addresses |-> "good"]
  /\ pc = [t \in Threads |-> "Idle"]
  /\ operation = NoThread /\ mutex = NoThread
  /\ locals = [t \in Threads |-> NullLocal]
  /\ result = [t \in Threads |-> "none"]
  /\ calls = [t \in Threads |-> NullCall]
  /\ selected = [t \in Threads |-> 0]
  /\ progress = [t \in Threads |-> NullProgress]
  /\ disarm_conflict = [t \in Threads |-> FALSE]
  /\ trap = dr /\ budget = Budget
  /\ flags = [hit |-> FALSE, filtered |-> FALSE, rejected |-> FALSE,
    torn |-> FALSE, inactive |-> FALSE, admissionRejected |-> FALSE,
    contextRejected |-> FALSE, ownerRejected |-> FALSE]

Mine(t,i) == reg[i].active /\ reg[i].owner = t /\ reg[i].address = calls[t].address
Free(i) == ~reg[i].active /\ \A j \in 1..SlotCount : (j < i) => reg[j].active
Full(i) == \A t \in Threads : LET s == reg[i].dr IN
  tls[t][s] = reg[i].address /\ dr[t][s] = [addr |-> reg[i].address, enabled |-> TRUE]
VerifiedCoverage(i) == \A t \in Threads :
  targets[t][reg[i].dr]=1 /\ tls[t][reg[i].dr]=reg[i].address
Cleared(i) == \A t \in Threads : targets[t][reg[i].dr] # 1
Configured(t,a,c) ==
  IF c="Disarm" THEN NoAddr ELSE
  LET old == {i \in 1..SlotCount : reg[i].active /\ reg[i].owner=t /\ reg[i].address=a}
      good == \E i \in old : reg[i].baseline="good"
  IN IF old={} THEN mem[a] ELSE
     IF c="ArmChanged" THEN IF good THEN "bad" ELSE "good"
     ELSE IF good THEN "good" ELSE "bad"

Bit(s) == CASE s=1 -> 1 [] s=2 -> 2 [] s=3 -> 4 [] OTHER -> 8
Has(m,s) == CASE s=1 -> m \in {1,3,5,7,9,11,13,15}
  [] s=2 -> m \in {2,3,6,7,10,11,14,15}
  [] s=3 -> m \in {4,5,6,7,12,13,14,15}
  [] OTHER -> m \in 8..15
Adjacent(a) == CASE a="A1" -> "A2" [] a="A2" -> "A3" [] OTHER -> ForeignAddr
\* @type: ({ command: Str, address: Str, value: Str, writer: Str, span: Int, baseline: Str }) => Set(Str);
Touched(c) == {c.address} \cup (IF c.span=2 THEN {Adjacent(c.address)} ELSE {})
\* @type: (Int -> {addr: Str, enabled: Bool}, { command: Str, address: Str, value: Str, writer: Str, span: Int, baseline: Str }) => Int;
MaskOf(d,c) ==
  (IF d[1].enabled /\ d[1].addr \in Touched(c) THEN 1 ELSE 0) +
  (IF d[2].enabled /\ d[2].addr \in Touched(c) THEN 2 ELSE 0) +
  (IF d[3].enabled /\ d[3].addr \in Touched(c) THEN 4 ELSE 0) +
  (IF d[4].enabled /\ d[4].addr \in Touched(c) THEN 8 ELSE 0)
Stored(t) == [a \in Addresses |-> IF a \in Touched(calls[t]) THEN calls[t].value ELSE mem[a]]
RetryPhases == {"SnapshotNoAdmission","SnapshotAdmissionLost","SnapshotInvalid","SnapshotTorn"}
SlotDonePhases == {"ContextRejected","OwnerRejected","LoadRejected","Filtered","HitReleased"}
ScanPhases == RetryPhases \cup SlotDonePhases \cup {"SnapshotProbe","SnapshotAdmissionChecked",
  "SnapshotLease","SnapshotAdmissionValidated","SnapshotSeq1","SnapshotPayload","SnapshotSeq2","SnapshotAccepted","Hit"}
NextSlot(t,s,after) == Has(progress[t].asserted,s) /\ s>after /\
  (\A earlier \in 1..SlotCount: after<earlier /\ earlier<s => ~Has(progress[t].asserted,earlier))
ScanNext(t,e,s) ==
  IF pc[t]="TrapEntry" THEN e=1 /\ NextSlot(t,s,0)
  ELSE IF pc[t] \in RetryPhases /\ locals[t].entry<SlotCount
    THEN e=locals[t].entry+1 /\ s=locals[t].slot
  ELSE (pc[t] \in SlotDonePhases \/ (pc[t] \in RetryPhases /\ locals[t].entry=SlotCount))
       /\ e=1 /\ NextSlot(t,s,locals[t].slot)
ScanDone(t) ==
  (pc[t] \in SlotDonePhases \/ (pc[t] \in RetryPhases /\ locals[t].entry=SlotCount)) /\
  (\A s \in 1..SlotCount: s>locals[t].slot => ~Has(progress[t].asserted,s))
Pop(m) == (IF Has(m,1) THEN 1 ELSE 0)+(IF Has(m,2) THEN 1 ELSE 0)+
  (IF Has(m,3) THEN 1 ELSE 0)+(IF Has(m,4) THEN 1 ELSE 0)
AppendDigit(m,s,n) == IF Has(m,s) THEN 5*n+s ELSE n
Order(m) == AppendDigit(m,4,AppendDigit(m,3,AppendDigit(m,2,AppendDigit(m,1,0))))
\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
Reserve(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"Idle"} /\ operation = NoThread /\ budget > 0 /\ p.command \in {"Arm","ArmChanged","Disarm"}
  /\ pc' = [pc EXCEPT ![p.thread] = "Reserve"]
  /\ operation' = p.thread
  /\ budget' = budget-1
  /\ calls' = [calls EXCEPT ![p.thread] = [command |-> p.command,address |-> p.address,value |-> p.value,writer |-> p.writer,span |-> p.span,baseline |-> Configured(p.thread,p.address,p.command)]]
  /\ selected' = [selected EXCEPT ![p.thread]=0]
  /\ result' = [result EXCEPT ![p.thread]="none"]
  /\ disarm_conflict' = [disarm_conflict EXCEPT ![p.thread]=FALSE]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, mutex, locals, trap, flags, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
Busy(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"Idle"} /\ operation # NoThread
  /\ pc' = [pc EXCEPT ![p.thread] = "Busy"]
  /\ calls' = [calls EXCEPT ![p.thread]=[command |-> p.command,address |-> p.address,value |-> p.value,writer |-> p.writer,span |-> p.span,baseline |-> Configured(p.thread,p.address,p.command)]]
  /\ selected' = [selected EXCEPT ![p.thread]=0]
  /\ result' = [result EXCEPT ![p.thread]="busy"]
  /\ disarm_conflict' = [disarm_conflict EXCEPT ![p.thread]=FALSE]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, locals, trap, budget, flags, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
ArmLock(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"Reserve"} /\ calls[p.thread].command \in {"Arm","ArmChanged"} /\ operation=p.thread /\ mutex=NoThread
  /\ pc' = [pc EXCEPT ![p.thread] = "ArmLock"]
  /\ mutex' = p.thread
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
ArmUnlock(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"PublishEven", "ArmReuse", "ArmNoSlot", "ArmConflict", "ArmBlocked"} /\ mutex=p.thread
  /\ pc' = [pc EXCEPT ![p.thread] = "ArmUnlock"]
  /\ mutex' = NoThread
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
ArmFinishLock(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"ArmTarget"} /\ operation=p.thread /\ mutex=NoThread
  /\ pc' = [pc EXCEPT ![p.thread] = "ArmFinishLock"]
  /\ mutex' = p.thread
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
ArmFinishUnlock(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"ArmFinishLock"} /\ mutex=p.thread
  /\ pc' = [pc EXCEPT ![p.thread] = "ArmFinishUnlock"]
  /\ mutex' = NoThread
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
DisLock(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"Reserve"} /\ calls[p.thread].command="Disarm" /\ operation=p.thread /\ mutex=NoThread
  /\ pc' = [pc EXCEPT ![p.thread] = "DisLock"]
  /\ mutex' = p.thread
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
DisUnlock(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"DisSelect", "DisNoEntry"} /\ mutex=p.thread
  /\ pc' = [pc EXCEPT ![p.thread] = "DisUnlock"]
  /\ mutex' = NoThread
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
DisFinishLock(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"DisTarget", "DisUnlock"} /\ selected[p.thread] \in 1..SlotCount /\ operation=p.thread /\ mutex=NoThread /\ selected[p.thread] \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "DisFinishLock"]
  /\ mutex' = p.thread
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
DisFinishUnlock(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"DisFinishLock"} /\ mutex=p.thread
  /\ pc' = [pc EXCEPT ![p.thread] = "DisFinishUnlock"]
  /\ mutex' = NoThread
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
ArmSelect(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"ArmLock"} /\ p.entry \in 1..SlotCount /\ Free(p.entry) /\ ~(\E j \in 1..SlotCount : Mine(p.thread,j))
  /\ pc' = [pc EXCEPT ![p.thread] = "ArmSelect"]
  /\ selected' = [selected EXCEPT ![p.thread]=p.entry]
  /\ reg' = [reg EXCEPT ![p.entry].dr=DrOf(p.entry)]
  /\ UNCHANGED <<dr, tls, targets, mem, operation, mutex, locals, result, calls, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
ArmReuse(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"ArmLock"} /\ p.entry \in 1..SlotCount /\ Mine(p.thread,p.entry) /\ reg[p.entry].accept /\ reg[p.entry].newThreads /\ calls[p.thread].command="Arm"
  /\ pc' = [pc EXCEPT ![p.thread] = "ArmReuse"]
  /\ selected' = [selected EXCEPT ![p.thread]=p.entry]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, locals, result, calls, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
ArmConflict(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"ArmLock"} /\ p.entry \in 1..SlotCount /\ Mine(p.thread,p.entry) /\ reg[p.entry].accept /\ reg[p.entry].newThreads /\ calls[p.thread].command="ArmChanged"
  /\ pc' = [pc EXCEPT ![p.thread] = "ArmConflict"]
  /\ selected' = [selected EXCEPT ![p.thread]=p.entry]
  /\ result' = [result EXCEPT ![p.thread]="conflict"]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, locals, calls, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
ArmBlocked(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"ArmLock"} /\ p.entry \in 1..SlotCount /\ Mine(p.thread,p.entry) /\ (~reg[p.entry].accept \/ ~reg[p.entry].newThreads)
  /\ pc' = [pc EXCEPT ![p.thread] = "ArmBlocked"]
  /\ selected' = [selected EXCEPT ![p.thread]=p.entry]
  /\ result' = [result EXCEPT ![p.thread]="partial"]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, locals, calls, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
ArmNoSlot(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"ArmLock"} /\ \A j \in 1..SlotCount : reg[j].active /\ ~Mine(p.thread,j)
  /\ pc' = [pc EXCEPT ![p.thread] = "ArmNoSlot"]
  /\ flags' = [flags EXCEPT !.rejected=TRUE]
  /\ result' = [result EXCEPT ![p.thread]="no-slot"]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, locals, calls, selected, trap, budget, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
PublishOdd(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"ArmSelect"} /\ ~reg[selected[p.thread]].accept /\ selected[p.thread] \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "PublishOdd"]
  /\ reg' = [reg EXCEPT ![selected[p.thread]].seq=@+1]
  /\ UNCHANGED <<dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
PublishPayload(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"PublishOdd"} /\ selected[p.thread] \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "PublishPayload"]
  /\ reg' = [reg EXCEPT ![selected[p.thread]]=[active |-> TRUE,seq |-> reg[selected[p.thread]].seq,address |-> calls[p.thread].address,owner |-> p.thread,baseline |-> calls[p.thread].baseline,dr |-> DrOf(selected[p.thread]),accept |-> FALSE,inflight |-> reg[selected[p.thread]].inflight,newThreads |-> TRUE]]
  /\ UNCHANGED <<dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
PublishEven(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"PublishPayload"} /\ selected[p.thread] \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "PublishEven"]
  /\ reg' = [reg EXCEPT ![selected[p.thread]].seq=@+1, ![selected[p.thread]].accept=TRUE]
  /\ UNCHANGED <<dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
ArmTarget(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"ArmUnlock", "ArmTarget"} /\ p.target \in Threads /\ selected[p.thread] \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "ArmTarget"]
  /\ dr' = LET s == reg[selected[p.thread]].dr IN IF ~dr[p.target][s].enabled THEN [dr EXCEPT ![p.target][s]=[addr |-> reg[selected[p.thread]].address,enabled |-> TRUE]] ELSE dr
  /\ tls' = LET s == reg[selected[p.thread]].dr IN [tls EXCEPT ![p.target][s]=IF ~dr[p.target][s].enabled \/ (dr[p.target][s].addr=reg[selected[p.thread]].address /\ targets[p.target][s]=1) THEN reg[selected[p.thread]].address ELSE NoAddr]
  /\ targets' = LET s == reg[selected[p.thread]].dr IN [targets EXCEPT ![p.target][s]=IF ~dr[p.target][s].enabled \/ (dr[p.target][s].addr=reg[selected[p.thread]].address /\ targets[p.target][s]=1) THEN 1 ELSE 0]
  /\ UNCHANGED <<reg, mem, operation, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
ArmOutcome(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"ArmFinishUnlock"} /\ selected[p.thread] \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "ArmOutcome"]
  /\ result' = [result EXCEPT ![p.thread]=IF VerifiedCoverage(selected[p.thread]) THEN "ok" ELSE "partial"]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, locals, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
DisSelect(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"DisLock"} /\ p.entry \in 1..SlotCount /\ Mine(p.thread,p.entry)
  /\ pc' = [pc EXCEPT ![p.thread] = "DisSelect"]
  /\ selected' = [selected EXCEPT ![p.thread]=p.entry]
  /\ reg' = [reg EXCEPT ![p.entry].newThreads=FALSE]
  /\ UNCHANGED <<dr, tls, targets, mem, operation, mutex, locals, result, calls, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
DisNoEntry(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"DisLock"} /\ ~(\E j \in 1..SlotCount : Mine(p.thread,j))
  /\ pc' = [pc EXCEPT ![p.thread] = "DisNoEntry"]
  /\ result' = [result EXCEPT ![p.thread]="not-armed"]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, locals, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
DisTarget(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"DisUnlock", "DisTarget"} /\ p.target \in Threads /\ targets[p.target][reg[selected[p.thread]].dr] # 0 /\ selected[p.thread] \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "DisTarget"]
  /\ dr' = LET s == reg[selected[p.thread]].dr IN IF dr[p.target][s].enabled /\ dr[p.target][s].addr=reg[selected[p.thread]].address THEN [dr EXCEPT ![p.target][s]=EmptyDR] ELSE dr
  /\ tls' = [tls EXCEPT ![p.target][reg[selected[p.thread]].dr]=NoAddr]
  /\ targets' = [targets EXCEPT ![p.target][reg[selected[p.thread]].dr]=2]
  /\ disarm_conflict' = [disarm_conflict EXCEPT ![p.thread]=@ \/ (dr[p.target][reg[selected[p.thread]].dr].enabled /\ dr[p.target][reg[selected[p.thread]].dr].addr=ForeignAddr)]
  /\ UNCHANGED <<reg, mem, operation, mutex, locals, result, calls, selected, trap, budget, flags, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
AdmissionClosed(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"DisFinishUnlock"} /\ Cleared(selected[p.thread]) /\ selected[p.thread] \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "AdmissionClosed"]
  /\ reg' = [reg EXCEPT ![selected[p.thread]].accept=FALSE]
  /\ UNCHANGED <<dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
RetirePartial(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"AdmissionClosed"} /\ reg[selected[p.thread]].inflight>0 /\ selected[p.thread] \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "RetirePartial"]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
RetireQuiescent(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"AdmissionClosed"} /\ reg[selected[p.thread]].inflight=0 /\ selected[p.thread] \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "RetireQuiescent"]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
RetireOdd(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"RetireQuiescent"} /\ selected[p.thread] \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "RetireOdd"]
  /\ reg' = [reg EXCEPT ![selected[p.thread]].seq=@+1]
  /\ UNCHANGED <<dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
RetirePayload(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"RetireOdd"} /\ selected[p.thread] \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "RetirePayload"]
  /\ reg' = [reg EXCEPT ![selected[p.thread]].active=FALSE, ![selected[p.thread]].newThreads=FALSE]
  /\ UNCHANGED <<dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
RetireEven(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"RetirePayload"} /\ selected[p.thread] \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "RetireEven"]
  /\ reg' = [reg EXCEPT ![selected[p.thread]].seq=@+1]
  /\ UNCHANGED <<dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
RetireClosed(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"RetireEven"} /\ selected[p.thread] \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "RetireClosed"]
  /\ targets' = [t \in Threads |-> [targets[t] EXCEPT ![reg[selected[p.thread]].dr]=0]]
  /\ UNCHANGED <<reg, dr, tls, mem, operation, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
DisOutcome(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"RetirePartial", "RetireClosed"} /\ selected[p.thread] \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "DisOutcome"]
  /\ result' = [result EXCEPT ![p.thread]=IF reg[selected[p.thread]].active THEN "partial" ELSE IF disarm_conflict[p.thread] THEN "conflict" ELSE "ok"]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, locals, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
Release(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"ArmOutcome", "DisOutcome", "ArmUnlock", "DisUnlock"} /\ operation=p.thread
  /\ pc' = [pc EXCEPT ![p.thread] = "Release"]
  /\ operation' = NoThread
  /\ UNCHANGED <<reg, dr, tls, targets, mem, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
WriteBegin(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"Idle"}
  /\ pc' = [pc EXCEPT ![p.thread] = "WriteBegin"]
  /\ progress' = [progress EXCEPT ![p.thread]=NullProgress]
  /\ calls' = [calls EXCEPT ![p.thread]=[command |-> "Write",address |-> p.address,value |-> p.value,writer |-> p.writer,span |-> p.span,baseline |-> NoAddr]]
  /\ selected' = [selected EXCEPT ![p.thread]=0]
  /\ locals' = [locals EXCEPT ![p.thread]=NullLocal]
  /\ trap' = [trap EXCEPT ![p.thread]=[s \in 1..SlotCount |-> EmptyDR]]
  /\ result' = [result EXCEPT ![p.thread]="none"]
  /\ disarm_conflict' = [disarm_conflict EXCEPT ![p.thread]=FALSE]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, budget, flags>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
TrapEntry(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"WriteBegin"} /\ MaskOf(dr[p.thread],calls[p.thread])>0
  /\ pc' = [pc EXCEPT ![p.thread] = "TrapEntry"]
  /\ mem' = Stored(p.thread)
  /\ trap' = [trap EXCEPT ![p.thread]=dr[p.thread]]
  /\ progress' = [progress EXCEPT ![p.thread].asserted=MaskOf(dr[p.thread],calls[p.thread]), ![p.thread].unclaimed=MaskOf(dr[p.thread],calls[p.thread])]
  /\ UNCHANGED <<reg, dr, tls, targets, operation, mutex, locals, result, calls, selected, budget, flags, disarm_conflict>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
SnapshotProbe(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ p.entry \in 1..SlotCount /\ p.slot \in 1..SlotCount /\ ScanNext(p.thread,p.entry,p.slot)
  /\ pc' = [pc EXCEPT ![p.thread] = "SnapshotProbe"]
  /\ locals' = [locals EXCEPT ![p.thread].entry=p.entry, ![p.thread].slot=p.slot]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
SnapshotNoAdmission(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"SnapshotProbe"} /\ ~reg[locals[p.thread].entry].accept /\ locals[p.thread].entry \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "SnapshotNoAdmission"]
  /\ flags' = [flags EXCEPT !.admissionRejected=TRUE]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
SnapshotAdmissionChecked(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"SnapshotProbe"} /\ reg[locals[p.thread].entry].accept /\ locals[p.thread].entry \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "SnapshotAdmissionChecked"]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
SnapshotLease(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"SnapshotAdmissionChecked"}
  /\ pc' = [pc EXCEPT ![p.thread] = "SnapshotLease"]
  /\ reg' = [reg EXCEPT ![locals[p.thread].entry].inflight=@+1]
  /\ UNCHANGED <<dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
SnapshotAdmissionLost(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"SnapshotLease"} /\ ~reg[locals[p.thread].entry].accept /\ locals[p.thread].entry \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "SnapshotAdmissionLost"]
  /\ reg' = [reg EXCEPT ![locals[p.thread].entry].inflight=@-1]
  /\ flags' = [flags EXCEPT !.admissionRejected=TRUE]
  /\ UNCHANGED <<dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
SnapshotAdmissionValidated(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"SnapshotLease"} /\ reg[locals[p.thread].entry].accept /\ locals[p.thread].entry \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "SnapshotAdmissionValidated"]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
SnapshotSeq1(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"SnapshotAdmissionValidated"} /\ locals[p.thread].entry \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "SnapshotSeq1"]
  /\ locals' = [locals EXCEPT ![p.thread].s1=reg[locals[p.thread].entry].seq]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
SnapshotInvalid(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"SnapshotSeq1"} /\ (locals[p.thread].s1 % 2=1 \/ ~reg[locals[p.thread].entry].active \/ reg[locals[p.thread].entry].dr # locals[p.thread].slot) /\ locals[p.thread].entry \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "SnapshotInvalid"]
  /\ reg' = [reg EXCEPT ![locals[p.thread].entry].inflight=@-1]
  /\ flags' = [flags EXCEPT !.torn=flags.torn \/ locals[p.thread].s1 % 2=1, !.inactive=flags.inactive \/ (locals[p.thread].s1 % 2=0 /\ ~reg[locals[p.thread].entry].active)]
  /\ UNCHANGED <<dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
SnapshotPayload(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"SnapshotSeq1"} /\ locals[p.thread].s1 % 2=0 /\ reg[locals[p.thread].entry].active /\ reg[locals[p.thread].entry].dr=locals[p.thread].slot /\ locals[p.thread].entry \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "SnapshotPayload"]
  /\ locals' = [locals EXCEPT ![p.thread].address=reg[locals[p.thread].entry].address, ![p.thread].baseline=reg[locals[p.thread].entry].baseline, ![p.thread].owner=reg[locals[p.thread].entry].owner, ![p.thread].active=reg[locals[p.thread].entry].active]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
SnapshotSeq2(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"SnapshotPayload"} /\ locals[p.thread].entry \in 1..SlotCount
  /\ pc' = [pc EXCEPT ![p.thread] = "SnapshotSeq2"]
  /\ locals' = [locals EXCEPT ![p.thread].s2=reg[locals[p.thread].entry].seq]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
SnapshotTorn(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"SnapshotSeq2"} /\ locals[p.thread].s1 # locals[p.thread].s2
  /\ pc' = [pc EXCEPT ![p.thread] = "SnapshotTorn"]
  /\ reg' = [reg EXCEPT ![locals[p.thread].entry].inflight=@-1]
  /\ flags' = [flags EXCEPT !.torn=TRUE]
  /\ UNCHANGED <<dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
SnapshotAccepted(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"SnapshotSeq2"} /\ locals[p.thread].s1=locals[p.thread].s2
  /\ pc' = [pc EXCEPT ![p.thread] = "SnapshotAccepted"]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
ContextRejected(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"SnapshotAccepted"} /\ (trap[p.thread][locals[p.thread].slot].addr # locals[p.thread].address \/ ~trap[p.thread][locals[p.thread].slot].enabled)
  /\ pc' = [pc EXCEPT ![p.thread] = "ContextRejected"]
  /\ reg' = [reg EXCEPT ![locals[p.thread].entry].inflight=@-1]
  /\ flags' = [flags EXCEPT !.contextRejected=TRUE]
  /\ UNCHANGED <<dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
OwnerRejected(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"SnapshotAccepted"} /\ trap[p.thread][locals[p.thread].slot].addr=locals[p.thread].address /\ trap[p.thread][locals[p.thread].slot].enabled /\ tls[p.thread][locals[p.thread].slot] # locals[p.thread].address
  /\ pc' = [pc EXCEPT ![p.thread] = "OwnerRejected"]
  /\ reg' = [reg EXCEPT ![locals[p.thread].entry].inflight=@-1]
  /\ flags' = [flags EXCEPT !.ownerRejected=TRUE]
  /\ UNCHANGED <<dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
Filtered(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"SnapshotAccepted"} /\ trap[p.thread][locals[p.thread].slot].addr=locals[p.thread].address /\ trap[p.thread][locals[p.thread].slot].enabled /\ tls[p.thread][locals[p.thread].slot]=locals[p.thread].address /\ (calls[p.thread].writer="allowed" /\ p.thread=locals[p.thread].owner /\ mem[locals[p.thread].address]=locals[p.thread].baseline)
  /\ pc' = [pc EXCEPT ![p.thread] = "Filtered"]
  /\ reg' = [reg EXCEPT ![locals[p.thread].entry].inflight=@-1]
  /\ flags' = [flags EXCEPT !.filtered=TRUE]
  /\ progress' = [progress EXCEPT ![p.thread].unclaimed=@-Bit(locals[p.thread].slot)]
  /\ UNCHANGED <<dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, disarm_conflict>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
Hit(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"SnapshotAccepted"} /\ trap[p.thread][locals[p.thread].slot].addr=locals[p.thread].address /\ trap[p.thread][locals[p.thread].slot].enabled /\ tls[p.thread][locals[p.thread].slot]=locals[p.thread].address /\ ~(calls[p.thread].writer="allowed" /\ p.thread=locals[p.thread].owner /\ mem[locals[p.thread].address]=locals[p.thread].baseline)
  /\ pc' = [pc EXCEPT ![p.thread] = "Hit"]
  /\ flags' = [flags EXCEPT !.hit=TRUE]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
HitReleased(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"Hit"}
  /\ pc' = [pc EXCEPT ![p.thread] = "HitReleased"]
  /\ reg' = [reg EXCEPT ![locals[p.thread].entry].inflight=@-1]
  /\ progress' = [progress EXCEPT ![p.thread].unclaimed=@-Bit(locals[p.thread].slot), ![p.thread].count=@+1, ![p.thread].mask=@+Bit(locals[p.thread].slot), ![p.thread].order=5*@+locals[p.thread].slot]
  /\ UNCHANGED <<dr, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
WriteDone(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ (pc[p.thread]="WriteBegin" /\ MaskOf(dr[p.thread],calls[p.thread])=0) \/ ScanDone(p.thread)
  /\ pc' = [pc EXCEPT ![p.thread] = "WriteDone"]
  /\ mem' = IF pc[p.thread]="WriteBegin" THEN Stored(p.thread) ELSE mem
  /\ progress' = [progress EXCEPT ![p.thread].fallback=progress[p.thread].unclaimed#0]
  /\ UNCHANGED <<reg, dr, tls, targets, operation, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
CallDone(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ pc[p.thread] \in {"Release", "WriteDone", "Busy"}
  /\ pc' = [pc EXCEPT ![p.thread] = "Idle"]
  /\ result' = [result EXCEPT ![p.thread]=IF calls[p.thread].command="Write" THEN "ok" ELSE result[p.thread]]
  /\ UNCHANGED <<reg, dr, tls, targets, mem, operation, mutex, locals, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
ForeignStomp(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ p.target \in Threads /\ p.slot \in 1..SlotCount
  /\ pc' = pc
  /\ dr' = [dr EXCEPT ![p.target][p.slot]=[addr |-> ForeignAddr,enabled |-> TRUE]]
  /\ UNCHANGED <<reg, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
ForeignClear(p) ==
  /\ p.thread \in Threads /\ p.span \in 1..2
  /\ p.target \in Threads /\ p.slot \in 1..SlotCount
  /\ pc' = pc
  /\ dr' = [dr EXCEPT ![p.target][p.slot]=EmptyDR]
  /\ UNCHANGED <<reg, tls, targets, mem, operation, mutex, locals, result, calls, selected, trap, budget, flags, disarm_conflict, progress>>

Actions == {"Reserve", "Busy", "Release", "ArmLock", "ArmUnlock", "ArmFinishLock", "ArmFinishUnlock", "ArmSelect", "ArmReuse", "ArmNoSlot", "PublishOdd", "PublishPayload", "PublishEven", "ArmTarget", "ArmOutcome", "DisLock", "DisUnlock", "DisFinishLock", "DisFinishUnlock", "DisSelect", "DisNoEntry", "DisTarget", "AdmissionClosed", "RetirePartial", "RetireQuiescent", "RetireOdd", "RetirePayload", "RetireEven", "DisOutcome", "WriteBegin", "TrapEntry", "SnapshotProbe", "SnapshotNoAdmission", "SnapshotAdmissionChecked", "SnapshotLease", "SnapshotAdmissionLost", "SnapshotAdmissionValidated", "SnapshotSeq1", "SnapshotInvalid", "SnapshotPayload", "SnapshotSeq2", "SnapshotTorn", "SnapshotAccepted", "ContextRejected", "OwnerRejected", "Filtered", "Hit", "HitReleased", "WriteDone", "CallDone", "RetireClosed", "ArmConflict", "ArmBlocked", "ForeignStomp", "ForeignClear"}
\* @type: ({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str }) => Bool;
Event(p) ==
  \/ /\ p.action="Reserve" /\ Reserve(p)
  \/ /\ p.action="Busy" /\ Busy(p)
  \/ /\ p.action="Release" /\ Release(p)
  \/ /\ p.action="ArmLock" /\ ArmLock(p)
  \/ /\ p.action="ArmUnlock" /\ ArmUnlock(p)
  \/ /\ p.action="ArmFinishLock" /\ ArmFinishLock(p)
  \/ /\ p.action="ArmFinishUnlock" /\ ArmFinishUnlock(p)
  \/ /\ p.action="ArmSelect" /\ ArmSelect(p)
  \/ /\ p.action="ArmReuse" /\ ArmReuse(p)
  \/ /\ p.action="ArmNoSlot" /\ ArmNoSlot(p)
  \/ /\ p.action="PublishOdd" /\ PublishOdd(p)
  \/ /\ p.action="PublishPayload" /\ PublishPayload(p)
  \/ /\ p.action="PublishEven" /\ PublishEven(p)
  \/ /\ p.action="ArmTarget" /\ ArmTarget(p)
  \/ /\ p.action="ArmOutcome" /\ ArmOutcome(p)
  \/ /\ p.action="DisLock" /\ DisLock(p)
  \/ /\ p.action="DisUnlock" /\ DisUnlock(p)
  \/ /\ p.action="DisFinishLock" /\ DisFinishLock(p)
  \/ /\ p.action="DisFinishUnlock" /\ DisFinishUnlock(p)
  \/ /\ p.action="DisSelect" /\ DisSelect(p)
  \/ /\ p.action="DisNoEntry" /\ DisNoEntry(p)
  \/ /\ p.action="DisTarget" /\ DisTarget(p)
  \/ /\ p.action="AdmissionClosed" /\ AdmissionClosed(p)
  \/ /\ p.action="RetirePartial" /\ RetirePartial(p)
  \/ /\ p.action="RetireQuiescent" /\ RetireQuiescent(p)
  \/ /\ p.action="RetireOdd" /\ RetireOdd(p)
  \/ /\ p.action="RetirePayload" /\ RetirePayload(p)
  \/ /\ p.action="RetireEven" /\ RetireEven(p)
  \/ /\ p.action="DisOutcome" /\ DisOutcome(p)
  \/ /\ p.action="WriteBegin" /\ WriteBegin(p)
  \/ /\ p.action="TrapEntry" /\ TrapEntry(p)
  \/ /\ p.action="SnapshotProbe" /\ SnapshotProbe(p)
  \/ /\ p.action="SnapshotNoAdmission" /\ SnapshotNoAdmission(p)
  \/ /\ p.action="SnapshotAdmissionChecked" /\ SnapshotAdmissionChecked(p)
  \/ /\ p.action="SnapshotLease" /\ SnapshotLease(p)
  \/ /\ p.action="SnapshotAdmissionLost" /\ SnapshotAdmissionLost(p)
  \/ /\ p.action="SnapshotAdmissionValidated" /\ SnapshotAdmissionValidated(p)
  \/ /\ p.action="SnapshotSeq1" /\ SnapshotSeq1(p)
  \/ /\ p.action="SnapshotInvalid" /\ SnapshotInvalid(p)
  \/ /\ p.action="SnapshotPayload" /\ SnapshotPayload(p)
  \/ /\ p.action="SnapshotSeq2" /\ SnapshotSeq2(p)
  \/ /\ p.action="SnapshotTorn" /\ SnapshotTorn(p)
  \/ /\ p.action="SnapshotAccepted" /\ SnapshotAccepted(p)
  \/ /\ p.action="ContextRejected" /\ ContextRejected(p)
  \/ /\ p.action="OwnerRejected" /\ OwnerRejected(p)
  \/ /\ p.action="Filtered" /\ Filtered(p)
  \/ /\ p.action="Hit" /\ Hit(p)
  \/ /\ p.action="HitReleased" /\ HitReleased(p)
  \/ /\ p.action="WriteDone" /\ WriteDone(p)
  \/ /\ p.action="CallDone" /\ CallDone(p)
  \/ /\ p.action="RetireClosed" /\ RetireClosed(p)
  \/ /\ p.action="ArmConflict" /\ ArmConflict(p)
  \/ /\ p.action="ArmBlocked" /\ ArmBlocked(p)
  \/ /\ p.action="ForeignStomp" /\ ForeignStomp(p)
  \/ /\ p.action="ForeignClear" /\ ForeignClear(p)
Inputs == [action: Actions, thread: Threads, command: {"Arm","ArmChanged","Disarm","Write"},
  address: Addresses, value: Values, writer: WriterKinds, span: 1..2, entry: 0..SlotCount,
  slot: 0..SlotCount, target: Threads \cup {NoThread}]
Next == \E p \in Inputs : Event(p)
Spec == Init /\ [][Next]_vars
TypeOK ==
  /\ budget \in 0..Budget
  /\ operation \in Threads \cup {NoThread} /\ mutex \in Threads \cup {NoThread}
  /\ \A i \in 1..SlotCount : reg[i].seq >= 0 /\ reg[i].inflight >= 0
SlotIntegrity == \A i,j \in 1..SlotCount : (i # j /\ reg[i].active /\ reg[j].active) => reg[i].dr # reg[j].dr
AdmissionSafe == \A i \in 1..SlotCount : reg[i].accept => reg[i].active /\ reg[i].seq % 2=0
ProtectedPhases == {"SnapshotAdmissionValidated","SnapshotSeq1","SnapshotPayload",
  "SnapshotSeq2","SnapshotAccepted","Hit"}
LeaseRetirementSafe == \A t \in Threads : pc[t] \in ProtectedPhases =>
  /\ locals[t].entry \in 1..SlotCount
  /\ reg[locals[t].entry].active
  /\ reg[locals[t].entry].seq % 2=0
  /\ reg[locals[t].entry].inflight > 0
ProtectedSnapshotStable == \A t \in Threads :
  pc[t] \in {"SnapshotSeq1","SnapshotPayload","SnapshotSeq2","SnapshotAccepted","Hit"} =>
  reg[locals[t].entry].seq=locals[t].s1
OperationOwnsMutex == mutex=NoThread \/ operation=mutex
ActiveWellFormed == \A i \in 1..SlotCount : reg[i].active =>
  reg[i].dr=DrOf(i) /\ reg[i].owner \in Threads /\ reg[i].address \in Addresses /\ reg[i].baseline \in Values
LifecyclePhases == {"Reserve","ArmLock","ArmUnlock","ArmFinishLock","ArmFinishUnlock",
  "ArmSelect","ArmReuse","ArmNoSlot","ArmConflict","ArmBlocked","PublishOdd","PublishPayload",
  "PublishEven","ArmTarget","ArmOutcome","DisLock","DisUnlock","DisFinishLock","DisFinishUnlock",
  "DisSelect","DisNoEntry","DisTarget","AdmissionClosed","RetirePartial","RetireQuiescent","RetireOdd",
  "RetirePayload","RetireEven","RetireClosed","DisOutcome"}
LifecycleReservationOK == \A t \in Threads : pc[t] \in LifecyclePhases => operation=t
OperationOwnerOK == operation=NoThread \/ pc[operation] \in LifecyclePhases
LockPhases == {"ArmLock","ArmSelect","ArmReuse","ArmNoSlot","ArmConflict","ArmBlocked",
  "PublishOdd","PublishPayload","PublishEven","ArmFinishLock","DisLock","DisSelect",
  "DisNoEntry","DisFinishLock"}
MutexOK == Cardinality({t \in Threads : pc[t] \in LockPhases}) <= 1
\* Success records verified target coverage; foreign hardware edits may follow.
FullOutcomeRequiresCoverage == \A t \in Threads :
  (pc[t]="ArmOutcome" /\ result[t]="ok") =>
  (\A target \in Threads : targets[target][reg[selected[t]].dr]=1
    /\ tls[target][reg[selected[t]].dr]=reg[selected[t]].address)
SuccessfulRetirement == \A t \in Threads :
  (pc[t]="DisOutcome" /\ result[t] \in {"ok","conflict"}) =>
  ~reg[selected[t]].active /\
  (\A target \in Threads : targets[target][reg[selected[t]].dr]=0)
NoOrphanHardware == \A t \in Threads,s \in 1..SlotCount :
  (dr[t][s].enabled /\ dr[t][s].addr # ForeignAddr) =>
  \E i \in 1..SlotCount : reg[i].active /\ reg[i].dr=s /\ reg[i].address=dr[t][s].addr
CallbackSafety == \A t \in Threads:
  /\ progress[t].count=Pop(progress[t].mask) /\ progress[t].count \in 0..4
  /\ progress[t].order=Order(progress[t].mask)
  /\ \A s \in 1..SlotCount: Has(progress[t].mask,s) => Has(progress[t].asserted,s) /\ ~Has(progress[t].unclaimed,s)
NoTorn == ~flags.torn
NoInactiveLease == ~flags.inactive
Safety == TypeOK /\ CallbackSafety /\ SlotIntegrity /\ ActiveWellFormed /\ AdmissionSafe /\ LeaseRetirementSafe /\ ProtectedSnapshotStable
  /\ OperationOwnsMutex /\ LifecycleReservationOK /\ OperationOwnerOK /\ MutexOK
  /\ FullOutcomeRequiresCoverage /\ SuccessfulRetirement /\ NoOrphanHardware
View == <<pc, reg, flags>>
====
