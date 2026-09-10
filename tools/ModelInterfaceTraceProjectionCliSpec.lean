import Codec.ModelInterfaceTraceProjectionJson
import Core.ModelInterface.Sha256

namespace ModelInterfaceTraceProjectionCliSpec

abbrev Failures := IO.Ref (List String)

private def check (failures : Failures) (name : String) (condition : Bool)
    (detail : String := "") : IO Unit := do
  if !condition then
    failures.modify (· ++ [if detail.isEmpty then name else s!"{name}: {detail}"])

private def source : String := String.intercalate "\n" [
  "-------------------- MODULE MiniRBT --------------------",
  "VARIABLES",
  "  \\* @type: Int -> Int;",
  "  nk,",
  "  \\* @type: Str;",
  "  action_taken",
  "========================================================",
  ""
]

private def staleSource : String := source.replace "  nk,\n" "  nodes,\n"

private def rawEvidence : String :=
  "{\"#meta\":{\"format\":\"ITF\",\"varTypes\":{" ++
  "\"nk\":\"(Int -> Int)\",\"action_taken\":\"Str\"}}," ++
  "\"vars\":[\"nk\",\"action_taken\"],\"states\":[" ++
  "{\"#meta\":{\"index\":0},\"action_taken\":\"init\"," ++
  "\"nk\":{\"#map\":[[{\"#bigint\":\"0\"},{\"#bigint\":\"0\"}]," ++
  "[{\"#bigint\":\"1\"},{\"#bigint\":\"0\"}]]}}," ++
  "{\"#meta\":{\"index\":1},\"action_taken\":\"insert\"," ++
  "\"nk\":{\"#map\":[[{\"#bigint\":\"0\"},{\"#bigint\":\"0\"}]," ++
  "[{\"#bigint\":\"1\"},{\"#bigint\":\"7\"}]]}}]}\n"

private def plan : String :=
  "{\"schema\":\"mirrors.model-interface-trace-projection/v1\"," ++
  "\"exactCopyVariables\":[\"action_taken\"],\"zipIntFunctions\":[{" ++
  "\"outputWireName\":\"nodes\",\"domain\":{" ++
  "\"lowerInclusive\":\"0\",\"upperInclusive\":\"1\"}," ++
  "\"fields\":[{\"name\":\"key\",\"sourceVariable\":\"nk\"}]}]}\n"

private def workNames : List String :=
  (List.range 31).map fun index => s!"m{index}"

private def excessiveWorkSource : String := String.intercalate "\n" [
  "-------------------- MODULE WorkBound --------------------",
  "VARIABLES " ++ String.intercalate ", " (workNames ++ ["action_taken"]),
  "==========================================================",
  ""
]

private def excessiveWorkEvidence : String :=
  let typeFields := (workNames.map fun name => s!"\"{name}\":\"(Int -> Int)\"") ++
    ["\"action_taken\":\"Str\""]
  let variables := (workNames ++ ["action_taken"]).map fun name => s!"\"{name}\""
  let state (index : Nat) (action : String) :=
    "{\"#meta\":{\"index\":" ++ toString index ++ "}," ++
      String.intercalate "," ((workNames.map fun name => s!"\"{name}\":null") ++
        [s!"\"action_taken\":\"{action}\""]) ++ "}"
  "{\"#meta\":{\"format\":\"ITF\",\"varTypes\":{" ++
    String.intercalate "," typeFields ++ "}},\"vars\":[" ++
    String.intercalate "," variables ++ "],\"states\":[" ++
    state 0 "init" ++ "," ++ state 1 "step" ++ "]}\n"

private def excessiveWorkPlan : String :=
  let fields := workNames.mapIdx fun index name =>
    "{\"name\":\"f" ++ toString index ++
      "\",\"sourceVariable\":\"" ++ name ++ "\"}"
  "{\"schema\":\"mirrors.model-interface-trace-projection/v1\"," ++
    "\"exactCopyVariables\":[\"action_taken\"],\"zipIntFunctions\":[{" ++
    "\"outputWireName\":\"nodes\",\"domain\":{" ++
    "\"lowerInclusive\":\"0\",\"upperInclusive\":\"4095\"},\"fields\":[" ++
    String.intercalate "," fields ++ "]}]}\n"

