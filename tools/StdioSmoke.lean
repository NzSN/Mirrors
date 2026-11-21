import Shell.Mirror.Session
import Shell.Version
import Codec.Json
import Lean.Data.Json

/-!
# Phase 3 stdio smoke test (tools/StdioSmoke.lean)

Spawns the built Lean mirror binary (@.lake/build/bin/mirror@) as a real
OS process, speaks the JSON wire protocol over its stdio pipes, and
asserts the Phase-3 default-mode session semantics end to end:

1. clean replay: @register_traces@ with two ITF trace files →
   @spec_validated@ → per-step @initial_state@/@next_step@ + @step_ok@
   → @all_steps_done@ (both traces, multi-trace continuation);
2. mismatch: a deliberately wrong @report_state@ mid-trace →
   @step_mismatch@ and the session ends (no @all_steps_done@).

This mirrors what the Haskell @MirrorProtocolSpec@ MBT-over-stdio test
observes (client-visible message flow only).
-/

open Codec Shell.Mirror

/-- Test ApalacheConfig (only @specPath@ matters for the traces flow). -/
def smokeCfg : ApalacheConfig where
  constInit := none
  initPredicate := none
  invariant := ""
  lengthBound := 10
  nextPredicate := none
  paramVars := ""
  specPath := "HourClock.tla"

