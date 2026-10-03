import Shell.ModelInterface.Emit.TypeScript

/-!
# C++ model-interface emitter

The `mirrorcpp-v1` target emits one header-only, model-specific port and
`StateComputer` binding.  Version 1 covers the portable model-interface type
baseline and rejects target-specific exclusions deterministically.
-/

namespace Shell.ModelInterface.Emit.Cpp

open Core.ModelInterface

abbrev EmitDiagnostic := TypeScript.EmitDiagnostic
abbrev GeneratedFile := TypeScript.GeneratedFile
abbrev GeneratedTree := TypeScript.GeneratedTree
abbrev EmitResult (α : Type) := Except (List EmitDiagnostic) α

private def targetProfile : String := "mirrorcpp-v1"
private def profileVersion : Nat := 1
private def manifestPath : String := ".model-interface-generated.json"

private def fail {α : Type} (code message : String) : EmitResult α :=
  .error [{ code, message }]

private def sortedBy {α : Type} (key : α → String) (xs : List α) : List α :=
  xs.toArray.qsort (fun a b => compare (key a) (key b) != Ordering.gt) |>.toList

private def sortedStrings (xs : List String) : List String := sortedBy id xs

private def duplicateStrings (xs : List String) : List String :=
  xs.foldl (fun duplicates value =>
    if xs.count value > 1 && !duplicates.contains value then
      duplicates ++ [value]
    else duplicates) []

private def lines (xs : List String) : String := String.intercalate "\n" xs ++ "\n"

private def lowerFirst (value : String) : String :=
  match value.toList with
  | [] => value
  | first :: rest =>
      let lowered := if 'A' ≤ first && first ≤ 'Z' then
        Char.ofNat (first.toNat + ('a'.toNat - 'A'.toNat)) else first
      String.ofList (lowered :: rest)

private def hexDigit (value : Nat) : Char :=
  if value < 10 then Char.ofNat ('0'.toNat + value)
  else Char.ofNat ('a'.toNat + value - 10)

private def cppString (value : String) : String :=
  let escaped := value.toList.flatMap fun character =>
    match character with
    | '"' => ['\\', '"']
    | '\\' => ['\\', '\\']
    | '\n' => ['\\', 'n']
    | '\r' => ['\\', 'r']
    | '\t' => ['\\', 't']
    | character =>
        if character.toNat < 0x20 then
          ['\\', 'u', '0', '0', hexDigit (character.toNat / 16),
            hexDigit (character.toNat % 16)]
        else [character]
  "\"" ++ String.ofList escaped ++ "\""

/-- Length-delimited UTF-8 data, including embedded NUL. Adjacent byte literals
prevent a following hexadecimal character from extending a hex escape. -/
private def cppByteString (value : String) : String :=
  let bytes := value.toUTF8
  let literals := bytes.data.toList.map fun byte =>
    "\"\\x" ++ String.ofList [hexDigit (byte.toNat / 16), hexDigit (byte.toNat % 16)] ++ "\""
  let literal := if literals.isEmpty then "\"\"" else String.intercalate "" literals
  s!"std::string({literal}, {bytes.size})"

private def cppKeywords : List String := [
  "alignas", "alignof", "and", "and_eq", "asm", "atomic_cancel",
  "atomic_commit", "atomic_noexcept", "auto", "bitand", "bitor", "bool",
  "break", "case", "catch", "char", "char8_t", "char16_t", "char32_t",
  "class", "compl", "concept", "const", "consteval", "constexpr",
  "constinit", "const_cast", "continue", "co_await", "co_return",
  "co_yield", "decltype", "default", "delete", "do", "double",
  "dynamic_cast", "else", "enum", "explicit", "export", "extern", "false",
  "float", "for", "friend", "goto", "if", "inline", "int", "long",
  "mutable", "namespace", "new", "noexcept", "not", "not_eq", "nullptr",
  "operator", "or", "or_eq", "private", "protected", "public", "reflexpr",
  "register", "reinterpret_cast", "requires", "return", "short", "signed",
  "sizeof", "static", "static_assert", "static_cast", "struct", "switch",
  "synchronized", "template", "this", "thread_local", "throw", "true",
  "try", "typedef", "typeid", "typename", "union", "unsigned", "using",
  "virtual", "void", "volatile", "wchar_t", "while", "xor", "xor_eq"]

private def validateName (context value : String) (profile : String := targetProfile) : EmitResult Unit := do
  let validFirst (character : Char) : Bool :=
    ('a' ≤ character && character ≤ 'z') ||
    ('A' ≤ character && character ≤ 'Z')
  let validRest (character : Char) : Bool :=
    validFirst character || ('0' ≤ character && character ≤ '9') ||
      character == '_'
  match value.toList with
  | [] => fail "MIC-E-NAME-001" s!"{profile} {context} name is empty"
  | first :: rest =>
      if !validFirst first || !rest.all validRest then
        fail "MIC-E-NAME-001"
          s!"{profile} {context} name is not a portable C++ identifier: {value}"
  if cppKeywords.contains (lowerFirst value) then
    fail "MIC-E-NAME-001" s!"{profile} {context} name is a C++ keyword: {value}"
  if value.startsWith "_" then
    fail "MIC-E-NAME-001" s!"{profile} {context} name uses a reserved prefix: {value}"

private def validateNativeNamespace (context : String) (stableIds : List String)
    (mandatory : List String := []) (profile : String := targetProfile) : EmitResult Unit := do
  for stableId in stableIds do
    let _ ← validateName context stableId profile
  match duplicateStrings (mandatory ++ stableIds.map lowerFirst) with
  | collision :: _ =>
      fail "MIC-E-NAME-001"
        s!"{profile} {context} contains colliding native identifier {collision}"
  | [] => pure ()

