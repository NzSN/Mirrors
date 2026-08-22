import Shell.Apalache.Cli
import Shell.Apalache.SpecSource
import Shell.Mirror.Session
import Shell.Jobs.Store
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

open Shell.Apalache.Cli Shell.Apalache.SpecSource

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
        let r ← try
          generateTraceFilesIn (some dir) cfg' tc
        finally
          releaseSpec res
          removeSessionDir dir
        match r with
        | .error e => return .error e
        | .ok (_, paths) =>
            -- read the generated files back as raw ITF values (parity:
            -- the client receives the file contents)
            let contents ← paths.mapM (fun (p : String) => do
              let txt ← IO.FS.readFile p
              match Lean.Json.parse txt with
              | .error _ => pure none
              | .ok j => pure ((Codec.decodeValue j).toOption))
            return .ok { itfTracePaths := paths,
                         itfTraces := contents.filterMap id }

/-- The sync-session oracles backed by real apalache: validation, trace
generation, and trace-file production run with per-flow session dirs;
the explorer flows remain Phase-5 stubs (t14). -/
def syncOracles : Shell.Mirror.Oracles where
  validateSpec := fun cfg spec _bound => do
    match ← acquireSpec spec cfg with
    | .error e => return .error e
    | .ok (res, cfg') =>
        let r ← try validateSpecIn none cfg' _bound
          finally releaseSpec res
        return r
  generateTraces := fun cfg spec tc => do
    match ← acquireSpec spec cfg with
    | .error e => return .error e
    | .ok (res, cfg') =>
        let dir ← freshSessionDir
        let r ← try generateTracesIn (some dir) cfg' tc
          finally (do releaseSpec res; removeSessionDir dir)
        return r
  generateTraceFiles := fun cfg spec tc => do
    match ← acquireSpec spec cfg with
    | .error e => return .error e
    | .ok (res, cfg') =>
        let dir ← freshSessionDir
        let r ← try generateTraceFilesIn (some dir) cfg' tc
          finally (do releaseSpec res; removeSessionDir dir)
        match r with
        | .error e => return .error e
        | .ok (_, paths) =>
            let contents ← paths.mapM (fun (p : String) => do
              let txt ← IO.FS.readFile p
              match Lean.Json.parse txt with
              | .error _ => pure none
              | .ok j => pure ((Codec.decodeValue j).toOption))
            return .ok ({ itfTracePaths := paths,
                           itfTraces := contents.filterMap id } : Codec.TraceGenResult)
  runExplore t _ _ _ _ :=
    Shell.Mirror.sendMirror t (Codec.MirrorMessage.registerError
      "apalache explorer adapter lands in Phase 5 (t14)")
  runExploreSession t _ _ _ := do
    Shell.Mirror.sendMirror t (Codec.MirrorMessage.registerError
      "apalache explorer adapter lands in Phase 5 (t14)")

end Shell.Apalache