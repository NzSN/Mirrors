import Core.ModelInterface
import Codec.ModelInterfaceJson
import Lean.Data.Json

/-!
# TypeScript model-interface emitter

The first concrete target emitter is deliberately pure. Target lowering and
rendering consume a locked model interface and return an owned, sorted tree of
UTF-8 files. Filesystem replacement and stale-file removal belong to the
surrounding shell.
-/

namespace Shell.ModelInterface.Emit.TypeScript

open Core.ModelInterface

/-- A stable target-emission diagnostic. -/
structure EmitDiagnostic where
  code : String
  message : String
  deriving Repr, BEq

/-- One file owned by a generated tree. -/
structure GeneratedFile where
  relativePath : String
  bytes : ByteArray
  executable : Bool := false
  deriving BEq

/-- Pure emitter output. Files are sorted by relative path. -/
structure GeneratedTree where
  files : List GeneratedFile
  deriving BEq

abbrev EmitResult (α : Type) := Except (List EmitDiagnostic) α

private def targetProfile : String := "mirrorecma-v1"
private def profileVersion : Nat := 1
private def manifestPath : String := ".model-interface-generated.json"

private def fail {α : Type} (code message : String) : EmitResult α :=
  .error [{ code, message }]

private partial def typeContainsPrototypeKey : ModelType → Bool
  | .set element | .seq element => typeContainsPrototypeKey element
  | .tuple elements => elements.any typeContainsPrototypeKey
  | .record fields => fields.any (fun field =>
      field.wireName == "__proto__" || typeContainsPrototypeKey field.type)
  | .map key value =>
      typeContainsPrototypeKey key || typeContainsPrototypeKey value
  | .variant cases => cases.any (fun item => typeContainsPrototypeKey item.payload)
  | _ => false

private def pathContainsPrototypeKey (path : List PathSegment) : Bool :=
  path.any fun
    | .field name => name == "__proto__"
    | _ => false

private def lockContainsPrototypeKey (lock : LockedModelInterface) : Bool :=
  let actions := lock.initializers ++ lock.actions
  lock.observations.any (fun observation =>
      observation.wireName == "__proto__" ||
        typeContainsPrototypeKey observation.type) ||
    actions.any (fun action => action.inputs.any (fun input =>
      pathContainsPrototypeKey input.projection.path ||
        typeContainsPrototypeKey input.projection.type))

private def sortedBy {α : Type} (key : α → String) (xs : List α) : List α :=
  xs.toArray.qsort (fun a b => compare (key a) (key b) != Ordering.gt) |>.toList

private def sortedStrings (xs : List String) : List String :=
  sortedBy id xs

private def lines (xs : List String) : String :=
  String.intercalate "\n" xs

private def withFinalLf (s : String) : String :=
  (s.dropEndWhile '\n').copy ++ "\n"

private def tsString (s : String) : String :=
  Lean.Json.compress (.str s)

private def lowerFirst (s : String) : String :=
  s.decapitalize

private def reservedWords : List String :=
  ["await", "break", "case", "catch", "class", "const", "continue", "debugger",
   "default", "delete", "do", "else", "enum", "export", "extends",
   "false", "finally", "for", "function", "if", "import", "in",
   "implements", "instanceof", "interface", "let", "new", "null", "package", "private",
   "protected", "public", "return", "static", "super", "switch", "this",
   "throw", "true", "try", "type", "typeof", "var", "void", "while",
   "with", "yield"]

private def nativeFieldName (stableId : String) : String :=
  let base := lowerFirst stableId
  if reservedWords.contains base then base ++ "_" else base

private def validTsIdentifier (name : String) : Bool :=
  match name.toList with
  | [] => false
  | first :: rest =>
      (first.isAlpha || first == '_' || first == '$') &&
        rest.all (fun character =>
          character.isAlphanum || character == '_' || character == '$')

private def validateNativeNamespace (context : String) (stableIds : List String)
    (mandatory : List String := []) : EmitResult Unit := do
  let lowered := stableIds.map nativeFieldName
  match lowered.find? (fun name => !validTsIdentifier name) with
  | some name =>
      fail "MIC-E-NAME-001"
        s!"{context} lowers to invalid TypeScript identifier {name}"
  | none => pure ()
  match duplicateStrings (mandatory ++ lowered) with
  | collision :: _ =>
      fail "MIC-E-NAME-001"
        s!"{context} contains colliding native identifier {collision}"
  | [] => pure ()