private def validateNativeNamespaces (lock : LockedModelInterface) (profile : String) : EmitResult Unit := do
  let _ ← validateName "model" lock.modelModule profile
  let actions := lock.initializers ++ lock.actions
  let _ ← validateNativeNamespace "implementation port" (actions.map (·.id)) ["observe"] profile
  for action in actions do
    let _ ← validateNativeNamespace s!"input fields for action {action.id}"
      (action.inputs.map (·.id)) [] profile
  let _ ← validateNativeNamespace "observation fields" (lock.observations.map (·.id)) [] profile
  pure ()

private partial def nativeType (profile : String) : ModelType → EmitResult String
  | .int => pure "mirrorcpp::Value::Int"
  | .bool => pure "bool"
  | .str => pure "std::string"
  | .null => pure "MirrorNull"
  | .set element => return s!"MirrorSet<{← nativeType profile element}>"
  | .seq element => return s!"MirrorSeq<{← nativeType profile element}>"
  | .tuple elements => do
      let types ← elements.mapM (nativeType profile)
      return s!"MirrorTuple<{String.intercalate ", " types}>"
  | .record fields => do
      let fields := sortedBy (·.wireName) fields
      let types ← fields.mapM fun field => do
        let type ← nativeType profile field.type
        return s!"RecordField<{cppString field.wireName}, {type}>"
      return s!"MirrorRecord<{String.intercalate ", " types}>"
  | .map .str value => return s!"MirrorMap<{← nativeType profile value}>"
  | .map .int value =>
      if profile == "mirrorcpp-v2" then
        return s!"MirrorMap<{← nativeType profile value}, mirrorcpp::Value::Int>"
      else fail "MIC-E-TYPE-001" "mirrorcpp-v1 supports only string-keyed maps"
  | .map _ _ => fail "MIC-E-TYPE-001"
      "mirrorcpp-v1 supports only string-keyed maps"
  | .variant cases => do
      let cases := sortedBy (·.tag) cases
      let types ← cases.mapM fun item => do
        let type ← nativeType profile item.payload
        return s!"VariantCase<{cppString item.tag}, {type}>"
      return s!"MirrorVariant<{String.intercalate ", " types}>"
  | .opaqueItf description => fail "MIC-E-TYPE-001"
      s!"mirrorcpp-v1 cannot emit opaque ITF type: {description}"

private def renderPathSegment (profile : String) : PathSegment → EmitResult String
  | .field name => pure s!"PathSegment::field({cppString name})"
  | .index index => pure s!"PathSegment::index({index})"
  | .variantValue tag => pure s!"PathSegment::variant({cppString tag})"
  | .mapKey key =>
      if profile == "mirrorcpp-v2" then
        match key with
        | .str text => pure s!"PathSegment::map_key(mirrorcpp::Value({cppByteString text}))"
        | .int integer => pure s!"PathSegment::map_key(mirrorcpp::Value(mirrorcpp::Value::Int(std::string({cppString (toString integer)}))))"
        | _ => fail "MIC-E-PATH-001" "mirrorcpp-v2 supports only string and integer mapKey literals"
      else fail "MIC-E-PATH-001"
      "mirrorcpp-v1 does not support mapKey paths"

private def renderPath (profile : String) (path : List PathSegment) : EmitResult String := do
  let segments ← path.mapM (renderPathSegment profile)
  pure ("std::vector<PathSegment>{" ++ String.intercalate ", " segments ++ "}")

private partial def unsupportedTypes (profile : String) (context : EmitDiagnostic) (path : String) :
    ModelType → List EmitDiagnostic
  | .map key value =>
      (if key == .str || (profile == "mirrorcpp-v2" && key == .int) then [] else [{ context with
        code := "MIC-E-TYPE-001"
        message := context.message ++ s!": {path}.key: {profile} does not support this map key type"
        arguments := context.arguments ++ [("typePath", path ++ ".key")] }]) ++
      unsupportedTypes profile context (path ++ ".value") value
  | .opaqueItf description => [{ context with
        code := "MIC-E-TYPE-001"
        message := context.message ++ s!": {path}: opaque ITF type {description} has no native representation"
        arguments := context.arguments ++ [("typePath", path)] }]
  | .set element | .seq element => unsupportedTypes profile context (path ++ ".element") element
  | .tuple elements => elements.zipIdx.flatMap fun (element, index) =>
      unsupportedTypes profile context (path ++ s!"[{index}]") element
  | .record fields => (sortedBy (·.wireName) fields).flatMap fun field =>
      unsupportedTypes profile context (path ++ ".field[" ++ cppString field.wireName ++ "]") field.type
  | .variant cases => (sortedBy (·.tag) cases).flatMap fun item =>
      unsupportedTypes profile context (path ++ ".case[" ++ cppString item.tag ++ "]") item.payload
  | _ => []

