import Core.ModelInterface
import Core.ModelInterface.Sha256
import Codec.StrictJson
import Shell.ModelInterface.Cache
import Shell.ModelInterface.Evidence
import Shell.ModelInterface.Emit.TypeScript
import Shell.ModelInterface.Runtime
import Shell.ModelInterface.Compiler

/-!
# Always-on model-interface specification

Executable coverage for the pure compiler and its first shell adapters. This
suite has no network or Apalache dependency; filesystem-hardening cases use
only freshly-created temporary directories.
-/

namespace ModelInterfaceSpec

open Core.ModelInterface

abbrev Failures := IO.Ref (List String)

def check (fails : Failures) (name : String) (ok : Bool)
    (detail : String := "") : IO Unit := do
  if !ok then
    if detail.isEmpty then
      fails.modify (fun fs => fs ++ [name])
    else
      fails.modify (fun fs => fs ++ [s!"{name}: {detail}"])

def strictErrorIs {α : Type} (kind : Codec.StrictJson.ErrorKind)
    (result : Except Codec.StrictJson.Error α) : Bool :=
  match result with
  | .error error => error.kind == kind
  | .ok _ => false

def counterEvidenceJson : String := String.intercalate "\n" [
  "{",
  "  \"#meta\": {",
  "    \"format\": \"ITF\",",
  "    \"varTypes\": {",
  "      \"parameters\": \"{ stride: Int }\",",
  "      \"action_taken\": \"Str\",",
  "      \"count\": \"Int\"",
  "    }",
  "  },",
  "  \"params\": [\"STRIDES\"],",
  "  \"vars\": [\"parameters\", \"action_taken\", \"count\"],",
  "  \"states\": [",
  "    {",
  "      \"#meta\": { \"index\": 0 },",
  "      \"action_taken\": \"init\",",
  "      \"count\": { \"#bigint\": \"0\" },",
  "      \"parameters\": { \"stride\": { \"#bigint\": \"0\" } }",
  "    },",
  "    {",
  "      \"#meta\": { \"index\": 1 },",
  "      \"action_taken\": \"tick\",",
  "      \"count\": { \"#bigint\": \"2\" },",
  "      \"parameters\": { \"stride\": { \"#bigint\": \"2\" } }",
  "    }",
  "  ]",
  "}"
]

def counterContract : ContractV1 where
  schema := contractSchemaV1
  interfaceVersion := "1.0.0"
  model := { moduleName := "Counter", source := "specs/Counter.tla" }
  wire := {
    actionVariable := actionVariableV1
    parameterVariable := some "parameters"
  }
  initializers := [{
    id := "Initialize"
    wireAction := "init"
  }]
  actions := [{
    id := "Tick"
    wireAction := "tick"
    inputs := [{
      id := "Stride"
      fromRoot := .stepParameters
      path := [.field "parameters", .field "stride"]
    }]
  }]
  observations := [{
    id := "Count"
    wireName := "count"
    provenance := .implementation
  }]

def counterRunProfile : RunProfile where
  configuredParamVar := some "parameters"

def counterResolveInput (evidence : ModelEvidence) : ResolveInput where
  contract := Located.unlocated counterContract
  evidence := evidence
  runProfile := counterRunProfile
  compilerVersion := "model-interface-spec"
  contractSha256 :=
    Core.ModelInterface.Sha256.digestDomainHex
      "mirrors-model-interface-contract/v1" "counter-contract".toUTF8

def resolvedSemanticBytes (resolved : ResolvedModelInterface) : ByteArray :=
  (toString (repr resolved.semanticDescriptor)).toUTF8