private def validateNativeNamespaces (lock : LockedModelInterface) : EmitResult Unit := do
  let actions := lock.initializers ++ lock.actions
  let _ ← validateNativeNamespace "implementation port"
    (actions.map (·.id)) ["observe"]
  for action in actions do
    let _ ← validateNativeNamespace s!"input fields for action {action.id}"
      (action.inputs.map (·.id))
  let _ ← validateNativeNamespace "observation fields"
    (lock.observations.map (·.id))
  pure ()

/-- Largest integer that can be represented exactly by JavaScript's `number`
type. Generated path indices are emitted as number literals. -/
private def maxSafeJavaScriptInteger : Nat := 9007199254740991

private def modelBaseName (moduleName : String) : EmitResult String :=
  match moduleName.toList with
  | [] => fail "MIC-E-NAME-001" "model module is empty"
  | c :: cs =>
      let validFirst := c.isAlpha || c == '_' || c == '$'
      let validRest := cs.all (fun x => x.isAlphanum || x == '_' || x == '$')
      if validFirst && validRest then
        pure moduleName
      else
        fail "MIC-E-NAME-001"
          s!"model module {moduleName} is not a TypeScript identifier"

private partial def renderTsType : ModelType → EmitResult String
  | .int => pure "bigint"
  | .bool => pure "boolean"
  | .str => pure "string"
  | .null => pure "null"
  | .set element => do
      let t ← renderTsType element
      pure s!"MirrorSet<{t}>"
  | .seq element => do
      let t ← renderTsType element
      pure s!"readonly ({t})[]"
  | .tuple elements => do
      let ts ← elements.mapM renderTsType
      pure s!"readonly [{String.intercalate ", " ts}]"
  | .record fields => do
      let fields := sortedBy (fun f => f.wireName) fields
      let rendered ← fields.mapM fun field => do
        let t ← renderTsType field.type
        pure s!"readonly {tsString field.wireName}: {t};"
      pure ("{ " ++ String.intercalate " " rendered ++ " }")
  | .map .str value => do
      let v ← renderTsType value
      pure s!"MirrorMap<string, {v}>"
  | .map _ _ =>
      fail "MIC-E-TYPE-001"
        "mirrorecma-v1 supports only string-keyed ITF maps"
  | .variant cases => do
      let cases := sortedBy (fun c => c.tag) cases
      let rendered ← cases.mapM fun c => do
        let payload ← renderTsType c.payload
        pure ("{ readonly tag: " ++ tsString c.tag ++
          "; readonly value: " ++ payload ++ " }")
      pure (String.intercalate " | " rendered)
  | .opaqueItf description =>
      fail "MIC-E-TYPE-001"
        s!"mirrorecma-v1 cannot emit opaque ITF type: {description}"

private partial def renderShape : ModelType → EmitResult String
  | .int => pure "{ kind: \"int\" }"
  | .bool => pure "{ kind: \"bool\" }"
  | .str => pure "{ kind: \"str\" }"
  | .null => pure "{ kind: \"null\" }"
  | .set element => do
      let e ← renderShape element
      pure ("{ kind: \"set\", element: " ++ e ++ " }")
  | .seq element => do
      let e ← renderShape element
      pure ("{ kind: \"seq\", element: " ++ e ++ " }")
  | .tuple elements => do
      let es ← elements.mapM renderShape
      pure ("{ kind: \"tuple\", elements: [" ++ String.intercalate ", " es ++ "] }")
  | .record fields => do
      let fields := sortedBy (fun f => f.wireName) fields
      let fs ← fields.mapM fun field => do
        let t ← renderShape field.type
        pure s!"[{tsString field.wireName}, {t}]"
      pure ("{ kind: \"record\", fields: [" ++ String.intercalate ", " fs ++ "] }")
  | .map .str value => do
      let v ← renderShape value
      pure ("{ kind: \"map\", key: { kind: \"str\" }, value: " ++ v ++ " }")
  | .map _ _ =>
      fail "MIC-E-TYPE-001"
        "mirrorecma-v1 supports only string-keyed ITF maps"
  | .variant cases => do
      let cases := sortedBy (fun c => c.tag) cases
      let cs ← cases.mapM fun c => do
        let t ← renderShape c.payload
        pure s!"[{tsString c.tag}, {t}]"
      pure ("{ kind: \"variant\", cases: [" ++ String.intercalate ", " cs ++ "] }")
  | .opaqueItf description =>
      fail "MIC-E-TYPE-001"
        s!"mirrorecma-v1 cannot emit opaque ITF type: {description}"

