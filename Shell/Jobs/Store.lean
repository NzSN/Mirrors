import Core.Jobs
import Core.AsyncOwnership
import Codec.Json
import Std.Sync.Mutex
import Std.Sync.Semaphore
import Lean

/-!
# Shell.Jobs.Store — the effectful async job store (Layer 3, design 5.4)

Port of the Haskell @Protocol.AsyncJobs@ per-session job store to Lean
@Task@ workers with a @Std.Mutex@-protected store and a
@Std.Semaphore@ worker-slot bound:

* One dedicated @Task@ per submitted job (Haskell @forkIO@); the
  semaphore bounds concurrently *running* job bodies, the store capacity
  bounds live (non-terminal) jobs — a submit beyond it fails
  synchronously with @job queue full@, exactly like Haskell.
* Every phase transition goes through the **pure** machine
  @Core.Jobs.transition@ (worker pickup, completion, infra failure,
  cancellation), so the §6.4 absorbing-terminal law is exactly the
  race-safety argument for double-cancel / cancel-vs-finish.
* Terminal results are retained in the store and delivered idempotently
  (a promise resolved at most once, under the store lock).
* Unknown ids answer @jobUnknown@ in query / @unknown@ in await (Haskell
  semantics); session finalization cancels and evicts its own ids,
  after which their queries are unknown — the effectful image of
  @Core.Jobs.evicted_becomes_unknown@.
* The job bodies are injected (@Runner@ below; Haskell @JobRunner@):
  Phase 5 wires the real apalache adapters, tests inject fakes.

Divergence from Haskell, documented: Lean tasks cannot be killed, so
cancellation is *cooperative* — the store flips the job's cancel token,
runs the body-registered cleanup (Phase 5 uses it to terminate the
apalache child), performs the terminal transition (so a late body result
is discarded by the absorbing law). The worker releases its own slot only
after its body exits. A noncooperative body can retain that slot; logical
cancellation is not a physical-quiescence claim.
-/

namespace Shell.Jobs

/-! ## Cancellation tokens (cooperative) -/

/-- Cooperative cancellation token handed to job bodies. The body may
poll @isCancelled@ and register cleanup (Phase 5: terminate the child
process). -/
private structure TokenState where
  registry : Core.AsyncResources.Cancellation.Checked (IO Unit) := .initial
  accounting : Option Core.AsyncResources.CheckedJob := none

structure CancelToken where
  private state : Std.Mutex TokenState

def CancelToken.new : BaseIO CancelToken := do
  return ⟨← Std.Mutex.new {}⟩

/-- Proof terms are erased; all successful accounting states carry a kernel
proof of reachability through the same executable transitions. -/
def CancelToken.newTracked (ownedSpec : Bool) : BaseIO CancelToken := do
  return ⟨← Std.Mutex.new { accounting := some (.initial ownedSpec) }⟩

def CancelToken.resourceEvent (t : CancelToken) (event : Core.AsyncResources.Event) : IO Unit := do
  if event = .cancel ∨ event = .installHook then
    throw (IO.userError "use atomic cancellation/child-hook registration")
  let accepted ← t.state.atomically do
    let current ← get
    match current.accounting with
    | none => return true
    | some accounting =>
      match accounting.step event with
      | none => return false
      | some next => set { current with accounting := some next }; return true
  if !accepted then throw (IO.userError s!"async resource accounting rejected {repr event}")

def CancelToken.resourceSnapshot (t : CancelToken) : BaseIO (Option Core.AsyncResources.Job) :=
  t.state.atomically do return (← get).accounting.map (·.value)

def CancelToken.isCancelled (t : CancelToken) : BaseIO Bool :=
  t.state.atomically do return (← get).registry.value.cancelled

