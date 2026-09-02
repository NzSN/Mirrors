import Core.ModelInterface.Types

/-!
# Pure runtime descriptor negotiation

Payload-independent selection of negotiation status and the `interfaceOk` bit
consumed by the session protocol. Authentication, authorization, byte limits,
canonical hashing, cache state, and wire codecs remain outside this module and
are supplied as already-decided facts.
-/

namespace Core.ModelInterface

inductive RequestMode where
  | verify
  | descriptor
  deriving Repr, DecidableEq

inductive NegotiationPolicy where
  | require
  | prefer
  deriving Repr, DecidableEq

inductive NegotiationStatus where
  | matched
  | resolved
  | notModified
  | mismatch
  | unsupported
  | unavailable
  | tooLarge
  deriving Repr, DecidableEq

structure ModelInterfaceRequestV1 where
  schema : String := negotiationSchemaV1
  request : RequestMode
  policy : NegotiationPolicy
  acceptDescriptorSchemas : List String
  expectedSemanticDigest : Option SemanticDigest := none
  ifNoneMatch : Option SemanticDigest := none
  deriving Repr, DecidableEq

/-- Facts established outside the pure policy module. `none` means descriptor
resolution was unavailable; no failure text crosses this seam. -/
structure NegotiationFacts where
  supportedDescriptorSchemas : List String := [descriptorSchemaV1]
  resolvedSemanticDigest : Option SemanticDigest
  descriptorFits : Bool := true
  finalEnvelopeFits : Bool := true
  deriving Repr, DecidableEq

structure NegotiationDecision where
  status : Option NegotiationStatus
  interfaceOk : Bool
  emitRegisterError : Bool
  includeDescriptor : Bool
  deriving Repr, DecidableEq

/-- Select the first client-preferred descriptor schema supported by the
server. The result is only a schema identity, never a URL or loader name. -/
def selectDescriptorSchema (accepted supported : List String) : Option String :=
  accepted.find? (fun schema => supported.contains schema)

def requestWellFormed (request : ModelInterfaceRequestV1) : Bool :=
  request.schema == negotiationSchemaV1 &&
    !request.acceptDescriptorSchemas.isEmpty &&
    match request.request with
    | .verify => request.expectedSemanticDigest.isSome && request.ifNoneMatch.isNone
    | .descriptor => true

/-- Status precedence is normative and matches the distribution design. -/
def selectNegotiationStatus (request : ModelInterfaceRequestV1)
    (facts : NegotiationFacts) : NegotiationStatus :=
  if (selectDescriptorSchema request.acceptDescriptorSchemas
      facts.supportedDescriptorSchemas).isNone then
    .unsupported
  else
    match facts.resolvedSemanticDigest with
    | none => .unavailable
    | some actual =>
        if request.expectedSemanticDigest.any (fun expected => expected != actual) then
          .mismatch
        else
          match request.request with
          | .verify => .matched
          | .descriptor =>
              if request.ifNoneMatch == some actual then
                .notModified
              else if !facts.descriptorFits || !facts.finalEnvelopeFits then
                .tooLarge
              else
                .resolved

/-- Exact digest pins never fall back. Other unavailable capabilities may
continue only under an explicit `prefer` policy. -/
def statusPermitsReplay (policy : NegotiationPolicy) : NegotiationStatus → Bool
  | .matched | .resolved | .notModified => true
  | .mismatch => false
  | .unsupported | .unavailable | .tooLarge => policy == .prefer

/-- No request means legacy success. A present request contributes the pure
`interfaceOk` bit that the session protocol combines with validation. -/
def interfaceOk (request : Option ModelInterfaceRequestV1)
    (facts : NegotiationFacts) : Bool :=
  match request with
  | none => true
  | some request =>
      requestWellFormed request &&
        statusPermitsReplay request.policy (selectNegotiationStatus request facts)

def decideNegotiation (request : Option ModelInterfaceRequestV1)
    (facts : NegotiationFacts) : NegotiationDecision :=
  match request with
  | none =>
      { status := none, interfaceOk := true, emitRegisterError := false,
        includeDescriptor := false }
  | some request =>
      let status := selectNegotiationStatus request facts
      let ok := requestWellFormed request && statusPermitsReplay request.policy status
      { status := some status
        interfaceOk := ok
        emitRegisterError := !ok
        includeDescriptor := ok && status == .resolved }

@[simp] theorem interfaceOk_legacy (facts : NegotiationFacts) :
    interfaceOk none facts = true := rfl

@[simp] theorem statusPermitsReplay_mismatch (policy : NegotiationPolicy) :
    statusPermitsReplay policy .mismatch = false := by cases policy <;> rfl

@[simp] theorem statusPermitsReplay_matched (policy : NegotiationPolicy) :
    statusPermitsReplay policy .matched = true := by cases policy <;> rfl

@[simp] theorem statusPermitsReplay_resolved (policy : NegotiationPolicy) :
    statusPermitsReplay policy .resolved = true := by cases policy <;> rfl

@[simp] theorem statusPermitsReplay_notModified (policy : NegotiationPolicy) :
    statusPermitsReplay policy .notModified = true := by cases policy <;> rfl

theorem required_failure_not_ok (status : NegotiationStatus)
    (h : status ≠ .matched ∧ status ≠ .resolved ∧ status ≠ .notModified) :
    statusPermitsReplay .require status = false := by
  cases status <;> simp_all [statusPermitsReplay]

theorem decision_descriptor_implies_resolved (request : ModelInterfaceRequestV1)
    (facts : NegotiationFacts) :
    (decideNegotiation (some request) facts).includeDescriptor = true →
      selectNegotiationStatus request facts = .resolved := by
  simp [decideNegotiation]

end Core.ModelInterface
