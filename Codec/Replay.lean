import Core.Replay
import Codec.Json
import Codec.ModelInterfaceDistributionJson

/-! The JSON boundary of the synchronous replay program. -/
namespace Codec.Replay

def invalidClientMessageError : String := "invalid client message"

private def convPathSeg : _root_.PathSeg → Codec.PathSeg
  | .field s => .field s
  | .index i => .index i

private def convPath (p : _root_.Path) : List Codec.PathSeg := p.map convPathSeg

/-- Convert a core diff hint to its wire form. -/
def convHint : _root_.DiffHint → Codec.DiffHint
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

/-- Decode the input of a single replay read, including transport EOF. -/
def decodeInput : Option String → Core.Replay.Input
  | none => .error "connection closed while expecting report_state"
  | some line => do
    let json ← (Codec.StrictJson.parseString line).mapError (fun _ => invalidClientMessageError)
    let message ← (Codec.decodeClient json).mapError (fun _ => invalidClientMessageError)
    match message with
    | .reportState state => .ok state
    | _ => .error "expected report_state"

/-- The fields required of a report, independently of the replay dispatcher.
The state object is decoded as a record of bindings, including ordinary keys. -/
def ReportFields (json : Lean.Json) (r : ValueMap) : Prop :=
  jStr json "proto_step" = .ok "report_state" ∧
    ∃ fields, json.getObjVal? "state" = .ok (.obj fields) ∧
      decRecordF defaultFuel fields.toList = .ok r

private theorem bindOk {x : Dec α} {f : α → Dec β} {b : β} :
    (x >>= f) = .ok b ↔ ∃ a, x = .ok a ∧ f a = .ok b := by
  cases x <;> simp [bind, Except.bind]

theorem decodeClient_report_iff (json : Lean.Json) (r : ValueMap) :
    decodeClient json = .ok (.reportState r) ↔ ReportFields json r := by
  constructor
  · intro decoded
    unfold decodeClient at decoded
    split at decoded <;> simp [bindOk, derr, pure, Except.pure] at decoded
    rename_i tagEq
    refine ⟨tagEq, ?_⟩
    change reqField json "state" _ = .ok r at decoded
    unfold reqField jOptField at decoded
    cases h : json.getObjVal? "state" with
    | error => simp [h] at decoded
    | ok val =>
      cases val <;> simp [h, derr] at decoded ⊢
      all_goals first | contradiction | assumption
  · rintro ⟨tagEq, fields, stateEq, decoded⟩
    unfold decodeClient
    simp only [tagEq]
    apply bindOk.mpr
    refine ⟨r, ?_, rfl⟩
    change reqField json "state" _ = .ok r
    simp only [reqField, jOptField, stateEq]
    exact decoded

/-- The possible outcomes of a framed replay read. Only a strictly parsed
report with the required tag and state fields can supply a comparison. -/
inductive Read : Option String → Core.Replay.Input → Prop where
  | eof : Read none (.error "connection closed while expecting report_state")
  | invalidJson (bad : StrictJson.parseString line = .error err) :
      Read (some line) (.error "invalid client message")
  | invalidMessage (parsed : StrictJson.parseString line = .ok json)
      (bad : decodeClient json = .error err) : Read (some line) (.error "invalid client message")
  | unexpected (parsed : StrictJson.parseString line = .ok json)
      (decoded : decodeClient json = .ok message) (other : ∀ r, message ≠ .reportState r) :
      Read (some line) (.error "expected report_state")
  | report (parsed : StrictJson.parseString line = .ok json) (fields : ReportFields json r) :
      Read (some line) (.ok r)

theorem read_decodeInput (raw : Option String) : Read raw (decodeInput raw) := by
  cases raw with
  | none => exact .eof
  | some line =>
    cases hp : StrictJson.parseString line with
    | error err => simpa [decodeInput, hp, Except.mapError, bind, Except.bind, invalidClientMessageError] using Read.invalidJson hp
    | ok json =>
      cases hd : decodeClient json with
      | error err => simpa [decodeInput, hp, hd, Except.mapError, bind, Except.bind, invalidClientMessageError] using Read.invalidMessage hp hd
      | ok message =>
        cases message <;> simp [decodeInput, hp, hd, Except.mapError, bind, Except.bind]
        all_goals first
          | exact .report hp ((decodeClient_report_iff _ _).mp hd)
          | exact .unexpected hp hd (by intro r; simp)