/-- Two tiny ITF traces (numbers must be ITF @#bigint@ strings). -/
def trace1 : String :=
  "{\"vars\": [\"hour\"], \"param_vars\": [], \"params\": [],
    \"states\": [
      {\"action_taken\": \"Init\", \"hour\": {\"#bigint\": \"1\"}},
      {\"action_taken\": \"Tick\", \"hour\": {\"#bigint\": \"2\"}}
    ]}"

def trace2 : String :=
  "{\"vars\": [\"hour\"], \"param_vars\": [\"delta\"], \"params\": [],
    \"states\": [
      {\"action_taken\": \"Init\", \"hour\": {\"#bigint\": \"7\"}},
      {\"action_taken\": \"Tick\", \"delta\": {\"#bigint\": \"1\"}, \"hour\": {\"#bigint\": \"8\"}},
      {\"action_taken\": \"Tick\", \"delta\": {\"#bigint\": \"1\"}, \"hour\": {\"#bigint\": \"9\"}}
    ]}"

/-- Corrupt a state map for the mismatch scenario (change hour). -/
def wrongState (m : ValueMap) : ValueMap :=
  m.map (fun (k, v) => if k == "hour" then (k, .vint 999) else (k, v))

abbrev SmokeState := IO.Ref (Array String × Nat) -- seen tags, step count

/-- Read one line from the mirror, update the session, reply if needed.
Returns false when the session is over (EOF or terminal message). -/
def handleLine (out : IO.FS.Handle) (st : SmokeState)
    (steps : List Step) (corruptAtStep : Option Nat) (line : String) :
    IO Bool := do
  if line.isEmpty then return false -- EOF: session over
  let line := Shell.Transport.stripEol line
  match Lean.Json.parse line with
  | .error e => throw (IO.userError s!"mirror sent undecodable line: {e}")
  | .ok j =>
    let tag := match j.getObjVal? "proto_step" with
      | .ok (.str s) => s
      | _ => "?"
    let (seen, stepCount) ← st.get
    st.set (seen.push tag, stepCount)
    match tag with
    | "initial_state" | "next_step" =>
        match steps[stepCount]? with
        | none => throw (IO.userError s!"client model: no step {stepCount}")
        | some s =>
            let expectedPrompt := if s.idx == 0 then Codec.MirrorMessage.initialState s.act s.vars
              else .nextStep s.act s.params
            if line != (encodeMirror expectedPrompt).compress then
              throw (IO.userError s!"unexpected replay prompt at step {stepCount}: {line}")
            let report :=
              if corruptAtStep == some stepCount then wrongState s.vars
              else s.vars
            out.putStr (toString (Lean.Json.compress (encodeClient (.reportState report))) ++ "\n")
            out.flush
            return true
    | "step_ok" =>
        let (seen', _) ← st.get
        st.set (seen', stepCount + 1)
        return true
    | "step_mismatch" =>
        let (seen', _) ← st.get
        st.set (seen', stepCount + 1000) -- flag: mismatch at current step
        return false
    | "all_steps_done" => return false
    | _ => return true

/-- Drive one full session to termination. -/
def driveSession (bin : String) (tracePaths : List String)
    (steps : List Step) (corruptAtStep : Option Nat) :
    IO (Array String) := do
  let child ← IO.Process.spawn
    ({ cmd := bin, args := #[], stdin := .piped, stdout := .piped :
      IO.Process.SpawnArgs })
  let seen ← try
    let (out, _) ← child.takeStdin
    out.putStr (toString (Lean.Json.compress
      (encodeClient (.registerTraces smokeCfg tracePaths))) ++ "\n")
    out.flush
    let st ← IO.mkRef ((#[] : Array String), 0)
    let mut go := true
    while go do
      let line ← child.stdout.getLine
      go ← handleLine out st steps corruptAtStep line
    -- A duplicate terminal, blank frame or partial final line must be visible.
    if !(← child.stdout.getLine).isEmpty then
      throw (IO.userError "unexpected output after terminal replay message")
    pure (← st.get).1
  catch err =>
    try child.kill catch _ => pure ()
    let _ ← child.wait
    throw err
  let code ← child.wait
  if code != 0 then throw (IO.userError s!"mirror exited with status {code}")
  return seen

/-- Exercise the real session dispatcher with scripted reports and optional
backend outcomes, without starting a model checker. -/
private def sessionTags (request : Codec.ClientMessage) (reports : List String := [])
    (oracles : Shell.Mirror.Oracles := stubOracles) : IO (List String) := do
  let pending ← IO.mkRef ((encodeClient request).compress :: reports)
  let tags ← IO.mkRef ([] : List String)
  let transport : Shell.Transport.Transport := {
    scope := .sharedFilesystem
    recv := do
      match ← pending.get with
      | [] => return none
      | first :: rest => pending.set rest; return some first
    send := fun line => do
      let .ok json := Lean.Json.parse line | throw (IO.userError "invalid response JSON")
      let .ok tag := json.getObjValAs? String "proto_step"
        | throw (IO.userError "response tag missing")
      tags.modify (· ++ [tag]) }
  Shell.Mirror.run transport oracles
  return ← tags.get

private def admissionRegressions (dir p1 : String) : IO Bool := do
  let empty := dir ++ "/empty.itf.json"
  IO.FS.writeFile empty "{\"vars\":[\"hour\"],\"states\":[]}"
  let emptyDir := dir ++ "/empty-dir"
  IO.FS.createDirAll emptyDir
  for paths in [[], [emptyDir], [empty], [p1, empty]] do
    let tags ← sessionTags (.registerTraces smokeCfg paths)
    if tags != ["register_error"] then
      IO.eprintln s!"empty replay admitted: {paths}: {tags}"
      return false
  -- Generated bundles use the same admission guard as supplied files.
  let .ok normal ← readItfTrace p1 | throw (IO.userError "normal trace did not parse")
  for traces in [[], [{ normal with traceStates := [] }],
      [normal, { normal with traceStates := [] }]] do
    let oracles : Shell.Mirror.Oracles := { stubOracles with
      generateTraces := fun _ _ _ _ _ => pure (.ok { traces }) }
    let tags ← sessionTags (.register smokeCfg none { numTraces := 1, view := none }) [] oracles
    if tags != ["register_error"] then
      IO.eprintln s!"empty generated replay admitted: {tags}"
      return false
  let mapPath := dir ++ "/map.itf.json"
  IO.FS.writeFile mapPath
    "{\"vars\":[\"m\"],\"states\":[{\"action_taken\":\"Init\",\"m\":{\"#map\":[[\"k\",1]]}}]}"
  let valid := "{\"proto_step\":\"report_state\",\"state\":{\"m\":{\"#map\":[[\"k\",1]]}}}"
  let clean ← sessionTags (.registerTraces smokeCfg [mapPath]) [valid]
  if clean != ["spec_validated", "initial_state", "step_ok", "all_steps_done"] then
    IO.eprintln s!"valid map replay refused: {clean}"
    return false
  for raw in [
      "{\"proto_step\":\"report_state\",\"state\":{\"m\":{\"#map\":[[\"k\",1],[\"k\",999]]}}}",
      "{\"proto_step\":\"report_state\",\"state\":{\"m\":{\"#map\":[[\"k\",1],[\"k\",1]]}}}" ] do
    let tags ← sessionTags (.registerTraces smokeCfg [mapPath]) [raw]
    if tags != ["spec_validated", "initial_state", "protocol_error"] then
      IO.eprintln s!"duplicate map report accepted: {tags}"
      return false
  IO.println "replay admission: empty bundles/states and duplicate map reports rejected"
  return true

def main : IO UInt32 := do
  let bin := ".lake/build/bin/mirror" ++ (if System.Platform.isWindows then ".exe" else "")
  -- Version inspection must exit successfully without entering a protocol session.
  let version ← IO.Process.output { cmd := bin, args := #["--version"] }
  if version.exitCode != 0 || version.stdout != s!"v{Shell.Version.version}\n" || !version.stderr.isEmpty then
    IO.eprintln s!"smoke: --version failed (exit={version.exitCode}, stdout={version.stdout}, stderr={version.stderr})"
    return 1
  -- The standalone mode rejects extra arguments instead of ignoring them.
  for args in #[#["--version", "extra"], #["--version", "--version"], #["--version", "--serve", "9000"]] do
    let invalid ← IO.Process.output { cmd := bin, args := args }
    if invalid.exitCode != 2 || !invalid.stdout.isEmpty || invalid.stderr.isEmpty then
      IO.eprintln s!"smoke: invalid --version invocation accepted: {args}"
      return 1
  IO.println "version CLI: output and argument validation passed"
  -- fixture directory (deterministic; removed first for idempotence)
  let dir := ".lake/tmp/stdio-smoke"
  try IO.FS.removeDirAll dir catch _ => pure ()
  IO.FS.createDirAll dir
  let p1 := dir ++ "/t1.itf.json"
  let p2 := dir ++ "/t2.itf.json"
  IO.FS.writeFile p1 trace1
  IO.FS.writeFile p2 trace2
  if !(← admissionRegressions dir p1) then return 1
  -- expected steps: mirror replays the traces in the given path order
  let traces ← match ← loadTraces [p1, p2] with
    | .error e => IO.eprintln s!"smoke: fixture parse failed: {e}"; return 1
    | .ok ts => pure ts
  let steps := (traces.map traceSteps).flatten
  -- 1. clean replay
  let seen ← driveSession bin [p1, p2] steps none
  IO.println s!"clean session: {seen}"
  let doneCount := seen.toList.countP (· == "all_steps_done")
  let ok1 := seen ==
    #["spec_validated",
      "initial_state", "step_ok",
      "next_step", "step_ok",          -- trace 1 done
      "initial_state", "step_ok",      -- trace 2 begins
      "next_step", "step_ok",
      "next_step", "step_ok",
      "all_steps_done"]
  -- Interrupt the generated-trace path at its final report after crossing a trace boundary.
  let oracles : Shell.Mirror.Oracles := { stubOracles with
    generateTraces := fun _ _ _ _ _ => pure (.ok { traces }) }
  let request := Codec.ClientMessage.register smokeCfg none { numTraces := 2, view := none }
  let priorReports := steps.dropLast.map fun step => (encodeClient (.reportState step.vars)).compress
  let prompts := seen.toList.dropLast.dropLast
  let finalStep := steps.getLast!
  let wrong := (encodeClient (.reportState (wrongState finalStep.vars))).compress
  for (lastInput, terminal) in [
      ([], "protocol_error"), (["{"], "protocol_error"),
      ([(encodeClient .exploreDone).compress], "protocol_error"), ([wrong], "step_mismatch")] do
    let tags ← sessionTags request (priorReports ++ lastInput) oracles
    if tags != prompts ++ [terminal] then
      IO.eprintln s!"incorrect final-report termination: {tags}"
      return 1
  -- 2. mismatch on global step 1 (second step of trace 1)
  let seen2 ← driveSession bin [p1, p2] steps (some 1)
  IO.println s!"mismatch session: {seen2}"
  let ok2 := seen2 ==
    #["spec_validated", "initial_state", "step_ok", "next_step", "step_mismatch"]
  let ok2b := (seen2.toList.countP (· == "all_steps_done")) == 0
  let ok1b := doneCount == 1
  if ok1 && ok2 && ok1b && ok2b then
    IO.println "STDIO SMOKE GREEN"
    return 0
  else
    IO.eprintln s!"STDIO SMOKE FAILED (clean={ok1} mismatch={ok2} one-all-done={ok1b} mismatch-no-all-done={ok2b} doneCount={doneCount})"
    return 1