/-- Accumulate independent lowering findings before constructing any output.
Pointers refer to the typed lock, not invented TLA+ source positions. -/
def targetDiagnostics (lock : LockedModelInterface) (profile : String := "mirrorcpp-v1") : List EmitDiagnostic :=
  let actionFindings (group : String) (actions : List ResolvedAction) :=
    actions.zipIdx.flatMap fun (action, actionIndex) =>
      action.inputs.zipIdx.flatMap fun (input, inputIndex) =>
        let pointer := s!"/{group}/{actionIndex}/inputs/{inputIndex}/projection"
        let context : EmitDiagnostic := {
          code := "MIC-E-TYPE-001"
          message := s!"model {lock.modelModule}, action {action.id}, input {input.id} at {pointer}"
          subject := "input", stableId := some input.id, pointer := some pointer
          arguments := [("model", lock.modelModule), ("action", action.id),
            ("input", input.id), ("target", profile)] }
        unsupportedTypes profile context "type" input.projection.type ++
          input.projection.path.zipIdx.filterMap fun (segment, index) =>
            match segment with
            | .mapKey key =>
                if profile == "mirrorcpp-v2" && (match key with | .int _ | .str _ => true | _ => false) then none
                else some { context with
                code := "MIC-E-PATH-001"
                message := context.message ++ s!": path[{index}]: {profile} does not support this mapKey literal"
                arguments := context.arguments ++ [("projectionSegment", toString index)] }
            | _ => none
  actionFindings "initializers" lock.initializers ++ actionFindings "actions" lock.actions ++
    lock.observations.zipIdx.flatMap fun (observation, index) =>
      let pointer := s!"/observations/{index}/type"
      unsupportedTypes profile {
        code := "MIC-E-TYPE-001"
        message := s!"model {lock.modelModule}, observation {observation.id} at {pointer}"
        subject := "observation", stableId := some observation.id, pointer := some pointer
        arguments := [("model", lock.modelModule), ("observation", observation.id),
          ("wireName", observation.wireName), ("target", profile)] } "type" observation.type

private def renderInputStruct (profile : String) (action : ResolvedAction) : EmitResult String := do
  if action.inputs.isEmpty then return ""
  let fields ← (sortedBy (·.id) action.inputs).mapM fun input => do
    let _ ← validateName "input" input.id profile
    let type ← nativeType profile input.projection.type
    pure s!"  {type} {lowerFirst input.id};"
  pure <| lines ([s!"struct {action.id}Input " ++ "{"] ++ fields ++ ["};"])

private def renderObservation (profile : String) (modelName : String)
    (observations : List ResolvedObservation) : EmitResult String := do
  let fields ← (sortedBy (·.id) observations).mapM fun observation => do
    let _ ← validateName "observation" observation.id
    let type ← nativeType profile observation.type
    pure s!"  {type} {lowerFirst observation.id};"
  pure <| lines ([s!"struct {modelName}Observation " ++ "{"] ++ fields ++ ["};"])

private def renderPortMethod (action : ResolvedAction) : EmitResult String := do
  let _ ← validateName "action" action.id
  if action.inputs.isEmpty then
    pure s!"  virtual void {lowerFirst action.id}() = 0;"
  else
    pure s!"  virtual void {lowerFirst action.id}(const {action.id}Input& input) = 0;"

private def renderInputDecoder (profile : String) (action : ResolvedAction) : EmitResult String := do
  if action.inputs.isEmpty then return ""
  let fields ← (sortedBy (·.id) action.inputs).mapM fun input => do
    let root := match input.projection.root with
      | .initialState => "comparable_initial_state(payload)"
      | .stepParameters => "payload"
    let path ← renderPath profile input.projection.path
    let type ← nativeType profile input.projection.type
    pure s!"      .{lowerFirst input.id} = decode_native<{type}>(read_path({root}, {path}, {cppString (action.id ++ "." ++ input.id)}), {cppString (action.id ++ "." ++ input.id)}),"
  pure <| lines ([s!"inline {action.id}Input decode_{lowerFirst action.id}_input(const mirrorcpp::State& payload) " ++ "{",
    s!"  return {action.id}Input" ++ "{"] ++ fields ++ ["  };", "}"])

private def renderActionBranch (isFirst : Bool) (action : ResolvedAction) : EmitResult String := do
  let labels := action.wireAction :: sortedStrings action.wireAliases
  let condition := String.intercalate " || "
    (labels.map fun label => s!"wire_action == {cppString label}")
  let precondition := if action.phase == .transition then
    ["      if (runtime->lifecycle == Lifecycle::fresh) {",
     "        throw binding_error(\"transition_before_initialization\", \"transition before initialization\");",
     "      }"] else []
  let call := if action.inputs.isEmpty then
    ["      stage = Stage::adapter;",
     s!"      runtime->port->{lowerFirst action.id}();"]
  else
    ["      stage = Stage::input;",
     s!"      const auto input = decode_{lowerFirst action.id}_input(payload);",
     "      stage = Stage::adapter;",
     s!"      runtime->port->{lowerFirst action.id}(input);"]
  pure <| lines <| [s!"    {if isFirst then "if" else "else if"} ({condition}) " ++ "{"] ++
    precondition ++ call ++
    ["      if (runtime->lifecycle == Lifecycle::poisoned) throw binding_error(\"adapter_failure\", \"reentrant callback poisoned the binding\");",
     "      runtime->lifecycle = Lifecycle::initialized;",
     s!"      stable_action = {cppString action.id};",
     "    }"]

private def renderObservationEncoder (profile : String) (modelName : String)
    (observations : List ResolvedObservation) : EmitResult String := do
  let assignments ← (sortedBy (·.id) observations).mapM fun observation => do
    let type ← nativeType profile observation.type
    pure s!"  state.emplace({cppString observation.wireName}, encode_native<{type}>(observation.{lowerFirst observation.id}, {cppString (modelName ++ "Observation." ++ observation.id)}));"
  pure <| lines ([s!"inline mirrorcpp::State encode_{lowerFirst modelName}_observation(const {modelName}Observation& observation) " ++ "{",
    "  mirrorcpp::State state;"] ++ assignments ++ ["  return state;", "}"])

