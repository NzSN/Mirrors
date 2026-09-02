import Core.ModelInterface.Resolve
import Codec.StrictJson
import Lean.Data.Json

/-!
# Canonical model-interface JSON

Canonical encoders and strict semantic decoders for the model-interface
compiler artifacts. Raw contract and descriptor entry points first pass through
`Codec.StrictJson`, so duplicate object keys are rejected before `Lean.Json`
can collapse them into its tree-map representation.
-/

namespace Codec.ModelInterfaceJson

open Lean Core.ModelInterface

abbrev DecodeResult (α : Type) := Except String α

private abbrev Fields := List (String × Json)

private def fail (context message : String) : DecodeResult α :=
  .error s!"{context}: {message}"

private def sortByString (key : α → String) (values : List α) : List α :=
  values.mergeSort fun a b => key a ≤ key b

private def sortStrings (values : List String) : List String :=
  values.mergeSort (· ≤ ·)

private def array (values : List Json) : Json :=
  .arr values.toArray

private def strings (values : List String) : Json :=
  array (values.map Json.str)

private def optionalField (name : String) (value : Option Json) : Fields :=
  match value with
  | some value => [(name, value)]
  | none => []

private def objectFields (context : String) : Json → DecodeResult Fields
  | .obj fields => .ok fields.toList
  | _ => fail context "object expected"

private def checkObject (context : String) (allowed required : List String)
    (json : Json) : DecodeResult Fields := do
  let fields ← objectFields context json
  match fields.find? (fun field => !allowed.contains field.1) with
  | some field => fail context s!"unknown field '{field.1}'"
  | none => pure ()
  match required.find? (fun name => (List.lookup name fields).isNone) with
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

private def decodeString (context : String) : Json → DecodeResult String
  | .str value => .ok value
  | _ => fail context "string expected"

private def decodeBool (context : String) : Json → DecodeResult Bool
  | .bool value => .ok value
  | _ => fail context "Boolean expected"

private def decodeNat (context : String) : Json → DecodeResult Nat
  | .num ⟨mantissa, 0⟩ =>
      if 0 ≤ mantissa then .ok mantissa.toNat
      else fail context "nonnegative integer expected"
  | _ => fail context "nonnegative integer expected"

private def decodeIntString (context : String) (json : Json) : DecodeResult Int := do
  let value ← decodeString context json
  match value.toInt? with
  | some value => return value
  | none => fail context "canonical decimal integer string expected"

private def decodeArray (context : String) (decode : Json → DecodeResult α) :
    Json → DecodeResult (List α)
  | .arr values => values.toList.mapM decode
  | _ => fail context "array expected"

private def decodeStringArray (context : String) (json : Json) : DecodeResult (List String) :=
  decodeArray context (decodeString context) json

/-! ## Structural types -/

/-- Encode the closed structural type grammar. -/
partial def encodeModelType : ModelType → Json
  | .int => Json.mkObj [("kind", .str "int")]
  | .bool => Json.mkObj [("kind", .str "bool")]
  | .str => Json.mkObj [("kind", .str "str")]
  | .null => Json.mkObj [("kind", .str "null")]
  | .set element => Json.mkObj [
      ("element", encodeModelType element), ("kind", .str "set")]
  | .seq element => Json.mkObj [
      ("element", encodeModelType element), ("kind", .str "seq")]
  | .tuple elements => Json.mkObj [
      ("elements", array (elements.map encodeModelType)), ("kind", .str "tuple")]
  | .record fields =>
      let fields := fields.map fun field =>
        (field.wireName, Json.mkObj [
          ("type", encodeModelType field.type), ("wireName", .str field.wireName)])
      let fields := fields.mergeSort fun a b => a.1 ≤ b.1
      Json.mkObj [
        ("fields", array (fields.map Prod.snd)),
        ("kind", .str "record")]
  | .map key value => Json.mkObj [
      ("key", encodeModelType key), ("kind", .str "map"),
      ("value", encodeModelType value)]
  | .variant cases =>
      let cases := cases.map fun item =>
        (item.tag, Json.mkObj [
          ("payload", encodeModelType item.payload), ("tag", .str item.tag)])
      let cases := cases.mergeSort fun a b => a.1 ≤ b.1
      Json.mkObj [
        ("cases", array (cases.map Prod.snd)),
        ("kind", .str "variant")]
  | .opaqueItf description => Json.mkObj [
      ("description", .str description), ("kind", .str "opaqueItf")]

