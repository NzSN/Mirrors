import Codec.ModelInterfaceTraceProjectionJson

namespace ModelInterfaceTraceProjectionSpec

open Lean Core.ModelInterface
abbrev Failures := IO.Ref (List String)
def check (fails : Failures) (name : String) (ok : Bool) (detail := "") : IO Unit := do
  if !ok then fails.modify (· ++ [if detail.isEmpty then name else s!"{name}: {detail}"])

def plan : TraceProjectionPlan := {
  exactCopyVariables := ["parameters", "step_count", "action_taken", "root"]
  zipIntFunctions := [{
    outputWireName := "nodes"
    domain := { lowerInclusive := "0", upperInclusive := "1" }
    fields := [
      { name := "key", sourceVariable := "nk" },
      { name := "color", sourceVariable := "nc" }] }] }

def variables := ["nk", "nc", "root", "action_taken", "step_count", "parameters"]
def context : TraceProjectionContext := {
  rawVariables := variables
  sourceVariables := variables
  sourceTypes := [
    ("nk", .map .int .int), ("nc", .map .int .str), ("root", .int),
    ("action_taken", .str), ("step_count", .int),
    ("parameters", .record [{ wireName := "keyParam", type := .int }])] }

def raw : String :=
  "{" ++
  "\"#meta\":{\"format\":\"ITF\",\"description\":\"kept\",\"varTypes\":{" ++
  "\"nk\":\"(Int -> Int)\",\"nc\":\"(Int -> Str)\",\"root\":\"Int\"," ++
  "\"action_taken\":\"Str\",\"step_count\":\"Int\"," ++
  "\"parameters\":\"{ keyParam: Int }\"}}," ++
  "\"param_vars\":[\"parameters\"]," ++
  "\"vars\":[\"nk\",\"nc\",\"root\",\"action_taken\",\"step_count\",\"parameters\"]," ++
  "\"states\":[{\"#meta\":{\"index\":0}," ++
  "\"nk\":{\"#map\":[[{\"#bigint\":\"0\"},{\"#bigint\":\"10\"}],[{\"#bigint\":\"1\"},{\"#bigint\":\"20\"}]]}," ++
  "\"nc\":{\"#map\":[[{\"#bigint\":\"0\"},\"B\"],[{\"#bigint\":\"1\"},\"R\"]]}," ++
  "\"root\":{\"#bigint\":\"1\"},\"action_taken\":\"init\"," ++
  "\"step_count\":{\"#bigint\":\"0\"},\"parameters\":{\"keyParam\":{\"#bigint\":\"0\"}}}]}"

def source := "---------------- MODULE RBT ----------------\nVARIABLES nk, nc\n====\n"

def scenarioHappy (fails : Failures) : IO (Option TraceProjectionResult) := do
  let first := Codec.ModelInterfaceTraceProjectionJson.projectTraceBytes
    source.toUTF8 raw.toUTF8 plan context
  let second := Codec.ModelInterfaceTraceProjectionJson.projectTraceBytes
    source.toUTF8 raw.toUTF8 { plan with exactCopyVariables := plan.exactCopyVariables.reverse }
    context
  match first, second with
  | .ok result, .ok again =>
      let bytes := Codec.ModelInterfaceTraceProjectionJson.canonicalProjectedTraceBytes result
      check fails "happy: deterministic projected bytes"
        (bytes == Codec.ModelInterfaceTraceProjectionJson.canonicalProjectedTraceBytes again)
      check fails "happy: canonical output hash is exact"
        (result.receipt.outputSha256 == Core.ModelInterface.Sha256.digestDomainHex
          Codec.ModelInterfaceTraceProjectionJson.projectionOutputDigestDomainV1 bytes)
      check fails "happy: input and output vars explicit"
        (result.receipt.inputVariables == sortStrings variables &&
          result.receipt.outputVariables ==
            ["action_taken", "nodes", "parameters", "root", "step_count"])
      let compressed := Codec.ModelInterfaceJson.canonicalString result.projectedTrace
      check fails "happy: aligned sequence records generated"
        (compressed.contains "\"nodes\":[{\"color\":\"B\",\"key\":{\"#bigint\":\"10\"}},{\"color\":\"R\",\"key\":{\"#bigint\":\"20\"}}]")
      check fails "happy: deterministic projected varTypes"
        (compressed.contains "\"nodes\":\"Seq({color: Str, key: Int})\"")
      check fails "happy: root and state metadata preserved"
        (compressed.contains "\"description\":\"kept\"" &&
          compressed.contains "\"#meta\":{\"index\":0}" &&
          compressed.contains "\"action_taken\":\"init\"")
      return some result
  | .error error, _ | _, .error error =>
      check fails "happy: RBT projection succeeds" false error
      return none