private def runtimeSupport : String := lines [
  "enum class Lifecycle { fresh, initialized, poisoned };",
  "enum class Stage { dispatch, input, adapter, observation };",
  "",
  "class BindingError : public mirrorcpp::ModelInterfaceBindingError {",
  " public:",
  "  BindingError(std::string code, std::string message)",
  "      : mirrorcpp::ModelInterfaceBindingError(std::move(code), std::move(message)) {}",
  "};",
  "",
  "inline BindingError binding_error(std::string code, std::string message) {",
  "  return BindingError(std::move(code), std::move(message));",
  "}",
  "",
  "struct PathSegment {",
  "  enum class Kind { field, index, variant_value };",
  "  Kind kind;",
  "  std::string text;",
  "  std::size_t position = 0;",
  "  static PathSegment field(std::string value) { return {Kind::field, std::move(value), 0}; }",
  "  static PathSegment index(std::size_t value) { return {Kind::index, {}, value}; }",
  "  static PathSegment variant(std::string value) { return {Kind::variant_value, std::move(value), 0}; }",
  "};",
  "",
  "inline mirrorcpp::State comparable_initial_state(const mirrorcpp::State& root) {",
  "  mirrorcpp::State filtered;",
  "  for (const auto& [name, value] : root) {",
  "    if (!name.starts_with(\"#\") && name != \"action_taken\" && name != \"parameters\") {",
  "      filtered.emplace(name, value);",
  "    }",
  "  }",
  "  return filtered;",
  "}",
  "",
  "inline mirrorcpp::Value read_path(const mirrorcpp::State& root,",
  "    const std::vector<PathSegment>& path, std::string_view label) {",
  "  mirrorcpp::Value value(mirrorcpp::Value::Record{root});",
  "  // Own a selected child before replacing its containing value.",
  "  for (const auto& segment : path) {",
  "    if (segment.kind == PathSegment::Kind::field) {",
  "      if (!value.is<mirrorcpp::Value::Record>()) throw binding_error(\"input_shape_mismatch\", std::string(label) + \": record expected\");",
  "      const auto& fields = value.get<mirrorcpp::Value::Record>().fields;",
  "      const auto found = fields.find(segment.text);",
  "      if (found == fields.end()) throw binding_error(\"input_shape_mismatch\", std::string(label) + \": missing field \" + segment.text);",
  "      value = mirrorcpp::Value(found->second);",
  "    } else if (segment.kind == PathSegment::Kind::index) {",
  "      const std::vector<mirrorcpp::Value>* values = nullptr;",
  "      if (value.is<mirrorcpp::Value::Seq>()) values = &value.get<mirrorcpp::Value::Seq>().elems;",
  "      if (value.is<mirrorcpp::Value::Tuple>()) values = &value.get<mirrorcpp::Value::Tuple>().elems;",
  "      if (values == nullptr || segment.position >= values->size()) throw binding_error(\"input_shape_mismatch\", std::string(label) + \": index out of range\");",
  "      value = mirrorcpp::Value((*values)[segment.position]);",
  "    } else {",
  "      if (!value.is<mirrorcpp::Value::Variant>() || value.get<mirrorcpp::Value::Variant>().tag != segment.text) throw binding_error(\"input_shape_mismatch\", std::string(label) + \": variant mismatch\");",
  "      value = mirrorcpp::Value(*value.get<mirrorcpp::Value::Variant>().value);",
  "    }",
  "  }",
  "  return value;",
  "}",
  "",
  "struct MirrorNull {};",
  "template <typename T> struct MirrorSet { std::vector<T> values; };",
  "template <typename T> struct MirrorSeq { std::vector<T> values; };",
  "template <typename... T> struct MirrorTuple { std::tuple<T...> values; };",
  "",
  "template <std::size_t N> struct FixedString {",
  "  char value[N];",
  "  constexpr FixedString(const char (&source)[N]) { std::copy_n(source, N, value); }",
  "  constexpr std::string_view view() const { return {value, N - 1}; }",
  "};",
  "template <FixedString Name, typename T> struct RecordField {",
  "  using value_type = T;",
  "  static constexpr auto name = Name;",
  "  T value;",
  "};",
  "template <typename... Fields> struct MirrorRecord { std::tuple<Fields...> fields; };",
  "template <typename T> struct MirrorMap { std::vector<std::pair<std::string, T>> entries; };",
  "template <FixedString Name, typename T> struct VariantCase {",
  "  using value_type = T;",
  "  static constexpr auto name = Name;",
  "  T value;",
  "};",
  "template <typename... Cases> struct MirrorVariant { std::variant<Cases...> value; };",
  "template <> struct MirrorVariant<> { MirrorVariant() = delete; };",
  "",
  "inline std::string child_path(std::string_view path, std::string_view child) {",
  "  return std::string(path) + \".\" + std::string(child);",
  "}",
  "inline void require_unique(const std::vector<mirrorcpp::Value>& values, std::string_view path) {",
  "  for (std::size_t i = 0; i < values.size(); ++i) {",
  "    for (std::size_t j = i + 1; j < values.size(); ++j) {",
  "      if (values[i] == values[j]) throw binding_error(\"observation_shape_mismatch\", std::string(path) + \": duplicate set element or map key\");",
  "    }",
  "  }",
  "}",
  "",
  "template <typename T> struct NativeCodec;",
  "template <typename T> T decode_native(const mirrorcpp::Value& value, std::string_view path) { return NativeCodec<T>::decode(value, path); }",
  "template <typename T> mirrorcpp::Value encode_native(const T& value, std::string_view path) { return NativeCodec<T>::encode(value, path); }",
  "",
  "template <> struct NativeCodec<mirrorcpp::Value::Int> {",
  "  static mirrorcpp::Value::Int decode(const mirrorcpp::Value& value, std::string_view path) {",
  "    if (!value.is_int()) throw binding_error(\"input_shape_mismatch\", std::string(path) + \": integer expected\");",
  "    return value.get<mirrorcpp::Value::Int>();",
  "  }",
  "  static mirrorcpp::Value encode(const mirrorcpp::Value::Int& value, std::string_view) { return mirrorcpp::Value(value); }",
  "};",
  "template <> struct NativeCodec<bool> {",
  "  static bool decode(const mirrorcpp::Value& value, std::string_view path) {",
  "    if (!value.is_bool()) throw binding_error(\"input_shape_mismatch\", std::string(path) + \": bool expected\");",
  "    return value.get<bool>();",
  "  }",
  "  static mirrorcpp::Value encode(bool value, std::string_view) { return mirrorcpp::Value(value); }",
  "};",
  "template <> struct NativeCodec<std::string> {",
  "  static std::string decode(const mirrorcpp::Value& value, std::string_view path) {",
  "    if (!value.is_str()) throw binding_error(\"input_shape_mismatch\", std::string(path) + \": string expected\");",
  "    return value.get<std::string>();",
  "  }",
  "  static mirrorcpp::Value encode(const std::string& value, std::string_view) { return mirrorcpp::Value(value); }",
  "};",
  "template <> struct NativeCodec<MirrorNull> {",
  "  static MirrorNull decode(const mirrorcpp::Value& value, std::string_view path) {",
  "    if (!value.is_null()) throw binding_error(\"input_shape_mismatch\", std::string(path) + \": null expected\");",
  "    return {};",
  "  }",
  "  static mirrorcpp::Value encode(MirrorNull, std::string_view) { return mirrorcpp::Value(nullptr); }",
  "};",
  "template <typename T> struct NativeCodec<MirrorSet<T>> {",
  "  static MirrorSet<T> decode(const mirrorcpp::Value& value, std::string_view path) {",
  "    if (!value.is<mirrorcpp::Value::Set>()) throw binding_error(\"input_shape_mismatch\", std::string(path) + \": set expected\");",
  "    const auto& source = value.get<mirrorcpp::Value::Set>().elems;",
  "    for (std::size_t i = 0; i < source.size(); ++i) for (std::size_t j = i + 1; j < source.size(); ++j) if (source[i] == source[j]) throw binding_error(\"input_shape_mismatch\", std::string(path) + \": duplicate set element\");",
  "    MirrorSet<T> result;",
  "    for (std::size_t i = 0; i < source.size(); ++i) result.values.push_back(decode_native<T>(source[i], std::string(path) + \"[\" + std::to_string(i) + \"]\"));",
  "    return result;",
  "  }",
  "  static mirrorcpp::Value encode(const MirrorSet<T>& value, std::string_view path) {",
  "    std::vector<mirrorcpp::Value> encoded;",
  "    for (std::size_t i = 0; i < value.values.size(); ++i) encoded.push_back(encode_native<T>(value.values[i], std::string(path) + \"[\" + std::to_string(i) + \"]\"));",
  "    require_unique(encoded, path);",
  "    return mirrorcpp::Value(mirrorcpp::Value::Set{std::move(encoded)});",
  "  }",
  "};",
  "template <typename T> struct NativeCodec<MirrorSeq<T>> {",
  "  static MirrorSeq<T> decode(const mirrorcpp::Value& value, std::string_view path) {",
  "    if (!value.is<mirrorcpp::Value::Seq>()) throw binding_error(\"input_shape_mismatch\", std::string(path) + \": sequence expected\");",
  "    MirrorSeq<T> result; const auto& source = value.get<mirrorcpp::Value::Seq>().elems;",
  "    for (std::size_t i = 0; i < source.size(); ++i) result.values.push_back(decode_native<T>(source[i], std::string(path) + \"[\" + std::to_string(i) + \"]\"));",
  "    return result;",
  "  }",
  "  static mirrorcpp::Value encode(const MirrorSeq<T>& value, std::string_view path) {",
  "    std::vector<mirrorcpp::Value> encoded; for (std::size_t i = 0; i < value.values.size(); ++i) encoded.push_back(encode_native<T>(value.values[i], std::string(path) + \"[\" + std::to_string(i) + \"]\"));",
  "    return mirrorcpp::Value(mirrorcpp::Value::Seq{std::move(encoded)});",
  "  }",
  "};",
  "template <typename... T> struct NativeCodec<MirrorTuple<T...>> {",
  "  template <std::size_t... I> static MirrorTuple<T...> decode_items(const std::vector<mirrorcpp::Value>& source, std::string_view path, std::index_sequence<I...>) {",
  "    return {std::tuple<T...>{decode_native<T>(source[I], std::string(path) + \"[\" + std::to_string(I) + \"]\")...}};",
  "  }",
  "  static MirrorTuple<T...> decode(const mirrorcpp::Value& value, std::string_view path) {",
  "    if (!value.is<mirrorcpp::Value::Tuple>() || value.get<mirrorcpp::Value::Tuple>().elems.size() != sizeof...(T)) throw binding_error(\"input_shape_mismatch\", std::string(path) + \": tuple shape mismatch\");",
  "    return decode_items(value.get<mirrorcpp::Value::Tuple>().elems, path, std::index_sequence_for<T...>{});",
  "  }",
  "  template <std::size_t... I> static mirrorcpp::Value encode_items(const MirrorTuple<T...>& value, std::string_view path, std::index_sequence<I...>) {",
  "    std::vector<mirrorcpp::Value> encoded{encode_native<std::tuple_element_t<I, std::tuple<T...>>>(std::get<I>(value.values), std::string(path) + \"[\" + std::to_string(I) + \"]\")...};",
  "    return mirrorcpp::Value(mirrorcpp::Value::Tuple{std::move(encoded)});",
  "  }",
  "  static mirrorcpp::Value encode(const MirrorTuple<T...>& value, std::string_view path) { return encode_items(value, path, std::index_sequence_for<T...>{}); }",
  "};",
  "template <typename Field> void encode_record_field(mirrorcpp::Value::Record& target, const Field& field, std::string_view path) {",
  "  target.fields.emplace(std::string(Field::name.view()), encode_native<typename Field::value_type>(field.value, child_path(path, Field::name.view())));",
  "}",
  "template <typename... Fields> struct NativeCodec<MirrorRecord<Fields...>> {",
  "  static MirrorRecord<Fields...> decode(const mirrorcpp::Value& value, std::string_view path) {",
  "    if (!value.is<mirrorcpp::Value::Record>()) throw binding_error(\"input_shape_mismatch\", std::string(path) + \": record expected\");",
  "    const auto& source = value.get<mirrorcpp::Value::Record>().fields;",
  "    if (source.size() != sizeof...(Fields) || (!(source.contains(std::string(Fields::name.view()))) || ...)) throw binding_error(\"input_shape_mismatch\", std::string(path) + \": record fields mismatch\");",
  "    return {std::tuple<Fields...>{Fields{decode_native<typename Fields::value_type>(source.at(std::string(Fields::name.view())), child_path(path, Fields::name.view()))}...}};",
  "  }",
  "  static mirrorcpp::Value encode(const MirrorRecord<Fields...>& value, std::string_view path) {",
  "    mirrorcpp::Value::Record result; std::apply([&](const auto&... field) { (encode_record_field(result, field, path), ...); }, value.fields); return mirrorcpp::Value(std::move(result));",
  "  }",
  "};",
  "template <typename T> struct NativeCodec<MirrorMap<T>> {",
  "  static MirrorMap<T> decode(const mirrorcpp::Value& value, std::string_view path) {",
  "    if (!value.is<mirrorcpp::Value::Map>()) throw binding_error(\"input_shape_mismatch\", std::string(path) + \": map expected\");",
  "    MirrorMap<T> result; std::set<std::string> keys; const auto& source = value.get<mirrorcpp::Value::Map>().entries;",
  "    for (std::size_t i = 0; i < source.size(); ++i) { if (!source[i].first.is_str()) throw binding_error(\"input_shape_mismatch\", std::string(path) + \": string map key expected\"); const auto key = source[i].first.get<std::string>(); if (!keys.insert(key).second) throw binding_error(\"input_shape_mismatch\", std::string(path) + \": duplicate map key\"); result.entries.emplace_back(key, decode_native<T>(source[i].second, child_path(path, key))); } return result;",
  "  }",
  "  static mirrorcpp::Value encode(const MirrorMap<T>& value, std::string_view path) {",
  "    mirrorcpp::Value::Map result; std::set<std::string> keys; for (const auto& [key, item] : value.entries) { if (!keys.insert(key).second) throw binding_error(\"observation_shape_mismatch\", std::string(path) + \": duplicate map key\"); result.entries.emplace_back(mirrorcpp::Value(key), encode_native<T>(item, child_path(path, key))); } return mirrorcpp::Value(std::move(result));",
  "  }",
  "};",
  "template <typename... Cases> struct NativeCodec<MirrorVariant<Cases...>> {",
  "  static MirrorVariant<Cases...> decode(const mirrorcpp::Value& value, std::string_view path) {",
  "    if (!value.is<mirrorcpp::Value::Variant>()) throw binding_error(\"input_shape_mismatch\", std::string(path) + \": variant expected\");",
  "    const auto& source = value.get<mirrorcpp::Value::Variant>(); std::optional<MirrorVariant<Cases...>> result;",
  "    ([&] { if (source.tag == Cases::name.view()) result = MirrorVariant<Cases...>{Cases{decode_native<typename Cases::value_type>(*source.value, child_path(path, source.tag))}}; }(), ...);",
  "    if (!result) throw binding_error(\"input_shape_mismatch\", std::string(path) + \": unknown variant tag\");",
  "    return std::move(*result);",
  "  }",
  "  static mirrorcpp::Value encode(const MirrorVariant<Cases...>& value, std::string_view path) {",
  "    return std::visit([&](const auto& item) { using Case = std::decay_t<decltype(item)>; return mirrorcpp::Value(mirrorcpp::Value::Variant{std::string(Case::name.view()), mirrorcpp::Box<mirrorcpp::Value>(encode_native<typename Case::value_type>(item.value, child_path(path, Case::name.view())))}); }, value.value);",
  "  }",
  "};",
  "template <> struct NativeCodec<MirrorVariant<>> {",
  "  static MirrorVariant<> decode(const mirrorcpp::Value&, std::string_view path) { throw binding_error(\"input_shape_mismatch\", std::string(path) + \": empty variant has no inhabitants\"); }",
  "  static mirrorcpp::Value encode(const MirrorVariant<>&, std::string_view path) { throw binding_error(\"observation_shape_mismatch\", std::string(path) + \": empty variant has no inhabitants\"); }",
  "};"
]


