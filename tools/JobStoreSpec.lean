import Shell.Mirror.Session
import Shell.Jobs.Store
import Shell.Transport.Mock
import Codec.Json
import Core.Value
import Lean.Data.Json

/-!
# Phase 4 job-store parity suite (tools/JobStoreSpec.lean)

Lean port of the Haskell @Protocol.AsyncJobsSpec@ fake-runner scenarios
(the "recorded workloads" of the Phase 4 exit criterion): with the same
injected fake job bodies, the Lean store + async session must produce
the same client-visible behavior as the Haskell implementation (phases,
outcomes, bound and capacity rejections, unknown-id answers,
cancellation, session close).
-/

open Shell.Jobs Shell.Mirror Codec

def isErr {α : Type} : Except String α → Bool
  | .error _ => true
  | .ok _ => false

def eqOutcome : Codec.JobOutcome → Codec.JobOutcome → Bool
  | .validate .valid, .validate .valid => true
  | .validate (.invalid a), .validate (.invalid b) => a == b
  | .genTraces a, .genTraces b => a.itfTracePaths == b.itfTracePaths
  | .infraError a, .infraError b => a == b
  | _, _ => false

def isOkOutcome (want : Codec.JobOutcome) (r : Except String Codec.JobOutcome) : Bool :=
  match r with
  | .ok o => eqOutcome want o
  | .error _ => false

def isJobErr (want : String) (r : Except String JobId) : Bool :=
  match r with
  | .error e => e == want
  | .ok _ => false

def isPhaseErr (want : String) (r : Except String Codec.JobOutcome) : Bool :=
  match r with
  | .error e => e == want
  | .ok _ => false

abbrev Failures := IO.Ref (List String)

def check (fails : Failures) (name : String) (ok : Bool) (detail : String := "") : IO Unit := do
  if !ok then
    if detail.isEmpty then fails.modify (fun fs => fs ++ [name])
    else fails.modify (fun fs => fs ++ [s!"{name}: {detail}"])

/-! ## Fake runners (Haskell fakes) -/

/-- fakeOkRunner: always succeeds. -/
def fakeOkRunner : Runner where
  validate _ _ _ _ := pure (Except.ok .valid)
  genTraces _ _ _ _ :=
    pure (Except.ok { itfTracePaths := ["fake/1.itf.json"], itfTraces := [Value.vint 1] })

/-- fakeFail255Runner: apalache-style infra failure mentioning "boom". -/
def fakeFail255Runner : Runner where
  validate _ _ _ _ := pure (Except.error "boom: fake apalache exit 255")
  genTraces _ _ _ _ := pure (Except.error "boom: fake apalache exit 255")

/-- fakeBlockingRunner: blocks until released. -/
def fakeBlockingRunner (release : IO.Ref Bool) : Runner where
  validate _ _ _ _ := do
    let mut spin := true
    while spin do
      if (← release.get) then spin := false else IO.sleep 2
    pure (Except.ok .valid)
  genTraces _ _ _ _ := do
    let mut spin := true
    while spin do
      if (← release.get) then spin := false else IO.sleep 2
    pure (Except.ok { itfTracePaths := [], itfTraces := [] })

/-! ## Wire client helpers -/

abbrev InMem := Shell.Transport.Transport

def csend (c : InMem) (m : Codec.ClientMessage) : IO Unit :=
  c.send (toString (Lean.Json.compress (Codec.encodeClient m)))

def crecv (c : InMem) : IO (Except String Codec.MirrorMessage) := do
  let some l ← c.recv | return .error "connection closed"
  match Lean.Json.parse l with
  | .error e => return .error e
  | .ok j => pure ((Codec.decodeMirror j).mapError (fun (e : Codec.DecodeError) => e.msg))

def expectJobAccepted (c : InMem) : IO (Except String String) := do
  match ← crecv c with
  | .error e => return .error s!"recv: {e}"
  | .ok (.jobAccepted jid _) => return .ok jid
  | .ok m => return .error s!"expected job_accepted, got {repr m}"

def hcCfg : Codec.ApalacheConfig where
  constInit := none
  initPredicate := none
  invariant := ""
  lengthBound := 10
  nextPredicate := none
  paramVars := ""
  specPath := "HourClock.tla"

