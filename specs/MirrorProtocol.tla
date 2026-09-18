---------------- MODULE MirrorProtocol ---------------------
EXTENDS Integers, Sequences, FiniteSets, Apalache

\* -----------------------------------------------------------------------------
\* Protocol phases (mirror side)
\* -----------------------------------------------------------------------------

Ms == {"idle", "validating", "generating", "ready", "stepping", "exploring", "done"}

\* Client phases
Cs == Ms \cup {"waiting_validation", "waiting_gen", "waiting_init", "waiting_action", "waiting_ack", "waiting_done", "waiting_validate"}

\* Message tags (integers so TLC can enumerate the domain)
REGISTER           == 0
REGISTER_ERROR     == 1
REPORT_STATE       == 2
SPEC_VALIDATED     == 3
INITIAL_STATE      == 4
NEXT_STEP          == 5
STEP_OK            == 6
STEP_MISMATCH      == 7
ALL_STEPS_DONE     == 8
REGISTER_VALIDATE  == 9
REGISTER_TRACES    == 10
REGISTER_TRACE_GEN == 11
GEN_TRACES_DONE    == 12
REGISTER_EXPLORE   == 13
REGISTER_EXPLORER_SESSION == 14
EXPLORER_READY     == 15
EXPLORE_CMD        == 16
EXPLORE_RESULT     == 17
EXPLORE_DONE       == 18

\* -----------------------------------------------------------------------------
\* Variables
\* -----------------------------------------------------------------------------

VARIABLE
  \* @type: Str;
  mirror_phase,           \* mirror phase
  \* @type: Str;
  client_phase,           \* client phase
  \* @type: Str;
  action_taken, \* label of the action executed at this step
  \* @type: Str;
  mirror_flow,        \* active registration flow: "none" | "traces" | "session" | "validate"
  \* @type: Seq(Int);
  client_to_mirror,    \* client → mirror: message queue (tags)
  \* @type: Seq(Int);
  mirror_to_client,    \* mirror → client: message queue (tags)
  \* @type: Bool;
  report_matches, \* payload bit set by ClientReport: whether the client's
                 \* reported state matches the expected state. Chosen
                 \* nondeterministically so the model (not the fixture)
                 \* decides the Ok/AllDone/Mismatch branch.
  \* @type: Bool;
  faulted,      \* set by fault-injection actions (MirrorProtocolFaults);
                \* invariants are only checked on fault-free paths
  \* @type: Bool;
  client_closed,    \* client closed the connection prematurely
  \* @type: Bool;
  mirror_closed    \* mirror closed the connection prematurely

\* -----------------------------------------------------------------------------
\* Client actions — send
\* -----------------------------------------------------------------------------

ClientRegister ==
  /\ client_phase = "idle"
  /\ mirror_phase = "idle"
  /\ client_to_mirror = <<>>
  /\ client_phase' = "waiting_validation"
  /\ client_to_mirror' = Append(client_to_mirror, REGISTER)
  /\ action_taken' = "ClientRegister"
  /\ UNCHANGED <<mirror_phase, mirror_to_client, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

ClientRegisterTraces ==
  /\ client_phase = "idle"
  /\ mirror_phase = "idle"
  /\ client_to_mirror = <<>>
  /\ client_phase' = "waiting_validation"
  /\ client_to_mirror' = Append(client_to_mirror, REGISTER_TRACES)
  /\ action_taken' = "ClientRegisterTraces"
  /\ UNCHANGED <<mirror_phase, mirror_to_client, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

ClientRegisterGenTraces ==
  /\ client_phase = "idle"
  /\ mirror_phase = "idle"
  /\ client_to_mirror = <<>>
  /\ client_phase' = "waiting_gen"
  /\ client_to_mirror' = Append(client_to_mirror, REGISTER_TRACE_GEN)
  /\ action_taken' = "ClientRegisterGenTraces"
  /\ UNCHANGED <<mirror_phase, mirror_to_client, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

\* Interactive symbolic exploration: at the message level the explore
\* flow is identical to Register (validate → step through states), so it
\* reuses the same mirror/client phases and step messages.
ClientRegisterExplore ==
  /\ client_phase = "idle"
  /\ mirror_phase = "idle"
  /\ client_to_mirror = <<>>
  /\ client_phase' = "waiting_validation"
  /\ client_to_mirror' = Append(client_to_mirror, REGISTER_EXPLORE)
  /\ action_taken' = "ClientRegisterExplore"
  /\ UNCHANGED <<mirror_phase, mirror_to_client, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

\* Client-driven interactive symbolic checking: the client opens an
\* explore session and then issues explorer commands (assumeTransition,
\* nextStep, query, checkInvariant, assumeState, rollback) itself; the
\* mirror forwards them to the apalache explorer server and returns the
\* results. Commands and results strictly alternate.
ClientRegisterExploreSession ==
  /\ client_phase = "idle"
  /\ mirror_phase = "idle"
  /\ client_to_mirror = <<>>
  /\ client_phase' = "waiting_validation"
  /\ client_to_mirror' = Append(client_to_mirror, REGISTER_EXPLORER_SESSION)
  /\ action_taken' = "ClientRegisterExploreSession"
  /\ UNCHANGED <<mirror_phase, mirror_to_client, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

\* Validate-only path: the client asks the mirror to validate the spec
\* (typecheck + bounded model check) and stop — no trace generation, no
\* stepping. The SpecValidated reply (valid or invalid) ends the session.
ClientRegisterValidate ==
  /\ client_phase = "idle"
  /\ mirror_phase = "idle"
  /\ client_to_mirror = <<>>
  /\ client_phase' = "waiting_validate"
  /\ client_to_mirror' = Append(client_to_mirror, REGISTER_VALIDATE)
  /\ action_taken' = "ClientRegisterValidate"
  /\ UNCHANGED <<mirror_phase, mirror_to_client, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

ClientExploreCmd ==
  /\ client_phase = "exploring"
  /\ client_to_mirror = <<>>
  /\ mirror_to_client = <<>>
  /\ client_to_mirror' = Append(client_to_mirror, EXPLORE_CMD)
  /\ action_taken' = "ClientExploreCmd"
  /\ UNCHANGED <<mirror_phase, client_phase, mirror_to_client, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

ClientExploreDone ==
  /\ client_phase = "exploring"
  /\ client_to_mirror = <<>>
  /\ mirror_to_client = <<>>
  /\ client_to_mirror' = Append(client_to_mirror, EXPLORE_DONE)
  /\ client_phase' = "waiting_done"
  /\ action_taken' = "ClientExploreDone"
  /\ UNCHANGED <<mirror_phase, mirror_to_client, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

ClientReport ==
  /\ client_phase = "waiting_action"
  /\ client_to_mirror = <<>>
  /\ client_phase' = "waiting_ack"
  /\ client_to_mirror' = Append(client_to_mirror, REPORT_STATE)
  /\ report_matches' \in BOOLEAN
  /\ action_taken' = "ClientReport"
  /\ UNCHANGED <<mirror_phase, mirror_to_client, mirror_flow, faulted, client_closed, mirror_closed>>

