import Core.Protocol
import Core.Jobs
import Shell.Jobs.Store
import Core.Trace
import Core.Diff
import Core.Value
import Codec.Json
import Codec.Bridge
import Codec.StrictJson
import Codec.ModelInterfaceDistributionJson
import Shell.Transport.Stdio
import Shell.ModelInterface.Evidence
import Shell.ModelInterface.Runtime
import Shell.Apalache.SpecSource
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

/-- Replay traces plus the typed structural evidence preserved from their raw
ITF metadata. Legacy callers may omit evidence; negotiated model-interface
resolution requires it. -/
structure TraceBundle where
  traces : List ItfTrace
  evidence : Option Core.ModelInterface.ModelEvidence := none
  /-- Present-but-malformed or mutually inconsistent strict evidence. Unlike
  absent evidence, this is a terminal preflight failure even under `prefer`. -/
  evidenceInvalid : Bool := false
  /-- Source content captured from the same acquired registration input. -/
  sources : List Core.ModelInterface.SourceDigest := []

/-- The effectful oracle surface of the mirror (everything that talks to
apalache or the explorer). Injected so @Core.Protocol@ stays pure. -/
structure Oracles where
  /- validateSpecIn: run a bounded validation. -/
  validateSpec : Codec.ApalacheConfig → Option Codec.SpecConfig → Nat →
    IO (Except String Codec.ValidateResult)
  /- generateTracesIn: produce in-memory traces for the replay flow. -/
  generateTraces : Codec.ApalacheConfig → Option Codec.SpecConfig → Codec.TraceConfig →
    /- Preserve compiler evidence/source identity only for negotiated runs. -/
    Bool →
    /- Permit a generated-file legacy parse only for an eligible `prefer`. -/
    Bool →
    IO (Except String TraceBundle)
  /- generateTraceFilesIn: produce trace files (register_trace_gen),
  honoring the client's optional destPath (copy + re-path, Haskell
  MkRunMirrorGenTraces). -/
  generateTraceFiles : Codec.ApalacheConfig → Option Codec.SpecConfig →
    Option String → Codec.TraceConfig →
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

private def sendSpecValidatedWithInterface (t : Shell.Transport.Transport)
    (reply : Option Codec.ModelInterfaceDistributionJson.ReplyV1) : IO Unit := do
  let base := Codec.encodeMirror (.specValidated .valid)
  match Codec.ModelInterfaceDistributionJson.insertSpecValidatedReply? base reply with
  | .ok json => t.send (Lean.Json.compress json)
  | .error e => throw (IO.userError e)

private def sendRegisterErrorWithInterface (t : Shell.Transport.Transport)
    (message : String)
    (failure : Option Codec.ModelInterfaceDistributionJson.FailureV1) : IO Unit := do
  let base := Codec.encodeMirror (.registerError message)
  match Codec.ModelInterfaceDistributionJson.insertRegisterErrorFailure? base failure with
  | .ok json => t.send (Lean.Json.compress json)
  | .error e => throw (IO.userError e)

private def sendError (t : Shell.Transport.Transport) (msg : String) : IO Unit :=
  sendMirror t (Codec.MirrorMessage.protocolError msg)

/-- Stable wire diagnostic for all untrusted JSON/decode failures. Raw strict
parser and codec diagnostics may contain attacker-controlled keys or values,
so they are intentionally retained only on the server side. -/
def invalidClientMessageError : String := "invalid client message"

private def errText : ProtocolError → String
  | .outOfOrder m => m

/-- Phase-3 stand-in: every apalache/explorer call fails with
@register_error@. @register_traces@ (which needs no oracle) is fully
functional with these oracles. -/
def stubOracles : Oracles where
  validateSpec _ _ _ :=
    pure (.error "apalache validate adapter lands in Phase 5")
  generateTraces _ _ _ _ _ :=
    pure (.error "apalache trace-generation adapter lands in Phase 5")
  generateTraceFiles _ _ _ _ :=
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

/-- Maximum size of one on-disk ITF JSON artifact. Disk traces are not JSONL
protocol messages and may legitimately exceed the transport's 65,535-byte
line bound, but remain bounded independently for resource safety. -/
def maxItfTraceArtifactBytes : Nat := 16 * 1024 * 1024

