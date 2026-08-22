import Core.Protocol

/-!
# Core.Jobs: async job state machine (design §6.4)

Pure port of the async-job machinery of the Haskell reference
(Protocol.AsyncJobs + the job vocabulary of Protocol.Core, at pin
ModelMirros@3496251): JobId/JobKind/JobPhase/JobOutcome vocabulary,
the per-session job store, the job state machine with bounds
enforcement, and the §6.4 theorems (terminal phases absorbing,
JobUnknown exactly for never-submitted-or-evicted ids, outcome
congruence with the synchronous RegisterValidate flow, and bound
enforcement on both paths).

Everything IO-shaped in the Haskell (MVar/TVar store, thread pool,
registry-backed process resources) is deliberately abstracted away:
the store is a list, the runner outcome is an oracle, and the resource
lifecycle obligations live in Core.Resource.
-/

/-- Opaque job id (Haskell: @newtype JobId = JobId Text@). -/
structure JobId where
  text : String
  deriving DecidableEq, Repr

/-- The two async job families (Haskell Protocol.Core.JobKind). -/
inductive JobKind where
  | validateJob | genTracesJob
  deriving DecidableEq, Repr

/-- Job phases as they appear on the wire (Haskell Protocol.Core.JobPhase).
@jobUnknown@ is not a state of any stored job: it is the answer for an
absent id, which is why the store uses StoredPhase below. -/
inductive JobPhase where
  | jobPending | jobRunning | jobDone | jobFailed | jobCancelled | jobUnknown
  deriving DecidableEq, Repr

/-- Phases a stored job can actually be in: JobPhase minus jobUnknown. -/
inductive StoredPhase where
  | pending | running | done | failed | cancelled
  deriving DecidableEq, Repr

def StoredPhase.toJobPhase : StoredPhase → JobPhase
  | .pending => .jobPending | .running => .jobRunning | .done => .jobDone
  | .failed => .jobFailed | .cancelled => .jobCancelled

/-- The abstract validation verdict carried by a completed validate job.
The apalache payload is abstracted to the valid/invalid split the
message tags distinguish (spec SpecValidatedValid vs SpecValidatedInvalid). -/
inductive ValidateResult where
  | mkValid | mkInvalid
  deriving DecidableEq, Repr

/-- Terminal outcomes (Haskell Protocol.Core.JobOutcome). -/
inductive JobOutcome where
  | jobValidateDone (r : ValidateResult)
  | jobGenTracesDone (files : List String)
  | jobInfraError (msg : String)
  deriving DecidableEq, Repr

/-! ## The job state machine -/

/-- The three terminal phases of the Haskell state machine. -/
def isTerminal : StoredPhase → Bool
  | .done | .failed | .cancelled => true
  | _ => false

/-- One stored job. -/
structure JobEntry where
  kind : JobKind
  phase : StoredPhase
  outcome : Option JobOutcome
  deriving Repr

/-- The events the job machinery applies to a stored job (worker pickup,
apalache completion, infrastructure failure, client cancellation). -/
inductive JobEvent where
  | startRunning
  | complete (o : JobOutcome)
  | failInfra (msg : String)
  | requestCancel

/-- One transition of the job state machine. Terminal states are
absorbing: every event leaves the entry unchanged. -/
def transition (e : JobEntry) (ev : JobEvent) : JobEntry :=
  if isTerminal e.phase then e else
    match e.phase, ev with
    | .pending, .startRunning => {e with phase := .running}
    | .pending, .complete o => {e with phase := .done, outcome := some o}
    | .pending, .failInfra msg => {e with phase := .failed, outcome := some (.jobInfraError msg)}
    | .pending, .requestCancel => {e with phase := .cancelled}
    | .running, .complete o => {e with phase := .done, outcome := some o}
    | .running, .failInfra msg => {e with phase := .failed, outcome := some (.jobInfraError msg)}
    | .running, .requestCancel => {e with phase := .cancelled}
    | _, _ => e

