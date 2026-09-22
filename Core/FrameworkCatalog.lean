/-!
# Framework catalog domain and validation

Pure version-1 capability/catalog types. JSON decoding, filesystem access and
rendering remain outside this module.
-/

namespace Core.FrameworkCatalog

def schemaV1 : String := "mirrors.framework-catalog/v1"

structure ValidationError where
  code : String
  path : String
  message : String
  deriving Repr, BEq

structure ComponentRef where
  componentId : String
  repository : String
  revision : String
  dirty : Bool
  dirtyDigest : Option String := none
  deriving Repr, BEq

structure Component where
  ref : ComponentRef
  productName : String
  productVersion : String
  deriving Repr, BEq

structure EvidenceRef where
  evidenceId : String
  schemaVersion : String
  runId : String
  envelopeSha256 : String
  projectionKind : String
  deriving Repr, BEq

structure Observation where
  dimension : String
  state : String
  evidenceId : Option String := none
  deriving Repr, BEq

structure Constraint where
  constraintId : String
  factKind : String
  factId : String
  operator : String
  values : List String
  deriving Repr, BEq

structure Capability where
  capabilityId : String
  ownerComponentId : String
  declarationState : String
  sourceState : String
  constraints : List Constraint
  observations : List Observation
  deriving Repr, BEq

structure Platform where
  os : String
  osRelease : String
  architecture : String
  backend : Option String := none
  deriving Repr, BEq

structure Dependency where
  dependencyId : String
  version : Option String := none
  className : String
  deriving Repr, BEq

structure DistributionProfile where
  profileId : String
  platform : Platform
  requiredCapabilityIds : List String
  optionalCapabilityIds : List String
  requiredObservationDimensions : List String
  dependencies : List Dependency
  deriving Repr, BEq

structure Combination where
  combinationId : String
  componentIds : List String
  platform : Platform
  capabilityIds : List String
  distributionProfileIds : List String
  declaredState : String
  evidenceIds : List String
  deriving Repr, BEq

structure Catalog where
  catalogId : String
  visibility : String
  components : List Component
  evidenceRefs : List EvidenceRef
  capabilities : List Capability
  distributionProfiles : List DistributionProfile
  combinations : List Combination
  deriving Repr, BEq

private def duplicates (values : List String) : List (Nat × String) :=
  values.zipIdx.filterMap fun (value, index) =>
    if (values.take index).contains value then some (index, value) else none

private def error (code path message : String) : ValidationError :=
  { code, path, message }

private def observation? (capability : Capability) (dimension : String) : Option Observation :=
  capability.observations.find? (·.dimension == dimension)

private def acceptedAt (capability : Capability) (dimension : String) : Bool :=
  match observation? capability dimension with
  | some observation => observation.state == "accepted" && observation.evidenceId.isSome
  | none => false

private def semver? (value : String) : Option (Nat × Nat × Nat) :=
  match value.splitOn "." with
  | [major, minor, patch] => do
      let majorNat ← major.toNat?
      let minorNat ← minor.toNat?
      let patchNat ← patch.toNat?
      if majorNat.repr != major || minorNat.repr != minor || patchNat.repr != patch then none
      else return (majorNat, minorNat, patchNat)
  | _ => none

private def semverAtLeast (actual minimum : String) : Bool :=
  match semver? actual, semver? minimum with
  | some (a, b, c), some (x, y, z) =>
      a > x || (a == x && (b > y || (b == y && c ≥ z)))
  | _, _ => false

private def constraintActual? (catalog : Catalog) (profile : DistributionProfile)
    (combination : Combination) (constraint : Constraint) : Option String :=
  match constraint.factKind with
  | "platformField" => match constraint.factId with
      | "os" => some combination.platform.os
      | "osRelease" => some combination.platform.osRelease
      | "architecture" => some combination.platform.architecture
      | "backend" => combination.platform.backend
      | _ => none
  | "componentVersion" =>
      (catalog.components.find? (·.ref.componentId == constraint.factId)).map (·.productVersion)
  | "dependencyVersion" =>
      (profile.dependencies.find? (·.dependencyId == constraint.factId)).bind (·.version)
  | "capabilitySelected" => some (if combination.capabilityIds.contains constraint.factId then "true" else "false")
  | _ => none

private def constraintSatisfied (actual : String) (constraint : Constraint) : Bool :=
  match constraint.operator with
  | "equals" => constraint.values == [actual]
  | "oneOf" => constraint.values.contains actual
  | "atLeastSemver" => match constraint.values with
      | [minimum] => semverAtLeast actual minimum
      | _ => false
  | _ => false

