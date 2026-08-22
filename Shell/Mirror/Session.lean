import Core.Protocol
import Core.Jobs
import Shell.Jobs.Store
import Core.Trace
import Core.Diff
import Core.Value
import Codec.Json
import Codec.Bridge
import Shell.Transport.Stdio
import Lean.Data.Json

/-!
# Shell.Mirror.Session — the effectful session driver (Layer 3, design 5.3)

The thin fold over @Core.Protocol.step@ (the pure machine lives at the
root namespace: @Phase@, @Session@, @step@, @Oracles@):

    recv line → decode → Core.step → encode → send

All oracle calls are injected as parameters (the @Shell.Mirror.Oracles@
record below): spec validation, trace generation / trace-file
production, and the two explorer flows. The core stays pure — this
module never mentions a proof and the 6.3 refinement never mentions IO.

Payload state (the loaded traces and the step cursor) is driver-side
bookkeeping, exactly as documented in @Core/Protocol.lean@: the pure
machine observes only the control-relevant facts (the TLA+
@report_matches@ bit and the last-step bit), which this driver computes
with @diffState@ before each @step@ call.

Phase coverage (design 8):
- Phase 3 (this file): the stdio default mode — all @Register*@ flows
  dispatch; @register_traces@ replay is fully functional (it needs no
  apalache: the client supplies trace files).
- The apalache-backed oracles land in Phase 5, the async job store in
  Phase 4; until then @stubOracles@ fails those calls with
  @register_error@, and async/job messages answer @register_error@.

Behavior parity notes (vs @Protocol.Mirror@ / @Engine.Interactive@):
- A sync @Register*@ runs one complete flow and then the session ends
  (the Haskell @run = exec . RecvMsg@ processes exactly one register).
- Replay: step 0 sends @initial_state@ with the full state variables,
  later steps send @next_step@ with the parameter bindings; each is
  answered by the client's @report_state@; the reply is diffed with
  @diffState@; a mismatch ends the session (and stops the remaining
  traces).
- Decode failures and unexpected messages answer @protocol_error@
  before the session ends, so a networked client always sees an
  explicit error (same contract as @makeTransportDriver@).
-/

open Shell.Transport

namespace Shell.Mirror

/-! ## Injected oracles -/

/-- The effectful oracle surface of the mirror (everything that talks to
apalache or the explorer). Injected so @Core.Protocol@ stays pure. -/
structure Oracles where
  /- validateSpecIn: run a bounded validation. -/
  validateSpec : Codec.ApalacheConfig → Option Codec.SpecConfig → Nat →
    IO (Except String Codec.ValidateResult)
  /- generateTracesIn: produce in-memory traces for the replay flow. -/
  generateTraces : Codec.ApalacheConfig → Option Codec.SpecConfig → Codec.TraceConfig →
    IO (Except String (List ItfTrace))
  /- generateTraceFilesIn: produce trace files (register_trace_gen). -/
  generateTraceFiles : Codec.ApalacheConfig → Option Codec.SpecConfig → Codec.TraceConfig →
    IO (Except String Codec.TraceGenResult)
  /- The full explorer mirror flow (register_explore): owns the wire
  exchange after the register is accepted. -/
  runExplore : Shell.Transport.Transport → Codec.SpecConfig → List String →
    List String → Nat → IO Unit
  /- The explorer session flow (register_explore_session). -/
  runExploreSession : Shell.Transport.Transport → Codec.SpecConfig → List String →
    List String → IO Unit

/-- Encode and send one mirror message (one line, compact JSON). -/
def sendMirror (t : Shell.Transport.Transport) (m : Codec.MirrorMessage) :
    IO Unit :=
  t.send (toString (Lean.Json.compress (Codec.encodeMirror m)))

private def sendError (t : Shell.Transport.Transport) (msg : String) : IO Unit :=
  sendMirror t (Codec.MirrorMessage.protocolError msg)

private def errText : ProtocolError → String
  | .outOfOrder m => m

/-- Phase-3 stand-in: every apalache/explorer call fails with
@register_error@. @register_traces@ (which needs no oracle) is fully
functional with these oracles. -/
def stubOracles : Oracles where
  validateSpec _ _ _ :=
    pure (.error "apalache validate adapter lands in Phase 5")
  generateTraces _ _ _ :=
    pure (.error "apalache trace-generation adapter lands in Phase 5")
  generateTraceFiles _ _ _ :=
    pure (.error "apalache trace-generation adapter lands in Phase 5")
  runExplore t _ _ _ _ :=
    sendMirror t (Codec.MirrorMessage.registerError
      "apalache explorer adapter lands in Phase 5")
  runExploreSession t _ _ _ :=
    sendMirror t (Codec.MirrorMessage.registerError
      "apalache explorer adapter lands in Phase 5")

