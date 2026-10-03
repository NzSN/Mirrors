import Shell.ModelInterface.Emit.TypeScript

/-! Deterministic native Lean ports and checked MirrorLean bindings. The target
uses the SDK's public values and codecs; it emits no protocol implementation. -/
namespace Shell.ModelInterface.Emit.Lean
open Core.ModelInterface
abbrev EmitResult (α : Type) := TypeScript.EmitResult α

private def fail {α : Type} (code message : String) : EmitResult α :=
  .error [{ code, message }]
private def lines (xs : List String) : String := String.intercalate "\n" xs ++ "\n"
private def sortedBy {α : Type} (key : α → String) (xs : List α) : List α :=
  xs.toArray.qsort (fun a b => compare (key a) (key b) != Ordering.gt) |>.toList
private def quote (s : String) : String := reprStr s
private def nativeName (s : String) : String :=
  String.ofList <| match s.toList with | [] => [] | c :: cs => c.toLower :: cs
private def fieldName (s : String) : String := "«" ++ nativeName s ++ "»"
private def keywords : List String :=
  ["abbrev", "axiom", "by", "class", "def", "deriving", "do", "else", "end", "example",
   "false", "for", "fun", "if", "import", "in", "inductive", "instance", "let", "macro",
   "match", "namespace", "opaque", "open", "private", "protected", "return", "structure",
   "then", "theorem", "true", "universe", "unsafe", "variable", "where", "with"]
private def validateNames (ids : List String) (reserved : List String := []) : EmitResult Unit := do
  let mut seen := reserved
  for id in ids do
    let name := nativeName id
    if id.isEmpty || !(id.toList.head!).isAlpha ||
        !id.toList.all (fun c => c.isAlphanum && c.toNat < 128) ||
        keywords.contains name || seen.contains name then
      fail "MIC-E-NAME-001" s!"mirrorlean-v1 invalid or colliding native name: {id}"
    seen := name :: seen