private def constraintPairCompatible (left right : Constraint) : Bool :=
  if left.factKind != right.factKind || left.factId != right.factId then true
  else match left.operator, right.operator with
    | "equals", "equals" => left.values == right.values
    | "equals", "oneOf" => left.values.all right.values.contains
    | "oneOf", "equals" => right.values.all left.values.contains
    | "oneOf", "oneOf" => left.values.any right.values.contains
    | "equals", "atLeastSemver" => match left.values, right.values with
        | [actual], [minimum] => semverAtLeast actual minimum
        | _, _ => false
    | "atLeastSemver", "equals" => match right.values, left.values with
        | [actual], [minimum] => semverAtLeast actual minimum
        | _, _ => false
    | "oneOf", "atLeastSemver" => match right.values with
        | [minimum] => left.values.any fun actual => semverAtLeast actual minimum
        | _ => false
    | "atLeastSemver", "oneOf" => match left.values with
        | [minimum] => right.values.any fun actual => semverAtLeast actual minimum
        | _ => false
    | "atLeastSemver", "atLeastSemver" => true
    | _, _ => false

private def setDuplicates (path label : String) (values : List String) : List ValidationError :=
  (duplicates values).map fun (index, value) =>
    error "E-FCAT-DUPLICATE-001" s!"{path}[{index}]" s!"duplicate {label}: {value}"

private def profileErrors (catalog : Catalog) (index : Nat)
    (profile : DistributionProfile) : List ValidationError := Id.run do
  let path := s!"$.distributionProfiles[{index}]"
  let mut errors := setDuplicates (path ++ ".requiredCapabilityIds") "capabilityId"
    profile.requiredCapabilityIds
  errors := errors ++ setDuplicates (path ++ ".optionalCapabilityIds") "capabilityId"
    profile.optionalCapabilityIds
  errors := errors ++ setDuplicates (path ++ ".requiredObservationDimensions") "observation dimension"
    profile.requiredObservationDimensions
  errors := errors ++ setDuplicates (path ++ ".dependencies") "dependencyId"
    (profile.dependencies.map (·.dependencyId))
  for capabilityId in profile.requiredCapabilityIds ++ profile.optionalCapabilityIds do
    if !(catalog.capabilities.any (·.capabilityId == capabilityId)) then
      errors := errors ++ [error "E-FCAT-REFERENCE-001" (path ++ ".requiredCapabilityIds")
        s!"capabilityId does not resolve: {capabilityId}"]
  for capabilityId in profile.requiredCapabilityIds do
    if profile.optionalCapabilityIds.contains capabilityId then
      errors := errors ++ [error "E-FCAT-CONTRADICTION-001" path
        s!"capability cannot be both required and optional: {capabilityId}"]
  errors

private def fixedPolicyErrors (index : Nat) (profile : DistributionProfile) : List ValidationError :=
  let path := s!"$.distributionProfiles[{index}].requiredObservationDimensions"
  match profile.platform.backend with
  | some "local-process" =>
      if profile.requiredObservationDimensions.contains "installedConsumerAccepted" then []
      else [error "E-FCAT-STATE-001" path
        "local-process supported profile requires installedConsumerAccepted"]
  | some "linux-bubblewrap-v1" =>
      let missing := ["installedConsumerAccepted", "locallyAccepted"].filter
        fun dimension => !profile.requiredObservationDimensions.contains dimension
      if missing.isEmpty then []
      else [error "E-FCAT-STATE-001" path
        "linux-bubblewrap-v1 supported profile requires installedConsumerAccepted and locallyAccepted"]
  | _ => []