\* -----------------------------------------------------------------------------
\* Client actions — receive messages from mirror
\* -----------------------------------------------------------------------------

ClientRecvSpecValidated ==
  /\ mirror_to_client /= <<>> /\ Head(mirror_to_client) = SPEC_VALIDATED
  /\ client_phase = "waiting_validation"
  /\ client_phase' = "waiting_init"
  /\ mirror_to_client' = Tail(mirror_to_client)
  /\ action_taken' = "ClientRecvSpecValidated"
  /\ UNCHANGED <<mirror_phase, client_to_mirror, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

\* Validate-only: the SpecValidated reply (valid or invalid — same tag,
\* the outcome rides in the payload) ends the session.
ClientRecvSpecValidatedDone ==
  /\ mirror_to_client /= <<>> /\ Head(mirror_to_client) = SPEC_VALIDATED
  /\ client_phase = "waiting_validate"
  /\ client_phase' = "done"
  /\ mirror_to_client' = Tail(mirror_to_client)
  /\ action_taken' = "ClientRecvSpecValidatedDone"
  /\ UNCHANGED <<mirror_phase, client_to_mirror, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

ClientRecvGenTracesDone ==
  /\ mirror_to_client /= <<>> /\ Head(mirror_to_client) = GEN_TRACES_DONE
  /\ client_phase = "waiting_gen"
  /\ client_phase' = "idle"
  /\ mirror_to_client' = Tail(mirror_to_client)
  /\ action_taken' = "ClientRecvGenTracesDone"
  /\ UNCHANGED <<mirror_phase, client_to_mirror, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

ClientRecvInitialState ==
  /\ mirror_to_client /= <<>> /\ Head(mirror_to_client) = INITIAL_STATE
  /\ client_phase = "waiting_init"
  /\ client_phase' = "waiting_action"
  /\ mirror_to_client' = Tail(mirror_to_client)
  /\ action_taken' = "ClientRecvInitialState"
  /\ UNCHANGED <<mirror_phase, client_to_mirror, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

ClientRecvNextStep ==
  /\ mirror_to_client /= <<>> /\ Head(mirror_to_client) = NEXT_STEP
  /\ client_phase = "waiting_ack"
  /\ client_phase' = "waiting_action"
  /\ mirror_to_client' = Tail(mirror_to_client)
  /\ action_taken' = "ClientRecvNextStep"
  /\ UNCHANGED <<mirror_phase, client_to_mirror, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

ClientRecvStepOk ==
  /\ mirror_to_client /= <<>> /\ Head(mirror_to_client) = STEP_OK
  /\ client_phase = "waiting_ack"
  /\ client_phase' = "waiting_ack"
  /\ mirror_to_client' = Tail(mirror_to_client)
  /\ action_taken' = "ClientRecvStepOk"
  /\ UNCHANGED <<mirror_phase, client_to_mirror, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

ClientRecvStepMismatch ==
  /\ mirror_to_client /= <<>> /\ Head(mirror_to_client) = STEP_MISMATCH
  /\ client_phase' = "done"
  /\ mirror_to_client' = Tail(mirror_to_client)
  /\ action_taken' = "ClientRecvStepMismatch"
  /\ UNCHANGED <<mirror_phase, client_to_mirror, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

ClientRecvAllStepsDone ==
  /\ mirror_to_client /= <<>> /\ Head(mirror_to_client) = ALL_STEPS_DONE
  /\ client_phase = "waiting_ack"
  /\ client_phase' = "done"
  /\ mirror_to_client' = Tail(mirror_to_client)
  /\ action_taken' = "ClientRecvAllStepsDone"
  /\ UNCHANGED <<mirror_phase, client_to_mirror, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

\* RegisterError replies to any registration request, including
\* RegisterValidate (inline-spec materialization or apalache-mc failure).
ClientRecvRegisterError ==
  /\ mirror_to_client /= <<>> /\ Head(mirror_to_client) = REGISTER_ERROR
  /\ client_phase \in {"waiting_validation", "waiting_validate"}
  /\ client_phase' = "done"
  /\ mirror_to_client' = Tail(mirror_to_client)
  /\ action_taken' = "ClientRecvRegisterError"
  /\ UNCHANGED <<mirror_phase, client_to_mirror, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

ClientRecvExplorerReady ==
  /\ mirror_to_client /= <<>> /\ Head(mirror_to_client) = EXPLORER_READY
  /\ client_phase = "waiting_validation"
  /\ client_phase' = "exploring"
  /\ mirror_to_client' = Tail(mirror_to_client)
  /\ action_taken' = "ClientRecvExplorerReady"
  /\ UNCHANGED <<mirror_phase, client_to_mirror, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

ClientRecvExploreResult ==
  /\ mirror_to_client /= <<>> /\ Head(mirror_to_client) = EXPLORE_RESULT
  /\ client_phase = "exploring"
  /\ mirror_to_client' = Tail(mirror_to_client)
  /\ action_taken' = "ClientRecvExploreResult"
  /\ UNCHANGED <<mirror_phase, client_phase, client_to_mirror, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

ClientRecvExploreDoneAck ==
  /\ mirror_to_client /= <<>> /\ Head(mirror_to_client) = EXPLORE_DONE
  /\ client_phase = "waiting_done"
  /\ client_phase' = "done"
  /\ mirror_to_client' = Tail(mirror_to_client)
  /\ action_taken' = "ClientRecvExploreDoneAck"
  /\ UNCHANGED <<mirror_phase, client_to_mirror, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

\* -----------------------------------------------------------------------------
\* Mirror actions — receive messages from client
\* -----------------------------------------------------------------------------

MirrorRecvRegister ==
  /\ client_to_mirror /= <<>> /\ Head(client_to_mirror) = REGISTER
  /\ mirror_phase = "idle"
  /\ mirror_phase' = "validating"
  /\ mirror_flow' = "traces"
  /\ client_to_mirror' = Tail(client_to_mirror)
  /\ action_taken' = "MirrorRecvRegister"
  /\ UNCHANGED <<client_phase, mirror_to_client, report_matches, faulted, client_closed, mirror_closed>>

MirrorRecvRegisterTraces ==
  /\ client_to_mirror /= <<>> /\ Head(client_to_mirror) = REGISTER_TRACES
  /\ mirror_phase = "idle"
  /\ mirror_phase' = "ready"
  /\ mirror_flow' = "traces"
  /\ client_to_mirror' = Tail(client_to_mirror)
  /\ mirror_to_client' = Append(mirror_to_client, SPEC_VALIDATED)
  /\ action_taken' = "MirrorRecvRegisterTraces"
  /\ UNCHANGED <<client_phase, report_matches, faulted, client_closed, mirror_closed>>