private def renderPathSegment : PathSegment → EmitResult String
  | .field name => pure ("{ kind: \"field\", name: " ++ tsString name ++ " }")
  | .index index =>
      if index ≤ maxSafeJavaScriptInteger then
        pure ("{ kind: \"index\", index: " ++ toString index ++ " }")
      else
        fail "MIC-E-PATH-001"
          s!"mirrorecma-v1 path index {index} exceeds Number.MAX_SAFE_INTEGER"
  | .variantValue tag =>
      pure ("{ kind: \"variantValue\", tag: " ++ tsString tag ++ " }")
  | .mapKey _ =>
      fail "MIC-E-PATH-001" "mirrorecma-v1 does not yet lower mapKey paths"

private def renderPath (projection : InputProjection) : EmitResult String := do
  let segments ← projection.path.mapM renderPathSegment
  pure s!"[{String.intercalate ", " segments}]"

/-!
The target runtime is emitted once per model module. It deliberately works
through MirrorECMA's public Value representation rather than reproducing JSON
wire encoding.
-/
private def runtimeSupport : String := lines [
  "export type MirrorSet<T> = readonly T[];",
  "export type MirrorMap<K, V> = readonly (readonly [K, V])[];",
  "",
  "type TypeShape =",
  "  | { readonly kind: \"int\" | \"bool\" | \"str\" | \"null\" }",
  "  | { readonly kind: \"set\" | \"seq\"; readonly element: TypeShape }",
  "  | { readonly kind: \"tuple\"; readonly elements: readonly TypeShape[] }",
  "  | { readonly kind: \"record\"; readonly fields: readonly (readonly [string, TypeShape])[] }",
  "  | { readonly kind: \"map\"; readonly key: TypeShape; readonly value: TypeShape }",
  "  | { readonly kind: \"variant\"; readonly cases: readonly (readonly [string, TypeShape])[] };",
  "",
  "type RuntimePathSegment =",
  "  | { readonly kind: \"field\"; readonly name: string }",
  "  | { readonly kind: \"index\"; readonly index: number }",
  "  | { readonly kind: \"variantValue\"; readonly tag: string };",
  "",
  "function ownRecord(value: unknown): Record<string, unknown> | null {",
  "  if (typeof value !== \"object\" || value === null || Array.isArray(value)) return null;",
  "  return value as Record<string, unknown>;",
  "}",
  "",
  "function exactKeys(value: Record<string, unknown>, expected: readonly string[], path: string): void {",
  "  const actual = Object.keys(value).sort();",
  "  const wanted = [...expected].sort();",
  "  if (actual.length !== wanted.length || actual.some((key, i) => key !== wanted[i])) {",
  "    throw new Error(path + \": expected keys [\" + wanted.join(\", \") + \"], got [\" + actual.join(\", \") + \"]\");",
  "  }",
  "}",
  "",
  "function comparableInitialState(root: State): State {",
  "  const filtered = Object.create(null) as State;",
  "  for (const [name, value] of Object.entries(root)) {",
  "    if (!name.startsWith(\"#\") && name !== \"action_taken\" && name !== \"parameters\") {",
  "      filtered[name] = value;",
  "    }",
  "  }",
  "  return filtered;",
  "}",
  "",
  "function valueIdentity(value: Value): string {",
  "  switch (value.tag) {",
  "    case \"int\": return \"int:\" + value.val.toString();",
  "    case \"bool\": return value.val ? \"bool:1\" : \"bool:0\";",
  "    case \"str\": return \"str:\" + JSON.stringify(value.val);",
  "    case \"null\": return \"null\";",
  "    case \"set\": return \"set:[\" + value.val.map(valueIdentity).sort().join(\",\") + \"]\";",
  "    case \"seq\": return \"seq:[\" + value.val.map(valueIdentity).join(\",\") + \"]\";",
  "    case \"tuple\": return \"tuple:[\" + value.val.map(valueIdentity).join(\",\") + \"]\";",
  "    case \"record\": return \"record:{\" + Object.keys(value.val).sort()",
  "      .map((key) => JSON.stringify(key) + \":\" + valueIdentity(value.val[key]!)).join(\",\") + \"}\";",
  "    case \"map\": return \"map:[\" + value.val.map(([key, item]) =>",
  "      valueIdentity(key) + \"=>\" + valueIdentity(item)).sort().join(\",\") + \"]\";",
  "    case \"variant\": return \"variant:\" + JSON.stringify(value.variantTag) + \"=\" + valueIdentity(value.value);",
  "    case \"unserializable\": return \"unserializable:\" + JSON.stringify(value.val);",
  "  }",
  "}",
  "",
  "function assertUniqueValues(values: readonly Value[], path: string): void {",
  "  const seen = new Set<string>();",
  "  for (const value of values) {",
  "    const identity = valueIdentity(value);",
  "    if (seen.has(identity)) throw new Error(path + \": duplicate set element or map key\");",
  "    seen.add(identity);",
  "  }",
  "}",
  "",
  "function readPath(root: State, path: readonly RuntimePathSegment[], label: string): Value {",
  "  let value: Value = { tag: \"record\", val: root };",
  "  for (const segment of path) {",
  "    if (segment.kind === \"field\") {",
  "      if (value.tag !== \"record\" || !Object.prototype.hasOwnProperty.call(value.val, segment.name)) {",
  "        throw new Error(label + \": missing record field \" + segment.name);",
  "      }",
  "      value = value.val[segment.name]!;",
  "    } else if (segment.kind === \"index\") {",
  "      if ((value.tag !== \"seq\" && value.tag !== \"tuple\") || segment.index >= value.val.length) {",
  "        throw new Error(label + \": missing index \" + segment.index);",
  "      }",
  "      value = value.val[segment.index]!;",
  "    } else {",
  "      if (value.tag !== \"variant\" || value.variantTag !== segment.tag) {",
  "        throw new Error(label + \": expected variant \" + segment.tag);",
  "      }",
  "      value = value.value;",
  "    }",
  "  }",
  "  return value;",
  "}",
  "",
  "function decodeNative(value: Value, shape: TypeShape, path: string): unknown {",
  "  switch (shape.kind) {",
  "    case \"int\": if (value.tag === \"int\") return value.val; break;",
  "    case \"bool\": if (value.tag === \"bool\") return value.val; break;",
  "    case \"str\": if (value.tag === \"str\") return value.val; break;",
  "    case \"null\": if (value.tag === \"null\") return null; break;",
  "    case \"set\":",
  "      if (value.tag === \"set\") return value.val.map((item, i) => decodeNative(item, shape.element, path + \"[\" + i + \"]\"));",
  "      break;",
  "    case \"seq\":",
  "      if (value.tag === \"seq\") return value.val.map((item, i) => decodeNative(item, shape.element, path + \"[\" + i + \"]\"));",
  "      break;",
  "    case \"tuple\":",
  "      if (value.tag === \"tuple\" && value.val.length === shape.elements.length) {",
  "        return value.val.map((item, i) => decodeNative(item, shape.elements[i]!, path + \"[\" + i + \"]\"));",
  "      }",
  "      break;",
  "    case \"record\":",
  "      if (value.tag === \"record\") {",
  "        exactKeys(value.val, shape.fields.map(([name]) => name), path);",
  "        const out = Object.create(null) as Record<string, unknown>;",
  "        for (const [name, fieldShape] of shape.fields) {",
  "          out[name] = decodeNative(value.val[name]!, fieldShape, path + \".\" + name);",
  "        }",
  "        return out;",
  "      }",
  "      break;",
  "    case \"map\":",
  "      if (value.tag === \"map\") return value.val.map(([key, item], i) => [",
  "        decodeNative(key, shape.key, path + \"[\" + i + \"].key\"),",
  "        decodeNative(item, shape.value, path + \"[\" + i + \"].value\"),",
  "      ] as const);",
  "      break;",
  "    case \"variant\":",
  "      if (value.tag === \"variant\") {",
  "        const found = shape.cases.find(([tag]) => tag === value.variantTag);",
  "        if (found) return {",
  "          tag: value.variantTag,",
  "          value: decodeNative(value.value, found[1], path + \".value\"),",
  "        };",
  "      }",
  "      break;",
  "  }",
  "  throw new Error(path + \": value does not match \" + shape.kind);",
  "}",
  "",
  "function encodeNative(value: unknown, shape: TypeShape, path: string): Value {",
  "  switch (shape.kind) {",
  "    case \"int\": if (typeof value === \"bigint\") return { tag: \"int\", val: value }; break;",
  "    case \"bool\": if (typeof value === \"boolean\") return { tag: \"bool\", val: value }; break;",
  "    case \"str\": if (typeof value === \"string\") return { tag: \"str\", val: value }; break;",
  "    case \"null\": if (value === null) return { tag: \"null\" }; break;",
  "    case \"set\":",
  "    case \"seq\":",
  "      if (Array.isArray(value)) {",
  "        const val = value.map((item, i) => encodeNative(item, shape.element, path + \"[\" + i + \"]\"));",
  "        if (shape.kind === \"set\") assertUniqueValues(val, path);",
  "        return shape.kind === \"set\" ? { tag: \"set\", val } : { tag: \"seq\", val };",
  "      }",
  "      break;",
  "    case \"tuple\":",
  "      if (Array.isArray(value) && value.length === shape.elements.length) {",
  "        return {",
  "          tag: \"tuple\",",
  "          val: value.map((item, i) => encodeNative(item, shape.elements[i]!, path + \"[\" + i + \"]\")),",
  "        };",
  "      }",
  "      break;",
  "    case \"record\": {",
  "      const record = ownRecord(value);",
  "      if (record) {",
  "        exactKeys(record, shape.fields.map(([name]) => name), path);",
  "        const val = Object.create(null) as Record<string, Value>;",
  "        for (const [name, fieldShape] of shape.fields) {",
  "          val[name] = encodeNative(record[name], fieldShape, path + \".\" + name);",
  "        }",
  "        return { tag: \"record\", val };",
  "      }",
  "      break;",
  "    }",
  "    case \"map\":",
  "      if (Array.isArray(value)) {",
  "        const val: [Value, Value][] = value.map((entry, i) => {",
  "          if (!Array.isArray(entry) || entry.length !== 2) {",
  "            throw new Error(path + \"[\" + i + \"]: expected map entry\");",
  "          }",
  "          return [",
  "            encodeNative(entry[0], shape.key, path + \"[\" + i + \"].key\"),",
  "            encodeNative(entry[1], shape.value, path + \"[\" + i + \"].value\"),",
  "          ];",
  "        });",
  "        assertUniqueValues(val.map(([key]) => key), path);",
  "        return { tag: \"map\", val };",
  "      }",
  "      break;",
  "    case \"variant\": {",
  "      const variant = ownRecord(value);",
  "      if (variant && typeof variant.tag === \"string\") {",
  "        exactKeys(variant, [\"tag\", \"value\"], path);",
  "        const found = shape.cases.find(([tag]) => tag === variant.tag);",
  "        if (found) return {",
  "          tag: \"variant\",",
  "          variantTag: variant.tag,",
  "          value: encodeNative(variant.value, found[1], path + \".value\"),",
  "        };",
  "      }",
  "      break;",
  "    }",
  "  }",
  "  throw new Error(path + \": implementation value does not match \" + shape.kind);",
  "}"
]