private partial def decodeModelTypeWithFuel (fuel : Nat) (context : String)
    (json : Json) : DecodeResult ModelType := do
  if fuel == 0 then fail context "structural type nesting exceeds decoder limit"
  else
    let tagFields ← objectFields context json
    let kindJson ← required context tagFields "kind"
    let kind ← decodeString (context ++ ".kind") kindJson
    let recur := decodeModelTypeWithFuel (fuel - 1)
    match kind with
    | "int" =>
        let _ ← checkObject context ["kind"] ["kind"] json
        return .int
    | "bool" =>
        let _ ← checkObject context ["kind"] ["kind"] json
        return .bool
    | "str" =>
        let _ ← checkObject context ["kind"] ["kind"] json
        return .str
    | "null" =>
        let _ ← checkObject context ["kind"] ["kind"] json
        return .null
    | "set" =>
        let fields ← checkObject context ["kind", "element"] ["kind", "element"] json
        return .set (← recur (context ++ ".element") (← required context fields "element"))
    | "seq" =>
        let fields ← checkObject context ["kind", "element"] ["kind", "element"] json
        return .seq (← recur (context ++ ".element") (← required context fields "element"))
    | "tuple" =>
        let fields ← checkObject context ["kind", "elements"] ["kind", "elements"] json
        let values ← required context fields "elements"
        return .tuple (← decodeArray (context ++ ".elements")
          (recur (context ++ ".elements[]")) values)
    | "record" =>
        let fields ← checkObject context ["kind", "fields"] ["kind", "fields"] json
        let values ← required context fields "fields"
        let decoded ← decodeArray (context ++ ".fields") (fun value => do
          let item ← checkObject (context ++ ".fields[]") ["wireName", "type"]
            ["wireName", "type"] value
          let name ← decodeString (context ++ ".fields[].wireName")
            (← required context item "wireName")
          let type ← recur (context ++ ".fields[].type") (← required context item "type")
          return { wireName := name, type := type }) values
        return .record decoded
    | "map" =>
        let fields ← checkObject context ["kind", "key", "value"]
          ["kind", "key", "value"] json
        return .map
          (← recur (context ++ ".key") (← required context fields "key"))
          (← recur (context ++ ".value") (← required context fields "value"))
    | "variant" =>
        let fields ← checkObject context ["kind", "cases"] ["kind", "cases"] json
        let values ← required context fields "cases"
        let decoded ← decodeArray (context ++ ".cases") (fun value => do
          let item ← checkObject (context ++ ".cases[]") ["tag", "payload"]
            ["tag", "payload"] value
          let tag ← decodeString (context ++ ".cases[].tag") (← required context item "tag")
          let payload ← recur (context ++ ".cases[].payload")
            (← required context item "payload")
          return { tag := tag, payload := payload }) values
        return .variant decoded
    | "opaqueItf" =>
        let fields ← checkObject context ["kind", "description"]
          ["kind", "description"] json
        return .opaqueItf (← decodeString (context ++ ".description")
          (← required context fields "description"))
    | other => fail (context ++ ".kind") s!"unknown structural type '{other}'"

/-- Strictly decode a structural model type. -/
def decodeModelType (json : Json) : DecodeResult ModelType :=
  decodeModelTypeWithFuel maxStructuralTypeDepthV1 "type" json

/-! ## Typed path literals and projections -/

private partial def encodeLiteral : CanonicalItfLiteral → Json
  | .int value => Json.mkObj [("kind", .str "int"), ("value", .str value.repr)]
  | .bool value => Json.mkObj [("kind", .str "bool"), ("value", .bool value)]
  | .str value => Json.mkObj [("kind", .str "str"), ("value", .str value)]
  | .null => Json.mkObj [("kind", .str "null")]
  | .set values =>
      let values := values.map encodeLiteral
      let values := values.mergeSort fun a b => Json.compress a ≤ Json.compress b
      Json.mkObj [("kind", .str "set"), ("values", array values)]
  | .seq values => Json.mkObj [
      ("kind", .str "seq"), ("values", array (values.map encodeLiteral))]
  | .tuple values => Json.mkObj [
      ("kind", .str "tuple"), ("values", array (values.map encodeLiteral))]
  | .record fields =>
      let fields := fields.map fun field =>
        (field.1, Json.mkObj [("name", .str field.1), ("value", encodeLiteral field.2)])
      let fields := fields.mergeSort fun a b => a.1 ≤ b.1
      Json.mkObj [("fields", array (fields.map Prod.snd)),
        ("kind", .str "record")]
  | .map entries =>
      let entries := entries.map fun entry =>
        let key := encodeLiteral entry.1
        (Json.compress key, Json.mkObj [("key", key), ("value", encodeLiteral entry.2)])
      let entries := entries.mergeSort fun a b => a.1 ≤ b.1
      Json.mkObj [("entries", array (entries.map Prod.snd)),
        ("kind", .str "map")]
  | .variant tag payload => Json.mkObj [
      ("kind", .str "variant"), ("payload", encodeLiteral payload), ("tag", .str tag)]