private def outputBoundField : String :=
  String.ofList (List.replicate 240 'x')

private def excessiveOutputEvidence : String :=
  let entries := (List.range 4096).map fun index =>
    "[{\"#bigint\":\"" ++ toString index ++ "\"},{\"#bigint\":\"0\"}]"
  let mapValue := "{\"#map\":[" ++ String.intercalate "," entries ++ "]}"
  let states := (List.range 18).map fun index =>
    "{\"#meta\":{\"index\":" ++ toString index ++ "},\"action_taken\":\"" ++
      (if index == 0 then "init" else "step") ++ "\",\"nk\":" ++ mapValue ++ "}"
  "{\"#meta\":{\"format\":\"ITF\",\"varTypes\":{" ++
    "\"nk\":\"(Int -> Int)\",\"action_taken\":\"Str\"}}," ++
    "\"vars\":[\"nk\",\"action_taken\"],\"states\":[" ++
    String.intercalate "," states ++ "]}\n"

private def excessiveOutputPlan : String :=
  "{\"schema\":\"mirrors.model-interface-trace-projection/v1\"," ++
    "\"exactCopyVariables\":[\"action_taken\"],\"zipIntFunctions\":[{" ++
    "\"outputWireName\":\"nodes\",\"domain\":{" ++
    "\"lowerInclusive\":\"0\",\"upperInclusive\":\"4095\"},\"fields\":[{" ++
    "\"name\":\"" ++ outputBoundField ++ "\",\"sourceVariable\":\"nk\"}]}]}\n"

private def invoke (spec evidence projection out receipt : System.FilePath)
    (replace : Bool := false) : IO IO.Process.Output :=
  IO.Process.output {
    cmd := ".lake/build/bin/model_interface_gen"
    args := #["project-trace", "--spec", spec.toString,
      "--evidence", evidence.toString, "--projection", projection.toString,
      "--out", out.toString, "--receipt", receipt.toString,
      "--diagnostics", "json"] ++ (if replace then #["--replace"] else #[])
  }

private abbrev NullChild := IO.Process.Child
  ({ stdin := .null, stdout := .null, stderr := .null } : IO.Process.StdioConfig)

private def spawnInvoke (spec evidence projection out receipt : System.FilePath) :
    IO NullChild :=
  IO.Process.spawn {
    cmd := ".lake/build/bin/model_interface_gen"
    args := #["project-trace", "--spec", spec.toString,
      "--evidence", evidence.toString, "--projection", projection.toString,
      "--out", out.toString, "--receipt", receipt.toString,
      "--replace", "--diagnostics", "json"]
    stdin := .null
    stdout := .null
    stderr := .null
  }

private def fileExists (path : System.FilePath) : IO Bool := path.pathExists

private def withoutTrailingLf (value : String) : String :=
  if value.endsWith "\n" then (value.dropEnd 1).toString else value

