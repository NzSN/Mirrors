import Shell.Apalache.SpecSource
import Shell.Mirror.Session
import Core.Trace
import Shell.Jobs.Store
import Codec.Json
import Lean

/-!
# Shell.Apalache.Cli — the apalache-mc CLI adapter (Layer 3, design 5.4)

Port of the Haskell @Apalache.Command@:

* @apalacheBin@ honors the @APALACHE_MC@ override, else @apalache-mc@
  on @PATH@; every child is spawned with @LC_ALL=C.UTF-8@ (the apalache
  JVM requirement carried over from the Haskell build).
* **cwd isolation (doc 9.5):** apalache 0.57 writes
  @_apalache-out/<Spec>/<timestamp>/@ and @tmp/@ into the process CWD
  even with @--run-dir@; when a run dir is supplied, the child also runs
  with @cwd = runDir@ and a relative @specPath@ is absolutized first,
  so all stray output lands inside the per-session temp dir.
* Exit-code classification (verified against apalache 0.57, as in the
  Haskell code): 255 (parse/config/infra) → infra error
  (@.error@ / register-error tier); typecheck failure (120) or invariant
  violation (12) → @.ok (.invalid msg)@ (client's verdict); 0 → valid.
* @runApalacheCancellable@ is the @spawnApalache@ port for the async job
  model: the child handle is registered on the job's @CancelToken@
  (@CancelToken.onCancel child.kill@), closing the cancellation
  kill-window; a late result is discarded by the job store's absorbing
  transition.
-/

namespace Shell.Apalache.Cli

/-- The full outcome of one apalache invocation (Haskell @ApalacheResult@). -/
structure ApalacheResult where
  exit : UInt32
  out : String
  err : String
deriving Repr

/-- Resolve the apalache binary (Haskell @apalacheBin@). -/
def apalacheBin : IO String := do
  match ← IO.getEnv "APALACHE_MC" with
  | some p => pure p
  | none => pure "apalache-mc"

/-- The apalache JVM locale requirement (unchanged from Haskell). -/
private def apalacheEnv : Array (String × Option String) :=
  #[("LC_ALL", some "C.UTF-8")]

/-- Drain one pipe to EOF (shared by both apalache flows). -/
private def drainToEnd (h : IO.FS.Handle) : IO String := do
  let mut s := ""
  let mut line ← h.getLine
  while !line.isEmpty do
    s := s ++ line
    line ← h.getLine
  return s

/-- Spawn apalache with stdin EOF and NO inheritable handle leak
(Defect D root cause, analyzer t2): @IO.Process.output@ and
@stdin := .null@ leak exactly +1 handle per spawn on Windows
(src/runtime/process.cpp setup_stdio NUL case). Spawning
@stdin := .piped@ and immediately @takeStdin@ + dropping the write end
gives the child stdin EOF without creating the NUL handle — 0 leak,
analyzer-measured. The returned child's config has stdin already taken
(@Stdio.null@), stdout/stderr still piped for drain, kill still works. -/
private def spawnApalacheEof (args : Array String) (runDir : Option String) :
    IO (IO.Process.Child { stdin := .null, stdout := .piped, stderr := .piped }) := do
  let child0 ← IO.Process.spawn
    { cmd := ← apalacheBin, args := args,
      env := apalacheEnv, stdin := .piped,
      stdout := .piped, stderr := .piped,
      cwd := runDir }
  let (wh, child) ← child0.takeStdin
  let _ := wh -- drop the write end: child sees stdin EOF, no leak
  return child

/-- The concrete child shape both apalache flows use after the
takeStdin workaround: stdin taken (null), stdout+stderr piped. -/
private abbrev ApalacheChild :=
  IO.Process.Child ({ stdin := .null, stdout := .piped, stderr := .piped } : IO.Process.StdioConfig)

/-- Drain stdout+stderr concurrently and wait for the child (shared by
both apalache flows; stderr drains in a task so a full pipe cannot
deadlock the stdout drain). -/
private def collectApalache (child : ApalacheChild) : IO ApalacheResult := do
  let errTask ← IO.asTask do
    drainToEnd (child.stderr : IO.FS.Handle)
  let out ← drainToEnd (child.stdout : IO.FS.Handle)
  let errResult : Except IO.Error String := errTask.get
  let err ← match errResult with
    | .ok s => pure s
    | .error e => pure s!"stderr drain failed: {e}"
  let code ← child.wait
  return ⟨code, out, err⟩

/-- Run one apalache invocation to completion (the
@readCreateProcessWithExitCode@ port): child @cwd = runDir@ when given,
@LC_ALL=C.UTF-8@, stdin EOF via the takeStdin workaround (NOT
@IO.Process.output@ — that forces @stdin := .null@ on Windows and leaks
+1 inheritable handle per spawn, the Defect D accumulation). -/
def runApalache (runDir : Option String) (args : List String) :
    IO ApalacheResult := do
  let child ← spawnApalacheEof args.toArray runDir
  collectApalache child

/-- Run one apalache invocation, cancellable (Haskell @spawnApalache@ +
the async-job kill wiring): the process handle is registered on the
token so job cancellation (or session close) terminates the child.
stdin goes through the same takeStdin EOF workaround as @runApalache@.
-/
private def killIgnoring {cfg : IO.Process.StdioConfig} (child : IO.Process.Child cfg) : IO Unit := do
  try child.kill catch _ => pure ()

def runApalacheCancellable (token : Shell.Jobs.CancelToken)
    (runDir : Option String) (args : List String) : IO ApalacheResult := do
  let child ← spawnApalacheEof args.toArray runDir
  token.onCancel (killIgnoring child)
  let r ← collectApalache child
  -- FFI-hardening/t4 (secondary retention, analyzer t2): the token's
  -- kill-closure pins the Child (hProcess + 2 pipe externals) in the
  -- job table until session close, ~3 handles/job. The child has
  -- EXITED here (wait happened inside collectApalache), so the
  -- kill-closure is dead weight — drop it so the Child becomes
  -- collectable and the handles are closed immediately (FLAT handle
  -- trend under the 300-cycle stress). Cancellation racing this point
  -- runs the old closure harmlessly (kill of an exited child).
  token.onCancel (pure ())
  return r

/-- Absolutize a (possibly relative) path against the current dir
(Haskell @makeAbsolute@): the child's cwd moves to the run dir, so a
relative spec path would no longer resolve. -/
def makeAbsolute (path : String) : IO String := do
  if (path : System.FilePath).isAbsolute then
    pure path
  else
    let cwd ← IO.currentDir
    pure (cwd.toString ++ "/" ++ path)

/-! ## Argument construction -/

private def optionalArg (pfx : String) (v : Option String) : List String :=
  match v with
  | none => []
  | some v => [pfx ++ v]

private def nonEmpty (s : String) : Option String :=
  if s.isEmpty then none else some s

/-- @typecheck@ argument list (Haskell @tcArgs@). -/
def tcArgs (runDir : Option String) (cfg : Codec.ApalacheConfig) : List String :=
  ["typecheck"] ++ optionalArg "--run-dir=" runDir ++ [cfg.specPath]

/-- @check@ argument list for validation (Haskell @checkArgs@). -/
def checkArgs (runDir : Option String) (cfg : Codec.ApalacheConfig)
    (bound : Nat) : List String :=
  ["check", s!"--length={bound}"]
    ++ optionalArg "--run-dir=" runDir
    ++ optionalArg "--inv=" (nonEmpty cfg.invariant)
    ++ optionalArg "--init=" cfg.initPredicate
    ++ optionalArg "--next=" cfg.nextPredicate
    ++ optionalArg "--cinit=" cfg.constInit
    ++ [cfg.specPath]

/-- @check@ argument list for trace generation (Haskell @traceArgs@):
@--inv@ is gated on a non-empty invariant exactly like @checkArgs@ — an
unconditional empty @--inv=@ is an apalache config error (exit 255). -/
def traceArgs (runDir : Option String) (cfg : Codec.ApalacheConfig)
    (tc : Codec.TraceConfig) : List String :=
  ["check"] ++ optionalArg "--inv=" (nonEmpty cfg.invariant)
    ++ [s!"--length={cfg.lengthBound}", s!"--max-error={tc.numTraces}",
        "--output-traces"]
    ++ optionalArg "--run-dir=" runDir
    ++ optionalArg "--init=" cfg.initPredicate
    ++ optionalArg "--next=" cfg.nextPredicate
    ++ optionalArg "--cinit=" cfg.constInit
    ++ optionalArg "--view=" tc.view
    ++ [cfg.specPath]

/-- Extract the @Output directory: <dir>@ line from apalache output
(Haskell @parseOutputDir@). t30: apalache on Windows emits CRLF line
endings, so a trailing carriage return is stripped — otherwise the
parsed path does not exist and trace discovery fails with a confusing
ENOENT. -/
def parseOutputDir (s : String) : Option String :=
  let rec go : List String → Option String
    | [] => none
    | l :: ls =>
        let l := l.dropRightWhile (fun c => c == '\r' || c == ' ')
        match l.splitOn ": " with
        | ["Output directory", rest] => some rest
        | _ => go ls
  go (s.splitOn "\n")

/-- The apalache exit-code tier: 255 is infra (@true@ = error tier),
anything else is a spec verdict (Haskell's case split, shared shape). -/
def isInfraExit (code : UInt32) : Bool := code == 255

/-! ## Silent-child / undocumented-exit classification (Defect D) -/

/-- apalache's documented spec-verdict exit codes (120 = typecheck
failure, 12 = invariant violation). Any other nonzero code — besides
the 255 infra tier — means the child did not produce a verdict at all,
so the spec-verdict tier must not fire. -/
def isSpecVerdictExit (code : UInt32) : Bool := code == 120 || code == 12

/-- A child that exits nonzero with EMPTY stdout+stderr (all streams
drained to EOF, nothing captured) is an infra failure: the run never
produced a verdict, so reporting .invalid "" would lie to the client
that the spec is invalid. Checked BEFORE the exit tier so the 255 /
empty-output corner also gets a real message. -/
def noOutputError (r : ApalacheResult) : Option String :=
  if r.exit != 0 && (r.out ++ r.err).isEmpty then
    some s!"apalache produced no output (exit {r.exit})"
  else
    none

/-! ## The three flows -/

/-- Bounded validation (Haskell @validateSpecIn@): typecheck then check,
both with @cwd = runDir@; 255 → infra error, other nonzero → spec
verdict, 0 → valid. Runs over an injected invocation for the async job
(@validateSpecVia@). -/
def validateSpecVia (run : Option String → List String → IO ApalacheResult)
    (runDir : Option String) (cfg : Codec.ApalacheConfig) (bound : Nat) :
    IO (Except String Codec.ValidateResult) := do
  let cfg' ← match runDir with
    | some _ => pure ({ cfg with specPath := ← makeAbsolute cfg.specPath } : Codec.ApalacheConfig)
    | none => pure cfg
  let tc ← run runDir (tcArgs runDir cfg')
  if let some e := noOutputError tc then
    return .error e
  else if isInfraExit tc.exit then
    return .error (tc.out ++ tc.err)
  else if tc.exit != 0 && !isSpecVerdictExit tc.exit then
    -- undocumented nonzero exit: the child did not run apalache to a
    -- verdict (wrapper/launcher failure) — infra tier, never a verdict
    return .error (tc.out ++ tc.err)
  else if tc.exit != 0 then
    return .ok (.invalid (tc.out ++ tc.err))
  else
    let c ← run runDir (checkArgs runDir cfg' bound)
    if let some e := noOutputError c then
      return .error e
    else if isInfraExit c.exit then
      return .error (c.out ++ c.err)
    else if c.exit != 0 && !isSpecVerdictExit c.exit then
      return .error (c.out ++ c.err)
    else if c.exit == 0 then
      return .ok .valid
    else
      return .ok (.invalid (c.out ++ c.err))

/-- Direct validation (Haskell @validateSpec@/@validateSpecIn@). -/
def validateSpecIn (runDir : Option String) (cfg : Codec.ApalacheConfig)
    (bound : Nat) : IO (Except String Codec.ValidateResult) :=
  validateSpecVia runApalache runDir cfg bound

/-- All @*.itf.json@ files in a directory, non-recursive (Haskell
@findTraceFiles@). -/
def findTraceFiles (dir : String) : IO (List String) := do
  let entries ← (dir : System.FilePath).readDir
  return (entries.toList.map (·.path.toString)).filter (·.endsWith ".itf.json")

/-- Trace generation producing trace files (Haskell
@generateTraceFilesIn@): returns the output dir and the ITF paths in it.
Runs over an injected invocation so the async job can use the
cancellable spawn (Haskell @generateTraceFilesVia@). -/
def generateTraceFilesVia (run : Option String → List String → IO ApalacheResult)
    (runDir : Option String) (cfg : Codec.ApalacheConfig)
    (tc : Codec.TraceConfig) : IO (Except String (String × List String)) := do
  let cfg' ← match runDir with
    | some _ => pure ({ cfg with specPath := ← makeAbsolute cfg.specPath } : Codec.ApalacheConfig)
    | none => pure cfg
  let r ← run runDir (traceArgs runDir cfg' tc)
  if let some e := noOutputError r then
    return .error e
  else if isInfraExit r.exit then
    return .error (r.out ++ r.err)
  else
    match parseOutputDir (r.out ++ r.err) with
    | none => return .error "Could not determine output directory from Apalache output"
    | some outDir =>
        let paths ← findTraceFiles outDir
        return .ok (outDir, paths)

/-- Direct trace-file generation (Haskell @generateTraceFilesIn@): the
sync @syncOracles@ path runs apalache uncancellable; the async job
(@Runner.jobRunner@) uses the cancellable @generateTraceFilesVia@ so a
cancelled trace-gen terminates the child. -/
def generateTraceFilesIn (runDir : Option String) (cfg : Codec.ApalacheConfig)
    (tc : Codec.TraceConfig) : IO (Except String (String × List String)) :=
  generateTraceFilesVia runApalache runDir cfg tc

/-- Trace generation producing replay traces plus raw typed evidence over an
injected trace-file generator. The injection is the Apalache process boundary;
disk discovery and ITF parsing remain the real production path. -/
def generateTraceBundleVia
    (generateFiles : Option String → Codec.ApalacheConfig → Codec.TraceConfig →
      IO (Except String (String × List String)))
    (runDir : Option String) (cfg : Codec.ApalacheConfig)
    (tc : Codec.TraceConfig) (preserveEvidence : Bool := true)
    (allowResourceFallback : Bool := false)
    (limits : Shell.Mirror.NegotiatedTraceLoadLimits :=
      Shell.Mirror.negotiatedTraceLoadLimitsV1) :
    IO (Except String Shell.Mirror.TraceBundle) := do
  let r ← generateFiles runDir cfg tc
  match r with
  | .error e => return .error e
  | .ok (_, paths) =>
      let legacyBundle : IO (Except String Shell.Mirror.TraceBundle) := do
        let mut traces := []
        for path in paths do
          match ← Shell.Mirror.readItfTrace path with
          | .error _ => return .error "generated ITF trace failed parsing"
          | .ok trace => traces := traces ++ [trace]
        return .ok { traces }
      let bundle ← if preserveEvidence then
          match ← Shell.Mirror.loadTraceBundleWithLimitsClassified paths limits with
          | .ok bundle => pure bundle
          | .error (.invalidInput _) =>
              return .error "generated ITF trace failed strict parsing"
          | .error (.resourceLimit _) =>
              -- The files already exist, so optional negotiation can retain
              -- legacy replay without launching Apalache a second time. No
              -- evidence crosses this fallback: `prefer` becomes unavailable,
              -- while `require` remains terminal in the session policy.
              if allowResourceFallback then
                match ← legacyBundle with
                | .ok bundle => pure bundle
                | .error error => return .error error
              else
                return .error "generated ITF trace exceeded negotiated resource limits"
        else
          match ← legacyBundle with
          | .ok bundle => pure bundle
          | .error error => return .error error
      let pvs := if cfg.paramVars.isEmpty then [] else [cfg.paramVars]
      let traced := bundle.traces.map (applyParamVars pvs)
      if traced.isEmpty then
        return .error "No ITF trace files found in output directory"
      else
        return .ok { bundle with traces := traced }

/-- Direct trace generation producing replay traces plus raw typed evidence. -/
def generateTraceBundleIn (runDir : Option String) (cfg : Codec.ApalacheConfig)
    (tc : Codec.TraceConfig) (preserveEvidence : Bool := true)
    (allowResourceFallback : Bool := false) :
    IO (Except String Shell.Mirror.TraceBundle) :=
  generateTraceBundleVia generateTraceFilesIn runDir cfg tc preserveEvidence
    allowResourceFallback

/-- Legacy list-only wrapper retained for focused callers/tests. -/
def generateTracesIn (runDir : Option String) (cfg : Codec.ApalacheConfig)
    (tc : Codec.TraceConfig) : IO (Except String (List ItfTrace)) := do
  return (← generateTraceBundleIn runDir cfg tc false).map (·.traces)

end Shell.Apalache.Cli