def hcTc : Codec.TraceConfig := { numTraces := 1, view := "utf8" }

def startAsync (mirror : InMem) (store : Shell.Jobs.JobStore) : IO Unit := do
  let _task ← IO.asTask (prio := Task.Priority.dedicated)
    (Shell.Mirror.runAsync mirror Shell.Mirror.stubOracles store)

/-- End a test session cleanly: a malformed line makes the session reply
@protocol_error@ and exit, so the spec process can terminate. -/
def endSession (c : InMem) : IO Unit := do
  c.send "{"
  let _ ← crecv c

/-! ## Scenarios -/

/-- Wire-level async validate round-trip (Haskell testValidateRoundTrip). -/
def scenarioValidateRoundTrip (fails : Failures) : IO Unit := do
  let (client, mirror) ← Shell.Transport.mockPair
  let store ← Shell.Jobs.newJobStoreWith 4 fakeOkRunner
  startAsync mirror store
  csend client (.registerValidateAsync hcCfg 1 none)
  let rjid ← expectJobAccepted client
  check fails "validate: accepted" rjid.isOk (toString (repr rjid))
  match rjid with
  | .error _ => return
  | .ok jid =>
    csend client (.awaitJob jid none)
    match ← crecv client with
    | .error e => check fails "validate: await recv" false e
    | .ok (.jobResult _ (.validate .valid)) => check fails "validate: result" true
    | .ok m => check fails "validate: result" false (toString (repr m))
  endSession client

/-- Wire-level async gen-traces round-trip (Haskell testGenTracesRoundTrip). -/
def scenarioGenTracesRoundTrip (fails : Failures) : IO Unit := do
  let (client, mirror) ← Shell.Transport.mockPair
  let store ← Shell.Jobs.newJobStoreWith 4 fakeOkRunner
  startAsync mirror store
  csend client (.registerGenTracesAsync hcCfg none none hcTc)
  let rjid ← expectJobAccepted client
  check fails "genTraces: accepted" rjid.isOk (toString (repr rjid))
  match rjid with
  | .error _ => return
  | .ok jid =>
    csend client (.awaitJob jid none)
    match ← crecv client with
    | .error e => check fails "genTraces: await recv" false e
    | .ok (.jobResult _ (.genTraces r)) =>
        check fails "genTraces: paths" (!r.itfTracePaths.isEmpty) (toString (repr r.itfTracePaths))
        check fails "genTraces: contents" (!r.itfTraces.isEmpty) (toString (repr r.itfTraces))
    | .ok m => check fails "genTraces: result" false (toString (repr m))
  endSession client

/-- Bad bounds are pre-accept register errors (Haskell
testBadBoundRejectedPreAccept). -/
def scenarioBadBound (fails : Failures) : IO Unit := do
  let store ← Shell.Jobs.newJobStoreWith 4 fakeOkRunner
  let r0 ← Shell.Jobs.submitValidateJob store hcCfg 0 none
  let r101 ← Shell.Jobs.submitValidateJob store hcCfg 101 none
  check fails "bound 0 rejected" (isErr r0) (toString (repr r0))
  check fails "bound 101 rejected" (isErr r101) (toString (repr r101))
  let (client, mirror) ← Shell.Transport.mockPair
  startAsync mirror store
  csend client (.registerValidateAsync hcCfg 0 none)
  match ← crecv client with
  | .ok (.registerError e) => check fails "bound msg" (e.contains "outside allowed range") e
  | other => check fails "bound wire" false (toString (repr other))
  endSession client

/-- Forced apalache failure is a post-accept infra error (Haskell
testForcedApalacheFailureIsInfraError). -/
def scenarioInfraFailure (fails : Failures) : IO Unit := do
  let store ← Shell.Jobs.newJobStoreWith 4 fakeFail255Runner
  let r ← Shell.Jobs.submitValidateJob store hcCfg 1 none
  let .ok jid := r | check fails "infra: accepted" false (toString (repr r)); return
  match ← Shell.Jobs.awaitJob store jid none with
  | .error e => check fails "infra: await" false e
  | .ok (.infraError e) => check fails "infra: msg" (e.contains "boom") e
  | .ok o => check fails "infra: kind" false (toString (repr o))
  let (ph, out?) ← Shell.Jobs.queryJob store jid
  check fails "infra: phase failed" (ph == .jobFailed) (toString (repr ph))
  check fails "infra: retained" out?.isSome (toString (repr out?))