def scenarioShaAndStrictJson (fails : Failures) : IO Unit := do
  check fails "sha: all known vectors"
    Core.ModelInterface.Sha256.knownVectorsOk
  check fails "sha: abc"
    (Core.ModelInterface.Sha256.digestStringHex "abc" ==
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

  check fails "strict-json: escaped duplicate"
    (strictErrorIs .duplicateKey
      (Codec.StrictJson.parseString "{\"a\":1,\"\\u0061\":2}"))
  check fails "strict-json: direct duplicate"
    (strictErrorIs .duplicateKey
      (Codec.StrictJson.parseString "{\"a\":1,\"a\":2}"))
  check fails "strict-json: invalid UTF-8"
    (strictErrorIs .invalidUtf8
      (Codec.StrictJson.parseBytes (ByteArray.empty.push 0xff)))
  check fails "strict-json: byte limit"
    (strictErrorIs .tooLarge
      (Codec.StrictJson.parseString "{}" { maxBytes := 1 }))
  check fails "strict-json: valid nested value"
    (Codec.StrictJson.parseString
      "{\"left\":{\"x\":1},\"right\":{\"x\":2}}").isOk

def scenarioCanonicalDiagnostics (fails : Failures) : IO Unit := do
  let primary : SourceLocation := {
    source := "contract.json"
    pointer := some "/observations/0"
  }
  let relatedA : SourceLocation := {
    source := "a.tla"
    pointer := some "/z"
    line := some 2
  }
  let relatedB : SourceLocation := {
    source := "b.tla"
    pointer := some "/a"
    column := some 3
  }
  let first : Diagnostic := {
    code := "MIC-R-TYPE-001"
    severity := .error
    stage := "resolve"
    subject := { kind := "observation", stableId := some "Count" }
    primary
    related := [relatedB, relatedA, relatedB]
    arguments := [("z", "2"), ("a", "2"), ("a", "1"), ("a", "1")]
  }
  let second : Diagnostic := {
    first with
      related := []
      arguments := [("a", "0")]
  }
  let encodedFirst := Codec.ModelInterfaceJson.canonicalString
    (Codec.ModelInterfaceJson.encodeDiagnostic first)
  let expectedFirst :=
    "{\"arguments\":[{\"name\":\"a\",\"value\":\"1\"}," ++
    "{\"name\":\"a\",\"value\":\"2\"},{\"name\":\"z\",\"value\":\"2\"}]," ++
    "\"code\":\"MIC-R-TYPE-001\",\"primary\":{" ++
    "\"pointer\":\"/observations/0\",\"source\":\"contract.json\"}," ++
    "\"related\":[{\"line\":2,\"pointer\":\"/z\",\"source\":\"a.tla\"}," ++
    "{\"column\":3,\"pointer\":\"/a\",\"source\":\"b.tla\"}]," ++
    "\"severity\":\"error\",\"stage\":\"resolve\",\"subject\":{" ++
    "\"kind\":\"observation\",\"stableId\":\"Count\"}}"
  check fails "canonical diagnostics: arguments and related are sorted and unique"
    (encodedFirst == expectedFirst)
    (s!"actual={encodedFirst}, expected={expectedFirst}")

  let forward := Codec.ModelInterfaceJson.canonicalString
    (Codec.ModelInterfaceJson.encodeDiagnostics [first, second])
  let reversed := Codec.ModelInterfaceJson.canonicalString
    (Codec.ModelInterfaceJson.encodeDiagnostics [second, first])
  check fails "canonical diagnostics: equal-base ordering includes arguments"
    (forward == reversed &&
      forward.startsWith
        "[{\"arguments\":[{\"name\":\"a\",\"value\":\"0\"}]")
    (s!"forward={forward}, reversed={reversed}")

  let relatedFirst : Diagnostic := { second with related := [relatedA] }
  let relatedSecond : Diagnostic := { second with related := [relatedB] }
  let warning : Diagnostic := { second with severity := .warning }
  let ordered := [second, relatedFirst, relatedSecond, warning]
  let orderedJson := Codec.ModelInterfaceJson.canonicalString
    (Codec.ModelInterfaceJson.encodeDiagnostics ordered)
  let shuffledJson := Codec.ModelInterfaceJson.canonicalString
    (Codec.ModelInterfaceJson.encodeDiagnostics
      [warning, relatedSecond, second, relatedFirst])
  let expectedOrderedJson := "[" ++ String.intercalate ","
    (ordered.map fun diagnostic => Codec.ModelInterfaceJson.canonicalString
      (Codec.ModelInterfaceJson.encodeDiagnostic diagnostic)) ++ "]"
  check fails "canonical diagnostics: severity and related locations are total tie breakers"
    (orderedJson == shuffledJson && orderedJson == expectedOrderedJson)
    (s!"ordered={orderedJson}, shuffled={shuffledJson}, expected={expectedOrderedJson}")
  check fails "logical path: Windows drive-like path rejected"
    (!validLogicalPath "C:Counter.tla")
  check fails "logical path: colon segment rejected"
    (!validLogicalPath "specs/private:Counter.tla")

def scenarioCounterResolution (fails : Failures) :
    IO (Option (ModelEvidence × ResolvedModelInterface)) := do
  let evidence ← match Shell.ModelInterface.Evidence.fromString
      counterEvidenceJson "embedded-counter.itf.json" with
    | .error error =>
        check fails "counter evidence: parses" false error
        return none
    | .ok evidence =>
        check fails "counter evidence: trace vars"
          (evidence.traceVars ==
            ["parameters", "action_taken", "count"])
          (toString (repr evidence.traceVars))
        check fails "counter evidence: three type facts"
          (evidence.typeFacts.length == 3)
          (toString evidence.typeFacts.length)
        check fails "counter evidence: digest length"
          (evidence.evidenceSha256.length == 64)
          evidence.evidenceSha256
        pure evidence

  let comparable := requiredObservationVars evidence counterRunProfile
  check fails "counter comparable vars: exact count"
    (comparable.length == 1) (toString (repr comparable))
  check fails "counter comparable vars: count only"
    (comparable == ["count"]) (toString (repr comparable))

  let first := resolve (counterResolveInput evidence)
  let second := resolve (counterResolveInput evidence)
  check fails "counter resolve: has value" first.value.isSome
  check fails "counter resolve: no errors" (!first.hasErrors)
    (toString (repr first.diagnostics))
  let some resolved := first.value
    | return none
  let some resolvedAgain := second.value
    | check fails "counter resolve: repeat has value" false
      return none

  check fails "counter resolve: one initializer"
    (resolved.initializers.length == 1)
  check fails "counter resolve: one action"
    (resolved.actions.length == 1)
  check fails "counter resolve: one observation"
    (resolved.observations.length == 1)
  check fails "counter resolve: observation is count"
    (resolved.observations.head?.map (·.wireName) == some "count")
  check fails "counter resolve: stride is int"
    (resolved.actions.head?.bind (fun action =>
      action.inputs.head?.map (·.projection.type)) == some .int)

  let bytes1 := resolvedSemanticBytes resolved
  let bytes2 := resolvedSemanticBytes resolvedAgain
  let digest1 := Core.ModelInterface.Sha256.digestDomainHex
    "mirrors-model-interface-lock/v1" bytes1
  let digest2 := Core.ModelInterface.Sha256.digestDomainHex
    "mirrors-model-interface-lock/v1" bytes2
  let descriptorDigest1 := Shell.ModelInterface.Cache.semanticDigest bytes1
  let descriptorDigest2 := Shell.ModelInterface.Cache.semanticDigest bytes2
  check fails "counter descriptor: deterministic bytes" (bytes1 == bytes2)
  check fails "counter descriptor: deterministic digest" (digest1 == digest2)
    (digest1 ++ " vs " ++ digest2)
  check fails "counter descriptor: deterministic cache digest"
    (descriptorDigest1 == descriptorDigest2)
    (descriptorDigest1 ++ " vs " ++ descriptorDigest2)
  check fails "counter descriptor: digest wire prefix"
    (descriptorDigest1.startsWith "sha256:") descriptorDigest1

  let otherFacts := evidence.typeFacts.filter (fun fact => fact.modelPath.root != "count")
  let conflictFact (type : ModelType) (source : String) (line : Nat) : TypeFact := {
    modelPath := ModelPath.top "count"
    type := type
    origin := .itfVarTypes
    location := { source := source, line := some line }
  }
  let boolFact := conflictFact .bool "a-types.tla" 3
  let stringFact := conflictFact .str "m-types.itf.json" 2
  let intFact := conflictFact .int "z-types.tla" 1
  let resolveConflict (facts : List TypeFact) :=
    resolve (counterResolveInput { evidence with typeFacts := otherFacts ++ facts })
  let firstConflict := resolveConflict [intFact, boolFact, stringFact]
  let secondConflict := resolveConflict [stringFact, intFact, boolFact]
  let thirdConflict := resolveConflict [boolFact, stringFact, intFact]
  let firstConflictBytes := Codec.ModelInterfaceJson.canonicalFileBytes
    (Codec.ModelInterfaceJson.encodeDiagnostics firstConflict.diagnostics)
  let secondConflictBytes := Codec.ModelInterfaceJson.canonicalFileBytes
    (Codec.ModelInterfaceJson.encodeDiagnostics secondConflict.diagnostics)
  let thirdConflictBytes := Codec.ModelInterfaceJson.canonicalFileBytes
    (Codec.ModelInterfaceJson.encodeDiagnostics thirdConflict.diagnostics)
  let expectedConflictBytes ← IO.FS.readBinFile
    "test/fixtures/model-interface/counter/Counter.type-conflict.diagnostics.json"
  check fails "type conflict: shuffled evidence has exact canonical diagnostics"
    (firstConflictBytes == secondConflictBytes &&
      secondConflictBytes == thirdConflictBytes &&
      firstConflictBytes == expectedConflictBytes)
    (s!"first={String.fromUTF8? firstConflictBytes}, " ++
      s!"second={String.fromUTF8? secondConflictBytes}, " ++
      s!"third={String.fromUTF8? thirdConflictBytes}, " ++
      s!"expected={String.fromUTF8? expectedConflictBytes}")
  match firstConflict.diagnostics.find? (fun diagnostic =>
      diagnostic.code == "MIC-R-TYPE-001" &&
        diagnostic.arguments.contains
          ("reason", "conflicting declaration evidence")) with
  | none => check fails "type conflict: conflict diagnostic present" false
  | some diagnostic =>
      check fails "type conflict: canonical primary location"
        (diagnostic.primary == boolFact.location)
        (toString (repr diagnostic.primary))
      check fails "type conflict: canonical related locations"
        (normalizeDiagnosticRelated diagnostic.related ==
          [stringFact.location, intFact.location])
        (toString (repr diagnostic.related))
  return some (evidence, resolved)

private def hasCompilerDiagnostic (code resource : String)
    (result : CompileResult α) : Bool :=
  result.diagnostics.any fun diagnostic =>
    diagnostic.code == code &&
      diagnostic.arguments.any (fun argument =>
        argument.1 == "resource" && argument.2 == resource)

private def nestedSeqType : Nat → ModelType
  | 0 => .int
  | depth + 1 => .seq (nestedSeqType depth)

private def nestedSeqText (wrappers : Nat) : String :=
  (List.range wrappers).foldl (fun inner _ => "Seq(" ++ inner ++ ")") "Int"

def scenarioResourceLimits (fails : Failures) : IO Unit := do
  let evidence ← match Shell.ModelInterface.Evidence.fromString
      counterEvidenceJson "resource-limit-counter.itf.json" with
    | .ok evidence => pure evidence
    | .error error =>
        check fails "resource limits: evidence parses" false error
        return
  check fails "resource limits: evidence parser accepts depth 32"
    (Shell.ModelInterface.Evidence.parseType
      (nestedSeqText (maxStructuralTypeDepthV1 - 1))).isOk
  check fails "resource limits: evidence parser rejects depth 33"
    (!(Shell.ModelInterface.Evidence.parseType
      (nestedSeqText maxStructuralTypeDepthV1)).isOk)
  let tooManyInitializers := (List.range (maxInitializersV1 + 1)).map fun index =>
    ({ id := "Initialize" ++ toString index
       wireAction := "init" ++ toString index } : ContractAction)
  let countLimited := Core.ModelInterface.resolve {
    counterResolveInput evidence with
      contract := Located.unlocated {
        counterContract with initializers := tooManyInitializers }
  }
  check fails "resource limits: initializer count rejected"
    (hasCompilerDiagnostic "MIC-R-LIMIT-001" "initializers" countLimited)

  let longLabel := String.ofList (List.replicate (maxStableNameBytesV1 + 1) 'x')
  let longActions := match counterContract.actions with
    | action :: _ => [{ action with wireAction := longLabel }]
    | [] => []
  let labelLimited := Core.ModelInterface.resolve {
    counterResolveInput evidence with
      contract := Located.unlocated {
        counterContract with
          actions := longActions }
  }
  check fails "resource limits: wire label bytes rejected"
    (hasCompilerDiagnostic "MIC-R-LIMIT-001" "stableIdOrWireLabelBytes"
      labelLimited)

  let deepEvidence : ModelEvidence := {
    evidence with
      typeFacts := evidence.typeFacts.map fun fact =>
        if fact.modelPath.root == "count" then
          { fact with type := nestedSeqType maxStructuralTypeDepthV1 }
        else fact
  }
  let depthLimited := Core.ModelInterface.resolve (counterResolveInput deepEvidence)
  check fails "resource limits: structural depth rejected"
    (hasCompilerDiagnostic "MIC-R-LIMIT-001" "structuralTypeDepth" depthLimited)

  let valid := Core.ModelInterface.resolve (counterResolveInput evidence)
  match valid.value with
  | none => check fails "descriptor validation: prerequisite resolution" false
  | some resolved =>
      let malformed := {
        resolved.semanticDescriptor with
          initializers := resolved.initializers ++ resolved.initializers }
      check fails "descriptor validation: duplicate action rejected"
        (!semanticDescriptorWellFormedV1 malformed)

def verifyRequest (policy : NegotiationPolicy)
    (expected : String := "digest-good") : ModelInterfaceRequestV1 where
  request := .verify
  policy := policy
  acceptDescriptorSchemas := [descriptorSchemaV1]
  expectedSemanticDigest := some expected

def scenarioNegotiation (fails : Failures) : IO Unit := do
  let matchedFacts : NegotiationFacts := {
    resolvedSemanticDigest := some "digest-good"
  }
  let matched := verifyRequest .require
  check fails "negotiation: matched status"
    (selectNegotiationStatus matched matchedFacts == .matched)
  check fails "negotiation: matched interfaceOk"
    (interfaceOk (some matched) matchedFacts)

  let mismatchFacts : NegotiationFacts := {
    resolvedSemanticDigest := some "digest-other"
  }
  let mismatchDecision := decideNegotiation (some matched) mismatchFacts
  check fails "negotiation: require mismatch status"
    (mismatchDecision.status == some .mismatch)
  check fails "negotiation: require mismatch not ok"
    (!mismatchDecision.interfaceOk)
  check fails "negotiation: require mismatch register error"
    mismatchDecision.emitRegisterError

  let prefer := verifyRequest .prefer
  let unavailableFacts : NegotiationFacts := {
    resolvedSemanticDigest := none
  }
  let unavailableDecision := decideNegotiation (some prefer) unavailableFacts
  check fails "negotiation: prefer unavailable status"
    (unavailableDecision.status == some .unavailable)
  check fails "negotiation: prefer unavailable interfaceOk"
    unavailableDecision.interfaceOk
  check fails "negotiation: prefer unavailable no register error"
    (!unavailableDecision.emitRegisterError)

  let descriptorRequest : ModelInterfaceRequestV1 := {
    request := .descriptor
    policy := .require
    acceptDescriptorSchemas := [descriptorSchemaV1]
  }
  let descriptorDecision := decideNegotiation
    (some descriptorRequest) matchedFacts
  check fails "negotiation: descriptor resolved"
    (descriptorDecision.status == some .resolved)
  check fails "negotiation: descriptor included"
    descriptorDecision.includeDescriptor

def scenarioRuntimeNegotiationMatrix (fails : Failures) : IO Unit := do
  let evidence ← match Shell.ModelInterface.Evidence.fromString
      counterEvidenceJson "runtime-matrix-counter.itf.json" with
    | .ok evidence => pure evidence
    | .error error =>
        check fails "runtime matrix: evidence parses" false error
        return
  let descriptorRequest : Codec.ModelInterfaceDistributionJson.RequestV1 := {
    request := .descriptor
    policy := .require
    acceptDescriptorSchemas := [descriptorSchemaV1]
    contract := .inline counterContract
  }
  let descriptor := Shell.ModelInterface.Runtime.resolve
    (some descriptorRequest) (some evidence) (some "parameters")
  let some digest := descriptor.lock.map (·.semanticDigest)
    | check fails "runtime matrix: descriptor resolves" false
      return
  let notModifiedRequest : Codec.ModelInterfaceDistributionJson.RequestV1 := {
    descriptorRequest with ifNoneMatch := some digest }
  let notModified := Shell.ModelInterface.Runtime.resolve
    (some notModifiedRequest) (some evidence) (some "parameters")
  check fails "runtime matrix: ifNoneMatch is not_modified"
    (notModified.decision.status == some .notModified)
  check fails "runtime matrix: not_modified omits descriptor"
    (notModified.reply.bind (·.descriptor)).isNone

  let unsupportedRequest : Codec.ModelInterfaceDistributionJson.RequestV1 := {
    descriptorRequest with
      acceptDescriptorSchemas := ["mirrors.model-interface-descriptor/v2"] }
  let unsupported := Shell.ModelInterface.Runtime.resolve
    (some unsupportedRequest) (some evidence) (some "parameters")
  check fails "runtime matrix: unsupported required is terminal"
    (unsupported.decision.status == some .unsupported &&
      unsupported.decision.emitRegisterError)
  check fails "runtime matrix: unsupported avoids compiler artifact"
    unsupported.lock.isNone

  let preferUnsupported := Shell.ModelInterface.Runtime.resolve
    (some { unsupportedRequest with policy := .prefer })
    (some evidence) (some "parameters")
  check fails "runtime matrix: unsupported prefer reports and permits fallback"
    (preferUnsupported.decision.status == some .unsupported &&
      preferUnsupported.decision.interfaceOk && preferUnsupported.reply.isSome)

  let denied := Shell.ModelInterface.Runtime.resolve
    (some descriptorRequest) (some evidence) (some "parameters")
    (access := .disabled)
  check fails "runtime matrix: disabled access is unavailable"
    (denied.decision.status == some .unavailable &&
      denied.decision.emitRegisterError)
  let verifyOnly := Shell.ModelInterface.Runtime.resolve
    (some descriptorRequest) (some evidence) (some "parameters")
    (access := .verifyOnly)
  check fails "runtime matrix: descriptor requires read scope"
    (verifyOnly.decision.status == some .unavailable &&
      verifyOnly.decision.emitRegisterError)

  let preferPin : Codec.ModelInterfaceDistributionJson.RequestV1 := {
    request := .verify
    policy := .prefer
    acceptDescriptorSchemas := [descriptorSchemaV1]
    expectedSemanticDigest := some (String.ofList (List.replicate 64 '0'))
    contract := .inline counterContract
  }
  let mismatch := Shell.ModelInterface.Runtime.resolve
    (some preferPin) (some evidence) (some "parameters")
  check fails "runtime matrix: prefer never relaxes digest mismatch"
    (mismatch.decision.status == some .mismatch &&
      !mismatch.decision.interfaceOk && mismatch.decision.emitRegisterError)

def scenarioNegotiationCodec (fails : Failures) : IO Unit := do
  let request : Codec.ModelInterfaceDistributionJson.RequestV1 := {
    request := .descriptor
    policy := .require
    acceptDescriptorSchemas := [descriptorSchemaV1]
    contract := .inline counterContract
  }
  let encoded := Codec.ModelInterfaceDistributionJson.encodeRequest request
  match Codec.ModelInterfaceDistributionJson.decodeRequest encoded with
  | .error error => check fails "negotiation codec: request round trip" false error
  | .ok decoded =>
      check fails "negotiation codec: request round trip"
        (decoded.request == .descriptor && decoded.policy == .require &&
          decoded.expectedSemanticDigest.isNone)
  match encoded with
  | .obj fields =>
      let withNull := Lean.Json.mkObj
        (("expectedSemanticDigest", .null) :: fields.toList)
      match Codec.ModelInterfaceDistributionJson.decodeRequest withNull with
      | .error error =>
          check fails "negotiation codec: explicit null optional" false error
      | .ok decoded =>
          check fails "negotiation codec: explicit null optional"
            decoded.expectedSemanticDigest.isNone
      let withUnknown := Lean.Json.mkObj (("polciy", .str "require") :: fields.toList)
      check fails "negotiation codec: unknown strict field rejected"
        (!(Codec.ModelInterfaceDistributionJson.decodeRequest withUnknown).isOk)
  | _ => check fails "negotiation codec: encoded request is object" false
  check fails "negotiation codec: uppercase digest rejected"
    (!(Codec.ModelInterfaceDistributionJson.parseWireDigest "digest"
      ("sha256:" ++ String.ofList (List.replicate 64 'A'))).isOk)

def cacheKey (fingerprint : String) :
    Shell.ModelInterface.Cache.ScopedResolutionKey where
  securityRealm := "model-interface-spec"
  tenantId := some "tenant-a"
  fingerprint := fingerprint

def scenarioCache (fails : Failures) : IO Unit := do
  let cache ← Shell.ModelInterface.Cache.new 1 1024
  let firstBytes := "descriptor-one".toUTF8
  let firstDigest := Shell.ModelInterface.Cache.semanticDigest firstBytes
  let firstKey := cacheKey "first"
  match ← Shell.ModelInterface.Cache.put cache firstKey firstDigest firstBytes with
  | .error error => check fails "cache: first put" false error
  | .ok () => check fails "cache: first put" true
  match ← Shell.ModelInterface.Cache.lookup cache firstKey with
  | none => check fails "cache: first lookup" false "cache miss"
  | some entry =>
      check fails "cache: first bytes" (entry.bytes == firstBytes)
      check fails "cache: first digest" (entry.semanticDigest == firstDigest)

  let corruptBytes := "descriptor-corrupt".toUTF8
  match ← Shell.ModelInterface.Cache.put cache (cacheKey "corrupt")
      firstDigest corruptBytes with
  | .error _ => check fails "cache: rejects corrupt claimed digest" true
  | .ok () => check fails "cache: rejects corrupt claimed digest" false

  let secondBytes := "descriptor-two".toUTF8
  let secondDigest := Shell.ModelInterface.Cache.semanticDigest secondBytes
  let secondKey := cacheKey "second"
  match ← Shell.ModelInterface.Cache.put cache secondKey secondDigest secondBytes with
  | .error error => check fails "cache: second put" false error
  | .ok () => check fails "cache: second put" true
  check fails "cache: max-entry count"
    ((← Shell.ModelInterface.Cache.entryCount cache) == 1)
  check fails "cache: oldest evicted"
    ((← Shell.ModelInterface.Cache.lookup cache firstKey).isNone)
  check fails "cache: newest retained"
    ((← Shell.ModelInterface.Cache.lookup cache secondKey).isSome)

  let scopedCache ← Shell.ModelInterface.Cache.new 10 4096 1 4096
  let realmAFirst := cacheKey "realm-a-first"
  let realmASecond := cacheKey "realm-a-second"
  let realmB : Shell.ModelInterface.Cache.ScopedResolutionKey := {
    securityRealm := "other-realm"
    tenantId := some "tenant-b"
    fingerprint := "realm-b-first"
  }
  let _ ← Shell.ModelInterface.Cache.put scopedCache realmAFirst firstDigest firstBytes
  let _ ← Shell.ModelInterface.Cache.put scopedCache realmB secondDigest secondBytes
  let _ ← Shell.ModelInterface.Cache.put scopedCache realmASecond secondDigest secondBytes
  check fails "cache: per-scope quota evicts only same scope"
    ((← Shell.ModelInterface.Cache.lookup scopedCache realmAFirst).isNone &&
      (← Shell.ModelInterface.Cache.lookup scopedCache realmASecond).isSome &&
      (← Shell.ModelInterface.Cache.lookup scopedCache realmB).isSome)

def runtimeDescriptorRequest :
    Codec.ModelInterfaceDistributionJson.RequestV1 where
  request := .descriptor
  policy := .require
  acceptDescriptorSchemas := [descriptorSchemaV1]
  contract := .inline counterContract

def scenarioRuntimeCache (fails : Failures) : IO Unit := do
  let evidence ← match Shell.ModelInterface.Evidence.fromString
      counterEvidenceJson "runtime-cache-counter.itf.json" with
    | .ok evidence => pure evidence
    | .error error =>
        check fails "runtime cache: evidence parses" false error
        return
  let service ← Shell.ModelInterface.Runtime.Service.new 8 (1024 * 1024) 1
  let scopeA : Shell.ModelInterface.Runtime.AuthorizationScope := {
    securityRealm := "realm-a"
    principalId := some "principal-a"
    tenantId := some "tenant-a"
  }
  let first ← Shell.ModelInterface.Runtime.resolveCached service scopeA
    (some runtimeDescriptorRequest) (some evidence) (some "parameters")
    (compilerVersion := "model-interface-spec")
  check fails "runtime cache: first call is miss" (!first.cacheHit)
  check fails "runtime cache: first resolves"
    (first.resolution.decision.status == some .resolved)
    (toString (repr first.resolution.diagnostics))
  let second ← Shell.ModelInterface.Runtime.resolveCached service scopeA
    (some runtimeDescriptorRequest) (some evidence) (some "parameters")
    (compilerVersion := "model-interface-spec")
  check fails "runtime cache: second call is hit" second.cacheHit
  check fails "runtime cache: same scoped key" (first.key == second.key)
  check fails "runtime cache: hit preserves semantic identity"
    (first.resolution.lock.bind (fun lock => some lock.semanticDigest) ==
      second.resolution.lock.bind (fun lock => some lock.semanticDigest))
  check fails "runtime cache: one entry after hit"
    ((← Shell.ModelInterface.Cache.entryCount service.cache) == 1)

  let scopeB : Shell.ModelInterface.Runtime.AuthorizationScope := {
    securityRealm := "realm-a"
    principalId := some "principal-a"
    tenantId := some "tenant-b"
  }
  let third ← Shell.ModelInterface.Runtime.resolveCached service scopeB
    (some runtimeDescriptorRequest) (some evidence) (some "parameters")
    (compilerVersion := "model-interface-spec")
  check fails "runtime cache: other tenant is miss" (!third.cacheHit)
  check fails "runtime cache: tenant changes key" (!(first.key == third.key))
  check fails "runtime cache: scoped entries stay separate"
    ((← Shell.ModelInterface.Cache.entryCount service.cache) == 2)

  let scopeC : Shell.ModelInterface.Runtime.AuthorizationScope := {
    securityRealm := "realm-a"
    principalId := some "principal-b"
    tenantId := some "tenant-a"
  }
  let fourth ← Shell.ModelInterface.Runtime.resolveCached service scopeC
    (some runtimeDescriptorRequest) (some evidence) (some "parameters")
    (compilerVersion := "model-interface-spec")
  check fails "runtime cache: other principal is miss" (!fourth.cacheHit)
  check fails "runtime cache: principal changes key" (!(first.key == fourth.key))
  check fails "runtime cache: principal-scoped entries stay separate"
    ((← Shell.ModelInterface.Cache.entryCount service.cache) == 3)

  let fingerprint := Shell.ModelInterface.Runtime.resolutionFingerprint
    counterContract evidence (some "parameters") []
  let fingerprintAgain := Shell.ModelInterface.Runtime.resolutionFingerprint
    counterContract evidence (some "parameters") []
  let otherProfile := Shell.ModelInterface.Runtime.resolutionFingerprint
    counterContract evidence none []
  let changedEvidence : ModelEvidence := {
    evidence with
      typeFacts := evidence.typeFacts.map fun fact =>
        if fact.modelPath.root == "count" then { fact with type := .bool }
        else fact
  }
  let otherEvidence := Shell.ModelInterface.Runtime.resolutionFingerprint
    counterContract changedEvidence (some "parameters") []
  check fails "runtime cache: fingerprint deterministic"
    (fingerprint == fingerprintAgain)
  check fails "runtime cache: run profile changes fingerprint"
    (fingerprint != otherProfile)
  check fails "runtime cache: normalized evidence changes fingerprint"
    (fingerprint != otherEvidence)

  let beforeNegative ← Shell.ModelInterface.Runtime.resolutionRunCount service
  let invalidFirst ← Shell.ModelInterface.Runtime.resolveCached service scopeA
    (some runtimeDescriptorRequest) (some evidence) none
    (compilerVersion := "model-interface-spec")
  let invalidSecond ← Shell.ModelInterface.Runtime.resolveCached service scopeA
    (some runtimeDescriptorRequest) (some evidence) none
    (compilerVersion := "model-interface-spec")
  let afterNegative ← Shell.ModelInterface.Runtime.resolutionRunCount service
  check fails "runtime cache: invalid input resolves unavailable"
    (invalidFirst.resolution.decision.status == some .unavailable &&
      invalidSecond.resolution.decision.status == some .unavailable)
  check fails "runtime cache: negative result avoids repeated resolution"
    (afterNegative == beforeNegative + 1)

  let expiringService ← Shell.ModelInterface.Runtime.Service.new
    8 (1024 * 1024) 1 4 4 8 8 1
  let _ ← Shell.ModelInterface.Runtime.resolveCached expiringService scopeA
    (some runtimeDescriptorRequest) (some evidence) none
    (compilerVersion := "model-interface-spec")
  IO.sleep 2
  let _ ← Shell.ModelInterface.Runtime.resolveCached expiringService scopeA
    (some runtimeDescriptorRequest) (some evidence) none
    (compilerVersion := "model-interface-spec")
  check fails "runtime cache: negative result expires"
    ((← Shell.ModelInterface.Runtime.resolutionRunCount expiringService) == 2)

  let flightService ← Shell.ModelInterface.Runtime.Service.new
    8 (1024 * 1024) 4 32 16
  let mut flightTasks := []
  for _ in List.range 16 do
    let task ← IO.asTask (prio := Task.Priority.dedicated)
      (Shell.ModelInterface.Runtime.resolveCached flightService scopeA
        (some runtimeDescriptorRequest) (some evidence) (some "parameters")
        (compilerVersion := "model-interface-spec"))
    flightTasks := task :: flightTasks
  let mut flightOk := true
  for task in flightTasks do
    match task.get with
    | .ok result =>
        if result.resolution.decision.status != some .resolved then
          flightOk := false
    | .error _ => flightOk := false
  check fails "runtime cache: concurrent callers resolve" flightOk
  check fails "runtime cache: identical misses are single-flight"
    ((← Shell.ModelInterface.Runtime.resolutionRunCount flightService) == 1)

def counterTrace : ItfTrace where
  traceVars := ["action_taken", "count", "parameters"]
  paramVars := ["parameters"]
  traceParams := []
  traceStates := [
    { actionTaken := "init"
      parameters := [("parameters", .vrecord [("stride", .vint 0)])]
      stateVars := [("count", .vint 0)] },
    { actionTaken := "tick"
      parameters := [("parameters", .vrecord [("stride", .vint 2)])]
      stateVars := [("count", .vint 2)] }
  ]

def transitionAtZeroTrace : ItfTrace :=
  { counterTrace with traceStates :=
      { actionTaken := "tick"
        parameters := [("parameters", .vrecord [("stride", .vint 0)])]
        stateVars := [("count", .vint 0)] } :: counterTrace.traceStates.tail }

def wrongObservationTrace : ItfTrace :=
  { counterTrace with traceStates :=
      counterTrace.traceStates.take 1 ++ [
        { actionTaken := "tick"
          parameters := [("parameters", .vrecord [("stride", .vint 2)])]
          stateVars := [("count", .vstr "two")] }] }

def wrongInputTrace : ItfTrace :=
  { counterTrace with traceStates :=
      counterTrace.traceStates.take 1 ++ [
        { actionTaken := "tick"
          parameters := [("parameters", .vrecord [("stride", .vstr "two")])]
          stateVars := [("count", .vint 2)] }] }

def hasDiagnosticCode (code : String) (result : PreflightResult) : Bool :=
  result.diagnostics.any (fun diagnostic => diagnostic.code == code)

def hasDiagnosticReason (reason : String) (result : PreflightResult) : Bool :=
  result.diagnostics.any (fun diagnostic =>
    diagnostic.arguments.any (fun argument =>
      argument.1 == "reason" && argument.2 == reason))

def scenarioPreflight (fails : Failures) (resolved : ResolvedModelInterface) : IO Unit := do
  let lock := resolved.withDigests
    (String.ofList (List.replicate 64 '0'))
    (String.ofList (List.replicate 64 '1'))
  let valid := preflight lock [counterTrace] { requireAllActions := true }
  check fails "preflight: valid Counter has no errors" (!valid.hasErrors)
    (toString (repr valid.diagnostics))
  check fails "preflight: valid Counter covers all actions"
    valid.coverage.unseenActions.isEmpty
  check fails "preflight: valid Counter state count" (valid.coverage.states == 2)

  let badPhase := preflight lock [transitionAtZeroTrace]
  check fails "preflight: transition at zero fails" badPhase.hasErrors
  check fails "preflight: transition at zero reason"
    (hasDiagnosticReason "transition action appears at state zero" badPhase)

  let badObservation := preflight lock [wrongObservationTrace]
  check fails "preflight: wrong observation fails" badObservation.hasErrors
  check fails "preflight: wrong observation value diagnostic"
    (hasDiagnosticCode "MIC-P-VALUE-001" badObservation)

  let badInput := preflight lock [wrongInputTrace]
  check fails "preflight: wrong input fails" badInput.hasErrors
  check fails "preflight: wrong input value diagnostic"
    (hasDiagnosticCode "MIC-P-VALUE-001" badInput)
  let actualDiagnosticBytes :=
    Codec.ModelInterfaceJson.canonicalFileBytes
      (Codec.ModelInterfaceJson.encodeDiagnostics badInput.diagnostics)
  let expectedDiagnosticBytes ← IO.FS.readBinFile
    "test/fixtures/model-interface/counter/Counter.wrong-input.diagnostics.json"
  check fails "preflight: wrong input diagnostic exact golden bytes"
    (actualDiagnosticBytes == expectedDiagnosticBytes)
    (s!"actual={String.fromUTF8? actualDiagnosticBytes}, " ++
      s!"expected={String.fromUTF8? expectedDiagnosticBytes}")

def scenarioCliDiagnostics (fails : Failures) : IO Unit := do
  let baseArgs := #[
    "preflight",
    "--lock", "test/fixtures/model-interface/counter/Counter.mirror-interface.lock.json",
    "--trace", "test/fixtures/model-interface/counter/Counter.wrong-input.itf.json",
    "--require-all-actions"
  ]
  let jsonOutput ← IO.Process.output {
    cmd := ".lake/build/bin/model_interface_gen"
    args := baseArgs ++ #["--diagnostics", "json"]
  }
  let expectedDiagnostics ← IO.FS.readBinFile
    "test/fixtures/model-interface/counter/Counter.wrong-input.diagnostics.json"
  check fails "cli diagnostics json: finding exit code"
    (jsonOutput.exitCode == 1) (toString jsonOutput.exitCode)
  let expectedCoverage ← IO.FS.readBinFile
    "test/fixtures/model-interface/counter/Counter.wrong-input.coverage.json"
  check fails "cli diagnostics json: coverage remains exact stdout bytes"
    (jsonOutput.stdout.toUTF8 == expectedCoverage)
    (s!"actual={jsonOutput.stdout}")
  check fails "cli diagnostics json: exact diagnostics remain stderr"
    (jsonOutput.stderr.toUTF8 == expectedDiagnostics)
    (s!"actual={jsonOutput.stderr}")

  let validJsonOutput ← IO.Process.output {
    cmd := ".lake/build/bin/model_interface_gen"
    args := #[
      "preflight",
      "--lock", "test/fixtures/model-interface/counter/Counter.mirror-interface.lock.json",
      "--trace", "test/fixtures/model-interface/counter/counter.itf.json",
      "--require-all-actions",
      "--diagnostics", "json"
    ]
  }
  check fails "cli diagnostics json: success exit code preserved"
    (validJsonOutput.exitCode == 0) (toString validJsonOutput.exitCode)
  let expectedValidCoverage ← IO.FS.readBinFile
    "test/fixtures/model-interface/counter/Counter.mirror-interface.coverage.json"
  check fails "cli diagnostics json: success keeps exact coverage on stdout"
    (validJsonOutput.stdout.toUTF8 == expectedValidCoverage)
    (s!"stdout={validJsonOutput.stdout}, stderr={validJsonOutput.stderr}")
  check fails "cli diagnostics json: success emits empty diagnostics on stderr"
    (validJsonOutput.stderr == "[]\n") validJsonOutput.stderr

  let humanOutput ← IO.Process.output {
    cmd := ".lake/build/bin/model_interface_gen"
    args := baseArgs
  }
  check fails "cli diagnostics human: finding exit code"
    (humanOutput.exitCode == 1) (toString humanOutput.exitCode)
  check fails "cli diagnostics human: coverage remains stdout"
    (humanOutput.stdout.toUTF8 == expectedCoverage)
    (s!"actual={humanOutput.stdout}")
  check fails "cli diagnostics human: diagnostic remains stderr"
    (humanOutput.stderr.contains "error MIC-P-VALUE-001") humanOutput.stderr

  let emptyDiagnostics := "[]\n".toUTF8
  let temporaryRoot ← IO.FS.createTempDir
  try
    let resolvedLock := temporaryRoot / "Counter.mirror-interface.lock.json"
    let resolveSuccess ← IO.Process.output {
      cmd := ".lake/build/bin/model_interface_gen"
      args := #[
        "resolve",
        "--spec", "specs/Counter.tla",
        "--contract",
          "test/fixtures/model-interface/counter/Counter.mirror-interface.json",
        "--evidence", "test/fixtures/model-interface/counter/counter.itf.json",
        "--param-var", "parameters",
        "--lock", resolvedLock.toString,
        "--diagnostics", "json"
      ]
    }
    check fails "cli diagnostics json: resolve success exit code"
      (resolveSuccess.exitCode == 0) (toString resolveSuccess.exitCode)
    let resolvedRaw ← IO.FS.readBinFile resolvedLock
    match Codec.ModelInterfaceJson.parseLockBytes resolvedRaw with
    | .error error =>
        check fails "cli diagnostics json: resolve success lock parses" false error
    | .ok lock =>
        check fails "cli diagnostics json: resolve summary remains exact stdout"
          (resolveSuccess.stdout ==
            s!"resolved {resolvedLock.toString} {lock.semanticDigest}\n")
          resolveSuccess.stdout
    check fails "cli diagnostics json: resolve success diagnostics remain stderr"
      (resolveSuccess.stderr.toUTF8 == emptyDiagnostics) resolveSuccess.stderr

    let resolveOutput ← IO.Process.output {
      cmd := ".lake/build/bin/model_interface_gen"
      args := #[
        "resolve",
        "--spec", "specs/Counter.tla",
        "--contract", "test/fixtures/model-interface/counter/counter.itf.json",
        "--evidence", "test/fixtures/model-interface/counter/counter.itf.json",
        "--param-var", "parameters",
        "--lock", (temporaryRoot / "unused.lock.json").toString,
        "--diagnostics", "json"
      ]
    }
    check fails "cli diagnostics json: resolve finding exit code"
      (resolveOutput.exitCode == 1) (toString resolveOutput.exitCode)
    check fails "cli diagnostics json: resolve finding is structured"
      (resolveOutput.stdout.isEmpty &&
        resolveOutput.stderr.contains "\"code\":\"MIC-C-CONTRACT-001\"" &&
        !resolveOutput.stderr.contains "test/fixtures")
      (s!"stdout={resolveOutput.stdout}, stderr={resolveOutput.stderr}")

    let generateOutput ← IO.Process.output {
      cmd := ".lake/build/bin/model_interface_gen"
      args := #[
        "generate",
        "--lock", "test/fixtures/model-interface/counter/counter.itf.json",
        "--target", "mirrorecma-v1",
        "--out", temporaryRoot.toString,
        "--diagnostics", "json"
      ]
    }
    check fails "cli diagnostics json: generate finding exit code"
      (generateOutput.exitCode == 1) (toString generateOutput.exitCode)
    check fails "cli diagnostics json: generate finding is structured"
      (generateOutput.stdout.isEmpty &&
        generateOutput.stderr.contains "\"code\":\"MIC-C-LOCK-001\"" &&
        !generateOutput.stderr.contains "test/fixtures")
      (s!"stdout={generateOutput.stdout}, stderr={generateOutput.stderr}")

    let staleOutput := temporaryRoot / "stale-output"
    IO.FS.createDir staleOutput
    let checkOutput ← IO.Process.output {
      cmd := ".lake/build/bin/model_interface_gen"
      args := #[
        "check",
        "--spec", "specs/Counter.tla",
        "--contract",
          "test/fixtures/model-interface/counter/Counter.mirror-interface.json",
        "--evidence", "test/fixtures/model-interface/counter/counter.itf.json",
        "--param-var", "parameters",
        "--lock",
          resolvedLock.toString,
        "--target", "mirrorecma-v1",
        "--out", staleOutput.toString,
        "--diagnostics", "json"
      ]
    }
    check fails "cli diagnostics json: stale check exit code"
      (checkOutput.exitCode == 1) (toString checkOutput.exitCode)
    let expectedStaleSummary :=
      s!"stale: {(staleOutput / ".model-interface-generated.json").toString}\n" ++
      s!"stale: {(staleOutput / "CounterMirror.generated.ts").toString}\n"
    check fails "cli diagnostics json: stale summary remains exact stdout"
      (checkOutput.stdout == expectedStaleSummary)
      (s!"stdout={checkOutput.stdout}, stderr={checkOutput.stderr}")
    check fails "cli diagnostics json: stale check diagnostics remain stderr"
      (checkOutput.stderr.contains "\"code\":\"MIC-C-STALE-001\"")
      checkOutput.stderr

    let generatedOutput := temporaryRoot / "generated-output"
    let generateSuccess ← IO.Process.output {
      cmd := ".lake/build/bin/model_interface_gen"
      args := #[
        "generate",
        "--lock",
          resolvedLock.toString,
        "--target", "mirrorecma-v1",
        "--out", generatedOutput.toString,
        "--diagnostics", "json"
      ]
    }
    check fails "cli diagnostics json: generate success exit code"
      (generateSuccess.exitCode == 0) (toString generateSuccess.exitCode)
    check fails "cli diagnostics json: generate summary remains exact stdout"
      (generateSuccess.stdout ==
        s!"generated 2 files in {generatedOutput.toString}\n")
      generateSuccess.stdout
    check fails "cli diagnostics json: generate success diagnostics remain stderr"
      (generateSuccess.stderr.toUTF8 == emptyDiagnostics) generateSuccess.stderr
  finally
    IO.FS.removeDirAll temporaryRoot