/-- Encode the complete message selected by the replay program. -/
def encodeOutput (reply : Option ModelInterfaceDistributionJson.ReplyV1) :
    Core.Replay.Output → Except String Lean.Json
  | .validated => ModelInterfaceDistributionJson.insertSpecValidatedReply?
      (encodeMirror (.specValidated .valid)) reply
  | .initialState action vars => .ok (encodeMirror (.initialState action vars))
  | .nextStep action params => .ok (encodeMirror (.nextStep action params))
  | .stepOk => .ok (encodeMirror .stepOk)
  | .allStepsDone => .ok (encodeMirror .allStepsDone)
  | .mismatch expected actual hints =>
    .ok (encodeMirror (.stepMismatch expected actual (hints.map convHint)))
  | .protocolError message => .ok (encodeMirror (.protocolError message))

def tag : Core.Replay.Output → String
  | .validated => "spec_validated"
  | .initialState .. => "initial_state"
  | .nextStep .. => "next_step"
  | .stepOk => "step_ok"
  | .allStepsDone => "all_steps_done"
  | .mismatch .. => "step_mismatch"
  | .protocolError .. => "protocol_error"

/-- Expected wire hint for a core difference. Path order, index, kind, and
the presence and orientation of actual and expected values are significant. -/
def wireHint (h : _root_.DiffHint) : Lean.Json :=
  let (kind, actual, expected) : DiffKind × Option Value × Option Value := match h with
    | .hValueMismatch _ e a => (.valueMismatch, some a, some e)
    | .hTypeMismatch _ e a => (.typeMismatch, some a, some e)
    | .hMissing _ e => (.missing, none, some e)
    | .hExtra _ a => (.extra, some a, none)
    | .hMissingElem _ e => (.missingElem, none, some e)
    | .hExtraElem _ a => (.extraElem, some a, none)
    | .hTruncated _ => (.truncated, none, none)
  let path := (hintPath h).map fun segment => match segment with
    | .field name => Codec.PathSeg.field name
    | .index n => Codec.PathSeg.index n
  jDiffHint { kind, path, actual, expected }

theorem convHint_wire (h : _root_.DiffHint) : jDiffHint (convHint h) = wireHint h := by
  cases h <;> rfl

/-- The replay wire objects in the interface contract. The general value and
hint codecs supply their wire representations. -/
def wireObject (reply : Option ModelInterfaceDistributionJson.ReplyV1) :
    Core.Replay.Output → Lean.Json
  | .validated =>
    let extension := reply.toList.map fun r => ("modelInterface", ModelInterfaceDistributionJson.encodeReply r)
    .mkObj (extension ++ [("proto_step", .str "spec_validated"), ("result", .str "valid")])
  | .initialState a vars => .mkObj [("action", .str a), ("proto_step", .str "initial_state"),
      ("state", jStateMap vars)]
  | .nextStep a params => .mkObj [("action", .str a), ("parameters", jStateMap params),
      ("proto_step", .str "next_step")]
  | .stepOk => .mkObj [("proto_step", .str "step_ok")]
  | .allStepsDone => .mkObj [("proto_step", .str "all_steps_done")]
  | .mismatch expected actual hints =>
    .mkObj [("actual", jStateMap actual), ("expected", jStateMap expected),
      ("hints", .arr (hints.map wireHint).toArray), ("proto_step", .str "step_mismatch")]
  | .protocolError message => .mkObj [("error", .str message), ("proto_step", .str "protocol_error")]

def OutputAllowed (reply : Option ModelInterfaceDistributionJson.ReplyV1) :
    Core.Replay.Output → Prop
  | .validated => ∀ r ∈ reply, ModelInterfaceDistributionJson.validateReply r = .ok ()
  | _ => True

