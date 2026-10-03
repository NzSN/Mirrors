import Core.ModelInterface.EvidenceMerge
import Codec.ModelInterfaceCorpusJson
import Shell.ModelInterface.Publication

namespace Shell.ModelInterface.Corpus

open Core.ModelInterface Compiler

structure ProjectCorpusPaths where
  spec : String
  evidence : List String
  projection : String
  out : String
  deriving Repr

structure CompiledCorpusMember where
  base : LoadedProjectionBase
  result : TraceProjectionResult
  workflowEvidence : WorkflowEvidenceMember

structure CorpusCompilation where
  manifest : CorpusManifest
  manifestBytes : ByteArray
  manifestSha256 : String
  files : List (String × ByteArray)
  members : List CompiledCorpusMember

private def finding (message : String) : Except CompilerError α :=
  .error { kind := .finding, message }
private def infrastructure (message : String) : Except CompilerError α :=
  .error { kind := .infrastructure, message }
private def lift (result : Except String α) : Except CompilerError α :=
  result.mapError fun message => { kind := .finding, message }
private def limits : Codec.StrictJson.Limits :=
  { maxBytes := maxCorpusArtifactBytesV1, maxDepth := 128 }

private def readInput (path : String) : IO (Except CompilerError ByteArray) := do
  try
    let handle ← IO.FS.Handle.mk path .read
    let mut bytes := ByteArray.empty
    repeat
      let chunk ← handle.read (min 65536 (maxCorpusArtifactBytesV1 + 1 - bytes.size)).toUSize
      if chunk.isEmpty then break
      bytes := bytes.append chunk
      if bytes.size > maxCorpusArtifactBytesV1 then
        return finding s!"corpus input exceeds per-artifact byte bound: {path}"
    return .ok bytes
  catch error => return infrastructure s!"cannot read corpus input {path}: {error}"

/-- Count bounded JSON traversal work before evidence admission or projection. -/
private partial def jsonNodes (json : Lean.Json) (budget : Nat) : Except String Nat := do
  if budget == 0 then throw "corpus JSON node bound exceeded"
  let children := match json with
    | .arr values => values.toList
    | .obj values => values.toList.map Prod.snd
    | _ => []
  let mut count := 1
  for child in children do
    count := count + (← jsonNodes child (budget - count))
  return count

private def fileIdentity (path : String) (bytes : ByteArray) : CorpusFile :=
  { path, sha256 := Sha256.digestHex bytes, bytes := bytes.size }

