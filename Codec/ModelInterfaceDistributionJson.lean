import Codec.ModelInterfaceJson
import Codec.StrictJson
import Core.ModelInterface.Distribution
import Core.ModelInterface.Sha256
import Lean.Data.Json

/-!
# Runtime model-interface distribution JSON

Wire-only negotiation types and codecs.  The helpers operate on registration,
`spec_validated`, and `register_error` JSON objects, leaving the frozen
`Codec.Json` message constructors unchanged.  Optional insertion with `none`
returns the original `Lean.Json` value verbatim.
-/

namespace Codec.ModelInterfaceDistributionJson

open Lean Core.ModelInterface

abbrev DecodeResult (α : Type) := Except String α

abbrev Policy := NegotiationPolicy
abbrev Status := NegotiationStatus

inductive ContractReference where
  | inline (contract : ContractV1)
  /-- Reserved for a future authorization-aware contract registry. -/
  | digest (digest : String)
  deriving Repr

structure RequestV1 where
  schema : String := negotiationSchemaV1
  request : RequestMode
  policy : Policy
  acceptDescriptorSchemas : List String
  /-- Normalized 64-character lowercase hexadecimal, without `sha256:`. -/
  expectedSemanticDigest : Option SemanticDigest := none
  /-- Normalized 64-character lowercase hexadecimal, without `sha256:`. -/
  ifNoneMatch : Option SemanticDigest := none
  contract : ContractReference
  deriving Repr

/-- Drop the wire-only contract reference before invoking the pure policy
module. -/
def RequestV1.toCore (request : RequestV1) : ModelInterfaceRequestV1 where
  schema := request.schema
  request := request.request
  policy := request.policy
  acceptDescriptorSchemas := request.acceptDescriptorSchemas
  expectedSemanticDigest := request.expectedSemanticDigest
  ifNoneMatch := request.ifNoneMatch

/-- Attach a wire contract reference to a pure policy request. -/
def RequestV1.ofCore (request : ModelInterfaceRequestV1)
    (contract : ContractReference) : RequestV1 where
  schema := request.schema
  request := request.request
  policy := request.policy
  acceptDescriptorSchemas := request.acceptDescriptorSchemas
  expectedSemanticDigest := request.expectedSemanticDigest
  ifNoneMatch := request.ifNoneMatch
  contract := contract

structure ReplyV1 where
  schema : String := negotiationSchemaV1
  status : Status
  descriptorSchema : Option String := none
  /-- Normalized lowercase hex without the wire prefix. -/
  semanticDigest : Option SemanticDigest := none
  provenanceDigest : Option ProvenanceDigest := none
  descriptorBytes : Option Nat := none
  descriptor : Option SemanticDescriptor := none
  deriving Repr

structure FailureV1 where
  schema : String := negotiationSchemaV1
  status : Status
  code : String
  expectedSemanticDigest : Option SemanticDigest := none
  actualSemanticDigest : Option SemanticDigest := none
  provenanceDigest : Option ProvenanceDigest := none
  descriptorBytes : Option Nat := none
  deriving Repr

def RequestMode.toCore : RequestMode → Core.ModelInterface.RequestMode
  | .verify => .verify
  | .descriptor => .descriptor

def Policy.toCore : Policy → Core.ModelInterface.NegotiationPolicy
  | .require => .require
  | .prefer => .prefer

def Status.ofCore : Core.ModelInterface.NegotiationStatus → Status
  | .matched => .matched
  | .resolved => .resolved
  | .notModified => .notModified
  | .mismatch => .mismatch
  | .unsupported => .unsupported
  | .unavailable => .unavailable
  | .tooLarge => .tooLarge

private abbrev Fields := List (String × Json)

private def fail (context message : String) : DecodeResult α :=
  .error s!"{context}: {message}"

private def array (values : List Json) : Json := .arr values.toArray