/-- Server cap on the validate bound (Haskell @maxValidateBound@). -/
def maxValidateBound : Nat := 100

/-! ## DiffHint conversion (Core.Diff → Codec) -/

private def convPathSeg : PathSeg → Codec.PathSeg
  | .field s => .field s
  | .index i => .index i

private def convPath (p : Path) : List Codec.PathSeg := p.map convPathSeg

/-- Convert a core diff hint to its wire form. -/
def convHint : DiffHint → Codec.DiffHint
  | .hValueMismatch p e a =>
      { kind := .valueMismatch, path := convPath p, actual := some a, expected := some e }
  | .hMissing p v =>
      { kind := .missing, path := convPath p, actual := none, expected := some v }
  | .hExtra p v =>
      { kind := .extra, path := convPath p, actual := some v, expected := none }
  | .hMissingElem p v =>
      { kind := .missingElem, path := convPath p, actual := none, expected := some v }
  | .hExtraElem p v =>
      { kind := .extraElem, path := convPath p, actual := some v, expected := none }
  | .hTypeMismatch p e a =>
      { kind := .typeMismatch, path := convPath p, actual := some a, expected := some e }
  | .hTruncated p =>
      { kind := .truncated, path := convPath p, actual := none, expected := none }

/-! ## Trace file IO (port of Apalache.Trace / FromJSON ItfTrace) -/

private def lookupV (m : ValueMap) (k : String) : Option Value :=
  (m.find? (fun p => p.1 == k)).map Prod.snd

private def jStrsOf : Lean.Json → Except String (List String)
  | .arr as =>
      as.toList.mapM (fun j => match j with
        | .str s => .ok s
        | _ => .error "expected string array")
  | _ => .error "expected string array"

private def jObjEntries : Lean.Json → Except String (List (String × Lean.Json))
  | .obj kvs => .ok kvs.toList
  | _ => .error "expected object"

/-- Decode a state-map object (keys → ITF values) using the verified
value codec (@Codec.decodeValue@; bare integral JSON numbers are
accepted natively — @Codec.decValueF_num@ — replacing the former
normNums normalization). -/
def decodeStateMap (j : Lean.Json) : Except String ValueMap := do
  let es ← jObjEntries j
  es.mapM (fun (k, jv) => do
    let v ← (Codec.decodeValue jv).mapError (fun e => e.msg)
    return (k, v))

/-- Port of the @FromJSON ItfTrace@ instance: @vars@, optional
@param_vars@ / @params@, and @states@ split into action / parameters /
state variables. -/
def parseItfTrace (j : Lean.Json) : Except String ItfTrace := do
  let varsJson ← j.getObjVal? "vars"
  let vars ← jStrsOf varsJson
  let pvs ← match j.getObjVal? "param_vars" with
    | .ok pj => jStrsOf pj
    | .error _ => .ok []
  let cns ← match j.getObjVal? "params" with
    | .ok cj => jStrsOf cj
    | .error _ => .ok []
  let statesJson ← j.getObjVal? "states"
  let rawStates ← match statesJson with
    | .arr as => .ok as.toList
    | _ => .error "ItfTrace.states: expected array"
  let states ← rawStates.mapM (fun sj => do
    let m ← decodeStateMap sj
    let actionTaken := match lookupV m "action_taken" with
      | some (.vstr a) => a
      | _ => ""
    let parameters := m.filter (fun (k, _) => pvs.contains k)
    let stateVars := m.filter (fun (k, _) =>
      vars.contains k && k != "action_taken" && !pvs.contains k)
    return ({ actionTaken, parameters, stateVars } : TraceState))
  let traceParams ← match states, rawStates with
    | _ :: _, sj :: _ =>
        let m ← decodeStateMap sj
        pure ((m.filter (fun (k, _) => cns.contains k)) : ValueMap)
    | _, _ => pure ([] : ValueMap)
  return { traceVars := vars, paramVars := pvs, traceParams, traceStates := states }

/-- Read and parse one ITF trace file (Haskell @readTrace@). -/
def readItfTrace (path : String) : IO (Except String ItfTrace) := do
  let content ← IO.FS.readFile path
  match Lean.Json.parse content with
  | .error e => return .error s!"{path}: {e}"
  | .ok j => return parseItfTrace j