private partial def decodeLiteralWithFuel (fuel : Nat) (context : String)
    (json : Json) : DecodeResult CanonicalItfLiteral := do
  if fuel == 0 then fail context "literal nesting exceeds decoder limit"
  else
    let initial ← objectFields context json
    let kind ← decodeString (context ++ ".kind") (← required context initial "kind")
    let recur := decodeLiteralWithFuel (fuel - 1)
    match kind with
    | "int" =>
        let fields ← checkObject context ["kind", "value"] ["kind", "value"] json
        return .int (← decodeIntString (context ++ ".value") (← required context fields "value"))
    | "bool" =>
        let fields ← checkObject context ["kind", "value"] ["kind", "value"] json
        return .bool (← decodeBool (context ++ ".value") (← required context fields "value"))
    | "str" =>
        let fields ← checkObject context ["kind", "value"] ["kind", "value"] json
        return .str (← decodeString (context ++ ".value") (← required context fields "value"))
    | "null" =>
        let _ ← checkObject context ["kind"] ["kind"] json
        return .null
    | "set" | "seq" | "tuple" =>
        let fields ← checkObject context ["kind", "values"] ["kind", "values"] json
        let values ← decodeArray (context ++ ".values") (recur (context ++ ".values[]"))
          (← required context fields "values")
        if kind == "set" then return .set values
        else if kind == "seq" then return .seq values
        else return .tuple values
    | "record" =>
        let fields ← checkObject context ["kind", "fields"] ["kind", "fields"] json
        let values ← decodeArray (context ++ ".fields") (fun value => do
          let item ← checkObject (context ++ ".fields[]") ["name", "value"]
            ["name", "value"] value
          let name ← decodeString (context ++ ".fields[].name") (← required context item "name")
          let payload ← recur (context ++ ".fields[].value") (← required context item "value")
          return (name, payload)) (← required context fields "fields")
        return .record values
    | "map" =>
        let fields ← checkObject context ["kind", "entries"] ["kind", "entries"] json
        let values ← decodeArray (context ++ ".entries") (fun value => do
          let item ← checkObject (context ++ ".entries[]") ["key", "value"]
            ["key", "value"] value
          let key ← recur (context ++ ".entries[].key") (← required context item "key")
          let payload ← recur (context ++ ".entries[].value") (← required context item "value")
          return (key, payload)) (← required context fields "entries")
        return .map values
    | "variant" =>
        let fields ← checkObject context ["kind", "tag", "payload"]
          ["kind", "tag", "payload"] json
        return .variant
          (← decodeString (context ++ ".tag") (← required context fields "tag"))
          (← recur (context ++ ".payload") (← required context fields "payload"))
    | other => fail (context ++ ".kind") s!"unknown canonical literal '{other}'"

private def encodePathRoot : PathRoot → Json
  | .initialState => .str "initialState"
  | .stepParameters => .str "stepParameters"

private def decodePathRoot (context : String) (json : Json) : DecodeResult PathRoot := do
  match ← decodeString context json with
  | "initialState" => return .initialState
  | "stepParameters" => return .stepParameters
  | other => fail context s!"unknown path root '{other}'"

private def encodePathSegment : PathSegment → Json
  | .field name => Json.mkObj [("field", .str name)]
  | .index index => Json.mkObj [("index", .num index)]
  | .mapKey key => Json.mkObj [("mapKey", encodeLiteral key)]
  | .variantValue tag => Json.mkObj [("variantValue", .str tag)]

private def decodePathSegment (context : String) (json : Json) : DecodeResult PathSegment := do
  let fields ← objectFields context json
  if fields.length != 1 then fail context "path segment must contain exactly one selector"
  else
    match fields with
    | [(name, value)] =>
        if name == "field" then
          return .field (← decodeString (context ++ ".field") value)
        else if name == "index" then
          return .index (← decodeNat (context ++ ".index") value)
        else if name == "mapKey" then
          return .mapKey (← decodeLiteralWithFuel 128 (context ++ ".mapKey") value)
        else if name == "variantValue" then
          return .variantValue (← decodeString (context ++ ".variantValue") value)
        else fail context s!"unknown path selector '{name}'"
    | _ => fail context "invalid path segment"

private def encodePath (path : List PathSegment) : Json :=
  array (path.map encodePathSegment)

private def decodePath (context : String) (json : Json) : DecodeResult (List PathSegment) :=
  decodeArray context (decodePathSegment (context ++ "[]")) json

/-! ## Companion contract -/

private def encodeContractInput (input : ContractInput) : Json :=
  Json.mkObj ([
    ("from", Json.mkObj [
      ("path", encodePath input.path), ("root", encodePathRoot input.fromRoot)]),
    ("id", .str input.id)
  ] ++ optionalField "expectedType" (input.expectedType.map encodeModelType))

private def encodeContractAction (action : ContractAction) : Json :=
  let inputs := sortByString (·.id) action.inputs
  Json.mkObj [
    ("id", .str action.id),
    ("inputs", array (inputs.map encodeContractInput)),
    ("wireAction", .str action.wireAction),
    ("wireAliases", strings (sortStrings action.wireAliases))]

private def encodeProvenance : ObservationProvenance → Json
  | .implementation => .str "implementation"
  | .oracle => .str "oracle"
  | .derived => .str "derived"

private def decodeProvenance (context : String) (json : Json) :
    DecodeResult ObservationProvenance := do
  match ← decodeString context json with
  | "implementation" => return .implementation
  | "oracle" => return .oracle
  | "derived" => return .derived
  | other => fail context s!"unknown observation provenance '{other}'"

private def encodeContractObservation (observation : ContractObservation) : Json :=
  Json.mkObj ([
    ("id", .str observation.id),
    ("provenance", encodeProvenance observation.provenance),
    ("wireName", .str observation.wireName)
  ] ++ optionalField "expectedType" (observation.expectedType.map encodeModelType))