/-- **§6.4 (absorbing):** a terminal job never changes again. -/
theorem terminal_absorbing (e : JobEntry) (h : isTerminal e.phase = true)
    (ev : JobEvent) : transition e ev = e :=
  by simp [transition, h]

/-- Transitioning never un-terminates a job. -/
theorem isTerminal_of_transition (e : JobEntry) (ev : JobEvent)
    (h : isTerminal e.phase = true) : isTerminal (transition e ev).phase = true := by
  rw [terminal_absorbing e h ev]; exact h

/-- A job that reaches @done@ via a transition from a non-terminal phase
carries its outcome. -/
theorem done_has_outcome (e : JobEntry) (ev : JobEvent)
    (hnt : isTerminal e.phase = false)
    (h : (transition e ev).phase = .done) :
    (transition e ev).outcome.isSome = true := by
  cases e with
  | mk k p o =>
    cases p <;> cases ev <;> simp_all [transition, isTerminal]

/-! ## The job store -/

/-- Per-session store (Haskell: JobStore with a counter for @job-<n>@ ids). -/
structure JobStore where
  jobs : List (JobId × JobEntry)
  counter : Nat
  deriving Repr

def lookupJob : List (JobId × JobEntry) → JobId → Option JobEntry
  | [], _ => none
  | (k, e) :: rest, j => if k = j then some e else lookupJob rest j

def JobStore.lookupEntry (st : JobStore) (j : JobId) : Option JobEntry :=
  lookupJob st.jobs j

/-- The pure counterpart of a QueryJob request: the stored phase, or
@jobUnknown@ when the id is absent. -/
def queryJobPhase (st : JobStore) (j : JobId) : JobPhase :=
  match st.lookupEntry j with
  | none => .jobUnknown
  | some e => e.phase.toJobPhase

/-- **§6.4 (JobUnknown exactly):** a query answers @jobUnknown@
iff the id is not in the store (never submitted, or evicted). -/
theorem queryJobPhase_unknown_iff (st : JobStore) (j : JobId) :
    queryJobPhase st j = .jobUnknown ↔ st.lookupEntry j = none := by
  unfold queryJobPhase
  cases h : st.lookupEntry j with
  | none => simp [h]
  | some e =>
    cases e with
    | mk k p o =>
      cases p <;> simp [h, StoredPhase.toJobPhase]

/-- Eviction (session close or store cap): the id becomes unknown. -/
def evict (st : JobStore) (j : JobId) : JobStore :=
  {st with jobs := st.jobs.filter (fun p => p.1 != j)}

theorem lookupJob_filter_ne : ∀ (l : List (JobId × JobEntry)) (j : JobId),
    lookupJob (l.filter (fun p => p.1 != j)) j = none := by
  intro l j
  induction l with
  | nil => rfl
  | cons hd tl ih =>
    by_cases hj : hd.1 = j
    · simp [List.filter_cons, hj, lookupJob, ih]
    · simp [List.filter_cons, hj, lookupJob, ih]
/-- **§6.4 (eviction):** after eviction the id answers unknown. -/
theorem evicted_becomes_unknown (st : JobStore) (j : JobId) :
    queryJobPhase (evict st j) j = .jobUnknown := by
  rw [queryJobPhase_unknown_iff]
  exact lookupJob_filter_ne st.jobs j

/-- Submitted ids answer a real phase, never unknown. -/
theorem submitted_not_unknown (st : JobStore) (j : JobId) (e : JobEntry)
    (h : st.lookupEntry j = some e) : queryJobPhase st j ≠ .jobUnknown := by
  intro hcontra
  rw [queryJobPhase_unknown_iff] at hcontra
  rw [h] at hcontra
  simp at hcontra
/-! ## Bounds enforcement -/

/-- Server-side cap, single source of truth (Haskell maxValidateBound). -/
def maxValidateBound : Int := 100