/-- Expand a trace path: a directory becomes its @*.itf.json@ entries
(non-recursive, sorted for determinism); a file stays itself (Haskell
@expandPath@ / @findTraceFiles@). -/
def expandTracePath (path : String) : IO (Except String (List String)) := do
  let isDir ← (path : System.FilePath).isDir
  if isDir then
    let entries ← (path : System.FilePath).readDir
    let files := entries.toList.map (fun e => e.path.toString) |>
      List.filter (fun f => f.endsWith ".itf.json") |>
      List.toArray |>.qsort (fun a b => compare a b != Ordering.gt) |>.toList
    return .ok files
  else
    return .ok [path]

/-- Load all traces for a @register_traces@ registration (expand, read,
parse; the first failure is reported as @register_error@, like the
Haskell @MkRunMirrorWithTraces@). -/
def loadTraces (paths : List String) : IO (Except String (List ItfTrace)) := do
  let mut out := []
  for p in paths do
    let expanded ← expandTracePath p
    match expanded with
    | .error e => return .error e
    | .ok ps =>
      for q in ps do
        let r ← readItfTrace q
        match r with
        | .error e => return .error e
        | .ok tr => out := out ++ [tr]
  return .ok out

/-! ## The session fold -/

abbrev SessionRef := IO.Ref ((p : Phase) × Session p)

/-- One replay step (port of @MkReplayOne.go@ / @makeTransportDriver@):
send the step message, receive the client's reported state, diff it with
the verified engine, and thread @step@ with the computed
@report_matches@ / last-step bits. Returns whether the session may
continue (@true@ = clean, @false@ = mismatch). -/
private def replayStep (t : Shell.Transport.Transport) (sess : SessionRef)
    (stp : Step) (lastStep : Bool) : IO Bool := do
  -- step 0 sends the full state variables, later steps the parameters
  if stp.idx == 0 then
    sendMirror t (Codec.MirrorMessage.initialState stp.act stp.vars)
  else
    sendMirror t (Codec.MirrorMessage.nextStep stp.act stp.params)
  -- receive and decode the client's report
  let line ← t.recv
  let actual ← match line with
    | none =>
        sendError t "connection closed while expecting report_state"
        throw (IO.userError "connection closed while expecting report_state")
    | some l =>
        match Lean.Json.parse l with
        | .error e =>
            sendError t e
            throw (IO.userError s!"decode error: {e}")
        | .ok j =>
            match Codec.decodeClient j with
            | .error e =>
                sendError t e.msg
                throw (IO.userError s!"decode error: {e.msg}")
            | .ok (Codec.ClientMessage.reportState st) => pure st
            | .ok _ =>
                sendError t "expected report_state"
                throw (IO.userError "expected report_state")
  -- diff with the verified engine and run the pure transition
  let diff := diffState stp.vars actual
  let repMatches := match diff with
    | StateDiff.statesMatch => true
    | StateDiff.stateMismatch _ _ _ => false
  let s ← sess.get
  match _root_.step ({ validationOk := true } : _root_.Oracles) s.2
      (Codec.reportStateBridge repMatches lastStep actual) with
  | .error e =>
      sendError t (errText e)
      return false
  | .ok ⟨p', s', _⟩ =>
      sess.set ⟨p', s'⟩
      if repMatches then
        -- Haskell replay: every matching report gets step_ok; the
        -- outer flow adds all_steps_done after the last trace
        sendMirror t Codec.MirrorMessage.stepOk
        if lastStep then
          sendMirror t Codec.MirrorMessage.allStepsDone
        return true
      else
        match diff with
        | StateDiff.stateMismatch expected actual' hints =>
            sendMirror t (Codec.MirrorMessage.stepMismatch expected actual'
              (hints.map convHint))
        | StateDiff.statesMatch => pure ()
        return false

/-- Replay one trace; @true@ = no mismatch (port of @MkReplayOne@). -/
private def replayOne (t : Shell.Transport.Transport) (sess : SessionRef)
    (trace : ItfTrace) (isLastTrace : Bool) : IO Bool := do
  let steps := traceSteps trace
  let n := steps.length
  let mut i := 0
  for stp in steps do
    let lastStep := isLastTrace && (i + 1 == n)
    let clean ← replayStep t sess stp lastStep
    if !clean then return false
    i := i + 1
  return true