/-- Canonically encode a version-1 companion contract. -/
def encodeContract (contract : ContractV1) : Json :=
  let initializers := sortByString (·.id) contract.initializers
  let actions := sortByString (·.id) contract.actions
  let observations := sortByString (·.id) contract.observations
  Json.mkObj [
    ("actions", array (actions.map encodeContractAction)),
    ("initializers", array (initializers.map encodeContractAction)),
    ("interfaceVersion", .str contract.interfaceVersion),
    ("model", Json.mkObj [
      ("module", .str contract.model.moduleName), ("source", .str contract.model.source)]),
    ("observations", array (observations.map encodeContractObservation)),
    ("schema", .str contract.schema),
    ("wire", Json.mkObj [
      ("actionVariable", .str contract.wire.actionVariable),
      ("parameterVariable", match contract.wire.parameterVariable with
        | some value => .str value | none => .null)])]

private def decodeOptionalType (context : String) (fields : Fields) :
    DecodeResult (Option ModelType) :=
  match optional fields "expectedType" with
  | none => .ok none
  | some value => some <$> decodeModelTypeWithFuel maxStructuralTypeDepthV1
      (context ++ ".expectedType") value

private def decodeContractInput (context : String) (json : Json) : DecodeResult ContractInput := do
  let fields ← checkObject context ["id", "from", "expectedType"] ["id", "from"] json
  let id ← decodeString (context ++ ".id") (← required context fields "id")
  let fromJson ← required context fields "from"
  let fromFields ← checkObject (context ++ ".from") ["root", "path"] ["root", "path"] fromJson
  let root ← decodePathRoot (context ++ ".from.root") (← required context fromFields "root")
  let path ← decodePath (context ++ ".from.path") (← required context fromFields "path")
  return {
    id := id
    fromRoot := root
    path := path
    expectedType := ← decodeOptionalType context fields
  }

private def decodeContractAction (context : String) (json : Json) : DecodeResult ContractAction := do
  let fields ← checkObject context ["id", "wireAction", "wireAliases", "inputs"]
    ["id", "wireAction", "wireAliases", "inputs"] json
  return {
    id := ← decodeString (context ++ ".id") (← required context fields "id")
    wireAction := ← decodeString (context ++ ".wireAction")
      (← required context fields "wireAction")
    wireAliases := ← decodeStringArray (context ++ ".wireAliases")
      (← required context fields "wireAliases")
    inputs := ← decodeArray (context ++ ".inputs")
      (decodeContractInput (context ++ ".inputs[]")) (← required context fields "inputs")
  }

private def decodeContractObservation (context : String) (json : Json) :
    DecodeResult ContractObservation := do
  let fields ← checkObject context ["id", "wireName", "provenance", "expectedType"]
    ["id", "wireName", "provenance"] json
  return {
    id := ← decodeString (context ++ ".id") (← required context fields "id")
    wireName := ← decodeString (context ++ ".wireName")
      (← required context fields "wireName")
    provenance := ← decodeProvenance (context ++ ".provenance")
      (← required context fields "provenance")
    expectedType := ← decodeOptionalType context fields
  }

/-- Strictly decode a parsed version-1 companion contract. Call
`parseContractBytes` for untrusted raw input so duplicate keys are observable. -/
def decodeContract (json : Json) : DecodeResult ContractV1 := do
  let context := "contract"
  let fields ← checkObject context
    ["schema", "interfaceVersion", "model", "wire", "initializers", "actions", "observations"]
    ["schema", "interfaceVersion", "model", "wire", "initializers", "actions", "observations"] json
  let schema ← decodeString "contract.schema" (← required context fields "schema")
  if schema != contractSchemaV1 then fail "contract.schema" s!"expected '{contractSchemaV1}'"
  let modelJson ← required context fields "model"
  let modelFields ← checkObject "contract.model" ["module", "source"] ["module", "source"] modelJson
  let wireJson ← required context fields "wire"
  let wireFields ← checkObject "contract.wire" ["actionVariable", "parameterVariable"]
    ["actionVariable", "parameterVariable"] wireJson
  let parameterVariable ← match optional wireFields "parameterVariable" with
    | none => .ok none
    | some value => some <$> decodeString "contract.wire.parameterVariable" value
  return {
    schema := schema
    interfaceVersion := ← decodeString "contract.interfaceVersion"
      (← required context fields "interfaceVersion")
    model := {
      moduleName := ← decodeString "contract.model.module" (← required context modelFields "module")
      source := ← decodeString "contract.model.source" (← required context modelFields "source")
    }
    wire := {
      actionVariable := ← decodeString "contract.wire.actionVariable"
        (← required context wireFields "actionVariable")
      parameterVariable := parameterVariable
    }
    initializers := ← decodeArray "contract.initializers"
      (decodeContractAction "contract.initializers[]") (← required context fields "initializers")
    actions := ← decodeArray "contract.actions" (decodeContractAction "contract.actions[]")
      (← required context fields "actions")
    observations := ← decodeArray "contract.observations"
      (decodeContractObservation "contract.observations[]")
      (← required context fields "observations")
  }