\* A stepping registration may fail admission before any replay output (for
\* example, required model-interface negotiation or trace preflight). This is
\* an alternative to MirrorRecvRegisterTraces, not an extra wire round trip.
MirrorRecvRegisterTracesError ==
  /\ client_to_mirror /= <<>> /\ Head(client_to_mirror) = REGISTER_TRACES
  /\ mirror_phase = "idle"
  /\ mirror_phase' = "done"
  /\ mirror_flow' = "traces"
  /\ client_to_mirror' = Tail(client_to_mirror)
  /\ mirror_to_client' = Append(mirror_to_client, REGISTER_ERROR)
  /\ action_taken' = "MirrorRecvRegisterTracesError"
  /\ UNCHANGED <<client_phase, report_matches, faulted, client_closed, mirror_closed>>

MirrorRecvRegisterGenTraces ==
  /\ client_to_mirror /= <<>> /\ Head(client_to_mirror) = REGISTER_TRACE_GEN
  /\ mirror_phase = "idle"
  /\ mirror_phase' = "generating"
  /\ mirror_flow' = "traces"
  /\ client_to_mirror' = Tail(client_to_mirror)
  /\ action_taken' = "MirrorRecvRegisterGenTraces"
  /\ UNCHANGED <<client_phase, mirror_to_client, report_matches, faulted, client_closed, mirror_closed>>

MirrorRecvRegisterExplore ==
  /\ client_to_mirror /= <<>> /\ Head(client_to_mirror) = REGISTER_EXPLORE
  /\ mirror_phase = "idle"
  /\ mirror_phase' = "validating"
  /\ mirror_flow' = "traces"
  /\ client_to_mirror' = Tail(client_to_mirror)
  /\ action_taken' = "MirrorRecvRegisterExplore"
  /\ UNCHANGED <<client_phase, mirror_to_client, report_matches, faulted, client_closed, mirror_closed>>

MirrorRecvRegisterExploreSession ==
  /\ client_to_mirror /= <<>> /\ Head(client_to_mirror) = REGISTER_EXPLORER_SESSION
  /\ mirror_phase = "idle"
  /\ mirror_phase' = "validating"
  /\ mirror_flow' = "session"
  /\ client_to_mirror' = Tail(client_to_mirror)
  /\ action_taken' = "MirrorRecvRegisterExploreSession"
  /\ UNCHANGED <<client_phase, mirror_to_client, report_matches, faulted, client_closed, mirror_closed>>

MirrorRecvRegisterValidate ==
  /\ client_to_mirror /= <<>> /\ Head(client_to_mirror) = REGISTER_VALIDATE
  /\ mirror_phase = "idle"
  /\ mirror_phase' = "validating"
  /\ mirror_flow' = "validate"
  /\ client_to_mirror' = Tail(client_to_mirror)
  /\ action_taken' = "MirrorRecvRegisterValidate"
  /\ UNCHANGED <<client_phase, mirror_to_client, report_matches, faulted, client_closed, mirror_closed>>

MirrorRecvExploreCmd ==
  /\ client_to_mirror /= <<>> /\ Head(client_to_mirror) = EXPLORE_CMD
  /\ mirror_phase = "exploring"
  /\ client_to_mirror' = Tail(client_to_mirror)
  /\ mirror_to_client' = Append(mirror_to_client, EXPLORE_RESULT)
  /\ action_taken' = "MirrorRecvExploreCmd"
  /\ UNCHANGED <<mirror_phase, client_phase, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

MirrorRecvExploreDone ==
  /\ client_to_mirror /= <<>> /\ Head(client_to_mirror) = EXPLORE_DONE
  /\ mirror_phase = "exploring"
  /\ mirror_phase' = "done"
  /\ client_to_mirror' = Tail(client_to_mirror)
  /\ mirror_to_client' = Append(mirror_to_client, EXPLORE_DONE)
  /\ action_taken' = "MirrorRecvExploreDone"
  /\ UNCHANGED <<client_phase, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

\* Mirror receives ReportState.
\* Three distinct actions encode: match with more steps, match on the
\* last step, and mismatch — split so trace projection can tell them apart.
MirrorRecvReportOk ==
  /\ client_to_mirror /= <<>> /\ Head(client_to_mirror) = REPORT_STATE
  /\ mirror_phase = "stepping"
  /\ report_matches
  /\ client_to_mirror' = Tail(client_to_mirror)
  /\ mirror_phase' = "stepping"                \* match, more steps remain
  /\ mirror_to_client' = Append(mirror_to_client, STEP_OK)            \* queued; NextStep sent separately
  /\ action_taken' = "MirrorRecvReportOk"
  /\ UNCHANGED <<client_phase, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

MirrorRecvReportAllDone ==
  /\ client_to_mirror /= <<>> /\ Head(client_to_mirror) = REPORT_STATE
  /\ mirror_phase = "stepping"
  /\ report_matches
  /\ client_to_mirror' = Tail(client_to_mirror)
  /\ mirror_phase' = "done"                    \* match, last step
  /\ mirror_to_client' = Append(mirror_to_client, ALL_STEPS_DONE)
  /\ action_taken' = "MirrorRecvReportAllDone"
  /\ UNCHANGED <<client_phase, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

MirrorRecvReportMismatch ==
  /\ client_to_mirror /= <<>> /\ Head(client_to_mirror) = REPORT_STATE
  /\ mirror_phase = "stepping"
  /\ ~report_matches
  /\ client_to_mirror' = Tail(client_to_mirror)
  /\ mirror_phase' = "done"                    \* mismatch
  /\ mirror_to_client' = Append(mirror_to_client, STEP_MISMATCH)
  /\ action_taken' = "MirrorRecvReportMismatch"
  /\ UNCHANGED <<client_phase, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

\* -----------------------------------------------------------------------------
\* Mirror actions — send messages to client
\* -----------------------------------------------------------------------------

MirrorSendGenTracesDone ==
  /\ mirror_phase = "generating"
  /\ mirror_to_client = <<>>
  /\ mirror_phase' = "idle"
  /\ mirror_to_client' = Append(mirror_to_client, GEN_TRACES_DONE)
  /\ action_taken' = "MirrorSendGenTracesDone"
  /\ UNCHANGED <<client_phase, client_to_mirror, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

MirrorSendSpecValidatedValid ==
  /\ mirror_phase = "validating"
  /\ mirror_to_client = <<>>
  /\ \/ /\ mirror_flow = "traces"    \* stepping flow: session continues
        /\ mirror_phase' = "ready"
     \/ /\ mirror_flow = "validate"  \* validate-only flow: session ends
        /\ mirror_phase' = "done"
  /\ mirror_to_client' = Append(mirror_to_client, SPEC_VALIDATED)
  /\ action_taken' = "MirrorSendSpecValidatedValid"
  /\ UNCHANGED <<client_phase, client_to_mirror, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

