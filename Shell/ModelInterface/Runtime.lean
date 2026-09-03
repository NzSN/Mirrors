import Core.ModelInterface
import Codec.ModelInterfaceJson
import Codec.ModelInterfaceDistributionJson
import Codec.Json
import Shell.ModelInterface.Cache
import Std.Sync.Mutex
import Std.Sync.Semaphore

/-!
# Runtime model-interface resolution

Composes the pure resolver, canonical codecs, digests, and negotiation policy.
It returns payloads to the session shell; it never sends protocol messages or
invokes target emitters.
-/

namespace Shell.ModelInterface.Runtime

open Core.ModelInterface

def maxInlineDescriptorBytes : Nat := 32768
def maxRuntimeDiagnostics : Nat := 64

inductive Access where
  | disabled
  | verifyOnly
  | descriptor
  deriving Repr, DecidableEq

/-- Whether a request is authorized and structurally eligible to perform
compiler/cache/source work. Failure classification still belongs to `resolve`. -/
def mayPerformResolution (access : Access)
    (request : Option Codec.ModelInterfaceDistributionJson.RequestV1) : Bool :=
  match request with
  | none => false
  | some request =>
      access != .disabled &&
        (request.request != .descriptor || access == .descriptor) &&
        (selectDescriptorSchema request.acceptDescriptorSchemas
          [descriptorSchemaV1]).isSome &&
        match request.contract with
        | .inline _ => true
        | .digest _ => false

structure Resolution where
  decision : NegotiationDecision
  lock : Option LockedModelInterface := none
  reply : Option Codec.ModelInterfaceDistributionJson.ReplyV1 := none
  failure : Option Codec.ModelInterfaceDistributionJson.FailureV1 := none
  diagnostics : List Diagnostic := []
  deriving Repr

/-- Authorization identity used only to scope cache lookup and accounting.
Access policy remains an explicit argument to the pure `resolve` function. -/
structure AuthorizationScope where
  securityRealm : String
  principalId : Option String := none
  tenantId : Option String := none
  deriving Repr, BEq

/-- Default scope for direct/local callers that do not supply transport
authorization explicitly. Production server modes always pass their context. -/
def localAuthorizationScope : AuthorizationScope := {
  securityRealm := "local-stdio"
  principalId := some "local-stdio"
}

/-- Bounded process-local runtime state. Descriptor storage, negative results,
key-level single-flight, per-scope queue admission, and resolution concurrency
are intentionally separate resources. -/
private structure ResolutionArtifact where
  descriptor : Option SemanticDescriptor := none
  diagnostics : List Diagnostic := []
  deriving Inhabited

private structure InFlightResolution where
  key : Cache.ScopedResolutionKey
  result : IO.Promise ResolutionArtifact
  waiters : Nat := 0

private structure NegativeResolution where
  key : Cache.ScopedResolutionKey
  artifact : ResolutionArtifact
  expiresAtMs : Nat

structure Service where
  cache : Cache.DescriptorCache
  resolutionSlots : Std.Semaphore
  inFlight : Std.Mutex (List InFlightResolution)
  negative : Std.Mutex (List NegativeResolution)
  maxInFlight : Nat
  maxInFlightPerScope : Nat
  maxNegativeEntries : Nat
  maxNegativeEntriesPerScope : Nat
  negativeTtlMs : Nat
  resolutionRuns : IO.Ref Nat

def Service.new (maxEntries : Nat := 128)
    (maxBytes : Nat := 16 * 1024 * 1024) (maxConcurrent : Nat := 4)
    (maxQueued : Nat := 32) (maxQueuedPerScope : Nat := 8)
    (maxNegativeEntries : Nat := 128)
    (maxNegativeEntriesPerScope : Nat := 64)
    (negativeTtlMs : Nat := 30 * 1000) :
    BaseIO Service := do
  return {
    cache := ← Cache.new maxEntries maxBytes
    resolutionSlots := ← Std.Semaphore.new (max 1 maxConcurrent)
    inFlight := ← Std.Mutex.new []
    negative := ← Std.Mutex.new []
    maxInFlight := max 1 (maxConcurrent + maxQueued)
    maxInFlightPerScope := max 1 maxQueuedPerScope
    maxNegativeEntries := max 1 maxNegativeEntries
    maxNegativeEntriesPerScope := max 1 maxNegativeEntriesPerScope
    negativeTtlMs := max 1 negativeTtlMs
    resolutionRuns := ← IO.mkRef 0
  }