/-! ## Resolved descriptor and lock -/

private def encodeOrigin : EvidenceOrigin → Json
  | .apalacheTypecheck => .str "apalacheTypecheck"
  | .itfVarTypes => .str "itfVarTypes"
  | .contractAssertion => .str "contractAssertion"

private def originName : EvidenceOrigin → String
  | .apalacheTypecheck => "apalacheTypecheck"
  | .itfVarTypes => "itfVarTypes"
  | .contractAssertion => "contractAssertion"

private def decodeOrigin (context : String) (json : Json) : DecodeResult EvidenceOrigin := do
  match ← decodeString context json with
  | "apalacheTypecheck" => return .apalacheTypecheck
  | "itfVarTypes" => return .itfVarTypes
  | "contractAssertion" => return .contractAssertion
  | other => fail context s!"unknown evidence origin '{other}'"

private def encodeActionPhase : ActionPhase → Json
  | .initialize => .str "initialize"
  | .transition => .str "transition"

private def decodeActionPhase (context : String) (json : Json) : DecodeResult ActionPhase := do
  match ← decodeString context json with
  | "initialize" => return .initialize
  | "transition" => return .transition
  | other => fail context s!"unknown action phase '{other}'"

private def encodeResolvedInput (includeTypeOrigins : Bool)
    (input : ResolvedInput) : Json :=
  Json.mkObj ([
    ("from", Json.mkObj [
      ("path", encodePath input.projection.path),
      ("root", encodePathRoot input.projection.root)]),
    ("id", .str input.id),
    ("type", encodeModelType input.projection.type)] ++
    if includeTypeOrigins then
      [("typeOrigins", strings
        ((sortByString originName input.typeOrigins).map originName))]
    else [])

private def encodeResolvedAction (includeTypeOrigins : Bool)
    (action : ResolvedAction) : Json :=
  let inputs := sortByString (·.id) action.inputs
  Json.mkObj [
    ("id", .str action.id),
    ("inputs", array (inputs.map (encodeResolvedInput includeTypeOrigins))),
    ("phase", encodeActionPhase action.phase),
    ("wireAction", .str action.wireAction),
    ("wireAliases", strings (sortStrings action.wireAliases))]

private def encodeResolvedObservation (includeTypeOrigins : Bool)
    (observation : ResolvedObservation) : Json :=
  Json.mkObj ([
    ("id", .str observation.id),
    ("provenance", encodeProvenance observation.provenance),
    ("type", encodeModelType observation.type),
    ("wireName", .str observation.wireName)] ++
    if includeTypeOrigins then
      [("typeOrigins", strings
        ((sortByString originName observation.typeOrigins).map originName))]
    else [])

private def encodeRunProfile (profile : ResolvedRunProfile) : Json :=
  Json.mkObj [
    ("actionVariable", .str profile.actionVariable),
    ("configuredParamVar", match profile.configuredParamVar with
      | some value => .str value | none => .null),
    ("effectiveParamVars", strings (sortStrings profile.effectiveParamVars)),
    ("itfParamVars", strings (sortStrings profile.itfParamVars))]

private def encodeSemanticDescriptorWithOrigins
    (includeTypeOrigins : Bool) (descriptor : SemanticDescriptor) : Json :=
  let initializers := sortByString (·.id) descriptor.initializers
  let actions := sortByString (·.id) descriptor.actions
  let observations := sortByString (·.id) descriptor.observations
  Json.mkObj [
    ("actions", array (actions.map
      (encodeResolvedAction includeTypeOrigins))),
    ("comparisonPolicyVersion", .str descriptor.comparisonPolicyVersion),
    ("initializers", array (initializers.map
      (encodeResolvedAction includeTypeOrigins))),
    ("interfaceVersion", .str descriptor.interfaceVersion),
    ("model", Json.mkObj [("module", .str descriptor.modelModule)]),
    ("observations", array (observations.map
      (encodeResolvedObservation includeTypeOrigins))),
    ("resolverSemanticsVersion", .str descriptor.resolverSemanticsVersion),
    ("runProfile", encodeRunProfile descriptor.runProfile),
    ("schema", .str descriptor.schema)]

/-- Canonically encode the distributable semantic descriptor. Evidence origins
are intentionally absent: the wire/cache artifact is exactly the semantic
identity projection. Checked-in locks retain origins separately. -/
def encodeSemanticDescriptor (descriptor : SemanticDescriptor) : Json :=
  encodeSemanticDescriptorWithOrigins false descriptor

/-- Encode only fields that participate in semantic identity. Evidence origins
explain how a type was established; changing them cannot change an adapter's
required behavior. -/
def encodeSemanticIdentityDescriptor (descriptor : SemanticDescriptor) : Json :=
  encodeSemanticDescriptorWithOrigins false descriptor

private def decodeOrigins (context : String) (json : Json) : DecodeResult (List EvidenceOrigin) :=
  decodeArray context (decodeOrigin (context ++ "[]")) json