\* Invalid outcome of the validate-only path: the reply is still
\* SpecValidated (same tag; the SpecInvalid payload is abstracted away),
\* and the session ends. Split from the valid outcome so traces can tell
\* them apart.
MirrorSendSpecValidatedInvalid ==
  /\ mirror_phase = "validating"
  /\ mirror_flow = "validate"
  /\ mirror_to_client = <<>>
  /\ mirror_phase' = "done"
  /\ mirror_to_client' = Append(mirror_to_client, SPEC_VALIDATED)
  /\ action_taken' = "MirrorSendSpecValidatedInvalid"
  /\ UNCHANGED <<client_phase, client_to_mirror, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

MirrorSendRegisterError ==
  /\ mirror_phase = "validating"
  /\ mirror_to_client = <<>>
  /\ mirror_phase' = "done"
  /\ mirror_to_client' = Append(mirror_to_client, REGISTER_ERROR)
  /\ action_taken' = "MirrorSendRegisterError"
  /\ UNCHANGED <<client_phase, client_to_mirror, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

MirrorSendExplorerReady ==
  /\ mirror_phase = "validating"
  /\ mirror_flow = "session"
  /\ mirror_to_client = <<>>
  /\ mirror_phase' = "exploring"
  /\ mirror_to_client' = Append(mirror_to_client, EXPLORER_READY)
  /\ action_taken' = "MirrorSendExplorerReady"
  /\ UNCHANGED <<client_phase, client_to_mirror, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

MirrorSendInitialState ==
  /\ mirror_phase = "ready"
  /\ mirror_to_client = <<>>
  /\ mirror_phase' = "stepping"
  /\ mirror_to_client' = Append(mirror_to_client, INITIAL_STATE)
  /\ action_taken' = "MirrorSendInitialState"
  /\ UNCHANGED <<client_phase, client_to_mirror, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

\* After sending step_ok, mirror sends next_step if more steps remain.
MirrorSendNextStep ==
  /\ mirror_to_client = <<>>
  /\ client_to_mirror = <<>>
  /\ mirror_phase = "stepping"
  /\ client_phase = "waiting_ack"
  /\ mirror_phase' = "stepping"
  /\ mirror_to_client' = Append(mirror_to_client, NEXT_STEP)
  /\ action_taken' = "MirrorSendNextStep"
  /\ UNCHANGED <<client_phase, client_to_mirror, mirror_flow, report_matches, faulted, client_closed, mirror_closed>>

\* -----------------------------------------------------------------------------
\* Init
\* -----------------------------------------------------------------------------

SyncInit ==
  /\ mirror_phase = "idle"
  /\ client_phase = "idle"
  /\ action_taken = "init"
  /\ mirror_flow = "none"
  /\ client_to_mirror = <<>>
  /\ mirror_to_client = <<>>
  /\ report_matches = FALSE
  /\ faulted = FALSE
  /\ client_closed = FALSE
  /\ mirror_closed = FALSE

\* -----------------------------------------------------------------------------
\* Next
\* -----------------------------------------------------------------------------

\* Explicit terminal state: both sides finished; halt cleanly.
Halt ==
  /\ mirror_phase = "done"
  /\ client_phase = "done"
  /\ action_taken' = "Halt"
  /\ UNCHANGED <<mirror_phase, client_phase, mirror_flow, client_to_mirror, mirror_to_client, report_matches, faulted, client_closed, mirror_closed>>

SyncNext ==
  \/ Halt
  \/ ClientRegister
  \/ ClientRegisterTraces
  \/ ClientRegisterGenTraces
  \/ ClientRegisterExplore
  \/ ClientRegisterExploreSession
  \/ ClientRegisterValidate
  \/ ClientExploreCmd
  \/ ClientExploreDone
  \/ ClientReport
  \/ ClientRecvSpecValidated
  \/ ClientRecvSpecValidatedDone
  \/ ClientRecvGenTracesDone
  \/ ClientRecvInitialState
  \/ ClientRecvNextStep
  \/ ClientRecvStepOk
  \/ ClientRecvStepMismatch
  \/ ClientRecvAllStepsDone
  \/ ClientRecvRegisterError
  \/ ClientRecvExplorerReady
  \/ ClientRecvExploreResult
  \/ ClientRecvExploreDoneAck
  \/ MirrorRecvRegister
  \/ MirrorRecvRegisterTraces
  \/ MirrorRecvRegisterTracesError
  \/ MirrorRecvRegisterGenTraces
  \/ MirrorRecvRegisterExplore
  \/ MirrorRecvRegisterExploreSession
  \/ MirrorRecvRegisterValidate
  \/ MirrorRecvExploreCmd
  \/ MirrorRecvExploreDone
  \/ MirrorRecvReportOk
  \/ MirrorRecvReportAllDone
  \/ MirrorRecvReportMismatch
  \/ MirrorSendGenTracesDone
  \/ MirrorSendSpecValidatedValid
  \/ MirrorSendSpecValidatedInvalid
  \/ MirrorSendRegisterError
  \/ MirrorSendExplorerReady
  \/ MirrorSendInitialState
  \/ MirrorSendNextStep

\* -----------------------------------------------------------------------------
\* Specification
\* -----------------------------------------------------------------------------



\* -----------------------------------------------------------------------------
\* Invariants
\* -----------------------------------------------------------------------------

\* Both sides are always in valid phases.
PhaseOk ==
  /\ mirror_phase \in Ms
  /\ client_phase \in Cs

\* The client never waits on a message the mirror will never send:
\* when the client is mid-session, the mirror is in a phase that can respond.
\* Only checked on fault-free paths — fault-injection actions
\* (MirrorProtocolFaults) may of course strand the client.
ClientNeverStuck ==
  ~faulted =>
    /\ client_phase = "waiting_init" => mirror_phase \in {"validating", "ready", "stepping"}
    /\ client_phase = "waiting_ack"  => mirror_phase \in {"stepping", "done"}
    /\ client_phase = "waiting_done" => mirror_phase \in {"exploring", "done"}

SyncInv == PhaseOk /\ ClientNeverStuck

\* Force trace generation: Apalache finds counterexamples
\* showing paths from idle to done.
TraceComplete ==
  client_phase /= "done"

\* Force a trace that completes through a SUCCESSFUL terminal message
\* (step mismatch counts as a completed conformance run). Error paths
\* (register errors, protocol errors) never satisfy this.
TraceSuccess ==
  ~(  action_taken = "ClientRecvAllStepsDone"
   \/ action_taken = "ClientRecvExploreDoneAck"
   \/ action_taken = "ClientRecvStepMismatch")

\* Force stepping path through ClientReport and mirror response.
TraceStepping ==
  ~(mirror_to_client /= <<>> /\ Head(mirror_to_client) = STEP_OK)

\* View that captures protocol-relevant state for trace inspection.
MirrorView == <<mirror_phase, client_phase, action_taken, mirror_flow, client_to_mirror, mirror_to_client>>

\* -----------------------------------------------------------------------------
\* Projection to the MirrorStep vocabulary of MinimalTraceCheck
\* ("Init" | "Tick" | "RecvReport" | "StepOk" | "Mismatch" | "AllDone").
\* The runner compares ProjectTrace(expected actions) against the
\* normalized MirrorStep sequence produced by a real ModelMirrors run.
\* -----------------------------------------------------------------------------