private def objectFields (context : String) : Json → DecodeResult Fields
  | .obj fields => .ok fields.toList
  | _ => fail context "object expected"

private def checkObject (context : String) (allowed requiredNames : List String)
    (json : Json) : DecodeResult Fields := do
  let fields ← objectFields context json
  match fields.find? (fun field => !allowed.contains field.1) with
  | some field => fail context s!"unknown field '{field.1}'"
  | none => pure ()
  match requiredNames.find? (fun name => (List.lookup name fields).isNone) with
  | some name => fail context s!"missing required field '{name}'"
  | none => return fields

private def required (context : String) (fields : Fields) (name : String) :
    DecodeResult Json :=
  match List.lookup name fields with
  | some value => .ok value
  | none => fail context s!"missing required field '{name}'"

private def optional (fields : Fields) (name : String) : Option Json :=
  match List.lookup name fields with
  | some .null | none => none
  | some value => some value

private def optionalField (name : String) (value : Option Json) : Fields :=
  match value with
  | some value => [(name, value)]
  | none => []

private def decodeString (context : String) : Json → DecodeResult String
  | .str value => .ok value
  | _ => fail context "string expected"

private def decodeNat (context : String) : Json → DecodeResult Nat
  | .num ⟨mantissa, 0⟩ =>
      if 0 ≤ mantissa then .ok mantissa.toNat
      else fail context "nonnegative integer expected"
  | _ => fail context "nonnegative integer expected"

private def decodeStringArray (context : String) : Json → DecodeResult (List String)
  | .arr values => values.toList.mapM (decodeString (context ++ "[]"))
  | _ => fail context "array expected"

private def isLowerHex (character : Char) : Bool :=
  ('0'.toNat ≤ character.toNat && character.toNat ≤ '9'.toNat) ||
  ('a'.toNat ≤ character.toNat && character.toNat ≤ 'f'.toNat)

/-- Validate a normalized digest payload (64 lowercase hexadecimal digits). -/
def validDigestHex (digest : String) : Bool :=
  digest.length == 64 && digest.toList.all isLowerHex

/-- Parse the wire form `sha256:<64 lowercase hex>` into normalized hex. -/
def parseWireDigest (context digest : String) : DecodeResult String :=
  if digest.startsWith "sha256:" then
    let payload := (digest.drop 7).toString
    if validDigestHex payload then .ok payload
    else fail context "digest must contain exactly 64 lowercase hexadecimal characters"
  else fail context "digest must start with 'sha256:'"

/-- Render normalized lowercase hex in the protocol's digest form. -/
def renderWireDigest (digest : String) : String :=
  "sha256:" ++ digest

private def decodeOptionalDigest (context name : String) (fields : Fields) :
    DecodeResult (Option String) :=
  match optional fields name with
  | none => .ok none
  | some value => do
      let wire ← decodeString (context ++ "." ++ name) value
      return some (← parseWireDigest (context ++ "." ++ name) wire)

private def encodeMode : RequestMode → Json
  | .verify => .str "verify"
  | .descriptor => .str "descriptor"

private def decodeMode (context : String) (json : Json) : DecodeResult RequestMode := do
  match ← decodeString context json with
  | "verify" => return .verify
  | "descriptor" => return .descriptor
  | other => fail context s!"unknown request mode '{other}'"

private def encodePolicy : Policy → Json
  | .require => .str "require"
  | .prefer => .str "prefer"

private def decodePolicy (context : String) (json : Json) : DecodeResult Policy := do
  match ← decodeString context json with
  | "require" => return .require
  | "prefer" => return .prefer
  | other => fail context s!"unknown policy '{other}'"

private def encodeStatus : Status → Json
  | .matched => .str "matched"
  | .resolved => .str "resolved"
  | .notModified => .str "not_modified"
  | .mismatch => .str "mismatch"
  | .unsupported => .str "unsupported"
  | .unavailable => .str "unavailable"
  | .tooLarge => .str "too_large"