def run : IO UInt32 := do
  let failures ← IO.mkRef ([] : List String)
  let root ← IO.FS.createTempDir
  try
    let spec := root / "MiniRBT.tla"
    let evidence := root / "raw.itf.json"
    let projection := root / "projection.json"
    IO.FS.writeFile spec source
    IO.FS.writeFile evidence rawEvidence
    IO.FS.writeFile projection plan

    let projected := root / "projected.itf.json"
    let receiptPath := root / "projection.receipt.json"
    let success ← invoke spec evidence projection projected receiptPath
    check failures "project-trace succeeds" (success.exitCode == 0) success.stderr
    check failures "project-trace success diagnostics are empty"
      (success.stderr == "[]\n") success.stderr
    let projectedText ← IO.FS.readFile projected
    check failures "projected trace contains portable nodes"
      (projectedText.contains "\"nodes\"" && !projectedText.contains "\"nk\"")
      projectedText
    match Codec.ModelInterfaceTraceProjectionJson.parseReceiptBytes
        (← IO.FS.readBinFile receiptPath) with
    | .error error => check failures "receipt is strict" false error
    | .ok receipt =>
        let parsedPlan := Codec.ModelInterfaceTraceProjectionJson.parsePlanString plan
        match parsedPlan with
        | .error error => check failures "test projection plan parses" false error
        | .ok parsedPlan =>
            let expectedSource := Core.ModelInterface.Sha256.digestDomainHex
              Codec.ModelInterfaceTraceProjectionJson.projectionSourceDigestDomainV1
              source.toUTF8
            let expectedRaw := Core.ModelInterface.Sha256.digestDomainHex
              Codec.ModelInterfaceTraceProjectionJson.projectionRawDigestDomainV1
              rawEvidence.toUTF8
            let expectedPlan := Core.ModelInterface.Sha256.digestDomainHex
              Codec.ModelInterfaceTraceProjectionJson.projectionPlanDigestDomainV1
              (Codec.ModelInterfaceTraceProjectionJson.canonicalPlanBytes parsedPlan)
            let expectedOutput := Core.ModelInterface.Sha256.digestDomainHex
              Codec.ModelInterfaceTraceProjectionJson.projectionOutputDigestDomainV1
              (withoutTrailingLf projectedText).toUTF8
            check failures "receipt binds source/raw/plan/output hashes"
              (receipt.sourceSha256 == expectedSource && receipt.rawSha256 == expectedRaw &&
                receipt.planSha256 == expectedPlan && receipt.outputSha256 == expectedOutput)
            let tamperedDigest := Core.ModelInterface.Sha256.digestDomainHex
              Codec.ModelInterfaceTraceProjectionJson.projectionOutputDigestDomainV1
              ((withoutTrailingLf projectedText) ++ " ").toUTF8
            check failures "output tampering changes receipt hash"
              (tamperedDigest != receipt.outputSha256)

    -- A retained lock models a writer inside the backup/publish/cleanup
    -- transaction. Two different projection writers start concurrently; both
    -- must fail closed and leave the seed pair hash-consistent.
    let projectionB := root / "projection-b.json"
    let projectionC := root / "projection-c.json"
    IO.FS.writeFile projectionB (plan.replace "\"name\":\"key\"" "\"name\":\"keyB\"")
    IO.FS.writeFile projectionC (plan.replace "\"name\":\"key\"" "\"name\":\"keyC\"")
    let heldLock : System.FilePath :=
      projected.toString ++ ".model-interface-projection.lock"
    IO.FS.writeFile heldLock "simulated-active-writer\n"
    let writerB ← spawnInvoke spec evidence projectionB projected receiptPath
    let writerC ← spawnInvoke spec evidence projectionC projected receiptPath
    let writerBCode ← writerB.wait
    let writerCCode ← writerC.wait
    IO.FS.removeFile heldLock
    check failures "overlapping distinct writers fail on the shared target lock"
      (writerBCode == 1 && writerCCode == 1)
      s!"writerB={writerBCode}, writerC={writerCCode}"
    match Codec.ModelInterfaceTraceProjectionJson.parseReceiptBytes
        (← IO.FS.readBinFile receiptPath) with
    | .error error => check failures "contention leaves strict receipt" false error
    | .ok receipt =>
        let finalTrace ← IO.FS.readFile projected
        let finalDigest := Core.ModelInterface.Sha256.digestDomainHex
          Codec.ModelInterfaceTraceProjectionJson.projectionOutputDigestDomainV1
          (withoutTrailingLf finalTrace).toUTF8
        check failures "contention cannot mix projected output and receipt"
          (finalDigest == receipt.outputSha256)

    let originalProjected ← IO.FS.readBinFile projected
    let originalReceipt ← IO.FS.readBinFile receiptPath
    let refused ← invoke spec evidence projection projected receiptPath
    check failures "default rerun refuses both existing targets"
      (refused.exitCode == 1 && (← IO.FS.readBinFile projected) == originalProjected &&
        (← IO.FS.readBinFile receiptPath) == originalReceipt) refused.stderr

    let conflictOut := root / "conflict-out.json"
    let conflictReceipt := root / "conflict-receipt.json"
    IO.FS.writeFile conflictOut "KEEP-OUT\n"
    let outConflict ← invoke spec evidence projection conflictOut conflictReceipt
    check failures "out conflict writes neither target"
      (outConflict.exitCode == 1 && (← IO.FS.readFile conflictOut) == "KEEP-OUT\n" &&
        !(← fileExists conflictReceipt)) outConflict.stderr

    let secondOut := root / "second-out.json"
    let secondReceipt := root / "second-receipt.json"
    IO.FS.writeFile secondReceipt "KEEP-RECEIPT\n"
    let receiptConflict ← invoke spec evidence projection secondOut secondReceipt
    check failures "receipt conflict writes neither target"
      (receiptConflict.exitCode == 1 && !(← fileExists secondOut) &&
        (← IO.FS.readFile secondReceipt) == "KEEP-RECEIPT\n") receiptConflict.stderr

    let replaced ← invoke spec evidence projection conflictOut secondReceipt true
    check failures "replace updates both validated targets"
      (replaced.exitCode == 0 && (← IO.FS.readFile conflictOut) != "KEEP-OUT\n" &&
        (← IO.FS.readFile secondReceipt) != "KEEP-RECEIPT\n") replaced.stderr

    let invalidPlan := root / "invalid-plan.json"
    IO.FS.writeFile invalidPlan (plan.replace "\"zipIntFunctions\"" "\"unknown\"")
    let invalidOut := root / "invalid-out.json"
    let invalidReceipt := root / "invalid-receipt.json"
    let invalid ← invoke spec evidence invalidPlan invalidOut invalidReceipt
    check failures "invalid plan performs no writes"
      (invalid.exitCode == 1 && !(← fileExists invalidOut) &&
        !(← fileExists invalidReceipt)) invalid.stderr

    let workSpec := root / "WorkBound.tla"
    let workEvidencePath := root / "work.itf.json"
    let workPlan := root / "work-plan.json"
    IO.FS.writeFile workSpec excessiveWorkSource
    IO.FS.writeFile workEvidencePath excessiveWorkEvidence
    IO.FS.writeFile workPlan excessiveWorkPlan
    let workOut := root / "work-out.json"
    let workReceipt := root / "work-receipt.json"
    let excessive ← invoke workSpec workEvidencePath workPlan workOut workReceipt
    check failures "projection work bound fails before either output is written"
      (excessive.exitCode == 1 && !(← fileExists workOut) &&
        !(← fileExists workReceipt)) excessive.stderr

    let outputEvidencePath := root / "large-output.itf.json"
    let outputPlan := root / "large-output-plan.json"
    IO.FS.writeFile outputEvidencePath excessiveOutputEvidence
    IO.FS.writeFile outputPlan excessiveOutputPlan
    let boundedOut := root / "bounded-out.json"
    let boundedReceipt := root / "bounded-receipt.json"
    let bounded ← invoke spec outputEvidencePath outputPlan boundedOut boundedReceipt
    check failures "projected artifact byte bound writes neither output"
      (bounded.exitCode == 1 && !(← fileExists boundedOut) &&
        !(← fileExists boundedReceipt)) bounded.stderr

    let staleSpecPath := root / "Stale.tla"
    IO.FS.writeFile staleSpecPath staleSource
    let absentPlan := root / "absent-plan.json"
    let staleOut := root / "stale-out.json"
    let staleReceipt := root / "stale-receipt.json"
    let stale ← invoke staleSpecPath evidence absentPlan staleOut staleReceipt
    check failures "stale source fails before projection plan read"
      (stale.exitCode == 1 && stale.stderr.contains "MIC-S-SOURCE-001" &&
        !(← fileExists staleOut) && !(← fileExists staleReceipt)) stale.stderr

    let aliasTarget := root / "alias.json"
    let aliasResult ← invoke spec evidence projection aliasTarget aliasTarget
    check failures "identical targets are rejected without a write"
      (aliasResult.exitCode == 1 && !(← fileExists aliasTarget)) aliasResult.stderr
  finally
    IO.FS.removeDirAll root
  let found ← failures.get
  if found.isEmpty then
    IO.println "MODEL INTERFACE TRACE PROJECTION CLI SPEC GREEN"
    return 0
  for failure in found do IO.eprintln s!"FAIL {failure}"
  IO.eprintln s!"{found.length} FAILURES"
  return 1

end ModelInterfaceTraceProjectionCliSpec

def main : IO UInt32 := ModelInterfaceTraceProjectionCliSpec.run
