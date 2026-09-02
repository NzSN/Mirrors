import Shell.Apalache.Cli
import Shell.Apalache.SpecSource
import Shell.Apalache.Runner
import Shell.Mirror.Session
import Codec.Json
import Codec.StrictJson
import Lean

/-!
# Phase 5 regression suite (tools/ApalacheCliSpec.lean)

Behavior tests (doc 9.5), not proofs, for the apalache CLI adapter:

* Spec materialization: MODULE-header parsing, per-source @.tla@ files,
  duplicate/no-source errors, Owned/Borrowed acquisition and release.
* Argument construction and output-dir parsing (pure, no apalache).
* cwd isolation: with a run dir, apalache's stray @_apalache-out@/@tmp@
  land inside the run dir, never in the mirror's cwd.
* Cancellable spawn: job cancellation terminates the child promptly.
* Validate/trace-gen classification against real apalache 0.57 (runs
  only when @APALACHE_MC@ is set; otherwise the integration part
  self-skips and the unit part must still pass).
-/

open Shell.Apalache.Cli Shell.Apalache.SpecSource

abbrev Failures := IO.Ref (List String)

def isErrOf {α : Type} (e : Except String α) : Bool :=
  match e with
  | .error _ => true
  | .ok _ => false

def prefixOf (p s : String) : Bool :=
  p.toList.length <= s.toList.length
    && (p.toList.zip s.toList).all (fun (a, b) => a == b)

def check (fails : Failures) (name : String) (ok : Bool) (detail : String := "") : IO Unit := do
  if !ok then
    if detail.isEmpty then fails.modify (fun fs => fs ++ [name])
    else fails.modify (fun fs => fs ++ [s!"{name}: {detail}"])

def hcSrc : String :=
  "---------------- MODULE HourClock ---------------------\n" ++
  "EXTENDS Naturals\n" ++
  "VARIABLE hr\n" ++
  "HCinit == hr = 1\n" ++
  "HCnext == hr' = IF hr # 12 THEN hr + 1 ELSE 1\n" ++
  "Inv == hr >= 1 /\\ hr <= 12\n" ++
  "=======================================\n"

def largeItfTraceJson : String :=
  "{" ++
  "\"vars\":[\"action_taken\",\"payload\"]," ++
  "\"states\":[{" ++
    "\"action_taken\":\"init\"," ++
    "\"payload\":\"" ++ String.ofList (List.replicate 70000 'x') ++ "\"" ++
  "}]}"

def smallItfTraceJson : String :=
  "{" ++
  "\"vars\":[\"action_taken\",\"count\"]," ++
  "\"states\":[{\"action_taken\":\"init\",\"count\":0}]" ++
  "}"

/-! ## Unit: MODULE header + materialization -/

def unitModuleName (fails : Failures) : IO Unit := do
  match moduleName hcSrc with
  | .ok n => check fails "moduleName: ok" (n == "HourClock") n
  | .error e => check fails "moduleName: ok" false e
  match moduleName "EXTENDS Naturals" with
  | .error e =>
      check fails "moduleName: no header"
        (e == "no MODULE header found in spec source") e
  | .ok n => check fails "moduleName: no header" false n
  check fails "moduleName: missing name" (isErrOf (moduleName "---- MODULE ----\n"))
  check fails "moduleName: bad keyword" (isErrOf (moduleName "---- MODULEX Foo ----\n"))
  check fails "moduleName: path traversal"
    (isErrOf (moduleName "---- MODULE ../../target ----\n"))
  check fails "moduleName: path separator"
    (isErrOf (moduleName "---- MODULE nested/target ----\n"))

