import Shell.ModelInterface.ScaffoldWorkflow

/-! Synthetic approval records below are explicit test data. These tests do
not authorize or infer human review of any application contract. -/
namespace ModelInterfaceWorkflowSpec
open Core.ModelInterface Shell.ModelInterface
open ScaffoldWorkflow
namespace WJ
abbrev reviewFileBytes := Codec.ModelInterfaceScaffoldWorkflowJson.reviewFileBytes
abbrev parseReviewBytes := Codec.ModelInterfaceScaffoldWorkflowJson.parseReviewBytes
abbrev parseProposalBytes := Codec.ModelInterfaceScaffoldWorkflowJson.parseProposalBytes
end WJ

private def require (name : String) (condition : Bool) : IO Unit := do
  if !condition then throw (IO.userError s!"FAIL: {name}")
  IO.println s!"PASS: {name}"
private def ok (name : String) (result : Except Compiler.CompilerError α) : IO α := do
  match result with
  | .ok value => return value
  | .error error => throw (IO.userError s!"{name}: {error.message}: {repr error.diagnostics}")
private def reject (name : String) (result : Except ε α) : IO Unit :=
  require name (!result.isOk)

private def source := "---- MODULE Workflow ----\nEXTENDS Shared\nVARIABLES action_taken, parameters\n====\n"
private def dependency := "---- MODULE Shared ----\nVARIABLE value\n====\n"
private def raw (n : String) (action : String := "add") : String :=
  "{\"#meta\":{\"varTypes\":{\"value\":\"Int\",\"action_taken\":\"Str\",\"parameters\":\"{ amount: Int }\"}}," ++
  "\"vars\":[\"value\",\"action_taken\",\"parameters\"],\"states\":[" ++
  "{\"value\":{\"#bigint\":\"0\"},\"action_taken\":\"init\",\"parameters\":{\"amount\":{\"#bigint\":\"0\"}}}," ++
  "{\"value\":{\"#bigint\":\"" ++ n ++ "\"},\"action_taken\":\"" ++ action ++
  "\",\"parameters\":{\"amount\":{\"#bigint\":\"1\"}}}]}\n"

private def approved (c : ReviewableCompilation) : ScaffoldReview := {
  approved := true
  proposalSha256 := c.proposalSha256
  complete := true
  initializers := c.proposal.observedInitializers
  transitions := c.proposal.observedTransitions
  contract := c.proposal.scaffold.contract
  replacements := []
  obligations := [] }

