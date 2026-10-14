import Codec.Json
import Codec.StrictJson
import Core.Diff

/-! Bounded typed comparisons of supplied DPM observations and oracle states.
This module does not evaluate models or acquire application resources. -/
namespace Codec.DpmEvidence
open Lean

private def object (j : Json) (names : List String) : Except String (List (String × Json)) := do
  let .obj values := j | throw "expected object"
  let fields := values.toList
  unless fields.length == names.length && fields.all (fun f => names.contains f.1) do
    throw "missing or unknown evidence field"
  return fields

private def field (fields : List (String × Json)) (name : String) : Except String Json :=
  match fields.lookup name with
  | some value => .ok value
  | none => .error s!"missing evidence field {name}"

/-- Duplicate function-map keys invalidate the assumptions of typed map lookup. -/
private def wellFormedValue : Nat → Value → Bool
  | 0, _ => false
  | fuel + 1, value => match value with
    | .vrecord entries | .vmap entries =>
      (entries.map (·.1)).eraseDups.length == entries.length &&
        entries.all (fun p => wellFormedValue fuel p.2)
    | .vintmap entries =>
      (entries.map (·.1)).eraseDups.length == entries.length &&
        entries.all (fun p => wellFormedValue fuel p.2)
    | .vset values | .vseq values | .vtuple values =>
      values.all (wellFormedValue fuel)
    | .vvariant _ value => wellFormedValue fuel value
    | _ => true

private def state (j : Json) : Except String ValueMap := do
  let .obj values := j | throw "evidence state must be an object"
  let decoded ← (Codec.decRecordF 64 values.toList).mapError (·.msg)
  unless wellFormedValue 64 (.vrecord decoded) do
    throw "duplicate map key or value depth exceeded"
  return decoded

private def counterDelta (expected actual : ValueMap) : Option String := do
  let names := ["count", "phase", "saved"]
  if expected.length != 3 || actual.length != 3 ||
      !expected.all (fun p => names.contains p.1) ||
      !actual.all (fun p => names.contains p.1) then none
  else do
    let .vint expectedCount ← expected.lookup "count" | none
    let .vint actualCount ← actual.lookup "count" | none
    let expectedPhase ← expected.lookup "phase"
    let actualPhase ← actual.lookup "phase"
    let expectedSaved ← expected.lookup "saved"
    let actualSaved ← actual.lookup "saved"
    if !valEq expectedPhase actualPhase || !valEq expectedSaved actualSaved ||
        expectedCount == actualCount then none
    else some (toString (actualCount - expectedCount))

private def pair (j : Json) : Except String Json := do
  let fields ← object j ["expected", "actual", "mode"]
  let .str mode := ← field fields "mode" | throw "invalid evidence comparison mode"
  unless ["model", "exact", "counter"].contains mode do
    throw "unsupported evidence comparison mode"
  let expected ← state (← field fields "expected")
  let actual ← state (← field fields "actual")
  let equal := if mode == "model" then
      match diffState expected actual with
      | .statesMatch => true
      | .stateMismatch .. => false
    else valEq (.vrecord expected) (.vrecord actual)
  let delta := if mode == "counter" then counterDelta expected actual else none
  return Json.mkObj [("equal", .bool equal),
    ("counterDelta", delta.map Json.str |>.getD .null)]

/-- Validate raw JSON before decoding; return bounded, inert comparison results. -/
def check (raw : ByteArray) : Except String Json := do
  let json ← (StrictJson.parseBytes raw
    { maxBytes := 32*1024*1024, maxDepth := 96 }).mapError toString
  let fields ← object json ["schema", "pairs"]
  unless (← field fields "schema") == Json.str "mirrors.dpm-value-check/v1" do
    throw "unsupported evidence request"
  let .arr pairs := ← field fields "pairs" | throw "evidence pairs must be array"
  if pairs.size > 8192 then throw "evidence pair bound exceeded"
  let results ← pairs.toList.mapM pair
  return Json.mkObj [("schema", .str "mirrors.dpm-value-check-result/v1"),
    ("results", .arr results.toArray)]

end Codec.DpmEvidence