private def decodeStatus (context : String) (json : Json) : DecodeResult Status := do
  match ← decodeString context json with
  | "matched" => return .matched
  | "resolved" => return .resolved
  | "not_modified" => return .notModified
  | "mismatch" => return .mismatch
  | "unsupported" => return .unsupported
  | "unavailable" => return .unavailable
  | "too_large" => return .tooLarge
  | other => fail context s!"unknown negotiation status '{other}'"

private def encodeContractReference : ContractReference → Json
  | .inline contract => Json.mkObj [("inline", ModelInterfaceJson.encodeContract contract)]
  | .digest digest => Json.mkObj [("digest", .str (renderWireDigest digest))]

private def decodeContractReference (context : String) (json : Json) :
    DecodeResult ContractReference := do
  let fields ← objectFields context json
  if fields.length != 1 then fail context "exactly one contract reference form is required"
  else
    match fields with
    | [(name, value)] =>
        if name == "inline" then
          return .inline (← ModelInterfaceJson.decodeContract value)
        else if name == "digest" then
          let wire ← decodeString (context ++ ".digest") value
          return .digest (← parseWireDigest (context ++ ".digest") wire)
        else fail context s!"unknown contract reference '{name}'"
    | _ => fail context "invalid contract reference"

/-- Validate request cross-field invariants after construction or decoding. -/
def validateRequest (request : RequestV1) : DecodeResult Unit := do
  if request.schema != negotiationSchemaV1 then
    fail "modelInterface.schema" s!"expected '{negotiationSchemaV1}'"
  if request.acceptDescriptorSchemas.isEmpty then
    fail "modelInterface.acceptDescriptorSchemas" "at least one schema is required"
  if request.acceptDescriptorSchemas.length > maxAcceptedDescriptorSchemasV1 then
    fail "modelInterface.acceptDescriptorSchemas" "at most eight schemas are accepted"
  if request.acceptDescriptorSchemas.any String.isEmpty then
    fail "modelInterface.acceptDescriptorSchemas" "schema names must not be empty"
  let uniqueSchemas := request.acceptDescriptorSchemas.foldl (fun seen schema =>
    if seen.contains schema then seen else schema :: seen) []
  if uniqueSchemas.length != request.acceptDescriptorSchemas.length then
    fail "modelInterface.acceptDescriptorSchemas" "duplicate schema name"
  match request.expectedSemanticDigest with
  | some digest =>
      if !validDigestHex digest then fail "modelInterface.expectedSemanticDigest" "invalid digest"
  | none => pure ()
  match request.ifNoneMatch with
  | some digest =>
      if !validDigestHex digest then fail "modelInterface.ifNoneMatch" "invalid digest"
  | none => pure ()
  match request.request with
  | .verify =>
      if request.expectedSemanticDigest.isNone then
        fail "modelInterface.expectedSemanticDigest" "required for verify"
      if request.ifNoneMatch.isSome then
        fail "modelInterface.ifNoneMatch" "allowed only for descriptor requests"
  | .descriptor => pure ()
  match request.contract with
  | .digest digest =>
      if !validDigestHex digest then fail "modelInterface.contract.digest" "invalid digest"
  | .inline _ => pure ()

/-- Encode the strict `modelInterface` registration field. -/
def encodeRequest (request : RequestV1) : Json :=
  Json.mkObj ([
    ("acceptDescriptorSchemas", array (request.acceptDescriptorSchemas.map Json.str)),
    ("contract", encodeContractReference request.contract),
    ("policy", encodePolicy request.policy),
    ("request", encodeMode request.request),
    ("schema", .str request.schema)
  ] ++ optionalField "expectedSemanticDigest"
      (request.expectedSemanticDigest.map (Json.str ∘ renderWireDigest)) ++
    optionalField "ifNoneMatch" (request.ifNoneMatch.map (Json.str ∘ renderWireDigest)))

