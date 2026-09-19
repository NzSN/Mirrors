import Shell.ModelInterface.Emit.TypeScript

/-! Deterministic Rust ports and fallible MirrorRust bindings. -/
namespace Shell.ModelInterface.Emit.Rust
open Core.ModelInterface
abbrev EmitResult (α : Type) := TypeScript.EmitResult α

private def fail {α : Type} (code message : String) : EmitResult α :=
  .error [{ code, message }]
private def lines (xs : List String) : String := String.intercalate "\n" xs ++ "\n"
private def sortedBy {α : Type} (key : α → String) (xs : List α) : List α :=
  xs.toArray.qsort (fun a b => compare (key a) (key b) != Ordering.gt) |>.toList
private def snake (s : String) : String :=
  String.intercalate "_" ((s.toList.foldl (fun (parts : List String) c =>
    if c.isUpper then parts ++ [String.singleton c.toLower]
    else match parts.reverse with
      | [] => [String.singleton c]
      | p :: rest => rest.reverse ++ [p.push c]) []))
private def quote (s : String) : String :=
  "\"" ++ String.join (s.toList.map fun c =>
    if c == '"' then "\\\"" else if c == '\\' then "\\\\"
    else if c.toNat < 32 || c.toNat == 127 then "\\u{" ++ Nat.repr (c.toNat / 16) ++ String.singleton ("0123456789abcdef".toList[c.toNat % 16]!) ++ "}"
    else String.singleton c) ++ "\""
private def keywords : List String := ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while", "abstract", "become", "box", "do", "final", "gen", "macro", "override", "priv", "try", "typeof", "unsized", "virtual", "yield"]
private def validateNames (ids : List String) (reserved : List String := []) : EmitResult Unit := do
  let mut seen := reserved
  for id in ids do
    let name := snake id
    if id.isEmpty || !(id.toList.head!).isAlpha ||
        !id.toList.all (fun c => c.isAlphanum && c.toNat < 128) ||
        keywords.contains name || seen.contains name then
      fail "MIC-E-NAME-001" s!"mirrorrust-v1 invalid or colliding native name: {id}"
    seen := name :: seen

private def runtimeSupport : String := r###"use mirrorrust::{ApalacheConfig, BindingError, FallibleStateComputer, GeneratedModelInterface, State, Value};
use num_bigint::BigInt;
use std::collections::BTreeMap;

