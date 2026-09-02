import Shell.Apalache.Cli
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

/-- Run one job body with the standard per-job scaffolding: acquire the
spec (release on cancel), create the session dir (removal on cancel),
absolutize nothing here (the Cli layer does), then clean up on the way
out. -/
private def withJobResources (token : Shell.Jobs.CancelToken)
    (cfg : Codec.ApalacheConfig) (spec : Option Codec.SpecConfig)
    (body : Codec.ApalacheConfig → String →
      IO (Except String Codec.ValidateResult)) :
    IO (Except String Codec.ValidateResult) := do
  match ← acquireSpec spec cfg with
  | .error e => return .error e
  | .ok (res, cfg') =>
      let dir ← freshSessionDir
      token.onCancel do
        releaseSpec res
        removeSessionDir dir
      let r ← try body cfg' dir
        finally
          releaseSpec res
          removeSessionDir dir
      return r

/-- The async-job runner backed by real apalache (validate) and by file
trace generation (gen-traces; returns the trace contents read back from
the generated files). -/
def jobRunner : Shell.Jobs.Runner where
  validate := fun cfg spec bound token =>
    withJobResources token cfg spec (fun cfg' dir =>
      validateSpecVia (runApalacheCancellable token) (some dir) cfg' bound)
  genTraces := fun cfg spec tc token => do
    match ← acquireSpec spec cfg with
    | .error e => return .error e
    | .ok (res, cfg') =>
        let dir ← freshSessionDir
        token.onCancel do
          releaseSpec res
          removeSessionDir dir
        -- t31: the file read-back must happen INSIDE the try, before the
        -- finally removes the session dir (reading after the finally
        -- raced the directory deletion and crashed the job body)
        -- t4: cancellable spawn (generateTraceFilesVia + the cancellable
        -- runner) so a cancelled trace-gen terminates the apalache child
        -- (Kill wiring identical to the validate path).
        let r ← try
          match ← generateTraceFilesVia (runApalacheCancellable token) (some dir) cfg' tc with
          | .error e => pure (.error e)
          | .ok (_, paths) =>
              -- read the generated files back as raw ITF values (parity:
              -- the client receives the file contents)
              do
                let contents ← paths.mapM (fun (p : String) => do
                  let txt ← IO.FS.readFile p
                  match Lean.Json.parse txt with
                  | .error _ => pure none
                  | .ok j => pure ((Codec.decodeValue j).toOption))
                pure (.ok (⟨paths, contents.filterMap id⟩ :
                  Codec.TraceGenResult))
        finally
          releaseSpec res
          removeSessionDir dir
        return r

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

/-- The interactive replay-like explore flow (Haskell @MkExploreMirror@). -/
partial def exploreFlow (t : Shell.Transport.Transport) (sources : List String)
    (invs exports : List String) (maxSteps : Nat) : IO Unit := do
  Shell.Apalache.Explorer.withApalacheServer fun server => do
    let client ← newRpcClient server.port
    match ← newExplorer client sources (some "Init") (some "Next") invs exports with
    | .error err => rpcFail t err "explore register"
    | .ok expl0 =>
      match ← exploreInit expl0 with
      | .error err =>
          Shell.Mirror.sendMirror t (Codec.MirrorMessage.protocolError
            (rpcErrorText err))
      | .ok expl1 =>
        Shell.Mirror.sendMirror t (Codec.MirrorMessage.specValidated .valid)
        exploreLoop t expl1 invs maxSteps 0
where
  exploreLoop (t : Shell.Transport.Transport) expl invs maxSteps stepIdx := do
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
        match Lean.Json.parse line with
        | .error e =>
            Shell.Mirror.sendMirror t (Codec.MirrorMessage.protocolError e)
        | .ok j =>
          match Codec.decodeClient j with
          | .error e =>
              Shell.Mirror.sendMirror t (Codec.MirrorMessage.protocolError e.msg)
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
                  | .ok (expl', _) =>
                      Shell.Mirror.sendMirror t Codec.MirrorMessage.stepOk
                      let violated ←
                        if invs.isEmpty then pure false
                        else match ← exploreCheck expl' 0 with
                          | .ok (.invViolated, _) => pure true
                          | _ => pure false
                      if violated then
                        Shell.Mirror.sendMirror t
                          (Codec.MirrorMessage.stepMismatch [] [] [])
                      else if stepIdx + 1 >= maxSteps then
                        Shell.Mirror.sendMirror t Codec.MirrorMessage.allStepsDone
                      else
                        match ← exploreNext expl' 0 with
                        | .error err =>
                            Shell.Mirror.sendMirror t (Codec.MirrorMessage.protocolError
                              (rpcErrorText err))
                        | .ok (_, .transDisabled) =>
                            Shell.Mirror.sendMirror t Codec.MirrorMessage.allStepsDone
                        | .ok (expl'', _) =>
                            exploreLoop t expl'' invs maxSteps (stepIdx + 1)
          | .ok _ =>
              Shell.Mirror.sendMirror t
                (Codec.MirrorMessage.protocolError "expected report_state")

/-- The interactive explorer session flow (Haskell @MkExploreSession@). -/
partial def exploreSessionFlow (t : Shell.Transport.Transport) (sources : List String)
    (invs exports : List String) : IO Unit := do
  Shell.Apalache.Explorer.withApalacheServer fun server => do
    let client ← newRpcClient server.port
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
    match Lean.Json.parse line with
    | .error e =>
        Shell.Mirror.sendMirror t (Codec.MirrorMessage.protocolError e)
    | .ok j =>
      match Codec.decodeClient j with
      | .error e =>
          Shell.Mirror.sendMirror t (Codec.MirrorMessage.protocolError e.msg)
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
        let finalPaths? ←
          try
            let r ← generateTraceFilesIn (some dir) cfg' tc
            match r with
            | .error _ => pure (none : Option (List String))
            | .ok (outDir, paths) =>
                match dest with
                | some d =>
                    if d != "" && d != outDir then
                      IO.FS.createDirAll d
                      let finals ← paths.mapM (fun (p : String) => do
                        let fname := (p : System.FilePath).fileName.getD p
                        let target := ((d : System.FilePath) / fname).toString
                        let txt ← IO.FS.readFile p
                        IO.FS.writeFile target txt
                        pure target)
                      pure (some finals)
                    else pure (some paths)
                | none => pure (some paths)
          finally (do releaseSpec res; removeSessionDir dir)
        match finalPaths? with
        | none => return .error "trace generation failed"
        | some paths =>
            let contents ← paths.mapM (fun (p : String) => do
              let txt ← IO.FS.readFile p
              match Lean.Json.parse txt with
              | .error _ => pure none
              | .ok j => pure ((Codec.decodeValue j).toOption))
            return .ok ({ itfTracePaths := paths,
                           itfTraces := contents.filterMap id } : Codec.TraceGenResult)
  runExplore := fun t spec invs exports maxSteps =>
    exploreFlow t spec.sources invs exports maxSteps
  runExploreSession := fun t spec invs exports =>
    exploreSessionFlow t spec.sources invs exports

end Shell.Apalache
