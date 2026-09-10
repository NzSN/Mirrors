import Codec.ModelInterfaceJson
import Codec.StrictJson
import Core.ModelInterface.Sha256
import Core.ModelInterface.TraceProjection

/-! Strict plan/receipt codecs and domain-separated projection hashing. -/

namespace Codec.ModelInterfaceTraceProjectionJson

open Lean Core.ModelInterface

abbrev DecodeResult (α : Type) := Except String α
private abbrev Fields := List (String × Json)

def projectionSourceDigestDomainV1 : String := "mirrors-trace-projection-source/v1"
def projectionRawDigestDomainV1 : String := "mirrors-trace-projection-raw/v1"
def projectionPlanDigestDomainV1 : String := "mirrors-trace-projection-plan/v1"
def projectionOutputDigestDomainV1 : String := "mirrors-trace-projection-output/v1"

private def fail (context message : String) : DecodeResult α := .error s!"{context}: {message}"
private def array (values : List Json) := Json.arr values.toArray
private def strings (values : List String) := array (values.map Json.str)
private def sortFields (values : List ZipIntFunctionField) :=
  values.mergeSort fun a b => a.name ≤ b.name
private def sortGroups (values : List ZipIntFunctions) :=
  values.mergeSort fun a b => a.outputWireName ≤ b.outputWireName

def normalizePlan (plan : TraceProjectionPlan) : TraceProjectionPlan :=
  { plan with
    exactCopyVariables := sortStrings plan.exactCopyVariables
    zipIntFunctions := sortGroups (plan.zipIntFunctions.map fun group =>
      { group with fields := sortFields group.fields }) }

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
private def required (context : String) (fields : Fields) (name : String) :=
  match List.lookup name fields with
  | some value => (Except.ok value : DecodeResult Json)
  | none => fail context s!"missing required field '{name}'"
private def decodeString (context : String) : Json → DecodeResult String
  | .str value => .ok value
  | _ => fail context "string expected"
private def decodeArray (context : String) (decode : Json → DecodeResult α) :
    Json → DecodeResult (List α)
  | .arr values => values.toList.mapM decode
  | _ => fail context "array expected"
private def decodeStrings (context : String) (json : Json) :=
  decodeArray context (decodeString (context ++ "[]")) json

private def encodeDomain (domain : IntDomain) := Json.mkObj [
  ("lowerInclusive", .str domain.lowerInclusive),
  ("upperInclusive", .str domain.upperInclusive)]
private def encodeField (field : ZipIntFunctionField) := Json.mkObj [
  ("name", .str field.name), ("sourceVariable", .str field.sourceVariable)]
private def encodeGroup (group : ZipIntFunctions) := Json.mkObj [
  ("domain", encodeDomain group.domain),
  ("fields", array (group.fields.map encodeField)),
  ("outputWireName", .str group.outputWireName)]

def encodePlan (input : TraceProjectionPlan) : Json :=
  let plan := normalizePlan input
  Json.mkObj [
    ("exactCopyVariables", strings plan.exactCopyVariables),
    ("schema", .str plan.schema),
    ("zipIntFunctions", array (plan.zipIntFunctions.map encodeGroup))]

private def decodeDomain (context : String) (json : Json) : DecodeResult IntDomain := do
  let fields ← checkObject context ["lowerInclusive", "upperInclusive"]
    ["lowerInclusive", "upperInclusive"] json
  return {
    lowerInclusive := ← decodeString (context ++ ".lowerInclusive")
      (← required context fields "lowerInclusive")
    upperInclusive := ← decodeString (context ++ ".upperInclusive")
      (← required context fields "upperInclusive") }
private def decodeField (context : String) (json : Json) : DecodeResult ZipIntFunctionField := do
  let fields ← checkObject context ["name", "sourceVariable"] ["name", "sourceVariable"] json
  return {
    name := ← decodeString (context ++ ".name") (← required context fields "name")
    sourceVariable := ← decodeString (context ++ ".sourceVariable")
      (← required context fields "sourceVariable") }
private def decodeGroup (context : String) (json : Json) : DecodeResult ZipIntFunctions := do
  let fields ← checkObject context ["outputWireName", "domain", "fields"]
    ["outputWireName", "domain", "fields"] json
  return {
    outputWireName := ← decodeString (context ++ ".outputWireName")
      (← required context fields "outputWireName")
    domain := ← decodeDomain (context ++ ".domain") (← required context fields "domain")
    fields := ← decodeArray (context ++ ".fields") (decodeField (context ++ ".fields[]"))
      (← required context fields "fields") }