private def registerTokenCleanup (t : CancelToken) (f : IO Unit) (child : Bool) : IO (IO Unit) := do
  let registration : Option (Option Nat × Option (IO Unit)) ← t.state.atomically do
    let current ← get
    let accounting? := if child then
        match current.accounting with
        | none => some none
        | some job => (job.step .installHook).map some
      else some current.accounting
    let some accounting := accounting? | return none
    let (registry, id?, immediate) := current.registry.register f
    set ({ registry, accounting } : TokenState)
    return some (id?, immediate)
  let some (id?, immediate) := registration
    | throw (IO.userError "async resource accounting rejected child hook")
  if let some cleanup := immediate then cleanup
  match id? with
  | none => return pure ()
  | some id => return t.state.atomically do
      modify (fun s => { s with registry := s.registry.retire id })

def CancelToken.registerCleanup (t : CancelToken) (f : IO Unit) : IO (IO Unit) :=
  registerTokenCleanup t f false

/-- Install the child hook and make its cancellation decision in one lock. -/
def CancelToken.registerChildCleanup (t : CancelToken) (f : IO Unit) : IO (IO Unit) :=
  registerTokenCleanup t f true

def CancelToken.onCancel (t : CancelToken) (f : IO Unit) : IO Unit := do
  let _ ← t.registerCleanup f

def CancelToken.cancel (t : CancelToken) : IO Unit := do
  let hooks : List (Nat × IO Unit) ← t.state.atomically do
    let current ← get
    let (registry, hooks) := current.registry.cancel
    set ({ registry, accounting := current.accounting.map (·.cancel) } : TokenState)
    return hooks
  let mut firstError : Option IO.Error := none
  for (_, cleanup) in hooks do
    try cleanup catch e => if firstError.isNone then firstError := some e
  if let some error := firstError then throw error

/-! ## Injectable job bodies -/

/-- The injected job-body surface (Haskell @JobRunner@): run one
validate / trace-generation invocation, observing the cancel token. The
real apalache-backed runner lands in Phase 5. -/
structure Runner where
  validate : Codec.ApalacheConfig → Option Codec.SpecConfig → Nat → CancelToken →
    IO (Except String Codec.ValidateResult)
  genTraces : Codec.ApalacheConfig → Option Codec.SpecConfig → Codec.TraceConfig → CancelToken →
    IO (Except String Codec.TraceGenResult)

/-- A runner whose every call fails immediately (placeholder until the
Phase 5 apalache adapters: accepted jobs end @failed@). -/
def stubRunner : Runner where
  validate _ _ _ _ :=
    pure (.error "apalache validate adapter lands in Phase 5")
  genTraces _ _ _ _ :=
    pure (.error "apalache trace-generation adapter lands in Phase 5")

/-! ## The store -/

/-- One stored job: the pure-machine entry plus the effectful delivery
state. @wire@ is the terminal outcome in wire shape (retained until
eviction). The job thread retains its semaphore permit until lexical cleanup
finishes, independently of table eviction or cancellation. -/
structure JobRec where
  /-- Job family (pure vocabulary, root namespace). -/
  kind : JobKind
  /-- Pure-machine state; every transition runs @Core.Jobs.transition@. -/
  entry : JobEntry
  /-- Resolved exactly once, at the terminal transition. -/
  result : IO.Promise (Option Codec.JobOutcome)
  /-- Terminal outcome in wire shape, retained for re-delivery. -/
  wire : Option Codec.JobOutcome
  token : CancelToken

abbrev JobTable := List (JobId × JobRec)

private structure St where
  counter : Nat
  jobs : JobTable

private def lookupRec : JobTable → JobId → Option JobRec :=
  Core.AsyncResources.lookupEntry

private def isTerm (e : JobEntry) : Bool := isTerminal e.phase

private def liveCount (s : St) : Nat :=
  (s.jobs.filter (fun (_, jr) => !isTerm jr.entry)).length

/-- Per-session async job store (Haskell @JobStore@). -/
structure JobStore where
  /-- Bound on live (non-terminal) jobs; @job queue full@ beyond it. -/
  capacity : Nat
  /-- Bound on concurrently running bodies (worker slots). -/
  slots : Std.Semaphore
  runner : Runner
  st : Std.Mutex St

