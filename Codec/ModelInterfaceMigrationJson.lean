import Core.ModelInterface.Migration
import Codec.ModelInterfaceJson

namespace Codec.ModelInterfaceMigrationJson
open Lean Core.ModelInterface

/-- Explanatory section differences use the same canonical identity projection
as hashing, so input list ordering and evidence origins do not create deltas. -/
def changedSemanticSections (old new : SemanticDescriptor) : List String :=
  let before := ModelInterfaceJson.encodeSemanticIdentityDescriptor old
  let after := ModelInterfaceJson.encodeSemanticIdentityDescriptor new
  ["schema", "interfaceVersion", "model", "resolverSemanticsVersion",
    "comparisonPolicyVersion", "runProfile", "initializers", "actions", "observations"].filter
    fun key => (before.getObjVal? key).toOption.map Json.compress !=
      (after.getObjVal? key).toOption.map Json.compress

def encodeComparison (old new : LockedModelInterface) : Json :=
  let result := compareVerifiedLocks old new
  let changed := result.kind == .semanticChange
  Json.mkObj [
    ("schema", .str "mirrors.model-interface-migration/v1"),
    ("kind", .str result.kind.name),
    ("fromSemanticDigest", .str result.fromSemanticDigest),
    ("toSemanticDigest", .str result.toSemanticDigest),
    ("fromProvenanceDigest", .str result.fromProvenanceDigest),
    ("toProvenanceDigest", .str result.toProvenanceDigest),
    ("changedSemanticSections", .arr ((changedSemanticSections old.semanticDescriptor
      new.semanticDescriptor).map Json.str).toArray),
    ("semanticIdentityMatches", .bool (!changed)),
    ("requiresRegeneration", .bool changed),
    ("requiresArtifactRefresh", .bool (result.kind != .unchanged)),
    ("runtimeCompatibilityVerified", .bool false)]

end Codec.ModelInterfaceMigrationJson