private def emitterErrorIs (code : String)
    (result : Shell.ModelInterface.Emit.TypeScript.EmitResult α) : Bool :=
  match result with
  | .error diagnostics => diagnostics.any (·.code == code)
  | .ok _ => false

private def emittedSource?
    (result : Shell.ModelInterface.Emit.TypeScript.EmitResult
      Shell.ModelInterface.Emit.TypeScript.GeneratedTree) : Option String := do
  let tree ← result.toOption
  let sourceFile ← tree.files.find? (fun file =>
    file.relativePath.endsWith "Mirror.generated.ts")
  String.fromUTF8? sourceFile.bytes

def scenarioEmitter (fails : Failures)
    (resolved : ResolvedModelInterface) : IO Unit := do
  let semantic := Core.ModelInterface.Sha256.digestDomainHex
    "mirrors-model-interface-lock/v1" (resolvedSemanticBytes resolved)
  let provenance := Core.ModelInterface.Sha256.digestDomainHex
    "mirrors-model-interface-provenance/v1" "counter-provenance".toUTF8
  let lock := resolved.withDigests semantic provenance
  let first := Shell.ModelInterface.Emit.TypeScript.emitTypeScript lock
  let second := Shell.ModelInterface.Emit.TypeScript.emitTypeScript lock
  let deterministic := match first, second with
    | .ok a, .ok b => a == b
    | .error a, .error b => a == b
    | _, _ => false
  check fails "emitter: deterministic result" deterministic
  match first with
  | .error diagnostics =>
      check fails "emitter: Counter succeeds" false
        (toString (repr diagnostics))
  | .ok tree =>
      check fails "emitter: two owned files" (tree.files.length == 2)
        (toString tree.files.length)
      check fails "emitter: sorted paths"
        (tree.files.map (·.relativePath) ==
          [".model-interface-generated.json", "CounterMirror.generated.ts"])
        (toString (repr (tree.files.map (·.relativePath))))
      let source? := tree.files.find? (fun file =>
        file.relativePath == "CounterMirror.generated.ts")
      let some sourceFile := source?
        | check fails "emitter: source exists" false
          return
      let some source := String.fromUTF8? sourceFile.bytes
        | check fails "emitter: UTF-8" false
          return
      check fails "emitter: final LF" (source.endsWith "\n")
      check fails "emitter: no CR" (!source.contains '\r')
      check fails "emitter: Tick input"
        (source.contains "export interface TickInput")
      check fails "emitter: observation"
        (source.contains "export interface CounterObservation")
      check fails "emitter: port"
        (source.contains "export interface CounterPort")
      check fails "emitter: StateComputer"
        (source.contains "readonly computer: StateComputer")
      check fails "emitter: config check"
        (source.contains "expected paramVars=")
      check fails "emitter: lifecycle"
        (source.contains "\"fresh\" | \"initialized\" | \"poisoned\"")
      check fails "emitter: coverage"
        (source.contains "assertAllActionsCovered")
      check fails "emitter: semantic digest"
        (source.contains semantic)

  let some transition := lock.actions.head?
    | check fails "emitter names: transition prerequisite" false
      return
  let observeLock := { lock with actions := [
    { transition with id := "Observe", wireAction := "observe-action" }
  ] }
  check fails "emitter names: action cannot collide with mandatory observe"
    (emitterErrorIs "MIC-E-NAME-001"
      (Shell.ModelInterface.Emit.TypeScript.emitTypeScript observeLock))

  let escapedActionLock := { lock with actions := [
    { transition with id := "Class", wireAction := "class-action" },
    { transition with id := "Class_", wireAction := "class-underscore-action" }
  ] }
  check fails "emitter names: escaped action collision rejected"
    (emitterErrorIs "MIC-E-NAME-001"
      (Shell.ModelInterface.Emit.TypeScript.emitTypeScript escapedActionLock))

  let some input := transition.inputs.head?
    | check fails "emitter names: input prerequisite" false
      return
  let inputCollisionLock := { lock with actions := [
    { transition with inputs := [
      { input with id := "Class" }, { input with id := "Class_" }
    ] }
  ] }
  check fails "emitter names: escaped input collision rejected"
    (emitterErrorIs "MIC-E-NAME-001"
      (Shell.ModelInterface.Emit.TypeScript.emitTypeScript inputCollisionLock))

  let some observation := lock.observations.head?
    | check fails "emitter names: observation prerequisite" false
      return
  let observationCollisionLock := { lock with observations := [
    { observation with id := "Class" },
    { observation with id := "Class_", wireName := "other" }
  ] }
  check fails "emitter names: escaped observation collision rejected"
    (emitterErrorIs "MIC-E-NAME-001"
      (Shell.ModelInterface.Emit.TypeScript.emitTypeScript
        observationCollisionLock))

  let maxSafe : Nat := 9007199254740991
  let atBoundLock := { lock with actions := [
    { transition with inputs := [
      { input with projection :=
        { input.projection with path := [.index maxSafe] } }
    ] }
  ] }
  let atBoundSource := emittedSource?
    (Shell.ModelInterface.Emit.TypeScript.emitTypeScript atBoundLock)
  check fails "emitter path: Number.MAX_SAFE_INTEGER accepted"
    (atBoundSource.any (·.contains "index: 9007199254740991"))
  let overflowLock := { lock with actions := [
    { transition with inputs := [
      { input with projection :=
        { input.projection with path := [.index (maxSafe + 1)] } }
    ] }
  ] }
  check fails "emitter path: Number.MAX_SAFE_INTEGER overflow rejected"
    (emitterErrorIs "MIC-E-PATH-001"
      (Shell.ModelInterface.Emit.TypeScript.emitTypeScript overflowLock))