/-- Numeric child names keep arbitrary wire keys and variant tags separate from
the Lean identifier namespace. Tuple and record carriers remain distinct. -/
private partial def lowerType (name : String) (type : ModelType) :
    EmitResult (String × List String) := do
  match type with
  | .int => pure ("Int", [])
  | .bool => pure ("Bool", [])
  | .str => pure ("String", [])
  | .null => pure ("MirrorNull", [])
  | .seq child | .set child | .map .str child =>
      let (ty, decls) ← lowerType (name ++ "Item") child
      let wrapper := match type with
        | .seq _ => "MirrorSeq" | .set _ => "MirrorSet" | _ => "MirrorMap"
      pure (s!"{wrapper} ({ty})", decls)
  | .map _ _ => fail "MIC-E-TYPE-001" "mirrorlean-v1 supports only string-keyed maps"
  | .opaqueItf text => fail "MIC-E-TYPE-001" s!"mirrorlean-v1 cannot emit opaque ITF: {text}"
  | .tuple _ | .record _ =>
      let fields : List (String × ModelType) := match type with
        | .tuple items => items.map fun t => ("", t)
        | .record fields => (sortedBy (·.wireName) fields).map fun f => (f.wireName, f.type)
        | _ => []
      let isRecord := match type with | .record _ => true | _ => false
      let constructor := if isRecord then "record" else "tuple"
      let children ← fields.zipIdx.mapM fun ((_, ty), i) => lowerType s!"{name}F{i}" ty
      let members := children.zipIdx.map fun ((ty, _), i) => s!"  field{i} : {ty}"
      let checks := if isRecord then
          ["    checkRecord items [" ++ String.intercalate ", " (fields.map (quote ∘ Prod.fst)) ++ "]"]
        else [s!"    if items.size != {fields.length} then throw shape"]
      let decodes := (fields.zip children).zipIdx.map fun ((field, (ty, _)), i) =>
        let access := if isRecord then s!"(← readPath value [.field {quote field.1}])" else s!"items[{i}]!"
        s!"    let field{i} : {ty} ← NativeCodec.decode {access}"
      let encodes := fields.zipIdx.map fun (_, i) => s!"    let field{i} ← NativeCodec.encode value.field{i}"
      let values := fields.zipIdx.map fun (field, i) =>
        if isRecord then s!"({quote field.1}, field{i})" else s!"field{i}"
      let native := if fields.isEmpty then name ++ ".mk" else
        "{ " ++ String.intercalate ", " (fields.zipIdx.map fun (_, i) => s!"field{i} := field{i}") ++ " }"
      pure (name, children.flatMap (·.2) ++ [lines <|
        [s!"structure {name} where"] ++ members ++
        [s!"instance : NativeCodec {name} where", "  decode value := do",
         s!"    let .{constructor} items := value | throw shape"] ++ checks ++ decodes ++
        [s!"    pure ({native})", "  encode value := do"] ++ encodes ++
        [s!"    pure (.{constructor} #[" ++ String.intercalate ", " values ++ "])"]])
  | .variant cases =>
      if cases.isEmpty then
        return (name, [lines [
          s!"inductive {name} where",
          s!"instance : NativeCodec {name} where",
          "  decode _ := .error shape", "  encode value := nomatch value"]])
      let cases := sortedBy (·.tag) cases
      let children ← cases.zipIdx.mapM fun (c, i) => lowerType s!"{name}C{i}" c.payload
      let members := children.zipIdx.map fun ((ty, _), i) => s!"  | case{i} : ({ty}) → {name}"
      let decodes := (cases.zip children).zipIdx.map fun ((c, _), i) =>
        s!"    | {quote c.tag} => return .case{i} (← NativeCodec.decode payload)"
      let encodes := cases.zipIdx.map fun (c, i) =>
        s!"    | .case{i} payload => return .variant {quote c.tag} (← NativeCodec.encode payload)"
      pure (name, children.flatMap (·.2) ++ [lines <|
        [s!"inductive {name} where"] ++ members ++
        [s!"instance : NativeCodec {name} where", "  decode value := do",
         "    let .variant tag payload := value | throw shape", "    match tag with"] ++ decodes ++
        ["    | _ => throw shape", "  encode value := do", "    match value with"] ++ encodes])

private def renderPath (path : List Core.ModelInterface.PathSegment) : EmitResult String := do
  let parts ← path.mapM fun segment => match segment with
    | .field name => pure s!".field {quote name}"
    | .index n => pure s!".index {n}"
    | .variantValue tag => pure s!".variantValue {quote tag}"
    | .mapKey _ => fail "MIC-E-PATH-001" "mirrorlean-v1 does not support mapKey paths"
  pure ("[" ++ String.intercalate ", " parts ++ "]")

private def runtimeSupport : String := r###"
private inductive Lifecycle where
  | fresh | initialized | poisoned
  deriving BEq
private structure RuntimeState where
  lifecycle : Lifecycle := .fresh
  busy : Bool := false
  counts : Array (String × Nat)

private def poison {α : Type} (runtime : IO.Ref RuntimeState) (error : BindingError) :
    IO (Except BindingError α) := do
  runtime.modify fun state => { state with lifecycle := .poisoned, busy := false }
  pure (.error error)

structure Binding where
  computer : FallibleStateComputer
  coverage : IO (Array (String × Nat))
  assertAllActionsCovered : IO (Except BindingError Unit)

def Binding.toLocalBinding (binding : Binding)
    (dispose : IO (Except BindingError Unit) := pure (.ok ())) : LocalBinding :=
  { semanticDigest := semanticDigest, computer := binding.computer,
    assertCompatibleConfig := assertCompatibleConfig, coverage := binding.coverage, dispose }

