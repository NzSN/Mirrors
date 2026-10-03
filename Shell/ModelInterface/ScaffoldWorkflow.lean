import Shell.ModelInterface.Compiler
import Shell.ModelInterface.Publication
import Shell.ModelInterface.Corpus
import Codec.ModelInterfaceScaffoldWorkflowJson
import Codec.ModelInterfaceCorpusJson

/-! Reviewed workflows authenticate captured originals before resolving a
projected view. All compile entrypoints are read-only. -/
namespace Shell.ModelInterface.ScaffoldWorkflow
open Core.ModelInterface
open Compiler (CompilerError Compilation)
namespace WJson
abbrev proposalDigest := Codec.ModelInterfaceScaffoldWorkflowJson.proposalDigest
abbrev reviewDigest := Codec.ModelInterfaceScaffoldWorkflowJson.reviewDigest
end WJson

structure WorkflowPaths where
  spec : String
  evidence : List String
  paramVar : Option String := none
  projection : Option String := none
  deriving Repr

structure CapturedMember where
  base : Compiler.LoadedProjectionBase
  identity : WorkflowEvidenceMember
  projected : Option TraceProjectionResult := none

structure ReviewableCompilation where
  proposal : ReviewableScaffold
  proposalBytes : ByteArray
  proposalSha256 : String
  evidence : ModelEvidence
  members : List CapturedMember
  planBytes : Option ByteArray := none
  diagnostics : List Diagnostic

structure SealCompilation where
  proposal : ReviewableScaffold
  review : ScaffoldReview
  receipt : ScaffoldReviewReceipt
  files : List (String × ByteArray)
  compilation : Compilation
  captured : ReviewableCompilation

private abbrev WorkflowM := ExceptT CompilerError IO
private def checked (result : Except CompilerError α) : WorkflowM α := ExceptT.mk (pure result)
private def stringChecked (result : Except String α) : WorkflowM α :=
  checked (result.mapError fun message => { kind := .finding, message })
private def failure (message : String) : WorkflowM α :=
  throw { kind := .finding, message }
private def read (path : String) : WorkflowM ByteArray :=
  ExceptT.mk (Compiler.readBytesWithLimit path maxCorpusArtifactBytesV1)

private def sortSources (sources : List SourceDigest) : List SourceDigest :=
  sources.mergeSort fun a b => a.logicalPath ≤ b.logicalPath

private partial def jsonNodes (json : Lean.Json) (budget : Nat) : Except String Nat := do
  if budget == 0 then throw "workflow JSON node bound exceeded"
  let children := match json with
    | .arr values => values.toList
    | .obj values => values.toList.map Prod.snd
    | _ => []
  let mut count := 1
  for child in children do count := count + (← jsonNodes child (budget - count))
  return count