/-- Capture one source graph, admit all raw inputs, then prepare the complete
publication in memory. This function never creates any output path. -/
def compileProjectCorpus (paths : ProjectCorpusPaths) : IO (Except CompilerError CorpusCompilation) := do
  if paths.evidence.isEmpty || paths.evidence.length > maxCorpusMembersV1 then
    return finding s!"corpus requires 1..{maxCorpusMembersV1} evidence inputs"
  let capture ← match ← analyzeSource paths.spec with
    | .ok value => pure value
    | .error error => return .error error
  if (frontendSourceDigests capture).length > maxCorpusSourcesV1 then
    return finding "corpus source count bound exceeded"
  let mut bases : List (String × LoadedProjectionBase × Nat) := []
  let mut aggregate := 0
  let mut nodes := 0
  for path in paths.evidence do
    let bytes ← match ← readInput path with
      | .ok value => pure value
      | .error error => return .error error
    aggregate := aggregate + bytes.size
    if aggregate > maxCorpusAggregateBytesV1 then return finding "corpus aggregate byte bound exceeded"
    let json ← match lift ((Codec.StrictJson.parseBytes bytes limits).mapError toString) with
      | .ok value => pure value
      | .error error => return .error error
    let count ← match lift (jsonNodes json (maxCorpusJsonNodesV1 - nodes)) with
      | .ok value => pure value
      | .error error => return .error error
    nodes := nodes + count
    let states ← match lift (do return (← (← json.getObjVal? "states").getArr?).size) with
      | .ok value => pure value
      | .error error => return .error error
    let base ← match loadProjectionBaseFromCapture capture paths.spec path bytes with
      | .ok value => pure value
      | .error error => return .error error
    bases := bases ++ [(Sha256.digestHex bytes, base, states)]
  bases := bases.mergeSort fun a b => a.1 ≤ b.1
  match lift (mergeEvidenceCorpus (bases.map fun (sha, base, _) => {
    rawFileSha256 := sha, evidence := base.rawEvidence,
    initializerLabels := base.rawInitializerLabels, transitionLabels := base.rawTransitionLabels })) with
  | .error error => return .error error
  | .ok _ => pure ()
  let planRaw ← match ← readInput paths.projection with
    | .ok value => pure value
    | .error error => return .error error
  aggregate := aggregate + planRaw.size
  if aggregate > maxCorpusAggregateBytesV1 then return finding "corpus aggregate byte bound exceeded"
  let plan ← match lift (Codec.ModelInterfaceTraceProjectionJson.parsePlanBytes planRaw limits) with
    | .ok value => pure value
    | .error error => return .error error
  let some (_, firstBase, _) := bases.head? | return finding "empty corpus"
  match lift (validateTraceProjectionPlan plan firstBase.context) with
  | .error error => return .error error
  | .ok () => pure ()
  let planNodeCount ← match lift (jsonNodes
      (Codec.ModelInterfaceTraceProjectionJson.encodePlan plan) (maxCorpusJsonNodesV1 - nodes)) with
    | .ok value => pure value
    | .error error => return .error error
  nodes := nodes + planNodeCount
  let planBytes := Codec.ModelInterfaceTraceProjectionJson.canonicalPlanFileBytes plan
  aggregate := aggregate + planBytes.size
  let mut work := 0
  for (_, _, stateCount) in bases do
    let estimate ← match lift (projectionWorkEstimate plan stateCount) with
      | .ok value => pure value
      | .error error => return .error error
    work := work + estimate
    if work > maxCorpusProjectionWorkV1 then return finding "corpus projection work bound exceeded"
  let mut compiled : List CompiledCorpusMember := []
  let mut members : List CorpusMember := []
  let mut files : List (String × ByteArray) := [("projection.json", planBytes)]
  for (rawFileSha256, base, _) in bases do
    let result ← match lift (Codec.ModelInterfaceTraceProjectionJson.projectTraceBytes base.normalizedSourceBytes base.rawBytes plan base.context limits) with
      | .ok value => pure value
      | .error error => return .error error
    let count ← match lift (jsonNodes result.projectedTrace (maxCorpusJsonNodesV1 - nodes)) with
      | .ok value => pure value
      | .error error => return .error error
    nodes := nodes + count
    let projectedEvidence ← match lift (Evidence.fromJson result.projectedTrace base.evidenceName) with
      | .ok value => pure value
      | .error error => return .error error
    let traceBytes := Codec.ModelInterfaceTraceProjectionJson.canonicalProjectedTraceFileBytes result
    let receiptBytes := Codec.ModelInterfaceTraceProjectionJson.canonicalReceiptFileBytes result.receipt
    aggregate := aggregate + traceBytes.size + receiptBytes.size
    if aggregate > maxCorpusAggregateBytesV1 then return finding "corpus aggregate byte bound exceeded"
    let member : CorpusMember := {
      rawSha256 := result.receipt.rawSha256, rawFileSha256, rawBytes := base.rawBytes.size,
      outputSha256 := result.receipt.outputSha256,
      trace := fileIdentity (corpusTracePath rawFileSha256) traceBytes,
      receipt := fileIdentity (corpusReceiptPath rawFileSha256) receiptBytes }
    members := members ++ [member]
    files := files ++ [(member.trace.path, traceBytes), (member.receipt.path, receiptBytes)]
    compiled := compiled ++ [{ base, result, workflowEvidence := {
      rawFileSha256, evidenceSha256 := base.rawEvidence.evidenceSha256,
      projection := some {
        outputSha256 := result.receipt.outputSha256,
        evidenceSha256 := projectedEvidence.evidenceSha256,
        fileSha256 := member.trace.sha256,
        receiptSha256 := Codec.ModelInterfaceCorpusJson.projectionReceiptDigest result.receipt } } }]
  let some first := compiled.head? | return finding "empty corpus"
  let manifest : CorpusManifest := {
    rootModule := first.base.sourceDigest.moduleName,
    sources := first.base.sources.mergeSort (fun a b => a.logicalPath ≤ b.logicalPath),
    sourceSha256 := first.result.receipt.sourceSha256,
    plan := { fileIdentity "projection.json" planBytes with
      planSha256 := first.result.receipt.planSha256 },
    members, corpusDigest := Codec.ModelInterfaceCorpusJson.orderedCorpusDigest members }
  let manifestBytes := Codec.ModelInterfaceCorpusJson.canonicalManifestFileBytes manifest
  aggregate := aggregate + manifestBytes.size
  if aggregate > maxCorpusAggregateBytesV1 then return finding "corpus aggregate byte bound exceeded"
  match lift (Codec.ModelInterfaceCorpusJson.parseManifestBytes manifestBytes) with
  | .error error => return .error error
  | .ok _ => pure ()
  return .ok {
    manifest, manifestBytes, manifestSha256 := Sha256.digestHex manifestBytes
    files := ("manifest.json", manifestBytes) :: files
    members := compiled }