/-- Strictly decode the `modelInterface` registration field. -/
def decodeRequest (json : Json) : DecodeResult RequestV1 := do
  let context := "modelInterface"
  let fields ← checkObject context
    ["schema", "request", "policy", "acceptDescriptorSchemas",
      "expectedSemanticDigest", "ifNoneMatch", "contract"]
    ["schema", "request", "policy", "acceptDescriptorSchemas", "contract"] json
  let request : RequestV1 := {
    schema := ← decodeString (context ++ ".schema") (← required context fields "schema")
    request := ← decodeMode (context ++ ".request") (← required context fields "request")
    policy := ← decodePolicy (context ++ ".policy") (← required context fields "policy")
    acceptDescriptorSchemas := ← decodeStringArray (context ++ ".acceptDescriptorSchemas")
      (← required context fields "acceptDescriptorSchemas")
    expectedSemanticDigest := ← decodeOptionalDigest context "expectedSemanticDigest" fields
    ifNoneMatch := ← decodeOptionalDigest context "ifNoneMatch" fields
    contract := ← decodeContractReference (context ++ ".contract")
      (← required context fields "contract")
  }
  validateRequest request
  return request

/-- Strictly parse a standalone negotiation request object. -/
def parseRequestBytes (raw : ByteArray)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) : DecodeResult RequestV1 := do
  let json ← (StrictJson.parseBytes raw limits).mapError toString
  decodeRequest json

/-- Compute the normalized semantic digest of a descriptor. -/
def descriptorSemanticDigest (descriptor : SemanticDescriptor) : String :=
  Core.ModelInterface.Sha256.digestDomainHex descriptorDigestDomainV1
    (ModelInterfaceJson.canonicalBytes (ModelInterfaceJson.encodeSemanticDescriptor descriptor))

private def validateOptionalDigest (context : String) : Option String → DecodeResult Unit
  | none => .ok ()
  | some digest =>
      if validDigestHex digest then .ok () else fail context "invalid digest"

/-- Validate status-dependent reply fields and descriptor correspondence. -/
def validateReply (reply : ReplyV1) : DecodeResult Unit := do
  if reply.schema != negotiationSchemaV1 then
    fail "modelInterface.schema" s!"expected '{negotiationSchemaV1}'"
  validateOptionalDigest "modelInterface.semanticDigest" reply.semanticDigest
  validateOptionalDigest "modelInterface.provenanceDigest" reply.provenanceDigest
  let requireDescriptorIdentity : DecodeResult Unit := do
    let schema ← match reply.descriptorSchema with
      | some schema => .ok schema
      | none => fail "modelInterface.descriptorSchema" "required for this status"
    if schema != descriptorSchemaV1 then
      fail "modelInterface.descriptorSchema" s!"expected '{descriptorSchemaV1}'"
    if reply.semanticDigest.isNone then
      fail "modelInterface.semanticDigest" "required for this status"
  match reply.status with
  | .matched =>
      requireDescriptorIdentity
      if reply.descriptor.isSome then fail "modelInterface.descriptor" "forbidden for matched"
      if reply.descriptorBytes.isSome then fail "modelInterface.descriptorBytes" "forbidden for matched"
  | .resolved =>
      requireDescriptorIdentity
      let descriptor ← match reply.descriptor with
        | some descriptor => .ok descriptor
        | none => fail "modelInterface.descriptor" "required for resolved"
      let byteCount ← match reply.descriptorBytes with
        | some byteCount => .ok byteCount
        | none => fail "modelInterface.descriptorBytes" "required for resolved"
      if descriptor.schema != reply.descriptorSchema.getD "" then
        fail "modelInterface.descriptor" "descriptor schema does not match envelope"
      let actualBytes :=
        (ModelInterfaceJson.canonicalBytes (ModelInterfaceJson.encodeSemanticDescriptor descriptor)).size
      if actualBytes != byteCount then
        fail "modelInterface.descriptorBytes" s!"expected {actualBytes}"
      let actualDigest := descriptorSemanticDigest descriptor
      if reply.semanticDigest != some actualDigest then
        fail "modelInterface.semanticDigest" "does not match canonical descriptor"
  | .notModified =>
      requireDescriptorIdentity
      if reply.descriptor.isSome then fail "modelInterface.descriptor" "forbidden for not_modified"
      if reply.descriptorBytes.isSome then
        fail "modelInterface.descriptorBytes" "forbidden for not_modified"
  | .tooLarge =>
      requireDescriptorIdentity
      if reply.descriptor.isSome then fail "modelInterface.descriptor" "forbidden for too_large"
      if reply.descriptorBytes.isNone then
        fail "modelInterface.descriptorBytes" "required for too_large"
  | .mismatch =>
      if reply.descriptor.isSome then fail "modelInterface.descriptor" "forbidden for failure status"
      if reply.descriptorBytes.isSome then
        fail "modelInterface.descriptorBytes" "forbidden for mismatch"
  | .unsupported | .unavailable =>
      if reply.descriptorSchema.isSome || reply.semanticDigest.isSome ||
          reply.provenanceDigest.isSome || reply.descriptorBytes.isSome || reply.descriptor.isSome then
        fail "modelInterface" "descriptor identity fields are forbidden when resolution is unavailable"