ProjectAction(a) ==
  CASE a = "ClientRecvInitialState"    -> <<"Init">>
    [] a = "ClientRecvNextStep"        -> <<"Tick">>
    [] a = "MirrorRecvReportOk"        -> <<"RecvReport", "StepOk">>
    [] a = "MirrorRecvReportAllDone"   -> <<"RecvReport", "AllDone">>
    [] a = "MirrorRecvReportMismatch"  -> <<"RecvReport", "Mismatch">>
    [] OTHER                           -> <<>>

ProjectTrace(actions) ==
  LET AppendStep(acc, a) == acc \o ProjectAction(a)
  IN ApaFoldSeqLeft(AppendStep, <<>>, actions)


\* -----------------------------------------------------------------------------
\* Server-mode asynchronous jobs and resource ownership.
\*
\* This is a bounded, interleaving model of Session.runAsync + Jobs.Store +
\* Apalache.Runner. A wire operation is atomic except await, connection cleanup,
\* and body acquisition/unwinding, whose relevant race boundaries are explicit.
\* The old single-session projection above is retained as SyncInit/SyncNext.
\* Jobs are shared across connections; a query/cancel caller is NOT their owner.
\*
\* Domains bound one verification run, not the implementation's lifetime IDs.
\* No ID is reused. The server standard library, borrowed source files, immutable
\* result payloads, and process-wide connection workers are outside job ownership.
\* Resource tokens abstract owned spec dirs, run dirs (including trace files),
\* and a child plus its streams/handles. A released child means killed/waited and
\* handles no longer retained, not merely that a cancellation flag was set.
\* Cleanup success and eventual process/worker progress are explicit assumptions:
\* arbitrary OS cleanup failure or a never-returning injected runner is not proved.
\* -----------------------------------------------------------------------------
REGISTER_VALIDATE_ASYNC  == 19
REGISTER_TRACE_GEN_ASYNC == 20
JOB_ACCEPTED            == 21
QUERY_JOB               == 22
AWAIT_JOB               == 23
CANCEL_JOB              == 24
JOB_STATUS              == 25
JOB_RESULT              == 26

AsyncSingleton == {1}
AsyncConnections == 1..2
AsyncJobIds == 1..2
AsyncCapacity == 1
AsyncWorkerSlots == 1
AsyncResourceKinds == {"spec", "directory", "child"}
AsyncTerminalPhases == {"done", "failed", "cancelled"}
AsyncStages == {"unused", "queued", "acquired", "body", "spec", "directory",
                "child", "running", "unwinding", "settled"}

VARIABLE
  \* @type: {connections: Int -> Str, jobs: Int -> {owner: Int, kind: Str, phase: Str, outcome: Str, firstOutcome: Str, stored: Bool, stage: Str, cancelled: Bool, stopRequested: Bool, hook: Bool, slot: Bool, ownedSpec: Bool, resources: Set(Str), acquired: Set(Str), released: Set(Str), slotAcquires: Int, slotReleases: Int, bodyResult: Str}, waiting: Int -> Int, last: {operation: Str, connection: Int, job: Int, tag: Int, value: Str}};
  async_state

\* @type: () => {owner: Int, kind: Str, phase: Str, outcome: Str, firstOutcome: Str, stored: Bool, stage: Str, cancelled: Bool, stopRequested: Bool, hook: Bool, slot: Bool, ownedSpec: Bool, resources: Set(Str), acquired: Set(Str), released: Set(Str), slotAcquires: Int, slotReleases: Int, bodyResult: Str};
AsyncEmptyJob ==
  [owner |-> 0, kind |-> "none", phase |-> "unused", outcome |-> "none",
   firstOutcome |-> "none", stored |-> FALSE, stage |-> "unused",
   cancelled |-> FALSE, stopRequested |-> FALSE, hook |-> FALSE, slot |-> FALSE, ownedSpec |-> FALSE,
   resources |-> {}, acquired |-> {}, released |-> {},
   slotAcquires |-> 0, slotReleases |-> 0, bodyResult |-> "none"]

AsyncReply(op, c, j, tag, value) ==
  [operation |-> op, connection |-> c, job |-> j, tag |-> tag, value |-> value]

AsyncInit ==
  async_state =
    [connections |-> [c \in AsyncConnections |-> "open"],
     jobs |-> [j \in AsyncJobIds |-> AsyncEmptyJob],
     waiting |-> [c \in AsyncConnections |-> 0],
     last |-> AsyncReply("init", 0, 0, -1, "none")]

AsyncFree(c) == async_state.connections[c] = "open" /\ async_state.waiting[c] = 0
AsyncLiveJobs == {j \in AsyncJobIds : async_state.jobs[j].stored /\
                  async_state.jobs[j].phase \in {"pending", "running"}}
AsyncSlotHolders == {j \in AsyncJobIds : async_state.jobs[j].slot}
\* @type: ({owner: Int, kind: Str, phase: Str, outcome: Str, firstOutcome: Str, stored: Bool, stage: Str, cancelled: Bool, stopRequested: Bool, hook: Bool, slot: Bool, ownedSpec: Bool, resources: Set(Str), acquired: Set(Str), released: Set(Str), slotAcquires: Int, slotReleases: Int, bodyResult: Str}, Set(Str)) => {owner: Int, kind: Str, phase: Str, outcome: Str, firstOutcome: Str, stored: Bool, stage: Str, cancelled: Bool, stopRequested: Bool, hook: Bool, slot: Bool, ownedSpec: Bool, resources: Set(Str), acquired: Set(Str), released: Set(Str), slotAcquires: Int, slotReleases: Int, bodyResult: Str};
AsyncAcquire(job, rs) ==
  [job EXCEPT !.resources = @ \cup rs, !.acquired = @ \cup rs]
\* @type: ({owner: Int, kind: Str, phase: Str, outcome: Str, firstOutcome: Str, stored: Bool, stage: Str, cancelled: Bool, stopRequested: Bool, hook: Bool, slot: Bool, ownedSpec: Bool, resources: Set(Str), acquired: Set(Str), released: Set(Str), slotAcquires: Int, slotReleases: Int, bodyResult: Str}, Set(Str)) => {owner: Int, kind: Str, phase: Str, outcome: Str, firstOutcome: Str, stored: Bool, stage: Str, cancelled: Bool, stopRequested: Bool, hook: Bool, slot: Bool, ownedSpec: Bool, resources: Set(Str), acquired: Set(Str), released: Set(Str), slotAcquires: Int, slotReleases: Int, bodyResult: Str};
AsyncRelease(job, rs) ==
  [job EXCEPT !.resources = @ \ rs,
              !.released = @ \cup (job.resources \cap rs)]