structure CachedResolution where
  resolution : Resolution
  cacheHit : Bool
  key : Option Cache.ScopedResolutionKey := none
  deriving Repr

private def statusCode : NegotiationStatus → String
  | .matched => "interface_matched"
  | .resolved => "interface_resolved"
  | .notModified => "interface_not_modified"
  | .mismatch => "interface_digest_mismatch"
  | .unsupported => "interface_schema_unsupported"
  | .unavailable => "interface_unavailable"
  | .tooLarge => "interface_descriptor_too_large"

private def wireStatus (status : NegotiationStatus) :
    Codec.ModelInterfaceDistributionJson.Status :=
  Codec.ModelInterfaceDistributionJson.Status.ofCore status

private def digestDescriptor (descriptor : SemanticDescriptor) : SemanticDigest :=
  Core.ModelInterface.Sha256.digestDomainHex descriptorDigestDomainV1
    (Codec.ModelInterfaceJson.canonicalSemanticDescriptorBytes descriptor)

private def digestProvenance (provenance : LockProvenance) : ProvenanceDigest :=
  Core.ModelInterface.Sha256.digestDomainHex
    "mirrors-model-interface-provenance/v1"
    (Codec.ModelInterfaceJson.canonicalProvenanceBytes provenance)

private def resolvedEnvelopeFits
    (descriptor : SemanticDescriptor) (semanticDigest provenanceDigest : String)
    (descriptorBytes : Nat) : Bool :=
  let reply : Codec.ModelInterfaceDistributionJson.ReplyV1 := {
    status := .resolved
    descriptorSchema := some descriptorSchemaV1
    semanticDigest := some semanticDigest
    provenanceDigest := some provenanceDigest
    descriptorBytes := some descriptorBytes
    descriptor := some descriptor
  }
  let base := Codec.encodeMirror (.specValidated .valid)
  match Codec.ModelInterfaceDistributionJson.insertSpecValidatedReply? base (some reply) with
  | .error _ => false
  | .ok json => (Lean.Json.compress json).toUTF8.size ≤ 65535

private def unavailable (request : Codec.ModelInterfaceDistributionJson.RequestV1)
    (diagnostics : List Diagnostic := []) : Resolution :=
  let facts : NegotiationFacts := { resolvedSemanticDigest := none }
  let decision := decideNegotiation (some request.toCore) facts
  let status := decision.status.getD .unavailable
  let failure := if decision.emitRegisterError then some {
      status := wireStatus status
      code := statusCode status
      expectedSemanticDigest := request.expectedSemanticDigest
    } else none
  let reply := if decision.emitRegisterError then none else some {
      status := wireStatus status
    }
  { decision, reply, failure, diagnostics }

/-- Convert a post-resolution trace/preflight failure into the same safe
`unavailable` negotiation outcome without exposing raw trace diagnostics on
the wire. Legacy calls never use this hook. -/
def rejectUnavailable
    (request : Option Codec.ModelInterfaceDistributionJson.RequestV1)
    (diagnostics : List Diagnostic) : Resolution :=
  match request with
  | some request => unavailable request diagnostics
  | none => { decision := decideNegotiation none { resolvedSemanticDigest := none } }

/-- Trace evidence that contradicts a resolved interface is an invalid
registration, not a missing optional capability. It is therefore terminal for
both `require` and `prefer`; preference can only relax unavailable capability
or descriptor delivery. -/
def rejectPreflight
    (request : Option Codec.ModelInterfaceDistributionJson.RequestV1)
    (diagnostics : List Diagnostic) : Resolution :=
  match request with
  | none => { decision := decideNegotiation none { resolvedSemanticDigest := none } }
  | some request =>
      { decision := {
          status := some .unavailable
          interfaceOk := false
          emitRegisterError := true
          includeDescriptor := false
        }
        failure := some {
          status := .unavailable
          code := "interface_trace_preflight_failed"
          expectedSemanticDigest := request.expectedSemanticDigest
        }
        diagnostics }