private def compilerRejected {α : Type}
    (result : Except Shell.ModelInterface.Compiler.CompilerError α) : Bool :=
  match result with
  | .error _ => true
  | .ok _ => false

def scenarioSemanticIdentityAndLargeLock (fails : Failures)
    (resolved : ResolvedModelInterface) : IO Unit := do
  let descriptor := resolved.semanticDescriptor
  let changedOrigins : SemanticDescriptor := {
    descriptor with
      initializers := descriptor.initializers.map fun action =>
        { action with inputs := action.inputs.map fun input =>
          { input with typeOrigins := [.contractAssertion] } }
      actions := descriptor.actions.map fun action =>
        { action with inputs := action.inputs.map fun input =>
          { input with typeOrigins := [.contractAssertion] } }
      observations := descriptor.observations.map fun observation =>
        { observation with typeOrigins := [.apalacheTypecheck] }
  }
  let semanticBytes :=
    Codec.ModelInterfaceJson.canonicalSemanticDescriptorBytes descriptor
  let changedSemanticBytes :=
    Codec.ModelInterfaceJson.canonicalSemanticDescriptorBytes changedOrigins
  check fails "semantic identity: type origins do not change canonical bytes"
    (semanticBytes == changedSemanticBytes)
  let wireBytes := Codec.ModelInterfaceJson.canonicalBytes
    (Codec.ModelInterfaceJson.encodeSemanticDescriptor descriptor)
  let changedWireBytes := Codec.ModelInterfaceJson.canonicalBytes
    (Codec.ModelInterfaceJson.encodeSemanticDescriptor changedOrigins)
  check fails "semantic identity: wire descriptor is the identity projection"
    (wireBytes == changedWireBytes && wireBytes == semanticBytes)
  let digest := Core.ModelInterface.Sha256.digestDomainHex
    descriptorDigestDomainV1 semanticBytes
  let changedDigest := Core.ModelInterface.Sha256.digestDomainHex
    descriptorDigestDomainV1 changedSemanticBytes
  check fails "semantic identity: type origins do not change digest"
    (digest == changedDigest)
  let lockWithOrigins : LockedModelInterface := {
    toSemanticDescriptor := descriptor
    semanticDigest := digest
    provenanceDigest := String.ofList (List.replicate 64 '0')
    provenance := resolved.provenance
  }
  let lockWithChangedOrigins : LockedModelInterface := {
    lockWithOrigins with toSemanticDescriptor := changedOrigins }
  let encodedLockWithOrigins := Codec.ModelInterfaceJson.canonicalBytes
    (Codec.ModelInterfaceJson.encodeLock lockWithOrigins)
  let encodedLockWithChangedOrigins := Codec.ModelInterfaceJson.canonicalBytes
    (Codec.ModelInterfaceJson.encodeLock lockWithChangedOrigins)
  check fails "semantic identity: checked-in lock excludes unauthenticated origins"
    (encodedLockWithOrigins == encodedLockWithChangedOrigins)
  match Codec.ModelInterfaceJson.parseLockBytes encodedLockWithOrigins with
  | .error error =>
      check fails "semantic identity: origin-free lock decodes" false error
  | .ok decoded =>
      check fails "semantic identity: decoded lock has no origin annotations"
        (decoded.initializers.all (fun action =>
            action.inputs.all (·.typeOrigins.isEmpty)) &&
          decoded.actions.all (fun action =>
            action.inputs.all (·.typeOrigins.isEmpty)) &&
          decoded.observations.all (·.typeOrigins.isEmpty))

  let sourceDigest : String := String.ofList (List.replicate 64 'a')
  let manySources := (List.range 1000).map fun index => ({
    moduleName := s!"Dependency{index}"
    logicalPath := s!"dependencies/Dependency{index}.tla"
    contentSha256 := sourceDigest
  } : SourceDigest)
  let largeProvenance := { resolved.provenance with sources := manySources }
  let provenanceBytes := Codec.ModelInterfaceJson.canonicalProvenanceBytes
    largeProvenance
  let provenanceDigest := Core.ModelInterface.Sha256.digestDomainHex
    Shell.ModelInterface.Compiler.provenanceDigestDomain provenanceBytes
  let largeLock : LockedModelInterface := {
    toSemanticDescriptor := descriptor
    semanticDigest := digest
    provenanceDigest := provenanceDigest
    provenance := largeProvenance
  }
  let largeLockBytes := Codec.ModelInterfaceJson.canonicalFileBytes
    (Codec.ModelInterfaceJson.encodeLock largeLock)
  check fails "compiler artifact limit: valid lock exceeds JSONL profile"
    (largeLockBytes.size > Codec.StrictJson.defaultLimits.maxBytes)
    (toString largeLockBytes.size)
  check fails "compiler artifact limit: valid lock remains below compiler profile"
    (largeLockBytes.size <
      Shell.ModelInterface.Compiler.maxCompilerArtifactBytes)
    (toString largeLockBytes.size)

  let temporaryRoot ← IO.FS.createTempDir
  try
    let lockPath := temporaryRoot / "large.lock.json"
    IO.FS.writeBinFile lockPath largeLockBytes
    match ← Shell.ModelInterface.Compiler.loadVerifiedLock lockPath.toString with
    | .error error =>
        check fails "compiler artifact limit: large lock loads" false error.message
    | .ok loaded =>
        let roundtrip := Codec.ModelInterfaceJson.canonicalFileBytes
          (Codec.ModelInterfaceJson.encodeLock loaded)
        check fails "compiler artifact limit: large lock roundtrips"
          (roundtrip == largeLockBytes)

    let replacementProvenance := {
      resolved.provenance with compilerVersion := "replacement" }
    let replacementProvenanceBytes :=
      Codec.ModelInterfaceJson.canonicalProvenanceBytes replacementProvenance
    let replacementLock := resolved.withDigests digest
      (Core.ModelInterface.Sha256.digestDomainHex
        Shell.ModelInterface.Compiler.provenanceDigestDomain
        replacementProvenanceBytes)
    let replacementLock : LockedModelInterface := {
      replacementLock with provenance := replacementProvenance }
    let replacementBytes := Codec.ModelInterfaceJson.canonicalFileBytes
      (Codec.ModelInterfaceJson.encodeLock replacementLock)
    let compilation : Shell.ModelInterface.Compiler.Compilation := {
      resolved := resolved
      lock := replacementLock
      descriptorBytes := semanticBytes
      provenanceBytes := replacementProvenanceBytes
      lockBytes := replacementBytes
      diagnostics := []
    }
    match ← Shell.ModelInterface.Compiler.writeLock lockPath.toString compilation with
    | .error error =>
        check fails "compiler artifact limit: large prior lock is replaceable"
          false error.message
    | .ok () =>
        check fails "compiler artifact limit: replacement bytes published"
          ((← IO.FS.readBinFile lockPath) == replacementBytes)
  finally
    IO.FS.removeDirAll temporaryRoot