/-- Both directions specify successful encoding, so rejecting every output
would also violate this contract. -/
theorem encodeOutput_ok_iff (reply : Option ModelInterfaceDistributionJson.ReplyV1)
    (output : Core.Replay.Output) (json : Lean.Json) :
    encodeOutput reply output = .ok json ↔ OutputAllowed reply output ∧ wireObject reply output = json := by
  cases output with
  | validated =>
    cases reply with
    | none => simp [OutputAllowed, encodeOutput, ModelInterfaceDistributionJson.insertSpecValidatedReply?, wireObject, encodeMirror, jValidateResult]
    | some r =>
      cases hv : ModelInterfaceDistributionJson.validateReply r with
      | error err => simp [encodeOutput, ModelInterfaceDistributionJson.insertSpecValidatedReply?, hv,
          bind, Except.bind, OutputAllowed]
      | ok u =>
        cases u
        simp [encodeOutput, ModelInterfaceDistributionJson.insertSpecValidatedReply?, hv,
          bind, Except.bind, OutputAllowed]
        change (Except.ok (ε := String) (wireObject (some r) .validated) = .ok json) ↔ _
        simp
  | mismatch => simp [OutputAllowed, encodeOutput, wireObject, encodeMirror, List.map_map,
      Function.comp_def, convHint_wire]
  | _ => simp [OutputAllowed, encodeOutput, wireObject, encodeMirror]

theorem wireObject_tag (reply : Option ModelInterfaceDistributionJson.ReplyV1)
    (output : Core.Replay.Output) :
    (wireObject reply output).getObjVal? "proto_step" = .ok (.str (tag output)) := by
  cases output <;> cases reply <;> rfl

theorem encodeOutput_tag (reply : Option ModelInterfaceDistributionJson.ReplyV1)
    (output : Core.Replay.Output) (json : Lean.Json) (encoded : encodeOutput reply output = .ok json) :
    json.getObjVal? "proto_step" = .ok (.str (tag output)) := by
  rw [← ((encodeOutput_ok_iff _ _ _).mp encoded).2]
  exact wireObject_tag _ _

/-- A successfully encoded replay object carries the completion tag exactly
for the completion event, including sessions with negotiated metadata. -/
theorem completion_tag_iff (reply : Option ModelInterfaceDistributionJson.ReplyV1)
    (output : Core.Replay.Output) (json : Lean.Json) (encoded : encodeOutput reply output = .ok json) :
    json.getObjVal? "proto_step" = .ok (.str "all_steps_done") ↔ output = .allStepsDone := by
  rw [encodeOutput_tag reply output json encoded]
  cases output <;> simp [tag]

private def sendOutput [Monad m] [MonadExceptOf ε m] (encodeError : String → ε)
    (send : String → m Unit) (reply : Option ModelInterfaceDistributionJson.ReplyV1)
    (output : Core.Replay.Output) : m Unit :=
  match encodeOutput reply output with
  | .ok json => send json.compress
  | .error message => throwThe ε (encodeError message)

/-- Interpret the verified program using the transport's framed send and read. -/
def run [Monad m] [MonadExceptOf ε m] (encodeError : String → ε)
    (send : String → m Unit) (receive : m (Option String))
    (reply : Option ModelInterfaceDistributionJson.ReplyV1) (traces : List ItfTrace)
    (control : Core.Replay.Control) : m Core.Replay.Control :=
  (Core.Replay.session traces control).run (sendOutput encodeError send reply) (decodeInput <$> receive)

/-- The framed transport records the line it wrote or read. EOF is `none`. -/
inductive Observation where
  | sent (line : String)
  | received (line : Option String)

/-- Wire evidence uses the message contract independently of the replay encoder
and decoder executed by the runner. -/
inductive AtWire (reply : Option ModelInterfaceDistributionJson.ReplyV1) :
    Core.Replay.Event → Observation → Prop where
  | send (allowed : OutputAllowed reply output) :
      AtWire reply (.sent output) (.sent (wireObject reply output).compress)
  | receive (read : Read line input) : AtWire reply (.received input) (.received line)