def projectCorpus (paths : ProjectCorpusPaths) : IO (Except CompilerError CorpusCompilation) := do
  let compilation ← match ← compileProjectCorpus paths with
    | .ok value => pure value
    | .error error => return .error error
  match ← Publication.publishDirectory paths.out compilation.files with
  | .error error => return .error error
  | .ok () => return .ok compilation

private def readVerified (directory : String) (file : CorpusFile) : IO (Except CompilerError ByteArray) := do
  let bytes ← match ← Publication.readFile directory file.path maxCorpusArtifactBytesV1 with
    | .ok value => pure value
    | .error error => return .error error
  if bytes.size != file.bytes || Sha256.digestHex bytes != file.sha256 then
    return finding s!"corpus file identity mismatch: {file.path}"
  return .ok bytes

/-- Verify exact membership and every byte/domain link without modifying the
directory. An expected external manifest hash is mandatory. Source/raw files
are authenticated separately when attaching a sealed workflow. -/
def checkCorpus (directory expectedManifestSha256 : String) : IO (Except CompilerError CorpusManifest) := do
  let bytes ← match ← Publication.readFile directory "manifest.json" maxCorpusArtifactBytesV1 with
    | .ok value => pure value
    | .error error => return .error error
  if Sha256.digestHex bytes != expectedManifestSha256 then return finding "corpus manifest SHA-256 mismatch"
  let manifest ← match lift (Codec.ModelInterfaceCorpusJson.parseManifestBytes bytes) with
    | .ok value => pure value
    | .error error => return .error error
  try
    let actual := (← (directory : System.FilePath).readDir).toList.map (·.fileName)
    if sortStrings actual != sortStrings (corpusMemberPaths manifest) then
      return finding "corpus directory membership differs from manifest"
  catch error => return infrastructure s!"cannot enumerate corpus directory: {error}"
  let planBytes ← match ← readVerified directory manifest.plan.toCorpusFile with
    | .ok value => pure value
    | .error error => return .error error
  let plan ← match lift (Codec.ModelInterfaceTraceProjectionJson.parsePlanBytes planBytes limits) with
    | .ok value => pure value
    | .error error => return .error error
  if planBytes != Codec.ModelInterfaceTraceProjectionJson.canonicalPlanFileBytes plan || manifest.plan.planSha256 !=
      Sha256.digestDomainHex Codec.ModelInterfaceTraceProjectionJson.projectionPlanDigestDomainV1 (Codec.ModelInterfaceTraceProjectionJson.canonicalPlanBytes plan) then
    return finding "corpus plan canonical identity mismatch"
  let mut nodes := 0
  let mut work := 0
  for member in manifest.members do
    let traceBytes ← match ← readVerified directory member.trace with
      | .ok value => pure value
      | .error error => return .error error
    let receiptBytes ← match ← readVerified directory member.receipt with
      | .ok value => pure value
      | .error error => return .error error
    let receipt ← match lift (Codec.ModelInterfaceTraceProjectionJson.parseReceiptBytes receiptBytes limits) with
      | .ok value => pure value
      | .error error => return .error error
    if receiptBytes != Codec.ModelInterfaceTraceProjectionJson.canonicalReceiptFileBytes receipt ||
        receipt.rawSha256 != member.rawSha256 || receipt.outputSha256 != member.outputSha256 ||
        receipt.planSha256 != manifest.plan.planSha256 || receipt.sourceSha256 != manifest.sourceSha256 then
      return finding "corpus receipt links mismatch"
    let trace ← match lift ((Codec.StrictJson.parseBytes traceBytes limits).mapError toString) with
      | .ok value => pure value
      | .error error => return .error error
    let result : TraceProjectionResult := { projectedTrace := trace, receipt }
    match lift (Codec.ModelInterfaceTraceProjectionJson.decodeResult (Codec.ModelInterfaceTraceProjectionJson.encodeResult result)) with
    | .error error => return .error error
    | .ok _ => pure ()
    if traceBytes != Codec.ModelInterfaceTraceProjectionJson.canonicalProjectedTraceFileBytes result then return finding "corpus trace is not canonical"
    let count ← match lift (jsonNodes trace (maxCorpusJsonNodesV1 - nodes)) with
      | .ok value => pure value
      | .error error => return .error error
    nodes := nodes + count
    let stateCount ← match lift (do return (← (← trace.getObjVal? "states").getArr?).size) with
      | .ok value => pure value
      | .error error => return .error error
    let estimate ← match lift (projectionWorkEstimate plan stateCount) with
      | .ok value => pure value
      | .error error => return .error error
    work := work + estimate
    if work > maxCorpusProjectionWorkV1 then return finding "corpus projection work bound exceeded"
  return .ok manifest

end Shell.ModelInterface.Corpus