private def renderInputInterface (action : ResolvedAction) : EmitResult String := do
  if action.inputs.isEmpty then return ""
  let fields ← (sortedBy (fun i => i.id) action.inputs).mapM fun input => do
    let t ← renderTsType input.projection.type
    pure s!"  readonly {nativeFieldName input.id}: {t};"
  pure <| lines
    ([s!"export interface {action.id}Input " ++ "{"] ++ fields ++ ["}"])

private def renderObservationInterface (modelName : String)
    (observations : List ResolvedObservation) : EmitResult String := do
  let fields ← (sortedBy (fun o => o.id) observations).mapM fun observation => do
    let t ← renderTsType observation.type
    pure s!"  readonly {nativeFieldName observation.id}: {t};"
  pure <| lines
    ([s!"export interface {modelName}Observation " ++ "{"] ++ fields ++ ["}"])

private def renderPortMethod (action : ResolvedAction) : String :=
  if action.inputs.isEmpty then
    s!"  {nativeFieldName action.id}(): void;"
  else
    s!"  {nativeFieldName action.id}(input: {action.id}Input): void;"

private def renderShapeConstForInput (action : ResolvedAction)
    (input : ResolvedInput) : EmitResult String := do
  let shape ← renderShape input.projection.type
  pure s!"const {nativeFieldName action.id}_{input.id}Shape: TypeShape = {shape};"