/-- The recording law applies to every framed line, irrespective of its JSON
contents. An interrupted write may already have delivered its complete frame. -/
def RecordsSend (history : σ → List Observation) (send : String → EStateM ε σ Unit) : Prop :=
  ∀ line w, match send line w with
    | .ok _ w' => history w' = history w ++ [.sent line]
    | .error _ w' => history w' = history w ∨ history w' = history w ++ [.sent line]

def RecordsReceive (history : σ → List Observation) (receive : EStateM ε σ (Option String)) : Prop :=
  ∀ w, match receive w with
    | .ok line w' => history w' = history w ++ [.received line]
    | .error _ w' => history w' = history w

/-- Every returned execution, including a transport exception, records a
prefix of the replay. Each returned line or EOF contributes one read event.
A receive that raises supplies no framed input. -/
theorem wire_prefix {ε σ : Type} (encodeError : String → ε)
    (send : String → EStateM ε σ Unit) (receive : EStateM ε σ (Option String))
    (history : σ → List Observation) (sendSpec : RecordsSend history send)
    (receiveSpec : RecordsReceive history receive)
    (reply : Option ModelInterfaceDistributionJson.ReplyV1)
    (traces : List ItfTrace) (control : Core.Replay.Control) (w : σ) (observed : List Observation)
    (execution : history (Core.Replay.endState
      (run encodeError send receive reply traces control w)) = history w ++ observed) :
    ∃ events, Core.Replay.Prefix (Core.Replay.session traces control) events ∧
      Core.Replay.Recording (AtWire reply) events observed := by
  obtain ⟨events, observations, recorded, pre, recording⟩ :=
    Core.Replay.Program.run_prefix (AtWire reply) history (sendOutput encodeError send reply)
      (decodeInput <$> receive)
      (by
        intro o world
        unfold sendOutput
        cases enc : encodeOutput reply o with
        | error msg => exact Or.inl rfl
        | ok json =>
          obtain ⟨allowed, rfl⟩ := (encodeOutput_ok_iff _ _ _).mp enc
          simp only
          have spec := sendSpec (wireObject reply o).compress world
          cases h : send (wireObject reply o).compress world with
          | ok => exact ⟨_, .send allowed, by simpa [h] using spec⟩
          | error =>
            rw [h] at spec
            exact spec.imp_right (fun wrote => ⟨_, .send allowed, wrote⟩))
      (by
        intro world
        have spec := receiveSpec world
        cases h : receive world with
        | ok line w' =>
          simp only [Functor.map, EStateM.map, h]
          exact ⟨_, .receive (read_decodeInput line), by simpa [h] using spec⟩
        | error => simpa [h, Functor.map, EStateM.map] using spec)
      (Core.Replay.session traces control) w
  unfold run at execution
  rw [execution] at recorded
  have eq := List.append_cancel_left recorded
  subst observations
  exact ⟨events, pre, recording⟩

/-- A finite raw observation of the replay instructions. The empty prefix
allows a stalled operation. A complete frame may be visible before the
corresponding send returns. -/
inductive FramedPrefix (reply : Option ModelInterfaceDistributionJson.ReplyV1) :
    Core.Replay.Program → List Observation → Prop where
  | pending : FramedPrefix reply p []
  | send (encoded : encodeOutput reply output = .ok json) (rest : FramedPrefix reply next obs) :
      FramedPrefix reply (.send output next) (.sent json.compress :: obs)
  | receive (rest : FramedPrefix reply (next (decodeInput line)) obs) :
      FramedPrefix reply (.receive next) (.received line :: obs)

theorem FramedPrefix.recording (h : FramedPrefix reply program observed) :
    ∃ events, Core.Replay.Prefix program events ∧ Core.Replay.Recording (AtWire reply) events observed := by
  induction h with
  | pending => exact ⟨[], .nil, .nil⟩
  | send encoded _ ih =>
    obtain ⟨events, pre, recording⟩ := ih
    obtain ⟨ok, rfl⟩ := (encodeOutput_ok_iff _ _ _).mp encoded
    exact ⟨_, .send pre, .cons (.send ok) recording⟩
  | receive _ ih =>
    obtain ⟨events, pre, recording⟩ := ih
    exact ⟨_, .receive pre, .cons (.receive (read_decodeInput _)) recording⟩