private def makeSymlink (target link : System.FilePath) : IO (Except String Unit) := do
  let output ← IO.Process.output {
    cmd := "ln"
    args := #["-s", "--", target.toString, link.toString]
  }
  if output.exitCode == 0 then return .ok ()
  return .error output.stderr

private partial def injectUnownedWhenStaged (directory target : System.FilePath)
    (remaining : Nat) : IO Bool := do
  if remaining == 0 then return false
  try
    if ← directory.pathExists then
      let entries ← directory.readDir
      if entries.any (fun entry =>
          entry.fileName.contains ".model-interface-tmp-") then
        let handle ← IO.FS.Handle.mk target .writeNew
        handle.write "CONCURRENT-UNOWNED".toUTF8
        handle.flush
        return true
  catch _ => pure ()
  IO.sleep 1
  injectUnownedWhenStaged directory target (remaining - 1)

def scenarioFilesystemHardening (fails : Failures)
    (resolved : ResolvedModelInterface) : IO Unit := do
  let semantic := Core.ModelInterface.Sha256.digestDomainHex
    "mirrors-model-interface-lock/v1" (resolvedSemanticBytes resolved)
  let provenance := Core.ModelInterface.Sha256.digestDomainHex
    "mirrors-model-interface-provenance/v1" "filesystem-hardening".toUTF8
  let lock := resolved.withDigests semantic provenance
  let tree ← match Shell.ModelInterface.Emit.TypeScript.emitTypeScript lock with
    | .ok tree => pure tree
    | .error diagnostics =>
        check fails "filesystem hardening: Counter emits" false
          (toString (repr diagnostics))
        return
  let temporaryRoot ← IO.FS.createTempDir
  try
    let outsideRoot := temporaryRoot / "outside-root"
    IO.FS.createDir outsideRoot
    let rootSentinel := outsideRoot / "sentinel.txt"
    IO.FS.writeFile rootSentinel "ROOT-SENTINEL"

    if System.Platform.isWindows then
      check fails "filesystem hardening: symlink cases skipped on Windows" true
    else
      let linkedRoot := temporaryRoot / "linked-root"
      match ← makeSymlink outsideRoot linkedRoot with
      | .error error =>
          check fails "filesystem hardening: create root symlink" false error
      | .ok () =>
          let result ← Shell.ModelInterface.Compiler.writeGeneratedTree
            linkedRoot.toString tree
          check fails "filesystem hardening: symlinked root rejected"
            (compilerRejected result)
          check fails "filesystem hardening: symlink root stayed contained"
            ((← IO.FS.readFile rootSentinel) == "ROOT-SENTINEL" &&
              !(← (outsideRoot / "CounterMirror.generated.ts").pathExists))

      let targetOut := temporaryRoot / "target-out"
      IO.FS.createDir targetOut
      let outsideTarget := temporaryRoot / "outside-target.txt"
      IO.FS.writeFile outsideTarget "TARGET-SENTINEL"
      match ← makeSymlink outsideTarget (targetOut / "CounterMirror.generated.ts") with
      | .error error =>
          check fails "filesystem hardening: create target symlink" false error
      | .ok () =>
          let result ← Shell.ModelInterface.Compiler.writeGeneratedTree
            targetOut.toString tree
          check fails "filesystem hardening: symlinked target rejected"
            (compilerRejected result)
          check fails "filesystem hardening: symlink target stayed contained"
            ((← IO.FS.readFile outsideTarget) == "TARGET-SENTINEL" &&
              !(← (targetOut /
                Shell.ModelInterface.Compiler.generatedManifestPath).pathExists))

      let componentOut := temporaryRoot / "component-out"
      let componentOutside := temporaryRoot / "component-outside"
      IO.FS.createDir componentOut
      IO.FS.createDir componentOutside
      match ← makeSymlink componentOutside (componentOut / "nested") with
      | .error error =>
          check fails "filesystem hardening: create component symlink" false error
      | .ok () =>
          let nestedTree : Shell.ModelInterface.Emit.TypeScript.GeneratedTree := {
            files := tree.files.map fun file =>
              if file.relativePath == "CounterMirror.generated.ts" then
                { file with relativePath := "nested/CounterMirror.generated.ts" }
              else file
          }
          let result ← Shell.ModelInterface.Compiler.writeGeneratedTree
            componentOut.toString nestedTree
          check fails "filesystem hardening: symlinked component rejected"
            (compilerRejected result)
          check fails "filesystem hardening: component escape absent"
            (!(← (componentOutside / "CounterMirror.generated.ts").pathExists))

      let cleanupOut := temporaryRoot / "cleanup-out"
      let firstPublication ← Shell.ModelInterface.Compiler.writeGeneratedTree
        cleanupOut.toString tree
      match firstPublication with
      | .error error =>
          check fails "filesystem hardening: cleanup prerequisite publication" false
            error.message
      | .ok _ =>
          let cleanupTarget := cleanupOut / "CounterMirror.generated.ts"
          IO.FS.removeFile cleanupTarget
          let cleanupOutside := temporaryRoot / "cleanup-outside.txt"
          IO.FS.writeFile cleanupOutside "CLEANUP-SENTINEL"
          match ← makeSymlink cleanupOutside cleanupTarget with
          | .error error =>
              check fails "filesystem hardening: create stale-path symlink" false error
          | .ok () =>
              let manifestOnly : Shell.ModelInterface.Emit.TypeScript.GeneratedTree := {
                files := tree.files.filter (fun file =>
                  file.relativePath ==
                    Shell.ModelInterface.Compiler.generatedManifestPath)
              }
              let cleanupResult ← Shell.ModelInterface.Compiler.writeGeneratedTree
                cleanupOut.toString manifestOnly
              check fails "filesystem hardening: symlinked stale cleanup rejected"
                (compilerRejected cleanupResult)
              check fails "filesystem hardening: cleanup escape preserved"
                ((← IO.FS.readFile cleanupOutside) == "CLEANUP-SENTINEL")

      let checkDir := temporaryRoot / "check-inputs"
      let checkOut := temporaryRoot / "check-out"
      IO.FS.createDir checkDir
      let specPath := checkDir / "Counter.tla"
      let contractPath := checkDir / "Counter.mirror-interface.json"
      let evidencePath := checkDir / "counter.itf.json"
      let lockPath := checkDir / "Counter.lock.json"
      IO.FS.writeFile specPath "---- MODULE Counter ----\n====\n"
      IO.FS.writeBinFile contractPath
        (Codec.ModelInterfaceJson.canonicalFileBytes
          (Codec.ModelInterfaceJson.encodeContract counterContract))
      IO.FS.writeFile evidencePath counterEvidenceJson
      let inputPaths : Shell.ModelInterface.Compiler.InputPaths := {
        spec := specPath.toString
        contract := contractPath.toString
        evidence := evidencePath.toString
        paramVar := some "parameters"
      }
      let rootMismatchPath := checkDir / "Root.tla"
      let helperPath := checkDir / "Helper.tla"
      let rootMismatchContractPath := checkDir / "RootMismatch.mirror-interface.json"
      IO.FS.writeFile rootMismatchPath
        "---- MODULE Root ----\nEXTENDS Helper\n====\n"
      IO.FS.writeFile helperPath "---- MODULE Helper ----\n====\n"
      let rootMismatchContract := {
        counterContract with model := {
          moduleName := "Helper"
          source := "specs/Root.tla" } }
      IO.FS.writeBinFile rootMismatchContractPath
        (Codec.ModelInterfaceJson.canonicalFileBytes
          (Codec.ModelInterfaceJson.encodeContract rootMismatchContract))
      let rootMismatchInputPaths := {
        inputPaths with
          spec := rootMismatchPath.toString
          contract := rootMismatchContractPath.toString }
      match ← Shell.ModelInterface.Compiler.compile rootMismatchInputPaths with
      | .ok _ =>
          check fails "filesystem hardening: dependency cannot impersonate root" false
      | .error error =>
          check fails "filesystem hardening: root-module mismatch is explicit"
            (error.message.contains "model source declares module Root")
            error.message
      let absoluteContractPath := checkDir / "AbsoluteSource.mirror-interface.json"
      let absoluteSourceContract := {
        counterContract with model := {
          counterContract.model with
            source := "C:\\Users\\private\\Counter.tla" } }
      IO.FS.writeBinFile absoluteContractPath
        (Codec.ModelInterfaceJson.canonicalFileBytes
          (Codec.ModelInterfaceJson.encodeContract absoluteSourceContract))
      let absoluteInputPaths := {
        inputPaths with contract := absoluteContractPath.toString }
      match ← Shell.ModelInterface.Compiler.compile absoluteInputPaths with
      | .ok _ =>
          check fails "filesystem hardening: absolute logical source rejected" false
      | .error error =>
          let locations := error.diagnostics.flatMap fun diagnostic =>
            diagnostic.primary :: diagnostic.related
          check fails "filesystem hardening: diagnostic locations present"
            (!locations.isEmpty)
          check fails "filesystem hardening: diagnostics omit absolute paths"
            (locations.all fun location =>
              !(location.source : System.FilePath).isAbsolute &&
                !location.source.contains temporaryRoot.toString &&
                !location.source.contains "Users" &&
                !location.source.contains '\\')
      match ← Shell.ModelInterface.Compiler.compile inputPaths with
      | .error error =>
          check fails "filesystem hardening: check prerequisite compilation" false
            error.message
      | .ok compilation =>
          let lockRaceDir := temporaryRoot / "lock-race"
          let lockRaceTarget := lockRaceDir / "Counter.lock.json"
          IO.FS.createDir lockRaceDir
          let lockInjection ← IO.asTask (prio := Task.Priority.dedicated)
            (injectUnownedWhenStaged lockRaceDir lockRaceTarget 5000)
          let lockRaceCompilation := {
            compilation with
              lockBytes := ByteArray.mk
                (Array.replicate (8 * 1024 * 1024) 0x62) }
          let lockRaceResult ← Shell.ModelInterface.Compiler.writeLock
            lockRaceTarget.toString lockRaceCompilation
          let lockInjectionResult : Except IO.Error Bool := lockInjection.get
          let lockInjected := match lockInjectionResult with
            | .ok value => value
            | .error _ => false
          check fails "filesystem hardening: concurrent lock target injected"
            lockInjected
          check fails "filesystem hardening: concurrent lock target rejected"
            (compilerRejected lockRaceResult)
          check fails "filesystem hardening: concurrent lock target preserved"
            (lockInjected &&
              (← IO.FS.readFile lockRaceTarget) == "CONCURRENT-UNOWNED")
          let lockWrite ← Shell.ModelInterface.Compiler.writeLock
            lockPath.toString compilation
          let checkTree ← match Shell.ModelInterface.Compiler.emitTarget
              Shell.ModelInterface.Compiler.mirrorecmaTarget compilation.lock with
            | .ok emitted => pure emitted
            | .error error =>
                check fails "filesystem hardening: check prerequisite emission" false
                  error.message
                pure { files := [] }
          let treeWrite ← Shell.ModelInterface.Compiler.writeGeneratedTree
            checkOut.toString checkTree
          if lockWrite.isOk && treeWrite.isOk then
            let checkTarget := checkOut / "CounterMirror.generated.ts"
            IO.FS.removeFile checkTarget
            let checkOutside := temporaryRoot / "check-outside.txt"
            IO.FS.writeFile checkOutside "CHECK-SENTINEL"
            match ← makeSymlink checkOutside checkTarget with
            | .error error =>
                check fails "filesystem hardening: create check symlink" false error
            | .ok () =>
                let checkResult ← Shell.ModelInterface.Compiler.check inputPaths
                  lockPath.toString Shell.ModelInterface.Compiler.mirrorecmaTarget
                  checkOut.toString
                check fails "filesystem hardening: read-only check rejects symlink"
                  (compilerRejected checkResult)
                check fails "filesystem hardening: read-only check stayed contained"
                  ((← IO.FS.readFile checkOutside) == "CHECK-SENTINEL")
          else
            check fails "filesystem hardening: check prerequisites publish" false

    let aliasDirectory := temporaryRoot / "alias-component"
    IO.FS.createDir aliasDirectory
    let aliasRoot := aliasDirectory.toString ++ "/.."
    let aliasResult ← Shell.ModelInterface.Compiler.writeGeneratedTree aliasRoot tree
    check fails "filesystem hardening: root alias rejected"
      (compilerRejected aliasResult)
    check fails "filesystem hardening: alias produced no manifest"
      (!(← (temporaryRoot /
        Shell.ModelInterface.Compiler.generatedManifestPath).pathExists))

    let unownedOut := temporaryRoot / "unowned-out"
    IO.FS.createDir unownedOut
    let unownedTarget := unownedOut / "CounterMirror.generated.ts"
    IO.FS.writeFile unownedTarget "UNOWNED"
    let unownedResult ← Shell.ModelInterface.Compiler.writeGeneratedTree
      unownedOut.toString tree
    check fails "filesystem hardening: existing unowned target rejected"
      (compilerRejected unownedResult)
    check fails "filesystem hardening: existing unowned target preserved"
      ((← IO.FS.readFile unownedTarget) == "UNOWNED")

    let lockedOut := temporaryRoot / "locked-out"
    IO.FS.createDir lockedOut
    let publicationLock := lockedOut /
      Shell.ModelInterface.Compiler.generatedPublicationLockPath
    IO.FS.writeFile publicationLock "ACTIVE"
    let lockedResult ← Shell.ModelInterface.Compiler.writeGeneratedTree
      lockedOut.toString tree
    check fails "filesystem hardening: cooperative publication lock rejected"
      (compilerRejected lockedResult)
    check fails "filesystem hardening: locked output stayed untouched"
      (!(← (lockedOut / "CounterMirror.generated.ts").pathExists) &&
        (← IO.FS.readFile publicationLock) == "ACTIVE")

    let reservedManifestOut := temporaryRoot / "reserved-manifest-out"
    IO.FS.createDir reservedManifestOut
    let reservedManifest := reservedManifestOut /
      Shell.ModelInterface.Compiler.generatedManifestPath
    IO.FS.writeFile reservedManifest <| Lean.Json.compress <| Lean.Json.mkObj [
      ("files", .arr #[
        .str Shell.ModelInterface.Compiler.generatedManifestPath,
        .str ".MODEL-INTERFACE-GENERATION.LOCK"]),
      ("profileVersion", .num 1),
      ("schema", .str "mirrors.model-interface-generated/v1"),
      ("semanticDigest", .str (String.ofList (List.replicate 64 '0'))),
      ("targetProfile", .str "mirrorecma-v1")]
    let reservedManifestResult ←
      Shell.ModelInterface.Compiler.writeGeneratedTree
        reservedManifestOut.toString tree
    check fails "filesystem hardening: manifest cannot own publication lock"
      (compilerRejected reservedManifestResult)
    check fails "filesystem hardening: malicious manifest cannot remove active lock"
      (!(← (reservedManifestOut /
          Shell.ModelInterface.Compiler.generatedPublicationLockPath).pathExists) &&
        !(← (reservedManifestOut /
          "CounterMirror.generated.ts").pathExists))

    let aliasManifestOut := temporaryRoot / "alias-manifest-out"
    IO.FS.createDir aliasManifestOut
    let oldAliasName := "COUNTERMIRROR.GENERATED.TS"
    let oldAliasTarget := aliasManifestOut / oldAliasName
    IO.FS.writeFile oldAliasTarget "OLD-GENERATED"
    IO.FS.writeFile
      (aliasManifestOut / Shell.ModelInterface.Compiler.generatedManifestPath) <|
      Lean.Json.compress <| Lean.Json.mkObj [
        ("files", .arr #[
          .str Shell.ModelInterface.Compiler.generatedManifestPath,
          .str oldAliasName]),
        ("profileVersion", .num 1),
        ("schema", .str "mirrors.model-interface-generated/v1"),
        ("semanticDigest", .str (String.ofList (List.replicate 64 '0'))),
        ("targetProfile", .str "mirrorecma-v1")]
    let aliasManifestResult ←
      Shell.ModelInterface.Compiler.writeGeneratedTree aliasManifestOut.toString tree
    check fails "filesystem hardening: cross-generation case alias rejected"
      (compilerRejected aliasManifestResult)
    check fails "filesystem hardening: prior alias spelling preserved"
      ((← IO.FS.readFile oldAliasTarget) == "OLD-GENERATED")

    let raceOut := temporaryRoot / "race-out"
    let raceTarget := raceOut / "zz-victim.txt"
    let raceTree : Shell.ModelInterface.Emit.TypeScript.GeneratedTree := {
      files := [
        { relativePath := "00-delay.bin"
          bytes := ByteArray.mk (Array.replicate (8 * 1024 * 1024) 0x61) },
        { relativePath := "zz-victim.txt", bytes := "GENERATED".toUTF8 },
        { relativePath := Shell.ModelInterface.Compiler.generatedManifestPath
          bytes := "{}\n".toUTF8 }
      ]
    }
    let injection ← IO.asTask (prio := Task.Priority.dedicated)
      (injectUnownedWhenStaged raceOut raceTarget 5000)
    let raceResult ← Shell.ModelInterface.Compiler.writeGeneratedTree
      raceOut.toString raceTree
    let injectionResult : Except IO.Error Bool := injection.get
    let injected := match injectionResult with
      | .ok value => value
      | .error _ => false
    check fails "filesystem hardening: concurrent target injected" injected
    check fails "filesystem hardening: concurrent unowned target rejected"
      (compilerRejected raceResult)
    check fails "filesystem hardening: concurrent unowned target preserved"
      (injected && (← IO.FS.readFile raceTarget) == "CONCURRENT-UNOWNED")
    check fails "filesystem hardening: failed tree rolled back new files"
      (!(← (raceOut / "00-delay.bin").pathExists) &&
        !(← (raceOut /
          Shell.ModelInterface.Compiler.generatedManifestPath).pathExists) &&
        !(← (raceOut /
          Shell.ModelInterface.Compiler.generatedPublicationLockPath).pathExists))

    let rollbackOut := temporaryRoot / "rollback-out"
    match ← Shell.ModelInterface.Compiler.writeGeneratedTree
        rollbackOut.toString tree with
    | .error error =>
        check fails "filesystem hardening: rollback prerequisite publication"
          false error.message
    | .ok _ =>
        let rollbackSource := rollbackOut / "CounterMirror.generated.ts"
        let rollbackManifest := rollbackOut /
          Shell.ModelInterface.Compiler.generatedManifestPath
        let originalSource ← IO.FS.readBinFile rollbackSource
        let originalManifest ← IO.FS.readBinFile rollbackManifest
        let rollbackVictim := rollbackOut / "zz-victim.txt"
        let rollbackTree : Shell.ModelInterface.Emit.TypeScript.GeneratedTree := {
          files := [
            { relativePath := "CounterMirror.generated.ts"
              bytes := ByteArray.mk (Array.replicate (8 * 1024 * 1024) 0x63) },
            { relativePath := "zz-victim.txt", bytes := "GENERATED".toUTF8 },
            { relativePath := Shell.ModelInterface.Compiler.generatedManifestPath
              bytes := originalManifest }
          ]
        }
        let rollbackInjection ← IO.asTask (prio := Task.Priority.dedicated)
          (injectUnownedWhenStaged rollbackOut rollbackVictim 5000)
        let rollbackResult ← Shell.ModelInterface.Compiler.writeGeneratedTree
          rollbackOut.toString rollbackTree
        let rollbackInjectionResult : Except IO.Error Bool :=
          rollbackInjection.get
        let rollbackInjected := match rollbackInjectionResult with
          | .ok value => value
          | .error _ => false
        check fails "filesystem hardening: rollback target injected"
          rollbackInjected
        check fails "filesystem hardening: rollback failure rejected"
          (compilerRejected rollbackResult)
        check fails "filesystem hardening: previous generated tree restored"
          ((← IO.FS.readBinFile rollbackSource) == originalSource &&
            (← IO.FS.readBinFile rollbackManifest) == originalManifest &&
            rollbackInjected &&
            (← IO.FS.readFile rollbackVictim) == "CONCURRENT-UNOWNED")
  finally
    IO.FS.removeDirAll temporaryRoot