pub trait NativeCodec: Sized {
    fn decode(value: &Value) -> Result<Self, BindingError>;
    fn encode(&self) -> Result<Value, BindingError>;
}
fn shape() -> BindingError { BindingError::new("input_shape_mismatch", "value does not match declared type") }
fn equivalent(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Set(a), Value::Set(b)) => a.len() == b.len() && a.iter().all(|x| b.iter().any(|y| equivalent(x, y))),
        (Value::Map(a), Value::Map(b)) => a.len() == b.len() && a.iter().all(|(k,v)| b.iter().any(|(l,w)| equivalent(k,l) && equivalent(v,w))),
        (Value::Seq(a), Value::Seq(b)) | (Value::Tuple(a), Value::Tuple(b)) => a.len() == b.len() && a.iter().zip(b).all(|(x,y)| equivalent(x,y)),
        (Value::Record(a), Value::Record(b)) => a.len() == b.len() && a.iter().all(|(k,v)| b.get(k).is_some_and(|w| equivalent(v,w))),
        (Value::Variant(a,v), Value::Variant(b,w)) => a == b && equivalent(v,w),
        _ => a == b,
    }
}
fn unique(values: &[Value]) -> Result<(), BindingError> {
    for (i, value) in values.iter().enumerate() {
        if values[..i].iter().any(|other| equivalent(value, other)) { return Err(shape()); }
    }
    Ok(())
}
macro_rules! scalar_codec {
    ($ty:ty, $case:ident) => {
        impl NativeCodec for $ty {
            fn decode(value: &Value) -> Result<Self, BindingError> {
                if let Value::$case(value) = value { Ok(value.clone()) } else { Err(shape()) }
            }
            fn encode(&self) -> Result<Value, BindingError> { Ok(Value::$case(self.clone())) }
        }
    };
}
scalar_codec!(BigInt, Int);
scalar_codec!(bool, Bool);
scalar_codec!(String, Str);
#[derive(Debug, Clone)]
pub struct MirrorNull;
impl NativeCodec for MirrorNull {
    fn decode(value: &Value) -> Result<Self, BindingError> { if matches!(value, Value::Null) { Ok(Self) } else { Err(shape()) } }
    fn encode(&self) -> Result<Value, BindingError> { Ok(Value::Null) }
}
#[derive(Debug, Clone)]
pub struct MirrorSeq<T>(pub Vec<T>);
#[derive(Debug, Clone)]
pub struct MirrorSet<T>(pub Vec<T>);
#[derive(Debug, Clone)]
pub struct MirrorMap<T>(pub BTreeMap<String, T>);
impl<T: NativeCodec> NativeCodec for MirrorSeq<T> {
    fn decode(value: &Value) -> Result<Self, BindingError> {
        if let Value::Seq(items) = value { Ok(Self(items.iter().map(T::decode).collect::<Result<_,_>>()?)) } else { Err(shape()) }
    }
    fn encode(&self) -> Result<Value, BindingError> { Ok(Value::Seq(self.0.iter().map(T::encode).collect::<Result<_,_>>()?)) }
}
impl<T: NativeCodec> NativeCodec for MirrorSet<T> {
    fn decode(value: &Value) -> Result<Self, BindingError> {
        if let Value::Set(items) = value {
            let decoded = items.iter().map(T::decode).collect::<Result<Vec<_>,_>>()?;
            unique(items)?;
            Ok(Self(decoded))
        } else { Err(shape()) }
    }
    fn encode(&self) -> Result<Value, BindingError> {
        let values = self.0.iter().map(T::encode).collect::<Result<Vec<_>,_>>()?;
        unique(&values).map_err(|e| BindingError::new("observation_shape_mismatch", e.message))?;
        Ok(Value::Set(values))
    }
}
impl<T: NativeCodec> NativeCodec for MirrorMap<T> {
    fn decode(value: &Value) -> Result<Self, BindingError> {
        if let Value::Map(items) = value {
            let mut result = BTreeMap::new();
            for (key, value) in items {
                let key = String::decode(key)?;
                if result.insert(key, T::decode(value)?).is_some() { return Err(shape()); }
            }
            Ok(Self(result))
        } else { Err(shape()) }
    }
    fn encode(&self) -> Result<Value, BindingError> {
        Ok(Value::Map(self.0.iter().map(|(k,v)| Ok((Value::Str(k.clone()), v.encode()?))).collect::<Result<_,BindingError>>()?))
    }
}
enum Segment { Field(&'static str), Index(usize), Variant(&'static str) }
fn read_path<'a>(root: &'a Value, path: &[Segment]) -> Result<&'a Value, BindingError> {
    let mut value = root;
    for segment in path {
        value = match (segment, value) {
            (Segment::Field(name), Value::Record(fields)) => fields.get(*name).ok_or_else(shape)?,
            (Segment::Index(index), Value::Seq(items) | Value::Tuple(items)) => items.get(*index).ok_or_else(shape)?,
            (Segment::Variant(tag), Value::Variant(actual, payload)) if *tag == actual => payload,
            _ => return Err(shape()),
        };
    }
    Ok(value)
}
#[derive(Clone, Copy, PartialEq)]
enum Lifecycle { Fresh, Initialized, Poisoned }
"###