/-- Encode a `modelInterface` field carried by `spec_validated`. -/
def encodeReply (reply : ReplyV1) : Json :=
  Json.mkObj ([
    ("schema", .str reply.schema), ("status", encodeStatus reply.status)
  ] ++ optionalField "descriptorSchema" (reply.descriptorSchema.map Json.str) ++
    optionalField "semanticDigest" (reply.semanticDigest.map (Json.str ∘ renderWireDigest)) ++
    optionalField "provenanceDigest" (reply.provenanceDigest.map (Json.str ∘ renderWireDigest)) ++
    optionalField "descriptorBytes" (reply.descriptorBytes.map Json.num) ++
    optionalField "descriptor" (reply.descriptor.map ModelInterfaceJson.encodeSemanticDescriptor))

/-- Strictly decode a `modelInterface` reply field. -/
def decodeReply (json : Json) : DecodeResult ReplyV1 := do
  let context := "modelInterface"
  let fields ← checkObject context
    ["schema", "status", "descriptorSchema", "semanticDigest", "provenanceDigest",
      "descriptorBytes", "descriptor"] ["schema", "status"] json
  let descriptorSchema ← match optional fields "descriptorSchema" with
    | none => .ok none
    | some value => some <$> decodeString (context ++ ".descriptorSchema") value
  let descriptorBytes ← match optional fields "descriptorBytes" with
    | none => .ok none
    | some value => some <$> decodeNat (context ++ ".descriptorBytes") value
  let descriptor ← match optional fields "descriptor" with
    | none => .ok none
    | some value => some <$> ModelInterfaceJson.decodeSemanticDescriptor value
  let reply : ReplyV1 := {
    schema := ← decodeString (context ++ ".schema") (← required context fields "schema")
    status := ← decodeStatus (context ++ ".status") (← required context fields "status")
    descriptorSchema := descriptorSchema
    semanticDigest := ← decodeOptionalDigest context "semanticDigest" fields
    provenanceDigest := ← decodeOptionalDigest context "provenanceDigest" fields
    descriptorBytes := descriptorBytes
    descriptor := descriptor
  }
  validateReply reply
  return reply

/-- Strictly parse a standalone negotiation reply object. -/
def parseReplyBytes (raw : ByteArray)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) : DecodeResult ReplyV1 := do
  let json ← (StrictJson.parseBytes raw limits).mapError toString
  decodeReply json