private def pureReviews (compiled : ReviewableCompilation) : IO Unit := do
  let review := approved compiled
  let validate := validateScaffoldReview compiled.proposal compiled.proposalSha256
  require "complete unchanged synthetic review admitted" (validate review).isOk
  reject "false approval rejected" (validate { review with approved := false })
  reject "missing closed-world declaration rejected" (validate { review with complete := false })
  reject "omitted observed transition rejected" (validate { review with transitions := [] })
  reject "cross-phase universe overlap rejected" (validate { review with initializers := review.transitions })
  reject "stale proposal digest rejected" (validate { review with proposalSha256 := String.ofList (List.replicate 64 '0') })
  reject "silently dropped observation rejected" (validate {
    review with contract := { review.contract with observations := [] } })
  reject "silently dropped input rejected" (validate {
    review with contract := { review.contract with actions := review.contract.actions.map fun a => { a with inputs := [] } } })
  let renamed : ScaffoldReview := {
    review with
    contract := { review.contract with observations := review.contract.observations.map fun o => { o with id := "RenamedValue" } }
    replacements := [{ kind := "observation", fromId := "Value", toId := "RenamedValue" }] }
  require "explicit observation replacement admitted" (validate renamed).isOk
  reject "unacknowledged observation replacement rejected" (validate { renamed with replacements := [] })
  reject "unknown replacement decision rejected" (validate {
    review with replacements := [{ kind := "observation", fromId := "Unknown", toId := "Value" }] })
  let kept : ContractObservation := { id := "Kept", wireName := "kept", expectedType := some .int }
  let twoObservations : ReviewableScaffold := {
    compiled.proposal with scaffold := { compiled.proposal.scaffold with
      contract := { review.contract with observations := review.contract.observations ++ [kept] } } }
  reject "replacement cannot collapse onto a retained subject"
    (validateScaffoldReview twoObservations compiled.proposalSha256 {
      review with
      contract := { review.contract with observations := [kept] }
      replacements := [{ kind := "observation", fromId := "Value", toId := "Kept" }] })
  let renameAction : ScaffoldReview := {
    review with
    contract := { review.contract with actions := review.contract.actions.map fun a => { a with id := "Increase" } }
    replacements := [{ kind := "action", fromId := "Add", toId := "Increase" }] }
  reject "renamed action requires scoped input decision" (validate renameAction)
  require "explicit scoped input replacement admitted" (validate {
    renameAction with replacements := renameAction.replacements ++
      [{ kind := "input", fromId := "Add/Amount", toId := "Increase/Amount" }] }).isOk
  let reviewRaw := String.fromUTF8! (WJ.reviewFileBytes review)
  reject "missing approval key rejected by strict codec"
    (WJ.parseReviewBytes (reviewRaw.replace "\"approved\":true," "").toUTF8)
  reject "false approval rejected by strict codec"
    (WJ.parseReviewBytes (reviewRaw.replace "\"approved\":true" "\"approved\":false").toUTF8)
  reject "duplicate approval rejected by strict scanner"
    (WJ.parseReviewBytes (reviewRaw.replace "\"approved\":true" "\"approved\":true,\"approved\":true").toUTF8)
  reject "unknown review field rejected"
    (WJ.parseReviewBytes (reviewRaw.replace "\"approved\":true" "\"approved\":true,\"unreviewed\":true").toUTF8)
  reject "legacy proposal requires reviewable regeneration"
    (WJ.parseProposalBytes (Codec.ModelInterfaceScaffoldJson.canonicalFileBytes compiled.proposal.scaffold))
  let obligationProposal : ReviewableScaffold := {
    compiled.proposal with scaffold := { compiled.proposal.scaffold with
      targetSupportObligations := [{ stableId := "Value", type := .map .int .int }] } }
  let validateObligation := validateScaffoldReview obligationProposal compiled.proposalSha256
  reject "missing obligation disposition rejected" (validateObligation review)
  reject "invalid obligation disposition rejected" (validateObligation {
    review with obligations := [{ stableId := "Value", disposition := "ignore", target := "mirrorecma-async-v1", reason := "test" }] })
  let evidenceWith (type : ModelType) : ModelEvidence := {
    compiled.evidence with typeFacts := compiled.evidence.typeFacts.map fun fact =>
      if fact.modelPath.root == "value" then { fact with type } else fact }
  let member (sha : String) (type : ModelType) : EvidenceCorpusMember := {
    rawFileSha256 := sha
    evidence := evidenceWith type
    initializerLabels := ["init"]
    transitionLabels := ["add"] }
  let recordAB := ModelType.record [{ wireName := "a", type := .int }, { wireName := "b", type := .str }]
  let recordBA := ModelType.record [{ wireName := "b", type := .str }, { wireName := "a", type := .int }]
  require "compatible record field order merges canonically"
    (mergeEvidenceCorpus [member "a" recordAB, member "b" recordBA]).isOk
  reject "closed records cannot silently widen"
    (mergeEvidenceCorpus [member "a" recordAB, member "b" (.record [{ wireName := "a", type := .int }])])
  reject "closed variants cannot silently widen"
    (mergeEvidenceCorpus [member "a" (.variant [{ tag := "A", payload := .int }]),
      member "b" (.variant [{ tag := "B", payload := .int }])])

