import Core.ModelInterface.Resolve
import Lean.Data.Json

/-! Pure, bounded projection of strict ITF JSON without `Core.Value` decoding. -/

namespace Core.ModelInterface

open Lean

def traceProjectionSchemaV1 : String := "mirrors.model-interface-trace-projection/v1"
def traceProjectionReceiptSchemaV1 : String :=
  "mirrors.model-interface-trace-projection-receipt/v1"
def traceProjectionResultSchemaV1 : String :=
  "mirrors.model-interface-trace-projection-result/v1"

def maxProjectionGroupsV1 : Nat := 32
def maxProjectionFieldsV1 : Nat := 128
def maxProjectionDomainSizeV1 : Nat := 4096
/-- Bounds allocation/copy work before projected records are constructed. -/
def maxProjectionWorkNodesV1 : Nat := 250000
/-- Shared cap for the canonical projected ITF artifact. -/
def maxProjectedTraceArtifactBytesV1 : Nat := 16 * 1024 * 1024

structure IntDomain where
  lowerInclusive : String
  upperInclusive : String
  deriving Repr, DecidableEq

structure ZipIntFunctionField where
  name : String
  sourceVariable : String
  deriving Repr, DecidableEq

structure ZipIntFunctions where
  outputWireName : String
  domain : IntDomain
  fields : List ZipIntFunctionField
  deriving Repr, DecidableEq

structure TraceProjectionPlan where
  schema : String := traceProjectionSchemaV1
  zipIntFunctions : List ZipIntFunctions
  exactCopyVariables : List String
  deriving Repr, DecidableEq

structure TraceProjectionContext where
  rawVariables : List String
  sourceVariables : List String
  sourceTypes : List (String × ModelType)
  deriving Repr

structure TraceProjectionReceipt where
  schema : String := traceProjectionReceiptSchemaV1
  sourceSha256 : String
  rawSha256 : String
  planSha256 : String
  outputSha256 : String
  inputVariables : List String
  outputVariables : List String
  deriving Repr, DecidableEq

structure TraceProjectionResult where
  projectedTrace : Json
  receipt : TraceProjectionReceipt

private def canonicalInt? (value : String) : Option Int :=
  value.toInt?.bind fun parsed =>
    if toString parsed == value then some parsed else none

private def domainBounds (domain : IntDomain) : Except String (Int × Int × Nat) := do
  let some lower := canonicalInt? domain.lowerInclusive
    | throw "projection domain lower bound is not a canonical decimal integer"
  let some upper := canonicalInt? domain.upperInclusive
    | throw "projection domain upper bound is not a canonical decimal integer"
  if upper < lower then throw "projection domain upper bound precedes lower bound"
  let span := upper - lower + 1
  let size := span.toNat
  if size > maxProjectionDomainSizeV1 then
    throw s!"projection domain exceeds limit {maxProjectionDomainSizeV1}"
  return (lower, upper, size)

private def sameSet (left right : List String) : Bool :=
  sortStrings (stableUniqueStrings left) == sortStrings (stableUniqueStrings right)

private def reservedWireName (name : String) : Bool :=
  name.startsWith "#" || ["__proto__", "constructor", "prototype"].contains name

mutual
  private def portableProjectedType : ModelType → Bool
    | .int | .bool | .str | .null => true
    | .set type | .seq type => portableProjectedType type
    | .tuple types => portableProjectedTypes types
    | .record fields =>
        (duplicateStrings (fields.map (·.wireName))).isEmpty &&
          portableProjectedFields fields
    | .map .str value => portableProjectedType value
    | .map _ _ | .variant _ | .opaqueItf _ => false

  private def portableProjectedTypes : List ModelType → Bool
    | [] => true
    | type :: rest => portableProjectedType type && portableProjectedTypes rest

  private def portableProjectedFields : List ModelField → Bool
    | [] => true
    | field :: rest =>
        !reservedWireName field.wireName && portableProjectedType field.type &&
          portableProjectedFields rest
end

def outputVariables (plan : TraceProjectionPlan) : List String :=
  sortStrings (plan.exactCopyVariables ++ plan.zipIntFunctions.map (·.outputWireName))

