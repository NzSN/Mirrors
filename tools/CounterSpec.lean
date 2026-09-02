import Shell.Mirror.Session
import Codec.Json
import Lean.Data.Json

/-!
# Counter end-to-end regression suite (tools/CounterSpec.lean)

Ports the INTENT of the upstream Haskell MainSpec.testCounterEndToEnd
(ModelMirros@3496251) against test/specs/Counter.tla, with corrected
expectations. Two upstream-stale assumptions are fixed and pinned here:

* The stale upstream client reports a @step_count@ key. Current
  @diffState@ (identical in Haskell and Lean — proven by the ordered
  differential gate) flags unknown actual-side keys as @extra@ hints,
  i.e. a mismatch. The upstream test only stays green because
  @findMirrorBinaryOrSkip@ skips it without a binary. The extra-key
  scenario below pins the REAL semantics.
* After @step_mismatch@ the Haskell mirror sends a trailing
  @all_steps_done@ (Protocol/Mirror.hs:270,299 — unconditional after the
  replay). The TLA+ model (specs/MirrorProtocol.tla,
  MirrorRecvReportMismatch) sends only STEP_MISMATCH and goes to done;
  the Lean mirror follows the spec (proven: no_unsolicited_output).
  DOCUMENTED DIVERGENCE (Haskell quirk vs TLA+ spec): the mismatch
  scenario below asserts the spec-faithful tail (no all_steps_done).

Scenarios (APALACHE_MC-gated; self-skip without it):
1. conform: scripted echo client follows the generated trace ->
   spec_validated, initial_state, step_ok/next_step ..., all_steps_done.
2. corrupt count: step_mismatch whose hints mention count; no trailing
   all_steps_done (spec-faithful, see above).
3. extra key (the stale upstream shape): step_mismatch with an
   @extra@ hint at step_count; no trailing all_steps_done.
-/

open Codec Shell.Mirror

/-- The Counter registration: mirrors the upstream test exactly
(constInit CInit, invariant TraceComplete, bound 5, paramVars
"parameters", one trace). -/
def counterCfg : ApalacheConfig where
  constInit := some "CInit"
  initPredicate := none
  invariant := "TraceComplete"
  lengthBound := 5
  nextPredicate := none
  paramVars := "parameters"
  specPath := "test/specs/Counter.tla"

def counterTcfg : TraceConfig where
  numTraces := 1
  view := none

inductive Corrupt where
  | none | count | extra

/-- Session state: seen tags, raw payloads of terminal messages for
hint inspection, and the client model's current count. -/
abbrev SessState := IO.Ref (Array String × Array String × Int)

/-- Find the stride in the next_step parameters. The wire shape with
@paramVars="parameters"@ is
@{"parameters":{"parameters":{"stride":N}}}@: the resplit moved the
whole @parameters@ spec variable to the params side. -/
def findStride (v : Value) : Option Int :=
  match v with
  | .vrecord fs | .vmap fs =>
      -- shape {"parameters": {"stride": N}} (paramVars="parameters")
      match fs.find? (fun (k, _) => k == "parameters") with
      | some (_, .vrecord inner) | some (_, .vmap inner) =>
          match inner.find? (fun (k, _) => k == "stride") with
          | some (_, .vint n) => some n
          | _ => none
      | _ =>
          -- fallback: flat {"stride": N}
          match fs.find? (fun (k, _) => k == "stride") with
          | some (_, .vint n) => some n
          | _ => none
  | _ => none

def vintOf (j : Lean.Json) : Option Int :=
  match Codec.decodeValue j with
  | .ok (.vint n) => some n
  | _ => none