/-- Replay all traces, stopping after the first mismatch (port of
@MkReplayAll@). Returns @true@ when every trace replayed cleanly. -/
private def replayAll (t : Shell.Transport.Transport) (sess : SessionRef)
    (traces : List ItfTrace) : IO Bool := do
  let n := traces.length
  let mut i := 0
  let mut clean := true
  for trace in traces do
    clean ← replayOne t sess trace (i + 1 == n)
    if !clean then break
    i := i + 1
  return clean

/-- The in-memory-traces replay flow shared by @register@ and
@register_traces@: @spec_validated@, replay, @all_steps_done@ on a clean
run (ports of @MkRunMirror@ / @MkRunMirrorWithTraces@). -/
private def runReplayFlow (t : Shell.Transport.Transport) (sess : SessionRef)
    (traces : List ItfTrace) : IO Unit := do
  sendMirror t (Codec.MirrorMessage.specValidated Codec.ValidateResult.valid)
  let clean ← replayAll t sess traces
  if clean then
    sendMirror t Codec.MirrorMessage.allStepsDone

/-- Dispatch one decoded client message (the register dispatch of
@RecvMsg@/step @exec@, with the oracle outcomes folded in). -/
private def dispatch (t : Shell.Transport.Transport) (sess : SessionRef)
    (orc : Oracles) (m : Codec.ClientMessage) : IO Unit := do
  match m with
  | .register cfg spec tcfg =>
      let r ← orc.generateTraces cfg spec tcfg
      match r with
      | .error e => sendMirror t (Codec.MirrorMessage.registerError e)
      | .ok traces =>
          let s ← sess.get
          match _root_.step ({ validationOk := true } : _root_.Oracles) s.2
              ClientMessage.register with
          | .ok _ =>
              sess.set ⟨Phase.stepping,
                ({ flow := Flow.traces } : Session Phase.stepping)⟩
          | .error e => sendError t (errText e)
          runReplayFlow t sess traces
  | .registerTraces cfg paths =>
      let r ← loadTraces paths
      match r with
      | .error e => sendMirror t (Codec.MirrorMessage.registerError e)
      | .ok parsed =>
          let pvs := if cfg.paramVars.isEmpty then [] else [cfg.paramVars]
          let traces := parsed.map (applyParamVars pvs)
          let s ← sess.get
          match _root_.step ({ validationOk := true } : _root_.Oracles) s.2
              ClientMessage.registerTraces with
          | .ok _ =>
              sess.set ⟨Phase.stepping,
                ({ flow := Flow.traces } : Session Phase.stepping)⟩
          | .error e => sendError t (errText e)
          runReplayFlow t sess traces
  | .registerGenTraces cfg _dest spec tcfg =>
      let r ← orc.generateTraceFiles cfg spec tcfg
      match r with
      | .error e => sendMirror t (Codec.MirrorMessage.registerError e)
      | .ok res => sendMirror t (Codec.MirrorMessage.genTracesDone res)
  | .registerValidate cfg bound spec =>
      if bound < 1 || bound > maxValidateBound then
        sendMirror t (Codec.MirrorMessage.registerError
          s!"validate bound {bound} outside allowed range 1..{maxValidateBound}")
      else
        let r ← orc.validateSpec cfg spec bound
        match r with
        | .error e => sendMirror t (Codec.MirrorMessage.registerError e)
        | .ok v => sendMirror t (Codec.MirrorMessage.specValidated v)
  | .registerExplore spec exports invariants maxSteps =>
      orc.runExplore t spec exports invariants maxSteps
  | .registerExploreSession spec exports invariants =>
      orc.runExploreSession t spec exports invariants
  | .registerValidateAsync _ _ _ | .registerGenTracesAsync _ _ _ _
  | .queryJob _ | .awaitJob _ _ | .cancelJob _ =>
      sendMirror t (Codec.MirrorMessage.registerError "async jobs arrive in Phase 4")
  | _ =>
      -- tag-level guard via the verified bridge: everything that is not
      -- an abstract Register/job tag is rejected here (reportState,
      -- explore commands mid-session, exploreDone)
      match Codec.protoClientTag m with
      | .register | .registerTraces | .registerGenTraces
      | .registerValidate | .registerExplore | .registerExploreSession
      | .registerValidateAsync | .registerGenTracesAsync
      | .queryJob | .awaitJob | .cancelJob => pure ()
      | _ => sendError t "Expected Register message"

