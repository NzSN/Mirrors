import Core.ModelInterface.Resolve

/-! Reviewed application-to-checkpoint data; no code, IO or schedule inference. -/
namespace Core.ModelInterface.ScheduleKit

structure Actor where
  actor : String
  operation : String
  deriving Repr

inductive ActorSource where
  | fixed (actor : String)
  | input (inputId : String)
  deriving Repr

structure ActionMapping where
  actionId : StableId
  actorSource : ActorSource
  checkpoint : String
  deriving Repr

structure Plan where
  semanticDigest : String
  actors : List Actor
  actions : List ActionMapping
  deriving Repr

def identifier (value : String) : Bool :=
  !value.isEmpty && value.toUTF8.size ≤ 128 && value.toList.all fun c =>
    c.isAlphanum && c.toNat < 128 || c == '_' || c == '.' || c == '/' || c == '-'

def validate (lock : LockedModelInterface) (plan : Plan) : Except String Unit := do
  if plan.semanticDigest != lock.semanticDigest then throw "kit model semantic identity differs from lock"
  if plan.actors.isEmpty || plan.actors.length > 64 then throw "kit requires 1..64 actors"
  if !(duplicateStrings (plan.actors.map (·.actor))).isEmpty then throw "duplicate kit actor"
  if !plan.actors.all (fun a => identifier a.actor && identifier a.operation) then
    throw "invalid kit actor/operation identifier"
  if plan.actions.length > 256 || !(duplicateStrings (plan.actions.map (·.actionId))).isEmpty then
    throw "kit action mapping count or uniqueness violated"
  if (plan.actions.map (·.actionId)).any (fun id => !lock.actions.any (·.id == id)) ||
      lock.actions.any (fun a => !plan.actions.any (·.actionId == a.id)) then
    throw "kit mappings must cover exactly every transition action"
  for mapping in plan.actions do
    if !(identifier mapping.checkpoint || mapping.checkpoint == "$done") then
      throw "invalid kit checkpoint identifier"
    let some action := lock.actions.find? (·.id == mapping.actionId)
      | throw "unknown kit action"
    match mapping.actorSource with
    | .fixed actor =>
        unless plan.actors.any (·.actor == actor) do throw "fixed kit actor is not declared"
    | .input inputId =>
        let some input := action.inputs.find? (·.id == inputId)
          | throw "kit actor input is not declared by action"
        unless input.projection.type == .str do throw "kit actor input must have string type"
  return ()

end Core.ModelInterface.ScheduleKit