private def decodeResolvedInput (includeTypeOrigins : Bool)
    (context : String) (json : Json) : DecodeResult ResolvedInput := do
  let allowed := if includeTypeOrigins then
    ["id", "from", "type", "typeOrigins"] else ["id", "from", "type"]
  let fields ← checkObject context allowed allowed json
  let fromJson ← required context fields "from"
  let fromFields ← checkObject (context ++ ".from") ["root", "path"] ["root", "path"] fromJson
  let root ← decodePathRoot (context ++ ".from.root") (← required context fromFields "root")
  let path ← decodePath (context ++ ".from.path") (← required context fromFields "path")
  let type ← decodeModelTypeWithFuel maxStructuralTypeDepthV1
    (context ++ ".type") (← required context fields "type")
  let typeOrigins ← if includeTypeOrigins then
      decodeOrigins (context ++ ".typeOrigins")
        (← required context fields "typeOrigins")
    else pure []
  return {
    id := ← decodeString (context ++ ".id") (← required context fields "id")
    projection := { root := root, path := path, type := type }
    typeOrigins := typeOrigins
  }

private def decodeResolvedAction (includeTypeOrigins : Bool)
    (context : String) (json : Json) : DecodeResult ResolvedAction := do
  let fields ← checkObject context ["id", "phase", "wireAction", "wireAliases", "inputs"]
    ["id", "phase", "wireAction", "wireAliases", "inputs"] json
  return {
    id := ← decodeString (context ++ ".id") (← required context fields "id")
    phase := ← decodeActionPhase (context ++ ".phase") (← required context fields "phase")
    wireAction := ← decodeString (context ++ ".wireAction")
      (← required context fields "wireAction")
    wireAliases := ← decodeStringArray (context ++ ".wireAliases")
      (← required context fields "wireAliases")
    inputs := ← decodeArray (context ++ ".inputs")
      (decodeResolvedInput includeTypeOrigins (context ++ ".inputs[]"))
      (← required context fields "inputs")
  }

private def decodeResolvedObservation (includeTypeOrigins : Bool)
    (context : String) (json : Json) :
    DecodeResult ResolvedObservation := do
  let allowed := if includeTypeOrigins then
    ["id", "wireName", "type", "provenance", "typeOrigins"]
    else ["id", "wireName", "type", "provenance"]
  let fields ← checkObject context allowed allowed json
  let typeOrigins ← if includeTypeOrigins then
      decodeOrigins (context ++ ".typeOrigins")
        (← required context fields "typeOrigins")
    else pure []
  return {
    id := ← decodeString (context ++ ".id") (← required context fields "id")
    wireName := ← decodeString (context ++ ".wireName")
      (← required context fields "wireName")
    type := ← decodeModelTypeWithFuel maxStructuralTypeDepthV1
      (context ++ ".type") (← required context fields "type")
    provenance := ← decodeProvenance (context ++ ".provenance")
      (← required context fields "provenance")
    typeOrigins := typeOrigins
  }

private def decodeRunProfile (context : String) (json : Json) : DecodeResult ResolvedRunProfile := do
  let fields ← checkObject context
    ["actionVariable", "configuredParamVar", "itfParamVars", "effectiveParamVars"]
    ["actionVariable", "configuredParamVar", "itfParamVars", "effectiveParamVars"] json
  let configured ← match optional fields "configuredParamVar" with
    | none => .ok none
    | some value => some <$> decodeString (context ++ ".configuredParamVar") value
  return {
    actionVariable := ← decodeString (context ++ ".actionVariable")
      (← required context fields "actionVariable")
    configuredParamVar := configured
    itfParamVars := ← decodeStringArray (context ++ ".itfParamVars")
      (← required context fields "itfParamVars")
    effectiveParamVars := ← decodeStringArray (context ++ ".effectiveParamVars")
      (← required context fields "effectiveParamVars")
  }

private def decodeSemanticDescriptorWithOrigins (includeTypeOrigins : Bool)
    (json : Json) : DecodeResult SemanticDescriptor := do
  let context := "descriptor"
  let fields ← checkObject context
    ["schema", "interfaceVersion", "model", "resolverSemanticsVersion",
      "comparisonPolicyVersion", "runProfile", "initializers", "actions", "observations"]
    ["schema", "interfaceVersion", "model", "resolverSemanticsVersion",
      "comparisonPolicyVersion", "runProfile", "initializers", "actions", "observations"] json
  let schema ← decodeString "descriptor.schema" (← required context fields "schema")
  if schema != descriptorSchemaV1 then
    fail "descriptor.schema" s!"expected '{descriptorSchemaV1}'"
  let modelJson ← required context fields "model"
  let model ← checkObject "descriptor.model" ["module"] ["module"] modelJson
  let descriptor : SemanticDescriptor := {
    schema := schema
    interfaceVersion := ← decodeString "descriptor.interfaceVersion"
      (← required context fields "interfaceVersion")
    modelModule := ← decodeString "descriptor.model.module" (← required context model "module")
    resolverSemanticsVersion := ← decodeString "descriptor.resolverSemanticsVersion"
      (← required context fields "resolverSemanticsVersion")
    comparisonPolicyVersion := ← decodeString "descriptor.comparisonPolicyVersion"
      (← required context fields "comparisonPolicyVersion")
    runProfile := ← decodeRunProfile "descriptor.runProfile" (← required context fields "runProfile")
    initializers := ← decodeArray "descriptor.initializers"
      (decodeResolvedAction includeTypeOrigins "descriptor.initializers[]")
      (← required context fields "initializers")
    actions := ← decodeArray "descriptor.actions"
      (decodeResolvedAction includeTypeOrigins "descriptor.actions[]")
      (← required context fields "actions")
    observations := ← decodeArray "descriptor.observations"
      (decodeResolvedObservation includeTypeOrigins "descriptor.observations[]")
      (← required context fields "observations")
  }
  if !semanticDescriptorWellFormedV1 descriptor then
    fail context "descriptor violates version-1 semantic invariants"
  return descriptor