/-- Capture a source graph once, admit every raw member, then apply one captured
projection plan. Raw and projected structural conflicts both fail closed. -/
def compileScaffold (paths : WorkflowPaths) : IO (Except CompilerError ReviewableCompilation) :=
  ExceptT.run do
    if paths.evidence.isEmpty || paths.evidence.length > maxWorkflowMembersV1 then
      failure s!"workflow requires 1..{maxWorkflowMembersV1} evidence inputs"
    let source ← ExceptT.mk (Compiler.analyzeSource paths.spec)
    let mut bytesUsed := 0
    let mut nodesUsed := 0
    let mut workUsed := 0
    let mut stateCounts : List (String × Nat) := []
    let mut bases : List Compiler.LoadedProjectionBase := []
    let mut rawMembers : List EvidenceCorpusMember := []
    for path in paths.evidence do
      let bytes ← read path
      bytesUsed := bytesUsed + bytes.size
      if bytesUsed > maxCorpusAggregateBytesV1 then failure "workflow aggregate input limit exceeded"
      let json ← stringChecked ((Codec.StrictJson.parseBytes bytes
        Codec.ModelInterfaceScaffoldWorkflowJson.artifactLimits).mapError toString)
      nodesUsed := nodesUsed + (← stringChecked (jsonNodes json (maxCorpusJsonNodesV1 - nodesUsed)))
      let states ← stringChecked (do return (← (← json.getObjVal? "states").getArr?).size)
      stateCounts := stateCounts ++ [(Sha256.digestHex bytes, states)]
      let base ← checked (Compiler.loadProjectionBaseFromCapture source paths.spec path bytes)
      bases := bases ++ [base]
      rawMembers := rawMembers ++ [{
        rawFileSha256 := Sha256.digestHex bytes
        evidence := base.rawEvidence
        initializerLabels := base.rawInitializerLabels
        transitionLabels := base.rawTransitionLabels }]
    let _ ← stringChecked (mergeEvidenceCorpus rawMembers)
    let some rootBase := bases.head? | failure "empty workflow evidence"
    if rootBase.sources.length > maxCorpusSourcesV1 then failure "source closure exceeds workflow bound"
    let (plan, planBytes) ← match paths.projection with
      | none => pure (none, none)
      | some path => do
          let bytes ← read path
          let parsed ← stringChecked (Codec.ModelInterfaceTraceProjectionJson.parsePlanBytes bytes
            Codec.ModelInterfaceScaffoldWorkflowJson.artifactLimits)
          pure (some parsed, some bytes)
    bytesUsed := bytesUsed + (planBytes.map (·.size)).getD 0
    let mut members : List CapturedMember := []
    let mut structural : List EvidenceCorpusMember := []
    let mut planDigest : Option String := none
    let mut outputVariables := rootBase.sourceVariables
    for base in bases do
      let rawHash := Sha256.digestHex base.rawBytes
      let (evidence, projection, projected) ← match plan with
        | none => pure (base.rawEvidence, none, none)
        | some plan => do
            let estimate ← stringChecked (projectionWorkEstimate plan ((List.lookup rawHash stateCounts).getD 0))
            workUsed := workUsed + estimate
            if workUsed > maxCorpusProjectionWorkV1 then failure "workflow projection work bound exceeded"
            let result ← stringChecked (Codec.ModelInterfaceTraceProjectionJson.projectTraceBytes
              base.normalizedSourceBytes base.rawBytes plan base.context
              Codec.ModelInterfaceScaffoldWorkflowJson.artifactLimits)
            nodesUsed := nodesUsed + (← stringChecked
              (jsonNodes result.projectedTrace (maxCorpusJsonNodesV1 - nodesUsed)))
            let evidence ← stringChecked (Evidence.fromJson result.projectedTrace "<projected-corpus>")
            let fileBytes := Codec.ModelInterfaceTraceProjectionJson.canonicalProjectedTraceFileBytes result
            bytesUsed := bytesUsed + fileBytes.size +
              (Codec.ModelInterfaceTraceProjectionJson.canonicalReceiptFileBytes result.receipt).size
            planDigest := some result.receipt.planSha256
            outputVariables := result.receipt.outputVariables
            let identity : WorkflowProjectionMember := {
              outputSha256 := result.receipt.outputSha256
              evidenceSha256 := evidence.evidenceSha256
              fileSha256 := Sha256.digestHex fileBytes
              receiptSha256 := Codec.ModelInterfaceCorpusJson.projectionReceiptDigest result.receipt }
            pure (evidence, some identity, some result)
      if bytesUsed > maxCorpusAggregateBytesV1 then failure "workflow aggregate artifact limit exceeded"
      members := members ++ [{
        base
        projected
        identity := {
          rawFileSha256 := rawHash
          evidenceSha256 := base.rawEvidence.evidenceSha256
          projection } }]
      structural := structural ++ [{
        rawFileSha256 := rawHash
        evidence
        initializerLabels := base.rawInitializerLabels
        transitionLabels := base.rawTransitionLabels }]
    let merged ← stringChecked (mergeEvidenceCorpus structural)
    let result := synthesizeScaffold {
      source := rootBase.sourceDigest, sourceVariableNames := outputVariables,
      evidence := merged.evidence, initializerLabels := merged.initializerLabels,
      transitionLabels := merged.transitionLabels, configuredParamVar := paths.paramVar }
    let some scaffold := result.value | throw {
      kind := .finding
      message := "reviewable scaffold synthesis failed"
      diagnostics := result.diagnostics }
    members := members.mergeSort fun a b => a.identity.rawFileSha256 ≤ b.identity.rawFileSha256
    let proposal : ReviewableScaffold := {
      scaffold, sources := sortSources rootBase.sources, members := members.map (·.identity),
      projectionPlanSha256 := planDigest, observedInitializers := merged.initializerLabels,
      observedTransitions := merged.transitionLabels }
    let proposalBytes := Codec.ModelInterfaceScaffoldWorkflowJson.proposalFileBytes proposal
    let _ ← stringChecked (Codec.ModelInterfaceScaffoldWorkflowJson.parseProposalBytes proposalBytes)
    return {
      proposal
      proposalBytes
      proposalSha256 := WJson.proposalDigest proposal
      evidence := merged.evidence
      members
      planBytes
      diagnostics := result.diagnostics }