/-- Strict JSON limits for on-disk ITF artifacts. Only the byte budget differs
from wire JSON; UTF-8, duplicate-key, syntax, and depth checks are retained. -/
def itfTraceArtifactLimits : Codec.StrictJson.Limits :=
  { Codec.StrictJson.defaultLimits with maxBytes := maxItfTraceArtifactBytes }

private partial def readBoundedBytesAux (handle : IO.FS.Handle)
    (limit : Nat) (accumulator : ByteArray) : IO (Except String ByteArray) := do
  if accumulator.size > limit then
    return .error s!"file exceeds {limit} bytes"
  let remainingProbe := limit + 1 - accumulator.size
  let requestSize := min 65536 remainingProbe
  let chunk ← handle.read requestSize.toUSize
  if chunk.isEmpty then return .ok accumulator
  readBoundedBytesAux handle limit (accumulator.append chunk)

/-- Read at most `limit` bytes plus one overflow probe, so a hostile disk
artifact cannot allocate without bound before strict JSON sees it. -/
private def readBoundedBytes (path : String) (limit : Nat) :
    IO (Except String ByteArray) := do
  try
    let handle ← IO.FS.Handle.mk path .read
    readBoundedBytesAux handle limit ByteArray.empty
  catch error =>
    return .error s!"cannot read {path}: {error}"

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

private def validateRawTraceShape (j : Lean.Json) : Except String Unit := do
  let vars ← jStrsOf (← j.getObjVal? "vars")
  let constants ← match j.getObjVal? "params" with
    | .ok value => jStrsOf value
    | .error _ => .ok []
  let states ← match ← j.getObjVal? "states" with
    | .arr values => .ok values.toList
    | _ => .error "ItfTrace.states: expected array"
  for state in states do
    let entries ← jObjEntries state
    let names := entries.map Prod.fst
    match entries.lookup "action_taken" with
    | some (.str action) =>
        if action.isEmpty then throw "action_taken must not be empty"
    | _ => throw "action_taken must be a nonempty string"
    match names.find? (fun name =>
        !vars.contains name && !constants.contains name && !name.startsWith "#") with
    | some name => throw s!"undeclared state key: {name}"
    | none => pure ()

/-- Read and parse one ITF trace file (Haskell @readTrace@). -/
def readItfTrace (path : String) : IO (Except String ItfTrace) := do
  let bytes ← match ← readBoundedBytes path maxItfTraceArtifactBytes with
    | .ok bytes => pure bytes
    | .error error => return .error error
  let content ← match String.fromUTF8? bytes with
    | some content => pure content
    | none => return .error s!"{path}: trace is not valid UTF-8"
  match Lean.Json.parse content with
  | .error e => return .error s!"{path}: {e}"
  | .ok j => return parseItfTrace j

/-- Read one trace once, preserving strict typed metadata for the compiler. -/
private def parseItfTraceBundleBytes (path : String) (content : ByteArray) :
    Except String TraceBundle := do
  match Codec.StrictJson.parseBytes content itfTraceArtifactLimits with
  | .error e => throw s!"{path}: {e}"
  | .ok j =>
      match parseItfTrace j with
      | .error e => throw s!"{path}: {e}"
      | .ok trace =>
          let rawShapeOk := (validateRawTraceShape j).isOk
          let varTypesPresent :=
            match j.getObjVal? "#meta" with
            | .ok metadata => (metadata.getObjVal? "varTypes").isOk
            | .error _ => false
          let evidenceResult := Shell.ModelInterface.Evidence.fromJson j path
          let evidence := if rawShapeOk then evidenceResult.toOption else none
          let evidenceInvalid := !rawShapeOk ||
            (varTypesPresent && !evidenceResult.isOk)
          return { traces := [trace], evidence, evidenceInvalid }

/-- Read one trace once, preserving strict typed metadata for the compiler. -/
def readItfTraceBundle (path : String) : IO (Except String TraceBundle) := do
  let content ← match ← readBoundedBytes path maxItfTraceArtifactBytes with
    | .ok content => pure content
    | .error error => return .error error
  return parseItfTraceBundleBytes path content

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

/-- Aggregate resource bounds for a negotiation-enabled trace registration.
They are deliberately separate from the legacy loader: a registration without
`modelInterface` keeps the historical expansion and parsing behavior. -/
structure NegotiatedTraceLoadLimits where
  maxFiles : Nat
  maxAggregateBytes : Nat
  maxTraces : Nat
  maxStates : Nat
  deriving Repr, DecidableEq

