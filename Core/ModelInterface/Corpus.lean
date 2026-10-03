import Core.ModelInterface.Types

/-! Bounded immutable projected-corpus identities. File SHA values always cover
the exact published bytes, including LF. Projection identities retain their
separate domain-separated canonical-JSON meaning. -/

namespace Core.ModelInterface

def corpusSchemaV1 : String := "mirrors.model-interface-corpus/v1"
def maxCorpusMembersV1 : Nat := maxWorkflowMembersV1
def maxCorpusArtifactBytesV1 : Nat := 16 * 1024 * 1024
/-- Sum of captured raw/plan bytes and all published file bytes. -/
def maxCorpusAggregateBytesV1 : Nat := 64 * 1024 * 1024
def maxCorpusJsonNodesV1 : Nat := 1000000
def maxCorpusProjectionWorkV1 : Nat := 1000000
def maxCorpusSourcesV1 : Nat := 256

structure CorpusFile where
  path : String
  sha256 : String
  bytes : Nat
  deriving Repr, DecidableEq

structure CorpusPlan extends CorpusFile where
  planSha256 : String
  deriving Repr, DecidableEq

structure CorpusMember where
  rawSha256 : String
  rawFileSha256 : String
  rawBytes : Nat
  outputSha256 : String
  trace : CorpusFile
  receipt : CorpusFile
  deriving Repr, DecidableEq

structure CorpusManifest where
  schema : String := corpusSchemaV1
  rootModule : String
  sources : List SourceDigest
  sourceSha256 : String
  plan : CorpusPlan
  members : List CorpusMember
  corpusDigest : String
  deriving Repr

def corpusTracePath (rawFileSha256 : String) : String := rawFileSha256 ++ ".itf.json"
def corpusReceiptPath (rawFileSha256 : String) : String := rawFileSha256 ++ ".receipt.json"

def corpusMemberPaths (manifest : CorpusManifest) : List String :=
  ["manifest.json", "projection.json"] ++
    manifest.members.flatMap (fun member => [member.trace.path, member.receipt.path])

end Core.ModelInterface