def rejects (result : Except String α) : Bool :=
  match result with | .error _ => true | .ok _ => false

def errorContains (needle : String) (result : Except String α) : Bool :=
  match result with | .error error => error.contains needle | .ok _ => false

def expansionFixture : TraceProjectionPlan × TraceProjectionContext × ByteArray :=
  let names := (List.range 32).map fun index => "source" ++ toString index
  let longStem := String.join (List.replicate 220 "x")
  let fields := names.zipIdx.map fun pair =>
    ({ name := longStem ++ toString pair.2, sourceVariable := pair.1 } :
      ZipIntFunctionField)
  let largePlan : TraceProjectionPlan := {
    exactCopyVariables := []
    zipIntFunctions := [{
      outputWireName := "expanded"
      domain := { lowerInclusive := "0", upperInclusive := "4095" }
      fields }] }
  let largeContext : TraceProjectionContext := {
    rawVariables := names
    sourceVariables := names
    sourceTypes := names.map fun name => (name, .map .int .int) }
  let state := Json.mkObj (("#meta", Json.mkObj [("index", .num 0)]) ::
    names.map fun name => (name, Json.null))
  let state2 := Json.mkObj (("#meta", Json.mkObj [("index", .num 1)]) ::
    names.map fun name => (name, Json.null))
  let rawJson := Json.mkObj [
    ("#meta", Json.mkObj [("format", .str "ITF"), ("varTypes", Json.mkObj [])]),
    ("vars", .arr (names.map Json.str).toArray),
    ("states", .arr #[state, state2])]
  (largePlan, largeContext, Codec.ModelInterfaceJson.canonicalBytes rawJson)

def scenarioReject (fails : Failures) : IO Unit := do
  let project (rawText := raw) (chosenPlan := plan) (chosenContext := context) :=
    Codec.ModelInterfaceTraceProjectionJson.projectTraceBytes
      source.toUTF8 rawText.toUTF8 chosenPlan chosenContext
  check fails "reject: missing source key"
    (rejects <| project (rawText := raw.replace
      "[{\"#bigint\":\"0\"},{\"#bigint\":\"10\"}]," ""))
  check fails "reject: extra source key outside bounded domain"
    (rejects <| project (rawText := raw.replace
      "[{\"#bigint\":\"1\"},{\"#bigint\":\"20\"}]]}"
      "[{\"#bigint\":\"1\"},{\"#bigint\":\"20\"}],[{\"#bigint\":\"2\"},{\"#bigint\":\"30\"}]]}"))
  let badDomain := { plan with zipIntFunctions := plan.zipIntFunctions.map fun group =>
    { group with domain := { lowerInclusive := "0", upperInclusive := "5000" } } }
  check fails "reject: oversized domain" (rejects <| project (chosenPlan := badDomain))
  let stale := { context with rawVariables := context.rawVariables.drop 1 }
  check fails "reject: plan does not consume supplied vars exactly"
    (rejects <| project (chosenContext := stale))
  let wrongType := { context with sourceTypes := context.sourceTypes.map fun pair =>
    if pair.1 == "nk" then (pair.1, .seq .int) else pair }
  check fails "reject: source must be Map[Int,T]"
    (rejects <| project (chosenContext := wrongType))
  let nestedMap := { context with sourceTypes := context.sourceTypes.map fun pair =>
    if pair.1 == "nk" then (pair.1, .map .int (.map .int .int)) else pair }
  check fails "reject: nested non-string map is nonportable"
    (rejects <| project (chosenContext := nestedMap))
  let reserved := { plan with zipIntFunctions := plan.zipIntFunctions.map fun group =>
    { group with outputWireName := "__proto__" } }
  check fails "reject: reserved output wire key" (rejects <| project (chosenPlan := reserved))
  check fails "reject: unknown ITF root field"
    (rejects <| project (rawText := raw.replace "\"states\":" "\"evil\":0,\"states\":"))
  check fails "reject: unknown root metadata field"
    (rejects <| project (rawText := raw.replace "\"format\":\"ITF\""
      "\"format\":\"ITF\",\"evil\":0"))
  let (largePlan, largeContext, smallRaw) := expansionFixture
  let expanded := Codec.ModelInterfaceTraceProjectionJson.projectTraceBytes
    source.toUTF8 smallRaw largePlan largeContext
  check fails "reject: small raw input cannot request excessive construction work"
    (smallRaw.size < maxProjectedTraceArtifactBytesV1 &&
      errorContains "projection work estimate" expanded)

def scenarioCodec (fails : Failures) (result : TraceProjectionResult) : IO Unit := do
  let planBytes := Codec.ModelInterfaceTraceProjectionJson.canonicalPlanBytes plan
  match Codec.ModelInterfaceTraceProjectionJson.parsePlanBytes planBytes with
  | .error error => check fails "codec: canonical plan parses" false error
  | .ok decoded =>
      check fails "codec: plan round trip canonical"
        (Codec.ModelInterfaceTraceProjectionJson.canonicalPlanBytes decoded == planBytes)
  let planText := String.fromUTF8! planBytes
  check fails "codec: unknown plan field rejected"
    (!(Codec.ModelInterfaceTraceProjectionJson.parsePlanString
      (planText.replace "\"schema\":" "\"evil\":0,\"schema\":" )).isOk)
  check fails "codec: duplicate plan field rejected"
    (!(Codec.ModelInterfaceTraceProjectionJson.parsePlanString
      (planText.replace "\"schema\":\"mirrors.model-interface-trace-projection/v1\""
       "\"schema\":\"mirrors.model-interface-trace-projection/v1\",\"schema\":\"mirrors.model-interface-trace-projection/v1\"")).isOk)
  let receiptBytes := Codec.ModelInterfaceTraceProjectionJson.canonicalReceiptBytes result.receipt
  match Codec.ModelInterfaceTraceProjectionJson.parseReceiptBytes receiptBytes with
  | .error error => check fails "codec: strict receipt parses" false error
  | .ok decoded =>
      check fails "codec: receipt round trip"
        (Codec.ModelInterfaceTraceProjectionJson.canonicalReceiptBytes decoded == receiptBytes)
  let resultBytes := Codec.ModelInterfaceTraceProjectionJson.canonicalResultBytes result
  match Codec.ModelInterfaceTraceProjectionJson.parseResultBytes resultBytes with
  | .error error => check fails "codec: strict combined result parses" false error
  | .ok decoded =>
      check fails "codec: combined result round trip"
        (Codec.ModelInterfaceTraceProjectionJson.canonicalResultBytes decoded == resultBytes)
  let resultText := String.fromUTF8! resultBytes
  check fails "codec: unknown combined-result field rejected"
    (!(Codec.ModelInterfaceTraceProjectionJson.parseResultString
      (resultText.replace "\"schema\":" "\"evil\":0,\"schema\":" )).isOk)

def run : IO UInt32 := do
  let fails ← IO.mkRef []
  let result ← scenarioHappy fails
  scenarioReject fails
  result.forM (scenarioCodec fails)
  let failures ← fails.get
  if failures.isEmpty then IO.println "MODEL INTERFACE TRACE PROJECTION SPEC GREEN"; return 0
  else failures.forM (fun failure => IO.eprintln s!"FAIL: {failure}"); return 1

end ModelInterfaceTraceProjectionSpec

def main : IO UInt32 := ModelInterfaceTraceProjectionSpec.run