private def renderShapeConstForObservation (modelName : String)
    (observation : ResolvedObservation) : EmitResult String := do
  let shape ← renderShape observation.type
  pure s!"const {lowerFirst modelName}{observation.id}ObservationShape: TypeShape = {shape};"

private def renderInputDecoder (action : ResolvedAction) : EmitResult String := do
  if action.inputs.isEmpty then return ""
  let fields ← (sortedBy (fun i => i.id) action.inputs).mapM fun input => do
    let path ← renderPath input.projection
    let root := match input.projection.root with
      | .initialState => "comparableInitialState(payload)"
      | .stepParameters => "payload"
    let nativeType ← renderTsType input.projection.type
    let name := nativeFieldName input.id
    let shapeName := s!"{nativeFieldName action.id}_{input.id}Shape"
    let label := tsString (action.id ++ "." ++ input.id)
    pure s!"    {name}: decodeNative(readPath({root}, {path}, {label}), {shapeName}, {label}) as {nativeType},"
  pure <| lines
    ([s!"function decode{action.id}Input(payload: State): {action.id}Input " ++ "{",
      "  return {"] ++ fields ++ ["  };", "}"])

private def renderActionCases (action : ResolvedAction) : String :=
  let labels := action.wireAction :: sortedStrings action.wireAliases
  let cases := labels.map (fun label => s!"      case {tsString label}:")
  let precondition := match action.phase with
    | .initialize => []
    | .transition =>
        ["        if (lifecycle === \"fresh\") throw bindingError(\"transition_before_initialization\", \"transition before initialization\");"]
  let callLines :=
    if action.inputs.isEmpty then
      ["        stage = \"adapter\";",
       s!"        port.{nativeFieldName action.id}();"]
    else
      ["        stage = \"input\";",
       s!"        const input = decode{action.id}Input(payload);",
       "        stage = \"adapter\";",
       s!"        port.{nativeFieldName action.id}(input);"]
  lines <| cases ++ ["      {"] ++ precondition ++
    callLines ++ ["        lifecycle = \"initialized\";",
     s!"        actionId = {tsString action.id};",
     "        break;",
     "      }"]