/-- Check exact consumption, collisions, limits, domains, and `Map[Int,T]`
source types before any state is transformed. -/
def validateTraceProjectionPlan (plan : TraceProjectionPlan)
    (context : TraceProjectionContext) : Except String Unit := do
  if plan.schema != traceProjectionSchemaV1 then throw "unsupported trace projection schema"
  if plan.zipIntFunctions.length > maxProjectionGroupsV1 then
    throw s!"projection group count exceeds limit {maxProjectionGroupsV1}"
  let sourceTypeNames := context.sourceTypes.map Prod.fst
  if !(duplicateStrings context.rawVariables).isEmpty ||
      !(duplicateStrings context.sourceVariables).isEmpty ||
      !(duplicateStrings sourceTypeNames).isEmpty then
    throw "projection context variable names contain duplicates"
  if !sameSet context.sourceVariables sourceTypeNames then
    throw "projection source variables and source types differ"
  let projectedSources := plan.zipIntFunctions.flatMap fun group =>
    group.fields.map (·.sourceVariable)
  let consumed := plan.exactCopyVariables ++ projectedSources
  if !(duplicateStrings consumed).isEmpty then
    throw "projection consumes a variable more than once"
  if !sameSet consumed context.rawVariables || !sameSet consumed context.sourceVariables then
    throw "projection does not consume the raw and source variable sets exactly"
  let outputs := plan.zipIntFunctions.map (·.outputWireName)
  if !(duplicateStrings (plan.exactCopyVariables ++ outputs)).isEmpty then
    throw "projection output variable collision"
  for group in plan.zipIntFunctions do
    if group.outputWireName.isEmpty || reservedWireName group.outputWireName ||
        group.outputWireName.toUTF8.size > maxStableNameBytesV1 then
      throw "projection output wire name is empty or too long"
    if group.fields.isEmpty || group.fields.length > maxProjectionFieldsV1 then
      throw s!"projection field count must be within 1..{maxProjectionFieldsV1}"
    if !(duplicateStrings (group.fields.map (·.name))).isEmpty then
      throw "projection record field collision"
    let _ ← domainBounds group.domain
    for field in group.fields do
      if field.name.isEmpty || reservedWireName field.name ||
          field.name.toUTF8.size > maxStableNameBytesV1 then
        throw "projection record field name is empty or too long"
      match List.lookup field.sourceVariable context.sourceTypes with
      | some (.map .int value) =>
          if portableProjectedType value then pure ()
          else throw s!"projection source '{field.sourceVariable}' has a nonportable value type"
      | some _ => throw s!"projection source '{field.sourceVariable}' must have type Map[Int,T]"
      | none => throw s!"projection source '{field.sourceVariable}' has no type"

private def requiredField (context name : String) (fields : List (String × Json)) :
    Except String Json :=
  match List.lookup name fields with
  | some value => .ok value
  | none => .error s!"{context}: missing '{name}'"

private def stringArray (context : String) : Json → Except String (List String)
  | .arr values => values.toList.mapM fun
      | .str value => pure value
      | _ => throw s!"{context}: expected string array"
  | _ => throw s!"{context}: expected array"

private def intKey : Json → Except String String
  | .obj fields => do
      if fields.size != 1 then throw "ITF integer key must contain only #bigint"
      let .str value ← requiredField "ITF integer key" "#bigint" fields.toList
        | throw "ITF integer key #bigint must be a string"
      if canonicalInt? value |>.isNone then throw "ITF integer key is not canonical decimal"
      return value
  | _ => throw "ITF integer key object expected"

private def intMapEntries (variableName : String) : Json → Except String (List (String × Json))
  | .obj fields => do
      if fields.size != 1 then throw s!"{variableName}: integer map must contain only #map"
      let .arr entries ← requiredField variableName "#map" fields.toList
        | throw s!"{variableName}.#map: expected array"
      let decoded ← entries.toList.mapM fun
        | .arr pair =>
            if pair.size != 2 then throw s!"{variableName}.#map[]: expected key/value pair"
            else return (← intKey pair[0]!, pair[1]!)
        | _ => throw s!"{variableName}.#map[]: expected pair array"
      if !(duplicateStrings (decoded.map Prod.fst)).isEmpty then
        throw s!"{variableName}: duplicate integer map key"
      return decoded
  | _ => throw s!"{variableName}: ITF #map object expected"

private def domainKeys (domain : IntDomain) : Except String (List String) := do
  let (lower, _, size) ← domainBounds domain
  return (List.range size).map fun offset => toString (lower + Int.ofNat offset)

/-- Conservative construction work: for each state, every copied value plus
every projected record and each of its fields. `Nat` arithmetic is unbounded. -/
def projectionWorkEstimate (plan : TraceProjectionPlan) (stateCount : Nat) :
    Except String Nat := do
  let perState ← plan.zipIntFunctions.foldlM (fun total group => do
    let (_, _, domainSize) ← domainBounds group.domain
    return total + domainSize * (group.fields.length + 1))
    plan.exactCopyVariables.length
  return stateCount * perState

private def checkProjectionWorkBound (plan : TraceProjectionPlan)
    (stateCount : Nat) : Except String Unit := do
  let estimate ← projectionWorkEstimate plan stateCount
  if estimate > maxProjectionWorkNodesV1 then
    throw s!"projection work estimate {estimate} exceeds limit {maxProjectionWorkNodesV1}"

private def projectGroup (state : List (String × Json))
    (group : ZipIntFunctions) : Except String Json := do
  let keys ← domainKeys group.domain
  let maps ← group.fields.mapM fun field => do
    let raw ← requiredField "state" field.sourceVariable state
    return (field, ← intMapEntries field.sourceVariable raw)
  let records ← keys.mapM fun key => do
    let fields ← maps.mapM fun item =>
      match List.lookup key item.2 with
      | some value => pure (item.1.name, value)
      | none => throw s!"{item.1.sourceVariable}: missing domain key {key}"
    return Json.mkObj fields
  for item in maps do
    if !sameSet (item.2.map Prod.fst) keys then
      throw s!"{item.1.sourceVariable}: keys differ from the declared domain"
  return .arr records.toArray