/-- Validate the structured `register_error` extension. -/
def validateFailure (failure : FailureV1) : DecodeResult Unit := do
  if failure.schema != negotiationSchemaV1 then
    fail "modelInterface.schema" s!"expected '{negotiationSchemaV1}'"
  if failure.code.isEmpty then fail "modelInterface.code" "must not be empty"
  match failure.status with
  | .matched | .resolved | .notModified =>
      fail "modelInterface.status" "success status is invalid on register_error"
  | .mismatch =>
      if failure.expectedSemanticDigest.isNone then
        fail "modelInterface.expectedSemanticDigest" "required for mismatch"
  | .tooLarge =>
      if failure.descriptorBytes.isNone then
        fail "modelInterface.descriptorBytes" "required for too_large"
  | .unsupported | .unavailable => pure ()
  validateOptionalDigest "modelInterface.expectedSemanticDigest" failure.expectedSemanticDigest
  validateOptionalDigest "modelInterface.actualSemanticDigest" failure.actualSemanticDigest
  validateOptionalDigest "modelInterface.provenanceDigest" failure.provenanceDigest

/-- Encode a structured `modelInterface` registration failure. -/
def encodeFailure (failure : FailureV1) : Json :=
  Json.mkObj ([
    ("code", .str failure.code), ("schema", .str failure.schema),
    ("status", encodeStatus failure.status)
  ] ++ optionalField "expectedSemanticDigest"
      (failure.expectedSemanticDigest.map (Json.str ∘ renderWireDigest)) ++
    optionalField "actualSemanticDigest"
      (failure.actualSemanticDigest.map (Json.str ∘ renderWireDigest)) ++
    optionalField "provenanceDigest"
      (failure.provenanceDigest.map (Json.str ∘ renderWireDigest)) ++
    optionalField "descriptorBytes" (failure.descriptorBytes.map Json.num))

/-- Strictly decode a structured `modelInterface` registration failure. -/
def decodeFailure (json : Json) : DecodeResult FailureV1 := do
  let context := "modelInterface"
  let fields ← checkObject context
    ["schema", "status", "code", "expectedSemanticDigest", "actualSemanticDigest",
      "provenanceDigest", "descriptorBytes"] ["schema", "status", "code"] json
  let descriptorBytes ← match optional fields "descriptorBytes" with
    | none => .ok none
    | some value => some <$> decodeNat (context ++ ".descriptorBytes") value
  let failure : FailureV1 := {
    schema := ← decodeString (context ++ ".schema") (← required context fields "schema")
    status := ← decodeStatus (context ++ ".status") (← required context fields "status")
    code := ← decodeString (context ++ ".code") (← required context fields "code")
    expectedSemanticDigest := ← decodeOptionalDigest context "expectedSemanticDigest" fields
    actualSemanticDigest := ← decodeOptionalDigest context "actualSemanticDigest" fields
    provenanceDigest := ← decodeOptionalDigest context "provenanceDigest" fields
    descriptorBytes := descriptorBytes
  }
  validateFailure failure
  return failure

/-- Strictly parse a standalone structured registration failure. -/
def parseFailureBytes (raw : ByteArray)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) : DecodeResult FailureV1 := do
  let json ← (StrictJson.parseBytes raw limits).mapError toString
  decodeFailure json

private def protoStep (context : String) (json : Json) : DecodeResult String := do
  let fields ← objectFields context json
  match List.lookup "proto_step" fields with
  | some value => decodeString (context ++ ".proto_step") value
  | none => fail context "missing required field 'proto_step'"

/-- Extract and decode an optional `modelInterface` field from `register` or
`register_traces`. Unknown outer registration fields remain additive. -/
def extractRegistrationRequest? (registration : Json) : DecodeResult (Option RequestV1) := do
  let tag ← protoStep "registration" registration
  let fields ← objectFields "registration" registration
  match optional fields "modelInterface" with
  | none => return none
  | some value =>
      if tag != "register" && tag != "register_traces" then
        fail "registration.proto_step"
          "model-interface negotiation is supported only on stepping registrations"
      return some (← decodeRequest value)

