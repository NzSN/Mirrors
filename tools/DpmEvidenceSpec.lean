import Codec.DpmEvidence
open Lean

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def request (expected actual : Json) (mode : String) : Json :=
  Json.mkObj [("schema", .str "mirrors.dpm-value-check/v1"),
    ("pairs", .arr #[Json.mkObj [("expected", expected), ("actual", actual),
      ("mode", .str mode)]])]

private def parse (text : String) : IO Json :=
  match Json.parse text with
  | .ok value => pure value
  | .error e => throw (IO.userError e)

private def fieldIs (value : Json) (name : String) (expected : Json) : Bool :=
  match value.getObjVal? name with
  | .ok actual => actual == expected
  | .error _ => false

private def result (expected actual : Json) (mode : String) : IO Json :=
  match Codec.DpmEvidence.check (request expected actual mode).compress.toUTF8 with
  | .error e => throw (IO.userError e)
  | .ok value =>
    match (value.getObjVal? "results").bind Json.getArr? with
    | .ok rows => pure rows[0]!
    | .error e => throw (IO.userError e)

def main : IO Unit := do
  let integer ← parse "{\"count\":{\"#bigint\":\"1\"}}"
  let boolean ← parse "{\"count\":true}"
  check (fieldIs (← result integer boolean "exact") "equal" (.bool false))
    "Boolean and integer evidence compared equal"
  let left ← parse "{\"count\":1,\"map\":{\"#map\":[[\"a\",1],[\"b\",2]]},\"set\":{\"#set\":[1,2]}}"
  let right ← parse "{\"count\":{\"#bigint\":\"1\"},\"map\":{\"#map\":[[\"b\",2],[\"a\",1]]},\"set\":{\"#set\":[2,1]}}"
  check (fieldIs (← result left right "exact") "equal" (.bool true))
    "Typed extensional ITF equality changed"
  let modelState ← parse "{\"count\":1,\"action_taken\":\"write\",\"parameters\":{\"actor\":\"a\"}}"
  check (fieldIs (← result modelState integer "model") "equal" (.bool true))
    "Model metadata was compared as SUT state"
  check (fieldIs (← result modelState integer "exact") "equal" (.bool false))
    "Exact receipt correspondence ignored metadata"
  let expected ← parse "{\"count\":5,\"phase\":{},\"saved\":{}}"
  let actual ← parse "{\"count\":7,\"phase\":{},\"saved\":{}}"
  check (fieldIs (← result expected actual "counter") "counterDelta" (.str "2"))
    "Counter integer delta changed"
  let unrelated ← parse "{\"count\":7,\"phase\":true,\"saved\":{}}"
  check (fieldIs (← result expected unrelated "counter") "counterDelta" .null)
    "Counter normalization admitted unrelated mismatch"
  let duplicate ← parse "{\"nested\":{\"#map\":[[\"a\",1],[\"a\",2]]}}"
  check (!(Codec.DpmEvidence.check (request duplicate duplicate "exact").compress.toUTF8).isOk)
    "Duplicate string map keys accepted"
  let duplicateInt ← parse "{\"nested\":{\"#map\":[[1,1],[{\"#bigint\":\"1\"},2]]}}"
  check (!(Codec.DpmEvidence.check (request duplicateInt duplicateInt "exact").compress.toUTF8).isOk)
    "Duplicate integer map keys accepted"
  check (!(Codec.DpmEvidence.check "{\"schema\":1,\"schema\":2}".toUTF8).isOk)
    "Duplicate raw JSON keys accepted"
  check (!(Codec.DpmEvidence.check (request integer integer "unknown").compress.toUTF8).isOk)
    "Unknown comparison mode accepted"
  check (!(Codec.DpmEvidence.check (request (.arr #[]) integer "model").compress.toUTF8).isOk)
    "Non-object state accepted"
  IO.println "DPM typed evidence: 11 gates passed"
