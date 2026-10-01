---- MODULE WriteSentry ----
(***************************************************************************)
(* WriteSentry Layer B — arm/disarm/trap protocol.                         *)
(*                                                                         *)
(* Apalache-compatible: no CHOOSE, no TLC module, INIT/NEXT style,         *)
(* structural Snowcat type annotations. (Also runs under TLC.)             *)
(*                                                                         *)
(* Models the safety-critical core of src/self_watch.cpp + src/veh.cpp:    *)
(*  - bounded registry with seqlock (odd seq = write in progress)          *)
(*  - writer mutex (short registry critical sections)                      *)
(*  - process-wide lifecycle reservation across each arm/disarm sweep       *)
(*  - per-thread DR slots armed by an atomic sweep (kAllThreads)           *)
(*  - TLS arm cache (tls[t][s] = the address this thread armed in slot s)  *)
(*  - trap path: the write commits first; the VEH then snapshots the       *)
(*    registry entry under the seqlock and decides:                        *)
(*    torn -> Search, inactive -> Search, legit -> Filtered, else Hit      *)
(*  - foreign-party DR stomp + repair on the next arm pass                 *)
(*                                                                         *)
(* Abstractions: pattern = NotEqual(baseline-at-arm); writer filter        *)
(* abstracted to WriterKinds {"allowed","other"} + the owner_thread_only   *)
(* rule; dump worker / Crashpad pipeline not modeled; Budget bounds the    *)
(* total number of arm/disarm operations so the model is finite and the    *)
(* seqlock version can never wrap (no ABA artifact).                       *)
(***************************************************************************)
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
  Budget

VARIABLES
  \* @type: Str -> Str;
  pc,
  \* @type: Int -> { active: Bool, seq: Int, address: Str, owner: Str, baseline: Str, dr: Int };
  reg,
  \* @type: Str;
  mutex,
  \* @type: Str;
  operation,
  \* @type: Str -> (Int -> Str);
  tls,
  \* @type: Str -> (Int -> { addr: Str, enabled: Bool });
  dr,
  \* @type: Str -> Str;
  mem,
  \* @type: Int;
  budget,
  \* @type: { hit: Bool, filtered: Bool, torn: Bool, searchInactive: Bool, rejected: Bool, silent: Bool, stomped: Bool, foreignTrap: Bool, foreignRepair: Bool };
  flags,
  \* @type: Str -> { addr: Str, ei: Int, slot: Int, v: Str, wk: Str, s1: Int, s2: Int, view: { active: Bool, seq: Int, address: Str, owner: Str, baseline: Str, dr: Int } };
  tmp

vars == <<pc, reg, mutex, operation, tls, dr, mem, budget, flags, tmp>>

NumSlots == 2          \* registry/DR slots modeled (protocol is size-independent)
NoThread == "noThread"
NoAddr   == "noAddr"
ForeignAddr == "foreign"

NullEntry == [active |-> FALSE, seq |-> 0, address |-> NoAddr,
              owner |-> NoThread, baseline |-> NoAddr, dr |-> 0]
NullTmp == [addr |-> NoAddr, ei |-> 0, slot |-> 0, v |-> "good",
            wk |-> "allowed", s1 |-> 0, s2 |-> 0, view |-> NullEntry]

DrOf(i) == NumSlots + 1 - i   \* allocate downward from the top slot (impl: DR3 first)

TypeOK ==
  /\ pc \in [Threads -> {"idle","arm3","arm4","arm5","arm6",
                         "dis2","dis3","dis4","dis5","dis6",
                         "wr2","wr3","wr4","wr5"}]
  /\ mutex \in Threads \cup {NoThread}
  /\ operation \in Threads \cup {NoThread}
  /\ budget \in 0..Budget
  /\ \A i \in 1..NumSlots :
       /\ reg[i].seq \in Nat
       /\ reg[i].active \in BOOLEAN
       /\ reg[i].address \in Addresses \cup {NoAddr}
       /\ reg[i].owner \in Threads \cup {NoThread}
       /\ reg[i].baseline \in Values \cup {NoAddr}
       /\ reg[i].dr \in 0..NumSlots

