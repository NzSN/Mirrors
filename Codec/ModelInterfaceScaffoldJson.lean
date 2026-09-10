import Codec.ModelInterfaceJson
import Codec.StrictJson
import Core.ModelInterface.Scaffold
import Lean.Data.Json

/-!
# Strict model-interface scaffold proposal JSON

The raw entry points reject duplicate keys before `Lean.Json` constructs an
object map.  Decoding is closed-world and normalizes every set-like array.
-/

namespace Codec.ModelInterfaceScaffoldJson

open Lean Core.ModelInterface

abbrev DecodeResult (α : Type) := Except String α
private abbrev Fields := List (String × Json)

private def fail (context message : String) : DecodeResult α :=
  .error s!"{context}: {message}"

private def array (values : List Json) : Json := .arr values.toArray
private def strings (values : List String) : Json := array (values.map Json.str)

private def objectFields (context : String) : Json → DecodeResult Fields
  | .obj fields => .ok fields.toList
  | _ => fail context "object expected"

private def checkObject (context : String) (allowed requiredNames : List String)
    (json : Json) : DecodeResult Fields := do
  let fields ← objectFields context json
  match fields.find? (fun field => !allowed.contains field.1) with
  | some field => fail context s!"unknown field '{field.1}'"
  | none => pure ()
  match requiredNames.find? (fun name => (List.lookup name fields).isNone) with
  | some name => fail context s!"missing required field '{name}'"
  | none => return fields

private def required (context : String) (fields : Fields) (name : String) :
    DecodeResult Json :=
  match List.lookup name fields with
  | some value => .ok value
  | none => fail context s!"missing required field '{name}'"

private def decodeString (context : String) : Json → DecodeResult String
  | .str value => .ok value
  | _ => fail context "string expected"

private def decodeArray (context : String) (decode : Json → DecodeResult α) :
    Json → DecodeResult (List α)
  | .arr values => values.toList.mapM decode
  | _ => fail context "array expected"

private def decodeStringArray (context : String) (json : Json) :
    DecodeResult (List String) :=
  decodeArray context (decodeString (context ++ "[]")) json

private def encodeSource (source : SourceDigest) : Json :=
  Json.mkObj [
    ("module", .str source.moduleName),
    ("path", .str source.logicalPath),
    ("sha256", .str source.contentSha256)]

private def decodeSource (context : String) (json : Json) : DecodeResult SourceDigest := do
  let fields ← checkObject context ["module", "path", "sha256"]
    ["module", "path", "sha256"] json
  return {
    moduleName := ← decodeString (context ++ ".module") (← required context fields "module")
    logicalPath := ← decodeString (context ++ ".path") (← required context fields "path")
    contentSha256 := ← decodeString (context ++ ".sha256")
      (← required context fields "sha256") }

private def encodeProjection (projection : ScaffoldProjectionProvenance) : Json :=
  Json.mkObj [
    ("outputSha256", .str projection.outputSha256),
    ("planSha256", .str projection.planSha256),
    ("rawSha256", .str projection.rawSha256)]

private def decodeProjection (context : String) (json : Json) :
    DecodeResult ScaffoldProjectionProvenance := do
  let fields ← checkObject context ["rawSha256", "planSha256", "outputSha256"]
    ["rawSha256", "planSha256", "outputSha256"] json
  return {
    rawSha256 := ← decodeString (context ++ ".rawSha256")
      (← required context fields "rawSha256")
    planSha256 := ← decodeString (context ++ ".planSha256")
      (← required context fields "planSha256")
    outputSha256 := ← decodeString (context ++ ".outputSha256")
      (← required context fields "outputSha256") }

private def obligationKey (obligation : TargetSupportObligation) : String :=
  obligation.subjectKind ++ "\u0000" ++ obligation.stableId

private def sortObligations (obligations : List TargetSupportObligation) :
    List TargetSupportObligation :=
  obligations.mergeSort fun left right => obligationKey left ≤ obligationKey right

private def encodeObligation (obligation : TargetSupportObligation) : Json :=
  Json.mkObj [
    ("subject", Json.mkObj [
      ("kind", .str obligation.subjectKind),
      ("stableId", .str obligation.stableId)]),
    ("type", ModelInterfaceJson.encodeModelType obligation.type)]

private def decodeObligation (context : String) (json : Json) :
    DecodeResult TargetSupportObligation := do
  let fields ← checkObject context ["subject", "type"] ["subject", "type"] json
  let subjectJson ← required context fields "subject"
  let subject ← checkObject (context ++ ".subject") ["kind", "stableId"]
    ["kind", "stableId"] subjectJson
  return {
    subjectKind := ← decodeString (context ++ ".subject.kind")
      (← required (context ++ ".subject") subject "kind")
    stableId := ← decodeString (context ++ ".subject.stableId")
      (← required (context ++ ".subject") subject "stableId")
    type := ← ModelInterfaceJson.decodeModelType (← required context fields "type") }