/-- Runtime specialization refuses template drift instead of silently emitting
an incomplete capability profile. Every replaced section must occur once. -/
private def replaceRuntimeSection (source needle replacement : String) : EmitResult String :=
  match source.splitOn needle with
  | [before, after] => pure (before ++ replacement ++ after)
  | _ => fail "MIC-E-INTERNAL-001" "C++ v2 runtime section is missing or ambiguous"

private def runtimeSupportV2 : EmitResult String := do
  let support ← replaceRuntimeSection runtimeSupport "enum class Kind { field, index, variant_value };"
      "enum class Kind { field, index, variant_value, map_key };"
  let support ← replaceRuntimeSection support "  std::size_t position = 0;"
      "  std::size_t position = 0;\n  mirrorcpp::Value key{};"
  let support ← replaceRuntimeSection support "  static PathSegment field(std::string value)"
      "  static PathSegment map_key(mirrorcpp::Value value) { return {Kind::map_key, {}, 0, std::move(value)}; }\n  static PathSegment field(std::string value)"
  let support ← replaceRuntimeSection support "    } else {\n      if (!value.is<mirrorcpp::Value::Variant>()"
      (lines [
        "    } else if (segment.kind == PathSegment::Kind::map_key) {",
        "      if (!value.is<mirrorcpp::Value::Map>()) throw binding_error(\"input_shape_mismatch\", std::string(label) + \": map expected\");",
        "      const auto& entries = value.get<mirrorcpp::Value::Map>().entries;",
        "      std::set<std::string> strings; std::set<mirrorcpp::Value::Int> integers;",
        "      const mirrorcpp::Value* found = nullptr;",
        "      for (const auto& [key, item] : entries) {",
        "        if (key.kind() != segment.key.kind()) throw binding_error(\"input_shape_mismatch\", std::string(label) + \": mistyped map key\");",
        "        const bool unique = key.is_str() ? strings.insert(key.get<std::string>()).second : integers.insert(key.get<mirrorcpp::Value::Int>()).second;",
        "        if (!unique) throw binding_error(\"input_shape_mismatch\", std::string(label) + \": duplicate map key\");",
        "        if (key == segment.key) found = &item;",
        "      }",
        "      if (found == nullptr) throw binding_error(\"input_shape_mismatch\", std::string(label) + \": map key is absent\");",
        "      value = mirrorcpp::Value(*found);",
        "    } else {"] ++ "      if (!value.is<mirrorcpp::Value::Variant>()")
  let support ← replaceRuntimeSection support "template <typename T> struct MirrorMap { std::vector<std::pair<std::string, T>> entries; };"
      "template <typename T, typename K = std::string> struct MirrorMap { std::vector<std::pair<K, T>> entries; };"
  let start := "template <typename T> struct NativeCodec<MirrorMap<T>> {"
  let finish := "template <typename... Cases> struct NativeCodec<MirrorVariant<Cases...>> {"
  let parts := support.splitOn start
  match parts with
  | [before, after] =>
      let remaining := after.splitOn finish
      match remaining with
      | [_, rest] => pure <| before ++ lines [
          "template <typename T, typename K> struct NativeCodec<MirrorMap<T, K>> {",
          "  static MirrorMap<T, K> decode(const mirrorcpp::Value& value, std::string_view path) {",
          "    if (!value.is<mirrorcpp::Value::Map>()) throw binding_error(\"input_shape_mismatch\", std::string(path) + \": map expected\");",
          "    MirrorMap<T, K> result; std::set<K> keys;",
          "    const auto& source = value.get<mirrorcpp::Value::Map>().entries;",
          "    for (std::size_t i = 0; i < source.size(); ++i) {",
          "      const auto key = decode_native<K>(source[i].first, std::string(path) + \": map key\");",
          "      if (!keys.insert(key).second) throw binding_error(\"input_shape_mismatch\", std::string(path) + \": duplicate map key\");",
          "      result.entries.emplace_back(key, decode_native<T>(source[i].second, std::string(path) + \"[\" + std::to_string(i) + \"]\"));",
          "    } return result;",
          "  }",
          "  static mirrorcpp::Value encode(const MirrorMap<T, K>& value, std::string_view path) {",
          "    mirrorcpp::Value::Map result; std::set<K> keys;",
          "    for (const auto& [key, item] : value.entries) {",
          "      if (!keys.insert(key).second) throw binding_error(\"observation_shape_mismatch\", std::string(path) + \": duplicate map key\");",
          "      result.entries.emplace_back(encode_native<K>(key, std::string(path) + \": map key\"), encode_native<T>(item, path));",
          "    } return mirrorcpp::Value(std::move(result));",
          "  }",
          "};"] ++ finish ++ rest
      | _ => fail "MIC-E-INTERNAL-001" "C++ v2 runtime variant boundary is ambiguous"
  | _ => fail "MIC-E-INTERNAL-001" "C++ v2 runtime map boundary is ambiguous"