Init ==
  /\ pc = [t \in Threads |-> "idle"]
  /\ reg = [i \in 1..NumSlots |-> NullEntry]
  /\ mutex = NoThread
  /\ operation = NoThread
  /\ tls = [t \in Threads |-> [s \in 1..NumSlots |-> NoAddr]]
  /\ dr = [t \in Threads |-> [s \in 1..NumSlots |-> [addr |-> NoAddr, enabled |-> FALSE]]]
  /\ mem = [a \in Addresses |-> "good"]
  /\ budget = Budget
  /\ flags = [hit |-> FALSE, filtered |-> FALSE, torn |-> FALSE,
              searchInactive |-> FALSE, rejected |-> FALSE, silent |-> FALSE,
              stomped |-> FALSE, foreignTrap |-> FALSE, foreignRepair |-> FALSE]
  /\ tmp = [t \in Threads |-> NullTmp]

(*** Post-arm witness seed: entry 1 watches "A1" on every modeled thread.  ***)
(*** It resets sequence, budget, and scratch bookkeeping, so it is not an    ***)
(*** exact state reachable from Init with the same Budget. It tests trap     ***)
(*** suffixes without paying for the arm prefix.                           ***)
InitArmed ==
  LET e1 == [active |-> TRUE, seq |-> 0, address |-> "A1", owner |-> "t1",
             baseline |-> "good", dr |-> DrOf(1)]
      armed == [addr |-> "A1", enabled |-> TRUE]
      empty == [addr |-> NoAddr, enabled |-> FALSE]
  IN
  /\ pc = [t \in Threads |-> "idle"]
  /\ reg = [i \in 1..NumSlots |-> IF i = 1 THEN e1 ELSE NullEntry]
  /\ mutex = NoThread
  /\ operation = NoThread
  /\ tls = [t \in Threads |-> [s \in 1..NumSlots |-> IF s = DrOf(1) THEN "A1" ELSE NoAddr]]
  /\ dr = [t \in Threads |-> [s \in 1..NumSlots |-> IF s = DrOf(1) THEN armed ELSE empty]]
  /\ mem = [a \in Addresses |-> "good"]
  /\ budget = Budget
  /\ flags = [hit |-> FALSE, filtered |-> FALSE, torn |-> FALSE,
               searchInactive |-> FALSE, rejected |-> FALSE, silent |-> FALSE,
               stomped |-> FALSE, foreignTrap |-> FALSE, foreignRepair |-> FALSE]
  /\ tmp = [t \in Threads |-> NullTmp]

(*** arm path: ArmStart -> ArmSeqOdd -> ArmPayload -> ArmSeqEvenRelease -> ArmApplyAll ***)

ArmStart(t) ==
  /\ pc[t] = "idle" /\ mutex = NoThread /\ operation = NoThread
  /\ budget > 0
  /\ \E a \in Addresses :
      LET reuse == {i \in 1..NumSlots :
                    reg[i].active /\ reg[i].address = a /\ reg[i].owner = t}
          free  == {i \in 1..NumSlots : ~reg[i].active}
          cand  == IF reuse # {} THEN reuse ELSE free
      IN  /\ cand # {}
          /\ \E i \in cand :
              /\ budget' = budget - 1
              /\ mutex' = t
              /\ operation' = t
              /\ tmp' = [tmp EXCEPT ![t].addr = a, ![t].ei = i]
              /\ pc' = [pc EXCEPT ![t] = "arm3"]
  /\ UNCHANGED <<reg, tls, dr, mem, flags>>

ArmStartRejected(t) ==
  /\ pc[t] = "idle" /\ mutex = NoThread /\ operation = NoThread
  /\ budget > 0
  /\ \E a \in Addresses :
      /\ {i \in 1..NumSlots :
          reg[i].active /\ reg[i].address = a /\ reg[i].owner = t} = {}
      /\ {i \in 1..NumSlots : ~reg[i].active} = {}
  /\ flags' = [flags EXCEPT !.rejected = TRUE]
  /\ UNCHANGED <<pc, reg, mutex, operation, tls, dr, mem, budget, tmp>>

