import Core.ModelInterface.Types
import Core.ModelInterface.Sha256
import Codec.StrictJson

/-!
# Model-interface structural evidence

Strictly parses the structural metadata carried by raw Apalache ITF traces.
This is intentionally a finite parser for the emitted type grammar used by the
first compiler slice, not a general TLA+ parser.
-/

namespace Shell.ModelInterface.Evidence

open Core.ModelInterface

private def sortedUniqueStrings (values : List String) : List String :=
  let unique := values.foldl (fun out value =>
    if out.contains value then out else value :: out) []
  unique.toArray.qsort (fun left right => compare left right == .lt) |>.toList

private def splitTopLevel (s : String) (separator : Char) : List String :=
  let rec go (chars : List Char) (depth : Nat) (cur : List Char)
      (out : List String) : List String :=
    match chars with
    | [] => (String.ofList cur.reverse).trimAscii.toString :: out |>.reverse
    | c :: cs =>
        let opens := c == '(' || c == '{' || c == '[' || c == '<'
        let closes := c == ')' || c == '}' || c == ']' || c == '>'
        if c == separator && depth == 0 then
          go cs depth [] ((String.ofList cur.reverse).trimAscii.toString :: out)
        else
          let depth := if opens then depth + 1 else if closes then depth - 1 else depth
          go cs depth (c :: cur) out
  go s.toList 0 [] []

private def splitField (s : String) : Option (String × String) :=
  let rec go (chars : List Char) (depth : Nat) (left : List Char) :
      Option (String × String) :=
    match chars with
    | [] => none
    | c :: cs =>
        let opens := c == '(' || c == '{' || c == '[' || c == '<'
        let closes := c == ')' || c == '}' || c == ']' || c == '>'
        if c == ':' && depth == 0 then
          some ((String.ofList left.reverse).trimAscii.toString,
            (String.ofList cs).trimAscii.toString)
        else
          let depth := if opens then depth + 1 else if closes then depth - 1 else depth
          go cs depth (c :: left)
  go s.toList 0 []

private def inner (s : String) (prefixChars suffixChars : Nat) : String :=
  (s.drop prefixChars).take (s.length - prefixChars - suffixChars) |>.toString

private partial def parseTypeWithFuel (fuel : Nat) (raw : String) :
    Except String ModelType := do
  if fuel == 0 then
    throw s!"Apalache type exceeds depth limit {maxStructuralTypeDepthV1}"
  let s := raw.trimAscii.toString
  if s == "Int" then return .int
  if s == "Bool" then return .bool
  if s == "Str" || s == "String" then return .str
  if s == "Null" then return .null
  if s.startsWith "Set(" && s.endsWith ")" then
    return .set (← parseTypeWithFuel (fuel - 1) (inner s 4 1))
  if s.startsWith "Seq(" && s.endsWith ")" then
    return .seq (← parseTypeWithFuel (fuel - 1) (inner s 4 1))
  if s.startsWith "{" && s.endsWith "}" then
    let body := inner s 1 1 |>.trimAscii |>.toString
    if body.isEmpty then return .record []
    let fields ← (splitTopLevel body ',').mapM fun part => do
      let some (name, ty) := splitField part
        | throw s!"malformed record field in Apalache type: {part}"
      if name.isEmpty then throw "empty record field name in Apalache type"
      let fieldType ← parseTypeWithFuel (fuel - 1) ty
      return ({ wireName := name, type := fieldType } : ModelField)
    return .record fields
  if s.startsWith "<<" && s.endsWith ">>" then
    let body := inner s 2 2 |>.trimAscii |>.toString
    if body.isEmpty then return .tuple []
    return .tuple (← (splitTopLevel body ',').mapM
      (parseTypeWithFuel (fuel - 1)))
  throw s!"unsupported Apalache type: {s}"

def parseType (raw : String) : Except String ModelType :=
  parseTypeWithFuel maxStructuralTypeDepthV1 raw

private def jsonStrings (j : Lean.Json) (field : String) : Except String (List String) := do
  let value ← j.getObjVal? field
  match value with
  | .arr values => values.toList.mapM fun
      | .str s => pure s
      | _ => throw s!"{field}: expected string array"
  | _ => throw s!"{field}: expected array"

private def optionalJsonStrings (j : Lean.Json) (field : String) : Except String (List String) :=
  match j.getObjVal? field with
  | .error _ => .ok []
  | .ok value =>
      match value with
      | .arr values => values.toList.mapM fun
          | .str s => pure s
          | _ => throw s!"{field}: expected string array"
      | _ => throw s!"{field}: expected array"

/-- Normalize one raw typed ITF document into compiler evidence. -/
def fromJson (j : Lean.Json) (sourceName : String := "<itf>") :
    Except String ModelEvidence := do
  let vars ← jsonStrings j "vars"
  let paramVars ← optionalJsonStrings j "param_vars"
  let metaJson ← j.getObjVal? "#meta"
  let varTypes ← metaJson.getObjVal? "varTypes"
  let entries ← match varTypes with
    | .obj fields => pure fields.toList
    | _ => throw "#meta.varTypes: expected object"
  let facts ← entries.mapM fun (name, value) => do
    let .str rendered := value
      | throw s!"#meta.varTypes.{name}: expected string"
    return ({
      modelPath := ModelPath.top name
      type := ← parseType rendered
      origin := .itfVarTypes
      location := { source := sourceName, pointer := some ("/#meta/varTypes/" ++ name) }
    } : TypeFact)
  -- Evidence identity covers every normalized input that can affect
  -- resolution, not only the type table. Source locations and raw formatting
  -- are deliberately excluded.
  let canonicalEvidence := Lean.Json.compress <| Lean.Json.mkObj [
    ("itfParamVars", .arr ((sortedUniqueStrings paramVars).map
      Lean.Json.str).toArray),
    ("traceVars", .arr ((sortedUniqueStrings vars).map
      Lean.Json.str).toArray),
    ("varTypes", varTypes)
  ]
  return {
    traceVars := vars
    itfParamVars := paramVars
    typeFacts := facts
    evidenceSha256 := Core.ModelInterface.Sha256.digestDomainHex
      "mirrors-model-interface-evidence/v1" canonicalEvidence.toUTF8
  }

/-- Evidence from multiple traces is reusable only when its normalized,
source-independent content digest agrees. -/
def compatible (left right : ModelEvidence) : Bool :=
  left.evidenceSha256 == right.evidenceSha256

/-- Strict raw-text entry point used by the CLI and replay trace bundle loader. -/
def fromString (raw : String) (sourceName : String := "<itf>")
    (limits : Codec.StrictJson.Limits := Codec.StrictJson.defaultLimits) :
    Except String ModelEvidence := do
  let j ← (Codec.StrictJson.parseString raw limits).mapError toString
  fromJson j sourceName

end Shell.ModelInterface.Evidence