private def renderObservationEncoder (modelName : String)
    (observations : List ResolvedObservation) : String :=
  let observations := sortedBy (fun o => o.id) observations
  let nativeKeys := observations.map (fun o => tsString (nativeFieldName o.id))
  let assignments := observations.map fun observation =>
    let shapeName := s!"{lowerFirst modelName}{observation.id}ObservationShape"
    let label := tsString (modelName ++ "Observation." ++ observation.id)
    s!"  state[{tsString observation.wireName}] = encodeNative(observation.{nativeFieldName observation.id}, {shapeName}, {label});"
  lines <| [s!"function encode{modelName}Observation(observation: {modelName}Observation): State " ++ "{",
    s!"  exactKeys(observation as unknown as Record<string, unknown>, [{String.intercalate ", " nativeKeys}], {tsString (modelName ++ "Observation")});",
    "  const state = Object.create(null) as State;"] ++ assignments ++ ["  return state;", "}"]

private def renderBinding (modelName semanticDigest contractJson : String)
    (configuredParamVar : Option String) (actions : List ResolvedAction) : String :=
  let actions := sortedBy (fun a => a.id) actions
  let actionIds := actions.map (fun a => tsString a.id)
  let actionUnion := String.intercalate " | " actionIds
  let coverageFields := actions.map (fun a => s!"    {tsString a.id}: 0,")
  let switchCases := actions.map renderActionCases
  let expectedParamVar := configuredParamVar.getD ""
  lines <|
    [s!"export const {modelName}SemanticDigest = {tsString semanticDigest} as const;",
     s!"export const {modelName}ModelInterface = " ++ "{",
     s!"  semanticDigest: {modelName}SemanticDigest,",
     s!"  contract: {contractJson},",
     "} as const;",
     "",
     s!"export type {modelName}BindingErrorCode =",
     "  | \"configuration_mismatch\"",
     "  | \"unknown_action\"",
     "  | \"transition_before_initialization\"",
     "  | \"input_shape_mismatch\"",
     "  | \"adapter_failure\"",
     "  | \"observation_shape_mismatch\"",
     "  | \"binding_poisoned\";",
     "",
     s!"export class {modelName}BindingError extends Error " ++ "{",
     s!"  constructor(readonly code: {modelName}BindingErrorCode, message: string, options?: ErrorOptions) " ++ "{",
     "    super(message, options);",
     s!"    this.name = {tsString (modelName ++ "BindingError")};",
     "  }",
     "}",
     "",
     s!"function bindingError(code: {modelName}BindingErrorCode, message: string, cause?: unknown): {modelName}BindingError " ++ "{",
     s!"  return new {modelName}BindingError(code, message, cause === undefined ? undefined : " ++ "{ cause });",
     "}",
     "",
     s!"type {modelName}ActionId = {actionUnion};",
     "",
     s!"export interface {modelName}Binding " ++ "{",
     "  readonly computer: StateComputer;",
     s!"  coverage(): Readonly<Record<{modelName}ActionId, number>>;",
     "  assertAllActionsCovered(): void;",
     "}",
     "",
     s!"export function bind{modelName}(",
     s!"  port: {modelName}Port,",
     "  config: Pick<ApalacheConfig, \"paramVars\">,",
     s!"): {modelName}Binding " ++ "{",
     s!"  const expectedParamVar = {tsString expectedParamVar};",
     "  const actualParamVar = config.paramVars ?? \"\";",
     "  if (actualParamVar !== expectedParamVar) {",
     "    throw bindingError(",
     "      \"configuration_mismatch\",",
     "      \"expected paramVars=\" + expectedParamVar + \", got \" + actualParamVar,",
     "    );",
     "  }",
     "",
     "  let lifecycle: \"fresh\" | \"initialized\" | \"poisoned\" = \"fresh\";",
     s!"  const counts: Record<{modelName}ActionId, number> = " ++ "{"] ++ coverageFields ++
    ["  };",
     "",
     "  const computer: StateComputer = (action, payload, _previousState) => {",
     "    if (lifecycle === \"poisoned\") {",
     "      throw bindingError(\"binding_poisoned\", \"binding is poisoned\");",
     "    }",
     s!"    let actionId: {modelName}ActionId;",
     "    let stage: \"dispatch\" | \"input\" | \"adapter\" | \"observation\" = \"dispatch\";",
     "    try {",
     "      switch (action) {"] ++ switchCases ++
    ["        default: throw bindingError(\"unknown_action\", \"unknown action \" + action);",
     "      }",
     "      stage = \"observation\";",
     "      const observation = port.observe();",
     s!"      const state = encode{modelName}Observation(observation);",
     "      counts[actionId] += 1;",
     "      return state;",
     "    } catch (error) {",
     "      lifecycle = \"poisoned\";",
     s!"      if (error instanceof {modelName}BindingError) throw error;",
     "      const code = stage === \"input\"",
     "        ? \"input_shape_mismatch\"",
     "        : stage === \"observation\"",
     "          ? \"observation_shape_mismatch\"",
     "          : \"adapter_failure\";",
     "      throw bindingError(code, \"binding failed for action \" + action, error);",
     "    }",
     "  };",
     "",
     "  return {",
     "    computer,",
     "    coverage: () => Object.freeze({ ...counts }),",
     "    assertAllActionsCovered: () => {",
     "      const unseen = (Object.keys(counts) as Array<keyof typeof counts>)",
     "        .filter((id) => counts[id] === 0);",
     "      if (unseen.length > 0) throw new Error(\"uncovered actions: \" + unseen.join(\", \"));",
     "    },",
     "  };",
     "}"]

