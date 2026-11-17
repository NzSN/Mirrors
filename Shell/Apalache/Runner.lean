import Shell.Apalache.Cli
import Shell.Apalache.TraceGeneration
import Shell.Apalache.SpecSource
import Shell.Mirror.Session
import Shell.Jobs.Store
import Shell.Apalache.Explorer
import Core.Diff
import Core.Value
import Shell.Transport.Mock
import Codec.Json
import Lean

/-!
# Shell.Apalache.Runner — Phase 5 oracle/runner glue (design 5.4)

Wires the apalache CLI adapter into the two injection points:

* @Shell.Jobs.Runner@ — the async job bodies: spec acquisition (inline
  specs materialized, owned; release registered on the job's cancel
  token), a per-job session dir as apalache's @--run-dir@ / cwd, and
  cancellable spawns (job cancellation terminates the apalache child
  and removes the session dir).
* @Shell.Mirror.Oracles@ — the sync flows (@register@ /
  @register_trace_gen@ / @register_validate@); the explorer oracles
  stay Phase-5 stubs (t14).

Divergence from Haskell, documented: Haskell's @submitValidateJob@
materializes the spec *pre-accept* (a bad inline spec is a
@register_error@ before @job_accepted@). The Lean job store accepts
first and reports materialization failure as a post-accept
@job_infra_error@; the spec-source validation itself is identical.
-/

namespace Shell.Apalache

open Shell.Apalache.Cli Shell.Apalache.SpecSource Shell.Apalache.Explorer

/-- Consume an acquired spec, then bracket the run-directory acquisition and
body independently. The injected directory action is the acquisition boundary
used by regression tests; production passes `freshSessionDir`. Cancellation
kills the child through its token hook; directories unwind after collection. -/
def withAcquiredJobScope {α : Type} (token : Shell.Jobs.CancelToken)
    (res : SpecRes) (cfg : Codec.ApalacheConfig) (createDirectory : IO String)
    (body : Codec.ApalacheConfig → String → IO (Except String α)) :
    IO (Except String α) := do
  let specTracked ← IO.mkRef false
  try
    if res.provenance == .Owned then
      token.resourceEvent (.acquire .spec)
      specTracked.set true
    if ← token.isCancelled then return .error "job cancelled during resource acquisition"
    let dir ← createDirectory
    let directoryTracked ← IO.mkRef false
    try
      token.resourceEvent (.acquire .directory)
      directoryTracked.set true
      if ← token.isCancelled then return .error "job cancelled during resource acquisition"
      body cfg dir
    finally
      removeSessionDir dir
      if ← directoryTracked.get then token.resourceEvent (.release .directory)
  finally
    releaseSpec res
    if ← specTracked.get then token.resourceEvent (.release .spec)

