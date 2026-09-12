import Core.ModelInterface.Resolve

/-!
# Pure model-interface scaffold synthesis

Builds an explicitly unsealed companion-contract proposal from normalized
source identity, typed evidence, and observed action labels.  This module has
no filesystem, JSON, hashing, resolution-command, or target-emission effects.
-/

namespace Core.ModelInterface

def scaffoldSchemaV1 : String := "mirrors.model-interface-scaffold/v1"

/-- Content-addressed provenance for an optional compiler-owned trace
projection. The source hash remains in `ScaffoldProposal.source`. -/
structure ScaffoldProjectionProvenance where
  rawSha256 : String
  planSha256 : String
  outputSha256 : String
  deriving Repr, DecidableEq

structure ScaffoldInput where
  interfaceVersion : String := "1.0.0"
  source : SourceDigest
  sourceVariableNames : List String
  evidence : ModelEvidence
  initializerLabels : List String
  transitionLabels : List String
  configuredParamVar : Option String := none
  projection : Option ScaffoldProjectionProvenance := none
  deriving Repr

/-- A target lowering must explicitly decide how to represent this inferred
observation type.  Version 1 emits these for maps with non-string keys. -/
structure TargetSupportObligation where
  subjectKind : String := "observation"
  stableId : StableId
  type : ModelType
  deriving Repr

structure ScaffoldProposal where
  schema : String := scaffoldSchemaV1
  contract : ContractV1
  unsealedInitializers : List StableId
  unsealedActions : List StableId
  source : SourceDigest
  evidenceSha256 : String
  projection : Option ScaffoldProjectionProvenance := none
  targetSupportObligations : List TargetSupportObligation
  deriving Repr

private def scaffoldDiagnostic (code subjectKind : String)
    (stableId : Option String) (source reason : String) : Diagnostic :=
  { code
    severity := .error
    stage := "scaffold"
    subject := { kind := subjectKind, stableId }
    primary := { source }
    arguments := [("reason", reason)] }

private def asciiUpper (c : Char) : Bool :=
  65 ≤ c.toNat && c.toNat ≤ 90

private def asciiLower (c : Char) : Bool :=
  97 ≤ c.toNat && c.toNat ≤ 122

private def asciiDigit (c : Char) : Bool :=
  48 ≤ c.toNat && c.toNat ≤ 57

private def asciiAlphaNumeric (c : Char) : Bool :=
  asciiUpper c || asciiLower c || asciiDigit c

private def upperAscii (c : Char) : Char :=
  if asciiLower c then Char.ofNat (c.toNat - 32) else c

private def lowerAscii (c : Char) : Char :=
  if asciiUpper c then Char.ofNat (c.toNat + 32) else c

private def capitalizeWord : List Char → List Char
  | [] => []
  | c :: cs => upperAscii c :: cs

private def splitLabelWords (chars : List Char) : List (List Char) :=
  let finished := chars.foldl (fun (state : List (List Char) × List Char) c =>
    if asciiAlphaNumeric c then (state.1, state.2 ++ [c])
    else if state.2.isEmpty then state
    else (state.1 ++ [state.2], [])) ([], [])
  if finished.2.isEmpty then finished.1 else finished.1 ++ [finished.2]

private def upperCamel (label : String) : String :=
  String.ofList <| (splitLabelWords label.toList).flatMap capitalizeWord

private def stripTerminalParam (id : String) : String :=
  if id.endsWith "Param" && id.length > 5 then
    (id.dropEnd 5).toString
  else id

private def actionStableId (label : String) : String :=
  if label == "init" then "Initialize" else upperCamel label

private def inputStableId (wireName : String) : String :=
  stripTerminalParam (upperCamel wireName)

private def reservedLabel (label : String) : Bool :=
  ["__proto__", "constructor", "prototype"].contains label

private def lowerHexChar (c : Char) : Bool :=
  asciiDigit c || (97 ≤ c.toNat && c.toNat ≤ 102)

private def validDigest (digest : String) : Bool :=
  digest.length == 64 && digest.toList.all lowerHexChar

private def sameStringSet (left right : List String) : Bool :=
  sortStrings (stableUniqueStrings left) == sortStrings (stableUniqueStrings right)

