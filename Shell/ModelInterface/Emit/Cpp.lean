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

private def validateName (context value : String) : EmitResult Unit := do
  let validFirst (character : Char) : Bool :=
    ('a' ≤ character && character ≤ 'z') ||
    ('A' ≤ character && character ≤ 'Z')
  let validRest (character : Char) : Bool :=
    validFirst character || ('0' ≤ character && character ≤ '9') ||
      character == '_'
  match value.toList with
  | [] => fail "MIC-E-NAME-001" s!"mirrorcpp-v1 {context} name is empty"
  | first :: rest =>
      if !validFirst first || !rest.all validRest then
        fail "MIC-E-NAME-001"
          s!"mirrorcpp-v1 {context} name is not a portable C++ identifier: {value}"
  if cppKeywords.contains (lowerFirst value) then
    fail "MIC-E-NAME-001" s!"mirrorcpp-v1 {context} name is a C++ keyword: {value}"
  if value.startsWith "_" then
    fail "MIC-E-NAME-001" s!"mirrorcpp-v1 {context} name uses a reserved prefix: {value}"

private def validateNativeNamespace (context : String) (stableIds : List String)
    (mandatory : List String := []) : EmitResult Unit := do
  for stableId in stableIds do
    let _ ← validateName context stableId
  match duplicateStrings (mandatory ++ stableIds.map lowerFirst) with
  | collision :: _ =>
      fail "MIC-E-NAME-001"
        s!"mirrorcpp-v1 {context} contains colliding native identifier {collision}"
  | [] => pure ()

private def validateNativeNamespaces (lock : LockedModelInterface) : EmitResult Unit := do
  let _ ← validateName "model" lock.modelModule
  let actions := lock.initializers ++ lock.actions
  let _ ← validateNativeNamespace "implementation port" (actions.map (·.id)) ["observe"]
  for action in actions do
    let _ ← validateNativeNamespace s!"input fields for action {action.id}"
      (action.inputs.map (·.id))
  let _ ← validateNativeNamespace "observation fields" (lock.observations.map (·.id))
  pure ()

private partial def nativeType : ModelType → EmitResult String
  | .int => pure "mirrorcpp::Value::Int"
  | .bool => pure "bool"
  | .str => pure "std::string"
  | .null => pure "MirrorNull"
  | .set element => return s!"MirrorSet<{← nativeType element}>"
  | .seq element => return s!"MirrorSeq<{← nativeType element}>"
  | .tuple elements => do
      let types ← elements.mapM nativeType
      return s!"MirrorTuple<{String.intercalate ", " types}>"
  | .record fields => do
      let fields := sortedBy (·.wireName) fields
      let types ← fields.mapM fun field => do
        let type ← nativeType field.type
        return s!"RecordField<{cppString field.wireName}, {type}>"
      return s!"MirrorRecord<{String.intercalate ", " types}>"
  | .map .str value => return s!"MirrorMap<{← nativeType value}>"
  | .map _ _ => fail "MIC-E-TYPE-001"
      "mirrorcpp-v1 supports only string-keyed maps"
  | .variant cases => do
      let cases := sortedBy (·.tag) cases
      let types ← cases.mapM fun item => do
        let type ← nativeType item.payload
        return s!"VariantCase<{cppString item.tag}, {type}>"
      return s!"MirrorVariant<{String.intercalate ", " types}>"
  | .opaqueItf description => fail "MIC-E-TYPE-001"
      s!"mirrorcpp-v1 cannot emit opaque ITF type: {description}"

private def renderPathSegment : PathSegment → EmitResult String
  | .field name => pure s!"PathSegment::field({cppString name})"
  | .index index => pure s!"PathSegment::index({index})"
  | .variantValue tag => pure s!"PathSegment::variant({cppString tag})"
  | .mapKey _ => fail "MIC-E-PATH-001"
      "mirrorcpp-v1 does not support mapKey paths"

private def renderPath (path : List PathSegment) : EmitResult String := do
  let segments ← path.mapM renderPathSegment
  pure ("std::vector<PathSegment>{" ++ String.intercalate ", " segments ++ "}")

private def renderInputStruct (action : ResolvedAction) : EmitResult String := do
  if action.inputs.isEmpty then return ""
  let fields ← (sortedBy (·.id) action.inputs).mapM fun input => do
    let _ ← validateName "input" input.id
    let type ← nativeType input.projection.type
    pure s!"  {type} {lowerFirst input.id};"
  pure <| lines ([s!"struct {action.id}Input " ++ "{"] ++ fields ++ ["};"])

private def renderObservation (modelName : String)
    (observations : List ResolvedObservation) : EmitResult String := do
  let fields ← (sortedBy (·.id) observations).mapM fun observation => do
    let _ ← validateName "observation" observation.id
    let type ← nativeType observation.type
    pure s!"  {type} {lowerFirst observation.id};"
  pure <| lines ([s!"struct {modelName}Observation " ++ "{"] ++ fields ++ ["};"])

