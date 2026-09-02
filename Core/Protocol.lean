/-!
# Mirror session protocol machine (Core/Protocol.lean, Layer 2, design 5.3)

Pure port of the mirror-side session loop (Haskell Protocol.Mirror.run)
as a finite, explicit transition function over a phase-indexed state, per
docs/lean4-refactor-design.md 5.3 and specs/MirrorProtocol.tla
(at pin ModelMirros@3496251 - the same pin the Phase 0 golden fixtures use).

* Phase mirrors Ms in the spec, extended with async-job flows
  (validatingAsync, generatingAsync) that postdate the spec.
* step consumes one client message and returns the next phase-indexed
  session plus the emitted mirror messages. Illegal orderings are
  unrepresentable: no step case accepts reportState in idle, so the
  first-message rule and the replay ordering hold by construction.
* The TLA+ mirror-side transition relation is encoded as the inductive
  predicate TlaStep (about one page) and section 6.3 is machine-checked:
  - step_refines_tla: safety refinement - every successful step
    corresponds to a 1-3 step TlaSteps derivation (async-job flows map
    to explicitly-marked extension steps);
  - no_unsolicited_output: in each phase the emittable mirror-message
    constructors are exactly AllowedOutputs (e.g. no stepOk except as a
    reply to reportState in stepping), and protocolError is never
    emitted by the pure machine (it covers driver-side decode failures).

Payloads are abstracted to what the control plane observes (reportState
carries the outcome of comparing the reported state with the expected
state, like the TLA+ report_matches bit); value-level comparison lives in
Core.Diff and the effectful driver.
-/

/-! ## Phases, flows, messages -/

/-- Mirror phases: Ms from the TLA+ spec, extended with async-job
phases (extension, 6.3). -/
inductive Phase where
  | idle | validating | generating | ready | stepping | exploring | done
  | validatingAsync | generatingAsync
  deriving Repr, DecidableEq

/-- Active registration flow (mirror_flow in the spec, extended). -/
inductive Flow where
  | none | traces | session | validate
  | asyncValidate | asyncGen
  deriving Repr, DecidableEq

/-- Client messages, abstracted to tags (payload contents are irrelevant
to the control plane). reportState carries the two protocol-relevant
facts about the reported state: whether it matches the expected state
and whether this was the last step. -/
inductive ClientMessage where
  | register | registerTraces | registerGenTraces | registerExplore
  | registerExploreSession | registerValidate
  | registerValidateAsync | registerGenTracesAsync
  | queryJob | awaitJob | cancelJob
  | exploreCmd | exploreDone
  | reportState (reportMatches lastStep : Bool)
  deriving Repr

/-- Mirror messages (tags 1,3-8,12,15,17,18 of the spec, plus the
async-job results and the driver-level protocolError). -/
inductive MirrorMessage where
  | specValidated | initialState | nextStep | stepOk | stepMismatch
  | allStepsDone | genTracesDone | registerError | explorerReady
  | exploreResult | exploreDone
  | jobAccepted | jobStatus | jobResult
  | protocolError
  deriving Repr, DecidableEq

/-- Errors of the pure machine: an ordering violation. (protocolError on
the wire is produced by the effectful driver for decode failures, 5.3;
the pure core never emits it.) -/
inductive ProtocolError where
  | outOfOrder (msg : String)
  deriving Repr

/-! ## The session machine -/

/-- Phase-indexed session state. The phantom index makes the protocol's
typing discipline explicit: a value of type Session .stepping is a
session known to be mid-replay. Control-relevant content is the active
flow; everything else (spec, traces, expected states) is driver-side
payload injected at the effect boundary. -/
structure Session (p : Phase) where
  flow : Flow
  deriving Repr

/-- The injected registration-admission oracle. For ordinary registrations it
is the abstract validation outcome; stepping registrations additionally fold
required model-interface negotiation into this bit. Keeping one control bit
preserves the existing oracle interface while making admission fail closed. -/
structure Oracles where
  validationOk : Bool
  deriving Repr

/-- The TLA+ report_matches bit as the mirror sees it: it rides in the
message, not in the state, in the message-driven encoding. -/
def matchesOf : ClientMessage → Bool
  | .reportState m _ => m
  | _ => false