private def firstTopType? (evidence : ModelEvidence) (name : String) : Option ModelType :=
  (evidence.typeFacts.find? fun fact =>
    fact.modelPath.root == name && fact.modelPath.path.isEmpty).map
      (fun fact => canonicalizeModelType fact.type)

private def parameterFields? (input : ScaffoldInput) : Option (List ModelField) :=
  input.configuredParamVar.bind fun parameterVariable =>
    match firstTopType? input.evidence parameterVariable with
    | some (.record fields) => some fields
    | _ => none

private def inferredInputs (input : ScaffoldInput) : List ContractInput :=
  (input.configuredParamVar.bind fun parameterVariable =>
    (parameterFields? input).map fun fields =>
      fields.map fun field =>
        { id := inputStableId field.wireName
          fromRoot := .stepParameters
          path := [.field parameterVariable, .field field.wireName]
          expectedType := some field.type }).getD []

private def inferredAction (input : ScaffoldInput) (label : String)
    (transition : Bool) : ContractAction :=
  { id := actionStableId label
    wireAction := label
    inputs := if transition then inferredInputs input else [] }

private def inferredObservation (input : ScaffoldInput)
    (wireName : String) : ContractObservation :=
  { id := upperCamel wireName
    wireName
    expectedType := firstTopType? input.evidence wireName }

private partial def containsNonStringMap : ModelType → Bool
    | .map key value => key != .str || containsNonStringMap key || containsNonStringMap value
    | .set type | .seq type => containsNonStringMap type
    | .tuple types => types.any containsNonStringMap
    | .record fields => fields.any (fun field => containsNonStringMap field.type)
    | .variant cases => cases.any (fun item => containsNonStringMap item.payload)
    | _ => false

private def targetObligations (resolved : ResolvedModelInterface) :
    List TargetSupportObligation :=
  resolved.observations.filterMap fun observation =>
    if containsNonStringMap observation.type then
      some { stableId := observation.id, type := observation.type }
    else none

private def labelDiagnostics (source : String) (kind : String)
    (labels : List String) : List Diagnostic :=
  labels.flatMap fun label =>
    (if label.isEmpty then
      [scaffoldDiagnostic "MIC-S-ACTION-001" kind none source "action label is empty"]
    else []) ++
    (if reservedLabel label then
      [scaffoldDiagnostic "MIC-S-ACTION-001" kind (some label) source
        "action label is reserved"]
    else []) ++
    (if label.toUTF8.size > maxStableNameBytesV1 then
      [scaffoldDiagnostic "MIC-S-LIMIT-001" kind (some label) source
        "action label exceeds the version-1 byte limit"]
    else []) ++
    (if !label.isEmpty && !reservedLabel label &&
        !validStableId (actionStableId label) then
      [scaffoldDiagnostic "MIC-S-ID-001" kind (some label) source
        "action label cannot produce a stable UpperCamel identifier"]
    else [])

private def duplicateIdDiagnostics (source kind : String)
    (pairs : List (String × String)) : List Diagnostic :=
  (duplicateStrings (pairs.map Prod.snd)).map fun id =>
    let labels := pairs.filter (fun pair => pair.2 == id) |>.map Prod.fst
    scaffoldDiagnostic "MIC-S-ID-001" kind (some id) source
      s!"stable identifier collision: {String.intercalate "," labels}"

private def inputDiagnostics (input : ScaffoldInput) : List Diagnostic :=
  match input.configuredParamVar with
  | none => []
  | some parameterVariable =>
      match firstTopType? input.evidence parameterVariable with
      | some (.record []) =>
          [scaffoldDiagnostic "MIC-S-PARAM-001" "parameterVariable"
            (some parameterVariable) input.source.logicalPath
            "configured parameter variable must be a nonempty record"]
      | some (.record fields) =>
          fields.flatMap fun field =>
            let id := inputStableId field.wireName
            (if validStableId id then [] else
              [scaffoldDiagnostic "MIC-S-ID-001" "input" (some field.wireName)
                input.source.logicalPath
                "parameter field cannot produce a stable input identifier"]) ++
            (if id.toUTF8.size ≤ maxStableNameBytesV1 then [] else
              [scaffoldDiagnostic "MIC-S-LIMIT-001" "input" (some id)
                input.source.logicalPath "input identifier exceeds the version-1 byte limit"])
      | some _ =>
          [scaffoldDiagnostic "MIC-S-PARAM-001" "parameterVariable"
            (some parameterVariable) input.source.logicalPath
            "configured parameter variable must have record type evidence"]
      | none =>
          [scaffoldDiagnostic "MIC-S-PARAM-001" "parameterVariable"
            (some parameterVariable) input.source.logicalPath
            "configured parameter variable has no top-level type evidence"]