private def compute (port : Port) (runtime : IO.Ref RuntimeState) : FallibleStateComputer :=
  fun action params _previous => do
    let acquired : Except BindingError Lifecycle ← runtime.modifyGet fun state =>
      if state.lifecycle == .poisoned then
        (.error { code := "binding_poisoned", message := "binding is poisoned" }, state)
      else if state.busy then
        (.error { code := "adapter_failure", message := "concurrent binding callback" },
          { state with lifecycle := .poisoned })
      else (.ok state.lifecycle, { state with busy := true })
    let phase ← match acquired with
      | .ok phase => pure phase
      | .error error => return .error error
    let initial := Value.record (params.toArray.filter fun (key, _) =>
      !key.startsWith "#" && key != "action_taken" && key != "parameters")
    let payload := State.toValue params
    let selected : Except BindingError (String × IO (Except BindingError Unit)) := do
      match action with
"###

private def runtimeFinish : String := r###"
      | _ => throw { code := "unknown_action", message := "unknown wire action" }
    let (stableAction, handler) ← match selected with
      | .ok selected => pure selected
      | .error error => return ← poison runtime error
    let handled ← try handler catch error =>
      pure (.error { code := "adapter_failure", message := toString error })
    match handled with
    | .error error => return ← poison runtime { error with code := "adapter_failure" }
    | .ok () => pure ()
    if (← runtime.get).lifecycle == .poisoned then
      return ← poison runtime { code := "binding_poisoned", message := "binding is poisoned" }
    let observed ← try port.observe catch error =>
      pure (.error { code := "observation_shape_mismatch", message := toString error })
    let observation ← match observed with
      | .ok observation => pure observation
      | .error error => return ← poison runtime { error with code := "observation_shape_mismatch" }
    let encoded := encodeObservation observation
    let report ← match encoded with
      | .ok report => pure report
      | .error error => return ← poison runtime { error with code := "observation_shape_mismatch" }
    let committed ← runtime.modifyGet fun state =>
      if state.lifecycle == .poisoned then (false, { state with busy := false })
      else (true, { state with
        lifecycle := .initialized, busy := false
        counts := state.counts.map fun (name, count) =>
          (name, if name == stableAction then count + 1 else count) })
    if !committed then return .error { code := "binding_poisoned", message := "binding is poisoned" }
    pure (.ok report)

def bind (port : Port) (config : ApalacheConfig) : IO (Except BindingError Binding) := do
  match assertCompatibleConfig config with
  | .error error => return .error error
  | .ok () => pure ()
"###