/-- One protocol step: consume a client message in phase p, producing
the next phase-indexed session and the messages to emit. Each case
composes the TLA+ MirrorRecv/MirrorSend action pair(s); the refinement
theorem unwinds the composition. -/
def step (orc : Oracles) {p : Phase} (s : Session p) (c : ClientMessage) :
    Except ProtocolError ((p' : Phase) × Session p' × List MirrorMessage) :=
  match p, s, c with
  | .idle, _, .register =>
      if orc.validationOk then
        .ok ⟨.stepping, ⟨.traces⟩, [.specValidated, .initialState]⟩
      else .ok ⟨.done, ⟨.traces⟩, [.registerError]⟩
  | .idle, _, .registerExplore =>
      if orc.validationOk then
        .ok ⟨.stepping, ⟨.traces⟩, [.specValidated, .initialState]⟩
      else .ok ⟨.done, ⟨.traces⟩, [.registerError]⟩
  | .idle, _, .registerTraces =>
      if orc.validationOk then
        .ok ⟨.stepping, ⟨.traces⟩, [.specValidated, .initialState]⟩
      else .ok ⟨.done, ⟨.traces⟩, [.registerError]⟩
  | .idle, _, .registerGenTraces =>
      .ok ⟨.idle, ⟨.traces⟩, [.genTracesDone]⟩
  | .idle, _, .registerExploreSession =>
      if orc.validationOk then
        .ok ⟨.exploring, ⟨.session⟩, [.explorerReady]⟩
      else .ok ⟨.done, ⟨.session⟩, [.registerError]⟩
  | .idle, _, .registerValidate =>
      if orc.validationOk then
        .ok ⟨.done, ⟨.validate⟩, [.specValidated]⟩
      else .ok ⟨.done, ⟨.validate⟩, [.registerError]⟩
  | .idle, _, .registerValidateAsync =>
      .ok ⟨.validatingAsync, ⟨.asyncValidate⟩, [.jobAccepted]⟩
  | .idle, _, .registerGenTracesAsync =>
      .ok ⟨.generatingAsync, ⟨.asyncGen⟩, [.jobAccepted]⟩
  | .validatingAsync, s, .queryJob =>
      .ok ⟨.validatingAsync, s, [.jobStatus]⟩
  | .validatingAsync, s, .awaitJob =>
      .ok ⟨.done, ⟨s.flow⟩, [.jobStatus, .jobResult]⟩
  | .validatingAsync, s, .cancelJob =>
      .ok ⟨.done, ⟨s.flow⟩, [.jobStatus]⟩
  | .generatingAsync, s, .queryJob =>
      .ok ⟨.generatingAsync, s, [.jobStatus]⟩
  | .generatingAsync, s, .awaitJob =>
      .ok ⟨.idle, ⟨s.flow⟩, [.jobStatus, .jobResult]⟩
  | .generatingAsync, s, .cancelJob =>
      .ok ⟨.done, ⟨s.flow⟩, [.jobStatus]⟩
  | .exploring, s, .exploreCmd =>
      .ok ⟨.exploring, s, [.exploreResult]⟩
  | .exploring, s, .exploreDone =>
      .ok ⟨.done, ⟨s.flow⟩, [.exploreDone]⟩
  | .stepping, s, .reportState m l =>
      if m then
        (if l then .ok ⟨.done, ⟨s.flow⟩, [.allStepsDone]⟩
         else .ok ⟨.stepping, ⟨s.flow⟩, [.stepOk, .nextStep]⟩)
      else .ok ⟨.done, ⟨s.flow⟩, [.stepMismatch]⟩
  | _, _, _ => .error (.outOfOrder "message not accepted in this phase")

/-! ## Ordering rules by construction -/

/-- The registrations: the only messages accepted in idle. -/
inductive IsRegistration : ClientMessage → Prop where
  | register : IsRegistration .register
  | registerTraces : IsRegistration .registerTraces
  | registerGenTraces : IsRegistration .registerGenTraces
  | registerExplore : IsRegistration .registerExplore
  | registerExploreSession : IsRegistration .registerExploreSession
  | registerValidate : IsRegistration .registerValidate
  | registerValidateAsync : IsRegistration .registerValidateAsync
  | registerGenTracesAsync : IsRegistration .registerGenTracesAsync

/-- **First-message rule**: a session accepts a message while idle
exactly when it is a registration. In particular reportState is
rejected in idle - the replay ordering
(initial_state then report_state then step_ok ...) holds by
construction. -/
theorem step_idle_iff_registration (orc : Oracles) (s : Session .idle)
    (c : ClientMessage) :
    (step orc s c).isOk ↔ IsRegistration c := by
  cases c with
  | register =>
    exact ⟨fun _ => .register, fun _ => by
      cases orc with | mk bv =>
      cases bv <;> unfold step <;> rfl⟩
  | registerTraces =>
    exact ⟨fun _ => .registerTraces, fun _ => by
      cases orc with | mk bv =>
      cases bv <;> unfold step <;> rfl⟩
  | registerGenTraces =>
    exact ⟨fun _ => .registerGenTraces, fun _ => by
      cases orc with | mk bv =>
      cases bv <;> unfold step <;> rfl⟩
  | registerExplore =>
    exact ⟨fun _ => .registerExplore, fun _ => by
      cases orc with | mk bv =>
      cases bv <;> unfold step <;> rfl⟩
  | registerExploreSession =>
    exact ⟨fun _ => .registerExploreSession, fun _ => by
      cases orc with | mk bv =>
      cases bv <;> unfold step <;> rfl⟩
  | registerValidate =>
    exact ⟨fun _ => .registerValidate, fun _ => by
      cases orc with | mk bv =>
      cases bv <;> unfold step <;> rfl⟩
  | registerValidateAsync =>
    exact ⟨fun _ => .registerValidateAsync, fun _ => by
      cases orc with | mk bv =>
      cases bv <;> unfold step <;> rfl⟩
  | registerGenTracesAsync =>
    exact ⟨fun _ => .registerGenTracesAsync, fun _ => by
      cases orc with | mk bv =>
      cases bv <;> unfold step <;> rfl⟩
  | queryJob =>
    exact ⟨fun h => by
      cases orc with | mk bv =>
      cases bv <;> unfold step at h <;> exact Bool.noConfusion h, fun h => by cases h⟩
  | awaitJob =>
    exact ⟨fun h => by
      cases orc with | mk bv =>
      cases bv <;> unfold step at h <;> exact Bool.noConfusion h, fun h => by cases h⟩
  | cancelJob =>
    exact ⟨fun h => by
      cases orc with | mk bv =>
      cases bv <;> unfold step at h <;> exact Bool.noConfusion h, fun h => by cases h⟩
  | exploreCmd =>
    exact ⟨fun h => by
      cases orc with | mk bv =>
      cases bv <;> unfold step at h <;> exact Bool.noConfusion h, fun h => by cases h⟩
  | exploreDone =>
    exact ⟨fun h => by
      cases orc with | mk bv =>
      cases bv <;> unfold step at h <;> exact Bool.noConfusion h, fun h => by cases h⟩
  | reportState m l =>
    exact ⟨fun h => by
      cases orc with | mk bv =>
      cases bv <;> unfold step at h <;> exact Bool.noConfusion h, fun h => by cases h⟩

/-- No reportState is ever accepted in idle - not merely rejected at
runtime: there is no such step case. -/
theorem step_idle_reportState (orc : Oracles) (s : Session .idle)
    (m l : Bool) :
    step orc s (.reportState m l) = .error (.outOfOrder
      "message not accepted in this phase") := rfl

/-- A replay-only registration denied by validation/interface admission ends
with exactly one registration error and never emits an initial state. -/
theorem step_registerTraces_admission_rejected (s : Session .idle) :
    step { validationOk := false } s .registerTraces =
      .ok ⟨.done, (⟨.traces⟩ : Session .done), [.registerError]⟩ := rfl

/-- While stepping, only reportState is accepted. -/
theorem step_stepping_iff_reportState (orc : Oracles)
    (s : Session .stepping) (c : ClientMessage) :
    (step orc s c).isOk ↔ ∃ m l, c = .reportState m l := by
  cases c with
  | reportState m l =>
    exact ⟨fun _ => ⟨m, l, rfl⟩, fun _ => by
        cases m <;> cases l <;> unfold step <;> rfl⟩
  | register =>
    exact ⟨fun h => by
        cases orc with | mk bv =>
        cases bv <;> unfold step at h <;> exact Bool.noConfusion h,
        fun h => by
          obtain ⟨m, l, hw⟩ := h
          exact ClientMessage.noConfusion hw⟩
  | registerTraces =>
    exact ⟨fun h => by
        cases orc with | mk bv =>
        cases bv <;> unfold step at h <;> exact Bool.noConfusion h,
        fun h => by
          obtain ⟨m, l, hw⟩ := h
          exact ClientMessage.noConfusion hw⟩
  | registerGenTraces =>
    exact ⟨fun h => by
        cases orc with | mk bv =>
        cases bv <;> unfold step at h <;> exact Bool.noConfusion h,
        fun h => by
          obtain ⟨m, l, hw⟩ := h
          exact ClientMessage.noConfusion hw⟩
  | registerExplore =>
    exact ⟨fun h => by
        cases orc with | mk bv =>
        cases bv <;> unfold step at h <;> exact Bool.noConfusion h,
        fun h => by
          obtain ⟨m, l, hw⟩ := h
          exact ClientMessage.noConfusion hw⟩
  | registerExploreSession =>
    exact ⟨fun h => by
        cases orc with | mk bv =>
        cases bv <;> unfold step at h <;> exact Bool.noConfusion h,
        fun h => by
          obtain ⟨m, l, hw⟩ := h
          exact ClientMessage.noConfusion hw⟩
  | registerValidate =>
    exact ⟨fun h => by
        cases orc with | mk bv =>
        cases bv <;> unfold step at h <;> exact Bool.noConfusion h,
        fun h => by
          obtain ⟨m, l, hw⟩ := h
          exact ClientMessage.noConfusion hw⟩
  | registerValidateAsync =>
    exact ⟨fun h => by
        cases orc with | mk bv =>
        cases bv <;> unfold step at h <;> exact Bool.noConfusion h,
        fun h => by
          obtain ⟨m, l, hw⟩ := h
          exact ClientMessage.noConfusion hw⟩
  | registerGenTracesAsync =>
    exact ⟨fun h => by
        cases orc with | mk bv =>
        cases bv <;> unfold step at h <;> exact Bool.noConfusion h,
        fun h => by
          obtain ⟨m, l, hw⟩ := h
          exact ClientMessage.noConfusion hw⟩
  | queryJob =>
    exact ⟨fun h => by
        cases orc with | mk bv =>
        cases bv <;> unfold step at h <;> exact Bool.noConfusion h,
        fun h => by
          obtain ⟨m, l, hw⟩ := h
          exact ClientMessage.noConfusion hw⟩
  | awaitJob =>
    exact ⟨fun h => by
        cases orc with | mk bv =>
        cases bv <;> unfold step at h <;> exact Bool.noConfusion h,
        fun h => by
          obtain ⟨m, l, hw⟩ := h
          exact ClientMessage.noConfusion hw⟩
  | cancelJob =>
    exact ⟨fun h => by
        cases orc with | mk bv =>
        cases bv <;> unfold step at h <;> exact Bool.noConfusion h,
        fun h => by
          obtain ⟨m, l, hw⟩ := h
          exact ClientMessage.noConfusion hw⟩
  | exploreCmd =>
    exact ⟨fun h => by
        cases orc with | mk bv =>
        cases bv <;> unfold step at h <;> exact Bool.noConfusion h,
        fun h => by
          obtain ⟨m, l, hw⟩ := h
          exact ClientMessage.noConfusion hw⟩
  | exploreDone =>
    exact ⟨fun h => by
        cases orc with | mk bv =>
        cases bv <;> unfold step at h <;> exact Bool.noConfusion h,
        fun h => by
          obtain ⟨m, l, hw⟩ := h
          exact ClientMessage.noConfusion hw⟩

/-- A done session accepts nothing. -/
theorem step_done_rejects (orc : Oracles) (s : Session .done)
    (c : ClientMessage) :
    ¬ (step orc s c).isOk := by
  cases orc with | mk bv =>
  cases bv <;> cases c <;> intro h <;> unfold step at h <;>
    exact Bool.noConfusion h

/-! ## The TLA+ encoding (6.3) -/

/-- Abstract TLA+ mirror-side state: phase, flow, the mirror-to-client
queue (tags only) and the report_matches bit. Client-side variables are
out of scope of the mirror refinement. -/
structure TlaState where
  phase : Phase
  flow : Flow
  out : List MirrorMessage
  matched : Bool

/-- The mirror-side transition relation of specs/MirrorProtocol.tla,
encoded inductively (state space: 7 phases x 19 message tags). Names are
the TLA+ action names; the last block marks the *extension* steps for
the async-job flows, which postdate the spec and are candidates for
upstreaming into specs/. -/

inductive TlaStep : TlaState → TlaState → Prop where
  | recvRegister (f : Flow) (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨.idle, f, q, m⟩ ⟨.validating, .traces, q, m⟩
  | recvRegisterTraces (f : Flow) (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨.idle, f, q, m⟩ ⟨.ready, .traces, q ++ [.specValidated], m⟩
  /-- Extension: a replay registration can now fail admission before
  stepping (model-interface negotiation `require` failure). This uses no new
  wire tag or phase and leaves the legacy successful transition unchanged. -/
  | extRecvRegisterTracesError (f : Flow) (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨.idle, f, q, m⟩ ⟨.done, .traces, q ++ [.registerError], m⟩
  | recvRegisterGenTraces (f : Flow) (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨.idle, f, q, m⟩ ⟨.generating, .traces, q, m⟩
  | recvRegisterExplore (f : Flow) (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨.idle, f, q, m⟩ ⟨.validating, .traces, q, m⟩
  | recvRegisterExploreSession (f : Flow) (q : List MirrorMessage)
      (m : Bool) :
      TlaStep ⟨.idle, f, q, m⟩ ⟨.validating, .session, q, m⟩
  | recvRegisterValidate (f : Flow) (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨.idle, f, q, m⟩ ⟨.validating, .validate, q, m⟩
  | recvExploreCmd (f : Flow) (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨.exploring, f, q, m⟩ ⟨.exploring, f, q ++ [.exploreResult], m⟩
  | recvExploreDone (f : Flow) (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨.exploring, f, q, m⟩ ⟨.done, f, q ++ [.exploreDone], m⟩
  | recvReportOk (f : Flow) (q : List MirrorMessage) :
      TlaStep ⟨.stepping, f, q, true⟩ ⟨.stepping, f, q ++ [.stepOk], true⟩
  | recvReportAllDone (f : Flow) (q : List MirrorMessage) :
      TlaStep ⟨.stepping, f, q, true⟩ ⟨.done, f, q ++ [.allStepsDone], true⟩
  | recvReportMismatch (f : Flow) (q : List MirrorMessage) :
      TlaStep ⟨.stepping, f, q, false⟩ ⟨.done, f, q ++ [.stepMismatch], false⟩
  | sendGenTracesDone (f : Flow) (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨.generating, f, q, m⟩ ⟨.idle, f, q ++ [.genTracesDone], m⟩
  | sendSpecValidatedTraces (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨.validating, .traces, q, m⟩
        ⟨.ready, .traces, q ++ [.specValidated], m⟩
  | sendSpecValidatedValidate (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨.validating, .validate, q, m⟩
        ⟨.done, .validate, q ++ [.specValidated], m⟩
  /-- Spec companion of sendSpecValidatedValidate: the *invalid* outcome
  of the validate-only flow; same SPEC_VALIDATED tag (the SpecInvalid
  payload is abstracted away in the tag model) and the session ends.
  Split so trace projection can tell the outcomes apart. Core.step
  abstracts valid/invalid/error into the single validationOk oracle
  bit and uses sendRegisterError for the failing branch, which the
  spec equally allows for REGISTER_VALIDATE (apalache-mc failure).
  This ctor exists so TlaStep encodes the full spec relation. -/
  | sendSpecValidatedInvalid (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨.validating, .validate, q, m⟩
        ⟨.done, .validate, q ++ [.specValidated], m⟩
  | sendRegisterError (f : Flow) (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨.validating, f, q, m⟩ ⟨.done, f, q ++ [.registerError], m⟩
  | sendExplorerReady (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨.validating, .session, q, m⟩
        ⟨.exploring, .session, q ++ [.explorerReady], m⟩
  | sendInitialState (f : Flow) (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨.ready, f, q, m⟩ ⟨.stepping, f, q ++ [.initialState], m⟩
  | sendNextStep (f : Flow) (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨.stepping, f, q, m⟩ ⟨.stepping, f, q ++ [.nextStep], m⟩
  /-- Extension: async validate job accepted (job_accepted). -/
  | extRecvRegisterValidateAsync (f : Flow) (q : List MirrorMessage)
      (m : Bool) :
      TlaStep ⟨.idle, f, q, m⟩
        ⟨.validatingAsync, .asyncValidate, q ++ [.jobAccepted], m⟩
  /-- Extension: async trace-gen job accepted (job_accepted). -/
  | extRecvRegisterGenTracesAsync (f : Flow) (q : List MirrorMessage)
      (m : Bool) :
      TlaStep ⟨.idle, f, q, m⟩
        ⟨.generatingAsync, .asyncGen, q ++ [.jobAccepted], m⟩
  /-- Extension: job status poll (job_status). -/
  | extJobStatus (p : Phase)
      (hp : p = .validatingAsync ∨ p = .generatingAsync)
      (f : Flow) (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨p, f, q, m⟩ ⟨p, f, q ++ [.jobStatus], m⟩
  /-- Extension: async validate job completes (job_result, done). -/
  | extJobResultValidate (f : Flow) (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨.validatingAsync, f, q, m⟩ ⟨.done, f, q ++ [.jobResult], m⟩
  /-- Extension: async trace-gen job completes (job_result, idle). -/
  | extJobResultGen (f : Flow) (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨.generatingAsync, f, q, m⟩ ⟨.idle, f, q ++ [.jobResult], m⟩
  /-- Extension: job cancelled (job_status, session over). -/
  | extJobCancel (p : Phase)
      (hp : p = .validatingAsync ∨ p = .generatingAsync)
      (f : Flow) (q : List MirrorMessage) (m : Bool) :
      TlaStep ⟨p, f, q, m⟩ ⟨.done, f, q ++ [.jobStatus], m⟩

/-- Reflexive-transitive closure of TlaStep (sequential composition of
spec actions). -/
inductive TlaSteps : TlaState → TlaState → Prop where
  | refl (s : TlaState) : TlaSteps s s
  | trans {a b c : TlaState} (h : TlaStep a b) (t : TlaSteps b c) :
      TlaSteps a c

/-- Embed a core session (empty mirror-to-client queue, the message's
report_matches bit) as a TLA+ state. -/
def embed {p : Phase} (s : Session p) (m : Bool) : TlaState :=
  ⟨p, s.flow, [], m⟩

/-! ### 6.3 theorem 1: safety refinement -/

/-- **Safety refinement**: every successful Core.step transition
corresponds to a sequence of TLA+ mirror actions leading from the
embedded source state to the embedded target state with exactly the
emitted messages queued. The async-job flows correspond to the
explicitly marked ext... extension steps (candidates for upstreaming
into specs/). -/
theorem step_refines_tla (orc : Oracles) {p : Phase} (s : Session p)
    (c : ClientMessage) {p2 : Phase} (s2 : Session p2)
    (out : List MirrorMessage)
    (h : step orc s c = .ok ⟨p2, s2, out⟩) :
    TlaSteps (embed s (matchesOf c)) ⟨p2, s2.flow, out, matchesOf c⟩ := by
  match p, c with
  | .idle, .register =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact TlaSteps.trans (TlaStep.recvRegister _ _ _)
        (TlaSteps.trans (TlaStep.sendSpecValidatedTraces _ _)
          (TlaSteps.trans (TlaStep.sendInitialState _ _ _)
            (TlaSteps.refl _)))
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact TlaSteps.trans (TlaStep.recvRegister _ _ _)
        (TlaSteps.trans (TlaStep.sendRegisterError _ _ _)
          (TlaSteps.refl _))
  | .idle, .registerExplore =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact TlaSteps.trans (TlaStep.recvRegisterExplore _ _ _)
        (TlaSteps.trans (TlaStep.sendSpecValidatedTraces _ _)
          (TlaSteps.trans (TlaStep.sendInitialState _ _ _)
            (TlaSteps.refl _)))
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact TlaSteps.trans (TlaStep.recvRegisterExplore _ _ _)
        (TlaSteps.trans (TlaStep.sendRegisterError _ _ _)
          (TlaSteps.refl _))
  | .idle, .registerTraces =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact TlaSteps.trans (TlaStep.recvRegisterTraces _ _ _)
        (TlaSteps.trans (TlaStep.sendInitialState _ _ _)
          (TlaSteps.refl _))
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact TlaSteps.trans (TlaStep.extRecvRegisterTracesError _ _ _)
        (TlaSteps.refl _)
  | .idle, .registerGenTraces =>
    simp only [step, Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    exact TlaSteps.trans (TlaStep.recvRegisterGenTraces _ _ _)
      (TlaSteps.trans (TlaStep.sendGenTracesDone _ _ _)
        (TlaSteps.refl _))
  | .idle, .registerExploreSession =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact TlaSteps.trans (TlaStep.recvRegisterExploreSession _ _ _)
        (TlaSteps.trans (TlaStep.sendExplorerReady _ _)
          (TlaSteps.refl _))
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact TlaSteps.trans (TlaStep.recvRegisterExploreSession _ _ _)
        (TlaSteps.trans (TlaStep.sendRegisterError _ _ _)
          (TlaSteps.refl _))
  | .idle, .registerValidate =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact TlaSteps.trans (TlaStep.recvRegisterValidate _ _ _)
        (TlaSteps.trans (TlaStep.sendSpecValidatedValidate _ _)
          (TlaSteps.refl _))
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact TlaSteps.trans (TlaStep.recvRegisterValidate _ _ _)
        (TlaSteps.trans (TlaStep.sendRegisterError _ _ _)
          (TlaSteps.refl _))
  | .idle, .registerValidateAsync =>
    simp only [step, Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    exact TlaSteps.trans (TlaStep.extRecvRegisterValidateAsync _ _ _)
      (TlaSteps.refl _)
  | .idle, .registerGenTracesAsync =>
    simp only [step, Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    exact TlaSteps.trans (TlaStep.extRecvRegisterGenTracesAsync _ _ _)
      (TlaSteps.refl _)
  | .validatingAsync, .queryJob =>
    simp only [step, Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    exact TlaSteps.trans (TlaStep.extJobStatus _ (Or.inl rfl) _ _ _)
      (TlaSteps.refl _)
  | .validatingAsync, .awaitJob =>
    simp only [step, Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    exact TlaSteps.trans (TlaStep.extJobStatus _ (Or.inl rfl) _ _ _)
      (TlaSteps.trans (TlaStep.extJobResultValidate _ _ _)
        (TlaSteps.refl _))
  | .validatingAsync, .cancelJob =>
    simp only [step, Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    exact TlaSteps.trans (TlaStep.extJobCancel _ (Or.inl rfl) _ _ _)
      (TlaSteps.refl _)
  | .generatingAsync, .queryJob =>
    simp only [step, Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    exact TlaSteps.trans (TlaStep.extJobStatus _ (Or.inr rfl) _ _ _)
      (TlaSteps.refl _)
  | .generatingAsync, .awaitJob =>
    simp only [step, Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    exact TlaSteps.trans (TlaStep.extJobStatus _ (Or.inr rfl) _ _ _)
      (TlaSteps.trans (TlaStep.extJobResultGen _ _ _)
        (TlaSteps.refl _))
  | .generatingAsync, .cancelJob =>
    simp only [step, Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    exact TlaSteps.trans (TlaStep.extJobCancel _ (Or.inr rfl) _ _ _)
      (TlaSteps.refl _)
  | .exploring, .exploreCmd =>
    simp only [step, Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    exact TlaSteps.trans (TlaStep.recvExploreCmd _ _ _)
      (TlaSteps.refl _)
  | .exploring, .exploreDone =>
    simp only [step, Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    exact TlaSteps.trans (TlaStep.recvExploreDone _ _ _)
      (TlaSteps.refl _)
  | .stepping, .reportState m l =>
    simp only [step] at h
    cases hm : m with
    | true =>
      rw [hm] at h; rw [if_pos rfl] at h
      cases hl : l with
      | true =>
        rw [hl] at h; rw [if_pos rfl] at h
        simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl, rfl⟩ := h
        exact TlaSteps.trans (TlaStep.recvReportAllDone _ _)
          (TlaSteps.refl _)
      | false =>
        rw [hl] at h; rw [if_neg (by decide)] at h
        simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl, rfl⟩ := h
        exact TlaSteps.trans (TlaStep.recvReportOk _ _)
          (TlaSteps.trans (TlaStep.sendNextStep _ _ _)
            (TlaSteps.refl _))
    | false =>
      rw [hm] at h; rw [if_neg (by decide)] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact TlaSteps.trans (TlaStep.recvReportMismatch _ _)
        (TlaSteps.refl _)
  | .idle, .queryJob => simp only [step] at h; cases h
  | .idle, .awaitJob => simp only [step] at h; cases h
  | .idle, .cancelJob => simp only [step] at h; cases h
  | .idle, .exploreCmd => simp only [step] at h; cases h
  | .idle, .exploreDone => simp only [step] at h; cases h
  | .idle, .reportState m l => simp only [step] at h; cases h
  | .validating, .register => simp only [step] at h; cases h
  | .validating, .registerTraces => simp only [step] at h; cases h
  | .validating, .registerGenTraces => simp only [step] at h; cases h
  | .validating, .registerExplore => simp only [step] at h; cases h
  | .validating, .registerExploreSession => simp only [step] at h; cases h
  | .validating, .registerValidate => simp only [step] at h; cases h
  | .validating, .registerValidateAsync => simp only [step] at h; cases h
  | .validating, .registerGenTracesAsync => simp only [step] at h; cases h
  | .validating, .queryJob => simp only [step] at h; cases h
  | .validating, .awaitJob => simp only [step] at h; cases h
  | .validating, .cancelJob => simp only [step] at h; cases h
  | .validating, .exploreCmd => simp only [step] at h; cases h
  | .validating, .exploreDone => simp only [step] at h; cases h
  | .validating, .reportState m l => simp only [step] at h; cases h
  | .generating, .register => simp only [step] at h; cases h
  | .generating, .registerTraces => simp only [step] at h; cases h
  | .generating, .registerGenTraces => simp only [step] at h; cases h
  | .generating, .registerExplore => simp only [step] at h; cases h
  | .generating, .registerExploreSession => simp only [step] at h; cases h
  | .generating, .registerValidate => simp only [step] at h; cases h
  | .generating, .registerValidateAsync => simp only [step] at h; cases h
  | .generating, .registerGenTracesAsync => simp only [step] at h; cases h
  | .generating, .queryJob => simp only [step] at h; cases h
  | .generating, .awaitJob => simp only [step] at h; cases h
  | .generating, .cancelJob => simp only [step] at h; cases h
  | .generating, .exploreCmd => simp only [step] at h; cases h
  | .generating, .exploreDone => simp only [step] at h; cases h
  | .generating, .reportState m l => simp only [step] at h; cases h
  | .ready, .register => simp only [step] at h; cases h
  | .ready, .registerTraces => simp only [step] at h; cases h
  | .ready, .registerGenTraces => simp only [step] at h; cases h
  | .ready, .registerExplore => simp only [step] at h; cases h
  | .ready, .registerExploreSession => simp only [step] at h; cases h
  | .ready, .registerValidate => simp only [step] at h; cases h
  | .ready, .registerValidateAsync => simp only [step] at h; cases h
  | .ready, .registerGenTracesAsync => simp only [step] at h; cases h
  | .ready, .queryJob => simp only [step] at h; cases h
  | .ready, .awaitJob => simp only [step] at h; cases h
  | .ready, .cancelJob => simp only [step] at h; cases h
  | .ready, .exploreCmd => simp only [step] at h; cases h
  | .ready, .exploreDone => simp only [step] at h; cases h
  | .ready, .reportState m l => simp only [step] at h; cases h
  | .stepping, .register => simp only [step] at h; cases h
  | .stepping, .registerTraces => simp only [step] at h; cases h
  | .stepping, .registerGenTraces => simp only [step] at h; cases h
  | .stepping, .registerExplore => simp only [step] at h; cases h
  | .stepping, .registerExploreSession => simp only [step] at h; cases h
  | .stepping, .registerValidate => simp only [step] at h; cases h
  | .stepping, .registerValidateAsync => simp only [step] at h; cases h
  | .stepping, .registerGenTracesAsync => simp only [step] at h; cases h
  | .stepping, .queryJob => simp only [step] at h; cases h
  | .stepping, .awaitJob => simp only [step] at h; cases h
  | .stepping, .cancelJob => simp only [step] at h; cases h
  | .stepping, .exploreCmd => simp only [step] at h; cases h
  | .stepping, .exploreDone => simp only [step] at h; cases h
  | .exploring, .register => simp only [step] at h; cases h
  | .exploring, .registerTraces => simp only [step] at h; cases h
  | .exploring, .registerGenTraces => simp only [step] at h; cases h
  | .exploring, .registerExplore => simp only [step] at h; cases h
  | .exploring, .registerExploreSession => simp only [step] at h; cases h
  | .exploring, .registerValidate => simp only [step] at h; cases h
  | .exploring, .registerValidateAsync => simp only [step] at h; cases h
  | .exploring, .registerGenTracesAsync => simp only [step] at h; cases h
  | .exploring, .queryJob => simp only [step] at h; cases h
  | .exploring, .awaitJob => simp only [step] at h; cases h
  | .exploring, .cancelJob => simp only [step] at h; cases h
  | .exploring, .reportState m l => simp only [step] at h; cases h
  | .done, .register => simp only [step] at h; cases h
  | .done, .registerTraces => simp only [step] at h; cases h
  | .done, .registerGenTraces => simp only [step] at h; cases h
  | .done, .registerExplore => simp only [step] at h; cases h
  | .done, .registerExploreSession => simp only [step] at h; cases h
  | .done, .registerValidate => simp only [step] at h; cases h
  | .done, .registerValidateAsync => simp only [step] at h; cases h
  | .done, .registerGenTracesAsync => simp only [step] at h; cases h
  | .done, .queryJob => simp only [step] at h; cases h
  | .done, .awaitJob => simp only [step] at h; cases h
  | .done, .cancelJob => simp only [step] at h; cases h
  | .done, .exploreCmd => simp only [step] at h; cases h
  | .done, .exploreDone => simp only [step] at h; cases h
  | .done, .reportState m l => simp only [step] at h; cases h
  | .validatingAsync, .register => simp only [step] at h; cases h
  | .validatingAsync, .registerTraces => simp only [step] at h; cases h
  | .validatingAsync, .registerGenTraces => simp only [step] at h; cases h
  | .validatingAsync, .registerExplore => simp only [step] at h; cases h
  | .validatingAsync, .registerExploreSession => simp only [step] at h; cases h
  | .validatingAsync, .registerValidate => simp only [step] at h; cases h
  | .validatingAsync, .registerValidateAsync => simp only [step] at h; cases h
  | .validatingAsync, .registerGenTracesAsync => simp only [step] at h; cases h
  | .validatingAsync, .exploreCmd => simp only [step] at h; cases h
  | .validatingAsync, .exploreDone => simp only [step] at h; cases h
  | .validatingAsync, .reportState m l => simp only [step] at h; cases h
  | .generatingAsync, .register => simp only [step] at h; cases h
  | .generatingAsync, .registerTraces => simp only [step] at h; cases h
  | .generatingAsync, .registerGenTraces => simp only [step] at h; cases h
  | .generatingAsync, .registerExplore => simp only [step] at h; cases h
  | .generatingAsync, .registerExploreSession => simp only [step] at h; cases h
  | .generatingAsync, .registerValidate => simp only [step] at h; cases h
  | .generatingAsync, .registerValidateAsync => simp only [step] at h; cases h
  | .generatingAsync, .registerGenTracesAsync => simp only [step] at h; cases h
  | .generatingAsync, .exploreCmd => simp only [step] at h; cases h
  | .generatingAsync, .exploreDone => simp only [step] at h; cases h
  | .generatingAsync, .reportState m l => simp only [step] at h; cases h

/-! ### 6.3 theorem 2: no unsolicited output -/

/-- The spec'd emittable mirror messages per input phase. Note
protocolError appears in none of them: the pure machine never emits it
(it belongs to the driver's decode-failure channel). -/
def AllowedOutputs : Phase → List MirrorMessage
  | .idle =>
      [.specValidated, .initialState, .genTracesDone, .registerError,
       .jobAccepted, .explorerReady]
  | .validating => []
  | .generating => []
  | .ready => []
  | .stepping => [.stepOk, .nextStep, .allStepsDone, .stepMismatch]
  | .exploring => [.exploreResult, .exploreDone]
  | .done => []
  | .validatingAsync => [.jobStatus, .jobResult]
  | .generatingAsync => [.jobStatus, .jobResult]

/-- **No unsolicited output**: every message emitted by a successful
step started in phase p belongs to the spec'd set for p. In particular
stepOk/stepMismatch/allStepsDone only ever leave stepping (and only in
reply to reportState), and protocolError is never emitted. -/
theorem no_unsolicited_output (orc : Oracles) {p : Phase} (s : Session p)
    (c : ClientMessage) {p2 : Phase} (s2 : Session p2)
    (out : List MirrorMessage)
    (h : step orc s c = .ok ⟨p2, s2, out⟩) :
    ∀ m ∈ out, m ∈ AllowedOutputs p := by
  match p, c with
  | .idle, .register =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      intro m hmem
      simp only [AllowedOutputs]
      rcases List.mem_cons.mp hmem with rfl | h2
      · simp
      · rcases List.mem_cons.mp h2 with rfl | h3
        · simp
        · nomatch h3
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      intro m hmem
      simp only [AllowedOutputs]
      rcases List.mem_cons.mp hmem with rfl | h2
      · simp
      · nomatch h2
  | .idle, .registerExplore =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      intro m hmem
      simp only [AllowedOutputs]
      rcases List.mem_cons.mp hmem with rfl | h2
      · simp
      · rcases List.mem_cons.mp h2 with rfl | h3
        · simp
        · nomatch h3
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      intro m hmem
      simp only [AllowedOutputs]
      rcases List.mem_cons.mp hmem with rfl | h2
      · simp
      · nomatch h2
  | .idle, .registerTraces =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      intro m hmem
      simp only [AllowedOutputs]
      rcases List.mem_cons.mp hmem with rfl | h2
      · simp
      · rcases List.mem_cons.mp h2 with rfl | h3
        · simp
        · nomatch h3
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      intro m hmem
      simp only [AllowedOutputs]
      rcases List.mem_cons.mp hmem with rfl | h2
      · simp
      · nomatch h2
  | .idle, .registerGenTraces =>
    simp only [step] at h
    simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    intro m hmem
    simp only [AllowedOutputs]
    rcases List.mem_cons.mp hmem with rfl | h2
    · simp
    · nomatch h2
  | .idle, .registerExploreSession =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      intro m hmem
      simp only [AllowedOutputs]
      rcases List.mem_cons.mp hmem with rfl | h2
      · simp
      · nomatch h2
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      intro m hmem
      simp only [AllowedOutputs]
      rcases List.mem_cons.mp hmem with rfl | h2
      · simp
      · nomatch h2
  | .idle, .registerValidate =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      intro m hmem
      simp only [AllowedOutputs]
      rcases List.mem_cons.mp hmem with rfl | h2
      · simp
      · nomatch h2
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      intro m hmem
      simp only [AllowedOutputs]
      rcases List.mem_cons.mp hmem with rfl | h2
      · simp
      · nomatch h2
  | .idle, .registerValidateAsync =>
    simp only [step] at h
    simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    intro m hmem
    simp only [AllowedOutputs]
    rcases List.mem_cons.mp hmem with rfl | h2
    · simp
    · nomatch h2
  | .idle, .registerGenTracesAsync =>
    simp only [step] at h
    simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    intro m hmem
    simp only [AllowedOutputs]
    rcases List.mem_cons.mp hmem with rfl | h2
    · simp
    · nomatch h2
  | .validatingAsync, .queryJob =>
    simp only [step] at h
    simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    intro m hmem
    simp only [AllowedOutputs]
    rcases List.mem_cons.mp hmem with rfl | h2
    · simp
    · nomatch h2
  | .validatingAsync, .awaitJob =>
    simp only [step] at h
    simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    intro m hmem
    simp only [AllowedOutputs]
    rcases List.mem_cons.mp hmem with rfl | h2
    · simp
    · rcases List.mem_cons.mp h2 with rfl | h3
      · simp
      · nomatch h3
  | .validatingAsync, .cancelJob =>
    simp only [step] at h
    simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    intro m hmem
    simp only [AllowedOutputs]
    rcases List.mem_cons.mp hmem with rfl | h2
    · simp
    · nomatch h2
  | .generatingAsync, .queryJob =>
    simp only [step] at h
    simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    intro m hmem
    simp only [AllowedOutputs]
    rcases List.mem_cons.mp hmem with rfl | h2
    · simp
    · nomatch h2
  | .generatingAsync, .awaitJob =>
    simp only [step] at h
    simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    intro m hmem
    simp only [AllowedOutputs]
    rcases List.mem_cons.mp hmem with rfl | h2
    · simp
    · rcases List.mem_cons.mp h2 with rfl | h3
      · simp
      · nomatch h3
  | .generatingAsync, .cancelJob =>
    simp only [step] at h
    simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    intro m hmem
    simp only [AllowedOutputs]
    rcases List.mem_cons.mp hmem with rfl | h2
    · simp
    · nomatch h2
  | .exploring, .exploreCmd =>
    simp only [step] at h
    simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    intro m hmem
    simp only [AllowedOutputs]
    rcases List.mem_cons.mp hmem with rfl | h2
    · simp
    · nomatch h2
  | .exploring, .exploreDone =>
    simp only [step] at h
    simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    intro m hmem
    simp only [AllowedOutputs]
    rcases List.mem_cons.mp hmem with rfl | h2
    · simp
    · nomatch h2
  | .stepping, .reportState m l =>
    simp only [step] at h
    cases hm : m with
    | true =>
      rw [hm] at h; rw [if_pos rfl] at h
      cases hl : l with
      | true =>
        rw [hl] at h; rw [if_pos rfl] at h
        simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl, rfl⟩ := h
        intro m hmem
        simp only [AllowedOutputs]
        rcases List.mem_cons.mp hmem with rfl | h2
        · simp
        · nomatch h2
      | false =>
        rw [hl] at h; rw [if_neg (by decide)] at h
        simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl, rfl⟩ := h
        intro m hmem
        simp only [AllowedOutputs]
        rcases List.mem_cons.mp hmem with rfl | h2
        · simp
        · rcases List.mem_cons.mp h2 with rfl | h3
          · simp
          · nomatch h3
    | false =>
      rw [hm] at h; rw [if_neg (by decide)] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      intro m hmem
      simp only [AllowedOutputs]
      rcases List.mem_cons.mp hmem with rfl | h2
      · simp
      · nomatch h2
  | .idle, .queryJob =>
    simp only [step] at h; cases h
  | .idle, .awaitJob =>
    simp only [step] at h; cases h
  | .idle, .cancelJob =>
    simp only [step] at h; cases h
  | .idle, .exploreCmd =>
    simp only [step] at h; cases h
  | .idle, .exploreDone =>
    simp only [step] at h; cases h
  | .idle, .reportState m l =>
    simp only [step] at h; cases h
  | .validating, .register =>
    simp only [step] at h; cases h
  | .validating, .registerTraces =>
    simp only [step] at h; cases h
  | .validating, .registerGenTraces =>
    simp only [step] at h; cases h
  | .validating, .registerExplore =>
    simp only [step] at h; cases h
  | .validating, .registerExploreSession =>
    simp only [step] at h; cases h
  | .validating, .registerValidate =>
    simp only [step] at h; cases h
  | .validating, .registerValidateAsync =>
    simp only [step] at h; cases h
  | .validating, .registerGenTracesAsync =>
    simp only [step] at h; cases h
  | .validating, .queryJob =>
    simp only [step] at h; cases h
  | .validating, .awaitJob =>
    simp only [step] at h; cases h
  | .validating, .cancelJob =>
    simp only [step] at h; cases h
  | .validating, .exploreCmd =>
    simp only [step] at h; cases h
  | .validating, .exploreDone =>
    simp only [step] at h; cases h
  | .validating, .reportState m l =>
    simp only [step] at h; cases h
  | .generating, .register =>
    simp only [step] at h; cases h
  | .generating, .registerTraces =>
    simp only [step] at h; cases h
  | .generating, .registerGenTraces =>
    simp only [step] at h; cases h
  | .generating, .registerExplore =>
    simp only [step] at h; cases h
  | .generating, .registerExploreSession =>
    simp only [step] at h; cases h
  | .generating, .registerValidate =>
    simp only [step] at h; cases h
  | .generating, .registerValidateAsync =>
    simp only [step] at h; cases h
  | .generating, .registerGenTracesAsync =>
    simp only [step] at h; cases h
  | .generating, .queryJob =>
    simp only [step] at h; cases h
  | .generating, .awaitJob =>
    simp only [step] at h; cases h
  | .generating, .cancelJob =>
    simp only [step] at h; cases h
  | .generating, .exploreCmd =>
    simp only [step] at h; cases h
  | .generating, .exploreDone =>
    simp only [step] at h; cases h
  | .generating, .reportState m l =>
    simp only [step] at h; cases h
  | .ready, .register =>
    simp only [step] at h; cases h
  | .ready, .registerTraces =>
    simp only [step] at h; cases h
  | .ready, .registerGenTraces =>
    simp only [step] at h; cases h
  | .ready, .registerExplore =>
    simp only [step] at h; cases h
  | .ready, .registerExploreSession =>
    simp only [step] at h; cases h
  | .ready, .registerValidate =>
    simp only [step] at h; cases h
  | .ready, .registerValidateAsync =>
    simp only [step] at h; cases h
  | .ready, .registerGenTracesAsync =>
    simp only [step] at h; cases h
  | .ready, .queryJob =>
    simp only [step] at h; cases h
  | .ready, .awaitJob =>
    simp only [step] at h; cases h
  | .ready, .cancelJob =>
    simp only [step] at h; cases h
  | .ready, .exploreCmd =>
    simp only [step] at h; cases h
  | .ready, .exploreDone =>
    simp only [step] at h; cases h
  | .ready, .reportState m l =>
    simp only [step] at h; cases h
  | .stepping, .register =>
    simp only [step] at h; cases h
  | .stepping, .registerTraces =>
    simp only [step] at h; cases h
  | .stepping, .registerGenTraces =>
    simp only [step] at h; cases h
  | .stepping, .registerExplore =>
    simp only [step] at h; cases h
  | .stepping, .registerExploreSession =>
    simp only [step] at h; cases h
  | .stepping, .registerValidate =>
    simp only [step] at h; cases h
  | .stepping, .registerValidateAsync =>
    simp only [step] at h; cases h
  | .stepping, .registerGenTracesAsync =>
    simp only [step] at h; cases h
  | .stepping, .queryJob =>
    simp only [step] at h; cases h
  | .stepping, .awaitJob =>
    simp only [step] at h; cases h
  | .stepping, .cancelJob =>
    simp only [step] at h; cases h
  | .stepping, .exploreCmd =>
    simp only [step] at h; cases h
  | .stepping, .exploreDone =>
    simp only [step] at h; cases h
  | .exploring, .register =>
    simp only [step] at h; cases h
  | .exploring, .registerTraces =>
    simp only [step] at h; cases h
  | .exploring, .registerGenTraces =>
    simp only [step] at h; cases h
  | .exploring, .registerExplore =>
    simp only [step] at h; cases h
  | .exploring, .registerExploreSession =>
    simp only [step] at h; cases h
  | .exploring, .registerValidate =>
    simp only [step] at h; cases h
  | .exploring, .registerValidateAsync =>
    simp only [step] at h; cases h
  | .exploring, .registerGenTracesAsync =>
    simp only [step] at h; cases h
  | .exploring, .queryJob =>
    simp only [step] at h; cases h
  | .exploring, .awaitJob =>
    simp only [step] at h; cases h
  | .exploring, .cancelJob =>
    simp only [step] at h; cases h
  | .exploring, .reportState m l =>
    simp only [step] at h; cases h
  | .done, .register =>
    simp only [step] at h; cases h
  | .done, .registerTraces =>
    simp only [step] at h; cases h
  | .done, .registerGenTraces =>
    simp only [step] at h; cases h
  | .done, .registerExplore =>
    simp only [step] at h; cases h
  | .done, .registerExploreSession =>
    simp only [step] at h; cases h
  | .done, .registerValidate =>
    simp only [step] at h; cases h
  | .done, .registerValidateAsync =>
    simp only [step] at h; cases h
  | .done, .registerGenTracesAsync =>
    simp only [step] at h; cases h
  | .done, .queryJob =>
    simp only [step] at h; cases h
  | .done, .awaitJob =>
    simp only [step] at h; cases h
  | .done, .cancelJob =>
    simp only [step] at h; cases h
  | .done, .exploreCmd =>
    simp only [step] at h; cases h
  | .done, .exploreDone =>
    simp only [step] at h; cases h
  | .done, .reportState m l =>
    simp only [step] at h; cases h
  | .validatingAsync, .register =>
    simp only [step] at h; cases h
  | .validatingAsync, .registerTraces =>
    simp only [step] at h; cases h
  | .validatingAsync, .registerGenTraces =>
    simp only [step] at h; cases h
  | .validatingAsync, .registerExplore =>
    simp only [step] at h; cases h
  | .validatingAsync, .registerExploreSession =>
    simp only [step] at h; cases h
  | .validatingAsync, .registerValidate =>
    simp only [step] at h; cases h
  | .validatingAsync, .registerValidateAsync =>
    simp only [step] at h; cases h
  | .validatingAsync, .registerGenTracesAsync =>
    simp only [step] at h; cases h
  | .validatingAsync, .exploreCmd =>
    simp only [step] at h; cases h
  | .validatingAsync, .exploreDone =>
    simp only [step] at h; cases h
  | .validatingAsync, .reportState m l =>
    simp only [step] at h; cases h
  | .generatingAsync, .register =>
    simp only [step] at h; cases h
  | .generatingAsync, .registerTraces =>
    simp only [step] at h; cases h
  | .generatingAsync, .registerGenTraces =>
    simp only [step] at h; cases h
  | .generatingAsync, .registerExplore =>
    simp only [step] at h; cases h
  | .generatingAsync, .registerExploreSession =>
    simp only [step] at h; cases h
  | .generatingAsync, .registerValidate =>
    simp only [step] at h; cases h
  | .generatingAsync, .registerValidateAsync =>
    simp only [step] at h; cases h
  | .generatingAsync, .registerGenTracesAsync =>
    simp only [step] at h; cases h
  | .generatingAsync, .exploreCmd =>
    simp only [step] at h; cases h
  | .generatingAsync, .exploreDone =>
    simp only [step] at h; cases h
  | .generatingAsync, .reportState m l =>
    simp only [step] at h; cases h

/-- **Exactness**: every message in the spec'd set for phase p is
actually emitted by some step from that phase (the set is not an
over-approximation). -/
theorem allowed_outputs_attainable (p : Phase) (m : MirrorMessage)
    (hm : m ∈ AllowedOutputs p) :
    ∃ (orc : Oracles) (s : Session p) (c : ClientMessage)
      (p2 : Phase) (s2 : Session p2) (out : List MirrorMessage),
      m ∈ out ∧ step orc s c = .ok ⟨p2, s2, out⟩ := by
  cases p with
  | idle =>
    simp only [AllowedOutputs, List.mem_cons] at hm
    rcases hm with rfl | rfl | rfl | rfl | rfl | rfl | hh
    · exact ⟨{ validationOk := true }, ⟨.none⟩, .register, .stepping, ⟨.traces⟩, [.specValidated, .initialState], ⟨.head _, rfl⟩⟩
    · exact ⟨{ validationOk := true }, ⟨.none⟩, .register, .stepping, ⟨.traces⟩, [.specValidated, .initialState], ⟨.tail _ (.head _), rfl⟩⟩
    · exact ⟨{ validationOk := true }, ⟨.none⟩, .registerGenTraces, .idle, ⟨.traces⟩, [.genTracesDone], ⟨.head _, rfl⟩⟩
    · exact ⟨{ validationOk := false }, ⟨.none⟩, .register, .done, ⟨.traces⟩, [.registerError], ⟨.head _, rfl⟩⟩
    · exact ⟨{ validationOk := true }, ⟨.none⟩, .registerValidateAsync, .validatingAsync, ⟨.asyncValidate⟩, [.jobAccepted], ⟨.head _, rfl⟩⟩
    · exact ⟨{ validationOk := true }, ⟨.none⟩, .registerExploreSession, .exploring, ⟨.session⟩, [.explorerReady], ⟨.head _, rfl⟩⟩
    · nomatch hh
  | stepping =>
    simp only [AllowedOutputs, List.mem_cons] at hm
    rcases hm with rfl | rfl | rfl | rfl | hh
    · exact ⟨{ validationOk := true }, ⟨.traces⟩, .reportState true false, .stepping, ⟨.traces⟩, [.stepOk, .nextStep], ⟨.head _, rfl⟩⟩
    · exact ⟨{ validationOk := true }, ⟨.traces⟩, .reportState true false, .stepping, ⟨.traces⟩, [.stepOk, .nextStep], ⟨.tail _ (.head _), rfl⟩⟩
    · exact ⟨{ validationOk := true }, ⟨.traces⟩, .reportState true true, .done, ⟨.traces⟩, [.allStepsDone], ⟨.head _, rfl⟩⟩
    · exact ⟨{ validationOk := true }, ⟨.traces⟩, .reportState false false, .done, ⟨.traces⟩, [.stepMismatch], ⟨.head _, rfl⟩⟩
    · nomatch hh
  | exploring =>
    simp only [AllowedOutputs, List.mem_cons] at hm
    rcases hm with rfl | rfl | hh
    · exact ⟨{ validationOk := true }, ⟨.session⟩, .exploreCmd, .exploring, ⟨.session⟩, [.exploreResult], ⟨.head _, rfl⟩⟩
    · exact ⟨{ validationOk := true }, ⟨.session⟩, .exploreDone, .done, ⟨.session⟩, [.exploreDone], ⟨.head _, rfl⟩⟩
    · nomatch hh
  | validatingAsync =>
    simp only [AllowedOutputs, List.mem_cons] at hm
    rcases hm with rfl | rfl | hh
    · exact ⟨{ validationOk := true }, ⟨.asyncValidate⟩, .queryJob, .validatingAsync, ⟨.asyncValidate⟩, [.jobStatus], ⟨.head _, rfl⟩⟩
    · exact ⟨{ validationOk := true }, ⟨.asyncValidate⟩, .awaitJob, .done, ⟨.asyncValidate⟩, [.jobStatus, .jobResult], ⟨.tail _ (.head _), rfl⟩⟩
    · nomatch hh
  | generatingAsync =>
    simp only [AllowedOutputs, List.mem_cons] at hm
    rcases hm with rfl | rfl | hh
    · exact ⟨{ validationOk := true }, ⟨.asyncGen⟩, .queryJob, .generatingAsync, ⟨.asyncGen⟩, [.jobStatus], ⟨.head _, rfl⟩⟩
    · exact ⟨{ validationOk := true }, ⟨.asyncGen⟩, .awaitJob, .idle, ⟨.asyncGen⟩, [.jobStatus, .jobResult], ⟨.tail _ (.head _), rfl⟩⟩
    · nomatch hh
  | validating => nomatch hm
  | generating => nomatch hm
  | ready => nomatch hm
  | done => nomatch hm
/-! ### Spec invariants (PhaseOk, ClientNeverStuck mirror obligations) -/

/-- The 7 mirror phases of the TLA+ spec (Ms). -/
def specPhases : List Phase :=
  [.idle, .validating, .generating, .ready, .stepping, .exploring, .done]

/-- The phase predicate preserved by every TlaStep. -/
def phaseOkP (st : TlaState) : Prop :=
  st.phase ∈ specPhases ∨ st.phase = .validatingAsync ∨ st.phase = .generatingAsync

theorem tlaStep_preserves_phaseOk {a b : TlaState} (h : TlaStep a b)
    (ha : phaseOkP a) : phaseOkP b := by
  cases h with
  | recvRegister => simp [specPhases, phaseOkP]
  | recvRegisterTraces => simp [specPhases, phaseOkP]
  | extRecvRegisterTracesError => simp [specPhases, phaseOkP]
  | recvRegisterGenTraces => simp [specPhases, phaseOkP]
  | recvRegisterExplore => simp [specPhases, phaseOkP]
  | recvRegisterExploreSession => simp [specPhases, phaseOkP]
  | recvRegisterValidate => simp [specPhases, phaseOkP]
  | recvExploreCmd => simp [specPhases, phaseOkP]
  | recvExploreDone => simp [specPhases, phaseOkP]
  | recvReportOk => simp [specPhases, phaseOkP]
  | recvReportAllDone => simp [specPhases, phaseOkP]
  | recvReportMismatch => simp [specPhases, phaseOkP]
  | sendGenTracesDone => simp [specPhases, phaseOkP]
  | sendSpecValidatedTraces => simp [specPhases, phaseOkP]
  | sendSpecValidatedValidate => simp [specPhases, phaseOkP]
  | sendSpecValidatedInvalid => simp [specPhases, phaseOkP]
  | sendRegisterError => simp [specPhases, phaseOkP]
  | sendExplorerReady => simp [specPhases, phaseOkP]
  | sendInitialState => simp [specPhases, phaseOkP]
  | sendNextStep => simp [specPhases, phaseOkP]
  | extRecvRegisterValidateAsync => simp [specPhases, phaseOkP]
  | extRecvRegisterGenTracesAsync => simp [specPhases, phaseOkP]
  | extJobResultValidate => simp [specPhases, phaseOkP]
  | extJobResultGen => simp [specPhases, phaseOkP]
  | extJobStatus p hp => cases hp with
    | inl hq => exact Or.inr (Or.inl hq)
    | inr hq => exact Or.inr (Or.inr hq)
  | extJobCancel p hp => cases hp <;> exact Or.inl (by simp [specPhases])

theorem tlaSteps_preserves_phaseOkP {a b : TlaState} (t : TlaSteps a b) :
    phaseOkP a → phaseOkP b := by
  induction t with
  | refl s => exact id
  | trans h t ih => exact fun ha => ih (tlaStep_preserves_phaseOk h ha)

/-- **PhaseOk**: a spec-phase source stays in the spec phase set; the only
exits from Ms are into the two declared async-job extension phases,
reachable only via ext* extension steps. -/
theorem tlaSteps_phaseOk {a b : TlaState} (t : TlaSteps a b)
    (ha : a.phase ∈ specPhases) : phaseOkP b :=
  tlaSteps_preserves_phaseOkP t (Or.inl ha)

theorem step_phaseOk (orc : Oracles) {p : Phase} (s : Session p) (c : ClientMessage)
    {p2 : Phase} (s2 : Session p2) (out : List MirrorMessage) (hp : p ∈ specPhases)
    (h : step orc s c = .ok ⟨p2, s2, out⟩) : phaseOkP ⟨p2, s2.flow, out, matchesOf c⟩ := by
  have href := step_refines_tla orc s c s2 out h
  exact tlaSteps_phaseOk href (by simpa [embed, phaseOkP, specPhases] using hp)

/-! ### ClientNeverStuck, mirror obligations

The mirror halves of the spec invariant (the client never waits on a
message the mirror will never send): step responses are emitted only
from the phase the spec prescribes, and their emission forces the
target phase. -/

theorem emit_step_responses_from_stepping (orc : Oracles) {p : Phase} (s : Session p)
    (c : ClientMessage) {p2 : Phase} (s2 : Session p2) (out : List MirrorMessage)
    (h : step orc s c = .ok ⟨p2, s2, out⟩)
    (hmem : .stepOk ∈ out ∨ .stepMismatch ∈ out ∨ .allStepsDone ∈ out ∨ .nextStep ∈ out) :
    p = .stepping := by
  have h1 := no_unsolicited_output orc s c s2 out h
  rcases hmem with hm | hm | hm | hm <;> cases p
  any_goals rfl
  all_goals exact absurd (h1 _ hm) (by simp [AllowedOutputs])
theorem emit_initialState_target_stepping (orc : Oracles) {p : Phase} (s : Session p)
    (c : ClientMessage) {p2 : Phase} (s2 : Session p2) (out : List MirrorMessage)
    (h : step orc s c = .ok ⟨p2, s2, out⟩) (hmem : .initialState ∈ out) :
    p = .idle ∧ p2 = .stepping := by
  have h1 := no_unsolicited_output orc s c s2 out h
  have hp : p = .idle := by
    cases p
    · rfl
    all_goals exact absurd (h1 _ hmem) (by simp [AllowedOutputs])
  subst hp
  match c with
  | .register =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact ⟨rfl, rfl⟩
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact absurd hmem (by decide)
  | .registerExplore =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact ⟨rfl, rfl⟩
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact absurd hmem (by decide)
  | .registerTraces =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact ⟨rfl, rfl⟩
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact absurd hmem (by decide)
  | .registerGenTraces => simp only [step, Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl, rfl⟩ := h; exact absurd hmem (by decide)
  | .registerExploreSession =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact absurd hmem (by decide)
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact absurd hmem (by decide)
  | .registerValidate =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact absurd hmem (by decide)
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact absurd hmem (by decide)
  | .registerValidateAsync => simp only [step, Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl, rfl⟩ := h; exact absurd hmem (by decide)
  | .registerGenTracesAsync => simp only [step, Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl, rfl⟩ := h; exact absurd hmem (by decide)
  | .queryJob => simp only [step] at h; cases h
  | .awaitJob => simp only [step] at h; cases h
  | .cancelJob => simp only [step] at h; cases h
  | .exploreCmd => simp only [step] at h; cases h
  | .exploreDone => simp only [step] at h; cases h
  | .reportState m l => simp only [step] at h; cases h
theorem emit_explorerReady_target_exploring (orc : Oracles) {p : Phase} (s : Session p)
    (c : ClientMessage) {p2 : Phase} (s2 : Session p2) (out : List MirrorMessage)
    (h : step orc s c = .ok ⟨p2, s2, out⟩) (hmem : .explorerReady ∈ out) :
    p = .idle ∧ p2 = .exploring := by
  have h1 := no_unsolicited_output orc s c s2 out h
  have hp : p = .idle := by
    cases p
    · rfl
    all_goals exact absurd (h1 _ hmem) (by simp [AllowedOutputs])
  subst hp
  match c with
  | .registerExploreSession =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact ⟨rfl, rfl⟩
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact absurd hmem (by decide)
  | .register =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact absurd hmem (by decide)
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact absurd hmem (by decide)
  | .registerTraces =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact absurd hmem (by decide)
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact absurd hmem (by decide)
  | .registerExplore =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact absurd hmem (by decide)
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact absurd hmem (by decide)
  | .registerGenTraces => simp only [step, Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl, rfl⟩ := h; exact absurd hmem (by decide)
  | .registerValidate =>
    simp only [step] at h
    by_cases hv : orc.validationOk = true
    · rw [if_pos hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact absurd hmem (by decide)
    · rw [if_neg hv] at h
      simp only [Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact absurd hmem (by decide)
  | .registerValidateAsync => simp only [step, Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl, rfl⟩ := h; exact absurd hmem (by decide)
  | .registerGenTracesAsync => simp only [step, Except.ok.injEq, Sigma.mk.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl, rfl⟩ := h; exact absurd hmem (by decide)
  | .queryJob => simp only [step] at h; cases h
  | .awaitJob => simp only [step] at h; cases h
  | .cancelJob => simp only [step] at h; cases h
  | .exploreCmd => simp only [step] at h; cases h
  | .exploreDone => simp only [step] at h; cases h
  | .reportState m l => simp only [step] at h; cases h
