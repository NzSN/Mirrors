import Shell.Mirror.Session
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
  "{\"vars\": [\"hour\"], \"param_vars\": [], \"params\": [],
    \"states\": [
      {\"action_taken\": \"Init\", \"hour\": {\"#bigint\": \"7\"}},
      {\"action_taken\": \"Tick\", \"hour\": {\"#bigint\": \"8\"}},
      {\"action_taken\": \"Tick\", \"hour\": {\"#bigint\": \"9\"}}
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
  if line.isEmpty then return true
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
  let (out, _) ← child.takeStdin
  out.putStr (toString (Lean.Json.compress
    (encodeClient (.registerTraces smokeCfg tracePaths))) ++ "\n")
  out.flush
  let st ← IO.mkRef ((#[] : Array String), 0)
  let mut go := true
  while go do
    let l ← (child.stdout : IO.FS.Handle).getLine
    go ← handleLine out st steps corruptAtStep l
  -- t28: read to EOF so a duplicate all_steps_done (or any trailing
  -- junk) cannot hide behind a client that stops at the first
  -- terminal message; the line protocol never emits blank lines, so
  -- an empty getLine is EOF
  let h := (child.stdout : IO.FS.Handle)
  let mut l2 ← h.getLine
  while !l2.isEmpty do
    let l2c := Shell.Transport.stripEol l2
    if !l2c.isEmpty then
      match Lean.Json.parse l2c with
      | .ok j =>
          let tag := match j.getObjVal? "proto_step" with
            | .ok (.str s) => s
            | _ => "?"
          let (seen, sc) ← st.get
          st.set (seen.push tag, sc)
      | .error _ =>
          let (seen, sc) ← st.get
          st.set (seen.push "UNPARSEABLE", sc)
    l2 ← h.getLine
  -- best-effort cleanup
  try child.kill catch _ => pure ()
  let (seen, _) ← st.get
  return seen

def main : IO UInt32 := do
  -- fixture directory (deterministic; removed first for idempotence)
  let dir := ".lake/tmp/stdio-smoke"
  try IO.FS.removeDirAll dir catch _ => pure ()
  IO.FS.createDirAll dir
  let p1 := dir ++ "/t1.itf.json"
  let p2 := dir ++ "/t2.itf.json"
  IO.FS.writeFile p1 trace1
  IO.FS.writeFile p2 trace2
  -- expected steps: mirror replays the traces in the given path order
  let traces ← match ← loadTraces [p1, p2] with
    | .error e => IO.eprintln s!"smoke: fixture parse failed: {e}"; return 1
    | .ok ts => pure ts
  let steps := (traces.map traceSteps).flatten
  let bin := ".lake/build/bin/mirror"
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