/-- Version-1 defaults. The per-file 16 MiB bound remains independently
enforced, while this profile caps a whole directory/multi-path registration. -/
def negotiatedTraceLoadLimitsV1 : NegotiatedTraceLoadLimits := {
  maxFiles := 256
  maxAggregateBytes := 64 * 1024 * 1024
  maxTraces := 256
  maxStates := 65536
}

/-- Classified result of negotiation-only aggregate admission. The
classification is used by `prefer` to distinguish an optional resource budget
from malformed evidence. The detailed message is never placed on the wire. -/
inductive NegotiatedTraceLoadFailure where
  | resourceLimit (message : String)
  | invalidInput (message : String)
  deriving Repr

def NegotiatedTraceLoadFailure.message : NegotiatedTraceLoadFailure → String
  | .resourceLimit message | .invalidInput message => message

private def negotiatedTraceLimitError (resource : String)
    (actual limit : Nat) : String :=
  s!"negotiated trace {resource} limit exceeded ({actual} > {limit})"

/-- Resolve and sort every directory before opening any trace. This makes the
file-count admission decision deterministic and prevents a large directory
from causing partial trace parsing before its registration is rejected. -/
private def expandNegotiatedTracePaths (paths : List String) (maxFiles : Nat) :
    IO (Except NegotiatedTraceLoadFailure (List String)) := do
  let mut files := []
  for path in paths do
    match ← expandTracePath path with
    | .error error => return .error (.invalidInput error)
    | .ok expanded =>
        let count := files.length + expanded.length
        if count > maxFiles then
          return .error (.resourceLimit
            (negotiatedTraceLimitError "file-count" count maxFiles))
        files := files ++ expanded
  return .ok files

/-- Load replay traces and preserve the first compatible typed evidence block.
All concrete traces are still parsed by the existing verified value codec.
The aggregate byte, trace, and state budgets are checked before model-interface
resolution is attempted. -/
def loadTraceBundleWithLimitsClassified (paths : List String)
    (limits : NegotiatedTraceLoadLimits) :
    IO (Except NegotiatedTraceLoadFailure TraceBundle) := do
  let files ← match ← expandNegotiatedTracePaths paths limits.maxFiles with
    | .ok files => pure files
    | .error error => return .error error
  let mut traces := []
  let mut evidence : Option Core.ModelInterface.ModelEvidence := none
  let mut evidenceConflict := false
  let mut evidenceIncomplete := false
  let mut evidencePresent := false
  let mut evidenceInvalid := false
  let mut aggregateBytes := 0
  let mut aggregateStates := 0
  for path in files do
    let remainingBytes := limits.maxAggregateBytes - aggregateBytes
    let readLimit := min maxItfTraceArtifactBytes remainingBytes
    let content ← match ← readBoundedBytes path readLimit with
      | .ok content => pure content
      | .error error =>
          if remainingBytes < maxItfTraceArtifactBytes then
            return .error (.resourceLimit
              (negotiatedTraceLimitError "aggregate-byte"
                (limits.maxAggregateBytes + 1) limits.maxAggregateBytes))
          else
            return .error (.invalidInput error)
    aggregateBytes := aggregateBytes + content.size
    if aggregateBytes > limits.maxAggregateBytes then
      return .error (.resourceLimit
        (negotiatedTraceLimitError "aggregate-byte"
          aggregateBytes limits.maxAggregateBytes))
    let bundle ← match parseItfTraceBundleBytes path content with
      | .ok bundle => pure bundle
      | .error error => return .error (.invalidInput error)
    let traceCount := traces.length + bundle.traces.length
    if traceCount > limits.maxTraces then
      return .error (.resourceLimit
        (negotiatedTraceLimitError "trace-count"
          traceCount limits.maxTraces))
    let bundleStates := bundle.traces.foldl
      (fun count trace => count + trace.traceStates.length) 0
    aggregateStates := aggregateStates + bundleStates
    if aggregateStates > limits.maxStates then
      return .error (.resourceLimit
        (negotiatedTraceLimitError "state-count"
          aggregateStates limits.maxStates))
    traces := traces ++ bundle.traces
    if bundle.evidenceInvalid then evidenceInvalid := true
    if bundle.evidence.isNone then evidenceIncomplete := true
    else evidencePresent := true
    if !evidenceConflict then
      match evidence, bundle.evidence with
      | none, some candidate => evidence := some candidate
      | some accepted, some candidate =>
          if !Shell.ModelInterface.Evidence.compatible accepted candidate then
            evidence := none
            evidenceConflict := true
            evidenceInvalid := true
      | _, _ => pure ()
  if evidenceIncomplete then evidence := none
  if evidenceIncomplete && evidencePresent then evidenceInvalid := true
  return .ok { traces, evidence, evidenceInvalid }