/-- Canonically encode the closed version-1 proposal envelope. -/
def encodeProposal (proposal : ScaffoldProposal) : Json :=
  let contract := normalizeContractV1 proposal.contract
  let initializers := sortStrings proposal.unsealedInitializers
  let actions := sortStrings proposal.unsealedActions
  let obligations := sortObligations proposal.targetSupportObligations
  let provenanceFields := [
    ("evidenceSha256", .str proposal.evidenceSha256),
    ("source", encodeSource proposal.source)] ++
    proposal.projection.toList.map fun projection =>
      ("projection", encodeProjection projection)
  Json.mkObj [
    ("contract", ModelInterfaceJson.encodeContract contract),
    ("provenance", Json.mkObj provenanceFields),
    ("schema", .str proposal.schema),
    ("targetSupportObligations", array (obligations.map encodeObligation)),
    ("unsealed", Json.mkObj [
      ("actions", strings actions),
      ("initializers", strings initializers)])]

/-- Strictly decode a parsed proposal, rejecting unknown fields and semantic
inconsistencies between the envelope and embedded contract. -/
def decodeProposal (json : Json) : DecodeResult ScaffoldProposal := do
  let context := "scaffold"
  let fields ← checkObject context
    ["schema", "contract", "unsealed", "provenance", "targetSupportObligations"]
    ["schema", "contract", "unsealed", "provenance", "targetSupportObligations"] json
  let schema ← decodeString "scaffold.schema" (← required context fields "schema")
  if schema != scaffoldSchemaV1 then
    fail "scaffold.schema" s!"expected '{scaffoldSchemaV1}'"
  let contract ← ModelInterfaceJson.decodeContract (← required context fields "contract")
  let unsealedJson ← required context fields "unsealed"
  let unsealed ← checkObject "scaffold.unsealed" ["initializers", "actions"]
    ["initializers", "actions"] unsealedJson
  let provenanceJson ← required context fields "provenance"
  let provenance ← checkObject "scaffold.provenance"
    ["source", "evidenceSha256", "projection"]
    ["source", "evidenceSha256"] provenanceJson
  let source ← decodeSource "scaffold.provenance.source"
    (← required "scaffold.provenance" provenance "source")
  let projection ← match List.lookup "projection" provenance with
    | none => pure none
    | some json => pure (some (← decodeProjection "scaffold.provenance.projection" json))
  let obligations ← decodeArray "scaffold.targetSupportObligations"
    (decodeObligation "scaffold.targetSupportObligations[]")
    (← required context fields "targetSupportObligations")
  let proposal : ScaffoldProposal :=
    { schema
      contract := normalizeContractV1 contract
      unsealedInitializers := sortStrings (← decodeStringArray
        "scaffold.unsealed.initializers" (← required "scaffold.unsealed" unsealed "initializers"))
      unsealedActions := sortStrings (← decodeStringArray
        "scaffold.unsealed.actions" (← required "scaffold.unsealed" unsealed "actions"))
      source
      evidenceSha256 := ← decodeString "scaffold.provenance.evidenceSha256"
        (← required "scaffold.provenance" provenance "evidenceSha256")
      projection
      targetSupportObligations := sortObligations obligations }
  if scaffoldProposalWellFormedV1 proposal then return proposal
  else fail context "proposal violates version-1 semantic invariants"

/-- Compact canonical JSON without a trailing newline. -/
def canonicalString (proposal : ScaffoldProposal) : String :=
  ModelInterfaceJson.canonicalString (encodeProposal proposal)

/-- Compact canonical UTF-8 JSON without a trailing newline. -/
def canonicalBytes (proposal : ScaffoldProposal) : ByteArray :=
  (canonicalString proposal).toUTF8

/-- Canonical artifact bytes with exactly one trailing LF. -/
def canonicalFileBytes (proposal : ScaffoldProposal) : ByteArray :=
  (canonicalString proposal ++ "\n").toUTF8

/-- Reject duplicate keys before decoding the proposal envelope. -/
def parseProposalBytes (raw : ByteArray)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) : DecodeResult ScaffoldProposal := do
  let json ← (StrictJson.parseBytes raw limits).mapError toString
  decodeProposal json

def parseProposalString (raw : String)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) : DecodeResult ScaffoldProposal :=
  parseProposalBytes raw.toUTF8 limits

end Codec.ModelInterfaceScaffoldJson