/-- Native spelling and declarations for one structural type. Numeric child names
keep arbitrary record keys and variant tags out of Rust identifier namespaces. -/
private partial def lowerType (name : String) (type : ModelType) :
    EmitResult (String × List String) := do
  match type with
  | .int => pure ("BigInt", [])
  | .bool => pure ("bool", [])
  | .str => pure ("String", [])
  | .null => pure ("MirrorNull", [])
  | .seq t | .set t | .map .str t =>
      let (child, decls) ← lowerType (name ++ "Item") t
      let wrapper := match type with
        | .seq _ => "MirrorSeq" | .set _ => "MirrorSet" | _ => "MirrorMap"
      pure (s!"{wrapper}<{child}>", decls)
  | .map _ _ => fail "MIC-E-TYPE-001" "mirrorrust-v1 supports only string-keyed maps"
  | .opaqueItf text => fail "MIC-E-TYPE-001" s!"mirrorrust-v1 cannot emit opaque ITF: {text}"
  | .tuple _ | .record _ =>
      let fields : List (String × ModelType) := match type with
        | .tuple items => items.map fun t => ("", t)
        | .record fields => (sortedBy (fun (f : ModelField) => f.wireName) fields).map fun f => (f.wireName, f.type)
        | _ => []
      let isRecord := match type with | .record _ => true | _ => false
      let children ← fields.zipIdx.mapM fun ((_, t), i) => lowerType s!"{name}F{i}" t
      let declarations := children.zipIdx.map fun ((ty, _), i) => s!"    pub field_{i}: {ty},"
      let decode := (fields.zip children).zipIdx.map fun ((f, (ty, _)), i) =>
        let access := if isRecord then s!"items.get({quote f.1}).ok_or_else(shape)?" else s!"&items[{i}]"
        s!"            field_{i}: <{ty}>::decode({access})?,"
      let encode := fields.zipIdx.map fun (f, i) =>
        if isRecord then s!"        items.insert({quote f.1}.into(), self.field_{i}.encode()?);"
        else s!"        items.push(self.field_{i}.encode()?);"
      let constructor := if isRecord then "Record" else "Tuple"
      pure (name, children.flatMap (·.2) ++ [lines <|
        ["#[derive(Debug, Clone)]", s!"pub struct {name} " ++ "{"] ++ declarations ++
        ["}", s!"impl NativeCodec for {name} " ++ "{",
         "    fn decode(value: &Value) -> Result<Self, BindingError> {",
         s!"        let Value::{constructor}(items) = value else " ++ "{ return Err(shape()); };",
         s!"        if items.len() != {fields.length} " ++ "{ return Err(shape()); }",
         "        Ok(Self {"] ++ decode ++ ["        })", "    }",
         "    fn encode(&self) -> Result<Value, BindingError> {",
         s!"        let mut items = {if isRecord then "BTreeMap" else "Vec"}::new();"] ++ encode ++
        [s!"        Ok(Value::{constructor}(items))", "    }", "}"]])
  | .variant cases =>
      let cases := sortedBy (·.tag) cases
      let children ← cases.zipIdx.mapM fun (c, i) => lowerType s!"{name}C{i}" c.payload
      let variants := children.zipIdx.map fun ((ty, _), i) => s!"    Case{i}({ty}),"
      let decode := (cases.zip children).zipIdx.map fun ((c, (ty, _)), i) =>
        s!"            {quote c.tag} => Ok(Self::Case{i}(<{ty}>::decode(payload)?)),"
      let encode := cases.zipIdx.map fun (c, i) =>
        s!"            Self::Case{i}(value) => Ok(Value::Variant({quote c.tag}.into(), Box::new(value.encode()?))),"
      pure (name, children.flatMap (·.2) ++ [lines <|
        ["#[derive(Debug, Clone)]", s!"pub enum {name} " ++ "{"] ++ variants ++
        ["}", s!"impl NativeCodec for {name} " ++ "{",
         "    fn decode(value: &Value) -> Result<Self, BindingError> {",
         "        let Value::Variant(tag, payload) = value else { return Err(shape()); };",
         "        match tag.as_str() {"] ++ decode ++
        ["            _ => Err(shape()),", "        }", "    }",
         "    fn encode(&self) -> Result<Value, BindingError> {", "        match self {"] ++ encode ++
        ["        }", "    }", "}"]])