\* @type: ({owner: Int, kind: Str, phase: Str, outcome: Str, firstOutcome: Str, stored: Bool, stage: Str, cancelled: Bool, stopRequested: Bool, hook: Bool, slot: Bool, ownedSpec: Bool, resources: Set(Str), acquired: Set(Str), released: Set(Str), slotAcquires: Int, slotReleases: Int, bodyResult: Str}, Str, Str) => {owner: Int, kind: Str, phase: Str, outcome: Str, firstOutcome: Str, stored: Bool, stage: Str, cancelled: Bool, stopRequested: Bool, hook: Bool, slot: Bool, ownedSpec: Bool, resources: Set(Str), acquired: Set(Str), released: Set(Str), slotAcquires: Int, slotReleases: Int, bodyResult: Str};
AsyncTerminal(job, phase, outcome) ==
  IF job.phase \in AsyncTerminalPhases THEN job
  ELSE [job EXCEPT !.phase = phase, !.outcome = outcome, !.firstOutcome = outcome]
AsyncAnswer(j) ==
  IF j = 0 THEN "unknown"
  ELSE IF ~async_state.jobs[j].stored THEN "unknown"
  ELSE IF async_state.jobs[j].phase \in AsyncTerminalPhases
       THEN async_state.jobs[j].outcome ELSE async_state.jobs[j].phase
AsyncAnswerTag(j) ==
  IF j = 0 THEN JOB_STATUS
  ELSE IF async_state.jobs[j].stored /\
          async_state.jobs[j].phase \in AsyncTerminalPhases
       THEN JOB_RESULT ELSE JOB_STATUS

AsyncSubmit(c, j, kind, owned) ==
  /\ AsyncFree(c)
  /\ async_state.jobs[j].phase = "unused"
  /\ Cardinality(AsyncLiveJobs) < AsyncCapacity
  /\ async_state' = [async_state EXCEPT
       !.jobs[j] = [AsyncEmptyJob EXCEPT !.owner = c, !.kind = kind,
         !.phase = "pending", !.stored = TRUE, !.stage = "queued", !.ownedSpec = owned],
       !.last = AsyncReply("submit", c, j, JOB_ACCEPTED, kind)]

\* Invalid validation bounds and full live-job capacity allocate NOTHING.
AsyncReject(c, reason) ==
  /\ AsyncFree(c)
  /\ reason = "bad_bound" \/ (reason = "queue_full" /\
       Cardinality(AsyncLiveJobs) >= AsyncCapacity)
  /\ async_state' = [async_state EXCEPT
       !.last = AsyncReply("submit_rejected", c, 0, REGISTER_ERROR, reason)]

AsyncQuery(c, j) ==
  /\ AsyncFree(c)
  /\ async_state' = [async_state EXCEPT
       !.last = AsyncReply("query", c, j, AsyncAnswerTag(j), AsyncAnswer(j))]

AsyncAwait(c, j) ==
  /\ AsyncFree(c)
  /\ async_state.jobs[j].stored
  /\ async_state.jobs[j].phase \in {"pending", "running"}
  /\ async_state' = [async_state EXCEPT !.waiting[c] = j,
       !.last = AsyncReply("await_begin", c, j, -1, "waiting")]

AsyncAwaitReply(c, timeout) ==
  LET j == async_state.waiting[c] IN
  /\ async_state.connections[c] = "open"
  /\ j /= 0
  /\ timeout \/ AsyncAnswerTag(j) = JOB_RESULT \/ AsyncAnswer(j) = "unknown"
  /\ async_state' = [async_state EXCEPT !.waiting[c] = 0,
       !.last = AsyncReply("await_reply", c, j, AsyncAnswerTag(j), AsyncAnswer(j))]

AsyncAwaitReady(c, j) ==
  /\ AsyncFree(c)
  /\ AsyncAnswerTag(j) = JOB_RESULT \/ AsyncAnswer(j) = "unknown"
  /\ async_state' = [async_state EXCEPT
       !.last = AsyncReply("await_reply", c, j, AsyncAnswerTag(j), AsyncAnswer(j))]

\* A queued cancelled job may acquire a permit only to return it immediately.
\* Slot ownership belongs to the task, independently of job-table eviction.
AsyncAcquireSlot(j) ==
  LET job == async_state.jobs[j] IN
  /\ job.stage = "queued"
  /\ Cardinality(AsyncSlotHolders) < AsyncWorkerSlots
  /\ async_state' = [async_state EXCEPT !.jobs[j] =
       [job EXCEPT !.slot = TRUE, !.slotAcquires = @ + 1, !.stage = "acquired",
        !.phase = IF job.phase = "pending" THEN "running" ELSE @]]

AsyncBeginBody(j) ==
  LET job == async_state.jobs[j] IN
  /\ job.stage = "acquired" /\ ~job.cancelled
  /\ async_state' = [async_state EXCEPT !.jobs[j].stage = "body"]

AsyncAcquireSpec(j) ==
  LET job == async_state.jobs[j] IN
  /\ job.stage = "body" /\ ~job.cancelled
  /\ async_state' = [async_state EXCEPT !.jobs[j] =
       [AsyncAcquire(job, IF job.ownedSpec THEN {"spec"} ELSE {}) EXCEPT !.stage = "spec"]]

AsyncAcquireDirectory(j) ==
  LET job == async_state.jobs[j] IN
  /\ job.stage = "spec" /\ ~job.cancelled
  /\ async_state' = [async_state EXCEPT !.jobs[j] =
       [AsyncAcquire(job, {"directory"}) EXCEPT !.stage = "directory"]]

\* Cancellation may race a spawn whose precheck already passed. The following
\* hook installation MUST observe prior cancellation and kill that late child.
AsyncSpawnChild(j) ==
  LET job == async_state.jobs[j] IN
  /\ job.stage = "directory"
  /\ async_state' = [async_state EXCEPT !.jobs[j] =
       [AsyncAcquire(job, {"child"}) EXCEPT !.stage = "child"]]

AsyncInstallHook(j) ==
  LET job == async_state.jobs[j]
      updated == IF job.cancelled THEN [job EXCEPT !.stopRequested = TRUE] ELSE job IN
  /\ job.stage = "child"
  /\ async_state' = [async_state EXCEPT !.jobs[j] =
       [updated EXCEPT !.hook = TRUE, !.stage = "running"]]

AsyncBodyReturns(j, result) ==
  LET job == async_state.jobs[j] IN
  /\ job.stage = "running"
  /\ result = "error" \/ (job.kind = "validate" /\ result \in {"valid", "invalid"})
       \/ (job.kind = "gen_traces" /\ result = "traces")
  /\ async_state' = [async_state EXCEPT !.jobs[j] =
       [AsyncRelease(job, {"child"}) EXCEPT
        !.hook = FALSE, !.stage = "unwinding", !.bodyResult = result]]

\* Acquisition failure or cancellation before body execution still unwinds
\* every resource already acquired, including a spec if directory creation fails.
AsyncBodyAborts(j) ==
  LET job == async_state.jobs[j] IN
  /\ job.stage \in {"acquired", "body", "spec", "directory", "child"}
  /\ async_state' = [async_state EXCEPT !.jobs[j] =
       [AsyncRelease(job, {"child"}) EXCEPT
        !.hook = FALSE, !.stage = "unwinding", !.bodyResult = "error"]]