/-- New store with the given live-job capacity and injected runner
(Haskell @newJobStoreWith@; worker slots = capacity, at least 1). -/
def newJobStoreWith (capacity : Nat) (runner : Runner) : BaseIO JobStore := do
  return { capacity := capacity,
           slots := ← Std.Semaphore.new (max 1 capacity),
           runner := runner,
           st := ← Std.Mutex.new { counter := 0, jobs := [] } }

/-- New store with the stub (Phase-5-pending) runner. -/
def newJobStore (capacity : Nat) : BaseIO JobStore :=
  newJobStoreWith capacity stubRunner

/-- Server-side validate bound cap, single source (Core.Jobs). -/
def maxValidateBound : Int := _root_.maxValidateBound

/-- Wire-facing phase names (Haskell @phaseText@). -/
def phaseText : JobPhase → String
  | .jobPending => "pending" | .jobRunning => "running" | .jobDone => "done"
  | .jobFailed => "failed" | .jobCancelled => "cancelled" | .jobUnknown => "unknown"

/-- Convert the stored phase to the wire codec's phase. -/
def toWirePhase : JobPhase → Codec.JobPhase
  | .jobPending => .pending | .jobRunning => .running | .jobDone => .done
  | .jobFailed => .failed | .jobCancelled => .cancelled | .jobUnknown => .unknown

/-- Non-blocking poll (Haskell @queryJob@): unknown ids answer
@jobUnknown@; terminal jobs carry their retained wire outcome. -/
def queryJob (store : JobStore) (jid : JobId) :
    IO (JobPhase × Option Codec.JobOutcome) := do
  store.st.atomically do
    let s ← get
    match lookupRec s.jobs jid with
    | none => return (.jobUnknown, none)
    | some jr =>
      return (jr.entry.phase.toJobPhase,
        if isTerm jr.entry then jr.wire else none)

/-- Long-poll (Haskell @awaitJob@): block on the job's result; the
optional timeout (seconds) yields @Left@ with the current phase name.
Unknown ids yield @Left "unknown"@. -/
def awaitJob (store : JobStore) (jid : JobId) (timeout : Option Nat) :
    IO (Except String Codec.JobOutcome) := do
  let prom? ← store.st.atomically do
    let s ← get
    return (lookupRec s.jobs jid).map (·.result)
  match prom? with
  | none => return .error "unknown"
  | some prom =>
    let now ← IO.monoMsNow
    let deadline := timeout.map (fun secs => now + secs * 1000)
    let mut out? : Option Codec.JobOutcome := none
    -- polling combines promise waiting with the timeout without leaking
    -- helper threads; the resolved promise retains its value
    while out?.isNone do
      if ← prom.isResolved then
        out? ← store.st.atomically do
          let s ← get
          return (lookupRec s.jobs jid).bind (fun jr => jr.wire)
        break
      else
        match deadline with
        | some d => if (← IO.monoMsNow) >= d then break else IO.sleep 5
        | none => IO.sleep 5
    match out? with
    | some o => return .ok o
    | none =>
      let (ph, _) ← queryJob store jid
      return .error (phaseText ph)

private def acquireSlot (store : JobStore) : IO Unit := do
  let p ← store.slots.acquire
  -- t33 fix: IO.wait, NOT Task.get — Task.get on the unresolved promise
  -- task returns immediately (Lean 4.33; Docs/worker-pool-impl-status.md
  -- §3), which silently disabled the worker-slot throttle since t31.
  let _acquired ← IO.wait p.result?

private def releaseSlot (store : JobStore) : IO Unit := store.slots.release