private def renderModule (lock : LockedModelInterface) : EmitResult (String × String) := do
  let modelName ← modelBaseName lock.modelModule
  let initializers := sortedBy (fun a => a.id) lock.initializers
  let transitions := sortedBy (fun a => a.id) lock.actions
  let actions := initializers ++ transitions
  let observations := sortedBy (fun o => o.id) lock.observations

  let inputInterfaces ← actions.mapM renderInputInterface
  let observationInterface ← renderObservationInterface modelName observations
  let portMethods := actions.map renderPortMethod
  let inputShapeGroups ← actions.mapM fun action =>
    (sortedBy (fun i => i.id) action.inputs).mapM (renderShapeConstForInput action)
  let inputShapes := inputShapeGroups.flatten
  let observationShapes ← observations.mapM
    (renderShapeConstForObservation modelName)
  let inputDecoders ← actions.mapM renderInputDecoder
  let observationEncoder := renderObservationEncoder modelName observations
  let contractJson := Lean.Json.compress
    (Codec.ModelInterfaceJson.encodeContract lock.contract)
  let binding := renderBinding modelName lock.semanticDigest contractJson
    lock.runProfile.configuredParamVar actions
  let sourcePath := s!"{modelName}Mirror.generated.ts"
  let header := lines [
    "// @generated by Mirrors model_interface_gen",
    s!"// target-profile: {targetProfile}",
    s!"// profile-version: {profileVersion}",
    s!"// semantic-sha256: {lock.semanticDigest}",
    "// DO NOT EDIT"
  ]
  let imports :=
    "import type { ApalacheConfig, State, StateComputer, Value } from \"mirrorecma\";"
  let port := lines ([s!"export interface {modelName}Port " ++ "{"] ++
    portMethods ++ [s!"  observe(): {modelName}Observation;", "}"])
  let source := withFinalLf <| String.intercalate "\n\n" <|
    [header, imports, runtimeSupport] ++
    inputInterfaces.filter (· != "") ++
    [observationInterface, port] ++
    inputShapes ++ observationShapes ++
    inputDecoders.filter (· != "") ++
    [observationEncoder, binding]
  pure (sourcePath, source)