private def unsupported (request : Codec.ModelInterfaceDistributionJson.RequestV1) :
    Resolution :=
  let facts : NegotiationFacts := {
    supportedDescriptorSchemas := []
    resolvedSemanticDigest := none
  }
  let decision := decideNegotiation (some request.toCore) facts
  let status := decision.status.getD .unsupported
  let failure := if decision.emitRegisterError then some {
      status := wireStatus status
      code := statusCode status
      expectedSemanticDigest := request.expectedSemanticDigest
    } else none
  let reply := if decision.emitRegisterError then none else some {
      status := wireStatus status
  }
  { decision, reply, failure }

private def negotiateDescriptor
    (request : Codec.ModelInterfaceDistributionJson.RequestV1)
    (contract : ContractV1) (descriptor : SemanticDescriptor)
    (provenance : LockProvenance)
    (diagnostics : List Diagnostic) (access : Access) : Resolution :=
  let semanticDigest := digestDescriptor descriptor
  let provenanceDigest := digestProvenance provenance
  let descriptorBytes :=
    Codec.ModelInterfaceJson.canonicalSemanticDescriptorBytes descriptor
  let facts : NegotiationFacts := {
    resolvedSemanticDigest := some semanticDigest
    descriptorFits := descriptorBytes.size ≤ maxInlineDescriptorBytes
    finalEnvelopeFits := resolvedEnvelopeFits descriptor semanticDigest
      provenanceDigest descriptorBytes.size
  }
  let decision := decideNegotiation (some request.toCore) facts
  let status := decision.status.getD .unavailable
  let lock : LockedModelInterface := {
    toSemanticDescriptor := descriptor
    contract := normalizeContractV1 contract
    semanticDigest := semanticDigest
    provenanceDigest := provenanceDigest
    provenance := provenance
  }
  let reply := if decision.emitRegisterError then none else
    let carriesIdentity := status == .matched || status == .resolved ||
      status == .notModified || status == .tooLarge
    some {
      status := wireStatus status
      descriptorSchema := if carriesIdentity then
        some descriptorSchemaV1 else none
      semanticDigest := if carriesIdentity then some semanticDigest else none
      provenanceDigest := if status == .resolved then
        some provenanceDigest else none
      descriptorBytes :=
        if status == .resolved || status == .tooLarge then
          some descriptorBytes.size else none
      descriptor := if decision.includeDescriptor then some descriptor else none
    }
  let failure := if decision.emitRegisterError then some {
    status := wireStatus status
    code := statusCode status
    expectedSemanticDigest := request.expectedSemanticDigest
    actualSemanticDigest :=
      if status == .mismatch && access == .descriptor then
        some semanticDigest else none
    provenanceDigest :=
      if status == .mismatch && access == .descriptor then
        some provenanceDigest else none
    descriptorBytes := if status == .tooLarge then some descriptorBytes.size else none
  } else none
  { decision, lock := some lock, reply, failure, diagnostics }

/-- Resolve and negotiate one optional request. No request is a zero-work,
byte-compatible legacy decision. -/
def resolve (request : Option Codec.ModelInterfaceDistributionJson.RequestV1)
    (evidence : Option ModelEvidence) (configuredParamVar : Option String)
    (sources : List SourceDigest := []) (compilerVersion : String := "development")
    (access : Access := .descriptor) :
    Resolution :=
  match request with
  | none =>
      { decision := decideNegotiation none { resolvedSemanticDigest := none } }
  | some request =>
      if access == .disabled ||
          (request.request == .descriptor && access != .descriptor) then
        unavailable request
      else if (selectDescriptorSchema request.acceptDescriptorSchemas
          [descriptorSchemaV1]).isNone then
        unsupported request
      else match request.contract, evidence with
      | .digest _, _ => unavailable request
      | _, none => unavailable request
      | .inline contract, some evidence =>
          let contractBytes := Codec.ModelInterfaceJson.canonicalBytes
            (Codec.ModelInterfaceJson.encodeContract contract)
          let input : ResolveInput := {
            contract := Located.unlocated contract
            evidence := evidence
            runProfile := { configuredParamVar }
            sources := sources
            compilerVersion := compilerVersion
            contractSha256 := Core.ModelInterface.Sha256.digestDomainHex
              "mirrors-model-interface-contract/v1" contractBytes
          }
          let resolved := Core.ModelInterface.resolve input
          match resolved.value with
          | none => unavailable request resolved.diagnostics
          | some interface =>
              negotiateDescriptor request interface.contract interface.semanticDescriptor
                interface.provenance resolved.diagnostics access