/-- Compatibility wrapper retaining the historical string error surface for
focused callers while the session and generated-trace path use the classified
form above. -/
def loadTraceBundleWithLimits (paths : List String)
    (limits : NegotiatedTraceLoadLimits) : IO (Except String TraceBundle) := do
  return (← loadTraceBundleWithLimitsClassified paths limits).mapError (·.message)

/-- Production negotiation-enabled trace loader. -/
def loadTraceBundle (paths : List String) : IO (Except String TraceBundle) :=
  loadTraceBundleWithLimits paths negotiatedTraceLoadLimitsV1

private def loadRegistrationTraceBundle
    (interfaceWork : Bool)
    (request : Option Codec.ModelInterfaceDistributionJson.RequestV1)
    (paths : List String) : IO (Except String TraceBundle) :=
  let legacy : IO (Except String TraceBundle) := do
      match ← loadTraces paths with
      | .error error => return .error error
      | .ok traces => return .ok ({ traces } : TraceBundle)
  if !interfaceWork then legacy
  else do
    match ← loadTraceBundleWithLimitsClassified paths negotiatedTraceLoadLimitsV1 with
    | .ok bundle => return .ok bundle
    | .error (.invalidInput error) => return .error error
    | .error (.resourceLimit error) =>
        match request with
        | some request =>
            if request.policy == .prefer then legacy else return .error error
        | none => legacy

private def normalizeSourceClosure
    (request : Option Codec.ModelInterfaceDistributionJson.RequestV1)
    (rootLogicalPath : Option String)
    (sources : List Core.ModelInterface.SourceDigest) :
    Option (List Core.ModelInterface.SourceDigest) :=
  match request with
  | none => some []
  | some request =>
      match request.contract with
      | .digest _ => none
      | .inline contract =>
          let rootSource := rootLogicalPath.bind fun path =>
            sources.find? (fun source => source.logicalPath == path)
          if rootSource.any (fun source =>
              source.moduleName == contract.model.moduleName) then
            some (sources.map fun source =>
              if rootLogicalPath == some source.logicalPath then
                { source with logicalPath := contract.model.source }
              else source)
          else none

private def registrationRootLogicalPath (cfg : Codec.ApalacheConfig)
    (spec : Option Codec.SpecConfig) : Option String :=
  match spec with
  | some inline => inline.sources.head?.bind fun source =>
      (Shell.Apalache.SpecSource.moduleName source).toOption.map (· ++ ".tla")
  | none => (cfg.specPath : System.FilePath).fileName

private def registrationSourceDigests
    (cfg : Codec.ApalacheConfig)
    (request : Option Codec.ModelInterfaceDistributionJson.RequestV1) :
    IO (List Core.ModelInterface.SourceDigest) := do
  let some request := request | return []
  let .inline _ := request.contract | return []
  -- `contract.model.source` is a logical identity, never an additional
  -- server filesystem read capability. Only the already-registered specPath
  -- may be opened here.
  match ← Shell.Apalache.SpecSource.borrowedSourceDigests cfg.specPath with
  | .ok sources => return (normalizeSourceClosure (some request)
      (registrationRootLogicalPath cfg none) sources).getD []
  | .error _ => return []

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
  let actual? ← match line with
    | none =>
        sendError t "connection closed while expecting report_state"
        pure none
    | some l =>
        match Codec.StrictJson.parseString l with
        | .error _ =>
            sendError t invalidClientMessageError
            pure none
        | .ok j =>
            match Codec.decodeClient j with
            | .error _ =>
                sendError t invalidClientMessageError
                pure none
            | .ok (Codec.ClientMessage.reportState st) => pure (some st)
            | .ok _ =>
                sendError t "expected report_state"
                pure none
  let some actual := actual? | return false
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
@register_traces@: @spec_validated@, replay (ports of @MkRunMirror@ /
@MkRunMirrorWithTraces@). The @all_steps_done@ tail is emitted by
replayStep on the LAST matching step (MirrorRecvReportAllDone) — t28
removed a duplicate wrapper emission here that sent it a second time
on a clean run (27 messages vs Haskell's 26; the TLA+ model reports
all-done exactly once, via the last-step handler). -/
private def runReplayFlow (t : Shell.Transport.Transport) (sess : SessionRef)
    (traces : List ItfTrace)
    (interfaceReply : Option Codec.ModelInterfaceDistributionJson.ReplyV1 := none) : IO Unit := do
  sendSpecValidatedWithInterface t interfaceReply
  let _ ← replayAll t sess traces