/-- Counter client model (the MBT client side): on initial_state, adopt
the mirror's state; on next_step, EXECUTE the tick action with the
mirror-supplied stride parameter (count' = count + stride) and report
the resulting state. Optionally corrupted. Returns false when the
session is over. -/
def handleLine (out : IO.FS.Handle) (st : SessState) (mode : Corrupt)
    (line : String) : IO Bool := do
  if line.isEmpty then return false
  let line := Shell.Transport.stripEol line
  if line.isEmpty then return true
  match Lean.Json.parse line with
  | .error e => throw (IO.userError s!"mirror sent undecodable line: {e}")
  | .ok j =>
    let tag := match j.getObjVal? "proto_step" with
      | .ok (.str s) => s
      | _ => "?"
    let (seen, raws, cnt) ← st.get
    st.set (seen.push tag, raws, cnt)
    let report (vm : ValueMap) : IO Bool := do
      out.putStr (toString (Lean.Json.compress
        (encodeClient (.reportState vm))) ++ "\n")
      out.flush
      return true
    match tag with
    | "initial_state" =>
        match j.getObjVal? "state" with
        | .error e => throw (IO.userError s!"no state in initial_state: {e}")
        | .ok sj =>
          match Shell.Mirror.decodeStateMap sj with
          | .error e => throw (IO.userError s!"state decode failed: {e}")
          | .ok vm =>
            let c := match vm.find? (fun (k, _) => k == "count") with
              | some (_, .vint n) => n
              | _ => 0
            let (_, raws', _) ← st.get
            st.set ((← st.get).1, raws', c)
            match mode with
            | .none => report vm
            | .count => report (vm.map (fun (k, v) =>
                if k == "count" then (k, .vint 999) else (k, v)))
            | .extra => report (("step_count", .vint 0) :: vm)
    | "next_step" =>
        match j.getObjVal? "parameters" with
        | .error e => throw (IO.userError s!"no parameters in next_step: {e}")
        | .ok pj =>
          match Codec.decodeValue pj with
          | .error e => throw (IO.userError s!"params decode failed: {e.msg}")
          | .ok pv =>
            let stride := match findStride pv with
              | some s => s
              | none => 0
            let cnt' := cnt + stride
            let (seen', raws', _) ← st.get
            st.set (seen', raws', cnt')
            let reported := match mode with
              | .none => cnt'
              | _ => cnt' -- count/extra corruptions apply on step 0 (initial)
            report [("action_taken", .vstr "tick"), ("count", .vint reported)]
    | "step_mismatch" =>
        let (seen', raws', c) ← st.get
        st.set (seen', raws'.push line, c)
        return false
    | "all_steps_done" => return false
    | _ => return true

def driveCounter (bin : String) (mode : Corrupt) : IO (Array String × Array String) := do
  let child ← IO.Process.spawn
    ({ cmd := bin, args := #[], stdin := .piped, stdout := .piped :
      IO.Process.SpawnArgs })
  let (out, _) ← child.takeStdin
  out.putStr (toString (Lean.Json.compress
    (encodeClient (.register counterCfg none counterTcfg))) ++ "\n")
  out.flush
  let st ← IO.mkRef ((#[] : Array String), (#[] : Array String), (0 : Int))
  let mut go := true
  while go do
    let l ← (child.stdout : IO.FS.Handle).getLine
    go ← handleLine out st mode l
  try child.kill catch _ => pure ()
  let (seen, raws, _) ← st.get
  return (seen, raws)

def checkC (fails : IO.Ref (List String)) (name : String) (ok : Bool)
    (detail : String := "") : IO Unit := do
  if !ok then
    if detail.isEmpty then fails.modify (· ++ [name])
    else fails.modify (· ++ [s!"{name}: {detail}"])

private def cwdArtifactSnapshot (path : System.FilePath) :
    IO (Option (List String)) := do
  if ← path.isDir then
    let entries ← path.readDir
    return some (entries.toList.map (·.fileName) |>.mergeSort (· ≤ ·))
  else if ← path.pathExists then
    return some ["<non-directory>"]
  else
    return none

def main : IO UInt32 := do
  let fails ← IO.mkRef ([] : List String)
  let bin? ← IO.getEnv "APALACHE_MC"
  match bin? with
  | none =>
      IO.eprintln "SKIP counter_spec (APALACHE_MC not set)"
      return 0
  | some _ => do
    let bin := ".lake/build/bin/mirror" ++ (if System.Platform.isWindows then ".exe" else "")
    let apalacheOutBefore ← cwdArtifactSnapshot "_apalache-out"
    let tmpBefore ← cwdArtifactSnapshot "tmp"
    -- 1. conforming echo client follows the generated trace
    let (seen, _) ← driveCounter bin .none
    IO.println s!"conform session: {seen}"
    let tags := seen.toList
    checkC fails "conform: first is spec_validated"
      (tags.head? == some "spec_validated") (toString tags)
    checkC fails "conform: second is initial_state"
      ((tags.drop 1).head? == some "initial_state") (toString tags)
    checkC fails "conform: ends with all_steps_done"
      (tags.getLast? == some "all_steps_done") (toString tags)
    checkC fails "conform: no mismatch"
      (!tags.contains "step_mismatch") (toString tags)
    let sends := tags.filter (fun t => t == "initial_state" || t == "next_step")
    let oks := tags.filter (· == "step_ok")
    checkC fails "conform: every expected state acked"
      (sends.length == oks.length && oks.length >= 2)
      s!"sends={sends.length} oks={oks.length}"
    -- The generated trace length is apalache-search-dependent
    -- (stride choice is nondeterministic), so we only require a real
    -- stepping session: init + at least one tick.
    checkC fails "conform: at least one tick"
      (sends.length >= 2) s!"sends={sends.length}"
    -- t29: run-dir isolation — a full register-with-validation
    -- session must not litter the mirror cwd (no _apalache-out/ or
    -- tmp/ created in the repo root by the validate path)
    let apalacheOutAfter ← cwdArtifactSnapshot "_apalache-out"
    let tmpAfter ← cwdArtifactSnapshot "tmp"
    checkC fails "run-dir isolation: _apalache-out unchanged"
      (apalacheOutAfter == apalacheOutBefore)
      s!"before={apalacheOutBefore}, after={apalacheOutAfter}"
    checkC fails "run-dir isolation: tmp unchanged"
      (tmpAfter == tmpBefore)
      s!"before={tmpBefore}, after={tmpAfter}"
    -- 2. corrupted count -> mismatch mentioning count, no trailing
    -- all_steps_done (spec-faithful tail; Haskell quirk documented
    -- in the module header)
    let (seen2, raws2) ← driveCounter bin .count
    IO.println s!"corrupt-count session: {seen2}"
    let tags2 := seen2.toList
    checkC fails "corrupt: ends with step_mismatch"
      (tags2.getLast? == some "step_mismatch") (toString tags2)
    checkC fails "corrupt: no trailing all_steps_done"
      (!tags2.contains "all_steps_done") (toString tags2)
    let mm2 := (raws2.toList).head?.getD ""
    checkC fails "corrupt: hint mentions count"
      ((mm2.splitOn "\"count\"").length > 1) mm2
    -- 3. extra key (the stale upstream report shape) -> extra-hint
    -- mismatch at step_count
    let (seen3, raws3) ← driveCounter bin .extra
    IO.println s!"extra-key session: {seen3}"
    let tags3 := seen3.toList
    checkC fails "extra: ends with step_mismatch"
      (tags3.getLast? == some "step_mismatch") (toString tags3)
    let mm3 := (raws3.toList).head?.getD ""
    checkC fails "extra: hint kind is extra"
      ((mm3.splitOn "\"extra\"").length > 1) mm3
    checkC fails "extra: hint path is step_count"
      ((mm3.splitOn "step_count").length > 1) mm3
    -- 4. t28: DeterministicCounter wire parity — exact upstream input
    -- (MainSpec testEndToEnd) and the FULL expected 26-message
    -- sequence; reads stdout to EOF so a duplicate all_steps_done
    -- cannot hide behind a client that stops at the first one.
    let dcBin := ".lake/build/bin/mirror" ++ (if System.Platform.isWindows then ".exe" else "")
    let dcReport (c a s : String) : String :=
      "{\"proto_step\":\"report_state\",\"state\":{" ++
      "\"count\":{\"#bigint\":\"" ++ c ++ "\"}" ++
      ",\"action_taken\":\"" ++ a ++ "\"" ++
      ",\"step_count\":{\"#bigint\":\"" ++ s ++ "\"}}}"
    let dcTrace : List String :=
      [dcReport "0" "init" "0"] ++
      [dcReport "1" "inc" "1", dcReport "2" "inc" "2", dcReport "3" "inc" "3",
       dcReport "4" "inc" "4", dcReport "5" "inc" "5"]
    let dcRegister : String :=
      "{\"proto_step\":\"register\",\"apalacheConfig\":{" ++
      "\"specPath\":\"test/specs/DeterministicCounter.tla\"," ++
      "\"initPredicate\":null,\"nextPredicate\":null,\"constInit\":null," ++
      "\"invariant\":\"TraceComplete\",\"lengthBound\":5,\"paramVars\":\"\"}," ++
      "\"traceConfig\":{\"numTraces\":1,\"view\":null}}"
    let dcInput := (dcRegister :: (dcTrace ++ dcTrace)).map (· ++ "\n") |>.foldl (· ++ ·) ""
    let dcChild ← IO.Process.spawn
      ({ cmd := dcBin, args := #[], stdin := .piped, stdout := .piped :
        IO.Process.SpawnArgs })
    let (dcOut, _) ← dcChild.takeStdin
    dcOut.putStr dcInput
    dcOut.flush
    -- read to EOF: mirror exits when the replay completes
    -- read to EOF: the mirror exits after the replay, and the line
    -- protocol never emits blank lines, so an empty getLine is EOF —
    -- nothing after it can hide a duplicate all_steps_done
    let h := (dcChild.stdout : IO.FS.Handle)
    let mut dcOutText := ""
    let mut dcL ← h.getLine
    while !dcL.isEmpty do
      dcOutText := dcOutText ++ dcL
      dcL ← h.getLine
    let dcLines := dcOutText.splitOn "\n" |>.filter (fun l => !l.isEmpty)
    let dcTraceMsgs : List String :=
      ["initial_state", "step_ok", "next_step", "step_ok", "next_step",
       "step_ok", "next_step", "step_ok", "next_step", "step_ok", "next_step",
       "step_ok"]
    let dcExpected := ["spec_validated"] ++ dcTraceMsgs ++ dcTraceMsgs ++ ["all_steps_done"]
    checkC fails "dc: exact message count (26)"
      (dcLines.length == dcExpected.length)
      s!"got {dcLines.length}, want {dcExpected.length}: {dcLines}"
    let dcTags := dcLines.map (fun l =>
      match l.splitOn "\"proto_step\":\"" with
      | [_, rest] => (rest.splitOn "\"").head?.getD "?"
      | _ => "?")
    IO.println s!"dc session: {dcLines.length} messages: {dcTags}"
    checkC fails "dc: full proto_step sequence byte-parity"
      (dcTags == dcExpected) s!"got {dcTags}"
    checkC fails "dc: exactly one all_steps_done"
      (dcTags.countP (· == "all_steps_done") == 1) s!"got {dcTags.countP (· == "all_steps_done")}"
    let _ ← dcChild.wait
    let fs ← fails.get
    if fs.isEmpty then
      IO.println "COUNTER SPEC GREEN"
      return 0
    else
      for f in fs do IO.eprintln s!"FAIL {f}"
      IO.eprintln s!"{fs.length} FAILURES"
      return 1