def decodePlan (json : Json) : DecodeResult TraceProjectionPlan := do
  let context := "traceProjection"
  let fields ← checkObject context ["schema", "zipIntFunctions", "exactCopyVariables"]
    ["schema", "zipIntFunctions", "exactCopyVariables"] json
  let schema ← decodeString (context ++ ".schema") (← required context fields "schema")
  if schema != traceProjectionSchemaV1 then fail (context ++ ".schema") "unsupported schema"
  return normalizePlan {
    schema
    zipIntFunctions := ← decodeArray (context ++ ".zipIntFunctions")
      (decodeGroup (context ++ ".zipIntFunctions[]"))
      (← required context fields "zipIntFunctions")
    exactCopyVariables := ← decodeStrings (context ++ ".exactCopyVariables")
      (← required context fields "exactCopyVariables") }

def canonicalPlanBytes (plan : TraceProjectionPlan) : ByteArray :=
  ModelInterfaceJson.canonicalBytes (encodePlan plan)
def canonicalPlanFileBytes (plan : TraceProjectionPlan) : ByteArray :=
  ModelInterfaceJson.canonicalFileBytes (encodePlan plan)
def parsePlanBytes (raw : ByteArray)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) : DecodeResult TraceProjectionPlan := do
  decodePlan (← (StrictJson.parseBytes raw limits).mapError toString)
def parsePlanString (raw : String)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) : DecodeResult TraceProjectionPlan :=
  parsePlanBytes raw.toUTF8 limits

private def validDigest (digest : String) : Bool :=
  digest.length == 64 && digest.toList.all fun c =>
    ('0'.toNat ≤ c.toNat && c.toNat ≤ '9'.toNat) ||
      ('a'.toNat ≤ c.toNat && c.toNat ≤ 'f'.toNat)

def encodeReceipt (receipt : TraceProjectionReceipt) : Json := Json.mkObj [
  ("inputVariables", strings (sortStrings receipt.inputVariables)),
  ("outputSha256", .str receipt.outputSha256),
  ("outputVariables", strings (sortStrings receipt.outputVariables)),
  ("planSha256", .str receipt.planSha256),
  ("rawSha256", .str receipt.rawSha256),
  ("schema", .str receipt.schema),
  ("sourceSha256", .str receipt.sourceSha256)]

def decodeReceipt (json : Json) : DecodeResult TraceProjectionReceipt := do
  let context := "traceProjectionReceipt"
  let names := ["schema", "sourceSha256", "rawSha256", "planSha256", "outputSha256",
    "inputVariables", "outputVariables"]
  let fields ← checkObject context names names json
  let receipt : TraceProjectionReceipt := {
    schema := ← decodeString (context ++ ".schema") (← required context fields "schema")
    sourceSha256 := ← decodeString (context ++ ".sourceSha256")
      (← required context fields "sourceSha256")
    rawSha256 := ← decodeString (context ++ ".rawSha256") (← required context fields "rawSha256")
    planSha256 := ← decodeString (context ++ ".planSha256") (← required context fields "planSha256")
    outputSha256 := ← decodeString (context ++ ".outputSha256")
      (← required context fields "outputSha256")
    inputVariables := sortStrings (← decodeStrings (context ++ ".inputVariables")
      (← required context fields "inputVariables"))
    outputVariables := sortStrings (← decodeStrings (context ++ ".outputVariables")
      (← required context fields "outputVariables")) }
  if receipt.schema != traceProjectionReceiptSchemaV1 then fail (context ++ ".schema") "unsupported schema"
  if ![receipt.sourceSha256, receipt.rawSha256, receipt.planSha256,
      receipt.outputSha256].all validDigest then fail context "invalid digest"
  if !(duplicateStrings receipt.inputVariables).isEmpty ||
      !(duplicateStrings receipt.outputVariables).isEmpty then fail context "duplicate variable"
  return receipt

def canonicalReceiptBytes (receipt : TraceProjectionReceipt) : ByteArray :=
  ModelInterfaceJson.canonicalBytes (encodeReceipt receipt)
def canonicalReceiptFileBytes (receipt : TraceProjectionReceipt) : ByteArray :=
  ModelInterfaceJson.canonicalFileBytes (encodeReceipt receipt)