def writeScaffold (paths : WorkflowPaths) (proposalPath : String) (replace : Bool := false) :
    IO (Except CompilerError ReviewableCompilation) := ExceptT.run do
  let compiled ← ExceptT.mk (compileScaffold paths)
  ExceptT.mk (Compiler.atomicWrite proposalPath compiled.proposalBytes replace)
  return compiled

private def compileSealLoaded (paths : WorkflowPaths) (proposalRaw reviewRaw : ByteArray) :
    IO (Except CompilerError SealCompilation) := ExceptT.run do
  let proposal ← stringChecked (Codec.ModelInterfaceScaffoldWorkflowJson.parseProposalBytes proposalRaw)
  let review ← stringChecked (Codec.ModelInterfaceScaffoldWorkflowJson.parseReviewBytes reviewRaw)
  let captured ← ExceptT.mk (compileScaffold paths)
  if Codec.ModelInterfaceScaffoldWorkflowJson.proposalFileBytes proposal != captured.proposalBytes then
    failure "proposal is stale: source closure, raw evidence, projection, or inferred structure changed"
  let proposalSha256 := WJson.proposalDigest proposal
  let reviewSha256 := WJson.reviewDigest review
  stringChecked (validateScaffoldReview proposal proposalSha256 review)
  let compilation ← checked (Compiler.resolveLoaded {
    spec := paths.spec, contract := "<reviewed-contract>", evidence := "<evidence-corpus>",
    paramVar := paths.paramVar } proposal.sources review.contract captured.evidence)
  let compilation ← checked (Compiler.attachWorkflow compilation {
    proposalSha256, reviewSha256, projectionPlanSha256 := proposal.projectionPlanSha256,
    members := proposal.members })
  for obligation in review.obligations do
    let _ ← checked (Compiler.emitTarget obligation.target compilation.lock)
  let receipt : ScaffoldReviewReceipt := {
    proposalSha256, reviewSha256, contractSha256 := compilation.lock.provenance.contractSha256 }
  let files := [
    ("contract.json", Codec.ModelInterfaceJson.canonicalFileBytes
      (Codec.ModelInterfaceJson.encodeContract compilation.lock.contract)),
    ("proposal.json", captured.proposalBytes),
    ("review.json", Codec.ModelInterfaceScaffoldWorkflowJson.reviewFileBytes review),
    ("review-receipt.json", Codec.ModelInterfaceScaffoldWorkflowJson.receiptFileBytes receipt)]
  return { proposal, review, receipt, files, compilation, captured }

def compileSeal (paths : WorkflowPaths) (proposalPath reviewPath : String) :
    IO (Except CompilerError SealCompilation) := ExceptT.run do
  let proposal ← read proposalPath
  let review ← read reviewPath
  ExceptT.mk (compileSealLoaded paths proposal review)

def sealScaffold (paths : WorkflowPaths) (proposalPath reviewPath outDir : String) :
    IO (Except CompilerError SealCompilation) := ExceptT.run do
  let compiled ← ExceptT.mk (compileSeal paths proposalPath reviewPath)
  ExceptT.mk (Publication.publishDirectory outDir compiled.files)
  return compiled

private def regularFile (path : System.FilePath) : WorkflowM ByteArray := do
  let some name := path.fileName | failure "artifact path has no filename"
  let parent := path.parent.getD "."
  let parent ← if parent.toString == "." then do
    let cwd ← liftM IO.currentDir
    pure cwd.toString
    else pure parent.toString
  ExceptT.mk (Publication.readFile parent name maxCorpusArtifactBytesV1)

