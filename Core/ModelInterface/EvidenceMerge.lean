import Core.ModelInterface.Resolve
import Core.ModelInterface.Sha256

/-! Pure, bounded evidence-corpus admission. Closed structures must agree;
sampling more traces never widens a record or a variant. -/
namespace Core.ModelInterface

structure EvidenceCorpusMember where
  rawFileSha256 : String
  evidence : ModelEvidence
  initializerLabels : List String
  transitionLabels : List String
  deriving Repr

structure MergedEvidenceCorpus where
  evidence : ModelEvidence
  initializerLabels : List String
  transitionLabels : List String
  deriving Repr

private def canonicalNames (names : List String) : List String :=
  sortStrings (stableUniqueStrings names)

/-- Raw hashes identify distinct inputs. The aggregate structural identity is
independent of paths, source locations, member order, and repeated facts. -/
def mergeEvidenceCorpus (members : List EvidenceCorpusMember) :
    Except String MergedEvidenceCorpus := do
  if members.isEmpty || members.length > maxWorkflowMembersV1 then
    throw s!"evidence corpus requires 1..{maxWorkflowMembersV1} members"
  if !(duplicateStrings (members.map (·.rawFileSha256))).isEmpty then
    throw "duplicate raw evidence input"
  let members := members.mergeSort fun a b => a.rawFileSha256 ≤ b.rawFileSha256
  let some first := members.head? | throw "empty evidence corpus"
  let variables := canonicalNames first.evidence.traceVars
  let parameters := canonicalNames first.evidence.itfParamVars
  let mut facts : List TypeFact := []
  for member in members do
    if !(duplicateStrings member.evidence.traceVars).isEmpty ||
        !(duplicateStrings member.evidence.itfParamVars).isEmpty then
      throw "duplicate evidence variable or parameter variable"
    if canonicalNames member.evidence.traceVars != variables ||
        canonicalNames member.evidence.itfParamVars != parameters then
      throw "evidence members have incompatible variable or parameter sets"
    for fact in member.evidence.typeFacts do
      if !fact.modelPath.path.isEmpty || !variables.contains fact.modelPath.root then
        throw "evidence member has an unknown or non-top-level type fact"
    for variableName in variables do
      let observed := member.evidence.typeFacts.filter fun f => f.modelPath.root == variableName
      if observed.isEmpty then throw s!"missing structural type for {variableName}"
      for fact in observed do
        let normalized := canonicalizeModelType fact.type
        match facts.find? (fun f => f.modelPath.root == variableName) with
        | some previous =>
            if previous.type != normalized then
              throw s!"conflicting closed structural evidence for {variableName}"
        | none =>
            facts := facts ++ [{ fact with
              type := normalized
              location := { source := "<evidence-corpus>", pointer := some variableName } }]
  let initializers := canonicalNames (members.flatMap (·.initializerLabels))
  let transitions := canonicalNames (members.flatMap (·.transitionLabels))
  if initializers.any transitions.contains then
    throw "observed action label appears in both initializer and transition phases"
  if initializers.isEmpty then throw "evidence corpus has no observed initializer"
  let digests := canonicalNames (members.map (·.evidence.evidenceSha256))
  let digest := Sha256.digestDomainHex "mirrors-model-interface-evidence-corpus/v1"
    (String.intercalate "\n" digests).toUTF8
  return {
    evidence := {
      traceVars := variables
      itfParamVars := parameters
      typeFacts := facts
      evidenceSha256 := digest }
    initializerLabels := initializers
    transitionLabels := transitions }

end Core.ModelInterface
