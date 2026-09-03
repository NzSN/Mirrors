import Core.Value
import Batteries

/-!
# Pure model-interface compiler domain

Language-neutral inputs and resolved artifacts for the model-interface
compiler.  This module deliberately contains no JSON, filesystem, hashing,
process, target-language, or transport behavior.  The effectful shell parses
and hashes; the pure resolver consumes normalized values defined here.
-/

namespace Core.ModelInterface

abbrev StableId := String
abbrev SemanticDigest := String
abbrev ProvenanceDigest := String

def contractSchemaV1 : String := "mirrors.model-interface/v1"
def lockSchemaV1 : String := "mirrors.model-interface-lock/v1"
def descriptorSchemaV1 : String := "mirrors.model-interface-descriptor/v1"
def descriptorDigestDomainV1 : String := "mirrors-model-interface-descriptor/v1"
def negotiationSchemaV1 : String := "mirrors.model-interface-negotiation/v1"
def actionVariableV1 : String := "action_taken"
def resolverSemanticsV1 : String := "mirrors-model-interface-resolver/v1"
def comparisonPolicyV1 : String := "mirrors-applyParamVars-filterMeta/v1"

/-! Version-1 resource bounds.  These are semantic compiler limits, distinct
from the outer JSONL byte bound enforced by transports and strict codecs. -/
def maxAcceptedDescriptorSchemasV1 : Nat := 8
def maxInitializersV1 : Nat := 32
def maxTransitionActionsV1 : Nat := 256
def maxAliasesPerActionV1 : Nat := 16
def maxInputsPerActionV1 : Nat := 128
def maxObservationsV1 : Nat := 1024
def maxPathSegmentsV1 : Nat := 32
def maxStructuralTypeDepthV1 : Nat := 32
def maxNormalizedTypeNodesV1 : Nat := 8192
def maxStableNameBytesV1 : Nat := 256

/-! ## Structural model types -/

/-- Shape functor used to keep the public recursive type structurally simple. -/
structure ModelFieldF (α : Type) where
  wireName : String
  type : α
  deriving Repr, BEq

/-- Shape functor for a tagged-variant case. -/
structure VariantCaseF (α : Type) where
  tag : String
  payload : α
  deriving Repr, BEq

/-- Closed structural types that can cross the model-interface seam. -/
inductive ModelType where
  | int
  | bool
  | str
  | null
  | set (element : ModelType)
  | seq (element : ModelType)
  | tuple (elements : List ModelType)
  | record (fields : List (ModelFieldF ModelType))
  | map (key value : ModelType)
  | variant (cases : List (VariantCaseF ModelType))
  | opaqueItf (description : String)
  deriving Repr, BEq

abbrev ModelField := ModelFieldF ModelType
abbrev VariantCase := VariantCaseF ModelType

/-! A typed, canonical subset of ITF literals used for map-key projections.
It is data, never an expression to evaluate. -/
inductive CanonicalItfLiteral where
  | int (value : Int)
  | bool (value : Bool)
  | str (value : String)
  | null
  | set (values : List CanonicalItfLiteral)
  | seq (values : List CanonicalItfLiteral)
  | tuple (values : List CanonicalItfLiteral)
  | record (fields : List (String × CanonicalItfLiteral))
  | map (entries : List (CanonicalItfLiteral × CanonicalItfLiteral))
  | variant (tag : String) (payload : CanonicalItfLiteral)
  deriving Repr

deriving instance BEq for CanonicalItfLiteral

inductive PathRoot where
  | initialState
  | stepParameters
  deriving Repr

deriving instance BEq for PathRoot

inductive PathSegment where
  | field (name : String)
  /-- Zero-based index in the ITF/host representation. -/
  | index (index : Nat)
  | mapKey (key : CanonicalItfLiteral)
  | variantValue (tag : String)
  deriving Repr

structure ModelPath where
  root : String
  path : List PathSegment := []
  deriving Repr

def ModelPath.top (name : String) : ModelPath := { root := name }

/-! ## Source locations and diagnostics -/

inductive Severity where
  | error
  | warning
  | obligation
  deriving Repr, DecidableEq

structure DiagnosticSubject where
  kind : String
  stableId : Option String := none
  deriving Repr, DecidableEq

structure SourceLocation where
  source : String
  pointer : Option String := none
  line : Option Nat := none
  column : Option Nat := none
  deriving Repr, DecidableEq

def SourceLocation.unknown : SourceLocation := { source := "<normalized-input>" }

def SourceLocation.atPointer (loc : SourceLocation) (pointer : String) : SourceLocation :=
  { loc with pointer := some pointer }

structure Diagnostic where
  code : String
  severity : Severity
  stage : String
  subject : DiagnosticSubject
  primary : SourceLocation
  related : List SourceLocation := []
  arguments : List (String × String) := []
  deriving Repr, DecidableEq

structure Located (α : Type) where
  value : α
  location : SourceLocation := SourceLocation.unknown
  deriving Repr

def Located.unlocated (value : α) : Located α := { value }

structure CompileResult (α : Type) where
  value : Option α
  diagnostics : List Diagnostic := []
  deriving Repr

def Diagnostic.isError (d : Diagnostic) : Bool := d.severity == .error

def CompileResult.hasErrors (r : CompileResult α) : Bool :=
  r.diagnostics.any Diagnostic.isError

/-! ## Companion contract and normalized evidence -/

structure ModelIdentity where
  moduleName : String
  source : String
  deriving Repr, DecidableEq

