--------------------------- MODULE ScheduledCounter ---------------------------
EXTENDS Integers, FiniteSets
VARIABLES
  \* @type: Int;
  count,
  \* @type: Str -> Int;
  saved,
  \* @type: Str -> Int;
  phase,
  \* @type: Str;
  action_taken,
  \* @type: { actor: Str };
  parameters
Actors == {"a", "b"}
InitWith(initial) ==
  /\ count = initial
  /\ saved = [actor \in Actors |-> 0]
  /\ phase = [actor \in Actors |-> 0]
  /\ action_taken = "init"
  /\ parameters = [actor |-> "a"]
Init == InitWith(0)
InitFive == InitWith(5)
Read(actor) ==
  /\ phase[actor] = 0
  /\ saved' = [saved EXCEPT ![actor] = count]
  /\ phase' = [phase EXCEPT ![actor] = 1]
  /\ action_taken' = "read"
  /\ parameters' = [actor |-> actor]
  /\ UNCHANGED count
Write(actor) ==
  /\ phase[actor] = 1
  /\ count' = saved[actor] + 1
  /\ phase' = [phase EXCEPT ![actor] = 2]
  /\ action_taken' = "write"
  /\ parameters' = [actor |-> actor]
  /\ UNCHANGED saved
Finish(actor) ==
  /\ phase[actor] = 2
  /\ phase' = [phase EXCEPT ![actor] = 3]
  /\ action_taken' = "finish"
  /\ parameters' = [actor |-> actor]
  /\ UNCHANGED <<count, saved>>
Next == \E actor \in Actors : Read(actor) \/ Write(actor) \/ Finish(actor)
NextSerial ==
  IF phase["a"] < 3 THEN Read("a") \/ Write("a") \/ Finish("a")
  ELSE Read("b") \/ Write("b") \/ Finish("b")
NextOverlap ==
  IF phase["a"] = 0 THEN Read("a")
  ELSE IF phase["b"] = 0 THEN Read("b")
  ELSE IF phase["a"] = 1 THEN Write("a")
  ELSE IF phase["b"] = 1 THEN Write("b")
  ELSE IF phase["a"] = 2 THEN Finish("a")
  ELSE Finish("b")
Safety == /\ count \in 0..7
          /\ saved \in [Actors -> 0..7]
          /\ phase \in [Actors -> 0..3]
TraceComplete == ~(\A actor \in Actors : phase[actor] = 3)
=============================================================================
