import Codec.StrictJson
import Core.ModelInterface.Reduction

/-! Strict inert JSON codec for the first domain-reduction request. -/

namespace Codec.ModelInterfaceReductionJson

open Core.ModelInterface

private def fields : Lean.Json → Except String (List (String × Lean.Json))
  | .obj values => .ok values.toList
  | _ => .error "reduction candidate must be an object"

private def exactFields (context : String) (actual expected : List String) :
    Except String Unit :=
  if actual.length == expected.length && actual.all expected.contains then .ok ()
  else .error s!"{context}: missing or unknown field"

private def required (values : List (String × Lean.Json)) (name : String) :
    Except String Lean.Json :=
  match List.lookup name values with
  | some value => .ok value
  | none => .error s!"missing field {name}"

private def string (context : String) : Lean.Json → Except String String
  | .str value => .ok value
  | _ => .error s!"{context}: expected string"

private def nat (context : String) : Lean.Json → Except String Nat
  | .num ⟨mantissa, 0⟩ =>
      if 0 ≤ mantissa then .ok mantissa.toNat
      else .error s!"{context}: expected nonnegative integer"
  | _ => .error s!"{context}: expected nonnegative integer"

private def int (context : String) : Lean.Json → Except String Int
  | .num ⟨mantissa, 0⟩ => .ok mantissa
  | _ => .error s!"{context}: expected integer"

private def decodeEdit (index : Nat) (json : Lean.Json) : Except String LeaseInputEdit := do
  let values ← fields json
  let expected := ["stateIndex", "actionId", "inputId", "before", "after"]
  exactFields s!"edits[{index}]" (values.map Prod.fst) expected
  return {
    stateIndex := ← nat s!"edits[{index}].stateIndex" (← required values "stateIndex")
    actionId := ← string s!"edits[{index}].actionId" (← required values "actionId")
    inputId := ← string s!"edits[{index}].inputId" (← required values "inputId")
    before := ← int s!"edits[{index}].before" (← required values "before")
    after := ← int s!"edits[{index}].after" (← required values "after")
  }

private def decodeEdits : Lean.Json → Except String (List LeaseInputEdit)
  | .arr values => values.toList.zipIdx.mapM fun (value, index) => decodeEdit index value
  | _ => .error "edits: expected array"

private def decodeNats (context : String) : Lean.Json → Except String (List Nat)
  | .arr values => values.toList.zipIdx.mapM fun (value, index) =>
      nat s!"{context}[{index}]" value
  | _ => .error s!"{context}: expected array"

def decodeCandidateJson (json : Lean.Json) : Except String LeaseReductionCandidate := do
  let values ← fields json
  let expected := ["schema", "modelSha256", "interfaceDigest", "orderedCorpusSha256",
    "originalBundleSha256", "selectedTraceSha256", "traceIndex", "traceOccurrences", "edits"]
  exactFields "candidate" (values.map Prod.fst) expected
  return {
    schema := ← string "schema" (← required values "schema")
    modelSha256 := ← string "modelSha256" (← required values "modelSha256")
    interfaceDigest := ← string "interfaceDigest" (← required values "interfaceDigest")
    orderedCorpusSha256 := ← string "orderedCorpusSha256"
      (← required values "orderedCorpusSha256")
    originalBundleSha256 := ← string "originalBundleSha256"
      (← required values "originalBundleSha256")
    selectedTraceSha256 := ← string "selectedTraceSha256"
      (← required values "selectedTraceSha256")
    traceIndex := ← nat "traceIndex" (← required values "traceIndex")
    traceOccurrences := ← decodeNats "traceOccurrences" (← required values "traceOccurrences")
    edits := ← decodeEdits (← required values "edits")
  }

def decodeCandidateBytes (raw : ByteArray) : Except String LeaseReductionCandidate := do
  let limits : Codec.StrictJson.Limits := { maxBytes := 262144, maxDepth := 16 }
  let json ← (Codec.StrictJson.parseBytes raw limits).mapError toString
  decodeCandidateJson json

def decodeAndValidate (raw : ByteArray) : Except String ValidatedLeaseReduction := do
  let candidate ← decodeCandidateBytes raw
  (validateLeaseReduction candidate).mapError fun refusal =>
    s!"{repr refusal.code}: {refusal.detail}"

end Codec.ModelInterfaceReductionJson