/-- Strictly decode a parsed distributable semantic descriptor. The runtime
descriptor is the origin-free semantic projection; decoded origin lists are
therefore empty. -/
def decodeSemanticDescriptor (json : Json) : DecodeResult SemanticDescriptor :=
  decodeSemanticDescriptorWithOrigins false json

private def encodeSourceDigest (source : SourceDigest) : Json :=
  Json.mkObj [
    ("module", .str source.moduleName), ("path", .str source.logicalPath),
    ("sha256", .str source.contentSha256)]

/-- Canonically encode the provenance projection used by the provenance digest. -/
def encodeLockProvenance (provenance : LockProvenance) : Json :=
  let sources := provenance.sources.mergeSort fun a b =>
    if a.moduleName == b.moduleName then a.logicalPath ≤ b.logicalPath
    else a.moduleName ≤ b.moduleName
  Json.mkObj [
    ("compilerVersion", .str provenance.compilerVersion),
    ("contractSha256", .str provenance.contractSha256),
    ("evidenceSha256", .str provenance.evidenceSha256),
    ("sources", array (sources.map encodeSourceDigest))]

/-- Canonically encode a complete checked-in lock. Evidence-origin annotations
remain compiler diagnostics only: they are neither interface semantics nor an
independently authenticated lock projection. -/
def encodeLock (lock : LockedModelInterface) : Json :=
  let descriptor := lock.semanticDescriptor
  match encodeSemanticDescriptorWithOrigins false
      { descriptor with schema := lockSchemaV1 } with
  | .obj fields => Json.mkObj (fields.toList ++ [
      ("provenance", encodeLockProvenance lock.provenance),
      ("provenanceDigest", .str lock.provenanceDigest),
      ("semanticDigest", .str lock.semanticDigest)])
  | other => other

private def isLowerHex (character : Char) : Bool :=
  ('0'.toNat ≤ character.toNat && character.toNat ≤ '9'.toNat) ||
  ('a'.toNat ≤ character.toNat && character.toNat ≤ 'f'.toNat)

private def decodeDigestHex (context : String) (json : Json) : DecodeResult String := do
  let digest ← decodeString context json
  if digest.length == 64 && digest.toList.all isLowerHex then return digest
  else fail context "64 lowercase hexadecimal characters expected"

private def decodeSourceDigest (context : String) (json : Json) : DecodeResult SourceDigest := do
  let fields ← checkObject context ["module", "path", "sha256"]
    ["module", "path", "sha256"] json
  return {
    moduleName := ← decodeString (context ++ ".module") (← required context fields "module")
    logicalPath := ← decodeString (context ++ ".path") (← required context fields "path")
    contentSha256 := ← decodeDigestHex (context ++ ".sha256") (← required context fields "sha256")
  }

/-- Strictly decode the provenance projection of a lock. -/
def decodeLockProvenance (json : Json) : DecodeResult LockProvenance := do
  let context := "lock.provenance"
  let fields ← checkObject context ["compilerVersion", "contractSha256", "evidenceSha256", "sources"]
    ["compilerVersion", "contractSha256", "evidenceSha256", "sources"] json
  return {
    compilerVersion := ← decodeString (context ++ ".compilerVersion")
      (← required context fields "compilerVersion")
    contractSha256 := ← decodeDigestHex (context ++ ".contractSha256")
      (← required context fields "contractSha256")
    evidenceSha256 := ← decodeDigestHex (context ++ ".evidenceSha256")
      (← required context fields "evidenceSha256")
    sources := ← decodeArray (context ++ ".sources")
      (decodeSourceDigest (context ++ ".sources[]")) (← required context fields "sources")
  }