private def capabilityErrors (catalog : Catalog) (index : Nat)
    (capability : Capability) : List ValidationError := Id.run do
  let mut errors : List ValidationError := []
  if !(catalog.components.any fun component =>
      component.ref.componentId == capability.ownerComponentId) then
    errors := errors ++ [error "E-FCAT-REFERENCE-001"
      s!"$.capabilities[{index}].ownerComponentId"
      s!"ownerComponentId does not resolve: {capability.ownerComponentId}"]
  errors := errors ++ setDuplicates
    s!"$.capabilities[{index}].declaration.constraints" "constraintId"
    (capability.constraints.map (·.constraintId))
  for constraint in capability.constraints do
    if constraint.factKind == "componentVersion" &&
        !(catalog.components.any (·.ref.componentId == constraint.factId)) then
      errors := errors ++ [error "E-FCAT-REFERENCE-001"
        s!"$.capabilities[{index}].declaration.constraints"
        s!"constraint component does not resolve: {constraint.factId}"]
    if constraint.factKind == "capabilitySelected" &&
        !(catalog.capabilities.any (·.capabilityId == constraint.factId)) then
      errors := errors ++ [error "E-FCAT-REFERENCE-001"
        s!"$.capabilities[{index}].declaration.constraints"
        s!"constraint capability does not resolve: {constraint.factId}"]
  for (left, leftIndex) in capability.constraints.zipIdx do
    for right in capability.constraints.drop (leftIndex + 1) do
      if !constraintPairCompatible left right then
        errors := errors ++ [error "E-FCAT-CONTRADICTION-001"
          s!"$.capabilities[{index}].declaration.constraints"
          s!"constraints disagree for {left.factKind}:{left.factId}"]
  for observation in capability.observations do
    match observation.evidenceId with
    | some evidenceId =>
        if !(catalog.evidenceRefs.any fun evidence => evidence.evidenceId == evidenceId) then
          errors := errors ++ [error "E-FCAT-REFERENCE-001"
            s!"$.capabilities[{index}].observations.{observation.dimension}.evidenceId"
            s!"evidenceId does not resolve: {evidenceId}"]
        if observation.state == "unknown" || observation.state == "notRun" then
          errors := errors ++ [error "E-FCAT-STATE-001"
            s!"$.capabilities[{index}].observations.{observation.dimension}"
            s!"{observation.state} observation must not carry evidenceId"]
    | none =>
        if observation.state == "accepted" || observation.state == "rejected" then
          let code := if observation.dimension == "published" then
            "E-FCAT-STATE-003" else "E-FCAT-STATE-001"
          let message := if observation.dimension == "published" then
            "accepted publication requires evidenceId"
            else s!"{observation.state} observation requires evidenceId"
          errors := errors ++ [error code
            s!"$.capabilities[{index}].observations.{observation.dimension}" message]
  errors

private def combinationErrors (catalog : Catalog) (index : Nat)
    (combination : Combination) : List ValidationError := Id.run do
  let mut errors : List ValidationError := []
  errors := errors ++ setDuplicates s!"$.combinations[{index}].componentIds"
    "componentId" combination.componentIds
  errors := errors ++ setDuplicates s!"$.combinations[{index}].capabilityIds"
    "capabilityId" combination.capabilityIds
  errors := errors ++ setDuplicates s!"$.combinations[{index}].distributionProfileIds"
    "distributionProfileId" combination.distributionProfileIds
  errors := errors ++ setDuplicates s!"$.combinations[{index}].evidenceIds"
    "evidenceId" combination.evidenceIds
  for componentId in combination.componentIds do
    if !(catalog.components.any fun component => component.ref.componentId == componentId) then
      errors := errors ++ [error "E-FCAT-REFERENCE-001"
        s!"$.combinations[{index}].componentIds" s!"componentId does not resolve: {componentId}"]
  for capabilityId in combination.capabilityIds do
    if !(catalog.capabilities.any fun capability => capability.capabilityId == capabilityId) then
      errors := errors ++ [error "E-FCAT-REFERENCE-001"
        s!"$.combinations[{index}].capabilityIds" s!"capabilityId does not resolve: {capabilityId}"]
  for evidenceId in combination.evidenceIds do
    if !(catalog.evidenceRefs.any fun evidence => evidence.evidenceId == evidenceId) then
      errors := errors ++ [error "E-FCAT-REFERENCE-001"
        s!"$.combinations[{index}].evidenceIds" s!"evidenceId does not resolve: {evidenceId}"]
  for profileId in combination.distributionProfileIds do
    match catalog.distributionProfiles.find? (·.profileId == profileId) with
    | none =>
        errors := errors ++ [error "E-FCAT-REFERENCE-001"
          s!"$.combinations[{index}].distributionProfileIds"
          s!"distributionProfileId does not resolve: {profileId}"]
    | some profile =>
        if profile.platform != combination.platform then
          errors := errors ++ [error "E-FCAT-PLATFORM-001"
            s!"$.combinations[{index}].platform.architecture"
            s!"combination platform differs from distribution profile {profileId}"]
        if combination.declaredState == "supported" then
          errors := errors ++ fixedPolicyErrors
            ((catalog.distributionProfiles.findIdx? (·.profileId == profileId)).getD 0) profile
          for capabilityId in profile.requiredCapabilityIds do
            match catalog.capabilities.find? (·.capabilityId == capabilityId) with
            | none =>
                errors := errors ++ [error "E-FCAT-REFERENCE-001"
                  s!"$.distributionProfiles[{profileId}].requiredCapabilityIds"
                  s!"capabilityId does not resolve: {capabilityId}"]
            | some capability =>
                if !combination.capabilityIds.contains capabilityId then
                  errors := errors ++ [error "E-FCAT-CONTRADICTION-001"
                    s!"$.combinations[{index}].capabilityIds"
                    s!"supported combination omits required capability: {capabilityId}"]
                if !combination.componentIds.contains capability.ownerComponentId then
                  errors := errors ++ [error "E-FCAT-CONTRADICTION-001"
                    s!"$.combinations[{index}].componentIds"
                    s!"supported combination omits capability owner: {capability.ownerComponentId}"]
                if capability.declarationState == "unavailable" || capability.sourceState == "absent" then
                  errors := errors ++ [error "E-FCAT-CONTRADICTION-001"
                    s!"$.combinations[{index}].declaredState"
                    s!"supported combination requires unavailable capability: {capabilityId}"]
                for dimension in profile.requiredObservationDimensions do
                  if !acceptedAt capability dimension then
                    errors := errors ++ [error "E-FCAT-STATE-003"
                      s!"$.combinations[{index}].declaredState"
                      s!"supported combination lacks accepted {dimension} evidence for {capabilityId}"]
                for constraint in capability.constraints do
                  match constraintActual? catalog profile combination constraint with
                  | none =>
                      errors := errors ++ [error "E-FCAT-REFERENCE-001"
                        s!"$.combinations[{index}].declaredState"
                        s!"constraint fact does not resolve: {constraint.factKind}:{constraint.factId}"]
                  | some actual =>
                      if !constraintSatisfied actual constraint then
                        errors := errors ++ [error "E-FCAT-CONTRADICTION-001"
                          s!"$.combinations[{index}].declaredState"
                          s!"constraint is not satisfied: {constraint.constraintId}"]
  errors

