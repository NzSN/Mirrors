---- MODULE DpmReplayCounter ----
EXTENDS Integers, Sequences

VARIABLES q, rho, sigma, phase, i, receipt

(***************************************************************************)
(* Concrete serial two-actor instance of DpmReplay. Each actor has the      *)
(* local chain read, write, $done. SUT and model states record the two      *)
(* zero-based positions in those chains. The observation function and the   *)
(* oracle correspondence are identity relations.                           *)
(***************************************************************************)

ActorIds == {"a", "b"}
Actors == {"a", "b"}
Checkpoints == {"read", "write", "$done"}
DoneCheckpoint == "$done"
Step(a, k) == [actor |-> a, checkpoint |-> k]

ActorChains ==
  [a \in Actors |->
    IF a = "a" THEN <<"read", "write", "$done">>
    ELSE <<"read", "write", "$done">>]

ActionValues == {"a-read", "a-write", "a-done",
                 "b-read", "b-write", "b-done"}
Mapping ==
  [action \in ActionValues |->
    CASE action = "a-read"  -> Step("a", "read")
      [] action = "a-write" -> Step("a", "write")
      [] action = "a-done"  -> Step("a", "$done")
      [] action = "b-read"  -> Step("b", "read")
      [] action = "b-write" -> Step("b", "write")
      [] action = "b-done"  -> Step("b", "$done")]

TraceActions ==
  <<"a-read", "a-write", "a-done", "b-read", "b-write", "b-done">>
Schedule ==
  <<Step("a", "read"), Step("a", "write"), Step("a", "$done"),
    Step("b", "read"), Step("b", "write"), Step("b", "$done")>>

SUTStates == [a: 0..3, b: 0..3]
InitialState == [a |-> 0, b |-> 0]
ActualInitStates == {InitialState}
CleanupStates == SUTStates
ObservationValues == SUTStates
ModelValues == SUTStates
ObservationFn == [state \in SUTStates |-> state]
MatchRelation == {[obs |-> state, model |-> state] : state \in SUTStates}

Advance(state, actor) == [state EXCEPT ![actor] = state[actor] + 1]

ArrivalStepsFor(actor) ==
  {[actor |-> actor, label |-> "arrive",
    checkpoint |-> ActorChains[actor][state[actor] + 1],
    src |-> state, dst |-> Advance(state, actor)] :
    state \in {s \in SUTStates : s[actor] < 3}}

ArrivalSteps == UNION {ArrivalStepsFor(actor) : actor \in Actors}

StopSteps ==
  {[actor |-> actor, label |-> "stop", checkpoint |-> DoneCheckpoint,
    src |-> state, dst |-> state] : actor \in Actors, state \in SUTStates}

SUTSteps == ArrivalSteps \cup StopSteps

RECURSIVE BuildTrace(_, _)
BuildTrace(steps, state) ==
  IF steps = <<>> THEN <<state>>
  ELSE <<state>> \o BuildTrace(Tail(steps), Advance(state, Head(steps).actor))

TraceStates == BuildTrace(Schedule, InitialState)

Dpm ==
  INSTANCE DpmReplay WITH
    ActorIds <- ActorIds,
    Actors <- Actors,
    Checkpoints <- Checkpoints,
    DoneCheckpoint <- DoneCheckpoint,
    ActionValues <- ActionValues,
    ModelValues <- ModelValues,
    ObservationValues <- ObservationValues,
    SUTStates <- SUTStates,
    ActorChains <- ActorChains,
    TraceActions <- TraceActions,
    TraceStates <- TraceStates,
    Mapping <- Mapping,
    Schedule <- Schedule,
    ActualInitStates <- ActualInitStates,
    CleanupStates <- CleanupStates,
    ObservationFn <- ObservationFn,
    MatchRelation <- MatchRelation,
    SUTSteps <- SUTSteps

Spec == Dpm!Spec
Safety == Dpm!Safety
Finality == Dpm!Finality
SuccessfulReplay == Dpm!SuccessfulReplay

====