AsyncUnwind(j) ==
  LET job == async_state.jobs[j]
      clean == AsyncRelease(job, AsyncResourceKinds)
      done == AsyncTerminal(clean, IF job.bodyResult = "error" THEN "failed" ELSE "done",
                            job.bodyResult) IN
  /\ job.stage = "unwinding"
  /\ async_state' = [async_state EXCEPT !.jobs[j] =
       [done EXCEPT !.stage = "settled", !.slot = FALSE, !.slotReleases = @ + 1]]

AsyncCancel(c, j) ==
  LET job == async_state.jobs[j]
      stopped == IF job.hook THEN [job EXCEPT !.stopRequested = TRUE] ELSE job IN
  /\ (AsyncFree(c) \/ (async_state.connections[c] = "closing" /\ job.owner = c))
  /\ job.stored /\ job.phase \in {"pending", "running"}
  /\ async_state' = [async_state EXCEPT !.jobs[j] =
       [AsyncTerminal(stopped, "cancelled", "cancelled") EXCEPT !.cancelled = TRUE],
       !.last = AsyncReply("cancel", c, j, JOB_STATUS, "cancelled")]

AsyncCancelTerminal(c, j) ==
  /\ AsyncFree(c)
  /\ IF j = 0 THEN TRUE ELSE
       ~async_state.jobs[j].stored \/ async_state.jobs[j].phase \in AsyncTerminalPhases
  /\ async_state' = [async_state EXCEPT
       !.last = AsyncReply("cancel_noop", c, j, JOB_STATUS,
         IF j = 0 THEN "unknown" ELSE IF ~async_state.jobs[j].stored THEN "unknown"
         ELSE async_state.jobs[j].phase)]

\* EOF, decoding/transport failure, and a terminal synchronous flow all enter
\* the same finally-owned drain. They do not abandon the submitted job list.
AsyncClose(c, reason) ==
  /\ async_state.connections[c] = "open"
  /\ async_state' = [async_state EXCEPT !.connections[c] = "closing", !.waiting[c] = 0,
       !.last = AsyncReply(reason, c, 0, -1, "closing")]

AsyncEvict(c, j) ==
  LET job == async_state.jobs[j] IN
  /\ async_state.connections[c] = "closing"
  /\ job.owner = c /\ job.stored /\ job.phase \in AsyncTerminalPhases
  /\ async_state' = [async_state EXCEPT !.jobs[j].stored = FALSE,
       !.last = AsyncReply("evict", c, j, -1, "unknown")]

AsyncFinishClose(c) ==
  /\ async_state.connections[c] = "closing"
  /\ \A j \in AsyncJobIds : async_state.jobs[j].owner = c => ~async_state.jobs[j].stored
  /\ async_state' = [async_state EXCEPT !.connections[c] = "closed"]

AsyncNextCore ==
  \/ \E c \in AsyncConnections, j \in AsyncJobIds, kind \in {"validate", "gen_traces"}, owned \in BOOLEAN : AsyncSubmit(c, j, kind, owned)
  \/ \E c \in AsyncConnections, reason \in {"bad_bound", "queue_full"} : AsyncReject(c, reason)
  \/ \E c \in AsyncConnections, j \in AsyncJobIds \cup {0} : AsyncQuery(c, j) \/ AsyncAwaitReady(c, j) \/ AsyncCancelTerminal(c, j)
  \/ \E c \in AsyncConnections, j \in AsyncJobIds : AsyncAwait(c, j) \/ AsyncCancel(c, j) \/ AsyncEvict(c, j)
  \/ \E c \in AsyncConnections, timeout \in BOOLEAN : AsyncAwaitReply(c, timeout)
  \/ \E c \in AsyncConnections, reason \in {"eof", "decode_error", "transport_error", "sync_done"} : AsyncClose(c, reason)
  \/ \E c \in AsyncConnections : AsyncFinishClose(c)
  \/ \E j \in AsyncJobIds : AsyncAcquireSlot(j) \/ AsyncBeginBody(j) \/ AsyncAcquireSpec(j) \/ AsyncAcquireDirectory(j) \/ AsyncSpawnChild(j) \/ AsyncInstallHook(j) \/ AsyncBodyAborts(j) \/ AsyncUnwind(j)
  \/ \E j \in AsyncJobIds, result \in {"valid", "invalid", "traces", "error"} : AsyncBodyReturns(j, result)

SyncVars == <<mirror_phase, client_phase, action_taken, mirror_flow,
              client_to_mirror, mirror_to_client, report_matches,
              faulted, client_closed, mirror_closed>>
ProtocolVars == <<SyncVars, async_state>>
Init == SyncInit /\ AsyncInit
AsyncNext == AsyncNextCore /\ UNCHANGED SyncVars
Next == (SyncNext /\ UNCHANGED async_state) \/ AsyncNext
Spec == Init /\ [][Next]_ProtocolVars
SyncSpec == Init /\ [][SyncNext /\ UNCHANGED async_state]_ProtocolVars
AsyncSpec == Init /\ [][AsyncNext]_ProtocolVars

AsyncTypeOK ==
  /\ DOMAIN async_state.connections = AsyncConnections
  /\ DOMAIN async_state.jobs = AsyncJobIds
  /\ DOMAIN async_state.waiting = AsyncConnections
  /\ \A c \in AsyncConnections :
       /\ async_state.connections[c] \in {"open", "closing", "closed"}
       /\ async_state.waiting[c] \in AsyncJobIds \cup {0}
  /\ \A j \in AsyncJobIds : LET job == async_state.jobs[j] IN
       /\ job.owner \in AsyncConnections \cup {0}
       /\ job.kind \in {"none", "validate", "gen_traces"}
       /\ job.phase \in {"unused", "pending", "running"} \cup AsyncTerminalPhases
       /\ job.stage \in AsyncStages
       /\ job.resources \subseteq AsyncResourceKinds
       /\ job.acquired \subseteq AsyncResourceKinds
       /\ job.released \subseteq AsyncResourceKinds
       /\ job.stored \in BOOLEAN /\ job.cancelled \in BOOLEAN /\ job.slot \in BOOLEAN
       /\ job.hook \in BOOLEAN /\ job.ownedSpec \in BOOLEAN /\ job.stopRequested \in BOOLEAN
       /\ job.slotAcquires \in 0..1 /\ job.slotReleases \in 0..1

AsyncResourceAccounting ==
  \A j \in AsyncJobIds : LET job == async_state.jobs[j] IN
    /\ job.resources = job.acquired \ job.released
    /\ job.released \subseteq job.acquired
    /\ job.slotReleases <= job.slotAcquires
    /\ job.slot = (job.slotAcquires - job.slotReleases = 1)
    /\ ~job.ownedSpec => "spec" \notin job.acquired