ArmSeqOdd(t) ==
  /\ pc[t] = "arm3"
  /\ reg' = [reg EXCEPT ![tmp[t].ei].seq = @ + 1]
  /\ pc' = [pc EXCEPT ![t] = "arm4"]
  /\ UNCHANGED <<mutex, operation, tls, dr, mem, budget, flags, tmp>>

ArmPayload(t) ==
  /\ pc[t] = "arm4"
  /\ LET i == tmp[t].ei
     IN  reg' = [reg EXCEPT ![i] =
                   [active |-> TRUE, seq |-> reg[i].seq,
                    address |-> tmp[t].addr, owner |-> t,
                    baseline |-> mem[tmp[t].addr], dr |-> DrOf(i)]]
  /\ pc' = [pc EXCEPT ![t] = "arm5"]
  /\ UNCHANGED <<mutex, operation, tls, dr, mem, budget, flags, tmp>>

ArmSeqEvenRelease(t) ==
  /\ pc[t] = "arm5"
  /\ reg' = [reg EXCEPT ![tmp[t].ei].seq = @ + 1]
  /\ mutex' = NoThread
  /\ pc' = [pc EXCEPT ![t] = "arm6"]
  /\ UNCHANGED <<operation, tls, dr, mem, budget, flags, tmp>>

ArmApplyAll(t) ==
  /\ pc[t] = "arm6"
  /\ LET i == tmp[t].ei
         s == reg[i].dr
         a == reg[i].address
         repaired == \E t2 \in Threads : dr[t2][s].addr = ForeignAddr
     IN  /\ dr' = [t2 \in Threads |-> [ss \in 1..NumSlots |->
                    IF ss = s THEN [addr |-> a, enabled |-> TRUE] ELSE dr[t2][ss]]]
         /\ tls' = [t2 \in Threads |-> [ss \in 1..NumSlots |->
                     IF ss = s THEN a ELSE tls[t2][ss]]]
         /\ flags' = [flags EXCEPT !.foreignRepair = (flags.foreignRepair \/ repaired)]
  /\ pc' = [pc EXCEPT ![t] = "idle"]
  /\ operation' = NoThread
  /\ UNCHANGED <<reg, mutex, mem, budget, tmp>>

(*** disarm path ***)

DisStart(t) ==
  /\ pc[t] = "idle" /\ mutex = NoThread /\ operation = NoThread
  /\ budget > 0
  /\ \E a \in Addresses :
      LET mine == {i \in 1..NumSlots :
                   reg[i].active /\ reg[i].owner = t /\ reg[i].address = a}
      IN  /\ mine # {}
          /\ \E i \in mine :
              /\ tmp' = [tmp EXCEPT ![t].ei = i, ![t].view = reg[i], ![t].addr = a]
              /\ budget' = budget - 1
              /\ mutex' = t
              /\ operation' = t
              /\ pc' = [pc EXCEPT ![t] = "dis2"]
  /\ UNCHANGED <<reg, tls, dr, mem, flags>>

(*** Release the short registry lock before clearing target hardware. ***)
DisReleaseRegistry(t) ==
  /\ pc[t] = "dis2"
  /\ mutex' = NoThread
  /\ pc' = [pc EXCEPT ![t] = "dis3"]
  /\ UNCHANGED <<reg, operation, tls, dr, mem, budget, flags, tmp>>

(*** Hardware is cleared while the registry entry remains reserved/active. ***)
DisApplyAll(t) ==
  /\ pc[t] = "dis3"
  /\ LET s == tmp[t].view.dr
         a == tmp[t].view.address
     IN  /\ dr' = [t2 \in Threads |-> [ss \in 1..NumSlots |->
                    IF ss = s /\ dr[t2][ss].addr = a
                    THEN [addr |-> NoAddr, enabled |-> FALSE]
                    ELSE dr[t2][ss]]]
         /\ tls' = [t2 \in Threads |-> [ss \in 1..NumSlots |->
                    IF ss = s /\ tls[t2][ss] = a THEN NoAddr ELSE tls[t2][ss]]]
  /\ pc' = [pc EXCEPT ![t] = "dis4"]
  /\ UNCHANGED <<reg, mutex, operation, mem, budget, flags, tmp>>