/-- A peer classifies completion soundly on the admissible frames it saw. -/
def CompletionTagSound (reply : Option ModelInterfaceDistributionJson.ReplyV1)
    (observed : List Observation) (peerCompleted : String → Prop) : Prop :=
  ∀ output, OutputAllowed reply output →
    let json := wireObject reply output
    Observation.sent json.compress ∈ observed → peerCompleted json.compress →
      json.getObjVal? "proto_step" = .ok (.str "all_steps_done")

private theorem completion_of_recording (traces : List ItfTrace) (s : Session .stepping)
    (pre : Core.Replay.Prefix (Core.Replay.session traces ⟨.stepping, s⟩) events)
    (recording : Core.Replay.Recording (AtWire reply) events observed)
    (tagSound : CompletionTagSound reply observed peerCompleted)
    (completed : ∃ line, Observation.sent line ∈ observed ∧ peerCompleted line) :
    ∃ body, Core.Replay.Accepted (traces.flatMap traceSteps) body ∧
      Core.Replay.Recording (AtWire reply) (.sent .validated :: body) observed := by
  obtain ⟨line, seen, recognized⟩ := completed
  obtain ⟨event, mem, rep⟩ := recording.event_of_mem seen
  have done : event = .sent .allStepsDone := by
    cases rep with
    | send allowed =>
      have header := tagSound _ allowed seen recognized
      rw [wireObject_tag] at header
      rename_i output
      cases output <;> simp [tag] at header ⊢
  rw [done] at mem
  obtain ⟨_, body, rfl, accepted⟩ :=
    (Core.Replay.session_completed_iff traces s events).mp ⟨pre, mem⟩
  exact ⟨body, accepted, recording⟩

/-- This implication concerns a finite observed prefix and needs no final IO
result, even if the peer has seen the final frame while its sender is stalled. -/
theorem FramedPrefix.completion (traces : List ItfTrace) (s : Session .stepping)
    (pre : FramedPrefix reply (Core.Replay.session traces ⟨.stepping, s⟩) observed)
    (tagSound : CompletionTagSound reply observed peerCompleted)
    (completed : ∃ line, Observation.sent line ∈ observed ∧ peerCompleted line) :
    ∃ body, Core.Replay.Accepted (traces.flatMap traceSteps) body ∧
      Core.Replay.Recording (AtWire reply) (.sent .validated :: body) observed := by
  obtain ⟨_, events, recording⟩ := pre.recording
  exact completion_of_recording traces s events recording tagSound completed

/-- Once a peer reads completion, the framed history is a recording of exactly
one successful exchange per step. Only observed, admissible replay outputs
require agreement with the peer's interpretation of the completion tag. -/
theorem wire_completion {ε σ : Type} (encodeError : String → ε)
    (send : String → EStateM ε σ Unit) (receive : EStateM ε σ (Option String))
    (history : σ → List Observation) (sendSpec : RecordsSend history send)
    (receiveSpec : RecordsReceive history receive)
    (reply : Option ModelInterfaceDistributionJson.ReplyV1)
    (traces : List ItfTrace) (s : Session .stepping) (w : σ) (observed : List Observation)
    (execution : history (Core.Replay.endState
      (run encodeError send receive reply traces ⟨.stepping, s⟩ w)) = history w ++ observed)
    (peerCompleted : String → Prop) (tagSound : CompletionTagSound reply observed peerCompleted)
    (completed : ∃ line, Observation.sent line ∈ observed ∧ peerCompleted line) :
    ∃ body, Core.Replay.Accepted (traces.flatMap traceSteps) body ∧
      Core.Replay.Recording (AtWire reply) (.sent .validated :: body) observed := by
  obtain ⟨_, pre, recording⟩ := wire_prefix encodeError send receive history sendSpec
    receiveSpec reply traces ⟨.stepping, s⟩ w observed execution
  exact completion_of_recording traces s pre recording tagSound completed

end Codec.Replay