/-- Render the canonical ownership manifest for a generated tree. -/
def renderOwnershipManifest (semanticDigest : String) (ownedPaths : List String) : String :=
  let paths := sortedStrings ownedPaths
  let json := Lean.Json.mkObj [
    ("files", .arr (paths.map Lean.Json.str).toArray),
    ("profileVersion", .num profileVersion),
    ("schema", .str "mirrors.model-interface-generated/v1"),
    ("semanticDigest", .str semanticDigest),
    ("targetProfile", .str targetProfile)
  ]
  withFinalLf (Lean.Json.compress json)

/--
Lower and deterministically render the mirrorecma-v1 output tree.

The manifest owns itself and the generated TypeScript source. Both files are
UTF-8, use LF, and end in exactly one newline.
-/
def emitTypeScript (lock : LockedModelInterface) : EmitResult GeneratedTree := do
  if lockContainsPrototypeKey lock then
    fail "MIC-E-NAME-001"
      "mirrorecma-v1 rejects the reserved wire key __proto__"
  let _ ← validateNativeNamespaces lock
  let (sourcePath, source) ← renderModule lock
  let ownedPaths := sortedStrings [manifestPath, sourcePath]
  let manifest := renderOwnershipManifest lock.semanticDigest ownedPaths
  let files := sortedBy (fun f : GeneratedFile => f.relativePath) [
    { relativePath := sourcePath, bytes := source.toUTF8 },
    { relativePath := manifestPath, bytes := manifest.toUTF8 }
  ]
  pure { files }

end Shell.ModelInterface.Emit.TypeScript