private def authenticateCorpus (sealed : SealCompilation) (manifestPath : String) :
    WorkflowM String := do
  let manifestRaw ← regularFile manifestPath
  if (manifestPath : System.FilePath).fileName != some "manifest.json" then
    failure "corpus manifest must be the publication's manifest.json"
  let directory := (manifestPath : System.FilePath).parent.getD "."
  let manifest ← ExceptT.mk (Corpus.checkCorpus directory.toString (Sha256.digestHex manifestRaw))
  if manifestRaw != Codec.ModelInterfaceCorpusJson.canonicalManifestFileBytes manifest then
    failure "corpus manifest bytes are not canonical"
  if manifest.rootModule != sealed.proposal.scaffold.source.moduleName ||
      sortSources manifest.sources != sortSources sealed.proposal.sources ||
      some manifest.plan.planSha256 != sealed.proposal.projectionPlanSha256 then
    failure "corpus source or projection identity differs from sealed review"
  if manifest.members.map (·.rawFileSha256) != sealed.proposal.members.map (·.rawFileSha256) then
    failure "corpus membership differs from sealed evidence"
  let planRaw ← regularFile (directory / "projection.json")
  let plan ← stringChecked (Codec.ModelInterfaceTraceProjectionJson.parsePlanBytes planRaw
    Codec.ModelInterfaceScaffoldWorkflowJson.artifactLimits)
  if Sha256.digestHex planRaw != manifest.plan.sha256 || planRaw.size != manifest.plan.bytes then
    failure "corpus projection plan file hash or size differs"
  let mut bytesUsed := manifestRaw.size + planRaw.size
  for (member, captured) in manifest.members.zip sealed.captured.members do
    let some projected := captured.projected | failure "corpus binding requires projected evidence"
    let recomputed ← stringChecked (Codec.ModelInterfaceTraceProjectionJson.projectTraceBytes
      captured.base.normalizedSourceBytes captured.base.rawBytes plan captured.base.context
      Codec.ModelInterfaceScaffoldWorkflowJson.artifactLimits)
    if recomputed.receipt != projected.receipt || manifest.sourceSha256 != projected.receipt.sourceSha256 ||
        member.rawSha256 != projected.receipt.rawSha256 || member.rawBytes != captured.base.rawBytes.size ||
        member.outputSha256 != projected.receipt.outputSha256 then
      failure "corpus projection chain differs from captured originals"
    let traceRaw ← regularFile (directory / corpusTracePath member.rawFileSha256)
    let receiptRaw ← regularFile (directory / corpusReceiptPath member.rawFileSha256)
    bytesUsed := bytesUsed + traceRaw.size + receiptRaw.size
    if bytesUsed > maxCorpusAggregateBytesV1 then failure "corpus aggregate byte limit exceeded"
    if traceRaw != Codec.ModelInterfaceTraceProjectionJson.canonicalProjectedTraceFileBytes projected ||
        receiptRaw != Codec.ModelInterfaceTraceProjectionJson.canonicalReceiptFileBytes projected.receipt ||
        Sha256.digestHex traceRaw != member.trace.sha256 || traceRaw.size != member.trace.bytes ||
        Sha256.digestHex receiptRaw != member.receipt.sha256 || receiptRaw.size != member.receipt.bytes then
      failure "corpus member bytes differ from reviewed projection or manifest"
  return Sha256.digestHex manifestRaw

/-- Authenticate the immutable sealed and recompute all source/raw/projection
inputs before resolving. Supplying a corpus additionally authenticates all of
its published bytes before the exact manifest file hash enters provenance. -/
def compileResolveSealed (paths : WorkflowPaths) (sealedDir : String)
    (corpusManifestPath : Option String := none) : IO (Except CompilerError Compilation) :=
  ExceptT.run do
    let root ← ExceptT.mk (Publication.validateDirectory sealedDir)
    let directory : System.FilePath := root
    let entries ← liftM directory.readDir
    if sortStrings (entries.toList.map (·.fileName)) !=
        ["contract.json", "proposal.json", "review-receipt.json", "review.json"] then
      failure "sealed directory must contain exactly its four canonical artifacts"
    let proposalRaw ← regularFile (directory / "proposal.json")
    let reviewRaw ← regularFile (directory / "review.json")
    let sealed ← ExceptT.mk (compileSealLoaded paths proposalRaw reviewRaw)
    for (name, expected) in sealed.files do
      let actual ← regularFile (directory / name)
      if actual != expected then failure s!"sealed artifact is stale or tampered: {name}"
    let corpusDigest ← match corpusManifestPath with
      | none => pure none
      | some path => pure (some (← authenticateCorpus sealed path))
    checked (Compiler.attachWorkflow sealed.compilation {
      proposalSha256 := sealed.receipt.proposalSha256, reviewSha256 := sealed.receipt.reviewSha256,
      projectionPlanSha256 := sealed.proposal.projectionPlanSha256,
      members := sealed.proposal.members, corpusManifestSha256 := corpusDigest })

end Shell.ModelInterface.ScaffoldWorkflow
