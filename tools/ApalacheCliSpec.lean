import Shell.Apalache.Cli
import Shell.Apalache.SpecSource
import Shell.Apalache.Runner
import Shell.Mirror.Session
import Codec.Json
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
    (traceArgs (some "/rd") cfg { numTraces := 3, view := "" } ==
      ["check", "--inv=Inv", "--length=13", "--max-error=3", "--output-traces",
       "--run-dir=/rd", "--init=I", "--next=N", "--cinit=CInit",
       "S.tla"])
  check fails "traceArgs: view gated"
    (traceArgs none { cfg with invariant := "" } { numTraces := 1, view := "untyped" } ==
      ["check", "--length=13", "--max-error=1", "--output-traces", "--init=I",
       "--next=N", "--cinit=CInit", "--view=untyped", "S.tla"])
  check fails "parseOutputDir: found"
    (parseOutputDir "foo\nOutput directory: /a/b\nbar" == some "/a/b")
  check fails "parseOutputDir: absent" (match parseOutputDir "no line here" with | .none => true | .some _ => false)

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
      match ← generateTraceFilesIn (some runDir) hcCfg { numTraces := 1, view := "" } with
      | .error e => check fails "int: trace files" false e
      | .ok (outDir, paths) => do
          check fails "int: trace paths" (!paths.isEmpty) (toString (repr paths))
          let outInRun := prefixOf runDir outDir
          check fails "int: out dir under run dir" outInRun (outDir ++ " vs " ++ runDir)
          if let some p := paths.head? then
            match ← Shell.Mirror.readItfTrace p with
            | .error e => check fails "int: trace parses" false e
            | .ok tr => check fails "int: trace states" (!tr.traceStates.isEmpty)
      match ← generateTracesIn (some runDir) hcCfg { numTraces := 1, view := "" } with
      | .error e => check fails "int: in-memory traces" false e
      | .ok ts => check fails "int: in-memory traces" (!ts.isEmpty)
      let stray3 ← ("_apalache-out" : System.FilePath).pathExists
      check fails "int: cwd clean (traces)" (!stray3)
      -- cancellable spawn: cancel a long run promptly
      let token ← Shell.Jobs.CancelToken.new
      let startMs ← IO.monoMsNow
      let task ← IO.asTask (prio := Task.Priority.dedicated)
        (runApalacheCancellable token (some runDir)
          (traceArgs (some runDir) hcCfg { numTraces := 10, view := "" }))
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
  run "args" unitArgs
  run "integration" integration
  let fs ← fails.get
  if fs.isEmpty then
    IO.println "APALACHE CLI GREEN"
    return 0
  else
    for f in fs do IO.eprintln s!"FAIL {f}"
    IO.eprintln s!"{fs.length} FAILURES"
    return 1