private def renderModule (profile : String) (lock : LockedModelInterface) : EmitResult (String × String) := do
  let support ← if profile == "mirrorcpp-v2" then runtimeSupportV2 else pure runtimeSupport
  let modelName := lock.modelModule
  let _ ← validateNativeNamespaces lock profile
  let actions := sortedBy (·.id) (lock.initializers ++ lock.actions)
  let inputStructs ← actions.mapM (renderInputStruct profile)
  let observation ← renderObservation profile modelName lock.observations
  let portMethods ← actions.mapM renderPortMethod
  let decoders ← actions.mapM (renderInputDecoder profile)
  let observationEncoder ← renderObservationEncoder profile modelName lock.observations
  let branches ← actions.zipIdx.mapM fun indexed =>
    renderActionBranch (indexed.2 == 0) indexed.1
  let contractJson := Codec.ModelInterfaceJson.canonicalString
    (Codec.ModelInterfaceJson.encodeContract lock.contract)
  let coverageEntries := actions.map fun action =>
    "        {" ++ cppString action.id ++ ", 0},"
  let source := lines <|
    ["// @generated by Mirrors model_interface_gen",
     s!"// target-profile: {profile}",
     s!"// profile-version: {if profile == "mirrorcpp-v2" then 2 else 1}",
     s!"// semantic-sha256: {lock.semanticDigest}",
     "// DO NOT EDIT",
     "#pragma once",
     "",
     "#include <mirrorcpp/mirrorcpp.hpp>",
     "#include <algorithm>",
     "#include <cstddef>",
     "#include <functional>",
     "#include <map>",
     "#include <memory>",
     "#include <optional>",
     "#include <set>",
     "#include <stdexcept>",
     "#include <string>",
     "#include <string_view>",
     "#include <tuple>",
     "#include <type_traits>",
     "#include <utility>",
     "#include <variant>",
     "#include <vector>",
     "",
     s!"namespace mirrors_generated::{lowerFirst modelName} " ++ "{",
     "",
     s!"inline constexpr std::string_view {modelName}SemanticDigest = {cppString lock.semanticDigest};",
     s!"inline const mirrorcpp::GeneratedModelInterface {modelName}ModelInterface" ++ "{",
     s!"    std::string({modelName}SemanticDigest),",
     s!"    {cppString contractJson},",
     "};",
     "",
     support] ++ inputStructs ++
    [observation,
     s!"struct {modelName}Port " ++ "{",
     s!"  virtual ~{modelName}Port() = default;"] ++ portMethods ++
    [s!"  virtual {modelName}Observation observe() = 0;",
     "};",
     ""] ++ decoders ++ [observationEncoder,
     s!"struct {modelName}Binding " ++ "{",
     "  mirrorcpp::StateComputer computer;",
     "  std::function<std::map<std::string, std::size_t>()> coverage;",
     "  std::function<void()> assert_all_actions_covered;",
     "};",
     "",
     s!"inline {modelName}Binding bind_{lowerFirst modelName}({modelName}Port& port, const mirrorcpp::ApalacheConfig& config) " ++ "{",
     s!"  const std::string expected_param_var = {cppString (lock.runProfile.configuredParamVar.getD "")};",
     "  if (config.param_vars != expected_param_var) throw binding_error(\"configuration_mismatch\", \"effective paramVars mismatch\");",
     "  struct Runtime {",
     s!"    {modelName}Port* port;",
     "    Lifecycle lifecycle = Lifecycle::fresh;",
     "    std::map<std::string, std::size_t> counts" ++ "{"] ++ coverageEntries ++
    ["    };",
     "    bool running = false;",
     "  };",
     "  auto runtime = std::make_shared<Runtime>();",
     "  runtime->port = &port;",
     "  mirrorcpp::StateComputer computer = [runtime](std::string_view wire_action, const mirrorcpp::State& payload, const mirrorcpp::State&) -> mirrorcpp::State {",
     "    if (runtime->lifecycle == Lifecycle::poisoned) throw binding_error(\"binding_poisoned\", \"binding is poisoned\");",
     "    if (runtime->running) { runtime->lifecycle = Lifecycle::poisoned; throw binding_error(\"adapter_failure\", \"binding callbacks must not be reentrant\"); }",
     "    runtime->running = true;",
     "    Stage stage = Stage::dispatch;",
     "    std::string stable_action;",
     "    try {"] ++ branches ++
    ["    else {",
     "      throw binding_error(\"unknown_action\", \"unknown wire action\");",
     "    }",
     "    stage = Stage::observation;",
     "    const auto observation = runtime->port->observe();",
     "    if (runtime->lifecycle == Lifecycle::poisoned) throw binding_error(\"observation_shape_mismatch\", \"reentrant observation poisoned the binding\");",
     s!"    auto state = encode_{lowerFirst modelName}_observation(observation);",
     "    ++runtime->counts.at(stable_action);",
     "    runtime->running = false;",
     "    return state;",
     "    } catch (const BindingError&) {",
     "      runtime->lifecycle = Lifecycle::poisoned;",
     "      runtime->running = false;",
     "      if (stage == Stage::dispatch || stage == Stage::input) throw;",
     "      throw binding_error(stage == Stage::observation ? \"observation_shape_mismatch\" : \"adapter_failure\", \"binding callback failed\");",
     "    } catch (const std::exception& error) {",
     "      runtime->lifecycle = Lifecycle::poisoned;",
     "      runtime->running = false;",
     "      const std::string code = stage == Stage::input ? \"input_shape_mismatch\" : stage == Stage::observation ? \"observation_shape_mismatch\" : \"adapter_failure\";",
     "      throw binding_error(code, error.what());",
     "    } catch (...) {",
     "      runtime->lifecycle = Lifecycle::poisoned;",
     "      runtime->running = false;",
     "      throw binding_error(stage == Stage::observation ? \"observation_shape_mismatch\" : \"adapter_failure\", \"unknown binding failure\");",
     "    }",
     "  };",
     "  return {",
     "    std::move(computer),",
     "    [runtime] { return runtime->counts; },",
     "    [runtime] {",
     "      for (const auto& [id, count] : runtime->counts) if (count == 0) throw std::runtime_error(\"uncovered action: \" + id);",
     "    },",
     "  };",
     "}",
     "",
     s!"}  // namespace mirrors_generated::{lowerFirst modelName}"]
  pure (s!"{modelName}Mirror.generated.hpp", source)