private def renderModule (lock : LockedModelInterface) : EmitResult String := do
  validateNames [lock.modelModule]
  let actions := sortedBy (·.id) (lock.initializers ++ lock.actions)
  validateNames (actions.map (·.id)) ["observe"]
  validateNames (lock.observations.map (·.id))
  let mut declarations : List String := []
  let mut methods : List String := []
  let mut branches : List String := []
  for (action, ai) in actions.zipIdx do
    let inputs := sortedBy (·.id) action.inputs
    validateNames (inputs.map (·.id))
    let mut fields : List String := []
    let mut decoders : List String := []
    for (input, ii) in inputs.zipIdx do
      let (ty, decls) ← lowerType s!"MiTypeA{ai}I{ii}" input.projection.type
      declarations := declarations ++ decls
      fields := fields ++ [s!"  {fieldName input.id} : {ty}"]
      let path ← renderPath input.projection.path
      let root := if input.projection.root == .initialState then "initial" else "payload"
      decoders := decoders ++ [s!"        let input{ii} : {ty} ← (readPath {root} {path}).bind NativeCodec.decode"]
    if !inputs.isEmpty then
      declarations := declarations ++ [lines <| [s!"structure {action.id}Input where"] ++ fields]
    let argument := if inputs.isEmpty then "" else s!"{action.id}Input → "
    methods := methods ++ [s!"  {fieldName action.id} : {argument}IO (Except BindingError Unit)"]
    let labels := String.intercalate " | " ((action.wireAction :: sortedBy id action.wireAliases).map quote)
    let phase := if action.phase == .transition then
      ["        if phase == .fresh then throw { code := \"transition_before_initialization\", message := \"transition before initialization\" }"] else []
    let argumentValue := if inputs.isEmpty then "" else " { " ++
      String.intercalate ", " (inputs.zipIdx.map fun (input, ii) => s!"{fieldName input.id} := input{ii}") ++ " }"
    branches := branches ++ [lines <| [s!"      | {labels} => do"] ++ phase ++ decoders ++
      [s!"        pure ({quote action.id}, port.{fieldName action.id}{argumentValue})"]]
  let mut observationFields : List String := []
  let mut encoders : List String := []
  let observations := sortedBy (·.id) lock.observations
  for (observation, oi) in observations.zipIdx do
    let (ty, decls) ← lowerType s!"MiTypeO{oi}" observation.type
    declarations := declarations ++ decls
    observationFields := observationFields ++ [s!"  {fieldName observation.id} : {ty}"]
    encoders := encoders ++ [s!"  let value{oi} ← NativeCodec.encode observation.{fieldName observation.id}"]
  let contract := Codec.ModelInterfaceJson.canonicalString (Codec.ModelInterfaceJson.encodeContract lock.contract)
  pure <| lines <|
    ["-- @generated by Mirrors model_interface_gen", "-- target-profile: mirrorlean-v1",
     "-- profile-version: 1", s!"-- semantic-sha256: {lock.semanticDigest}", "-- DO NOT EDIT",
     "import MirrorLean.ModelInterface", s!"namespace {lock.modelModule}Mirror",
     "open MirrorLean MirrorLean.ModelInterface", "set_option linter.unusedVariables false",
     s!"def semanticDigest : String := {quote lock.semanticDigest}",
     s!"def metadata : GeneratedMetadata := " ++ "{ semanticDigest := semanticDigest, contractJson := " ++ quote contract ++ " }",
     "def assertCompatibleConfig (config : ApalacheConfig) : Except BindingError Unit := do",
     s!"  if config.paramVars.getD \"\" != {quote (lock.runProfile.configuredParamVar.getD "")} then",
     "    throw { code := \"configuration_mismatch\", message := \"effective paramVars mismatch\" }"] ++ declarations ++
    ["structure Observation where"] ++ observationFields ++
    ["structure Port where"] ++ methods ++
    ["  observe : IO (Except BindingError Observation)",
     "private def encodeObservation (observation : Observation) : Except BindingError State := do"] ++ encoders ++
    ["  pure (State.ofList [" ++ String.intercalate ", "
      (observations.zipIdx.map fun (o, oi) => s!"({quote o.wireName}, value{oi})") ++ "])",
     runtimeSupport] ++ branches ++ [runtimeFinish,
     "  let runtime ← IO.mkRef ({ counts := #[" ++ String.intercalate ", "
       (actions.map fun a => s!"({quote a.id}, 0)") ++ "] } : RuntimeState)",
     "  pure (.ok {", "    computer := compute port runtime",
     "    coverage := return (← runtime.get).counts",
     "    assertAllActionsCovered := do",
     "      if (← runtime.get).counts.any (fun (_, count) => count == 0) then",
     "        return .error { code := \"uncovered_action\", message := \"declared actions remain uncovered\" }",
     "      pure (.ok ()) })", s!"end {lock.modelModule}Mirror"]

/-- Emit an importable Lean module and the standard owned-file manifest. -/
def emitLean (lock : LockedModelInterface) : EmitResult TypeScript.GeneratedTree := do
  let source ← renderModule lock
  let path := s!"{lock.modelModule}Mirror.lean"
  let manifestPath := ".model-interface-generated.json"
  let manifest := Codec.ModelInterfaceJson.canonicalString (_root_.Lean.Json.mkObj [
    ("files", .arr #[.str manifestPath, .str path]), ("profileVersion", .num 1),
    ("schema", .str "mirrors.model-interface-generated/v1"),
    ("semanticDigest", .str lock.semanticDigest), ("targetProfile", .str "mirrorlean-v1")]) ++ "\n"
  pure { files := [{ relativePath := manifestPath, bytes := manifest.toUTF8 },
    { relativePath := path, bytes := source.toUTF8 }] }
end Shell.ModelInterface.Emit.Lean