/-- Admit a negotiation-enabled registration failure through the pure protocol
machine before sending its bounded structured response. The internal oracle or
filesystem diagnostic is deliberately not accepted here: negotiated remote
failures expose only the stable classification. -/
private def rejectNegotiatedRegistration
    (t : Shell.Transport.Transport) (sess : SessionRef)
    (request : Codec.ModelInterfaceDistributionJson.RequestV1)
    (registration : _root_.ClientMessage) : IO Unit := do
  let negotiation := Shell.ModelInterface.Runtime.rejectPreflight
    (some request) []
  let current ← sess.get
  match _root_.step ({ validationOk := false } : _root_.Oracles)
      current.2 registration with
  | .ok ⟨phase, next, _⟩ =>
      sess.set ⟨phase, next⟩
      sendRegisterErrorWithInterface t
        "interface_trace_preflight_failed" negotiation.failure
  | .error error => sendError t (errText error)

/-- Dispatch one decoded client message (the register dispatch of
@RecvMsg@/step @exec@, with the oracle outcomes folded in). -/
private def dispatch (t : Shell.Transport.Transport) (sess : SessionRef)
    (orc : Oracles) (m : Codec.ClientMessage)
    (interfaceRequest : Option Codec.ModelInterfaceDistributionJson.RequestV1 := none)
    (interfaceAccess : Shell.ModelInterface.Runtime.Access)
    (interfaceScope : Shell.ModelInterface.Runtime.AuthorizationScope)
    (interfaceService : Shell.ModelInterface.Runtime.Service) :
    IO Unit := do
  match m with
  | .register cfg spec tcfg =>
      let interfaceWork := Shell.ModelInterface.Runtime.mayPerformResolution
        interfaceAccess interfaceRequest
      let allowResourceFallback := interfaceWork && interfaceRequest.any
        (fun request => request.policy == .prefer)
      let r ← orc.generateTraces cfg spec tcfg interfaceWork
        allowResourceFallback
      match r with
      | .error error =>
          if !interfaceWork then
            -- No interface work was admitted, so preserve the underlying
            -- legacy oracle failure even when an optional/ineligible request
            -- field was present.
            sendMirror t (Codec.MirrorMessage.registerError error)
          else
            match interfaceRequest with
            | some request =>
                rejectNegotiatedRegistration t sess request .register
            | none => sendMirror t (Codec.MirrorMessage.registerError error)
      | .ok bundle =>
          let configuredParamVar := if cfg.paramVars.isEmpty then none else some cfg.paramVars
          let normalizedSources :=
            if interfaceWork then normalizeSourceClosure interfaceRequest
              (registrationRootLogicalPath cfg spec) bundle.sources
            else some []
          let sources := normalizedSources.getD []
          let evidence :=
            if interfaceWork && (normalizedSources.isNone || sources.isEmpty) then none
            else bundle.evidence
          let cached ← Shell.ModelInterface.Runtime.resolveCached interfaceService
            interfaceScope interfaceRequest evidence configuredParamVar sources
            (access := interfaceAccess)
          let negotiation :=
            if interfaceWork && bundle.evidenceInvalid then
              Shell.ModelInterface.Runtime.rejectPreflight interfaceRequest []
            else
              match interfaceRequest, cached.resolution.lock with
              | some _, some lock =>
                  if !cached.resolution.decision.interfaceOk then cached.resolution
                  else
                    let checked := Core.ModelInterface.preflight lock bundle.traces
                    if checked.hasErrors then
                      Shell.ModelInterface.Runtime.rejectPreflight interfaceRequest
                        checked.diagnostics
                    else cached.resolution
              | _, _ => cached.resolution
          let s ← sess.get
          match _root_.step
              ({ validationOk := negotiation.decision.interfaceOk } : _root_.Oracles) s.2
              ClientMessage.register with
          | .ok ⟨p', s', _⟩ =>
              sess.set ⟨p', s'⟩
              if negotiation.decision.interfaceOk then
                runReplayFlow t sess bundle.traces negotiation.reply
              else
                let message := negotiation.failure.map (·.code) |>.getD
                  "model interface admission failed"
                sendRegisterErrorWithInterface t message negotiation.failure
          | .error e => sendError t (errText e)
  | .registerTraces cfg paths =>
      let interfaceWork := Shell.ModelInterface.Runtime.mayPerformResolution
        interfaceAccess interfaceRequest
      -- Aggregate/strict trace admission is optional interface work. Disabled,
      -- unsupported, and otherwise ineligible requests retain the legacy
      -- loader. A supported `prefer` request may also fall back to it after a
      -- negotiation-only resource-limit failure.
      let r ← loadRegistrationTraceBundle interfaceWork interfaceRequest paths
      match r with
      | .error e =>
          if !interfaceWork then
            sendMirror t (Codec.MirrorMessage.registerError e)
          else
            match interfaceRequest with
            | some request =>
                rejectNegotiatedRegistration t sess request .registerTraces
            | none => sendMirror t (Codec.MirrorMessage.registerError e)
      | .ok bundle =>
          let pvs := if cfg.paramVars.isEmpty then [] else [cfg.paramVars]
          let traces := bundle.traces.map (applyParamVars pvs)
          let configuredParamVar := if cfg.paramVars.isEmpty then none else some cfg.paramVars
          let sources ← if interfaceWork then
              registrationSourceDigests cfg interfaceRequest
            else pure []
          let evidence :=
            if interfaceRequest.isSome && sources.isEmpty then none
            else bundle.evidence
          let cached ← Shell.ModelInterface.Runtime.resolveCached interfaceService
            interfaceScope interfaceRequest evidence configuredParamVar sources
            (access := interfaceAccess)
          let negotiation :=
            if interfaceWork && bundle.evidenceInvalid then
              Shell.ModelInterface.Runtime.rejectPreflight interfaceRequest []
            else
              match interfaceRequest, cached.resolution.lock with
              | some _, some lock =>
                  if !cached.resolution.decision.interfaceOk then cached.resolution
                  else
                    let checked := Core.ModelInterface.preflight lock traces
                    if checked.hasErrors then
                      Shell.ModelInterface.Runtime.rejectPreflight interfaceRequest
                        checked.diagnostics
                    else cached.resolution
              | _, _ => cached.resolution
          let s ← sess.get
          match _root_.step
              ({ validationOk := negotiation.decision.interfaceOk } : _root_.Oracles) s.2
              ClientMessage.registerTraces with
          | .ok ⟨p', s', _⟩ =>
              sess.set ⟨p', s'⟩
              if negotiation.decision.interfaceOk then
                runReplayFlow t sess traces negotiation.reply
              else
                let message := negotiation.failure.map (·.code) |>.getD
                  "model interface admission failed"
                sendRegisterErrorWithInterface t message negotiation.failure
          | .error e => sendError t (errText e)
  | .registerGenTraces cfg _dest spec tcfg =>
      let r ← orc.generateTraceFiles cfg spec _dest tcfg
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
      orc.runExplore t spec invariants exports maxSteps
  | .registerExploreSession spec exports invariants =>
      orc.runExploreSession t spec invariants exports
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
def run (t : Shell.Transport.Transport) (orc : Oracles)
    (interfaceAccess : Shell.ModelInterface.Runtime.Access := .descriptor)
    (interfaceScope : Shell.ModelInterface.Runtime.AuthorizationScope :=
      Shell.ModelInterface.Runtime.localAuthorizationScope)
    (interfaceService : Option Shell.ModelInterface.Runtime.Service := none) : IO Unit := do
  let interfaceService ← match interfaceService with
    | some service => pure service
    | none => Shell.ModelInterface.Runtime.Service.new
  let sess ← IO.mkRef ⟨Phase.idle, ({ flow := Flow.none } : Session Phase.idle)⟩
  let line ← t.recv
  match line with
  | none => return () -- EOF before any message: quiet exit
  | some l =>
    match Codec.StrictJson.parseString l with
    | .error _ => sendError t invalidClientMessageError
    | .ok j =>
      match Codec.ModelInterfaceDistributionJson.extractRegistrationRequest? j with
      | .error _ => sendError t invalidClientMessageError
      | .ok interfaceRequest =>
        match Codec.decodeClient j with
        | .error _ => sendError t invalidClientMessageError
        | .ok m =>
            dispatch t sess orc m interfaceRequest interfaceAccess
              interfaceScope interfaceService