def parseReceiptBytes (raw : ByteArray)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) : DecodeResult TraceProjectionReceipt := do
  decodeReceipt (← (StrictJson.parseBytes raw limits).mapError toString)
def parseReceiptString (raw : String)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) : DecodeResult TraceProjectionReceipt :=
  parseReceiptBytes raw.toUTF8 limits

def canonicalProjectedTraceBytes (result : TraceProjectionResult) : ByteArray :=
  ModelInterfaceJson.canonicalBytes result.projectedTrace
def canonicalProjectedTraceFileBytes (result : TraceProjectionResult) : ByteArray :=
  ModelInterfaceJson.canonicalFileBytes result.projectedTrace

def encodeResult (result : TraceProjectionResult) : Json := Json.mkObj [
  ("projectedTrace", result.projectedTrace),
  ("receipt", encodeReceipt result.receipt),
  ("schema", .str traceProjectionResultSchemaV1)]

def decodeResult (json : Json) : DecodeResult TraceProjectionResult := do
  let context := "traceProjectionResult"
  let fields ← checkObject context ["schema", "projectedTrace", "receipt"]
    ["schema", "projectedTrace", "receipt"] json
  let schema ← decodeString (context ++ ".schema") (← required context fields "schema")
  if schema != traceProjectionResultSchemaV1 then fail (context ++ ".schema") "unsupported schema"
  let projectedTrace ← required context fields "projectedTrace"
  let receipt ← decodeReceipt (← required context fields "receipt")
  let outputBytes := ModelInterfaceJson.canonicalBytes projectedTrace
  let expected := Sha256.digestDomainHex projectionOutputDigestDomainV1 outputBytes
  if receipt.outputSha256 != expected then fail context "projected trace does not match outputSha256"
  let .obj root ← pure projectedTrace | fail (context ++ ".projectedTrace") "object expected"
  let vars ← decodeStrings (context ++ ".projectedTrace.vars")
    (← required (context ++ ".projectedTrace") root.toList "vars")
  if sortStrings vars != receipt.outputVariables then
    fail context "projected trace vars do not match receipt outputVariables"
  return { projectedTrace, receipt }

def canonicalResultBytes (result : TraceProjectionResult) : ByteArray :=
  ModelInterfaceJson.canonicalBytes (encodeResult result)
def canonicalResultFileBytes (result : TraceProjectionResult) : ByteArray :=
  ModelInterfaceJson.canonicalFileBytes (encodeResult result)
def parseResultBytes (raw : ByteArray)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) : DecodeResult TraceProjectionResult := do
  decodeResult (← (StrictJson.parseBytes raw limits).mapError toString)
def parseResultString (raw : String)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) : DecodeResult TraceProjectionResult :=
  parseResultBytes raw.toUTF8 limits

/-- Parse the raw trace strictly, project it, and bind exact canonical bytes in
a domain-separated receipt. `outputSha256` covers `canonicalProjectedTraceBytes`. -/
def projectTraceBytes (sourceBytes rawBytes : ByteArray) (inputPlan : TraceProjectionPlan)
    (context : TraceProjectionContext)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) : DecodeResult TraceProjectionResult := do
  let plan := normalizePlan inputPlan
  let raw ← (StrictJson.parseBytes rawBytes limits).mapError toString
  let projectedTrace ← projectTraceJson plan context raw
  let outputBytes := ModelInterfaceJson.canonicalBytes projectedTrace
  if outputBytes.size > maxProjectedTraceArtifactBytesV1 then
    throw s!"projected trace exceeds {maxProjectedTraceArtifactBytesV1}-byte limit"
  let receipt : TraceProjectionReceipt := {
    sourceSha256 := Sha256.digestDomainHex projectionSourceDigestDomainV1 sourceBytes
    rawSha256 := Sha256.digestDomainHex projectionRawDigestDomainV1 rawBytes
    planSha256 := Sha256.digestDomainHex projectionPlanDigestDomainV1 (canonicalPlanBytes plan)
    outputSha256 := Sha256.digestDomainHex projectionOutputDigestDomainV1 outputBytes
    inputVariables := sortStrings context.rawVariables
    outputVariables := outputVariables plan }
  return { projectedTrace, receipt }

end Codec.ModelInterfaceTraceProjectionJson