/-- Unknown ids answer jobUnknown everywhere (Haskell testUnknownJobId). -/
def scenarioUnknownJob (fails : Failures) : IO Unit := do
  let store ← Shell.Jobs.newJobStoreWith 4 fakeOkRunner
  let unknown : JobId := { text := "job-nope" }
  let (ph, out?) ← Shell.Jobs.queryJob store unknown
  check fails "unknown: query" (ph == .jobUnknown) (toString (repr ph))
  check fails "unknown: no outcome" out?.isNone (toString (repr out?))
  let a ← Shell.Jobs.awaitJob store unknown none
  check fails "unknown: await" (isPhaseErr "unknown" a) (toString (repr a))
  Shell.Jobs.cancelJob store unknown -- must not throw
  let (ph2, _) ← Shell.Jobs.queryJob store unknown
  check fails "unknown: still unknown" (ph2 == .jobUnknown) (toString (repr ph2))
  let (client, mirror) ← Shell.Transport.mockPair
  startAsync mirror store
  csend client (.queryJob "job-nope")
  match ← crecv client with
  | .ok (.jobStatus "job-nope" .unknown) => check fails "unknown: wire" true
  | other => check fails "unknown: wire" false (toString (repr other))
  endSession client

/-- Capacity 1 serializes (Haskell testCapacityOneSerializes). -/
def scenarioCapacity (fails : Failures) : IO Unit := do
  let release ← IO.mkRef false
  let store ← Shell.Jobs.newJobStoreWith 1 (fakeBlockingRunner release)
  let r1 ← Shell.Jobs.submitValidateJob store hcCfg 1 none
  let .ok j1 := r1 | check fails "cap: first submit" false (toString (repr r1)); return
  let mut running := false
  let mut tries := 0
  while !running && tries < 500 do
    let (ph, _) ← Shell.Jobs.queryJob store j1
    if ph == .jobRunning then
      running := true
    else
      IO.sleep 5
      tries := tries + 1
  check fails "cap: first running" running
  let r2 ← Shell.Jobs.submitValidateJob store hcCfg 1 none
  check fails "cap: queue full" (isJobErr "job queue full" r2) (toString (repr r2))
  release.set true
  match ← Shell.Jobs.awaitJob store j1 none with
  | .error e => check fails "cap: await 1" false e
  | .ok (.validate .valid) => check fails "cap: first valid" true
  | .ok o => check fails "cap: first valid" false (toString (repr o))
  release.set false
  let r3 ← Shell.Jobs.submitValidateJob store hcCfg 1 none
  check fails "cap: resubmit" r3.isOk (toString (repr r3))
  match r3 with
  | .error _ => return
  | .ok j3 =>
    release.set true
    match ← Shell.Jobs.awaitJob store j3 none with
    | .error e => check fails "cap: await 3" false e
    | .ok (.validate .valid) => check fails "cap: third valid" true
    | .ok o => check fails "cap: third valid" false (toString (repr o))
  Shell.Jobs.closeJobStore store

/-- Cancelling a running job answers cancelled and frees capacity
(Haskell testCancelRunningJob). -/
def scenarioCancel (fails : Failures) : IO Unit := do
  let release ← IO.mkRef false
  let store ← Shell.Jobs.newJobStoreWith 1 (fakeBlockingRunner release)
  match ← Shell.Jobs.submitValidateJob store hcCfg 1 none with
  | .error e => check fails "cancel: submit" false e; return
  | .ok jid =>
    let mut running := false
    let mut tries := 0
    while !running && tries < 500 do
      let (ph, _) ← Shell.Jobs.queryJob store jid
      if ph == .jobRunning then
        running := true
      else
        IO.sleep 5
        tries := tries + 1
    check fails "cancel: running" running
    Shell.Jobs.cancelJob store jid
    let (ph, out?) ← Shell.Jobs.queryJob store jid
    check fails "cancel: phase" (ph == .jobCancelled) (toString (repr ph))
    match out? with
    | some (.infraError e) => check fails "cancel: msg" (e == "job cancelled") e
    | o => check fails "cancel: outcome" false (toString (repr o))
    release.set true
    let r2 ← Shell.Jobs.submitValidateJob store hcCfg 1 none
    check fails "cancel: resubmit" r2.isOk (toString (repr r2))
    Shell.Jobs.closeJobStore store