/-- Apply a pure-machine event to a stored job under the store lock;
the returned follow-up actions (resolve the result promise) run after unlocking. The transition itself is entirely the
pure machine's. -/
private def applyEvent (store : JobStore) (jid : JobId) (ev : JobEvent)
    (wireOut : Option Codec.JobOutcome) : IO Unit := do
  let acts : Array (IO Unit) ← store.st.atomically do
    let s ← get
    match lookupRec s.jobs jid with
    | none => return #[]
    | some jr =>
      if isTerm jr.entry then
        return #[]
      else
        let entryNew := transition jr.entry ev
        if isTerm entryNew then
          let result : Core.AsyncResources.Outcome :=
            match entryNew.phase, wireOut with
            | .cancelled, _ => .cancelled
            | _, some (.validate .valid) => .valid
            | _, some (.validate (.invalid _)) => .invalid
            | _, some (.genTraces _) => .traces
            | _, _ => .failed
          jr.token.resourceEvent (.publish result)
        let recNew := { jr with entry := entryNew, wire := (if isTerm entryNew then wireOut else jr.wire) }
        let jobs' := s.jobs.map
          (fun (k, v) => if k == jid then (k, recNew) else (k, v))
        set { s with jobs := jobs' }
        let mut acts := #[]
        if isTerm entryNew then
          if let some o := wireOut then
            acts := acts.push (promResolve recNew.result o)
        return acts
  for a in acts do a
where
  promResolve (p : IO.Promise (Option Codec.JobOutcome))
      (o : Codec.JobOutcome) : IO Unit := p.resolve (some o)

/-- Map a wire outcome to the pure machine's abstract outcome. -/
private def toCoreOutcome : Codec.JobOutcome → JobOutcome
  | .validate .valid => .jobValidateDone .mkValid
  | .validate (.invalid m) => .jobValidateDone .mkInvalid
  | .genTraces r => .jobGenTracesDone r.itfTracePaths
  | .infraError m => .jobInfraError m

/-- The job thread (Haskell @jobThread@): acquire a worker slot, run the
body, perform the terminal transition. A late body result after a
cancel/close is discarded by the pure machine's absorbing law. -/
private def runJobBody (store : JobStore) (jid : JobId) (token : CancelToken)
    (body : CancelToken → IO (Except String Codec.JobOutcome)) : IO Unit := do
  let started ← store.st.atomically do
    let s ← get
    match lookupRec s.jobs jid with
    | none => return false
    | some jr =>
      if isTerm jr.entry then return false
      let recNew := { jr with entry := transition jr.entry .startRunning }
      set { s with jobs := s.jobs.map (fun (k, v) => if k == jid then (k, recNew) else (k, v)) }
      return true
  if started then
    let outcome : Codec.JobOutcome ←
      try
        if ← token.isCancelled then pure (.infraError "job cancelled")
        else
          match ← body token with
          | .ok o => pure o
          | .error e => pure (.infraError e)
      catch e => pure (.infraError s!"job body crashed: {e}")
    try
      match outcome with
      | .infraError msg => applyEvent store jid (.failInfra msg) (some outcome)
      | _ => applyEvent store jid (.complete (toCoreOutcome outcome)) (some outcome)
    catch error =>
      let message := s!"job resource accounting failed: {error}"
      applyEvent store jid (.failInfra message) (some (.infraError message))

private def jobThread (store : JobStore) (jid : JobId) (token : CancelToken)
    (body : CancelToken → IO (Except String Codec.JobOutcome)) : IO Unit := do
  acquireSlot store
  try
    token.resourceEvent .start
    let result : Except IO.Error Unit ←
      try runJobBody store jid token body; pure (.ok ())
      catch error => pure (.error error)
    token.resourceEvent .settle
    match result with
    | .ok () => pure ()
    | .error error => throw error
  finally
    releaseSlot store

/-- Shared submit (Haskell @submitJob@): capacity check, id assignment,
handle creation, task spawn, map insert. -/
private partial def submitJob (store : JobStore) (kind : JobKind) (ownedSpec : Bool)
    (body : CancelToken → IO (Except String Codec.JobOutcome)) :
    IO (Except String JobId) := do
  let alloc ← store.st.atomically do
    let s ← get
    if !Core.AsyncResources.admissionAllowed (liveCount s) store.capacity then
      return (Except.error "job queue full")
    else
      return (Except.ok (s.counter, ({ text := "job-" ++ toString s.counter } : JobId)))
  match alloc with
  | .error e => return .error e
  | .ok (n, jid) =>
    let prom ← IO.Promise.new
    let token ← CancelToken.newTracked ownedSpec
    let inserted ← store.st.atomically do
      let s ← get
      if !Core.AsyncResources.admissionAllowed (liveCount s) store.capacity || s.counter != n then
        return false
      else
        let jr : JobRec := { kind := kind, entry := { kind := kind, phase := .pending, outcome := none }, result := prom, wire := none, token }
        let jobs' := (jid, jr) :: s.jobs
        set { s with counter := s.counter + 1, jobs := jobs' }
        return true
    if inserted then
      try
        let _task ← IO.asTask (prio := Task.Priority.dedicated) (jobThread store jid token body)
        return .ok jid
      catch error =>
        store.st.atomically do
          modify fun s => { s with jobs := Core.AsyncResources.dropEntry jid s.jobs }
        return .error s!"job task launch failed: {error}"
    else
      -- lost the capacity/counter race under the second pass: retry
      submitJob store kind ownedSpec body

/-- Submit an async validate job (Haskell @submitValidateJob@): the
bound guard runs synchronously before acceptance. -/
def submitValidateJob (store : JobStore) (cfg : Codec.ApalacheConfig)
    (bound : Nat) (spec : Option Codec.SpecConfig) : IO (Except String JobId) :=
  if (bound : Int) < 1 || (bound : Int) > maxValidateBound then
    return .error
      s!"validate bound {bound} outside allowed range 1..{maxValidateBound}"
  else
    submitJob store .validateJob spec.isSome (fun token => do
      match ← store.runner.validate cfg spec bound token with
      | .ok v => return (Except.ok (Codec.JobOutcome.validate v))
      | .error e => return (Except.ok (Codec.JobOutcome.infraError e)))

/-- Submit an async trace-generation job (Haskell @submitGenTracesJob@). -/
def submitGenTracesJob (store : JobStore) (cfg : Codec.ApalacheConfig)
    (tc : Codec.TraceConfig) (_dest : Option String) (spec : Option Codec.SpecConfig) :
    IO (Except String JobId) :=
  submitJob store .genTracesJob spec.isSome (fun token => do
      match ← store.runner.genTraces cfg spec tc token with
      | .ok r => return (Except.ok (Codec.JobOutcome.genTraces r))
      | .error e => return (Except.ok (Codec.JobOutcome.infraError e)))

/-- Cancel a job (Haskell @cancelJob@): flip the token, run the body
cleanup and terminal-transition to cancelled. The worker retains its slot
until its body exits. Unknown ids
are a no-op. -/
def cancelJob (store : JobStore) (jid : JobId) : IO Unit := do
  let token? ← store.st.atomically do
    let s ← get
    match lookupRec s.jobs jid with
    | none => return none
    | some jr =>
      if isTerm jr.entry then return none
      else return some jr.token
  match token? with
  | none => pure ()
  | some token =>
    try token.cancel
    finally
      applyEvent store jid .requestCancel
        (some (Codec.JobOutcome.infraError "job cancelled"))

/-- Cancel one stored job's id (eviction): afterwards every query for
it answers @jobUnknown@ — the effectful image of
@Core.Jobs.evicted_becomes_unknown@. -/
def evictJob (store : JobStore) (jid : JobId) : IO Unit := do
  store.st.atomically do
    modify (fun s => { s with jobs := Core.AsyncResources.dropEntry jid s.jobs })

/-- Session close (Haskell @closeJobStore@): cancel every live job
(cooperative: token flip + body cleanup + terminal transition), like
the Haskell force-release-all. Ids stay known (cancelled) exactly as
in the Haskell store, whose queries after close answer @cancelled@. -/
def closeJobStore (store : JobStore) : IO Unit := do
  let ids ← store.st.atomically do
    let s ← get
    return (s.jobs.filter (fun (_, jr) => !isTerm jr.entry)).map Prod.fst
  let mut firstError : Option IO.Error := none
  for jid in ids do
    try cancelJob store jid catch error => if firstError.isNone then firstError := some error
  if let some error := firstError then throw error

end Shell.Jobs