/-! ## Effectful scoped resolution cache -/

private def sortedStrings (values : List String) : List String :=
  values.mergeSort (· ≤ ·)

private def sortedSources (sources : List SourceDigest) : List SourceDigest :=
  sources.mergeSort fun left right =>
    if left.moduleName == right.moduleName then
      left.logicalPath ≤ right.logicalPath
    else
      left.moduleName ≤ right.moduleName

private def sourceJson (source : SourceDigest) : Lean.Json :=
  Lean.Json.mkObj [
    ("module", .str source.moduleName),
    ("path", .str source.logicalPath),
    ("sha256", .str source.contentSha256)
  ]

private def originText : EvidenceOrigin → String
  | .apalacheTypecheck => "apalacheTypecheck"
  | .itfVarTypes => "itfVarTypes"
  | .contractAssertion => "contractAssertion"

private def typeFactJson (fact : TypeFact) : Lean.Json :=
  Lean.Json.mkObj [
    ("modelPath", .str (toString (repr fact.modelPath))),
    ("origin", .str (originText fact.origin)),
    ("type", Codec.ModelInterfaceJson.encodeModelType fact.type)
  ]

private def sortedTypeFacts (facts : List TypeFact) : List TypeFact :=
  facts.mergeSort fun left right =>
    Lean.Json.compress (typeFactJson left) ≤ Lean.Json.compress (typeFactJson right)

private def contractDigest (contract : ContractV1) : String :=
  Core.ModelInterface.Sha256.digestDomainHex
    "mirrors-model-interface-contract/v1"
    (Codec.ModelInterfaceJson.canonicalBytes
      (Codec.ModelInterfaceJson.encodeContract contract))

private def provenanceOf (contract : ContractV1) (evidence : ModelEvidence)
    (sources : List SourceDigest) (compilerVersion : String) : LockProvenance :=
  {
    compilerVersion := compilerVersion
    contractSha256 := contractDigest contract
    evidenceSha256 := evidence.evidenceSha256
    sources := sortedSources sources
  }

/-- Deterministic resolution identity. Authorization scope is deliberately not
hashed into this fingerprint; it forms a separate tuple component in the cache
key so identical content can never authorize cross-realm lookup. -/
def resolutionFingerprint (contract : ContractV1) (evidence : ModelEvidence)
    (configuredParamVar : Option String) (sources : List SourceDigest) : String :=
  let payload := Lean.Json.mkObj [
    ("contractDigest", .str (contractDigest contract)),
    ("evidenceDigest", .str evidence.evidenceSha256),
    ("itfParamVars", .arr
      ((sortedStrings evidence.itfParamVars).map Lean.Json.str).toArray),
    ("resolverSemanticsVersion", .str resolverSemanticsV1),
    ("runProfile", Lean.Json.mkObj [
      ("configuredParamVar", match configuredParamVar with
        | some value => .str value
        | none => .null)
    ]),
    ("sources", .arr ((sortedSources sources).map sourceJson).toArray),
    ("typeFacts", .arr ((sortedTypeFacts evidence.typeFacts).map typeFactJson).toArray),
    ("traceVars", .arr
      ((sortedStrings evidence.traceVars).map Lean.Json.str).toArray)
  ]
  Core.ModelInterface.Sha256.digestDomainHex
    "mirrors-model-interface-resolution/v1"
    (Codec.ModelInterfaceJson.canonicalBytes payload)

private def scopedKey (scope : AuthorizationScope) (contract : ContractV1)
    (evidence : ModelEvidence) (configuredParamVar : Option String)
    (sources : List SourceDigest) : Cache.ScopedResolutionKey :=
  {
    securityRealm := scope.securityRealm
    principalId := scope.principalId
    tenantId := scope.tenantId
    fingerprint := resolutionFingerprint contract evidence configuredParamVar sources
  }

private def sameResolutionScope (left right : Cache.ScopedResolutionKey) : Bool :=
  left.securityRealm == right.securityRealm &&
    left.principalId == right.principalId &&
    left.tenantId == right.tenantId

private def negativeLookup (service : Service) (key : Cache.ScopedResolutionKey) :
    IO (Option ResolutionArtifact) := do
  let now ← IO.monoMsNow
  service.negative.atomically do
    let entries ← get
    let entries := entries.filter (fun entry => now < entry.expiresAtMs)
    match entries.find? (fun entry => entry.key == key) with
    | none =>
        set entries
        return none
    | some found =>
        set (found :: entries.filter (fun entry => !(entry.key == key)))
        return some found.artifact