private def scenario (root : System.FilePath) : IO Unit := do
  let spec := root / "Workflow.tla"
  let imported := root / "Shared.tla"
  let first := root / "a.itf.json"
  let second := root / "b.itf.json"
  let proposalPath := root / "proposal.json"
  let reviewPath := root / "review.json"
  let sealedDir := root / "sealed"
  IO.FS.writeFile spec source
  IO.FS.writeFile imported dependency
  IO.FS.writeFile first (raw "1")
  IO.FS.writeFile second (raw "2")
  let paths : WorkflowPaths := {
    spec := spec.toString
    evidence := [first.toString, second.toString]
    paramVar := some "parameters" }
  let compiled ← ok "compile corpus" (← compileScaffold paths)
  let permuted ← ok "compile permuted corpus" (← compileScaffold { paths with evidence := paths.evidence.reverse })
  require "input permutation produces byte-identical proposal" (compiled.proposalBytes == permuted.proposalBytes)
  require "every exact raw input and imported source is bound"
    (compiled.proposal.members.length == 2 && compiled.proposal.sources.length == 2)
  reject "duplicate raw inputs rejected" (← compileScaffold { paths with evidence := [first.toString, first.toString] })
  IO.FS.writeFile second (raw "2" "init")
  reject "cross-document phase overlap rejected" (← compileScaffold paths)
  IO.FS.writeFile second ((raw "2").replace "\"value\":\"Int\"" "\"value\":\"Str\"")
  reject "incompatible structural members rejected" (← compileScaffold paths)
  IO.FS.writeFile second (raw "2")
  pureReviews compiled
  IO.FS.writeBinFile proposalPath compiled.proposalBytes
  IO.FS.writeBinFile reviewPath (WJ.reviewFileBytes (approved compiled))
  let sealed ← ok "publish synthetic reviewed artifact" (← sealScaffold paths proposalPath.toString reviewPath.toString sealedDir.toString)
  let resolved ← ok "resolve unchanged seal" (← compileResolveSealed paths sealedDir.toString)
  require "seal resolves with v2 workflow provenance" (resolved.lock.provenance.workflow.isSome)
  require "seal resolution preserves resolved semantics" (resolved.lock.semanticDigest == sealed.compilation.lock.semanticDigest)
  reject "existing immutable seal is preserved" (← sealScaffold paths proposalPath.toString reviewPath.toString sealedDir.toString)
  let originalReceipt ← IO.FS.readBinFile (sealedDir / "review-receipt.json")
  IO.FS.writeFile (sealedDir / "review-receipt.json") "{}\n"
  reject "tampered seal receipt rejected" (← compileResolveSealed paths sealedDir.toString)
  IO.FS.writeBinFile (sealedDir / "review-receipt.json") originalReceipt
  IO.FS.writeFile (sealedDir / "extra.json") "{}\n"
  reject "unexpected seal directory member rejected" (← compileResolveSealed paths sealedDir.toString)
  IO.FS.removeFile (sealedDir / "extra.json")
  IO.FS.writeFile imported (dependency.replace "VARIABLE value" "\\* imported revision\nVARIABLE value")
  reject "imported source drift rejects old review" (← compileSeal paths proposalPath.toString reviewPath.toString)
  IO.FS.writeFile imported dependency
  IO.FS.writeFile first (raw "3")
  let failedOut := root / "stale-seal"
  reject "raw value drift with identical type evidence rejects review"
    (← sealScaffold paths proposalPath.toString reviewPath.toString failedOut.toString)
  require "stale review publishes no partial output" (!(← failedOut.pathExists))
  let revised ← ok "fresh raw proposal" (← compileScaffold paths)
  IO.FS.writeBinFile proposalPath revised.proposalBytes
  IO.FS.writeBinFile reviewPath (WJ.reviewFileBytes (approved revised))
  let revisedSeal ← ok "fresh raw review" (← compileSeal paths proposalPath.toString reviewPath.toString)
  require "changed raw evidence changes provenance, preserves semantics"
    (revisedSeal.compilation.lock.semanticDigest == sealed.compilation.lock.semanticDigest &&
      revisedSeal.compilation.lock.provenanceDigest != sealed.compilation.lock.provenanceDigest)
  let failedPublication := root / "injected"
  reject "injected seal staging failure rejects publication"
    (← Publication.publishDirectory failedPublication.toString revisedSeal.files (some 2))
  require "injected failure leaves no partial seal" (!(← failedPublication.pathExists))
  -- A typed integer function creates a real support obligation. A reviewer
  -- cannot assert support that the requested emitter does not implement.
  IO.FS.writeFile first ((raw "1").replace "\"value\":\"Int\"" "\"value\":\"(Int -> Int)\"")
  let intPaths := { paths with evidence := [first.toString] }
  let intProposal ← ok "integer function proposal" (← compileScaffold intPaths)
  let intReview := { approved intProposal with obligations := [
    { stableId := "Value", disposition := "target-supported", target := "mirrorecma-async-v1", reason := "synthetic unsupported claim" }] }
  IO.FS.writeBinFile proposalPath intProposal.proposalBytes
  IO.FS.writeBinFile reviewPath (WJ.reviewFileBytes intReview)
  reject "claimed target support is checked by real emitter"
    (← compileSeal intPaths proposalPath.toString reviewPath.toString)
  let intRaw := ((raw "1").replace "\"value\":\"Int\"" "\"value\":\"(Int -> Int)\"")
    |>.replace "\"value\":{\"#bigint\":\"0\"}" "\"value\":{\"#map\":[[{\"#bigint\":\"0\"},{\"#bigint\":\"0\"}],[{\"#bigint\":\"1\"},{\"#bigint\":\"0\"}]]}"
    |>.replace "\"value\":{\"#bigint\":\"1\"}" "\"value\":{\"#map\":[[{\"#bigint\":\"0\"},{\"#bigint\":\"1\"}],[{\"#bigint\":\"1\"},{\"#bigint\":\"0\"}]]}"
  IO.FS.writeFile first intRaw
  let plan := root / "projection.json"
  IO.FS.writeFile plan ("{\"schema\":\"mirrors.model-interface-trace-projection/v1\"," ++
    "\"exactCopyVariables\":[\"action_taken\",\"parameters\"],\"zipIntFunctions\":[{" ++
    "\"outputWireName\":\"view\",\"domain\":{\"lowerInclusive\":\"0\",\"upperInclusive\":\"1\"}," ++
    "\"fields\":[{\"name\":\"entry\",\"sourceVariable\":\"value\"}]}]}\n")
  let projectedPaths := { intPaths with projection := some plan.toString }
  let projectedProposal ← ok "projected scaffold" (← compileScaffold projectedPaths)
  require "projection eliminates integer-map target obligations"
    projectedProposal.proposal.scaffold.targetSupportObligations.isEmpty
  IO.FS.writeBinFile proposalPath projectedProposal.proposalBytes
  IO.FS.writeBinFile reviewPath (WJ.reviewFileBytes (approved projectedProposal))
  let projectedSealDir := root / "projected-seal"
  let _ ← ok "projected seal" (← sealScaffold projectedPaths proposalPath.toString reviewPath.toString projectedSealDir.toString)
  let corpusDir := root / "corpus"
  let corpus ← ok "projected corpus" (← Corpus.projectCorpus {
    spec := spec.toString
    evidence := [first.toString]
    projection := plan.toString
    out := corpusDir.toString })
  let projectedLock ← ok "projected resolve with corpus" (← compileResolveSealed projectedPaths
    projectedSealDir.toString (some (corpusDir / "manifest.json").toString))
  require "corpus exact manifest file hash enters workflow provenance"
    (projectedLock.lock.provenance.workflow.bind (·.corpusManifestSha256) == some corpus.manifestSha256)
  let some firstMember := corpus.manifest.members.head? | throw (IO.userError "missing corpus member")
  let projectedTrace := corpusDir / firstMember.trace.path
  reject "ordinary resolution still rejects projected-only source variables" (← Compiler.compile {
    spec := spec.toString
    contract := (projectedSealDir / "contract.json").toString
    evidence := projectedTrace.toString
    paramVar := some "parameters" })
  let traceBytes ← IO.FS.readBinFile projectedTrace
  IO.FS.writeBinFile projectedTrace (traceBytes.append " ".toUTF8)
  reject "tampered corpus trace rejected before provenance binding"
    (← compileResolveSealed projectedPaths projectedSealDir.toString (some (corpusDir / "manifest.json").toString))

def run : IO UInt32 := do
  let root ← IO.FS.createTempDir
  try
    scenario root
    IO.println "model-interface workflow: all checks passed"
    return 0
  catch error =>
    IO.eprintln (toString error)
    return 1
  finally IO.FS.removeDirAll root

end ModelInterfaceWorkflowSpec

def main : IO UInt32 := ModelInterfaceWorkflowSpec.run
