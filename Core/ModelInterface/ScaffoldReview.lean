import Core.ModelInterface.Scaffold
import Core.ModelInterface.EvidenceMerge

namespace Core.ModelInterface

def reviewableScaffoldSchemaV1 := "mirrors.model-interface-scaffold-reviewable/v1"
def scaffoldReviewSchemaV1 := "mirrors.model-interface-scaffold-review/v1"
def scaffoldReviewReceiptSchemaV1 := "mirrors.model-interface-scaffold-review-receipt/v1"

structure ReviewableScaffold where
  schema : String := reviewableScaffoldSchemaV1
  scaffold : ScaffoldProposal
  sources : List SourceDigest
  members : List WorkflowEvidenceMember
  projectionPlanSha256 : Option String := none
  observedInitializers : List String
  observedTransitions : List String
  deriving Repr

structure ScaffoldReplacement where
  kind : String
  fromId : String
  toId : String
  deriving Repr, DecidableEq

structure ScaffoldObligationDisposition where
  stableId : String
  disposition : String
  target : String
  reason : String
  deriving Repr, DecidableEq

structure ScaffoldReview where
  schema : String := scaffoldReviewSchemaV1
  approved : Bool
  proposalSha256 : String
  complete : Bool
  initializers : List String
  transitions : List String
  contract : ContractV1
  replacements : List ScaffoldReplacement
  obligations : List ScaffoldObligationDisposition
  deriving Repr

structure ScaffoldReviewReceipt where
  schema : String := scaffoldReviewReceiptSchemaV1
  proposalSha256 : String
  reviewSha256 : String
  contractSha256 : String
  deriving Repr, DecidableEq

private def labels (actions : List ContractAction) : List String :=
  sortStrings (actions.flatMap fun a => a.wireAction :: a.wireAliases)

private def sameSegment : PathSegment → PathSegment → Bool
  | .field a, .field b => a == b
  | .index a, .index b => a == b
  | .mapKey a, .mapKey b => a == b
  | .variantValue a, .variantValue b => a == b
  | _, _ => false

private def sameInput (a b : ContractInput) : Bool :=
  a.id == b.id && a.fromRoot == b.fromRoot && a.path.length == b.path.length &&
    (a.path.zip b.path).all (fun pair => sameSegment pair.1 pair.2) &&
    a.expectedType.map canonicalizeModelType == b.expectedType.map canonicalizeModelType

private def sameAction (a b : ContractAction) : Bool :=
  a.id == b.id && a.wireAction == b.wireAction &&
    sortStrings a.wireAliases == sortStrings b.wireAliases

private def sameObservation (a b : ContractObservation) : Bool :=
  a.id == b.id && a.wireName == b.wireName && a.provenance == b.provenance &&
    a.expectedType.map canonicalizeModelType == b.expectedType.map canonicalizeModelType

private partial def nonStringMap : ModelType → Bool
  | .map k v => k != .str || nonStringMap k || nonStringMap v
  | .set t | .seq t => nonStringMap t
  | .tuple ts => ts.any nonStringMap
  | .record fs => fs.any fun f => nonStringMap f.type
  | .variant cs => cs.any fun c => nonStringMap c.payload
  | _ => false

private def replacementKey (r : ScaffoldReplacement) : String := r.kind ++ "/" ++ r.fromId

private def mapped (review : ScaffoldReview) (kind sourceId : String) : String :=
  ((review.replacements.find? fun r => r.kind == kind && r.fromId == sourceId).map (·.toId)).getD sourceId

private def requireDecision (review : ScaffoldReview) (kind sourceId targetId : String)
    (unchanged : Bool) : Except String (List String) := do
  match review.replacements.find? (fun r => r.kind == kind && r.fromId == sourceId) with
  | none =>
      if unchanged then return []
      else throw s!"changed {kind} {sourceId} requires an explicit replacement"
  | some replacement =>
      if replacement.toId != targetId then throw s!"replacement target does not match {kind} {sourceId}"
      if unchanged then throw s!"unnecessary replacement for unchanged {kind} {sourceId}"
      return [replacementKey replacement]