private def renderPortMethod (action : ResolvedAction) : EmitResult String := do
  let _ ← validateName "action" action.id
  if action.inputs.isEmpty then
    pure s!"  virtual void {lowerFirst action.id}() = 0;"
  else
    pure s!"  virtual void {lowerFirst action.id}(const {action.id}Input& input) = 0;"

private def renderInputDecoder (action : ResolvedAction) : EmitResult String := do
  if action.inputs.isEmpty then return ""
  let fields ← (sortedBy (·.id) action.inputs).mapM fun input => do
    let root := match input.projection.root with
      | .initialState => "comparable_initial_state(payload)"
      | .stepParameters => "payload"
    let path ← renderPath input.projection.path
    let type ← nativeType input.projection.type
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

private def renderObservationEncoder (modelName : String)
    (observations : List ResolvedObservation) : EmitResult String := do
  let assignments ← (sortedBy (·.id) observations).mapM fun observation => do
    let type ← nativeType observation.type
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
  "  for (const auto& segment : path) {",
  "    if (segment.kind == PathSegment::Kind::field) {",
  "      if (!value.is<mirrorcpp::Value::Record>()) throw binding_error(\"input_shape_mismatch\", std::string(label) + \": record expected\");",
  "      const auto& fields = value.get<mirrorcpp::Value::Record>().fields;",
  "      const auto found = fields.find(segment.text);",
  "      if (found == fields.end()) throw binding_error(\"input_shape_mismatch\", std::string(label) + \": missing field \" + segment.text);",
  "      value = found->second;",
  "    } else if (segment.kind == PathSegment::Kind::index) {",
  "      const std::vector<mirrorcpp::Value>* values = nullptr;",
  "      if (value.is<mirrorcpp::Value::Seq>()) values = &value.get<mirrorcpp::Value::Seq>().elems;",
  "      if (value.is<mirrorcpp::Value::Tuple>()) values = &value.get<mirrorcpp::Value::Tuple>().elems;",
  "      if (values == nullptr || segment.position >= values->size()) throw binding_error(\"input_shape_mismatch\", std::string(label) + \": index out of range\");",
  "      value = (*values)[segment.position];",
  "    } else {",
  "      if (!value.is<mirrorcpp::Value::Variant>() || value.get<mirrorcpp::Value::Variant>().tag != segment.text) throw binding_error(\"input_shape_mismatch\", std::string(label) + \": variant mismatch\");",
  "      value = *value.get<mirrorcpp::Value::Variant>().value;",
  "    }",
  "  }",
  "  if (path.empty()) throw binding_error(\"input_shape_mismatch\", std::string(label) + \": empty path cannot select the state record\");",
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
  "};"
]

private def renderModule (lock : LockedModelInterface) : EmitResult (String × String) := do
  let modelName := lock.modelModule
  let _ ← validateNativeNamespaces lock
  let actions := sortedBy (·.id) (lock.initializers ++ lock.actions)
  let inputStructs ← actions.mapM renderInputStruct
  let observation ← renderObservation modelName lock.observations
  let portMethods ← actions.mapM renderPortMethod
  let decoders ← actions.mapM renderInputDecoder
  let observationEncoder ← renderObservationEncoder modelName lock.observations
  let branches ← actions.zipIdx.mapM fun indexed =>
    renderActionBranch (indexed.2 == 0) indexed.1
  let contractJson := Codec.ModelInterfaceJson.canonicalString
    (Codec.ModelInterfaceJson.encodeContract lock.contract)
  let coverageEntries := actions.map fun action =>
    "        {" ++ cppString action.id ++ ", 0},"
  let source := lines <|
    ["// @generated by Mirrors model_interface_gen",
     s!"// target-profile: {targetProfile}",
     s!"// profile-version: {profileVersion}",
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
     runtimeSupport] ++ inputStructs ++
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

private def renderOwnershipManifest (digest : String) (paths : List String) : String :=
  let json := Lean.Json.mkObj [
    ("files", .arr (paths.map Lean.Json.str).toArray),
    ("profileVersion", .num profileVersion),
    ("schema", .str "mirrors.model-interface-generated/v1"),
    ("semanticDigest", .str digest),
    ("targetProfile", .str targetProfile)]
  Codec.ModelInterfaceJson.canonicalString json ++ "\n"

/-- Emit the deterministic `mirrorcpp-v1` header and ownership manifest. -/
def emitCpp (lock : LockedModelInterface) : EmitResult GeneratedTree := do
  let (sourcePath, source) ← renderModule lock
  let ownedPaths := sortedStrings [manifestPath, sourcePath]
  let manifest := renderOwnershipManifest lock.semanticDigest ownedPaths
  let files := sortedBy (·.relativePath) [
    { relativePath := sourcePath, bytes := source.toUTF8 },
    { relativePath := manifestPath, bytes := manifest.toUTF8 }]
  pure { files }

end Shell.ModelInterface.Emit.Cpp