/-- Strictly parse a raw registration line and extract its optional request. -/
def parseRegistrationRequestBytes (raw : ByteArray)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) :
    DecodeResult (Json × Option RequestV1) := do
  let json ← (StrictJson.parseBytes raw limits).mapError toString
  return (json, ← extractRegistrationRequest? json)

private def insertField (context expectedTag name : String) (value : Json)
    (message : Json) : DecodeResult Json := do
  let tag ← protoStep context message
  if tag != expectedTag then fail (context ++ ".proto_step") s!"expected '{expectedTag}'"
  let fields ← objectFields context message
  if (List.lookup name fields).isSome then fail context s!"field '{name}' already present"
  return Json.mkObj ((name, value) :: fields)

/-- Insert an optional request into an existing `register` or
`register_traces` JSON object. `none` returns the original value exactly. -/
def insertRegistrationRequest? (registration : Json) (request : Option RequestV1) :
    DecodeResult Json :=
  match request with
  | none => .ok registration
  | some request => do
      validateRequest request
      let tag ← protoStep "registration" registration
      if tag != "register" && tag != "register_traces" then
        fail "registration.proto_step"
          "model-interface negotiation is supported only on stepping registrations"
      let fields ← objectFields "registration" registration
      if (List.lookup "modelInterface" fields).isSome then
        fail "registration" "field 'modelInterface' already present"
      return Json.mkObj (("modelInterface", encodeRequest request) :: fields)

/-- Insert an optional reply into an existing `spec_validated` JSON object.
`none` returns the original value exactly. -/
def insertSpecValidatedReply? (message : Json) (reply : Option ReplyV1) :
    DecodeResult Json :=
  match reply with
  | none => .ok message
  | some reply => do
      validateReply reply
      insertField "spec_validated" "spec_validated" "modelInterface" (encodeReply reply) message

/-- Insert an optional structured failure into an existing `register_error`
JSON object. `none` returns the original value exactly. -/
def insertRegisterErrorFailure? (message : Json) (failure : Option FailureV1) :
    DecodeResult Json :=
  match failure with
  | none => .ok message
  | some failure => do
      validateFailure failure
      insertField "register_error" "register_error" "modelInterface"
        (encodeFailure failure) message

/-- Decode an optional reply field from an existing `spec_validated` object. -/
def extractSpecValidatedReply? (message : Json) : DecodeResult (Option ReplyV1) := do
  let tag ← protoStep "spec_validated" message
  if tag != "spec_validated" then fail "spec_validated.proto_step" "unexpected message tag"
  let fields ← objectFields "spec_validated" message
  match optional fields "modelInterface" with
  | none => return none
  | some value => return some (← decodeReply value)

/-- Decode an optional failure field from an existing `register_error` object. -/
def extractRegisterErrorFailure? (message : Json) : DecodeResult (Option FailureV1) := do
  let tag ← protoStep "register_error" message
  if tag != "register_error" then fail "register_error.proto_step" "unexpected message tag"
  let fields ← objectFields "register_error" message
  match optional fields "modelInterface" with
  | none => return none
  | some value => return some (← decodeFailure value)

/-- Strictly parse a full `spec_validated` line and extract its optional reply. -/
def parseSpecValidatedReplyBytes (raw : ByteArray)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) :
    DecodeResult (Json × Option ReplyV1) := do
  let json ← (StrictJson.parseBytes raw limits).mapError toString
  return (json, ← extractSpecValidatedReply? json)

/-- Strictly parse a full `register_error` line and extract its optional
structured failure. -/
def parseRegisterErrorFailureBytes (raw : ByteArray)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) :
    DecodeResult (Json × Option FailureV1) := do
  let json ← (StrictJson.parseBytes raw limits).mapError toString
  return (json, ← extractRegisterErrorFailure? json)

end Codec.ModelInterfaceDistributionJson
