import Core.ModelInterface.Types

/-! Read-only migration classification of already verified lock identities.
The shell must authenticate both locks before using this result. -/
namespace Core.ModelInterface

inductive MigrationKind where
  | unchanged
  | provenanceOnly
  | semanticChange
  deriving Repr, BEq

def MigrationKind.name : MigrationKind → String
  | .unchanged => "unchanged"
  | .provenanceOnly => "provenance_only"
  | .semanticChange => "semantic_change"

structure LockMigration where
  kind : MigrationKind
  fromSemanticDigest : SemanticDigest
  toSemanticDigest : SemanticDigest
  fromProvenanceDigest : ProvenanceDigest
  toProvenanceDigest : ProvenanceDigest
  deriving Repr

def compareVerifiedLocks (old new : LockedModelInterface) : LockMigration where
  kind := if old.semanticDigest != new.semanticDigest then .semanticChange
    else if old.provenanceDigest != new.provenanceDigest then .provenanceOnly
    else .unchanged
  fromSemanticDigest := old.semanticDigest
  toSemanticDigest := new.semanticDigest
  fromProvenanceDigest := old.provenanceDigest
  toProvenanceDigest := new.provenanceDigest

end Core.ModelInterface
