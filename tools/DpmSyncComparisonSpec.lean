import Codec.DpmSyncComparison
open Lean

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def setField (json : Json) (key : String) (value : Json) : Json :=
  match json with
  | .obj fields => Json.mkObj ((fields.toList.filter (fun p => p.1 != key)) ++ [(key, value)])
  | _ => json

private def field (json : Json) (key : String) : Json := (json.getObjVal? key).toOption.getD .null

private def request (receipt : Json) : Json := Json.mkObj [
  ("schema", .str "mirrors.controlled-sync-check/v1"),
  ("identity", field receipt "identity"), ("receipt", receipt)]

private def admitted (receipt : Json) : Bool :=
  (Codec.DpmSyncComparison.check (request receipt).compress.toUTF8).isOk

private def replaceFirst (receipt : Json) (key : String) (f : Json → Json) : Json :=
  match field receipt key with
  | .arr values => setField receipt key (.arr (values.modify 0 f))
  | _ => receipt

def main : IO Unit := do
  let raw ← IO.FS.readBinFile "test/fixtures/deterministic-scheduling/controlled-sync/native-complete.json"
  let .ok original := Codec.StrictJson.parseBytes raw {}
    | throw (IO.userError "native receipt fixture did not parse")
  check (admitted original) "complete native witness refused"
  let .ok witness := Codec.DpmSyncComparison.check (request original).compress.toUTF8
    | throw (IO.userError "complete witness did not decode")
  check (field witness "modelComparison" == .bool false) "admission fabricated model comparison"
  for (name, value) in [("passed", .bool false), ("finished", .bool false),
      ("modelComparison", .bool true), ("cleanup", .str "incomplete"),
      ("outcome", .str "timed_out"), ("failureGraph", Json.mkObj []),
      ("decisions", .bool true), ("unknown", .str "extra")] do
    check (!admitted (setField original name value)) s!"invalid controlled field accepted: {name}"
  check (!admitted (setField original "budgetExceeded"
      (Json.mkObj [("execution", .bool true), ("cleanup", .bool false)])))
    "execution deadline excess accepted"
  check (!admitted (replaceFirst original "events" (fun e => setField e "ordinal" (.num 1))))
    "incorrect event ordinal accepted"
  check (!admitted (replaceFirst original "events" (fun e =>
      setField e "enabled" (.arr #[.str "consumer", .str "consumer"]))))
    "duplicate enabled actor accepted"
  check (!admitted (replaceFirst original "observations" (fun row =>
      setField row "state" (setField (field row "state") "count" (.bool true)))))
    "Boolean count accepted as integer"
  let .arr observations := field original "observations" | throw (IO.userError "missing fixture observations")
  check (!admitted (setField original "observations" (.arr observations.pop)))
    "missing terminal observation accepted"
  let changedIdentity := setField (field original "identity") "mappingSha256" (.str (String.ofList (List.replicate 64 'd')))
  check (!(Codec.DpmSyncComparison.check
      (setField (request original) "identity" changedIdentity).compress.toUTF8).isOk)
    "unselected mapping accepted"
  -- This semantic deviation must survive admission unchanged for the remote
  -- model to reject. The admission gate cannot serve as its own model oracle.
  let changedObservation := setField observations.back! "state"
    (setField (field observations.back! "state") "count" (.num 3))
  let changed := setField original "observations" (.arr (observations.set! (observations.size-1) changedObservation))
  check (admitted changed) "admission silently replaced actual semantic evidence"
  let .ok changedWitness := Codec.DpmSyncComparison.check (request changed).compress.toUTF8
    | throw (IO.userError "semantic evidence disappeared")
  let .arr counts := field changedWitness "counts" | throw (IO.userError "missing witness counts")
  check (counts.back! == .num 3 && field changedWitness "modelComparison" == .bool false)
    "actual observation was turned into an expected state or a model match"
  check (!(Codec.DpmSyncComparison.check "{\"schema\":1,\"schema\":2}".toUTF8).isOk)
    "duplicate raw keys accepted"
  IO.println "DPM CONTROLLED WITNESS SPEC GREEN"