private def negativeRemove (service : Service) (key : Cache.ScopedResolutionKey) :
    IO Unit :=
  service.negative.atomically do
    let entries ← get
    set (entries.filter (fun entry => !(entry.key == key)))

private def negativePut (service : Service) (key : Cache.ScopedResolutionKey)
    (_artifact : ResolutionArtifact) : IO Unit := do
  let now ← IO.monoMsNow
  let summary : ResolutionArtifact := {}
  service.negative.atomically do
    let entries ← get
    let remaining := entries.filter (fun entry =>
      now < entry.expiresAtMs && !(entry.key == key))
    let sameScope := remaining.filter (fun entry => sameResolutionScope entry.key key)
    let otherScopes := remaining.filter (fun entry => !sameResolutionScope entry.key key)
    let scopedEntries := ({
      key
      artifact := summary
      expiresAtMs := now + service.negativeTtlMs
    } : NegativeResolution) :: sameScope
    let scopedEntries := scopedEntries.take service.maxNegativeEntriesPerScope
    set ((scopedEntries ++ otherScopes).take service.maxNegativeEntries)

private inductive InFlightAdmission where
  | leader (result : IO.Promise ResolutionArtifact)
  | follower (result : IO.Promise ResolutionArtifact)
  | rejected

private def admitInFlight (service : Service) (key : Cache.ScopedResolutionKey) :
    IO InFlightAdmission := do
  let candidate ← IO.Promise.new
  service.inFlight.atomically do
    let entries ← get
    let totalRequests := entries.foldl
      (fun count entry => count + 1 + entry.waiters) 0
    let scopeRequests := entries.foldl (fun count entry =>
      if sameResolutionScope entry.key key then count + 1 + entry.waiters
      else count) 0
    let atCapacity := totalRequests >= service.maxInFlight ||
      scopeRequests >= service.maxInFlightPerScope
    match entries.find? (fun entry => entry.key == key) with
    | some existing =>
        if atCapacity then return .rejected
        set (entries.map fun entry =>
          if entry.key == key then { entry with waiters := entry.waiters + 1 }
          else entry)
        return .follower existing.result
    | none =>
        if atCapacity then return .rejected
        set (({ key, result := candidate } : InFlightResolution) :: entries)
        return .leader candidate

private def removeInFlight (service : Service) (key : Cache.ScopedResolutionKey) :
    IO Unit :=
  service.inFlight.atomically do
    let entries ← get
    set (entries.filter (fun entry => !(entry.key == key)))

private partial def awaitResolutionArtifact
    (promise : IO.Promise ResolutionArtifact) : IO (Option ResolutionArtifact) := do
  if ← promise.isResolved then
    IO.wait promise.result?
  else
    IO.sleep 5
    awaitResolutionArtifact promise

private def resolutionFromArtifact
    (request : Codec.ModelInterfaceDistributionJson.RequestV1)
    (contract : ContractV1) (evidence : ModelEvidence)
    (sources : List SourceDigest) (compilerVersion : String) (access : Access)
    (artifact : ResolutionArtifact) : Resolution :=
  match artifact.descriptor with
  | some descriptor =>
      negotiateDescriptor request contract descriptor
        (provenanceOf contract evidence sources compilerVersion)
        artifact.diagnostics access
  | none => unavailable request artifact.diagnostics

/-- Test and operations visibility for the number of actual pure resolver
executions. Cache hits, negative hits, and in-flight followers do not increment
this counter. -/
def resolutionRunCount (service : Service) : IO Nat := service.resolutionRuns.get

private def cachedResolution? (service : Service) (key : Cache.ScopedResolutionKey)
    (request : Codec.ModelInterfaceDistributionJson.RequestV1)
    (contract : ContractV1) (evidence : ModelEvidence) (sources : List SourceDigest)
    (compilerVersion : String) (access : Access) : IO (Option Resolution) := do
  let some entry ← Cache.lookup service.cache key | return none
  match Codec.ModelInterfaceJson.parseDescriptorBytes entry.bytes with
  | .error _ => return none
  | .ok descriptor =>
      let provenance := provenanceOf contract evidence sources compilerVersion
      return some (negotiateDescriptor request contract descriptor provenance [] access)