private def preliminaryDiagnostics (input : ScaffoldInput)
    (observationNames : List String) : List Diagnostic :=
  let source := input.source.logicalPath
  let initPairs := input.initializerLabels.map fun label => (label, actionStableId label)
  let actionPairs := input.transitionLabels.map fun label => (label, actionStableId label)
  let observationPairs := observationNames.map fun name => (name, upperCamel name)
  (if validDigest input.source.contentSha256 then [] else
    [scaffoldDiagnostic "MIC-S-DIGEST-001" "source" none source
      "source digest must be 64 lowercase hexadecimal characters"]) ++
  (if validDigest input.evidence.evidenceSha256 then [] else
    [scaffoldDiagnostic "MIC-S-DIGEST-001" "evidence" none source
      "evidence digest must be 64 lowercase hexadecimal characters"]) ++
  (if (duplicateStrings input.sourceVariableNames).isEmpty then [] else
    [scaffoldDiagnostic "MIC-S-SOURCE-001" "sourceVariables" none source
      "source variable names contain duplicates"]) ++
  (if sameStringSet input.sourceVariableNames input.evidence.traceVars then [] else
    [scaffoldDiagnostic "MIC-S-SOURCE-001" "sourceVariables" none source
      "source and evidence variable sets differ"] ) ++
  (if input.initializerLabels.isEmpty then
    [scaffoldDiagnostic "MIC-S-ACTION-001" "initializer" none source
      "at least one observed initializer label is required"]
   else []) ++
  labelDiagnostics source "initializer" input.initializerLabels ++
  labelDiagnostics source "action" input.transitionLabels ++
  (duplicateStrings (input.initializerLabels ++ input.transitionLabels)).map (fun label =>
    scaffoldDiagnostic "MIC-S-ACTION-001" "action" (some label) source
      "action label is duplicated or appears in both phases") ++
  duplicateIdDiagnostics source "action" (initPairs ++ actionPairs) ++
  duplicateIdDiagnostics source "observation" observationPairs ++
  observationPairs.filterMap (fun pair =>
    if validStableId pair.2 then none else
      some (scaffoldDiagnostic "MIC-S-ID-001" "observation" (some pair.1) source
        "variable name cannot produce a stable observation identifier")) ++
  inputDiagnostics input

/-- Synthesize a deterministic, complete, explicitly unsealed proposal. -/
def synthesizeScaffold (input : ScaffoldInput) : CompileResult ScaffoldProposal :=
  let run : RunProfile := { configuredParamVar := input.configuredParamVar }
  let observationNames := sortStrings (requiredObservationVars input.evidence run)
  let preliminary := preliminaryDiagnostics input observationNames
  if preliminary.any Diagnostic.isError then
    { value := none, diagnostics := sortDiagnostics preliminary }
  else
    let initializers := input.initializerLabels.map (inferredAction input · false)
    let actions := input.transitionLabels.map (inferredAction input · true)
    let observations := observationNames.map (inferredObservation input)
    let contract : ContractV1 :=
      { interfaceVersion := input.interfaceVersion
        model := { moduleName := input.source.moduleName, source := input.source.logicalPath }
        wire := { parameterVariable := input.configuredParamVar }
        initializers
        actions
        observations }
    let resolved := resolve
      { contract := Located.unlocated contract
        evidence := input.evidence
        runProfile := run
        sources := [input.source] }
    if resolved.hasErrors then
      { value := none, diagnostics := resolved.diagnostics }
    else match resolved.value with
      | none => { value := none, diagnostics := resolved.diagnostics }
      | some resolvedInterface =>
          let proposal : ScaffoldProposal :=
            { contract := resolvedInterface.contract
              unsealedInitializers := resolvedInterface.initializers.map (·.id)
              unsealedActions := resolvedInterface.actions.map (·.id)
              source := input.source
              evidenceSha256 := input.evidence.evidenceSha256
              projection := input.projection
              targetSupportObligations := targetObligations resolvedInterface }
          { value := some proposal, diagnostics := resolved.diagnostics }