/-- Validate all cross-record references and state combinations. Structural
decoding errors are reported by `Codec.FrameworkCatalog` before this function. -/
def validate (catalog : Catalog) : List ValidationError :=
  Id.run do
    let mut errors : List ValidationError := []
    for (index, value) in duplicates (catalog.components.map (·.ref.componentId)) do
      errors := errors ++ [error "E-FCAT-DUPLICATE-001"
        s!"$.components[{index}].componentRef.componentId" s!"duplicate componentId: {value}"]
    for (index, value) in duplicates (catalog.evidenceRefs.map (·.evidenceId)) do
      errors := errors ++ [error "E-FCAT-DUPLICATE-001"
        s!"$.evidenceRefs[{index}].evidenceId" s!"duplicate evidenceId: {value}"]
    for (evidence, index) in catalog.evidenceRefs.zipIdx do
      let identity := evidence.schemaVersion ++ "\u0000" ++ evidence.runId ++ "\u0000" ++
        evidence.envelopeSha256 ++ "\u0000" ++ evidence.projectionKind
      if (catalog.evidenceRefs.take index).any fun earlier =>
          earlier.schemaVersion ++ "\u0000" ++ earlier.runId ++ "\u0000" ++
            earlier.envelopeSha256 ++ "\u0000" ++ earlier.projectionKind == identity then
        errors := errors ++ [error "E-FCAT-DUPLICATE-001"
          s!"$.evidenceRefs[{index}].runRef" "duplicate runRef identity"]
    for (index, value) in duplicates (catalog.capabilities.map (·.capabilityId)) do
      errors := errors ++ [error "E-FCAT-DUPLICATE-001"
        s!"$.capabilities[{index}].capabilityId" s!"duplicate capabilityId: {value}"]
    for (index, value) in duplicates (catalog.distributionProfiles.map (·.profileId)) do
      errors := errors ++ [error "E-FCAT-DUPLICATE-001"
        s!"$.distributionProfiles[{index}].profileId" s!"duplicate profileId: {value}"]
    for (index, value) in duplicates (catalog.combinations.map (·.combinationId)) do
      errors := errors ++ [error "E-FCAT-DUPLICATE-001"
        s!"$.combinations[{index}].combinationId" s!"duplicate combinationId: {value}"]
    for (capability, index) in catalog.capabilities.zipIdx do
      errors := errors ++ capabilityErrors catalog index capability
    for (profile, index) in catalog.distributionProfiles.zipIdx do
      errors := errors ++ profileErrors catalog index profile
    for (combination, index) in catalog.combinations.zipIdx do
      errors := errors ++ combinationErrors catalog index combination
    errors.mergeSort fun left right =>
      (left.path ++ "\u0000" ++ left.code) ≤ (right.path ++ "\u0000" ++ right.code)

end Core.FrameworkCatalog
