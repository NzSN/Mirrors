---- MODULE WriteSentryMBT ----
(* Scheduled source-event oracle. Every event uses the canonical relation. *)
EXTENDS WriteSentry, Sequences
CONSTANT
  \* @type: Seq({ action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str });
  Plan
VARIABLES
  \* @type: Str;
  action_taken,
  \* @type: { action: Str, thread: Str, command: Str, address: Str, value: Str, writer: Str, span: Int, entry: Int, slot: Int, target: Str };
  parameters,
  \* @type: Int;
  step_count
MBTInit ==
  /\ Init
  /\ action_taken="init"
  /\ parameters=[action |-> "init",thread |-> "t1",command |-> "none",address |-> NoAddr,
       value |-> "good",writer |-> "allowed",span |-> 1,entry |-> 0,slot |-> 0,target |-> NoThread]
  /\ step_count=0
MBTNext ==
  /\ step_count < Len(Plan)
  /\ LET p == Plan[step_count+1] IN
       /\ Event(p)
       /\ action_taken'=p.action /\ parameters'=p
  /\ step_count'=step_count+1
MBTSafety == Safety /\ NoTorn /\ NoInactiveLease
MBTTraceIncomplete == MBTSafety /\ step_count < Len(Plan)
====