/-- Review cannot infer closure from observed samples. Every original subject
must survive or have a one-to-one, explicit replacement. Resolution remains a
separate check of the complete reviewed contract against admitted evidence. -/
def validateScaffoldReview (proposal : ReviewableScaffold) (proposalDigest : String)
    (review : ScaffoldReview) : Except String Unit := do
  if review.schema != scaffoldReviewSchemaV1 || !review.approved then
    throw "review requires literal approved:true"
  if review.proposalSha256 != proposalDigest then throw "review proposal digest is stale"
  if !review.complete then throw "review must explicitly declare complete action universes"
  if review.initializers.isEmpty ||
      !(duplicateStrings (review.initializers ++ review.transitions)).isEmpty then
    throw "review universes contain duplicates, phase overlap, or no initializer"
  if !(proposal.observedInitializers.all review.initializers.contains) ||
      !(proposal.observedTransitions.all review.transitions.contains) then
    throw "review universe omits an observed action or changes its phase"
  if sortStrings review.initializers != labels review.contract.initializers ||
      sortStrings review.transitions != labels review.contract.actions then
    throw "review universes must exactly match all reviewed contract wire labels"
  let original := proposal.scaffold.contract
  if original.model != review.contract.model || original.wire != review.contract.wire ||
      original.interfaceVersion != review.contract.interfaceVersion then
    throw "review cannot change model identity, wire configuration, or interface version"
  if review.replacements.length > 8192 || review.obligations.length > maxObservationsV1 then
    throw "review decision count exceeds bounds"
  if !(duplicateStrings (review.replacements.map replacementKey)).isEmpty ||
      !(duplicateStrings (review.replacements.map fun r => r.kind ++ "/" ++ r.toId)).isEmpty then
    throw "replacement decisions must be one-to-one and unique"
  let mut consumed : List String := []
  let mut mappedTargets : List String := []
  for (kind, oldActions, newActions) in
      [("initializer", original.initializers, review.contract.initializers),
       ("action", original.actions, review.contract.actions)] do
    for old in oldActions do
      let target := mapped review kind old.id
      let some current := newActions.find? (fun a => a.id == target)
        | throw s!"review dropped {kind} {old.id} or names an unknown replacement"
      mappedTargets := mappedTargets ++ [kind ++ "/" ++ target]
      consumed := consumed ++ (← requireDecision review kind old.id target (sameAction old current))
      for input in old.inputs do
        let oldKey := old.id ++ "/" ++ input.id
        let defaultKey := current.id ++ "/" ++ input.id
        let target := ((review.replacements.find? fun r =>
          r.kind == "input" && r.fromId == oldKey).map (·.toId)).getD defaultKey
        let some newInput := current.inputs.find? (fun i => current.id ++ "/" ++ i.id == target)
          | throw s!"review dropped input {oldKey} or names an unknown replacement"
        mappedTargets := mappedTargets ++ ["input/" ++ target]
        consumed := consumed ++ (← requireDecision review "input" oldKey target
          (sameInput input newInput && oldKey == target))
  for old in original.observations do
    let target := mapped review "observation" old.id
    let some current := review.contract.observations.find? (fun o => o.id == target)
      | throw s!"review dropped observation {old.id} or names an unknown replacement"
    mappedTargets := mappedTargets ++ ["observation/" ++ target]
    consumed := consumed ++ (← requireDecision review "observation" old.id target
      (sameObservation old current))
  if sortStrings consumed != sortStrings (review.replacements.map replacementKey) then
    throw "review contains unknown or incomplete replacement decisions"
  if !(duplicateStrings mappedTargets).isEmpty then
    throw "replacement collides with another replaced or retained subject"
  let expected := proposal.scaffold.targetSupportObligations.map (·.stableId)
  if sortStrings expected != sortStrings (review.obligations.map (·.stableId)) then
    throw "review must give exactly one disposition for every target-support obligation"
  for obligation in review.obligations do
    if obligation.reason.trimAscii.toString.isEmpty then
      throw "target-support disposition requires a reason"
    if !["mirrorecma-v1", "mirrorecma-async-v1", "mirrorecma-async-v2", "mirrorcpp-v1", "mirrorcpp-v2",
        "mirrorrust-v1", "mirrorrust-v2", "mirrorlean-v1"].contains obligation.target then
      throw "unknown target in target-support disposition"
    if obligation.disposition == "replaced" then
      if !(review.replacements.any fun r =>
          r.kind == "observation" && r.fromId == obligation.stableId) then
        throw "replaced obligation requires an explicit observation replacement"
      let target := mapped review "observation" obligation.stableId
      let some observation := review.contract.observations.find? (fun o => o.id == target)
        | throw "replacement obligation names an unknown observation"
      if observation.expectedType.isNone || observation.expectedType.any nonStringMap then
        throw "replacement did not eliminate the target-support obligation"
    else if obligation.disposition != "target-supported" then
      throw "invalid target-support disposition"

end Core.ModelInterface
