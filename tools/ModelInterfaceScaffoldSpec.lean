import Core.ModelInterface.Scaffold
import Codec.ModelInterfaceScaffoldJson

/-!
# Pure scaffold and strict proposal-codec specification

No filesystem or Apalache dependency.  The RBT-shaped evidence keeps the
non-string function fields that motivated explicit target support obligations.
-/

namespace ModelInterfaceScaffoldSpec

open Core.ModelInterface

abbrev Failures := IO.Ref (List String)

def check (fails : Failures) (name : String) (ok : Bool)
    (detail : String := "") : IO Unit := do
  if !ok then
    fails.modify fun items => items ++ [if detail.isEmpty then name else s!"{name}: {detail}"]

def digestA : String := String.join (List.replicate 64 "a")
def digestB : String := String.join (List.replicate 64 "b")

def rbtVars : List String :=
  ["nk", "nc", "nl", "nr", "nb", "root", "activeKeys", "usedNodes",
   "action_taken", "step_count", "parameters"]

def topFact (name : String) (type : ModelType) : TypeFact :=
  { modelPath := .top name, type, origin := .apalacheTypecheck }

def rbtEvidence : ModelEvidence :=
  { traceVars := rbtVars
    itfParamVars := ["parameters"]
    evidenceSha256 := digestB
    typeFacts := [
      topFact "nk" (.map .int .int),
      topFact "nc" (.map .int .str),
      topFact "nl" (.map .int .int),
      topFact "nr" (.map .int .int),
      topFact "nb" (.map .int .int),
      topFact "root" .int,
      topFact "activeKeys" (.set .int),
      topFact "usedNodes" (.set .int),
      topFact "action_taken" .str,
      topFact "step_count" .int,
      topFact "parameters" (.record [{ wireName := "keyParam", type := .int }]) ] }

def rbtInput : ScaffoldInput :=
  { source := {
      moduleName := "RBT"
      logicalPath := "specs/RBT/RBT.tla"
      contentSha256 := digestA }
    sourceVariableNames := rbtVars
    evidence := rbtEvidence
    initializerLabels := ["init"]
    transitionLabels := ["insert", "delete"]
    configuredParamVar := some "parameters" }

def diagnosticCode (result : CompileResult α) (code : String) : Bool :=
  result.diagnostics.any (fun diagnostic => diagnostic.code == code)

def scenarioRbt (fails : Failures) : IO (Option ScaffoldProposal) := do
  let result := synthesizeScaffold rbtInput
  check fails "rbt: synthesis has no errors" (!result.hasErrors)
    (toString (repr result.diagnostics))
  let some proposal := result.value
    | check fails "rbt: synthesis returns proposal" false
      return none
  check fails "rbt: proposal schema" (proposal.schema == scaffoldSchemaV1)
  check fails "rbt: semantic envelope is well formed"
    (scaffoldProposalWellFormedV1 proposal)
  check fails "rbt: inferred action IDs are stable and sorted"
    (proposal.unsealedInitializers == ["Initialize"] &&
      proposal.unsealedActions == ["Delete", "Insert"])
  let actionInputs := proposal.contract.actions.map fun action =>
    (action.id, action.inputs)
  check fails "rbt: keyParam becomes one Key projection"
    (actionInputs.all fun pair =>
      match pair.2 with
      | [input] => input.id == "Key" && input.fromRoot == .stepParameters &&
          input.path.length == 2 &&
          (match input.path with
           | [.field "parameters", .field "keyParam"] => true
           | _ => false) && input.expectedType == some .int
      | _ => false)
  let observationNames := proposal.contract.observations.map (·.wireName)
  check fails "rbt: observations exclude action and effective parameters"
    (observationNames ==
      ["activeKeys", "nb", "nc", "nk", "nl", "nr", "root", "step_count", "usedNodes"])
  check fails "rbt: Int-keyed functions stay explicit target obligations"
    (proposal.targetSupportObligations.map (·.stableId) == ["Nb", "Nc", "Nk", "Nl", "Nr"])
  return some proposal

