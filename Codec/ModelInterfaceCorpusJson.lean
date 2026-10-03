import Core.ModelInterface.Corpus
import Core.ModelInterface.Sha256
import Codec.ModelInterfaceTraceProjectionJson

namespace Codec.ModelInterfaceCorpusJson

open Lean Core.ModelInterface

def projectionReceiptDigestDomainV1 : String := "mirrors-trace-projection-receipt/v1"
def projectionReceiptDigest (receipt : TraceProjectionReceipt) : String :=
  Sha256.digestDomainHex projectionReceiptDigestDomainV1
    (ModelInterfaceTraceProjectionJson.canonicalReceiptBytes receipt)

private def encodeFile (file : CorpusFile) : Json := Json.mkObj [
  ("path", .str file.path), ("sha256", .str file.sha256), ("bytes", toJson file.bytes)]

def encodeManifest (manifest : CorpusManifest) : Json := Json.mkObj [
  ("schema", .str manifest.schema), ("rootModule", .str manifest.rootModule),
  ("sources", .arr (manifest.sources.map (fun source => Json.mkObj [
    ("moduleName", .str source.moduleName), ("logicalPath", .str source.logicalPath),
    ("contentSha256", .str source.contentSha256)])).toArray),
  ("sourceSha256", .str manifest.sourceSha256),
  ("plan", Json.mkObj [("path", .str manifest.plan.path),
    ("sha256", .str manifest.plan.sha256), ("bytes", toJson manifest.plan.bytes),
    ("planSha256", .str manifest.plan.planSha256)]),
  ("members", .arr (manifest.members.map (fun member => Json.mkObj [
    ("rawSha256", .str member.rawSha256), ("rawFileSha256", .str member.rawFileSha256),
    ("rawBytes", toJson member.rawBytes), ("outputSha256", .str member.outputSha256),
    ("trace", encodeFile member.trace), ("receipt", encodeFile member.receipt)])).toArray),
  ("corpusDigest", .str manifest.corpusDigest)]

def canonicalManifestFileBytes (manifest : CorpusManifest) : ByteArray :=
  ModelInterfaceJson.canonicalFileBytes (encodeManifest manifest)

/-- Content address of the complete manifest file, including its final LF. -/
def manifestDigest (manifest : CorpusManifest) : String :=
  Sha256.digestHex (canonicalManifestFileBytes manifest)

/-- Mirrors MirrorECMA's ordered replay corpus identity exactly. -/
def orderedCorpusDigest (members : List CorpusMember) : String :=
  Sha256.digestHex (ModelInterfaceJson.canonicalBytes (Json.mkObj [
    ("schema", .str "mirrorecma.corpus/v1"),
    ("traces", .arr (members.map (fun member => Json.str member.trace.sha256)).toArray)]))

private abbrev Fields := List (String × Json)
private def fields (context : String) (names : List String) (json : Json) :
    Except String Fields := do
  let .obj value := json | throw s!"{context}: object expected"
  let value := value.toList
  if value.length != names.length || value.any (fun item => !names.contains item.1) then
    throw s!"{context}: fields must be exactly {names}"
  return value
private def get (items : Fields) (name : String) : Except String Json :=
  match List.lookup name items with
  | some value => .ok value
  | none => .error s!"missing {name}"
private def str (items : Fields) (name : String) : Except String String := do
  (← get items name).getStr?
private def nat (items : Fields) (name : String) : Except String Nat := do
  (← get items name).getNat?
private def list (json : Json) : Except String (List Json) := do
  return (← json.getArr?).toList
private def digestValid (value : String) : Bool :=
  value.length == 64 && value.toList.all fun c =>
    ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')
private def boundedFile (file : CorpusFile) : Bool :=
  digestValid file.sha256 && 0 < file.bytes && file.bytes ≤ maxCorpusArtifactBytesV1

private def decodeFile (json : Json) : Except String CorpusFile := do
  let items ← fields "corpus file" ["path", "sha256", "bytes"] json
  return { path := ← str items "path", sha256 := ← str items "sha256", bytes := ← nat items "bytes" }