/-! ## The async session loop (Phase 4, design §5) -/

/-- One async-session dispatch; @false@ ends the session. The session
tracks the ids it submitted so its end can cancel/evict exactly its own
jobs (Haskell @endSession@) even when the store is shared by a whole
server process (t31). -/
private def dispatchAsync (t : Shell.Transport.Transport) (sess : SessionRef)
    (orc : Oracles) (store : Shell.Jobs.JobStore)
    (mine : IO.Ref (List JobId)) (m : Codec.ClientMessage)
    (interfaceRequest : Option Codec.ModelInterfaceDistributionJson.RequestV1 := none)
    (interfaceAccess : Shell.ModelInterface.Runtime.Access)
    (interfaceScope : Shell.ModelInterface.Runtime.AuthorizationScope)
    (interfaceService : Shell.ModelInterface.Runtime.Service) :
    IO Bool := do
  match m with
  | .registerValidateAsync cfg bound spec =>
      let r ← Shell.Jobs.submitValidateJob store cfg bound spec
      match r with
      | .error e => sendMirror t (Codec.MirrorMessage.registerError e)
      | .ok jid =>
          mine.modify (fun ids => ids ++ [jid])
          sendMirror t (Codec.MirrorMessage.jobAccepted jid.text .validate)
      return true
  | .registerGenTracesAsync cfg dest spec tcfg =>
      let r ← Shell.Jobs.submitGenTracesJob store cfg tcfg dest spec
      match r with
      | .error e => sendMirror t (Codec.MirrorMessage.registerError e)
      | .ok jid =>
          mine.modify (fun ids => ids ++ [jid])
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
          dispatch t sess orc m interfaceRequest interfaceAccess interfaceScope
            interfaceService
      | _ => sendError t "unexpected message in async session"
      let current ← sess.get
      return current.1 != .done