def unitMaterialize (fails : Failures) : IO Unit := do
  match ← materializeSpec { sources := [] } with
  | .error e => check fails "materialize: no sources" (e == "spec has no sources") e
  | .ok _ => check fails "materialize: no sources" false "expected error"
  let dup := { sources := [hcSrc, hcSrc] }
  match ← materializeSpec (dup : Codec.SpecConfig) with
  | .error e => check fails "materialize: dup names" (e == "duplicate module names in spec sources") e
  | .ok _ => check fails "materialize: dup names" false "expected error"
  let ext := "---- MODULE Ext ----\nFoo == 1\n====\n"
  match ← materializeSpec { sources := [hcSrc, ext] } with
  | .error e => check fails "materialize: two sources" false e
  | .ok (dir, root) =>
      let rootOk ← (root : System.FilePath).pathExists
      let extOk ← (dir ++ "/Ext.tla" : System.FilePath).pathExists
      check fails "materialize: root exists" rootOk root
      check fails "materialize: ext exists" extOk (dir ++ "/Ext.tla")
      removeDirRecursive dir
      let still ← (dir : System.FilePath).pathExists
      check fails "materialize: removed" (!still) dir
      check fails "materialize: root name" (root.endsWith "HourClock.tla") root

def unitAcquire (fails : Failures) : IO Unit := do
  let cfg : Codec.ApalacheConfig :=
    { constInit := none, initPredicate := none, invariant := "", lengthBound := 10,
      nextPredicate := none, paramVars := "", specPath := "specs/Counter.tla" }
  match ← acquireSpec none cfg with
  | .error e => check fails "acquire: borrowed" false e
  | .ok (res, cfg') =>
      check fails "acquire: borrowed prov" (res.provenance == .Borrowed)
      check fails "acquire: borrowed path" (res.rootPath == "specs/Counter.tla")
      check fails "acquire: cfg unchanged" (cfg'.specPath == "specs/Counter.tla")
      releaseSpec res -- must not delete anything
  match ← acquireSpec (some { sources := [hcSrc] }) cfg with
  | .error e => check fails "acquire: owned" false e
  | .ok (res, cfg') =>
      check fails "acquire: owned prov" (res.provenance == .Owned)
      let dirOk ← match res.dir with | some d => (d : System.FilePath).pathExists | none => pure false
      check fails "acquire: owned dir" dirOk (toString (repr res.dir))
      check fails "acquire: cfg overridden" (cfg'.specPath == res.rootPath) cfg'.specPath
      releaseSpec res
      let still ← match res.dir with | some d => (d : System.FilePath).pathExists | none => pure false
      check fails "acquire: owned released" (!still)

def unitBorrowedCounterClosure (fails : Failures) : IO Unit := do
  match ← borrowedSourceDigests "specs/Counter.tla" with
  | .error error =>
      check fails "borrowed closure: Counter resolves" false error
  | .ok [source] =>
      check fails "borrowed closure: Counter module"
        (source.moduleName == "Counter") source.moduleName
      check fails "borrowed closure: logical filename only"
        (source.logicalPath == "Counter.tla") source.logicalPath
      check fails "borrowed closure: normalized Counter digest"
        (source.contentSha256 ==
          "405b4ffb80464cdf919d986e142b180e044c41caf8e6aabe978db0e8e7aa0340")
        source.contentSha256
  | .ok sources =>
      check fails "borrowed closure: Counter resolves" false
        (toString (repr sources))

def digestFor (name : String)
    (sources : List Core.ModelInterface.SourceDigest) : Option String :=
  (sources.find? (fun source => source.moduleName == name)).map
    (·.contentSha256)

def closureASource : String :=
  "---- MODULE A ----\n" ++
  "EXTENDS Naturals\n" ++
  "Child == INSTANCE B\n" ++
  "Quoted == \"INSTANCE Ghost\"\n" ++
  "\\* EXTENDS Missing\n" ++
  "AValue == B!BValue\n" ++
  "====\n"

def closureBSource (value : Nat) : String :=
  "---- MODULE B ----\n" ++
  "EXTENDS A\n" ++
  s!"BValue == {value}\n" ++
  "====\n"

def unitBorrowedRecursiveClosure (fails : Failures) : IO Unit := do
  let dir ← freshSessionDir
  let rootPath := dir ++ "/A.tla"
  let childPath := dir ++ "/B.tla"
  IO.FS.writeFile rootPath (closureASource.replace "\n" "\r\n")
  IO.FS.writeFile childPath (closureBSource 1)
  let first ← match ← borrowedSourceDigests rootPath with
    | .error error =>
        check fails "borrowed closure: recursive cycle resolves" false error
        pure []
    | .ok sources => pure sources
  check fails "borrowed closure: recursive cycle deduplicated"
    (first.map (fun source => (source.moduleName, source.logicalPath)) ==
      [("A", "A.tla"), ("B", "B.tla")]) (toString (repr first))
  check fails "borrowed closure: no absolute paths"
    (first.all fun source =>
      !source.logicalPath.contains "/" &&
      !source.logicalPath.contains "\\" &&
      !source.logicalPath.contains dir) (toString (repr first))

  IO.FS.writeFile rootPath closureASource
  let normalized ← match ← borrowedSourceDigests rootPath with
    | .error error =>
        check fails "borrowed closure: LF rewrite resolves" false error
        pure []
    | .ok sources => pure sources
  check fails "borrowed closure: CRLF normalization stable"
    (decide (first = normalized))

  IO.FS.writeFile childPath (closureBSource 2)
  let changed ← match ← borrowedSourceDigests rootPath with
    | .error error =>
        check fails "borrowed closure: changed sibling resolves" false error
        pure []
    | .ok sources => pure sources
  check fails "borrowed closure: unchanged root digest stable"
    (digestFor "A" first == digestFor "A" changed)
  check fails "borrowed closure: sibling change updates digest"
    ((digestFor "B" first).isSome &&
      digestFor "B" first != digestFor "B" changed)

  IO.FS.writeFile rootPath
    "---- MODULE A ----\nEXTENDS Option, Variants\n====\n"
  match ← borrowedSourceDigests rootPath with
  | .error error =>
      check fails "borrowed closure: Apalache standard modules resolve" false error
  | .ok sources =>
      check fails "borrowed closure: Apalache standard modules are external"
        (sources.map (·.moduleName) == ["A"]) (toString (repr sources))
  removeDirRecursive dir

def checkClosureError {alpha : Type} (fails : Failures) (name needle : String)
    (result : Except String alpha) : IO Unit :=
  match result with
  | .error error => check fails name (error.contains needle) error
  | .ok _ => check fails name false "expected closure resolution error"

def unitBorrowedClosureFailures (fails : Failures) : IO Unit := do
  let dir ← freshSessionDir
  let rootPath := dir ++ "/A.tla"
  let childPath := dir ++ "/B.tla"
  IO.FS.writeFile rootPath closureASource
  IO.FS.writeFile childPath (closureBSource 1)

  checkClosureError fails "borrowed closure: module total bounded" "module limit 1"
    (← borrowedSourceDigests rootPath
      (limits := { defaultBorrowedSourceLimits with maxModules := 1 }))
  checkClosureError fails "borrowed closure: file bytes bounded" "file byte limit 1"
    (← borrowedSourceDigests rootPath
      (limits := { defaultBorrowedSourceLimits with maxFileBytes := 1 }))
  checkClosureError fails "borrowed closure: total bytes bounded" "total byte limit"
    (← borrowedSourceDigests rootPath
      (limits := { defaultBorrowedSourceLimits with
        maxTotalBytes := closureASource.toUTF8.size }))
  checkClosureError fails "borrowed closure: depth bounded" "depth limit 0"
    (← borrowedSourceDigests rootPath
      (limits := { defaultBorrowedSourceLimits with maxDepth := 0 }))

  IO.FS.writeFile childPath "this is readable but not a TLA module\n"
  let malformed ← borrowedSourceDigests rootPath
  match malformed with
  | .error error =>
      check fails "borrowed closure: malformed local module fails"
        (error.contains "B.tla" && error.contains "no MODULE header") error
  | .ok sources =>
      check fails "borrowed closure: malformed local module fails" false
        (toString (repr sources))
  removeDirRecursive dir

private def makeSourceSymlink (target link : System.FilePath) :
    IO (Except String Unit) := do
  let output ← IO.Process.output {
    cmd := "ln"
    args := #["-s", "--", target.toString, link.toString]
  }
  if output.exitCode == 0 then return .ok ()
  return .error output.stderr

def unitBorrowedClosureSymlinks (fails : Failures) : IO Unit := do
  if System.Platform.isWindows then
    check fails "borrowed closure: symlink cases skipped on Windows" true
  else
    let dir ← freshSessionDir
    let realRoot : System.FilePath := dir ++ "/RealA.tla"
    let linkedRoot : System.FilePath := dir ++ "/A.tla"
    IO.FS.writeFile realRoot closureASource
    match ← makeSourceSymlink realRoot linkedRoot with
    | .error error =>
        check fails "borrowed closure: create root symlink" false error
    | .ok () =>
        checkClosureError fails "borrowed closure: root symlink rejected"
          "symbolic link" (← borrowedSourceDigests linkedRoot.toString)

    IO.FS.removeFile linkedRoot
    IO.FS.writeFile linkedRoot closureASource
    let realChild : System.FilePath := dir ++ "/RealB.tla"
    let linkedChild : System.FilePath := dir ++ "/B.tla"
    IO.FS.writeFile realChild (closureBSource 1)
    match ← makeSourceSymlink realChild linkedChild with
    | .error error =>
        check fails "borrowed closure: create sibling symlink" false error
    | .ok () =>
        checkClosureError fails "borrowed closure: sibling symlink rejected"
          "symbolic link" (← borrowedSourceDigests linkedRoot.toString)
    removeDirRecursive dir

def unitBorrowedTraceSnapshot (fails : Failures) : IO Unit := do
  let dir ← freshSessionDir
  let rootPath := dir ++ "/A.tla"
  let childPath := dir ++ "/B.tla"
  let originalRoot := closureASource
  let originalChild := closureBSource 1
  let changedRoot := originalRoot.replace "AValue == B!BValue" "AValue == 99"
  let changedChild := closureBSource 2
  IO.FS.writeFile rootPath originalRoot
  IO.FS.writeFile childPath originalChild
  let cfg : Codec.ApalacheConfig :=
    { constInit := none, initPredicate := none, invariant := "", lengthBound := 1,
      nextPredicate := none, paramVars := "", specPath := rootPath }
  let seenRoot ← IO.mkRef ""
  let seenChild ← IO.mkRef ""
  let seenPath ← IO.mkRef ""
  let generate := fun (_ : Option String) (acquired : Codec.ApalacheConfig)
      (_ : Codec.TraceConfig) (_ : Bool) (_ : Bool) => do
    -- This mutation models the borrowed files changing after provenance was
    -- captured but before Apalache opens its configured source path.
    IO.FS.writeFile rootPath changedRoot
    IO.FS.writeFile childPath changedChild
    seenPath.set acquired.specPath
    seenRoot.set (← IO.FS.readFile acquired.specPath)
    let acquiredDir := (acquired.specPath : System.FilePath).parent.getD "."
    seenChild.set (← IO.FS.readFile (acquiredDir / "B.tla"))
    return .ok ({ traces := [default] } : Shell.Mirror.TraceBundle)
  let result ← Shell.Apalache.generateSyncTraceBundleVia generate cfg none
    { numTraces := 1, view := none } true false
  match result with
  | .error error =>
      check fails "borrowed snapshot: negotiated generation succeeds" false error
  | .ok bundle =>
      check fails "borrowed snapshot: Apalache root is immutable capture"
        ((← seenRoot.get) == originalRoot)
      check fails "borrowed snapshot: Apalache dependency is immutable capture"
        ((← seenChild.get) == originalChild)
      check fails "borrowed snapshot: config does not retain borrowed root"
        ((← seenPath.get) != rootPath) (← seenPath.get)
      check fails "borrowed snapshot: manifest matches captured root"
        (digestFor "A" bundle.sources ==
          some "3ab90b08dc4db7dcf79c3c493a0da13ad5aa6c50637a91751a07dd40add10e19")
      check fails "borrowed snapshot: manifest matches captured dependency"
        (digestFor "B" bundle.sources ==
          some "2a08b2faeac3127728c8a5087454908caf00bb3482a72e805b452ffd7320c5ea")
      let snapshotStill ← ((← seenPath.get) : System.FilePath).pathExists
      check fails "borrowed snapshot: released after generation" (!snapshotStill)

  let legacyPath ← IO.mkRef ""
  let generateLegacy := fun (_ : Option String) (acquired : Codec.ApalacheConfig)
      (_ : Codec.TraceConfig) (_ : Bool) (_ : Bool) => do
    legacyPath.set acquired.specPath
    return .ok ({ traces := [default] } : Shell.Mirror.TraceBundle)
  match ← Shell.Apalache.generateSyncTraceBundleVia generateLegacy cfg none
      { numTraces := 1, view := none } false false with
  | .error error =>
      check fails "borrowed snapshot: legacy generation succeeds" false error
  | .ok bundle =>
      check fails "borrowed snapshot: legacy path remains borrowed"
        ((← legacyPath.get) == rootPath) (← legacyPath.get)
      check fails "borrowed snapshot: legacy has no source manifest"
        bundle.sources.isEmpty (toString (repr bundle.sources))

  let missingCfg := { cfg with specPath := dir ++ "/Missing.tla" }
  match ← Shell.Apalache.generateSyncTraceBundleVia generateLegacy missingCfg none
      { numTraces := 1, view := none } true false with
  | .error error =>
      check fails "borrowed snapshot: unavailable capture preserves generation" false error
  | .ok bundle =>
      check fails "borrowed snapshot: unavailable capture has no manifest"
        bundle.sources.isEmpty (toString (repr bundle.sources))
      check fails "borrowed snapshot: unavailable capture uses legacy path"
        ((← legacyPath.get) == missingCfg.specPath) (← legacyPath.get)
  removeDirRecursive dir

/-! ## Unit: args and output-dir parsing -/

def unitArgs (fails : Failures) : IO Unit := do
  let cfg : Codec.ApalacheConfig :=
    { constInit := some "CInit", initPredicate := some "I", invariant := "Inv",
      lengthBound := 13, nextPredicate := some "N", paramVars := "",
      specPath := "S.tla" }
  check fails "tcArgs"
    (tcArgs (some "/rd") cfg == ["typecheck", "--run-dir=/rd", "S.tla"])
  check fails "checkArgs"
    (checkArgs (some "/rd") cfg 10 ==
      ["check", "--length=10", "--run-dir=/rd", "--inv=Inv", "--init=I",
       "--next=N", "--cinit=CInit", "S.tla"])
  check fails "checkArgs: empty inv skipped"
    (checkArgs none { cfg with invariant := "" } 10 ==
      ["check", "--length=10", "--init=I", "--next=N", "--cinit=CInit", "S.tla"])
  check fails "traceArgs"
    (traceArgs (some "/rd") cfg { numTraces := 3, view := none } ==
      ["check", "--inv=Inv", "--length=13", "--max-error=3", "--output-traces",
       "--run-dir=/rd", "--init=I", "--next=N", "--cinit=CInit",
       "S.tla"])
  check fails "traceArgs: view gated"
    (traceArgs none { cfg with invariant := "" } { numTraces := 1, view := some "untyped" } ==
      ["check", "--length=13", "--max-error=1", "--output-traces", "--init=I",
       "--next=N", "--cinit=CInit", "--view=untyped", "S.tla"])
  check fails "parseOutputDir: found"
    (parseOutputDir "foo\nOutput directory: /a/b\nbar" == some "/a/b")
  check fails "parseOutputDir: absent" (match parseOutputDir "no line here" with | .none => true | .some _ => false)

/-! ## Unit: disk ITF artifact parsing -/

def unitDiskTraceLimits (fails : Failures) : IO Unit := do
  check fails "disk ITF: separate bounded artifact profile"
    (Shell.Mirror.itfTraceArtifactLimits.maxBytes ==
        Shell.Mirror.maxItfTraceArtifactBytes &&
      Shell.Mirror.maxItfTraceArtifactBytes == 16 * 1024 * 1024 &&
      Shell.Mirror.itfTraceArtifactLimits.maxDepth ==
        Codec.StrictJson.defaultLimits.maxDepth)
  check fails "disk ITF: fixture exceeds wire limit"
    (largeItfTraceJson.toUTF8.size > Codec.StrictJson.defaultLimits.maxBytes)
  let dir ← freshSessionDir
  let path := dir ++ "/large.itf.json"
  IO.FS.writeFile path largeItfTraceJson
  match ← Shell.Mirror.readItfTrace path with
  | .error error =>
      check fails "legacy disk ITF: valid large artifact accepted" false error
  | .ok trace =>
      check fails "legacy disk ITF: valid large artifact accepted"
        (trace.traceStates.length == 1)
  match ← Shell.Mirror.readItfTraceBundle path with
  | .error error =>
      check fails "disk ITF: valid large artifact accepted" false error
  | .ok bundle =>
      check fails "disk ITF: valid large artifact accepted"
        (bundle.traces.length == 1)
  match Codec.StrictJson.parseString largeItfTraceJson with
  | .error error =>
      check fails "wire JSON: same large payload rejected"
        (error.kind == .tooLarge) (toString error)
  | .ok _ =>
      check fails "wire JSON: same large payload rejected" false
  removeDirRecursive dir

def unitGeneratedTraceParseFailure (fails : Failures) : IO Unit := do
  let dir ← freshSessionDir
  let validPath := dir ++ "/valid.itf.json"
  let invalidPath := dir ++ "/invalid.itf.json"
  IO.FS.writeFile validPath smallItfTraceJson
  IO.FS.writeFile invalidPath "{"
  let cfg : Codec.ApalacheConfig :=
    { constInit := none, initPredicate := none, invariant := "", lengthBound := 1,
      nextPredicate := none, paramVars := "", specPath := "S.tla" }
  let generateFiles := fun (_ : Option String) (_ : Codec.ApalacheConfig)
      (_ : Codec.TraceConfig) =>
    pure (.ok (dir, [validPath, invalidPath]))
  match ← generateTraceBundleVia generateFiles none cfg
      { numTraces := 2, view := none } with
  | .error error =>
      check fails "generated traces: one parse failure rejects bundle"
        (error == "generated ITF trace failed strict parsing" &&
          !error.contains dir) error
  | .ok bundle =>
      check fails "generated traces: one parse failure rejects bundle" false
        s!"silently retained {bundle.traces.length} trace(s)"
  removeDirRecursive dir

def unitGeneratedTraceResourceFallback (fails : Failures) : IO Unit := do
  let path := "test/fixtures/model-interface/counter/counter.itf.json"
  let raw ← IO.FS.readFile path
  let cfg : Codec.ApalacheConfig :=
    { constInit := none, initPredicate := none, invariant := "", lengthBound := 3,
      nextPredicate := none, paramVars := "parameters", specPath := "Counter.tla" }
  let calls ← IO.mkRef 0
  let generateFiles := fun (_ : Option String) (_ : Codec.ApalacheConfig)
      (_ : Codec.TraceConfig) => do
    calls.modify (· + 1)
    return .ok ("generated-output", [path, path])
  let exact : Shell.Mirror.NegotiatedTraceLoadLimits := {
    maxFiles := 2
    maxAggregateBytes := raw.toUTF8.size * 2
    maxTraces := 2
    maxStates := 6
  }
  match ← generateTraceBundleVia generateFiles none cfg
      { numTraces := 2, view := none } true false exact with
  | .error error =>
      check fails "generated limits: exact budgets accepted" false error
  | .ok bundle =>
      check fails "generated limits: exact evidence retained"
        (bundle.traces.length == 2 && bundle.evidence.isSome &&
          !bundle.evidenceInvalid)

  let beforeRequired ← calls.get
  match ← generateTraceBundleVia generateFiles none cfg
      { numTraces := 2, view := none } true false
      { exact with maxFiles := 1 } with
  | .ok _ =>
      check fails "generated limits require: fails before legacy parse" false
  | .error error =>
      check fails "generated limits require: stable resource error"
        (error == "generated ITF trace exceeded negotiated resource limits")
        error
  check fails "generated limits require: generator invoked once"
    ((← calls.get) == beforeRequired + 1)

  let expectFallback (label : String)
      (limits : Shell.Mirror.NegotiatedTraceLoadLimits) : IO Unit := do
    let before ← calls.get
    match ← generateTraceBundleVia generateFiles none cfg
        { numTraces := 2, view := none } true true limits with
    | .error error => check fails (label ++ ": legacy fallback") false error
    | .ok bundle =>
        check fails (label ++ ": traces retained")
          (bundle.traces.length == 2)
        check fails (label ++ ": evidence unavailable")
          (bundle.evidence.isNone && !bundle.evidenceInvalid)
    check fails (label ++ ": generator invoked once")
      ((← calls.get) == before + 1)

  expectFallback "generated limits file-count" { exact with maxFiles := 1 }
  expectFallback "generated limits aggregate-byte"
    { exact with maxAggregateBytes := exact.maxAggregateBytes - 1 }
  expectFallback "generated limits trace-count" { exact with maxTraces := 1 }
  expectFallback "generated limits state-count" { exact with maxStates := 5 }

/-! ## Integration against real apalache -/

def integration (fails : Failures) : IO Unit := do
  let bin? ← IO.getEnv "APALACHE_MC"
  match bin? with
  | none => IO.eprintln "SKIP integration (APALACHE_MC not set)"
  | some bin => do
      let repo ← IO.currentDir
      let specAbs := repo.toString ++ "/test/specs/HourClock.tla"
      let hcCfg : Codec.ApalacheConfig :=
        { constInit := none, initPredicate := none, invariant := "TraceComplete",
          lengthBound := 13, nextPredicate := none, paramVars := "",
          specPath := specAbs }
      -- scratch cwd: the "mirror working directory" apalache must not litter
      let scratch ← freshSessionDir
      IO.Process.setCurrentDir scratch
      -- validate with run dir: cwd isolation + exit classification
      let runDir ← freshSessionDir
      match ← validateSpecIn (some runDir) hcCfg 1 with
      | .error e => check fails "int: validate valid" false e
      | .ok .valid => check fails "int: validate valid" true
      | .ok (.invalid m) => check fails "int: validate valid" false m
      let stray1 ← ("_apalache-out" : System.FilePath).pathExists
      let stray2 ← ("tmp" : System.FilePath).pathExists
      check fails "int: cwd clean (validate)" (!stray1 && !stray2)
      let runDirOk ← (runDir : System.FilePath).pathExists
      check fails "int: run dir exists" runDirOk runDir
      -- violated invariant at a longer bound: spec-authored verdict
      -- (exit 12), not infra; a missing operator is a config error
      -- (exit 255) and must classify as infra
      match ← validateSpecIn (some runDir) hcCfg 13 with
      | .ok (.invalid _) => check fails "int: invalid verdict" true
      | .ok .valid => check fails "int: invalid verdict" false "unexpectedly valid"
      | .error e => check fails "int: invalid verdict" false e
      match ← validateSpecIn (some runDir) { hcCfg with invariant := "NoSuchInvariant" } 1 with
      | .error _ => check fails "int: missing op is infra" true
      | .ok _ => check fails "int: missing op is infra" false "unexpectedly a verdict"
      -- trace generation into a run dir
      match ← generateTraceFilesIn (some runDir) hcCfg { numTraces := 1, view := none } with
      | .error e => check fails "int: trace files" false e
      | .ok (outDir, paths) => do
          check fails "int: trace paths" (!paths.isEmpty) (toString (repr paths))
          let outInRun := prefixOf runDir outDir
          check fails "int: out dir under run dir" outInRun (outDir ++ " vs " ++ runDir)
          if let some p := paths.head? then
            match ← Shell.Mirror.readItfTrace p with
            | .error e => check fails "int: trace parses" false e
            | .ok tr => check fails "int: trace states" (!tr.traceStates.isEmpty)
      match ← generateTracesIn (some runDir) hcCfg { numTraces := 1, view := none } with
      | .error e => check fails "int: in-memory traces" false e
      | .ok ts => check fails "int: in-memory traces" (!ts.isEmpty)
      let stray3 ← ("_apalache-out" : System.FilePath).pathExists
      check fails "int: cwd clean (traces)" (!stray3)
      -- cancellable spawn: cancel a long run promptly
      let token ← Shell.Jobs.CancelToken.new
      let startMs ← IO.monoMsNow
      let task ← IO.asTask (prio := Task.Priority.dedicated)
        (runApalacheCancellable token (some runDir)
          (traceArgs (some runDir) hcCfg { numTraces := 10, view := none }))
      IO.sleep 3000
      token.flag.set true
      (← token.cleanup.get)
      let rRes : Except IO.Error ApalacheResult := task.get
      let r := rRes
      let elapsed ← IO.monoMsNow
      match r with
      | .error e => check fails "int: cancellable" false s!"{e}"
      | .ok _ =>
          check fails "int: cancellable returned" true
          check fails "int: cancel prompt" (elapsed - startMs < 60000)
              s!"{(elapsed - startMs)}ms"
      IO.Process.setCurrentDir repo
      removeDirRecursive scratch

def main : IO UInt32 := do
  let fails ← IO.mkRef ([] : List String)
  let run (name : String) (s : Failures → IO Unit) := do
    IO.eprintln s!"[scenario {name}]"
    try s fails
    catch e => IO.eprintln s!"EXCEPTION in {name}: {e}"
  run "moduleName" unitModuleName
  run "materialize" unitMaterialize
  run "acquire" unitAcquire
  run "borrowed-counter-closure" unitBorrowedCounterClosure
  run "borrowed-recursive-closure" unitBorrowedRecursiveClosure
  run "borrowed-closure-failures" unitBorrowedClosureFailures
  run "borrowed-closure-symlinks" unitBorrowedClosureSymlinks
  run "borrowed-trace-snapshot" unitBorrowedTraceSnapshot
  run "args" unitArgs
  run "disk-trace-limits" unitDiskTraceLimits
  run "generated-trace-parse-failure" unitGeneratedTraceParseFailure
  run "generated-trace-resource-fallback" unitGeneratedTraceResourceFallback
  run "integration" integration
  let fs ← fails.get
  if fs.isEmpty then
    IO.println "APALACHE CLI GREEN"
    return 0
  else
    for f in fs do IO.eprintln s!"FAIL {f}"
    IO.eprintln s!"{fs.length} FAILURES"
    return 1