AsyncNoOrphanedResources ==
  \A j \in AsyncJobIds : LET job == async_state.jobs[j] IN
    /\ job.stored => job.owner \in AsyncConnections
    /\ job.resources /= {} => job.stage \notin {"unused", "queued", "settled"}
    /\ job.stage \in {"unused", "settled"} => ~job.slot /\ job.resources = {}
    /\ job.stage \notin {"unused", "queued", "settled"} => job.slot

AsyncClosedOwnersHaveNoEntries ==
  \A c \in AsyncConnections : async_state.connections[c] = "closed" =>
    \A j \in AsyncJobIds : async_state.jobs[j].owner = c => ~async_state.jobs[j].stored

AsyncTerminalResultsStable ==
  \A j \in AsyncJobIds : LET job == async_state.jobs[j] IN
    job.firstOutcome /= "none" =>
      job.phase \in AsyncTerminalPhases /\ job.outcome = job.firstOutcome

AsyncLateCancellationSafe ==
  \A j \in AsyncJobIds : LET job == async_state.jobs[j] IN
    job.cancelled /\ job.hook /\ "child" \in job.resources => job.stopRequested

\* An outstanding await borrows the result promise even after table eviction.
AsyncLivePromises == {j \in AsyncJobIds : async_state.jobs[j].stored \/
                      (\E c \in AsyncConnections : async_state.waiting[c] = j)}
AsyncWaitersOwned == \A c \in AsyncConnections :
  async_state.waiting[c] /= 0 => async_state.connections[c] = "open"
AsyncQuiescent ==
  /\ \A c \in AsyncConnections : async_state.connections[c] = "closed"
  /\ \A j \in AsyncJobIds : async_state.jobs[j].stage \in {"unused", "settled"}
AsyncNoLeaksAtQuiescence == AsyncQuiescent =>
  /\ AsyncSlotHolders = {} /\ AsyncLivePromises = {}
  /\ \A j \in AsyncJobIds : async_state.jobs[j].resources = {} /\ ~async_state.jobs[j].stored

AsyncCapacityOK ==
  /\ Cardinality(AsyncLiveJobs) <= AsyncCapacity
  /\ Cardinality(AsyncSlotHolders) <= AsyncWorkerSlots

\* The reply snapshot is diagnostic only: no guard or invariant reads it.
\* TLC may quotient it out without merging different resource/ownership states.
AsyncView == <<async_state.connections, async_state.jobs, async_state.waiting>>

AsyncInv == AsyncTypeOK /\ AsyncResourceAccounting /\ AsyncNoOrphanedResources
            /\ AsyncClosedOwnersHaveNoEntries /\ AsyncTerminalResultsStable
            /\ AsyncLateCancellationSafe /\ AsyncCapacityOK
            /\ AsyncWaitersOwned /\ AsyncNoLeaksAtQuiescence

Inv == SyncInv /\ AsyncInv

\* Liveness is separate from safety. Fairness requires worker scheduling,
\* body completion (including a killed child being collected), lexical cleanup,
\* and per-owner draining to make progress. It does not require clients to close.
AsyncWorkerProgress(j) == AsyncBeginBody(j) \/ AsyncAcquireSpec(j) \/ AsyncAcquireDirectory(j)
                         \/ AsyncSpawnChild(j) \/ AsyncInstallHook(j) \/ AsyncBodyAborts(j)
                         \/ (\E r \in {"valid", "invalid", "traces", "error"} : AsyncBodyReturns(j, r))
                         \/ AsyncUnwind(j)
AsyncDrain(c) == AsyncFinishClose(c) \/
                (\E j \in AsyncJobIds : AsyncCancel(c, j) \/ AsyncEvict(c, j))
AsyncFairness ==
  /\ \A j \in AsyncJobIds : SF_async_state(AsyncAcquireSlot(j)) /\ WF_async_state(AsyncWorkerProgress(j))
  /\ \A c \in AsyncConnections : WF_async_state(AsyncDrain(c)) /\ WF_async_state(AsyncAwaitReply(c, FALSE))
AsyncFairSpec == AsyncSpec /\ AsyncFairness
AsyncResourcesReleased ==
  \A j \in AsyncJobIds :
    (async_state.jobs[j].phase \in AsyncTerminalPhases) ~>
    (async_state.jobs[j].stage = "settled" /\ async_state.jobs[j].resources = {} /\ ~async_state.jobs[j].slot)
AsyncClosingEventuallyClean ==
  \A c \in AsyncConnections : (async_state.connections[c] = "closing") ~>
    (async_state.connections[c] = "closed" /\
      \A j \in AsyncJobIds : async_state.jobs[j].owner = c =>
        ~async_state.jobs[j].stored /\ async_state.jobs[j].resources = {} /\ ~async_state.jobs[j].slot /\ j \notin AsyncLivePromises)

\* Negative controls for the pre-fix implementation, NOT enabled by Next.
AsyncLeakOnExit(c) ==
  /\ async_state.connections[c] = "open"
  /\ async_state' = [async_state EXCEPT !.connections[c] = "closed", !.waiting[c] = 0,
       !.last = AsyncReply("unsafe_exit", c, 0, -1, "closed")]
AsyncEarlySlotRelease(j) ==
  LET job == async_state.jobs[j] IN
  /\ job.phase = "cancelled" /\ job.slot /\ job.stage /= "settled"
  /\ async_state' = [async_state EXCEPT !.jobs[j].slot = FALSE,
       !.jobs[j].slotReleases = @ + 1]
AsyncMissLateHook(j) ==
  /\ async_state.jobs[j].stage = "child" /\ async_state.jobs[j].cancelled
  /\ async_state' = [async_state EXCEPT !.jobs[j].hook = TRUE, !.jobs[j].stage = "running"]
AsyncLeakPartialAcquisition(j) ==
  /\ async_state.jobs[j].stage = "spec" /\ async_state.jobs[j].ownedSpec
  /\ async_state' = [async_state EXCEPT !.jobs[j].stage = "settled", !.jobs[j].phase = "failed",
       !.jobs[j].outcome = "error", !.jobs[j].firstOutcome = "error",
       !.jobs[j].slot = FALSE, !.jobs[j].slotReleases = @ + 1]
AsyncExitFaultNext == AsyncNext \/ ((\E c \in AsyncConnections : AsyncLeakOnExit(c)) /\ UNCHANGED SyncVars)
AsyncSlotFaultNext == AsyncNext \/ ((\E j \in AsyncJobIds : AsyncEarlySlotRelease(j)) /\ UNCHANGED SyncVars)
AsyncHookFaultNext == AsyncNext \/ ((\E j \in AsyncJobIds : AsyncMissLateHook(j)) /\ UNCHANGED SyncVars)
AsyncAcquisitionFaultNext == AsyncNext \/ ((\E j \in AsyncJobIds : AsyncLeakPartialAcquisition(j)) /\ UNCHANGED SyncVars)

==============================================================================
