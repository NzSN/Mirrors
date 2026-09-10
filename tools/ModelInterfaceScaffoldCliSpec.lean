import Codec.ModelInterfaceScaffoldJson

/-!
# Scaffold CLI regression gate

Exercises proposal-only publication using an RBT-shaped trace whose integer-key
maps must remain opaque to the action-label inspector.
-/

namespace ModelInterfaceScaffoldCliSpec

abbrev Failures := IO.Ref (List String)

private def check (failures : Failures) (name : String) (condition : Bool)
    (detail : String := "") : IO Unit := do
  if !condition then
    failures.modify (· ++ [if detail.isEmpty then name else s!"{name}: {detail}"])

private def source : String := String.intercalate "\n" [
  "-------------------- MODULE RBT --------------------",
  "EXTENDS Integers",
  "VARIABLES",
  "  \\* @type: Int -> Int;",
  "  nk,",
  "  \\* @type: Int -> Str;",
  "  nc,",
  "  \\* @type: Int;",
  "  root,",
  "  \\* @type: Str;",
  "  action_taken,",
  "  \\* @type: Int;",
  "  step_count,",
  "  \\* @type: { keyParam : Int };",
  "  parameters",
  "====================================================",
  ""
]

private def evidence : String := String.intercalate "\n" [
  "{",
  "  \"#meta\": {\"format\":\"ITF\",\"varTypes\":{",
  "    \"nk\":\"(Int -> Int)\",\"nc\":\"(Int -> Str)\",\"root\":\"Int\",",
  "    \"action_taken\":\"Str\",\"step_count\":\"Int\",",
  "    \"parameters\":\"{ keyParam: Int }\"}},",
  "  \"param_vars\": null,",
  "  \"vars\":[\"nk\",\"nc\",\"root\",\"action_taken\",\"step_count\",\"parameters\"],",
  "  \"states\":[",
  "    {\"#meta\":{\"index\":0},\"action_taken\":\"init\",",
  "     \"nk\":{\"#map\":[[{\"#bigint\":\"0\"},{\"#bigint\":\"0\"}],[{\"#bigint\":\"1\"},{\"#bigint\":\"0\"}]]},",
  "     \"nc\":{\"#map\":[[{\"#bigint\":\"0\"},\"B\"],[{\"#bigint\":\"1\"},\"B\"]]},",
  "     \"root\":{\"#bigint\":\"0\"},\"step_count\":{\"#bigint\":\"0\"},",
  "     \"parameters\":{\"keyParam\":{\"#bigint\":\"0\"}}},",
  "    {\"#meta\":{\"index\":1},\"action_taken\":\"insert\",",
  "     \"nk\":{\"#map\":[[{\"#bigint\":\"0\"},{\"#bigint\":\"0\"}],[{\"#bigint\":\"1\"},{\"#bigint\":\"7\"}]]},",
  "     \"nc\":{\"#map\":[[{\"#bigint\":\"0\"},\"B\"],[{\"#bigint\":\"1\"},\"B\"]]},",
  "     \"root\":{\"#bigint\":\"1\"},\"step_count\":{\"#bigint\":\"1\"},",
  "     \"parameters\":{\"keyParam\":{\"#bigint\":\"7\"}}}",
  "  ]",
  "}",
  ""
]

private def projectionPlan : String :=
  "{\"schema\":\"mirrors.model-interface-trace-projection/v1\"," ++
  "\"exactCopyVariables\":[\"root\",\"action_taken\",\"step_count\",\"parameters\"]," ++
  "\"zipIntFunctions\":[{\"outputWireName\":\"nodes\"," ++
  "\"domain\":{\"lowerInclusive\":\"0\",\"upperInclusive\":\"1\"}," ++
  "\"fields\":[{\"name\":\"key\",\"sourceVariable\":\"nk\"}," ++
  "{\"name\":\"color\",\"sourceVariable\":\"nc\"}]}]}\n"

private def invoke (spec evidence proposal : System.FilePath)
    (extra : Array String := #[]) : IO IO.Process.Output :=
  IO.Process.output {
    cmd := ".lake/build/bin/model_interface_gen"
    args := #["scaffold", "--spec", spec.toString, "--evidence", evidence.toString,
      "--param-var", "parameters", "--proposal", proposal.toString,
      "--diagnostics", "json"] ++ extra
  }

private def fileExists (path : System.FilePath) : IO Bool := path.pathExists

