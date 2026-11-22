---- MODULE DpmReplay ----
EXTENDS Integers, Sequences, FiniteSets

(***************************************************************************)
(* A bounded TLA+ encoding of specs/papers/dpm-replay-type-theory.tex.      *)
(*                                                                         *)
(* The module uses the paper's restricted replay profile: every scheduled  *)
(* checkpoint interval, including $done, is the image of one fully          *)
(* instantiated model action and has one subsequent observation.            *)
(* ActualInitStates is the image of Init(I, sigma) for the fixed input I.   *)
(* Receipt events are semantic events, not the raw SDK receipt schema.      *)
(*                                                                         *)
(* The index i and observation/fault indices remain zero-based as in the   *)
(* paper. TraceStates[j+1] therefore represents the paper's model state s_j.*)
(* No fairness is assumed: ReplayValid is existential and progress is not   *)
(* guaranteed. Artifact identity, cancellation, undeclared workers, actor   *)
(* and observer exceptions, timeouts, and cleanup failure are out of scope. *)
(***************************************************************************)

CONSTANTS
  ActorIds,            \* All identifiers allowed by configuration formation.
  Actors,              \* Declared actors, a subset of ActorIds.
  Checkpoints,
  DoneCheckpoint,
  ActionValues,        \* Fully instantiated model actions.
  ModelValues,
  ObservationValues,
  SUTStates,
  ActorChains,         \* [Actors -> Seq(Checkpoints)]
  TraceActions,        \* Sequence of ActionValues, length n.
  TraceStates,         \* Sequence of ModelValues, length n+1.
  Mapping,             \* [ActionValues -> actor/checkpoint steps]
  Schedule,            \* Full admitted schedule Q0.
  ActualInitStates,    \* Actual states satisfying Init(I, sigma).
  CleanupStates,       \* Actual states satisfying CleanupOk(sigma).
  ObservationFn,       \* [SUTStates -> ObservationValues]
  MatchRelation,       \* Pairs [obs, model] in the Mirrors correspondence.
  SUTSteps             \* Labeled actual worker transitions.

N == Len(TraceActions)
Modes == {"parked", "running", "done"}
Steps == [actor: ActorIds, checkpoint: Checkpoints]

Quiet == [tag |-> "quiet"]
Succeeded == [tag |-> "succeeded"]
Run(a, k) == [tag |-> "run", actor |-> a, checkpoint |-> k]
Check(j) == [tag |-> "check", index |-> j]
Failed(e) == [tag |-> "failed", fault |-> e]

PermitEvent(a, k) == [tag |-> "permit", actor |-> a, checkpoint |-> k]
ArrivalEvent(a, k) == [tag |-> "arrival", actor |-> a, checkpoint |-> k]
ObservationEvent(j, o) == [tag |-> "observation", index |-> j, obs |-> o]
FaultEvent(e) == [tag |-> "fault", fault |-> e]
CleanupEvent == [tag |-> "cleanup"]

UnexpectedFaults ==
  [tag: {"unexpected"},
   expectedActor: ActorIds, expectedCheckpoint: Checkpoints,
   actualActor: ActorIds, actualCheckpoint: Checkpoints]
PrematureFaults == [tag: {"premature"}, actor: ActorIds]
MismatchFaults ==
  [tag: {"modelMismatch"}, index: 0..N,
   obs: ObservationValues, model: ModelValues]
Faults == UnexpectedFaults \cup PrematureFaults \cup MismatchFaults

Events ==
  [tag: {"permit"}, actor: ActorIds, checkpoint: Checkpoints]
  \cup [tag: {"arrival"}, actor: ActorIds, checkpoint: Checkpoints]
  \cup [tag: {"observation"}, index: 0..N, obs: ObservationValues]
  \cup [tag: {"fault"}, fault: Faults]
  \cup [tag: {"cleanup"}]

Phases ==
  [tag: {"quiet"}]
  \cup [tag: {"succeeded"}]
  \cup [tag: {"run"}, actor: ActorIds, checkpoint: Checkpoints]
  \cup [tag: {"check"}, index: 0..N]
  \cup [tag: {"failed"}, fault: Faults]

StaticAssumptions ==
  /\ IsFiniteSet(ActorIds)
  /\ IsFiniteSet(Checkpoints)
  /\ IsFiniteSet(ActionValues)
  /\ Actors \subseteq ActorIds
  /\ DoneCheckpoint \in Checkpoints
  /\ ActorChains \in [Actors -> Seq(Checkpoints)]
  /\ TraceActions \in Seq(ActionValues)
  /\ TraceStates \in Seq(ModelValues)
  /\ Mapping \in [ActionValues -> Steps]
  /\ Schedule \in Seq(Steps)
  /\ ActualInitStates \subseteq SUTStates
  /\ CleanupStates \subseteq SUTStates
  /\ ObservationFn \in [SUTStates -> ObservationValues]
  /\ MatchRelation \subseteq [obs: ObservationValues, model: ModelValues]
  /\ SUTSteps \subseteq
       [actor: Actors, label: {"internal", "arrive", "stop"},
        checkpoint: Checkpoints, src: SUTStates, dst: SUTStates]

ASSUME StaticAssumptions

ScheduleOf(actions) == [j \in 1..Len(actions) |-> Mapping[actions[j]]]

RECURSIVE Project(_, _)
Project(a, steps) ==
  IF steps = <<>> THEN <<>>
  ELSE IF Head(steps).actor = a
    THEN <<Head(steps)>> \o Project(a, Tail(steps))
    ELSE Project(a, Tail(steps))

ActorsOf(steps) == {steps[j].actor : j \in DOMAIN steps}

WellChain(chain) ==
  /\ Len(chain) > 0
  /\ chain[Len(chain)] = DoneCheckpoint
  /\ \A j \in 1..(Len(chain)-1) : chain[j] /= DoneCheckpoint

Admissible ==
  /\ Len(TraceStates) = N + 1
  /\ Schedule = ScheduleOf(TraceActions)
  /\ ActorsOf(Schedule) = Actors
  /\ \A a \in Actors :
       /\ WellChain(ActorChains[a])
       /\ Project(a, Schedule) = ActorChains[a]

VARIABLES q, rho, sigma, phase, i, receipt
vars == <<q, rho, sigma, phase, i, receipt>>

TypeOK ==
  /\ q \in Seq(Steps)
  /\ rho \in [Actors -> Modes]
  /\ sigma \in SUTStates
  /\ phase \in Phases
  /\ i \in 0..(N+1)
  /\ receipt \in Seq(Events)

Matches(o, j) == [obs |-> o, model |-> TraceStates[j+1]] \in MatchRelation

Init ==
  /\ Admissible
  /\ sigma \in ActualInitStates
  /\ q = Schedule
  /\ rho = [a \in Actors |-> "parked"]
  /\ phase = Check(0)
  /\ i = 0
  /\ receipt = <<>>

ObserveMatch ==
  /\ phase.tag = "check"
  /\ phase.index = i
  /\ Matches(ObservationFn[sigma], i)
  /\ phase' = Quiet
  /\ i' = i + 1
  /\ receipt' = Append(receipt, ObservationEvent(i, ObservationFn[sigma]))
  /\ UNCHANGED <<q, rho, sigma>>

ObserveMismatch ==
  /\ phase.tag = "check"
  /\ phase.index = i
  /\ ~Matches(ObservationFn[sigma], i)
  /\ LET fault == [tag |-> "modelMismatch", index |-> i,
                   obs |-> ObservationFn[sigma], model |-> TraceStates[i+1]]
     IN /\ phase' = Failed(fault)
        /\ receipt' = Append(receipt, FaultEvent(fault))
  /\ UNCHANGED <<q, rho, sigma, i>>

Permit ==
  /\ phase = Quiet
  /\ q /= <<>>
  /\ Head(q).actor \in Actors
  /\ rho[Head(q).actor] = "parked"
  /\ rho' = [rho EXCEPT ![Head(q).actor] = "running"]
  /\ phase' = Run(Head(q).actor, Head(q).checkpoint)
  /\ receipt' = Append(receipt, PermitEvent(Head(q).actor, Head(q).checkpoint))
  /\ UNCHANGED <<q, sigma, i>>

InternalStep ==
  /\ phase.tag = "run"
  /\ phase.actor \in Actors
  /\ rho[phase.actor] = "running"
  /\ \E step \in SUTSteps :
       /\ step.actor = phase.actor
       /\ step.label = "internal"
       /\ step.src = sigma
       /\ sigma' = step.dst
  /\ UNCHANGED <<q, rho, phase, i, receipt>>

ExpectedArrival ==
  /\ phase.tag = "run"
  /\ q /= <<>>
  /\ Head(q) = [actor |-> phase.actor, checkpoint |-> phase.checkpoint]
  /\ phase.actor \in Actors
  /\ rho[phase.actor] = "running"
  /\ 1 <= i
  /\ i <= N
  /\ \E step \in SUTSteps :
       /\ step.actor = phase.actor
       /\ step.label = "arrive"
       /\ step.checkpoint = phase.checkpoint
       /\ step.src = sigma
       /\ sigma' = step.dst
  /\ q' = Tail(q)
  /\ rho' = [rho EXCEPT ![phase.actor] =
       IF phase.checkpoint = DoneCheckpoint THEN "done" ELSE "parked"]
  /\ phase' = Check(i)
  /\ receipt' = Append(receipt, ArrivalEvent(phase.actor, phase.checkpoint))
  /\ UNCHANGED i

UnexpectedArrival ==
  /\ phase.tag = "run"
  /\ q /= <<>>
  /\ Head(q) = [actor |-> phase.actor, checkpoint |-> phase.checkpoint]
  /\ phase.actor \in Actors
  /\ rho[phase.actor] = "running"
  /\ \E step \in SUTSteps :
       LET fault == [tag |-> "unexpected",
                     expectedActor |-> phase.actor,
                     expectedCheckpoint |-> phase.checkpoint,
                     actualActor |-> step.actor,
                     actualCheckpoint |-> step.checkpoint]
       IN /\ step.label = "arrive"
          /\ step.src = sigma
          /\ (step.actor /= phase.actor \/ step.checkpoint /= phase.checkpoint)
          /\ sigma' = step.dst
          /\ phase' = Failed(fault)
          /\ receipt' = Append(receipt, FaultEvent(fault))
  /\ UNCHANGED <<q, rho, i>>

PrematureReturn ==
  /\ phase.tag = "run"
  /\ q /= <<>>
  /\ Head(q) = [actor |-> phase.actor, checkpoint |-> phase.checkpoint]
  /\ phase.actor \in Actors
  /\ rho[phase.actor] = "running"
  /\ \E step \in SUTSteps :
       LET fault == [tag |-> "premature", actor |-> phase.actor]
       IN /\ step.actor = phase.actor
          /\ step.label = "stop"
          /\ step.src = sigma
          /\ sigma' = step.dst
          /\ phase' = Failed(fault)
          /\ receipt' = Append(receipt, FaultEvent(fault))
  /\ UNCHANGED <<q, rho, i>>

SuccessfulCompletion ==
  /\ q = <<>>
  /\ phase = Quiet
  /\ i = N + 1
  /\ \A a \in Actors : rho[a] = "done"
  /\ sigma \in CleanupStates
  /\ phase' = Succeeded
  /\ receipt' = Append(receipt, CleanupEvent)
  /\ UNCHANGED <<q, rho, sigma, i>>

Next ==
  ObserveMatch \/ ObserveMismatch \/ Permit \/ InternalStep \/
  ExpectedArrival \/ UnexpectedArrival \/ PrematureReturn \/
  SuccessfulCompletion

Spec == Init /\ [][Next]_vars

FinalState == phase.tag = "succeeded" \/ phase.tag = "failed"
SuccessfulReplay == phase = Succeeded /\ q = <<>> /\ i = N + 1
Finality == FinalState => ~ENABLED Next

CoordinatorModeInvariant ==
  /\ Cardinality({a \in Actors : rho[a] = "running"}) <= 1
  /\ \A a \in Actors :
       rho[a] = "running" =>
         ((phase.tag = "run" /\ phase.actor = a) \/ phase.tag = "failed")

QuiescentObservation ==
  phase.tag = "check" => \A a \in Actors : rho[a] /= "running"

RECURSIVE PermitSteps(_)
PermitSteps(events) ==
  IF events = <<>> THEN <<>>
  ELSE IF Head(events).tag = "permit"
    THEN <<[actor |-> Head(events).actor,
            checkpoint |-> Head(events).checkpoint]>> \o PermitSteps(Tail(events))
    ELSE PermitSteps(Tail(events))

RECURSIVE ArrivalSteps(_)
ArrivalSteps(events) ==
  IF events = <<>> THEN <<>>
  ELSE IF Head(events).tag = "arrival"
    THEN <<[actor |-> Head(events).actor,
            checkpoint |-> Head(events).checkpoint]>> \o ArrivalSteps(Tail(events))
    ELSE ArrivalSteps(Tail(events))

RECURSIVE ObservationEvents(_)
ObservationEvents(events) ==
  IF events = <<>> THEN <<>>
  ELSE IF Head(events).tag = "observation"
    THEN <<Head(events)>> \o ObservationEvents(Tail(events))
    ELSE ObservationEvents(Tail(events))

ScheduleFidelity ==
  phase = Succeeded =>
    /\ PermitSteps(receipt) = Schedule
    /\ ArrivalSteps(receipt) = Schedule

ObservationCorrespondence ==
  phase = Succeeded =>
    LET observations == ObservationEvents(receipt)
    IN /\ Len(observations) = N + 1
       /\ \A j \in 0..N :
            /\ observations[j+1].index = j
            /\ Matches(observations[j+1].obs, j)

Safety ==
  /\ TypeOK
  /\ CoordinatorModeInvariant
  /\ QuiescentObservation
  /\ ScheduleFidelity
  /\ ObservationCorrespondence

(***************************************************************************)
(* Optional order-preserving merge relation from the paper. It is not part  *)
(* of Next and makes no completeness or model-comparison claim by itself.   *)
(***************************************************************************)
RECURSIVE IsMerge(_, _, _)
IsMerge(xs, ys, zs) ==
  \/ xs = <<>> /\ ys = <<>> /\ zs = <<>>
  \/ xs /= <<>> /\ zs /= <<>> /\ Head(xs) = Head(zs)
     /\ IsMerge(Tail(xs), ys, Tail(zs))
  \/ ys /= <<>> /\ zs /= <<>> /\ Head(ys) = Head(zs)
     /\ IsMerge(xs, Tail(ys), Tail(zs))

====