structure WireContract where
  actionVariable : String := actionVariableV1
  parameterVariable : Option String := none
  deriving Repr, DecidableEq

structure ContractInput where
  id : StableId
  fromRoot : PathRoot
  path : List PathSegment
  expectedType : Option ModelType := none
  deriving Repr

structure ContractAction where
  id : StableId
  wireAction : String
  wireAliases : List String := []
  inputs : List ContractInput := []
  deriving Repr

inductive ObservationProvenance where
  | implementation
  /-- Reserved invalid-in-v1 cases let the pure resolver fail explicitly. -/
  | oracle
  | derived
  deriving Repr, DecidableEq

deriving instance BEq for ObservationProvenance

structure ContractObservation where
  id : StableId
  wireName : String
  provenance : ObservationProvenance := .implementation
  expectedType : Option ModelType := none
  deriving Repr

structure ContractV1 where
  schema : String := contractSchemaV1
  interfaceVersion : String
  model : ModelIdentity
  wire : WireContract
  initializers : List ContractAction
  actions : List ContractAction := []
  observations : List ContractObservation
  deriving Repr

structure RunProfile where
  configuredParamVar : Option String := none
  deriving Repr, DecidableEq

structure SourceDigest where
  moduleName : String
  logicalPath : String
  contentSha256 : String
  deriving Repr, DecidableEq

inductive EvidenceOrigin where
  | apalacheTypecheck
  | itfVarTypes
  | contractAssertion
  deriving Repr, DecidableEq

deriving instance BEq for EvidenceOrigin

structure TypeFact where
  modelPath : ModelPath
  type : ModelType
  origin : EvidenceOrigin
  location : SourceLocation := SourceLocation.unknown
  deriving Repr

structure ModelEvidence where
  traceVars : List String
  itfParamVars : List String := []
  typeFacts : List TypeFact
  evidenceSha256 : String
  deriving Repr

structure ResolveInput where
  contract : Located ContractV1
  evidence : ModelEvidence
  runProfile : RunProfile
  sources : List SourceDigest := []
  compilerVersion : String := "development"
  contractSha256 : String := ""
  deriving Repr

/-! ## Resolved semantic interface -/

structure InputProjection where
  root : PathRoot
  path : List PathSegment
  type : ModelType
  deriving Repr

inductive ActionPhase where
  | initialize
  | transition
  deriving Repr, DecidableEq

structure ResolvedInput where
  id : StableId
  projection : InputProjection
  typeOrigins : List EvidenceOrigin := []
  deriving Repr

structure ResolvedAction where
  id : StableId
  phase : ActionPhase
  wireAction : String
  wireAliases : List String := []
  inputs : List ResolvedInput := []
  deriving Repr

structure ResolvedObservation where
  id : StableId
  wireName : String
  type : ModelType
  provenance : ObservationProvenance := .implementation
  typeOrigins : List EvidenceOrigin := []
  deriving Repr

structure ResolvedRunProfile where
  actionVariable : String := actionVariableV1
  configuredParamVar : Option String
  itfParamVars : List String
  effectiveParamVars : List String
  deriving Repr, DecidableEq

/-- The only runtime-distributable compiler artifact. It intentionally has no
source manifest, evidence locations, diagnostics, executable code, or URLs. -/
structure SemanticDescriptor where
  schema : String := descriptorSchemaV1
  interfaceVersion : String
  modelModule : String
  resolverSemanticsVersion : String := resolverSemanticsV1
  comparisonPolicyVersion : String := comparisonPolicyV1
  runProfile : ResolvedRunProfile
  initializers : List ResolvedAction
  actions : List ResolvedAction
  observations : List ResolvedObservation
  deriving Repr

structure LockProvenance where
  compilerVersion : String
  contractSha256 : String
  evidenceSha256 : String
  sources : List SourceDigest
  deriving Repr, DecidableEq

/-- A fully resolved interface before the shell computes canonical digests. -/
structure ResolvedModelInterface extends SemanticDescriptor where
  /-- Canonical companion contract used to resolve this interface. It is lock
  metadata, not part of the runtime semantic descriptor or semantic digest. -/
  contract : ContractV1
  provenance : LockProvenance
  deriving Repr

/-- A checked-in lock after the shell has hashed the canonical semantic and
provenance projections. -/
structure LockedModelInterface extends SemanticDescriptor where
  /-- Canonical companion contract authenticated by
  `provenance.contractSha256`. -/
  contract : ContractV1
  semanticDigest : SemanticDigest
  provenanceDigest : ProvenanceDigest
  provenance : LockProvenance
  deriving Repr

def ResolvedModelInterface.semanticDescriptor (r : ResolvedModelInterface) :
    SemanticDescriptor := r.toSemanticDescriptor

def ResolvedModelInterface.withDigests (r : ResolvedModelInterface)
    (semanticDigest : SemanticDigest) (provenanceDigest : ProvenanceDigest) :
    LockedModelInterface where
  toSemanticDescriptor := r.toSemanticDescriptor
  contract := r.contract
  semanticDigest := semanticDigest
  provenanceDigest := provenanceDigest
  provenance := r.provenance

def LockedModelInterface.semanticDescriptor (lock : LockedModelInterface) :
    SemanticDescriptor := lock.toSemanticDescriptor

@[simp] theorem ResolvedModelInterface.semanticDescriptor_withDigests
    (r : ResolvedModelInterface) (semantic provenance : String) :
    (r.withDigests semantic provenance).semanticDescriptor = r.semanticDescriptor := rfl

end Core.ModelInterface