private def obligationsWellFormed (proposal : ScaffoldProposal) : Bool :=
  let observations := proposal.contract.observations
  let expected := observations.filter (fun observation =>
    observation.expectedType.any containsNonStringMap)
  proposal.targetSupportObligations.map (·.stableId) == expected.map (·.id) &&
  proposal.targetSupportObligations.all (fun obligation =>
    obligation.subjectKind == "observation" &&
      observations.any (fun observation =>
        observation.id == obligation.stableId &&
          observation.expectedType == some obligation.type &&
          containsNonStringMap obligation.type))

private def inferredInputWellFormed (parameterVariable : String)
    (input : ContractInput) : Bool :=
  validStableId input.id && input.id.toUTF8.size ≤ maxStableNameBytesV1 &&
    input.fromRoot == .stepParameters &&
    (match input.path with
     | [.field root, .field field] =>
         root == parameterVariable && input.id == inputStableId field
     | _ => false) &&
    input.expectedType.any (fun type =>
      type.wellFormed && modelTypeDepth type ≤ maxStructuralTypeDepthV1)

private def inferredActionWellFormed (parameterVariable : Option String)
    (initializer : Bool) (action : ContractAction) : Bool :=
  validStableId action.id && action.id.toUTF8.size ≤ maxStableNameBytesV1 &&
    !action.wireAction.isEmpty && !reservedLabel action.wireAction &&
    action.wireAction.toUTF8.size ≤ maxStableNameBytesV1 &&
    action.wireAliases.isEmpty &&
    if initializer then action.inputs.isEmpty
    else match parameterVariable with
      | none => action.inputs.isEmpty
      | some parameterVariable =>
          !action.inputs.isEmpty &&
            action.inputs.all (inferredInputWellFormed parameterVariable) &&
            (duplicateStrings (action.inputs.map (·.id))).isEmpty

private def projectionProvenanceWellFormed : Option ScaffoldProjectionProvenance → Bool
  | none => true
  | some provenance =>
      validDigest provenance.rawSha256 && validDigest provenance.planSha256 &&
        validDigest provenance.outputSha256

/-- Pure structural checks available to strict proposal decoders. -/
def scaffoldProposalWellFormedV1 (proposal : ScaffoldProposal) : Bool :=
  let contract := proposal.contract
  let allActions := contract.initializers ++ contract.actions
  proposal.schema == scaffoldSchemaV1 &&
    contract.schema == contractSchemaV1 &&
    validInterfaceVersion contract.interfaceVersion &&
    validModuleName contract.model.moduleName &&
    validLogicalPath contract.model.source &&
    contract.model.moduleName == proposal.source.moduleName &&
    contract.model.source == proposal.source.logicalPath &&
    validDigest proposal.source.contentSha256 &&
    validDigest proposal.evidenceSha256 &&
    projectionProvenanceWellFormed proposal.projection &&
    contract.wire.actionVariable == actionVariableV1 &&
    !contract.initializers.isEmpty &&
    contract.initializers.length ≤ maxInitializersV1 &&
    contract.actions.length ≤ maxTransitionActionsV1 &&
    contract.observations.length ≤ maxObservationsV1 &&
    (duplicateStrings (allActions.map (·.id))).isEmpty &&
    (duplicateStrings (allActions.map (·.wireAction))).isEmpty &&
    contract.initializers.all (inferredActionWellFormed contract.wire.parameterVariable true) &&
    contract.actions.all (inferredActionWellFormed contract.wire.parameterVariable false) &&
    proposal.unsealedInitializers == contract.initializers.map (·.id) &&
    proposal.unsealedActions == contract.actions.map (·.id) &&
    (duplicateStrings (contract.observations.map (·.id))).isEmpty &&
    (duplicateStrings (contract.observations.map (·.wireName))).isEmpty &&
    contract.observations.all (fun observation =>
      validStableId observation.id && !observation.wireName.isEmpty &&
        observation.provenance == .implementation &&
        observation.expectedType.any ModelType.wellFormed) &&
    obligationsWellFormed proposal

end Core.ModelInterface