/-- Bounds accepted from a client: [1, maxValidateBound]. -/
def checkBound (b : Int) : Bool := 1 <= b && b <= maxValidateBound

inductive SubmitError where
  | boundOutOfRange
  | internal (e : ProtocolError)
  deriving Repr

def JobStore.nextJobId (st : JobStore) : JobId :=
  {text := "job-" ++ toString st.counter}

def JobStore.insertJob (st : JobStore) (j : JobId) (e : JobEntry) : JobStore :=
  {st with jobs := (j, e) :: st.jobs, counter := st.counter + 1}

/-- Submit an async validate job. The bound is checked before anything is
stored - the identical guard to the synchronous path. -/
def submitValidateJob (st : JobStore) (b : Int) :
    Except SubmitError (JobStore × JobId) :=
  if checkBound b then
    .ok (st.insertJob st.nextJobId {kind := .validateJob, phase := .pending, outcome := none}, st.nextJobId)
  else .error .boundOutOfRange

/-- The synchronous RegisterValidate path behind the same bound guard:
Core.step with the validate-only flow. -/
def registerValidateSync (b : Int) (orc : Oracles) :
    Except SubmitError ((p' : Phase) × Session p' × List MirrorMessage) :=
  if checkBound b then
    match step orc (⟨.none⟩ : Session .idle) .registerValidate with
    | .ok r => .ok r
    | .error e => .error (.internal e)
  else .error .boundOutOfRange

/-- **§6.4 (bounds):** out-of-range bounds are rejected on both paths. -/
theorem bounds_rejected_both_paths (st : JobStore) (b : Int) (orc : Oracles)
    (h : checkBound b = false) :
    submitValidateJob st b = .error .boundOutOfRange ∧
      registerValidateSync b orc = .error .boundOutOfRange := by
  simp [submitValidateJob, registerValidateSync, h]

theorem bounds_accepted_submit (st : JobStore) (b : Int) (h : checkBound b = true) :
    (submitValidateJob st b).isOk = true := by
  simp only [submitValidateJob, h]
  rfl

/-! ## Outcome congruence -/

/-- Observational view of an outcome: the message tag a client sees. -/
def outcomeTag : JobOutcome → MirrorMessage
  | .jobValidateDone _ => .specValidated
  | .jobGenTracesDone _ => .genTracesDone
  | .jobInfraError _ => .registerError

/-- What the async machinery records when apalache finishes a validate job,
given the same oracle bit the synchronous Core.step uses. -/
def oracleValidateOutcome (ok : Bool) : JobOutcome :=
  if ok then .jobValidateDone .mkValid else .jobInfraError "apalache failure"

/-- The single tag the synchronous RegisterValidate flow replies with. -/
def syncValidateReplyTag (ok : Bool) : MirrorMessage :=
  match step {validationOk := ok} (⟨.none⟩ : Session .idle) .registerValidate with
  | .ok ⟨_, _, [m]⟩ => m
  | _ => .protocolError

/-- **§6.4 (outcome congruence):** the completed validate job′s
observable tag equals the synchronous RegisterValidate reply, on
identical oracle inputs. -/
theorem outcome_congruence (ok : Bool) :
    outcomeTag (oracleValidateOutcome ok) = syncValidateReplyTag ok := by
  unfold syncValidateReplyTag oracleValidateOutcome outcomeTag step
  cases ok <;> rfl

/-- The completed async job machine ends in @done@ with exactly that
outcome, and @done@ is terminal. -/
theorem async_completion (ok : Bool) :
    let e := transition {kind := .validateJob, phase := .running, outcome := none}
      (.complete (oracleValidateOutcome ok))
    e.phase = .done ∧e.outcome = some (oracleValidateOutcome ok) ∧
      isTerminal e.phase = true := by
  unfold transition
  cases ok <;> simp [oracleValidateOutcome, isTerminal]