/-- Session close cancels a running job (Haskell testSessionCloseGC). -/
def scenarioClose (fails : Failures) : IO Unit := do
  let release ← IO.mkRef false
  let store ← Shell.Jobs.newJobStoreWith 1 (fakeBlockingRunner release)
  match ← Shell.Jobs.submitValidateJob store hcCfg 1 none with
  | .error e => check fails "close: submit" false e; return
  | .ok jid =>
    let mut running := false
    let mut tries := 0
    while !running && tries < 500 do
      let (ph, _) ← Shell.Jobs.queryJob store jid
      if ph == .jobRunning then
        running := true
      else
        IO.sleep 5
        tries := tries + 1
    check fails "close: running" running
    Shell.Jobs.closeJobStore store
    let (ph, out?) ← Shell.Jobs.queryJob store jid
    check fails "close: cancelled" (ph == .jobCancelled) (toString (repr ph))
    match out? with
    | some (.infraError e) => check fails "close: msg" (e == "job cancelled") e
    | o => check fails "close: outcome" false (toString (repr o))
    release.set true

/-- await with a timeout answers the current phase, and the job still
completes afterwards (Haskell await-timeout semantics). -/
def scenarioAwaitTimeout (fails : Failures) : IO Unit := do
  let release ← IO.mkRef false
  let store ← Shell.Jobs.newJobStoreWith 1 (fakeBlockingRunner release)
  match ← Shell.Jobs.submitValidateJob store hcCfg 1 none with
  | .error e => check fails "timeout: submit" false e; return
  | .ok jid =>
    let r ← Shell.Jobs.awaitJob store jid (some 0)
    check fails "timeout: phase error"
      (isPhaseErr "running" r || isPhaseErr "pending" r) (toString (repr r))
    release.set true
    let r2 ← Shell.Jobs.awaitJob store jid (some 30)
    check fails "timeout: completes" (isOkOutcome (.validate .valid) r2) (toString (repr r2))
    Shell.Jobs.closeJobStore store

/-- Eviction makes an id unknown (Core.Jobs.evicted_becomes_unknown,
effectful image; the documented eviction policy). -/
def scenarioEviction (fails : Failures) : IO Unit := do
  let store ← Shell.Jobs.newJobStoreWith 4 fakeOkRunner
  match ← Shell.Jobs.submitValidateJob store hcCfg 1 none with
  | .error e => check fails "evict: submit" false e; return
  | .ok jid =>
    let _ ← Shell.Jobs.awaitJob store jid (some 30)
    let (ph0, _) ← Shell.Jobs.queryJob store jid
    check fails "evict: known before" (ph0 != .jobUnknown) (toString (repr ph0))
    Shell.Jobs.evictJob store jid
    let (ph1, out?) ← Shell.Jobs.queryJob store jid
    check fails "evict: unknown after" (ph1 == .jobUnknown) (toString (repr ph1))
    check fails "evict: outcome dropped" out?.isNone (toString (repr out?))

def main : IO UInt32 := do
  let fails ← IO.mkRef ([] : List String)
  let run (name : String) (s : Failures → IO Unit) := do
    IO.eprintln s!"[scenario {name}]"
    s fails
  run "validateRoundTrip" scenarioValidateRoundTrip
  run "genTracesRoundTrip" scenarioGenTracesRoundTrip
  run "badBound" scenarioBadBound
  run "infraFailure" scenarioInfraFailure
  run "unknownJob" scenarioUnknownJob
  run "capacity" scenarioCapacity
  run "cancel" scenarioCancel
  run "close" scenarioClose
  run "awaitTimeout" scenarioAwaitTimeout
  run "eviction" scenarioEviction
  let fs ← fails.get
  if fs.isEmpty then
    IO.println "JOBSTORE PARITY GREEN"
    return 0
  else
    for f in fs do IO.eprintln s!"FAIL {f}"
    IO.eprintln s!"{fs.length} FAILURES"
    return 1