/-- The session entry point: receive the first (register) message and
run its flow to completion (port of @Protocol.Mirror.run@ =
@exec . RecvMsg@). One sync register per process run, exactly like the
Haskell default stdio mode. -/
def run (t : Shell.Transport.Transport) (orc : Oracles) : IO Unit := do
  let sess ← IO.mkRef ⟨Phase.idle, ({ flow := Flow.none } : Session Phase.idle)⟩
  let line ← t.recv
  match line with
  | none => return () -- EOF before any message: quiet exit
  | some l =>
    match Lean.Json.parse l with
    | .error e => sendError t e
    | .ok j =>
      match Codec.decodeClient j with
      | .error e => sendError t e.msg
      | .ok m => dispatch t sess orc m

/-! ## The async session loop (Phase 4, design §5) -/

/-- One async-session dispatch; @false@ ends the session. -/
private def dispatchAsync (t : Shell.Transport.Transport) (sess : SessionRef)
    (orc : Oracles) (store : Shell.Jobs.JobStore) (m : Codec.ClientMessage) :
    IO Bool := do
  match m with
  | .registerValidateAsync cfg bound spec =>
      let r ← Shell.Jobs.submitValidateJob store cfg bound spec
      match r with
      | .error e => sendMirror t (Codec.MirrorMessage.registerError e)
      | .ok jid =>
          sendMirror t (Codec.MirrorMessage.jobAccepted jid.text .validate)
      return true
  | .registerGenTracesAsync cfg dest spec tcfg =>
      let r ← Shell.Jobs.submitGenTracesJob store cfg tcfg dest spec
      match r with
      | .error e => sendMirror t (Codec.MirrorMessage.registerError e)
      | .ok jid =>
          sendMirror t (Codec.MirrorMessage.jobAccepted jid.text .genTraces)
      return true
  | .queryJob jid =>
      let (ph, out?) ← Shell.Jobs.queryJob store { text := jid }
      match out? with
      | some o => sendMirror t (Codec.MirrorMessage.jobResult jid o)
      | none => sendMirror t (Codec.MirrorMessage.jobStatus jid (Shell.Jobs.toWirePhase ph))
      return true
  | .awaitJob jid timeout =>
      let r ← Shell.Jobs.awaitJob store { text := jid } timeout
      match r with
      | .ok o => sendMirror t (Codec.MirrorMessage.jobResult jid o)
      | .error _ =>
          let (ph, out?) ← Shell.Jobs.queryJob store { text := jid }
          match out? with
          | some o => sendMirror t (Codec.MirrorMessage.jobResult jid o)
          | none => sendMirror t (Codec.MirrorMessage.jobStatus jid (Shell.Jobs.toWirePhase ph))
      return true
  | .cancelJob jid =>
      Shell.Jobs.cancelJob store { text := jid }
      let (ph, _) ← Shell.Jobs.queryJob store { text := jid }
      sendMirror t (Codec.MirrorMessage.jobStatus jid (Shell.Jobs.toWirePhase ph))
      return true
  | _ =>
      -- tag-level dispatch via the verified bridge: sync registers run
      -- inline (one flow); anything else is unexpected mid-session
      match Codec.protoClientTag m with
      | .register | .registerTraces | .registerGenTraces
      | .registerValidate | .registerExplore | .registerExploreSession =>
          dispatch t sess orc m
      | _ => sendError t "unexpected message in async session"
      return true

/-- The async-session entry point (Haskell @runAsyncSession@): a
recv-dispatch loop over one transport with a job store. Async registers
fork (dedicated task) and return to the loop immediately; job operations
are answered from the store (terminal query/await replies with
@job_result@, per the async contract); a /sync/ register received
mid-session still runs to completion inline. Transport EOF or a decode
failure ends the session: a reply on the way out is best-effort and the
session's jobs are cancelled (Haskell @endSession@ semantics). -/
def runAsync (t : Shell.Transport.Transport) (orc : Oracles)
    (store : Shell.Jobs.JobStore) : IO Unit := do
  let sess ← IO.mkRef (⟨Phase.idle, ({ flow := Flow.none } : Session Phase.idle)⟩ : (p : Phase) × Session p)
  let mut loop := true
  while loop do
    let line ← t.recv
    match line with
    | none =>
        -- EOF: kill the session's jobs and end
        Shell.Jobs.closeJobStore store
        loop := false
    | some l =>
      match Lean.Json.parse l with
      | .error e =>
          sendError t e
          Shell.Jobs.closeJobStore store
          loop := false
      | .ok j =>
        match Codec.decodeClient j with
        | .error e =>
            sendError t e.msg
            Shell.Jobs.closeJobStore store
            loop := false
        | .ok m =>
            let keep ← dispatchAsync t sess orc store m
            loop := keep

end Shell.Mirror