private def renderOwnershipManifest (profile : String) (digest : String) (paths : List String) : String :=
  let json := Lean.Json.mkObj [
    ("files", .arr (paths.map Lean.Json.str).toArray),
    ("profileVersion", .num (if profile == "mirrorcpp-v2" then 2 else profileVersion)),
    ("schema", .str "mirrors.model-interface-generated/v1"),
    ("semanticDigest", .str digest),
    ("targetProfile", .str profile)]
  Codec.ModelInterfaceJson.canonicalString json ++ "\n"

/-- Emit the deterministic `mirrorcpp-v1` header and ownership manifest. -/
def emitCpp (lock : LockedModelInterface) (profile : String := "mirrorcpp-v1") : EmitResult GeneratedTree := do
  if profile != "mirrorcpp-v1" && profile != "mirrorcpp-v2" then
    fail "MIC-E-TARGET-001" s!"unsupported C++ target profile {profile}"
  let diagnostics := targetDiagnostics lock profile
  if !diagnostics.isEmpty then throw diagnostics
  let (sourcePath, source) ← renderModule profile lock
  let ownedPaths := sortedStrings [manifestPath, sourcePath]
  let manifest := renderOwnershipManifest profile lock.semanticDigest ownedPaths
  let files := sortedBy (·.relativePath) [
    { relativePath := sourcePath, bytes := source.toUTF8 },
    { relativePath := manifestPath, bytes := manifest.toUTF8 }]
  pure { files }

end Shell.ModelInterface.Emit.Cpp