def scenarioRejections (fails : Failures) : IO Unit := do
  let stale := synthesizeScaffold { rbtInput with sourceVariableNames := rbtVars.drop 1 }
  check fails "reject: stale source/evidence variable mismatch"
    (stale.value.isNone && diagnosticCode stale "MIC-S-SOURCE-001")
  let collision := synthesizeScaffold {
    rbtInput with transitionLabels := ["foo-bar", "foo_bar"] }
  check fails "reject: UpperCamel collision"
    (collision.value.isNone && diagnosticCode collision "MIC-S-ID-001")
  let empty := synthesizeScaffold { rbtInput with transitionLabels := [""] }
  check fails "reject: empty label"
    (empty.value.isNone && diagnosticCode empty "MIC-S-ACTION-001")
  let reserved := synthesizeScaffold {
    rbtInput with transitionLabels := ["constructor"] }
  check fails "reject: reserved label"
    (reserved.value.isNone && diagnosticCode reserved "MIC-S-ACTION-001")
  let multiParamEvidence := {
    rbtEvidence with typeFacts := rbtEvidence.typeFacts.map fun fact =>
      if fact.modelPath.root == "parameters" then
        { fact with type := .record [
          { wireName := "keyParam", type := .int },
          { wireName := "otherParam", type := .int }] }
      else fact }
  let multiParam := synthesizeScaffold { rbtInput with evidence := multiParamEvidence }
  check fails "parameters: a multi-field record emits every candidate input"
    (match multiParam.value with
     | some proposal => proposal.contract.actions.all fun action =>
         action.inputs.map (·.id) == ["Key", "Other"]
     | none => false)
  let emptyParamEvidence := {
    rbtEvidence with typeFacts := rbtEvidence.typeFacts.map fun fact =>
      if fact.modelPath.root == "parameters" then
        { fact with type := .record [] }
      else fact }
  let emptyParam := synthesizeScaffold { rbtInput with evidence := emptyParamEvidence }
  check fails "reject: parameter record is empty"
    (emptyParam.value.isNone && diagnosticCode emptyParam "MIC-S-PARAM-001")
  let tooMany := (List.range (maxTransitionActionsV1 + 1)).map fun index =>
    "action" ++ toString index
  let limited := synthesizeScaffold { rbtInput with transitionLabels := tooMany }
  check fails "reject: action resource limit"
    (limited.value.isNone && diagnosticCode limited "MIC-R-LIMIT-001")

def scenarioCodec (fails : Failures) (proposal : ScaffoldProposal) : IO Unit := do
  let bytes := Codec.ModelInterfaceScaffoldJson.canonicalBytes proposal
  match Codec.ModelInterfaceScaffoldJson.parseProposalBytes bytes with
  | .error error => check fails "codec: canonical proposal parses" false error
  | .ok decoded =>
      check fails "codec: decode/re-encode is byte canonical"
        (Codec.ModelInterfaceScaffoldJson.canonicalBytes decoded == bytes)
  let reversed := {
    proposal with
      contract := { proposal.contract with
        actions := proposal.contract.actions.reverse
        observations := proposal.contract.observations.reverse }
      unsealedActions := proposal.unsealedActions.reverse
      targetSupportObligations := proposal.targetSupportObligations.reverse }
  check fails "codec: collection order canonicalizes"
    (Codec.ModelInterfaceScaffoldJson.canonicalBytes reversed == bytes)
  let canonical := Codec.ModelInterfaceScaffoldJson.canonicalString proposal
  let unknown := canonical.replace
    "\"targetSupportObligations\":" "\"unknown\":true,\"targetSupportObligations\":"
  check fails "codec: unknown field rejected"
    (!(Codec.ModelInterfaceScaffoldJson.parseProposalString unknown).isOk)
  let duplicate := canonical.replace
    "\"schema\":\"mirrors.model-interface-scaffold/v1\""
    "\"schema\":\"mirrors.model-interface-scaffold/v1\",\"schema\":\"mirrors.model-interface-scaffold/v1\""
  check fails "codec: duplicate field rejected before object decoding"
    (!(Codec.ModelInterfaceScaffoldJson.parseProposalString duplicate).isOk)
  let pretty := (Codec.ModelInterfaceScaffoldJson.encodeProposal proposal).pretty
  match Codec.ModelInterfaceScaffoldJson.parseProposalString pretty with
  | .error error => check fails "codec: insignificant whitespace accepted" false error
  | .ok decoded =>
      check fails "codec: whitespace returns identical canonical bytes"
        (Codec.ModelInterfaceScaffoldJson.canonicalBytes decoded == bytes)
  check fails "codec: byte limit enforced"
    (!(Codec.ModelInterfaceScaffoldJson.parseProposalBytes bytes { maxBytes := 8 }).isOk)

def run : IO UInt32 := do
  let fails ← IO.mkRef []
  let proposal? ← scenarioRbt fails
  scenarioRejections fails
  match proposal? with
  | some proposal => scenarioCodec fails proposal
  | none => pure ()
  let failures ← fails.get
  if failures.isEmpty then
    IO.println "MODEL INTERFACE SCAFFOLD SPEC GREEN"
    return 0
  else
    failures.forM (fun failure => IO.eprintln s!"FAIL: {failure}")
    return 1

end ModelInterfaceScaffoldSpec

def main : IO UInt32 :=
  ModelInterfaceScaffoldSpec.run