(*** Deactivation is published only after the hardware-clear sweep. ***)
DisSeqOdd(t) ==
  /\ pc[t] = "dis4"
  /\ mutex = NoThread
  /\ mutex' = t
  /\ reg' = [reg EXCEPT ![tmp[t].ei].seq = @ + 1]
  /\ pc' = [pc EXCEPT ![t] = "dis5"]
  /\ UNCHANGED <<operation, tls, dr, mem, budget, flags, tmp>>

DisDeactivate(t) ==
  /\ pc[t] = "dis5"
  /\ reg' = [reg EXCEPT ![tmp[t].ei].active = FALSE]
  /\ pc' = [pc EXCEPT ![t] = "dis6"]
  /\ UNCHANGED <<mutex, operation, tls, dr, mem, budget, flags, tmp>>

DisSeqEvenRelease(t) ==
  /\ pc[t] = "dis6"
  /\ reg' = [reg EXCEPT ![tmp[t].ei].seq = @ + 1]
  /\ mutex' = NoThread
  /\ operation' = NoThread
  /\ pc' = [pc EXCEPT ![t] = "idle"]
  /\ UNCHANGED <<tls, dr, mem, budget, flags, tmp>>

(*** write + trap path: the store commits, then the VEH snapshots and decides ***)

WrStart(t) ==
  /\ pc[t] = "idle"
  /\ \E a \in Addresses, v \in Values, wk \in WriterKinds :
      /\ mem' = [mem EXCEPT ![a] = v]
      /\ LET slots == {s \in 1..NumSlots : dr[t][s].enabled /\ dr[t][s].addr = a}
         IN  IF slots = {}
             THEN /\ flags' = [flags EXCEPT !.silent = TRUE]
                  /\ UNCHANGED <<pc, tmp>>
             ELSE \E s \in slots :
                    LET gov == {i \in 1..NumSlots : reg[i].dr = s}
                    IN  IF gov = {}
                        THEN /\ flags' = [flags EXCEPT !.foreignTrap = TRUE]
                             /\ UNCHANGED <<pc, tmp>>
                        ELSE \E i \in gov :
                               /\ tmp' = [tmp EXCEPT ![t].addr = a, ![t].v = v,
                                                     ![t].wk = wk, ![t].slot = s,
                                                     ![t].ei = i]
                               /\ pc' = [pc EXCEPT ![t] = "wr2"]
                               /\ UNCHANGED flags
  /\ UNCHANGED <<reg, mutex, operation, tls, dr, budget>>

WrReadSeq1(t) ==
  /\ pc[t] = "wr2"
  /\ tmp' = [tmp EXCEPT ![t].s1 = reg[tmp[t].ei].seq]
  /\ pc' = [pc EXCEPT ![t] = "wr3"]
  /\ UNCHANGED <<reg, mutex, operation, tls, dr, mem, budget, flags>>

WrReadPayload(t) ==
  /\ pc[t] = "wr3"
  /\ tmp' = [tmp EXCEPT ![t].view = reg[tmp[t].ei]]
  /\ pc' = [pc EXCEPT ![t] = "wr4"]
  /\ UNCHANGED <<reg, mutex, operation, tls, dr, mem, budget, flags>>

WrReadSeq2(t) ==
  /\ pc[t] = "wr4"
  /\ tmp' = [tmp EXCEPT ![t].s2 = reg[tmp[t].ei].seq]
  /\ pc' = [pc EXCEPT ![t] = "wr5"]
  /\ UNCHANGED <<reg, mutex, operation, tls, dr, mem, budget, flags>>

