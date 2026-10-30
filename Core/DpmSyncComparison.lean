import Core.Dpm

/-! Pure admission for the finite producer/consumer controlled-resource
comparison profile. Admission establishes a complete native witness; it does
not establish a model match. Expected transition semantics stay in the model. -/
namespace Core.DpmSyncComparison

structure Identity where
  model : String
  mapping : String
  implementation : String
  deriving BEq, Repr

inductive Operation where
  | start | lock | unlock | send | receive | checkpoint | done
  deriving BEq, Repr

def Operation.text : Operation → String
  | .start => "start" | .lock => "lock" | .unlock => "unlock"
  | .send => "send" | .receive => "receive" | .checkpoint => "checkpoint"
  | .done => "$done"

structure Event where
  ordinal : Nat
  grant : Bool
  actor : String
  operation : Operation
  resource : String
  value : Option Int := none
  enabled : List String := []
  deriving Repr

structure Decision where
  actor : String
  operation : Operation
  resource : String
  value : Int
  enabled : List String
  deriving Repr

structure Observation where
  afterDecisions : Nat
  count : Int
  received : List Int
  deriving Repr

structure Receipt where
  executionId : String
  identity : Identity
  decisions : Nat
  events : List Event
  observations : List Observation
  complete : Bool
  /-- Terminal actor/resource declarations were checked by the typed codec. -/
  terminalShape : Bool
  deriving Repr

private def digest (text : String) : Bool :=
  text.utf8ByteSize == 64 && text.toList.all fun c =>
    ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')

def validIdentity (identity : Identity) : Bool :=
  [identity.model, identity.mapping, identity.implementation].all digest

def validActor (actor : String) : Bool := ["producer", "consumer"].contains actor

private def validResource (operation : Operation) (resource : String) : Bool :=
  match operation with
  | .start | .done => resource.isEmpty
  | .lock | .unlock => resource == "mutex"
  | .send | .receive => resource == "queue"
  | .checkpoint => resource == "critical"

private def pairEvents : List Event → Nat → Except String (List Decision)
  | [], _ => .ok []
  | grant :: result :: rest, index => do
      unless grant.grant && !result.grant && grant.ordinal == 2*index &&
          result.ordinal == 2*index+1 && grant.actor == result.actor &&
          grant.operation == result.operation && grant.resource == result.resource &&
          validActor grant.actor && validResource grant.operation grant.resource &&
          grant.value.isNone && result.enabled.isEmpty &&
          grant.enabled.contains grant.actor &&
          grant.enabled.all validActor && grant.enabled.eraseDups == grant.enabled do
        throw "invalid controlled decision event pair"
      let some value := result.value | throw "missing controlled result value"
      unless -9223372036854775808 ≤ value && value ≤ 9223372036854775807 do
        throw "controlled result is outside int64"
      let tail ← pairEvents rest (index+1)
      let decision : Decision := {
        actor := grant.actor
        operation := grant.operation
        resource := grant.resource
        value
        enabled := grant.enabled }
      return decision :: tail
  | _, _ => .error "incomplete controlled decision event pair"

/-- A complete receipt becomes a bounded decision/observation witness. Neither
native `passed` nor this successful admission implies model conformance. -/
def admit (expected : Identity) (receipt : Receipt) : Except String (List Decision) := do
  unless validIdentity expected && expected == receipt.identity do
    throw "controlled model/mapping/implementation identity differs"
  unless !receipt.executionId.isEmpty && receipt.executionId.utf8ByteSize ≤ 256 &&
      receipt.executionId.toList.all (fun c => c.toNat < 128 && c.toNat ≥ 32) do
    throw "invalid controlled execution identity"
  unless receipt.complete && receipt.terminalShape do
    throw "controlled execution or cleanup is incomplete"
  unless receipt.decisions > 0 && receipt.decisions ≤ 32 &&
      receipt.events.length == 2*receipt.decisions &&
      receipt.observations.length == receipt.decisions+1 do
    throw "controlled witness is incomplete or outside finite bounds"
  let decisions ← pairEvents receipt.events 0
  for actor in ["consumer", "producer"] do
    let chain := decisions.filter (fun decision => decision.actor == actor)
    unless (chain.head?.map (·.operation)) == some .start &&
        (chain.getLast?.map (·.operation)) == some .done &&
        (chain.filter (fun d => d.operation == .start)).length == 1 &&
        (chain.filter (fun d => d.operation == .done)).length == 1 do
      throw "controlled actor lacks its complete start/completion chain"
  for (observation, index) in receipt.observations.zipIdx do
    unless observation.afterDecisions == index && observation.received.length ≤ 2 &&
        -9223372036854775808 ≤ observation.count && observation.count ≤ 9223372036854775807 &&
        observation.received.all (fun v => -9223372036854775808 ≤ v && v ≤ 9223372036854775807) do
      throw "invalid or incomplete controlled observation"
  return decisions

/-- Reuse the existing finite-catalog cost: actors, fixed input rank,
preemptions and decisions. This profile reduces an explicitly supplied catalog. -/
def cost (decisions : List Decision) : List Nat := Core.Dpm.cost {
  id := "controlled-sync"
  inputRank := 0
  steps := decisions.map fun decision => {
    actor := decision.actor
    checkpoint := decision.operation.text } }

end Core.DpmSyncComparison