private def renderPath (path : List PathSegment) : EmitResult String := do
  let parts ← path.mapM fun segment => match segment with
    | .field name => pure s!"Segment::Field({quote name})"
    | .index n =>
        if n > 4294967295 then fail "MIC-E-PATH-001" "mirrorrust-v1 index exceeds portable usize range"
        else pure s!"Segment::Index({n})"
    | .variantValue tag => pure s!"Segment::Variant({quote tag})"
    | .mapKey _ => fail "MIC-E-PATH-001" "mirrorrust-v1 does not support mapKey paths"
  pure ("&[" ++ String.intercalate ", " parts ++ "]")

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
      fields := fields ++ [s!"    pub {snake input.id}: {ty},"]
      let path ← renderPath input.projection.path
      let root := if input.projection.root == .initialState then "initial" else "payload"
      let label := quote (action.id ++ "." ++ input.id)
      decoders := decoders ++ [s!"                    {snake input.id}: read_path(&{root}, {path}).and_then(<{ty}>::decode).map_err(|e| BindingError::new(e.code, e.message + \" at \" + {label}))?,"]
    if !inputs.isEmpty then
      declarations := declarations ++ [lines <| ["#[derive(Debug, Clone)]", s!"pub struct {action.id}Input " ++ "{"] ++ fields ++ ["}"]]
    let arg := if inputs.isEmpty then "" else s!", input: {action.id}Input"
    methods := methods ++ [s!"    fn {snake action.id}(&mut self{arg}) -> Result<(), BindingError>;"]
    let labels := String.intercalate " | " ((action.wireAction :: sortedBy id action.wireAliases).map quote)
    let phase := if action.phase == .transition then
      ["                if self.lifecycle == Lifecycle::Fresh { return Err(BindingError::new(\"transition_before_initialization\", \"transition before initialization\")); }"] else []
    let inputDecode := if inputs.isEmpty then [] else
      [s!"                let input = {action.id}Input " ++ "{"] ++ decoders ++ ["                };"]
    branches := branches ++ [lines <| [s!"            {labels} => " ++ "{"] ++ phase ++ inputDecode ++
      ["                stage = \"adapter_failure\";",
       s!"                self.port.{snake action.id}({if inputs.isEmpty then "" else "input"})?;",
       s!"                {quote action.id}", "            },"]]
  let mut observationFields : List String := []
  let mut encoders : List String := []
  for (observation, oi) in (sortedBy (·.id) lock.observations).zipIdx do
    let (ty, decls) ← lowerType s!"MiTypeO{oi}" observation.type
    declarations := declarations ++ decls
    observationFields := observationFields ++ [s!"    pub {snake observation.id}: {ty},"]
    encoders := encoders ++ [s!"            state.insert({quote observation.wireName}.into(), observation.{snake observation.id}.encode()?);"]
  let model := lock.modelModule
  let contract := Codec.ModelInterfaceJson.canonicalString (Codec.ModelInterfaceJson.encodeContract lock.contract)
  pure <| lines <|
    ["// @generated by Mirrors model_interface_gen", "// target-profile: mirrorrust-v1",
     "// profile-version: 1", s!"// semantic-sha256: {lock.semanticDigest}", "// DO NOT EDIT",
     runtimeSupport, s!"pub const SEMANTIC_DIGEST: &str = {quote lock.semanticDigest};",
     s!"pub const CONTRACT_JSON: &str = {quote contract};",
     "pub fn model_interface() -> GeneratedModelInterface {",
     "    GeneratedModelInterface { semantic_digest: SEMANTIC_DIGEST.into(), contract_json: CONTRACT_JSON.into() }", "}",
     "pub fn assert_compatible_config(config: &ApalacheConfig) -> Result<(), BindingError> {",
     s!"    if config.param_vars.as_deref().unwrap_or(\"\") != {quote (lock.runProfile.configuredParamVar.getD "")} " ++ "{",
     "        return Err(BindingError::new(\"configuration_mismatch\", \"effective paramVars mismatch\"));", "    }", "    Ok(())", "}"] ++ declarations ++
    ["#[derive(Debug, Clone)]", s!"pub struct {model}Observation " ++ "{"] ++ observationFields ++
    ["}", s!"pub trait {model}Port " ++ "{"] ++ methods ++
    [s!"    fn observe(&mut self) -> Result<{model}Observation, BindingError>;", "}",
     s!"pub struct {model}Binding<P: {model}Port> " ++ "{",
     "    port: P,", "    lifecycle: Lifecycle,", "    counts: BTreeMap<&'static str, usize>,", "}",
     s!"pub fn bind_{snake model}<P: {model}Port>(port: P, config: &ApalacheConfig) -> Result<{model}Binding<P>, BindingError> " ++ "{",
     "    assert_compatible_config(config)?;",
     s!"    Ok({model}Binding " ++ "{ port, lifecycle: Lifecycle::Fresh, counts: BTreeMap::from([" ++
       String.intercalate ", " (actions.map fun a => s!"({quote a.id}, 0)") ++ "]) })", "}",
     s!"impl<P: {model}Port> {model}Binding<P> " ++ "{",
     "    pub fn into_local_binding(self) -> Result<mirrorrust::LocalBinding, BindingError> where P: 'static {",
     "        let semantic_digest = mirrorrust::SemanticDigest::from_hex(SEMANTIC_DIGEST).map_err(|e| BindingError::new(\"descriptor_digest_invalid\", e.to_string()))?;",
     "        Ok(mirrorrust::LocalBinding { semantic_digest, computer: Box::new(self), assert_compatible_config: Box::new(assert_compatible_config), dispose: Box::new(|| Ok(())) })",
     "    }",
     "    pub fn coverage(&self) -> BTreeMap<&'static str, usize> { self.counts.clone() }",
     "    pub fn assert_all_actions_covered(&self) -> Result<(), BindingError> {",
     "        if self.counts.values().any(|count| *count == 0) { return Err(BindingError::new(\"uncovered_action\", \"declared actions remain uncovered\")); }",
     "        Ok(())", "    }", "}",
     s!"impl<P: {model}Port> FallibleStateComputer for {model}Binding<P> " ++ "{",
     "    fn compute(&mut self, action: &str, params: &State, _prev: &State) -> Result<State, BindingError> {",
     "        if self.lifecycle == Lifecycle::Poisoned { return Err(BindingError::new(\"binding_poisoned\", \"binding is poisoned\")); }",
     "        let mut stage = \"input_shape_mismatch\";",
     "        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {",
     "            let initial = Value::Record(params.iter().filter(|(k,_)| !k.starts_with('#') && *k != \"action_taken\" && *k != \"parameters\").map(|(k,v)| (k.clone(), v.clone())).collect());",
     "            let payload = Value::Record(params.clone());",
     "            let stable_action = match action {"] ++ branches ++
    ["                _ => return Err(BindingError::new(\"unknown_action\", \"unknown wire action\")),", "            };",
     "            stage = \"observation_shape_mismatch\";",
     "            let observation = self.port.observe()?;", "            let mut state = State::new();"] ++ encoders ++
    ["            *self.counts.get_mut(stable_action).expect(\"generated action\") += 1;",
     "            self.lifecycle = Lifecycle::Initialized;", "            Ok(state)", "        }));",
     "        match result {", "            Ok(Ok(state)) => Ok(state),",
     "            Ok(Err(error)) => {", "                self.lifecycle = Lifecycle::Poisoned;",
     "                if stage == \"input_shape_mismatch\" { Err(error) } else { Err(BindingError::new(stage, error.message)) }", "            },",
     "            Err(_) => { self.lifecycle = Lifecycle::Poisoned; Err(BindingError::new(stage, \"binding callback panicked\")) },",
     "        }", "    }", "}"]

/-- Emit a Rust module and the standard owned-file manifest. -/
def emitRust (lock : LockedModelInterface) : EmitResult TypeScript.GeneratedTree := do
  let source ← renderModule lock
  let path := s!"{lock.modelModule}Mirror.generated.rs"
  let manifestPath := ".model-interface-generated.json"
  let manifest := Codec.ModelInterfaceJson.canonicalString (Lean.Json.mkObj [
    ("files", .arr #[.str manifestPath, .str path]),
    ("profileVersion", .num 1), ("schema", .str "mirrors.model-interface-generated/v1"),
    ("semanticDigest", .str lock.semanticDigest), ("targetProfile", .str "mirrorrust-v1")]) ++ "\n"
  pure { files := [{ relativePath := manifestPath, bytes := manifest.toUTF8 }, { relativePath := path, bytes := source.toUTF8 }] }
end Shell.ModelInterface.Emit.Rust
