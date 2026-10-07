import Core.ModelInterface.ScheduleKit
import Codec.StrictJson
import Codec.ModelInterfaceJson

namespace Codec.ModelInterfaceScheduleKitJson
open Lean Core.ModelInterface.ScheduleKit

private def fields (value : Json) (keys : List String) : Except String (List (String × Json)) := do
  let .obj fs := value | throw "kit object expected"
  let entries := fs.toList
  unless entries.length == keys.length && entries.all (fun e => keys.contains e.1) do
    throw "unknown or missing kit fields"
  return entries
private def get (entries : List (String × Json)) (key : String) : Except String Json :=
  match List.lookup key entries with
  | some value => .ok value
  | none => .error s!"missing kit field {key}"
private def str (entries : List (String × Json)) (key : String) : Except String String := do
  let .str value ← get entries key | throw "kit string expected"
  return value
private def array (entries : List (String × Json)) (key : String) : Except String (List Json) := do
  let .arr value ← get entries key | throw "kit array expected"
  return value.toList

def parse (raw : ByteArray) : Except String Plan := do
  let value ← (StrictJson.parseBytes raw { maxBytes := 1_048_576, maxDepth := 32 }).mapError toString
  let top ← fields value ["schema", "semanticDigest", "actors", "actions"]
  unless (← str top "schema") == "mirrors.dpm-kit-plan/v1" do throw "unknown kit schema"
  let actorValues ← array top "actors"
  let actionValues ← array top "actions"
  if actorValues.length > 64 || actionValues.length > 256 then throw "kit array bounds exceeded"
  let actors ← actorValues.mapM fun value => do
    let fs ← fields value ["actor", "operation"]
    return { actor := ← str fs "actor", operation := ← str fs "operation" : Actor }
  let actions ← actionValues.mapM fun value => do
    let fs ← fields value ["actionId", "actorSource", "checkpoint"]
    let source ← get fs "actorSource"
    let .obj sourceFields := source | throw "actor source object expected"
    let kind ← str sourceFields.toList "kind"
    let actorSource ← if kind == "fixed" then do
        let entries ← fields source ["kind", "actor"]
        pure (ActorSource.fixed (← str entries "actor"))
      else if kind == "input" then do
        let entries ← fields source ["kind", "inputId"]
        pure (ActorSource.input (← str entries "inputId"))
      else throw "unknown kit actor source kind"
    return {
      actionId := ← str fs "actionId"
      actorSource
      checkpoint := ← str fs "checkpoint" : ActionMapping }
  return { semanticDigest := ← str top "semanticDigest", actors, actions }

def encode (plan : Plan) : Json :=
  let actors := plan.actors.mergeSort (fun a b => a.actor ≤ b.actor)
  let actions := plan.actions.mergeSort (fun a b => a.actionId ≤ b.actionId)
  Json.mkObj [
    ("schema", .str "mirrors.dpm-kit-plan/v1"),
    ("semanticDigest", .str plan.semanticDigest),
    ("actors", .arr (actors.map fun a => Json.mkObj [
      ("actor", .str a.actor), ("operation", .str a.operation)]).toArray),
    ("actions", .arr (actions.map fun a => Json.mkObj [
      ("actionId", .str a.actionId),
      ("checkpoint", .str a.checkpoint),
      ("actorSource", match a.actorSource with
        | .fixed actor => Json.mkObj [("kind", .str "fixed"), ("actor", .str actor)]
        | .input input => Json.mkObj [("kind", .str "input"), ("inputId", .str input)])]).toArray)]

def canonicalBytes (plan : Plan) : ByteArray :=
  ModelInterfaceJson.canonicalFileBytes (encode plan)

end Codec.ModelInterfaceScheduleKitJson