def decodeManifest (json : Json) : Except String CorpusManifest := do
  let items ← fields "corpus" ["schema", "rootModule", "sources", "sourceSha256",
    "plan", "members", "corpusDigest"] json
  let sources ← (← list (← get items "sources")).mapM fun source => do
    let fs ← fields "source" ["moduleName", "logicalPath", "contentSha256"] source
    return ({
      moduleName := ← str fs "moduleName"
      logicalPath := ← str fs "logicalPath"
      contentSha256 := ← str fs "contentSha256" } : SourceDigest)
  let planFields ← fields "plan" ["path", "sha256", "bytes", "planSha256"] (← get items "plan")
  let plan : CorpusPlan := {
    path := ← str planFields "path", sha256 := ← str planFields "sha256",
    bytes := ← nat planFields "bytes", planSha256 := ← str planFields "planSha256" }
  let members ← (← list (← get items "members")).mapM fun member => do
    let fs ← fields "member" ["rawSha256", "rawFileSha256", "rawBytes", "outputSha256",
      "trace", "receipt"] member
    return ({
      rawSha256 := ← str fs "rawSha256"
      rawFileSha256 := ← str fs "rawFileSha256"
      rawBytes := ← nat fs "rawBytes"
      outputSha256 := ← str fs "outputSha256"
      trace := ← decodeFile (← get fs "trace")
      receipt := ← decodeFile (← get fs "receipt") } : CorpusMember)
  let manifest : CorpusManifest := {
    schema := ← str items "schema", rootModule := ← str items "rootModule", sources,
    sourceSha256 := ← str items "sourceSha256", plan, members,
    corpusDigest := ← str items "corpusDigest" }
  if manifest.schema != corpusSchemaV1 then throw "unsupported corpus schema"
  if members.isEmpty || members.length > maxCorpusMembersV1 then throw "corpus member count out of bounds"
  if sources.isEmpty || sources.length > maxCorpusSourcesV1 then throw "corpus source count out of bounds"
  if !sources.all (fun s => !s.moduleName.isEmpty && validLogicalPath s.logicalPath && digestValid s.contentSha256) ||
      !(duplicateStrings (sources.map (·.moduleName))).isEmpty ||
      !(duplicateStrings (sources.map (·.logicalPath))).isEmpty ||
      sources.map (·.logicalPath) != sortStrings (sources.map (·.logicalPath)) ||
      !sources.any (fun s => s.moduleName == manifest.rootModule) then
    throw "invalid or noncanonical corpus source closure"
  if !digestValid manifest.sourceSha256 || !digestValid plan.planSha256 ||
      !boundedFile plan.toCorpusFile || plan.path != "projection.json" then
    throw "invalid corpus plan identity"
  let hashes := members.map (·.rawFileSha256)
  if hashes != sortStrings hashes || !(duplicateStrings hashes).isEmpty ||
      !(duplicateStrings (members.map (·.rawSha256))).isEmpty then
    throw "duplicate or noncanonical corpus members"
  for member in members do
    if ![member.rawSha256, member.rawFileSha256, member.outputSha256].all digestValid ||
        member.rawBytes == 0 || member.rawBytes > maxCorpusArtifactBytesV1 ||
        !boundedFile member.trace || !boundedFile member.receipt ||
        member.trace.path != corpusTracePath member.rawFileSha256 ||
        member.receipt.path != corpusReceiptPath member.rawFileSha256 then
      throw "invalid corpus member identity"
  let aggregate := plan.bytes + members.foldl (fun n m => n + m.rawBytes + m.trace.bytes + m.receipt.bytes) 0
  if aggregate > maxCorpusAggregateBytesV1 then throw "corpus aggregate byte bound exceeded"
  if manifest.corpusDigest != orderedCorpusDigest members then throw "ordered corpus digest mismatch"
  return manifest

def parseManifestBytes (raw : ByteArray) : Except String CorpusManifest := do
  let json ← (StrictJson.parseBytes raw { maxBytes := maxCorpusArtifactBytesV1, maxDepth := 128 }).mapError toString
  let manifest ← decodeManifest json
  if canonicalManifestFileBytes manifest != raw then throw "corpus manifest is not canonical"
  if raw.size + manifest.plan.bytes + manifest.members.foldl
      (fun n m => n + m.rawBytes + m.trace.bytes + m.receipt.bytes) 0 > maxCorpusAggregateBytesV1 then
    throw "corpus aggregate byte bound exceeded"
  return manifest

end Codec.ModelInterfaceCorpusJson