WrDecide(t) ==
  /\ pc[t] = "wr5"
  /\ LET e == tmp[t].view
         torn == (tmp[t].s1 # tmp[t].s2) \/ (tmp[t].s1 % 2 = 1)
         legit == tmp[t].wk = "allowed" /\ tmp[t].v = e.baseline /\ t = e.owner
     IN  IF torn
         THEN flags' = [flags EXCEPT !.torn = TRUE]
         ELSE IF ~e.active
              THEN flags' = [flags EXCEPT !.searchInactive = TRUE]
              ELSE IF legit
                   THEN flags' = [flags EXCEPT !.filtered = TRUE]
                   ELSE flags' = [flags EXCEPT !.hit = TRUE]
  /\ pc' = [pc EXCEPT ![t] = "idle"]
  /\ UNCHANGED <<reg, mutex, operation, tls, dr, mem, budget, tmp>>

(*** a foreign party stomps one of our armed DR slots (once per run) ***)

ForeignStomp ==
  /\ ~flags.stomped
  /\ \E t \in Threads, s \in 1..NumSlots :
      /\ dr[t][s].enabled /\ tls[t][s] # NoAddr
      /\ dr' = [dr EXCEPT ![t][s] = [addr |-> ForeignAddr, enabled |-> TRUE]]
      /\ flags' = [flags EXCEPT !.stomped = TRUE]
  /\ UNCHANGED <<pc, reg, mutex, operation, tls, mem, budget, tmp>>

Next ==
  \/ \E t \in Threads :
       \/ ArmStart(t) \/ ArmStartRejected(t) \/ ArmSeqOdd(t) \/ ArmPayload(t)
       \/ ArmSeqEvenRelease(t) \/ ArmApplyAll(t)
       \/ DisStart(t) \/ DisReleaseRegistry(t) \/ DisApplyAll(t)
       \/ DisSeqOdd(t) \/ DisDeactivate(t) \/ DisSeqEvenRelease(t)
       \/ WrStart(t) \/ WrReadSeq1(t) \/ WrReadPayload(t) \/ WrReadSeq2(t)
       \/ WrDecide(t)
  \/ ForeignStomp

Spec == Init /\ [][Next]_vars

(*** safety invariants ***)

MutexOK ==
  Cardinality({t \in Threads :
               pc[t] \in {"arm3","arm4","arm5","dis2","dis5","dis6"}}) <= 1

OperationOwnerOK ==
  operation = NoThread \/ pc[operation] \in
    {"arm3","arm4","arm5","arm6","dis2","dis3","dis4","dis5","dis6"}

LifecycleReservationOK ==
  \A t \in Threads :
    pc[t] \in {"arm3","arm4","arm5","arm6",
              "dis2","dis3","dis4","dis5","dis6"} => operation = t

OperationOwnsMutex == mutex = NoThread \/ operation = mutex

SlotIntegrity ==
  \A i, j \in 1..NumSlots :
    (i # j /\ reg[i].active /\ reg[j].active) => reg[i].dr # reg[j].dr

ActiveWellFormed ==
  \A i \in 1..NumSlots : reg[i].active =>
    /\ reg[i].dr = DrOf(i)
    /\ reg[i].address \in Addresses
    /\ reg[i].owner \in Threads
    /\ reg[i].baseline \in Values

Coherence ==
  \A t \in Threads, s \in 1..NumSlots :
    (dr[t][s].enabled /\ dr[t][s].addr # ForeignAddr) =>
      \E i \in 1..NumSlots :
        reg[i].active /\ reg[i].dr = s /\ reg[i].address = dr[t][s].addr

(*** At a lifecycle boundary, each active watch owns live hardware on each  ***)
(*** modeled thread, unless an explicit foreign stomp replaced that slot.  ***)
QuiescentCoverage ==
  operation = NoThread =>
    \A i \in 1..NumSlots : reg[i].active =>
      \A t \in Threads :
        LET slot == dr[t][reg[i].dr]
        IN  slot.enabled /\
            (slot.addr = reg[i].address \/
             (flags.stomped /\ slot.addr = ForeignAddr))

(*** state view for --max-error dedup: flags distinguish witnesses ***)
View == flags

(*** coverage witnesses (negated; used with WriteSentryCoverage.cfg) ***)
NoHit == ~flags.hit
NoFiltered == ~flags.filtered
NoTorn == ~flags.torn
NoSearchInactive == ~flags.searchInactive
NoRejected == ~flags.rejected
NoSilent == ~flags.silent
NoStomp == ~flags.stomped
NoForeignRepair == ~flags.foreignRepair
NoForeignTrap == ~flags.foreignTrap
====