/-- Strictly decode a complete checked-in lock. The lock JSON uses the lock
schema, while its in-memory `SemanticDescriptor` retains the descriptor schema
used for semantic hashing and runtime distribution. -/
def decodeLock (json : Json) : DecodeResult LockedModelInterface := do
  let context := "lock"
  let allowed := ["schema", "interfaceVersion", "model", "resolverSemanticsVersion",
    "comparisonPolicyVersion", "runProfile", "initializers", "actions", "observations",
    "semanticDigest", "provenanceDigest", "provenance"]
  let fields ← checkObject context allowed allowed json
  let schema ← decodeString "lock.schema" (← required context fields "schema")
  if schema != lockSchemaV1 then fail "lock.schema" s!"expected '{lockSchemaV1}'"
  let descriptorFields := fields.filter fun field =>
    field.1 != "semanticDigest" && field.1 != "provenanceDigest" && field.1 != "provenance"
  let descriptorJson := Json.mkObj (("schema", .str descriptorSchemaV1) ::
    descriptorFields.filter fun field => field.1 != "schema")
  let descriptor ← decodeSemanticDescriptorWithOrigins false descriptorJson
  return {
    toSemanticDescriptor := descriptor
    semanticDigest := ← decodeDigestHex "lock.semanticDigest"
      (← required context fields "semanticDigest")
    provenanceDigest := ← decodeDigestHex "lock.provenanceDigest"
      (← required context fields "provenanceDigest")
    provenance := ← decodeLockProvenance (← required context fields "provenance")
  }

/-! ## Diagnostics -/

private def encodeSeverity : Severity → Json
  | .error => .str "error"
  | .warning => .str "warning"
  | .obligation => .str "obligation"

private def encodeLocation (location : SourceLocation) : Json :=
  Json.mkObj ([ ("source", .str location.source) ] ++
    optionalField "pointer" (location.pointer.map Json.str) ++
    optionalField "line" (location.line.map Json.num) ++
    optionalField "column" (location.column.map Json.num))

/-- Canonically encode a structured compiler diagnostic. -/
def encodeDiagnostic (diagnostic : Diagnostic) : Json :=
  let related := normalizeDiagnosticRelated diagnostic.related
  let arguments := normalizeDiagnosticArguments diagnostic.arguments
  Json.mkObj [
    ("arguments", array (arguments.map fun argument => Json.mkObj [
      ("name", .str argument.1), ("value", .str argument.2)])),
    ("code", .str diagnostic.code),
    ("primary", encodeLocation diagnostic.primary),
    ("related", array (related.map encodeLocation)),
    ("severity", encodeSeverity diagnostic.severity),
    ("stage", .str diagnostic.stage),
    ("subject", Json.mkObj ([ ("kind", .str diagnostic.subject.kind) ] ++
      optionalField "stableId" (diagnostic.subject.stableId.map Json.str)))]

/-- Canonically encode a complete structured-diagnostics artifact. Diagnostic
order is normalized before encoding so callers cannot accidentally expose
producer traversal order. -/
def encodeDiagnostics (diagnostics : List Diagnostic) : Json :=
  .arr ((sortDiagnostics diagnostics).map encodeDiagnostic).toArray

/-! ## Canonical rendering and raw strict entry points -/

/-- Compact canonical JSON without a trailing newline. -/
def canonicalString (json : Json) : String :=
  Json.compress json

/-- Compact canonical UTF-8 JSON without a trailing newline. -/
def canonicalBytes (json : Json) : ByteArray :=
  (canonicalString json).toUTF8

/-- Canonical semantic descriptor bytes used as the domain-separated semantic
digest payload. -/
def canonicalSemanticDescriptorBytes (descriptor : SemanticDescriptor) : ByteArray :=
  canonicalBytes (encodeSemanticIdentityDescriptor descriptor)

/-- Canonical provenance bytes used as the domain-separated provenance digest
payload. -/
def canonicalProvenanceBytes (provenance : LockProvenance) : ByteArray :=
  canonicalBytes (encodeLockProvenance provenance)

/-- Canonical artifact bytes with exactly one trailing LF. -/
def canonicalFileBytes (json : Json) : ByteArray :=
  (canonicalString json ++ "\n").toUTF8

/-- Strictly parse and decode a raw companion contract. -/
def parseContractBytes (raw : ByteArray)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) : DecodeResult ContractV1 := do
  let json ← (StrictJson.parseBytes raw limits).mapError toString
  decodeContract json

/-- Strictly parse and decode a companion contract string. -/
def parseContractString (raw : String)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) : DecodeResult ContractV1 :=
  parseContractBytes raw.toUTF8 limits

/-- Strictly parse and decode a raw semantic descriptor. -/
def parseDescriptorBytes (raw : ByteArray)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) : DecodeResult SemanticDescriptor := do
  let json ← (StrictJson.parseBytes raw limits).mapError toString
  decodeSemanticDescriptor json

/-- Strictly parse and decode a semantic descriptor string. -/
def parseDescriptorString (raw : String)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) : DecodeResult SemanticDescriptor :=
  parseDescriptorBytes raw.toUTF8 limits

/-- Strictly parse and decode a complete checked-in lock. -/
def parseLockBytes (raw : ByteArray)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) : DecodeResult LockedModelInterface := do
  let json ← (StrictJson.parseBytes raw limits).mapError toString
  decodeLock json

/-- Strictly parse and decode a complete checked-in lock string. -/
def parseLockString (raw : String)
    (limits : StrictJson.Limits := StrictJson.defaultLimits) : DecodeResult LockedModelInterface :=
  parseLockBytes raw.toUTF8 limits

end Codec.ModelInterfaceJson