def run : IO UInt32 := do
  let failures ← IO.mkRef ([] : List String)
  let root ← IO.FS.createTempDir
  try
    let spec := root / "RBT.tla"
    let evidencePath := root / "rbt.itf.json"
    IO.FS.writeFile spec source
    IO.FS.writeFile evidencePath evidence

    let proposalA := root / "a.proposal.json"
    let proposalB := root / "b.proposal.json"
    let first ← invoke spec evidencePath proposalA
    let second ← invoke spec evidencePath proposalB
    check failures "RBT-shaped raw evidence succeeds" (first.exitCode == 0)
      first.stderr
    check failures "success diagnostics are canonical and empty"
      (first.stderr == "[]\n") first.stderr
    check failures "scaffold output is deterministic"
      (first.exitCode == 0 && second.exitCode == 0 &&
        (← IO.FS.readBinFile proposalA) == (← IO.FS.readBinFile proposalB))
    match Codec.ModelInterfaceScaffoldJson.parseProposalBytes
        (← IO.FS.readBinFile proposalA) with
    | .error error => check failures "proposal is a strict envelope" false error
    | .ok proposal =>
        check failures "initializer remains unsealed"
          (proposal.unsealedInitializers == ["Initialize"])
        check failures "transition remains unsealed"
          (proposal.unsealedActions == ["Insert"])
        check failures "integer-key map obligations are retained"
          (proposal.targetSupportObligations.map (·.stableId) == ["Nc", "Nk"])

    let planPath := root / "rbt.projection.json"
    IO.FS.writeFile planPath projectionPlan
    let projectedProposal := root / "projected.proposal.json"
    let projected ← invoke spec evidencePath projectedProposal
      #["--projection", planPath.toString]
    check failures "scaffold accepts compiler-owned raw RBT projection"
      (projected.exitCode == 0) projected.stderr
    match Codec.ModelInterfaceScaffoldJson.parseProposalBytes
        (← IO.FS.readBinFile projectedProposal) with
    | .error error => check failures "projected proposal is strict" false error
    | .ok proposal =>
        check failures "projected scaffold yields Nodes observation"
          (proposal.contract.observations.any (·.id == "Nodes"))
        check failures "projected scaffold clears map obligations"
          proposal.targetSupportObligations.isEmpty
        check failures "projected scaffold binds provenance hash triple"
          proposal.projection.isSome

    let staleSpec := root / "RBT-stale.tla"
    IO.FS.writeFile staleSpec (source.replace "  nc,\n" "  nodes,\n")
    let staleProposal := root / "stale.proposal.json"
    let staleFirst ← invoke staleSpec evidencePath staleProposal
    let staleSecond ← invoke staleSpec evidencePath staleProposal
    check failures "stale source mismatch is a finding"
      (staleFirst.exitCode == 1 && staleFirst.stderr.contains "MIC-C-EVIDENCE-001")
      staleFirst.stderr
    check failures "stale mismatch diagnostics are deterministic"
      (staleFirst.stderr == staleSecond.stderr) s!"first={staleFirst.stderr} second={staleSecond.stderr}"
    check failures "stale mismatch performs no write" (!(← fileExists staleProposal))

    let occupied := root / "occupied.proposal.json"
    IO.FS.writeFile occupied "KEEP\n"
    let refused ← invoke spec evidencePath occupied
    check failures "default publication refuses overwrite"
      (refused.exitCode == 1 && (← IO.FS.readFile occupied) == "KEEP\n") refused.stderr
    let replaced ← invoke spec evidencePath occupied #["--replace"]
    check failures "explicit replace succeeds atomically"
      (replaced.exitCode == 0 && (← IO.FS.readFile occupied) != "KEEP\n") replaced.stderr
    check failures "replacement remains a strict proposal"
      (Codec.ModelInterfaceScaffoldJson.parseProposalBytes
        (← IO.FS.readBinFile occupied)).isOk

    let malformedEvidence := root / "malformed.itf.json"
    IO.FS.writeFile malformedEvidence
      (evidence.replace "\"action_taken\":\"insert\""
        "\"action_taken\":{\"#bigint\":\"1\"}")
    let malformedProposal := root / "malformed.proposal.json"
    let malformed ← invoke spec malformedEvidence malformedProposal
    check failures "non-string action is rejected without writing"
      (malformed.exitCode == 1 && !(← fileExists malformedProposal)) malformed.stderr

    let allInitEvidence := root / "all-init.itf.json"
    IO.FS.writeFile allInitEvidence
      (evidence.replace "\"action_taken\":\"insert\"" "\"action_taken\":\"init\"")
    let allInitProposal := root / "all-init.proposal.json"
    let allInit ← invoke spec allInitEvidence allInitProposal
    check failures "action observed in both phases is rejected without writing"
      (allInit.exitCode == 1 && allInit.stderr.contains "MIC-S-ACTION-001" &&
        !(← fileExists allInitProposal)) allInit.stderr

    let unknownEvidence := root / "unknown.itf.json"
    IO.FS.writeFile unknownEvidence
      (evidence.replace "{\n  \"#meta\"" "{\n  \"unknown\":true,\n  \"#meta\"")
    let unknownProposal := root / "unknown.proposal.json"
    let unknown ← invoke spec unknownEvidence unknownProposal
    check failures "unknown evidence field is rejected without writing"
      (unknown.exitCode == 1 && !(← fileExists unknownProposal)) unknown.stderr

    let usageProposal := root / "usage.proposal.json"
    let usage ← invoke spec evidencePath usageProposal #["--unknown", "value"]
    check failures "unknown CLI option exits as usage without writing"
      (usage.exitCode == 2 && !(← fileExists usageProposal)) usage.stderr
  finally
    IO.FS.removeDirAll root
  let found ← failures.get
  if found.isEmpty then
    IO.println "MODEL INTERFACE SCAFFOLD CLI SPEC GREEN"
    return 0
  for failure in found do IO.eprintln s!"FAIL {failure}"
  IO.eprintln s!"{found.length} FAILURES"
  return 1

end ModelInterfaceScaffoldCliSpec

def main : IO UInt32 := ModelInterfaceScaffoldCliSpec.run
