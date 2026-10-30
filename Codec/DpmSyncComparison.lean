import Core.DpmSyncComparison
import Codec.StrictJson
import Lean

namespace Codec.DpmSyncComparison
open Lean Core.DpmSyncComparison

private def object (json : Json) (names : List String) : Except String (List (String × Json)) := do
  let .obj fields := json | throw "expected controlled evidence object"
  let fields := fields.toList
  unless fields.length == names.length && fields.all (fun p => names.contains p.1) do
    throw "missing or unknown controlled evidence field"
  return fields

private def field (fields : List (String × Json)) (name : String) : Except String Json :=
  match fields.lookup name with
  | some value => .ok value
  | none => .error s!"missing controlled evidence field: {name}"

private def string (json : Json) : Except String String :=
  json.getStr?.mapError (fun _ => "expected controlled string")

private def integer (json : Json) : Except String Int :=
  json.getInt?.mapError (fun _ => "expected controlled integer")

private def natural (json : Json) : Except String Nat :=
  json.getNat?.mapError (fun _ => "expected controlled natural number")

private def array (json : Json) : Except String (List Json) := do
  let .arr values := json | throw "expected controlled array"
  return values.toList

private def identity (json : Json) : Except String Identity := do
  let fields ← object json ["modelSemanticDigest", "mappingSha256", "implementationSha256"]
  return {
    model := ← string (← field fields "modelSemanticDigest"),
    mapping := ← string (← field fields "mappingSha256"),
    implementation := ← string (← field fields "implementationSha256") }

private def operation (text : String) : Except String Operation :=
  match text with
  | "start" => .ok .start | "lock" => .ok .lock | "unlock" => .ok .unlock
  | "send" => .ok .send | "receive" => .ok .receive
  | "checkpoint" => .ok .checkpoint | "$done" => .ok .done
  | _ => .error "unsupported controlled operation"

private def event (json : Json) : Except String Event := do
  let kind ← string (← json.getObjVal? "kind")
  let grant := kind == "grant"
  unless grant || kind == "result" do throw "unsupported controlled event kind"
  let fields ← object json (["ordinal", "kind", "actor", "operation", "resource"] ++
    if grant then ["enabled"] else ["value"])
  let value : Option Int ← if grant then pure none else do
    let number ← integer (← field fields "value")
    pure (some number)
  let enabled : List String ← if grant then do
    (← array (← field fields "enabled")).mapM string
    else pure []
  return {
    ordinal := ← natural (← field fields "ordinal"), grant,
    actor := ← string (← field fields "actor"),
    operation := ← operation (← string (← field fields "operation")),
    resource := ← string (← field fields "resource"),
    value, enabled }

private def observation (json : Json) : Except String Observation := do
  let fields ← object json ["afterDecisions", "state"]
  let state ← object (← field fields "state") ["count", "received"]
  return {
    afterDecisions := ← natural (← field fields "afterDecisions"),
    count := ← integer (← field state "count"),
    received := ← (← array (← field state "received")).mapM integer }

private def terminalActors (json : Json) : Except String Bool := do
  let actors ← array json
  let names ← actors.mapM fun actor => do
    let fields ← object actor ["actor", "state", "operation", "resource"]
    unless (← string (← field fields "state")) == "finished" &&
        (← string (← field fields "operation")) == "$done" &&
        (← string (← field fields "resource")).isEmpty do
      throw "controlled actor has not finished"
    string (← field fields "actor")
  return names.length == 2 && names.eraseDups.length == 2 && names.all validActor

private def terminalResources (json : Json) : Except String Bool := do
  let resources ← array json
  let names ← resources.mapM fun resource => do
    let fields ← object resource ["id", "kind", "capacity", "owner", "contents"]
    let name ← string (← field fields "id")
    let kind ← string (← field fields "kind")
    let capacity ← natural (← field fields "capacity")
    unless (← string (← field fields "owner")).isEmpty &&
        (← array (← field fields "contents")).isEmpty &&
        ((name == "mutex" && kind == "mutex" && capacity == 0) ||
         (name == "queue" && kind == "queue" && capacity == 1)) do
      throw "controlled terminal resource differs from finite mapping"
    return name
  return names.length == 2 && names.eraseDups.length == 2

private def receipt (json : Json) : Except String Receipt := do
  let fields ← object json ["schema", "profile", "executionId", "identity", "outcome", "detail",
    "finished", "cleanup", "passed", "budgetExceeded", "decisions", "events", "observations",
    "resources", "actors", "failureGraph", "coverage", "modelComparison"]
  unless (← field fields "schema") == .str "mirrors.controlled-sync-replay/v1" &&
      (← field fields "profile") == .str "mirrorcpp.controlled-sync-experimental/v1" &&
      (← field fields "modelComparison") == .bool false &&
      (← field fields "coverage") == .str "recorded-controlled-resource-decisions-only" do
    throw "unsupported controlled receipt profile or comparison claim"
  let budget ← object (← field fields "budgetExceeded") ["execution", "cleanup"]
  let complete := (← field fields "outcome") == .str "completed" &&
    (← field fields "detail") == .str "" && (← field fields "finished") == .bool true &&
    (← field fields "cleanup") == .str "confirmed" && (← field fields "passed") == .bool true &&
    (← field fields "failureGraph") == .null && (← field budget "execution") == .bool false &&
    (← field budget "cleanup") == .bool false
  let actorsOk ← terminalActors (← field fields "actors")
  let resourcesOk ← terminalResources (← field fields "resources")
  return {
    executionId := ← string (← field fields "executionId"),
    identity := ← identity (← field fields "identity"),
    decisions := ← natural (← field fields "decisions"),
    events := ← (← array (← field fields "events")).mapM event,
    observations := ← (← array (← field fields "observations")).mapM observation,
    complete, terminalShape := actorsOk && resourcesOk }

def check (raw : ByteArray) : Except String Json := do
  let json ← (StrictJson.parseBytes raw { maxBytes := 1024*1024, maxDepth := 32 }).mapError toString
  let fields ← object json ["schema", "identity", "receipt"]
  unless (← field fields "schema") == .str "mirrors.controlled-sync-check/v1" do
    throw "unsupported controlled witness request"
  let expected ← identity (← field fields "identity")
  let actual ← receipt (← field fields "receipt")
  let decisions ← Core.DpmSyncComparison.admit expected actual
  return Json.mkObj [
    ("schema", .str "mirrors.controlled-sync-witness/v1"),
    ("executionId", .str actual.executionId), ("modelComparison", .bool false),
    ("cost", toJson (Core.DpmSyncComparison.cost decisions)),
    ("actors", toJson (decisions.map (·.actor))),
    ("operations", toJson (decisions.map (·.operation.text))),
    ("resources", toJson (decisions.map (·.resource))),
    ("values", toJson (decisions.map (·.value))),
    ("enabled", toJson (decisions.map (·.enabled))),
    ("counts", toJson (actual.observations.map (·.count))),
    ("received", toJson (actual.observations.map (·.received))) ]

end Codec.DpmSyncComparison