private def withJobResources (token : Shell.Jobs.CancelToken)
    (cfg : Codec.ApalacheConfig) (spec : Option Codec.SpecConfig)
    (body : Codec.ApalacheConfig → String → IO (Except String Codec.ValidateResult)) :
    IO (Except String Codec.ValidateResult) := do
  if ← token.isCancelled then return .error "job cancelled before resource acquisition"
  match ← acquireSpec spec cfg with
  | .error e => return .error e
  | .ok (res, cfg') => withAcquiredJobScope token res cfg' freshSessionDir body

/-- Generate and decode a complete async trace result inside its owned scope.
The invocation seam permits file/codec failure regressions without a model
checker; production uses the cancellable Apalache invocation. -/
def generateJobTracesVia
    (generate : Option String → Codec.ApalacheConfig → Codec.TraceConfig →
      IO (Except String (String × List String)))
    (token : Shell.Jobs.CancelToken) (cfg : Codec.ApalacheConfig)
    (spec : Option Codec.SpecConfig) (tc : Codec.TraceConfig) :
    IO (Except String Codec.TraceGenResult) := do
  if ← token.isCancelled then return .error "job cancelled before resource acquisition"
  match ← acquireSpec spec cfg with
  | .error e => return .error e
  | .ok (res, cfg') =>
      withAcquiredJobScope token res cfg' freshSessionDir fun cfg' dir => do
        match ← generate (some dir) cfg' tc with
        | .error e => pure (.error e)
        | .ok (_, paths) => readGeneratedTraceResult paths

/-- The async-job runner backed by real apalache (validate) and by file
trace generation (gen-traces; returns the trace contents read back from
the generated files). -/
def jobRunner : Shell.Jobs.Runner where
  validate := fun cfg spec bound token =>
    withJobResources token cfg spec (fun cfg' dir =>
      validateSpecVia (runApalacheCancellable token) (some dir) cfg' bound)
  genTraces := fun cfg spec tc token =>
    generateJobTracesVia (generateTraceFilesVia (runApalacheCancellable token))
      token cfg spec tc

/-! ## The explorer flows (Haskell MkExploreMirror / MkExploreSession) -/

private def rpcFail (t : Shell.Transport.Transport) (err : RpcError)
    (kind : String) : IO Unit :=
  Shell.Mirror.sendMirror t
    (Codec.MirrorMessage.registerError s!"{kind}: {rpcErrorText err}")

private def stateVar (m : ValueMap) (k : String) : String :=
  match m.lookup k with
  | some (.vstr s) => s
  | _ => "explore"

private def convHintsCore : List DiffHint → List Codec.DiffHint :=
  fun hs => hs.map Shell.Mirror.convHint

/-- Check every backend-reported state invariant and, after a transition,
every action invariant. Unknown solver results cannot establish acceptance. -/
private def checkAutomaticInvariants (expl : Explorer) (afterTransition : Bool) :
    IO (RpcResult Bool) := do
  let checks := expl.params.stateInvariants.map (fun (id, _) => (id, InvariantKind.stateInvariant)) ++
    (if afterTransition then
      expl.params.actionInvariants.map (fun (id, _) => (id, InvariantKind.actionInvariant))
     else [])
  for (id, kind) in checks do
    match ← checkInvariant expl.client expl.sessionId id kind with
    | .error error => return .error error
    | .ok result =>
        match result.status with
        | .invViolated => return .ok true
        | .invSatisfied => pure ()
        | .invUnknown => return .error (.protocolError (-32000)
            s!"invariant {id} returned UNKNOWN")
  return .ok false

/-- Run automatic exploration through a selected RPC client. The production
wrapper owns the server; tests supply a scripted loopback peer. -/
partial def exploreFlowWithClient (t : Shell.Transport.Transport) (client : RpcClient)
    (sources : List String)
    (invs exports : List String) (maxSteps : Nat) : IO Unit := do
  match ← newExplorer client sources (some "Init") (some "Next") invs exports with
  | .error err => rpcFail t err "explore register"
  | .ok expl0 =>
    match ← exploreInit expl0 with
    | .error err =>
        Shell.Mirror.sendMirror t (Codec.MirrorMessage.protocolError
          (rpcErrorText err))
    | .ok expl1 =>
      Shell.Mirror.sendMirror t (Codec.MirrorMessage.specValidated .valid)
      exploreLoop t expl1 maxSteps 0
where
  exploreLoop (t : Shell.Transport.Transport) expl maxSteps stepIdx := do
    match ← exploreQueryState expl with
    | .error err =>
        Shell.Mirror.sendMirror t (Codec.MirrorMessage.protocolError
          (rpcErrorText err))
    | .ok expected =>
        let action := stateVar expected "action_taken"
        if stepIdx == 0 then
          Shell.Mirror.sendMirror t (Codec.MirrorMessage.initialState action expected)
        else
          Shell.Mirror.sendMirror t (Codec.MirrorMessage.nextStep action expected)
        let some line ← t.recv
          | Shell.Mirror.sendMirror t (Codec.MirrorMessage.protocolError "client closed")
        match Codec.StrictJson.parseString line with
        | .error _ =>
            Shell.Mirror.sendMirror t
              (Codec.MirrorMessage.protocolError Shell.Mirror.invalidClientMessageError)
        | .ok j =>
          match Codec.decodeClient j with
          | .error _ =>
              Shell.Mirror.sendMirror t
                (Codec.MirrorMessage.protocolError Shell.Mirror.invalidClientMessageError)
          | .ok (.reportState actual) =>
              match diffState expected actual with
              | .stateMismatch e a hints =>
                  Shell.Mirror.sendMirror t
                    (Codec.MirrorMessage.stepMismatch e a (convHintsCore hints))
              | .statesMatch =>
                  match ← exploreAssumeState expl actual with
                  | .error err =>
                      Shell.Mirror.sendMirror t (Codec.MirrorMessage.protocolError
                        (rpcErrorText err))
                  | .ok (expl', status) =>
                      if status != .transEnabled then
                        Shell.Mirror.sendMirror t (Codec.MirrorMessage.protocolError
                          s!"reported state assumption is {transitionStatusText status}")
                      else
                        match ← checkAutomaticInvariants expl' (stepIdx > 0) with
                        | .error err =>
                            Shell.Mirror.sendMirror t (Codec.MirrorMessage.protocolError
                              (rpcErrorText err))
                        | .ok true =>
                            Shell.Mirror.sendMirror t
                              (Codec.MirrorMessage.stepMismatch [] [] [])
                        | .ok false =>
                            Shell.Mirror.sendMirror t Codec.MirrorMessage.stepOk
                            if stepIdx + 1 >= maxSteps then
                              Shell.Mirror.sendMirror t Codec.MirrorMessage.allStepsDone
                            else
                              match expl'.params.nextTransitions.head? with
                              | none => Shell.Mirror.sendMirror t Codec.MirrorMessage.allStepsDone
                              | some (tid, _) =>
                                match ← exploreNext expl' tid with
                                | .error err =>
                                    Shell.Mirror.sendMirror t (Codec.MirrorMessage.protocolError
                                      (rpcErrorText err))
                                | .ok (_, .transDisabled) =>
                                    Shell.Mirror.sendMirror t Codec.MirrorMessage.allStepsDone
                                | .ok (_, .transUnknown) =>
                                    Shell.Mirror.sendMirror t (Codec.MirrorMessage.protocolError
                                      "next transition returned UNKNOWN")
                                | .ok (expl'', .transEnabled) =>
                                    exploreLoop t expl'' maxSteps (stepIdx + 1)
          | .ok _ =>
              Shell.Mirror.sendMirror t
                (Codec.MirrorMessage.protocolError "expected report_state")

/-- The interactive replay-like explore flow (Haskell @MkExploreMirror@). -/
def exploreFlow (t : Shell.Transport.Transport) (sources : List String)
    (invs exports : List String) (maxSteps : Nat) : IO Unit :=
  Shell.Apalache.Explorer.withApalacheServer fun server => do
    withRpcClient server.port fun client =>
      exploreFlowWithClient t client sources invs exports maxSteps

/-- Interactive explorer through a selected client; the caller owns its scope. -/
partial def exploreSessionFlowWithClient (t : Shell.Transport.Transport) (client : RpcClient)
    (sources : List String)
    (invs exports : List String) : IO Unit := do
  match ← newExplorer client sources (some "Init") (some "Next") invs exports with
  | .error err => rpcFail t err "explore register"
  | .ok expl0 =>
    let ps := expl0.params
    Shell.Mirror.sendMirror t (Codec.MirrorMessage.explorerReady
      ps.initTransitions.length ps.nextTransitions.length ps.stateInvariants.length)
    sessionLoop t expl0
where
  sessionLoop (t : Shell.Transport.Transport) expl := do
    let some line ← t.recv
      | Shell.Mirror.sendMirror t (Codec.MirrorMessage.protocolError "client closed")
    match Codec.StrictJson.parseString line with
    | .error _ =>
        Shell.Mirror.sendMirror t
          (Codec.MirrorMessage.protocolError Shell.Mirror.invalidClientMessageError)
    | .ok j =>
      match Codec.decodeClient j with
      | .error _ =>
          Shell.Mirror.sendMirror t
            (Codec.MirrorMessage.protocolError Shell.Mirror.invalidClientMessageError)
      | .ok m =>
        let replyFail (err : RpcError) := do
          Shell.Mirror.sendMirror t (Codec.MirrorMessage.protocolError
            (rpcErrorText err))
          sessionLoop t expl
        match m with
        | .exploreDone =>
            let _ ← exploreDispose expl
            Shell.Mirror.sendMirror t Codec.MirrorMessage.exploreSessionDone
        | .exploreAssumeTransition tid =>
            match ← assumeTransition expl.client
                { sessionId := expl.sessionId, transitionId := tid,
                  checkEnabled := true, timeoutSec := none } with
            | .error err => replyFail err
            | .ok atr =>
                Shell.Mirror.sendMirror t (Codec.MirrorMessage.exploreTransitionStatus
                  (transitionStatusText atr.status))
                sessionLoop t { expl with snapshot := atr.snapshotId }
        | .exploreNextStep =>
            match ← nextStep expl.client expl.sessionId with
            | .error err => replyFail err
            | .ok nsr =>
                Shell.Mirror.sendMirror t (Codec.MirrorMessage.exploreStepDone
                  nsr.newStepNo)
                sessionLoop t { expl with snapshot := nsr.snapshotId }
        | .exploreQueryState =>
            match ← exploreQueryState expl with
            | .error err => replyFail err
            | .ok st =>
                Shell.Mirror.sendMirror t (Codec.MirrorMessage.exploreState st)
                sessionLoop t expl
        | .exploreCheckInvariant iid =>
            match ← exploreCheck expl iid with
            | .error err => replyFail err
            | .ok (st, _) =>
                Shell.Mirror.sendMirror t (Codec.MirrorMessage.exploreInvariantStatus
                  (invariantStatusText st))
                sessionLoop t expl
        | .exploreAssumeState eqs =>
            match ← exploreAssumeState expl eqs with
            | .error err => replyFail err
            | .ok (expl', st) =>
                Shell.Mirror.sendMirror t (Codec.MirrorMessage.exploreAssumeStatus
                  (transitionStatusText st))
                sessionLoop t expl'
        | .exploreRollback snap =>
            match ← exploreRollback expl snap with
            | .error err => replyFail err
            | .ok expl' =>
                Shell.Mirror.sendMirror t (Codec.MirrorMessage.exploreRollbackDone snap)
                sessionLoop t expl'
        | _ =>
            Shell.Mirror.sendMirror t
              (Codec.MirrorMessage.protocolError
                "unexpected message in explore session")

/-- The interactive explorer session flow (Haskell @MkExploreSession@). -/
def exploreSessionFlow (t : Shell.Transport.Transport) (sources : List String)
    (invs exports : List String) : IO Unit :=
  Shell.Apalache.Explorer.withApalacheServer fun server =>
    withRpcClient server.port fun client =>
      exploreSessionFlowWithClient t client sources invs exports

/-! ## Trace generation with source identity -/

/-- Generate the trace bundle used by a synchronous registration. For a
negotiated borrowed spec, the source closure is captured into a mirror-owned
snapshot before the injected Apalache boundary runs. The returned source
manifest is derived from exactly that capture.

If capture is unavailable, trace generation retains the legacy borrowed path
but returns no source manifest. This preserves `prefer` fallback behavior while
ensuring that a descriptor is never built from bytes different from those
Apalache was asked to execute. -/
def generateSyncTraceBundleVia
    (generateBundle : Option String → Codec.ApalacheConfig →
      Codec.TraceConfig → Bool → Bool →
        IO (Except String Shell.Mirror.TraceBundle))
    (cfg : Codec.ApalacheConfig) (spec : Option Codec.SpecConfig)
    (tc : Codec.TraceConfig) (preserveInterfaceEvidence : Bool)
    (allowResourceFallback : Bool) :
    IO (Except String Shell.Mirror.TraceBundle) := do
  let acquisition : Except String
      (SpecRes × Codec.ApalacheConfig ×
        List Core.ModelInterface.SourceDigest) ←
    if preserveInterfaceEvidence then
      match spec with
      | none =>
          match ← acquireBorrowedSpecSnapshot cfg with
          | .ok snapshot => pure (.ok snapshot)
          | .error _ =>
              -- No source manifest may accompany this fallback: the borrowed
              -- files can still change before the process opens them.
              match ← acquireSpec none cfg with
              | .error error => pure (.error error)
              | .ok (resource, acquiredCfg) =>
                  pure (.ok (resource, acquiredCfg, []))
      | some inline =>
          match ← acquireSpec (some inline) cfg with
          | .error error => pure (.error error)
          | .ok (resource, acquiredCfg) =>
              let sources := (inlineSourceDigests inline).toOption.getD []
              pure (.ok (resource, acquiredCfg, sources))
    else
      match ← acquireSpec spec cfg with
      | .error error => pure (.error error)
      | .ok (resource, acquiredCfg) =>
          pure (.ok (resource, acquiredCfg, []))
  match acquisition with
  | .error error => return .error error
  | .ok (resource, acquiredCfg, sources) =>
      let dir ← freshSessionDir
      let result ← try
          generateBundle (some dir) acquiredCfg tc preserveInterfaceEvidence
            allowResourceFallback
        finally
          releaseSpec resource
          removeSessionDir dir
      return result.map fun bundle => { bundle with sources := sources }

/-- The sync-session oracles backed by real apalache: validation, trace
generation, trace-file production, and the two explorer flows (t14). -/
def syncOracles : Shell.Mirror.Oracles where
  validateSpec := fun cfg spec _bound => do
    match ← acquireSpec spec cfg with
    | .error e => return .error e
    | .ok (res, cfg') =>
        -- t29: validate in a FRESH session dir like the trace paths —
        -- passing none ran apalache with the mirror's cwd and littered
        -- _apalache-out/<spec>/ + tmp/ into the repo root
        let dir ← freshSessionDir
        let r ← try validateSpecIn (some dir) cfg' _bound
          finally (do releaseSpec res; removeSessionDir dir)
        return r
  generateTraces := generateSyncTraceBundleVia
    (fun runDir cfg tc preserve allowFallback =>
      generateTraceBundleIn runDir cfg tc preserve allowFallback)
  generateTraceFiles := fun cfg spec dest tc => do
    match ← acquireSpec spec cfg with
    | .error e => return .error e
    | .ok (res, cfg') =>
        let dir ← freshSessionDir
        -- Port of MkRunMirrorGenTraces: generate into the session dir,
        -- optionally copy into the client's destPath (creating it), then
        -- read the *final* paths for inlining — all before the session
        -- dir is removed (reading after cleanup would hit ENOENT).
        let delivery ← withTraceGenerationCleanup (do
          match ← generateTraceFilesIn (some dir) cfg' tc with
          | .error error => return .error error
          | .ok (outDir, paths) =>
              prepareGeneratedTraceDelivery dir outDir paths dest)
          (releaseSpec res) (removeSessionDir dir)
        return delivery
  runExplore := fun t spec invs exports maxSteps =>
    exploreFlow t spec.sources invs exports maxSteps
  runExploreSession := fun t spec invs exports =>
    exploreSessionFlow t spec.sources invs exports

end Shell.Apalache