private partial def renderType : ModelType → String
  | .int => "Int" | .bool => "Bool" | .str => "Str" | .null => "Null"
  | .set type => s!"Set({renderType type})"
  | .seq type => s!"Seq({renderType type})"
  | .tuple types => "<<" ++ String.intercalate ", " (types.map renderType) ++ ">>"
  | .record fields => "{" ++ String.intercalate ", " (fields.map fun field =>
      field.wireName ++ ": " ++ renderType field.type) ++ "}"
  | .map key value => s!"({renderType key} -> {renderType value})"
  | .variant _ | .opaqueItf _ => "<unsupported>"

private def projectedType (context : TraceProjectionContext)
    (group : ZipIntFunctions) : ModelType :=
  .seq (.record (group.fields.map fun field =>
    let valueType := match List.lookup field.sourceVariable context.sourceTypes with
      | some (.map .int value) => value
      | _ => .opaqueItf "invalid-projection-source"
    { wireName := field.name, type := valueType }))

private def projectVarTypes (plan : TraceProjectionPlan)
    (context : TraceProjectionContext) : Json :=
  let copied := plan.exactCopyVariables.filterMap fun name =>
    (List.lookup name context.sourceTypes).map fun type => (name, .str (renderType type))
  let zipped := plan.zipIntFunctions.map fun group =>
    (group.outputWireName, .str (renderType (projectedType context group)))
  Json.mkObj (copied ++ zipped)

private def projectMeta (plan : TraceProjectionPlan) (context : TraceProjectionContext) :
    Json → Except String Json
  | .obj fields => do
      let allowed := ["format", "format-description", "description", "varTypes"]
      match fields.toList.find? (fun field => !allowed.contains field.1) with
      | some field => throw s!"#meta: unknown field '{field.1}'"
      | none => pure ()
      if (List.lookup "varTypes" fields.toList).isNone then throw "#meta: missing 'varTypes'"
      pure <| Json.mkObj (fields.toList.filter (fun field => field.1 != "varTypes") ++
        [("varTypes", projectVarTypes plan context)])
  | _ => throw "#meta: object expected"

/-- Project already strictly parsed raw ITF JSON. Metadata and state `#meta`
objects are preserved; `vars`, `varTypes`, and state variables are replaced. -/
def projectTraceJson (plan : TraceProjectionPlan) (context : TraceProjectionContext)
    (raw : Json) : Except String Json := do
  validateTraceProjectionPlan plan context
  let .obj root := raw | throw "ITF root object expected"
  let fields := root.toList
  let rootAllowed := ["#meta", "vars", "states", "params", "param_vars"]
  match fields.find? (fun field => !rootAllowed.contains field.1) with
  | some field => throw s!"ITF: unknown field '{field.1}'"
  | none => pure ()
  let rawVars ← stringArray "vars" (← requiredField "ITF" "vars" fields)
  if !sameSet rawVars context.rawVariables || !(duplicateStrings rawVars).isEmpty then
    throw "ITF vars differ from projection context"
  let projectedMetadata ← projectMeta plan context (← requiredField "ITF" "#meta" fields)
  match List.lookup "param_vars" fields with
  | some .null | none => pure ()
  | some value =>
      let params ← stringArray "param_vars" value
      if !params.all (fun name => plan.exactCopyVariables.contains name) then
        throw "projected function sources cannot be param_vars"
  let .arr states ← requiredField "ITF" "states" fields
    | throw "states: expected array"
  checkProjectionWorkBound plan states.size
  let projectedStates ← states.toList.mapM fun
    | .obj state => do
        let stateFields := state.toList
        match stateFields.find? (fun item => item.1.startsWith "#" && item.1 != "#meta") with
        | some item => throw s!"state: unknown metadata field '{item.1}'"
        | none => pure ()
        match List.lookup "#meta" stateFields with
        | some (.obj stateMetadata) =>
            match stateMetadata.toList.find? (fun item => item.1 != "index") with
            | some item => throw s!"state.#meta: unknown field '{item.1}'"
            | none => pure ()
        | some _ => throw "state.#meta: object expected"
        | none => pure ()
        let present := stateFields.filter (fun item => !item.1.startsWith "#") |>.map Prod.fst
        if !sameSet present context.rawVariables || !(duplicateStrings present).isEmpty then
          throw "state variables differ from projection context"
        let copied ← plan.exactCopyVariables.mapM fun name =>
          return (name, ← requiredField "state" name stateFields)
        let zipped ← plan.zipIntFunctions.mapM fun group =>
          return (group.outputWireName, ← projectGroup stateFields group)
        let metadata := stateFields.filter (fun item => item.1.startsWith "#")
        return Json.mkObj (metadata ++ copied ++ zipped)
    | _ => throw "states[]: object expected"
  return Json.mkObj (fields.filter (fun field =>
    field.1 != "#meta" && field.1 != "vars" && field.1 != "states") ++ [
      ("#meta", projectedMetadata),
      ("vars", .arr ((outputVariables plan).map Json.str).toArray),
      ("states", .arr projectedStates.toArray)])

end Core.ModelInterface