/-- The async-session entry point (Haskell @runAsyncSession@): a
recv-dispatch loop over one transport with a job store. Async registers
fork (dedicated task) and return to the loop immediately; job operations
are answered from the store (terminal query/await replies with
@job_result@, per the async contract); a /sync/ register received
mid-session still runs to completion inline. Transport EOF or a decode
failure ends the session: a reply on the way out is best-effort and the
session's jobs are cancelled (Haskell @endSession@ semantics). -/
def runAsync (t : Shell.Transport.Transport) (orc : Oracles)
    (store : Shell.Jobs.JobStore)
    (interfaceAccess : Shell.ModelInterface.Runtime.Access := .descriptor)
    (interfaceScope : Shell.ModelInterface.Runtime.AuthorizationScope :=
      Shell.ModelInterface.Runtime.localAuthorizationScope)
    (interfaceService : Option Shell.ModelInterface.Runtime.Service := none) : IO Unit := do
  let interfaceService ← match interfaceService with
    | some service => pure service
    | none => Shell.ModelInterface.Runtime.Service.new
  let sess ← IO.mkRef (⟨Phase.idle, ({ flow := Flow.none } : Session Phase.idle)⟩ : (p : Phase) × Session p)
  -- t31: the store may be shared by a whole server process; session end
  -- cancels + evicts exactly THIS session's jobs (the image of the
  -- per-session Haskell store disappearing), never other sessions' jobs
  let mine ← IO.mkRef ([] : List JobId)
  let endSession : IO Unit := do
    let ids ← mine.get
    for jid in ids do
      Shell.Jobs.cancelJob store jid
      Shell.Jobs.evictJob store jid
  let mut loop := true
  while loop do
    let line ← t.recv
    match line with
    | none =>
        -- EOF: kill the session's jobs and end
        endSession
        loop := false
    | some l =>
      match Codec.StrictJson.parseString l with
      | .error _ =>
          sendError t invalidClientMessageError
          endSession
          loop := false
      | .ok j =>
        match Codec.ModelInterfaceDistributionJson.extractRegistrationRequest? j with
        | .error _ =>
            sendError t invalidClientMessageError
            endSession
            loop := false
        | .ok interfaceRequest =>
          match Codec.decodeClient j with
          | .error _ =>
              sendError t invalidClientMessageError
              endSession
              loop := false
          | .ok m =>
              let keep ← dispatchAsync t sess orc store mine m interfaceRequest
                interfaceAccess interfaceScope interfaceService
              loop := keep

end Shell.Mirror