private def acquireResolutionSlot (service : Service) : IO Unit := do
  let permit ← service.resolutionSlots.acquire
  let _ ← IO.wait permit.result?
  return ()

private def withResolutionSlot (service : Service) (action : IO α) : IO α := do
  acquireResolutionSlot service
  try
    let result ← action
    service.resolutionSlots.release
    return result
  catch error =>
    service.resolutionSlots.release
    throw error

/-- Cache-aware form of `resolve`. Legacy, disabled, unavailable-evidence, and
future digest-reference requests retain the exact pure behavior and perform no
cache work. Eligible misses are key-deduplicated, queue-bounded per scope,
negative-cached, and admitted through a separate semaphore; hits bypass it. -/
def resolveCached (service : Service) (scope : AuthorizationScope)
    (request : Option Codec.ModelInterfaceDistributionJson.RequestV1)
    (evidence : Option ModelEvidence) (configuredParamVar : Option String)
    (sources : List SourceDigest := []) (compilerVersion : String := "development")
    (access : Access := .descriptor) : IO CachedResolution := do
  let fallback : Unit → Resolution := fun _ =>
    resolve request evidence configuredParamVar sources compilerVersion access
  let some request := request
    | return { resolution := fallback (), cacheHit := false }
  if access == .disabled ||
      (request.request == .descriptor && access != .descriptor) then
    return { resolution := fallback (), cacheHit := false }
  if (selectDescriptorSchema request.acceptDescriptorSchemas
      [descriptorSchemaV1]).isNone then
    return { resolution := fallback (), cacheHit := false }
  let .inline contract := request.contract
    | return { resolution := fallback (), cacheHit := false }
  let some evidence := evidence
    | return { resolution := fallback (), cacheHit := false }
  let key := scopedKey scope contract evidence configuredParamVar sources
  if let some cached ← cachedResolution? service key request contract evidence
      sources compilerVersion access then
    return { resolution := cached, cacheHit := true, key := some key }
  if let some artifact ← negativeLookup service key then
    return {
      resolution := resolutionFromArtifact request contract evidence sources
        compilerVersion access artifact
      cacheHit := false
      key := some key
    }
  match ← admitInFlight service key with
  | .rejected =>
      return {
        resolution := unavailable request []
        cacheHit := false
        key := some key
      }
  | .follower promise =>
      let some artifact ← awaitResolutionArtifact promise
        | return {
            resolution := unavailable request []
            cacheHit := false
            key := some key
          }
      return {
        resolution := resolutionFromArtifact request contract evidence sources
          compilerVersion access artifact
        cacheHit := false
        key := some key
      }
  | .leader promise =>
      let finish (artifact : ResolutionArtifact) : IO CachedResolution := do
        promise.resolve artifact
        removeInFlight service key
        return {
          resolution := resolutionFromArtifact request contract evidence sources
            compilerVersion access artifact
          cacheHit := false
          key := some key
        }
      try
        -- Close the small miss/admission race after a prior leader publishes.
        if let some cached ← cachedResolution? service key request contract evidence
            sources compilerVersion access then
          let artifact : ResolutionArtifact := {
            descriptor := cached.lock.map (·.semanticDescriptor)
            diagnostics := cached.diagnostics
          }
          return ← finish artifact
        if let some artifact ← negativeLookup service key then
          return ← finish artifact
        let artifact ← withResolutionSlot service do
          service.resolutionRuns.modify (fun count => count + 1)
          let resolution := resolve (some request) (some evidence)
            configuredParamVar sources compilerVersion access
          let artifact : ResolutionArtifact := {
            descriptor := resolution.lock.map (·.semanticDescriptor)
            diagnostics := (sortDiagnostics resolution.diagnostics).take
              maxRuntimeDiagnostics
          }
          match artifact.descriptor with
          | none => negativePut service key artifact
          | some descriptor =>
              negativeRemove service key
              let bytes := Codec.ModelInterfaceJson.canonicalSemanticDescriptorBytes
                descriptor
              let claimed := Cache.semanticDigest bytes
              let _ ← Cache.put service.cache key claimed bytes
              pure ()
          return artifact
        finish artifact
      catch _ =>
        let artifact : ResolutionArtifact := {}
        negativePut service key artifact
        finish artifact

end Shell.ModelInterface.Runtime