def run : IO UInt32 := do
  let fails ← IO.mkRef ([] : List String)
  let scenario (name : String) (body : IO Unit) : IO Unit := do
    IO.eprintln s!"[scenario {name}]"
    try body
    catch error =>
      fails.modify (fun fs => fs ++ [s!"{name}: exception: {error}"])

  scenario "sha-strict-json" (scenarioShaAndStrictJson fails)
  scenario "canonical-diagnostics" (scenarioCanonicalDiagnostics fails)
  let resolvedRef ← IO.mkRef (none : Option ResolvedModelInterface)
  scenario "counter-resolution" do
    match ← scenarioCounterResolution fails with
    | some (_, resolved) => resolvedRef.set (some resolved)
    | none => pure ()
  scenario "resource-limits" (scenarioResourceLimits fails)
  scenario "negotiation" (scenarioNegotiation fails)
  scenario "runtime-negotiation-matrix" (scenarioRuntimeNegotiationMatrix fails)
  scenario "negotiation-codec" (scenarioNegotiationCodec fails)
  scenario "cache" (scenarioCache fails)
  scenario "runtime-cache" (scenarioRuntimeCache fails)
  scenario "preflight" do
    match ← resolvedRef.get with
    | some resolved => scenarioPreflight fails resolved
    | none => check fails "preflight: prerequisite resolution" false
  scenario "cli-diagnostics" (scenarioCliDiagnostics fails)
  scenario "typescript-emitter" do
    match ← resolvedRef.get with
    | some resolved => scenarioEmitter fails resolved
    | none => check fails "emitter: prerequisite resolution" false
  scenario "semantic-identity-and-large-lock" do
    match ← resolvedRef.get with
    | some resolved => scenarioSemanticIdentityAndLargeLock fails resolved
    | none => check fails "semantic identity: prerequisite resolution" false
  scenario "filesystem-hardening" do
    match ← resolvedRef.get with
    | some resolved => scenarioFilesystemHardening fails resolved
    | none => check fails "filesystem hardening: prerequisite resolution" false

  let failures ← fails.get
  if failures.isEmpty then
    IO.println "MODEL INTERFACE SPEC GREEN"
    return 0
  else
    for failure in failures do
      IO.eprintln s!"FAIL {failure}"
    IO.eprintln s!"{failures.length} FAILURES"
    return 1

end ModelInterfaceSpec

def main : IO UInt32 :=
  ModelInterfaceSpec.run
