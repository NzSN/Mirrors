import Core.FrameworkCatalog
import Core.ModelInterface.Sha256
import Codec.StrictJson
import Lean.Data.Json

/-! Strict version-1 framework-catalog decoding and canonical rendering. -/

namespace Codec.FrameworkCatalog

open Lean Core.FrameworkCatalog

abbrev DecodeResult (α : Type) := Except ValidationError α
private abbrev Fields := List (String × Json)

structure Decoded where
  catalog : Catalog
  json : Json
  canonical : String

def Decoded.selectionDigest (decoded : Decoded) : String :=
  Core.ModelInterface.Sha256.digestStringHex decoded.canonical

private def fail (code path message : String) : DecodeResult α :=
  .error { code, path, message }

private def fields (path : String) : Json → DecodeResult Fields
  | .obj value => .ok value.toList
  | _ => fail "E-FCAT-SCHEMA-001" path "object expected"

private def checkedFields (path : String) (allowed required : List String)
    (json : Json) : DecodeResult Fields := do
  let value ← fields path json
  match value.find? fun field => !allowed.contains field.1 with
  | some field => fail "E-FCAT-SCHEMA-001" (path ++ "." ++ field.1) s!"unknown field: {field.1}"
  | none => pure ()
  match required.find? fun name => (List.lookup name value).isNone with
  | some name => fail "E-FCAT-SCHEMA-001" (path ++ "." ++ name) s!"missing required field: {name}"
  | none => return value

private def required (path : String) (value : Fields) (name : String) : DecodeResult Json :=
  match List.lookup name value with
  | some json => .ok json
  | none => fail "E-FCAT-SCHEMA-001" (path ++ "." ++ name) s!"missing required field: {name}"

private def optional (value : Fields) (name : String) : Option Json :=
  List.lookup name value

private def optionalString (path : String) : Option Json → DecodeResult (Option String)
  | some (.str value) => .ok (some value)
  | some _ => fail "E-FCAT-SCHEMA-001" path "string expected"
  | none => .ok none

private def string (path : String) : Json → DecodeResult String
  | .str value =>
      if value.toUTF8.size > 65536 then
        fail "E-FCAT-BOUND-001" path "string exceeds 65536-byte limit"
      else .ok value
  | _ => fail "E-FCAT-SCHEMA-001" path "string expected"

private def boolean (path : String) : Json → DecodeResult Bool
  | .bool value => .ok value
  | _ => fail "E-FCAT-SCHEMA-001" path "Boolean expected"

private def array (path : String) : Json → DecodeResult (List Json)
  | .arr values => .ok values.toList
  | _ => fail "E-FCAT-SCHEMA-001" path "array expected"

private def boundedArray (path : String) (limit : Nat) (json : Json) : DecodeResult (List Json) := do
  let values ← array path json
  if values.length > limit then
    fail "E-FCAT-BOUND-001" path s!"array has {values.length} items; limit is {limit}"
  return values

private def stringArray (path : String) (json : Json) : DecodeResult (List String) := do
  let values ← array path json
  values.zipIdx.mapM fun (value, index) => string s!"{path}[{index}]" value

private def enum (path value : String) (allowed : List String) : DecodeResult String :=
  if allowed.contains value then .ok value
  else fail "E-FCAT-SCHEMA-001" path s!"unsupported value: {value}"

private def isLowerHex (length : Nat) (value : String) : Bool :=
  value.toUTF8.size == length && value.toList.all fun char =>
    ('0' ≤ char && char ≤ '9') || ('a' ≤ char && char ≤ 'f')

private def byteListLe (left right : List UInt8) : Bool :=
  match left, right with
  | [], _ => true
  | _ :: _, [] => false
  | a :: restA, b :: restB =>
      if a == b then byteListLe restA restB else a.toNat < b.toNat

private def keyLe (left right : String) : Bool :=
  byteListLe left.toUTF8.data.toList right.toUTF8.data.toList

private def identifier (path : String) (json : Json) : DecodeResult String := do
  let value ← string path json
  if value.isEmpty || value.toUTF8.size > 256 then
    fail "E-FCAT-BOUND-001" path "identifier must contain 1 to 256 UTF-8 bytes"
  return value

private def optionalIdentifier (path : String) : Option Json → DecodeResult (Option String)
  | some value => do return some (← identifier path value)
  | none => .ok none

private def idArray (path : String) (json : Json) : DecodeResult (List String) := do
  let values ← boundedArray path 256 json
  values.zipIdx.mapM fun (value, index) => identifier s!"{path}[{index}]" value

private def logicalPathWithLimit (limit : Nat) (path : String) (json : Json) : DecodeResult String := do
  let value ← string path json
  let segments := value.splitOn "/"
  let invalidControl := value.toList.any fun char => char.toNat < 0x20 || char.toNat == 0x7f
  let drivePath := value.toList[1]? == some ':'
  if value.isEmpty || value.toUTF8.size > limit || value.startsWith "/" ||
      value.contains "\\" || value.contains "//" || invalidControl ||
      drivePath || segments.any fun segment => segment.isEmpty || segment == "." || segment == ".." then
    fail "E-FCAT-IDENTITY-001" path "logical path must be relative, normalized, and traversal-free"
  return value

private def logicalPath (path : String) (json : Json) : DecodeResult String :=
  logicalPathWithLimit 4096 path json

private def requireSortedUnique (path label : String) (values : List String) : DecodeResult Unit := do
  let sorted := values.mergeSort keyLe
  if sorted != values then fail "E-FCAT-CONTRADICTION-001" path s!"{label} must be sorted by UTF-8 bytes"
  if values.zipIdx.any fun (value, index) => (values.take index).contains value then
    fail "E-FCAT-DUPLICATE-001" path s!"{label} contains a duplicate"

private def validExtensionName (value : String) : Bool :=
  let segments := value.splitOn "."
  segments.length ≥ 2 && segments.all fun segment =>
    !segment.isEmpty && !segment.startsWith "-" && !segment.endsWith "-" &&
      segment.toList.all fun char =>
        ('a' ≤ char && char ≤ 'z') || ('0' ≤ char && char ≤ '9') || char == '-'

private def validCoreSemver (value : String) : Bool :=
  match value.splitOn "." with
  | [major, minor, patch] => [major, minor, patch].all fun part =>
      match part.toNat? with
      | some number => number.repr == part
      | none => false
  | _ => false

private def revision (path : String) (json : Json) : DecodeResult String := do
  let value ← string path json
  if isLowerHex 40 value then return value
  fail "E-FCAT-IDENTITY-001" path "component revision must be 40 lowercase hexadecimal characters"

private def digest (path : String) (json : Json) : DecodeResult String := do
  let value ← string path json
  if isLowerHex 64 value then return value
  fail "E-FCAT-IDENTITY-001" path "SHA-256 must be 64 lowercase hexadecimal characters"

private def decodeDirty (path : String) (json : Json) : DecodeResult String := do
  let value ← checkedFields path ["algorithm", "digest", "method", "includedPaths", "excludedPaths"]
    ["algorithm", "digest", "method", "includedPaths", "excludedPaths"] json
  let algorithm ← string (path ++ ".algorithm") (← required path value "algorithm")
  if algorithm != "sha256" then
    fail "E-FCAT-IDENTITY-001" (path ++ ".algorithm") "dirty content algorithm must be sha256"
  let method ← string (path ++ ".method") (← required path value "method")
  let _ ← enum (path ++ ".method") method
    ["git-diff-and-untracked-manifest-v1", "filesystem-tree-v1"]
  let includedJson ← boundedArray (path ++ ".includedPaths") 4096
    (← required path value "includedPaths")
  let included ← includedJson.zipIdx.mapM fun (item, index) =>
    logicalPathWithLimit 1024 s!"{path}.includedPaths[{index}]" item
  let _ ← requireSortedUnique (path ++ ".includedPaths") "includedPaths" included
  let excluded ← boundedArray (path ++ ".excludedPaths") 4096
    (← required path value "excludedPaths")
  let mut excludedPaths : List String := []
  for (item, index) in excluded.zipIdx do
    let itemPath := s!"{path}.excludedPaths[{index}]"
    let itemFields ← checkedFields itemPath ["path", "reasonCode"] ["path", "reasonCode"] item
    let excludedPath ← logicalPathWithLimit 1024 (itemPath ++ ".path")
      (← required itemPath itemFields "path")
    excludedPaths := excludedPaths ++ [excludedPath]
    let reason ← string (itemPath ++ ".reasonCode") (← required itemPath itemFields "reasonCode")
    let _ ← enum (itemPath ++ ".reasonCode") reason
      ["pre-existing-unrelated", "evidence-output", "build-output"]
  let _ ← requireSortedUnique (path ++ ".excludedPaths") "excludedPaths" excludedPaths
  match included.find? excludedPaths.contains with
  | some overlap => fail "E-FCAT-CONTRADICTION-001" path s!"dirty path cannot be both included and excluded: {overlap}"
  | none => pure ()
  digest (path ++ ".digest") (← required path value "digest")

private def decodeComponentRef (visibility path : String) (json : Json) : DecodeResult ComponentRef := do
  let value ← checkedFields path ["componentId", "repository", "revision", "dirty", "dirtyContent"]
    ["componentId", "repository", "dirty"] json
  let componentId ← identifier (path ++ ".componentId") (← required path value "componentId")
  let repository ← string (path ++ ".repository") (← required path value "repository")
  if repository.startsWith "/" || repository.startsWith "file:" || repository.contains "\\" then
    fail "E-FCAT-IDENTITY-001" (path ++ ".repository") "repository must not be a host-local path"
  if visibility == "public" && !repository.startsWith "https://" then
    fail "E-FCAT-IDENTITY-001" (path ++ ".repository") "public repository must be an HTTPS URI"
  if visibility == "public" && (repository == "https://" || repository.contains "?" ||
      repository.contains "#" || repository.toList.any (·.isWhitespace)) then
    fail "E-FCAT-IDENTITY-001" (path ++ ".repository") "public repository URI must be normalized and immutable"
  let revisionJson ← match optional value "revision" with
    | some revision => pure revision
    | none => fail "E-FCAT-IDENTITY-001" (path ++ ".revision") "component revision is required"
  let revision ← revision (path ++ ".revision") revisionJson
  let dirty ← boolean (path ++ ".dirty") (← required path value "dirty")
  let dirtyDigest ← match dirty, optional value "dirtyContent" with
    | true, some content => some <$> decodeDirty (path ++ ".dirtyContent") content
    | true, none => fail "E-FCAT-IDENTITY-001" (path ++ ".dirtyContent") "dirty component requires dirtyContent"
    | false, some _ => fail "E-FCAT-IDENTITY-001" (path ++ ".dirtyContent") "clean component must not contain dirtyContent"
    | false, none => pure none
  if visibility == "public" && dirty then
    fail "E-FCAT-IDENTITY-001" path "public catalog must not contain dirty componentRef"
  return { componentId, repository, revision, dirty, dirtyDigest }

private def decodeComponent (visibility : String) (index : Nat) (json : Json) : DecodeResult Component := do
  let path := s!"$.components[{index}]"
  let value ← checkedFields path ["componentRef", "product", "records"]
    ["componentRef", "product", "records"] json
  let ref ← decodeComponentRef visibility (path ++ ".componentRef")
    (← required path value "componentRef")
  let productPath := path ++ ".product"
  let product ← checkedFields productPath ["name", "version"] ["name", "version"]
    (← required path value "product")
  let records ← array (path ++ ".records") (← required path value "records")
  for (record, recordIndex) in records.zipIdx do
    let recordPath := s!"{path}.records[{recordIndex}]"
    let recordFields ← checkedFields recordPath ["recordId", "path", "recordKind"]
      ["recordId", "path", "recordKind"] record
    let _ ← identifier (recordPath ++ ".recordId") (← required recordPath recordFields "recordId")
    let _ ← logicalPath (recordPath ++ ".path") (← required recordPath recordFields "path")
    let kind ← string (recordPath ++ ".recordKind") (← required recordPath recordFields "recordKind")
    let _ ← enum (recordPath ++ ".recordKind") kind
      ["source", "manifest", "pins", "protocol", "ledger"]
  return {
    ref
    productName := ← string (productPath ++ ".name") (← required productPath product "name")
    productVersion := ← string (productPath ++ ".version") (← required productPath product "version")
  }

private def decodeEvidence (visibility : String) (index : Nat) (json : Json) : DecodeResult EvidenceRef := do
  let path := s!"$.evidenceRefs[{index}]"
  let value ← checkedFields path ["evidenceId", "runRef"] ["evidenceId", "runRef"] json
  let runPath := path ++ ".runRef"
  let run ← checkedFields runPath ["schemaVersion", "runId", "envelopeSha256", "projectionKind"]
    ["schemaVersion", "runId", "envelopeSha256", "projectionKind"] (← required path value "runRef")
  let schema ← string (runPath ++ ".schemaVersion") (← required runPath run "schemaVersion")
  let projection ← string (runPath ++ ".projectionKind") (← required runPath run "projectionKind")
  let validPair := (schema == "mirrors.evidence-envelope/v1.0" && projection == "private") ||
    (schema == "mirrors.evidence-public-summary/v1.0" && projection == "public")
  if !validPair then fail "E-FCAT-REFERENCE-001" runPath "runRef schema/projection pair is invalid"
  if visibility == "public" && projection != "public" then
    fail "E-FCAT-REFERENCE-001" runPath "public catalog must reference public evidence projection"
  let _ ← identifier (runPath ++ ".runId") (← required runPath run "runId")
  let _ ← digest (runPath ++ ".envelopeSha256") (← required runPath run "envelopeSha256")
  return {
    evidenceId := ← identifier (path ++ ".evidenceId") (← required path value "evidenceId")
    schemaVersion := schema
    runId := ← identifier (runPath ++ ".runId") (← required runPath run "runId")
    envelopeSha256 := ← digest (runPath ++ ".envelopeSha256") (← required runPath run "envelopeSha256")
    projectionKind := projection
  }

private def decodeConstraint (path : String) (json : Json) : DecodeResult Constraint := do
  let value ← checkedFields path ["constraintId", "fact", "operator", "values"]
    ["constraintId", "fact", "operator", "values"] json
  let factPath := path ++ ".fact"
  let fact ← checkedFields factPath ["kind", "id"] ["kind", "id"] (← required path value "fact")
  let kind ← string (factPath ++ ".kind") (← required factPath fact "kind")
  let _ ← enum (factPath ++ ".kind") kind
    ["platformField", "componentVersion", "dependencyVersion", "capabilitySelected"]
  let factId ← identifier (factPath ++ ".id") (← required factPath fact "id")
  if kind == "platformField" then
    let _ ← enum (factPath ++ ".id") factId ["os", "osRelease", "architecture", "backend"]
  let operator ← string (path ++ ".operator") (← required path value "operator")
  let _ ← enum (path ++ ".operator") operator ["equals", "oneOf", "atLeastSemver"]
  let values ← stringArray (path ++ ".values") (← required path value "values")
  if values.isEmpty || ((operator == "equals" || operator == "atLeastSemver") && values.length != 1) then
    fail "E-FCAT-CONTRADICTION-001" (path ++ ".values") "constraint values do not match operator arity"
  let _ ← requireSortedUnique (path ++ ".values") "constraint values" values
  if operator == "atLeastSemver" && !values.all validCoreSemver then
    fail "E-FCAT-SCHEMA-001" (path ++ ".values") "atLeastSemver requires MAJOR.MINOR.PATCH without leading zeros"
  return {
    constraintId := ← identifier (path ++ ".constraintId") (← required path value "constraintId")
    factKind := kind
    factId
    operator
    values
  }

private def decodeObservation (path dimension : String) (json : Json) : DecodeResult Observation := do
  let value ← checkedFields path ["state", "evidenceId"] ["state"] json
  let state ← string (path ++ ".state") (← required path value "state")
  let _ ← enum (path ++ ".state") state ["accepted", "rejected", "unavailable", "notRun", "unknown"]
  let evidenceId ← optionalIdentifier (path ++ ".evidenceId") (optional value "evidenceId")
  return {
    dimension
    state
    evidenceId
  }

private def decodeCapability (index : Nat) (json : Json) : DecodeResult Capability := do
  let path := s!"$.capabilities[{index}]"
  let value ← checkedFields path
    ["capabilityId", "ownerComponentId", "description", "declaration", "sourceImplementation", "observations"]
    ["capabilityId", "ownerComponentId", "description", "declaration", "sourceImplementation", "observations"] json
  let _ ← string (path ++ ".description") (← required path value "description")
  let declarationPath := path ++ ".declaration"
  let declaration ← checkedFields declarationPath ["state", "constraints"] ["state", "constraints"]
    (← required path value "declaration")
  let declarationState ← string (declarationPath ++ ".state") (← required declarationPath declaration "state")
  let _ ← enum (declarationPath ++ ".state") declarationState ["available", "experimental", "unavailable"]
  let constraintJson ← array (declarationPath ++ ".constraints") (← required declarationPath declaration "constraints")
  let constraints ← constraintJson.zipIdx.mapM fun (item, itemIndex) =>
    decodeConstraint s!"{declarationPath}.constraints[{itemIndex}]" item
  if constraints.mergeSort (fun left right => keyLe left.constraintId right.constraintId) != constraints then
    fail "E-FCAT-CONTRADICTION-001" (declarationPath ++ ".constraints")
      "constraints must be sorted by constraintId UTF-8 bytes"
  let sourcePath := path ++ ".sourceImplementation"
  let source ← checkedFields sourcePath ["state", "locations"] ["state", "locations"]
    (← required path value "sourceImplementation")
  let sourceState ← string (sourcePath ++ ".state") (← required sourcePath source "state")
  let _ ← enum (sourcePath ++ ".state") sourceState ["present", "absent", "unknown"]
  let locations ← array (sourcePath ++ ".locations") (← required sourcePath source "locations")
  for (location, locationIndex) in locations.zipIdx do
    let locationPath := s!"{sourcePath}.locations[{locationIndex}]"
    let locationFields ← checkedFields locationPath ["path", "symbol"] ["path"] location
    let _ ← logicalPath (locationPath ++ ".path") (← required locationPath locationFields "path")
    match optional locationFields "symbol" with
    | some symbol => let _ ← string (locationPath ++ ".symbol") symbol
    | none => pure ()
  if sourceState == "present" && locations.isEmpty then
    fail "E-FCAT-STATE-001" sourcePath "present source implementation requires a location"
  if sourceState != "present" && !locations.isEmpty then
    fail "E-FCAT-STATE-001" sourcePath "absent or unknown source implementation cannot carry locations"
  let observationsPath := path ++ ".observations"
  let dimensions := ["sourceTested", "locallyAccepted", "installedConsumerAccepted", "hostedCiAccepted", "published"]
  let observationsFields ← checkedFields observationsPath dimensions dimensions (← required path value "observations")
  let observations ← dimensions.mapM fun dimension => do
    decodeObservation (observationsPath ++ "." ++ dimension) dimension
      (← required observationsPath observationsFields dimension)
  return {
    capabilityId := ← identifier (path ++ ".capabilityId") (← required path value "capabilityId")
    ownerComponentId := ← identifier (path ++ ".ownerComponentId") (← required path value "ownerComponentId")
    declarationState
    sourceState
    constraints
    observations
  }

private def decodePlatform (path : String) (json : Json) : DecodeResult Platform := do
  let value ← checkedFields path ["os", "osRelease", "architecture", "backend"]
    ["os", "osRelease", "architecture"] json
  let backend ← optionalString (path ++ ".backend") (optional value "backend")
  return {
    os := ← string (path ++ ".os") (← required path value "os")
    osRelease := ← string (path ++ ".osRelease") (← required path value "osRelease")
    architecture := ← string (path ++ ".architecture") (← required path value "architecture")
    backend
  }

private def decodeDependency (path : String) (json : Json) : DecodeResult Dependency := do
  let value ← checkedFields path ["dependencyId", "version", "class"] ["dependencyId", "class"] json
  let className ← string (path ++ ".class") (← required path value "class")
  let _ ← enum (path ++ ".class") className
    ["bundled-artifact", "content-addressed-runtime-tree", "operator-host-prerequisite"]
  let version ← optionalString (path ++ ".version") (optional value "version")
  return {
    dependencyId := ← identifier (path ++ ".dependencyId") (← required path value "dependencyId")
    version
    className
  }

private def decodeProfile (index : Nat) (json : Json) : DecodeResult DistributionProfile := do
  let path := s!"$.distributionProfiles[{index}]"
  let value ← checkedFields path
    ["profileId", "platform", "requiredCapabilityIds", "optionalCapabilityIds", "requiredObservationDimensions", "dependencies"]
    ["profileId", "platform", "requiredCapabilityIds", "optionalCapabilityIds", "requiredObservationDimensions", "dependencies"] json
  let dependenciesJson ← array (path ++ ".dependencies") (← required path value "dependencies")
  let dimensions ← stringArray (path ++ ".requiredObservationDimensions")
    (← required path value "requiredObservationDimensions")
  for (dimension, dimensionIndex) in dimensions.zipIdx do
    let _ ← enum s!"{path}.requiredObservationDimensions[{dimensionIndex}]" dimension
      ["sourceTested", "locallyAccepted", "installedConsumerAccepted", "hostedCiAccepted", "published"]
  return {
    profileId := ← identifier (path ++ ".profileId") (← required path value "profileId")
    platform := ← decodePlatform (path ++ ".platform") (← required path value "platform")
    requiredCapabilityIds := ← idArray (path ++ ".requiredCapabilityIds") (← required path value "requiredCapabilityIds")
    optionalCapabilityIds := ← idArray (path ++ ".optionalCapabilityIds") (← required path value "optionalCapabilityIds")
    requiredObservationDimensions := dimensions
    dependencies := ← dependenciesJson.zipIdx.mapM fun (item, itemIndex) =>
      decodeDependency s!"{path}.dependencies[{itemIndex}]" item
  }

private def decodeCombination (index : Nat) (json : Json) : DecodeResult Combination := do
  let path := s!"$.combinations[{index}]"
  let value ← checkedFields path
    ["combinationId", "componentIds", "platform", "capabilityIds", "distributionProfileIds", "declaredState", "evidenceIds"]
    ["combinationId", "componentIds", "platform", "capabilityIds", "distributionProfileIds", "declaredState", "evidenceIds"] json
  let declaredState ← string (path ++ ".declaredState") (← required path value "declaredState")
  let _ ← enum (path ++ ".declaredState") declaredState ["candidate", "supported", "unsupported"]
  return {
    combinationId := ← identifier (path ++ ".combinationId") (← required path value "combinationId")
    componentIds := ← idArray (path ++ ".componentIds") (← required path value "componentIds")
    platform := ← decodePlatform (path ++ ".platform") (← required path value "platform")
    capabilityIds := ← idArray (path ++ ".capabilityIds") (← required path value "capabilityIds")
    distributionProfileIds := ← idArray (path ++ ".distributionProfileIds")
      (← required path value "distributionProfileIds")
    declaredState
    evidenceIds := ← idArray (path ++ ".evidenceIds") (← required path value "evidenceIds")
  }

private def hexDigit (value : Nat) : Char :=
  if value < 10 then Char.ofNat ('0'.toNat + value)
  else Char.ofNat ('a'.toNat + value - 10)

private def escapeChar (char : Char) : String :=
  if char == '"' then "\\\""
  else if char == '\\' then "\\\\"
  else if char.toNat < 0x20 then
    String.ofList ['\\', 'u', '0', '0', hexDigit (char.toNat / 16), hexDigit (char.toNat % 16)]
  else String.singleton char

private def quote (value : String) : String :=
  "\"" ++ String.join (value.toList.map escapeChar) ++ "\""

partial def canonicalize : Json → Except String String
  | .null => .ok "null"
  | .bool value => .ok (if value then "true" else "false")
  | .str value => .ok (quote value)
  | .num ⟨mantissa, exponent⟩ =>
      if exponent != 0 then .error "canonical catalog JSON rejects fractional or exponent numbers"
      else if mantissa < -9007199254740991 || mantissa > 9007199254740991 then
        .error "canonical catalog JSON integer exceeds signed safe range"
      else .ok mantissa.repr
  | .arr values => do
      let rendered ← values.toList.mapM canonicalize
      return "[" ++ String.intercalate "," rendered ++ "]"
  | .obj value => do
      let sorted := value.toList.mergeSort fun left right => keyLe left.1 right.1
      let rendered ← sorted.mapM fun (key, item) => do
        return quote key ++ ":" ++ (← canonicalize item)
      return "{" ++ String.intercalate "," rendered ++ "}"

private def decodeJson (json : Json) : DecodeResult Catalog := do
  let root ← checkedFields "$"
    ["schemaVersion", "catalogId", "visibility", "components", "evidenceRefs", "capabilities", "distributionProfiles", "combinations", "extensions"]
    ["schemaVersion", "catalogId", "visibility", "components", "evidenceRefs", "capabilities", "distributionProfiles", "combinations"] json
  let schema ← string "$.schemaVersion" (← required "$" root "schemaVersion")
  if schema != schemaV1 then
    fail "E-FCAT-SCHEMA-001" "$.schemaVersion" s!"unsupported catalog schema: {schema}"
  let visibility ← string "$.visibility" (← required "$" root "visibility")
  let _ ← enum "$.visibility" visibility ["public", "private"]
  match optional root "extensions" with
  | some (.obj extensionFields) =>
      for (name, _) in extensionFields.toList do
        if !validExtensionName name then
          fail "E-FCAT-SCHEMA-001" ("$.extensions." ++ name)
            "extension key must be a reverse-DNS name"
  | some _ => fail "E-FCAT-SCHEMA-001" "$.extensions" "object expected"
  | none => pure ()
  let componentJson ← boundedArray "$.components" 64 (← required "$" root "components")
  let evidenceJson ← boundedArray "$.evidenceRefs" 4096 (← required "$" root "evidenceRefs")
  let capabilityJson ← boundedArray "$.capabilities" 4096 (← required "$" root "capabilities")
  let profileJson ← boundedArray "$.distributionProfiles" 256 (← required "$" root "distributionProfiles")
  let combinationJson ← boundedArray "$.combinations" 1024 (← required "$" root "combinations")
  return {
    catalogId := ← identifier "$.catalogId" (← required "$" root "catalogId")
    visibility
    components := ← componentJson.zipIdx.mapM fun (item, index) => decodeComponent visibility index item
    evidenceRefs := ← evidenceJson.zipIdx.mapM fun (item, index) => decodeEvidence visibility index item
    capabilities := ← capabilityJson.zipIdx.mapM fun (item, index) => decodeCapability index item
    distributionProfiles := ← profileJson.zipIdx.mapM fun (item, index) => decodeProfile index item
    combinations := ← combinationJson.zipIdx.mapM fun (item, index) => decodeCombination index item
  }

def decodeString (raw : String) : Except (List ValidationError) Decoded := do
  let json ← match Codec.StrictJson.parseString raw { maxBytes := 4 * 1024 * 1024, maxDepth := 32 } with
    | .ok json => .ok json
    | .error strict =>
        let code := if strict.kind == .tooLarge || strict.kind == .tooDeep then
          "E-FCAT-BOUND-001" else if strict.kind == .duplicateKey then
          "E-FCAT-DUPLICATE-001" else "E-FCAT-SCHEMA-001"
        .error [{ code, path := "$", message := toString strict }]
  let catalog ← match decodeJson json with
    | .ok catalog => .ok catalog
    | .error error => .error [error]
  let errors := Core.FrameworkCatalog.validate catalog
  if !errors.isEmpty then .error errors
  let canonical ← match canonicalize json with
    | .ok value => .ok value
    | .error message => .error [{ code := "E-FCAT-SCHEMA-001", path := "$", message }]
  return { catalog, json, canonical }

private def observationState (capability : Capability) (dimension : String) : String :=
  match capability.observations.find? (·.dimension == dimension) with
  | some observation => observation.state
  | none => "unknown"

def renderMarkdown (catalog : Catalog) : String :=
  let componentHeader := [
    "<!-- BEGIN GENERATED FRAMEWORK SUPPORT -->",
    s!"Catalog `{catalog.catalogId}` visibility: **{catalog.visibility}**. Dirty source identities are explicit; this table does not publish packages or assert runtime acceptance.",
    "",
    "| Component | Revision | Dirty |",
    "| --- | --- | --- |"]
  let componentRows := (catalog.components.mergeSort fun left right =>
      left.ref.componentId ≤ right.ref.componentId).map fun component =>
    s!"| `{component.ref.componentId}` | `{component.ref.revision}` | {component.ref.dirty} |"
  let capabilityHeader := [
    "",
    "| Capability | Owner | Declared | Source | Tested | Local | Installed | Hosted CI | Published |",
    "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
  let rows := (catalog.capabilities.mergeSort fun left right =>
      left.capabilityId ≤ right.capabilityId).map fun capability =>
    s!"| `{capability.capabilityId}` | `{capability.ownerComponentId}` | {capability.declarationState} | {capability.sourceState} | {observationState capability "sourceTested"} | {observationState capability "locallyAccepted"} | {observationState capability "installedConsumerAccepted"} | {observationState capability "hostedCiAccepted"} | {observationState capability "published"} |"
  String.intercalate "\n" (componentHeader ++ componentRows ++ capabilityHeader ++ rows ++
    ["<!-- END GENERATED FRAMEWORK SUPPORT -->", ""])

/-! ## Existing owner-record adapters

These adapters produce the same domain types consumed by catalog validation.
They do not select a combination or attach evidence. -/

private def unknownObservations : List Observation :=
  ["sourceTested", "locallyAccepted", "installedConsumerAccepted", "hostedCiAccepted", "published"].map
    fun dimension => { dimension, state := "unknown" }

private def adaptedCapability (owner id state : String) : Capability :=
  { capabilityId := id, ownerComponentId := owner, declarationState := state,
    sourceState := "unknown", constraints := [], observations := unknownObservations }

private def natArray (path : String) (json : Json) : DecodeResult (List Nat) := do
  let values ← array path json
  values.zipIdx.mapM fun (value, index) => match value with
    | .num ⟨mantissa, 0⟩ =>
        if 0 ≤ mantissa then .ok mantissa.toNat
        else fail "E-FCAT-SCHEMA-001" s!"{path}[{index}]" "nonnegative integer expected"
    | _ => fail "E-FCAT-SCHEMA-001" s!"{path}[{index}]" "nonnegative integer expected"

def adaptGateCompatibility (raw : String) (ownerComponentId : String := "mirrorgate") :
    Except (List ValidationError) (List Capability) := do
  let json ← match Codec.StrictJson.parseString raw { maxBytes := 262144, maxDepth := 16 } with
    | .ok json => .ok json
    | .error problem => .error [{ code := "E-FCAT-SCHEMA-001", path := "$", message := toString problem }]
  let adapted ← match (do
      let value ← checkedFields "$"
        ["schema", "status", "sdkVersion", "controlVersions", "workerVersions", "backend",
         "controller", "nativeClients", "nativeClientControlVersions", "workerRuntimes", "buildTools",
         "capabilityNegotiationRequired", "ownedProcessCloseReceipt", "productionPublication",
         "recovery", "aggregateQuota",
         "modelFacadeAcceptance", "modelFacadeEvidenceLedger", "rustEvaluatorEvidenceLedger",
         "rustEvaluatorTargetProfile", "rustGeneratedApplicationTarget"]
        ["schema", "controlVersions", "workerVersions", "backend", "workerRuntimes",
         "productionPublication", "rustGeneratedApplicationTarget"] json
      let schema ← string "$.schema" (← required "$" value "schema")
      if schema != "mirrorgate.sdk-compatibility/v1" then
        fail "E-FCAT-SCHEMA-001" "$.schema" s!"unsupported Gate compatibility schema: {schema}"
      let backend ← string "$.backend" (← required "$" value "backend")
      let controls ← natArray "$.controlVersions" (← required "$" value "controlVersions")
      let workers ← natArray "$.workerVersions" (← required "$" value "workerVersions")
      let runtimes ← stringArray "$.workerRuntimes" (← required "$" value "workerRuntimes")
      let published ← boolean "$.productionPublication" (← required "$" value "productionPublication")
      let generatedRust ← boolean "$.rustGeneratedApplicationTarget"
        (← required "$" value "rustGeneratedApplicationTarget")
      let mut capabilities := [adaptedCapability ownerComponentId
        ("mirrorgate.backend." ++ backend) "experimental"]
      for version in controls do capabilities := capabilities ++
        [adaptedCapability ownerComponentId s!"mirrorgate.control.v{version}" "experimental"]
      for version in workers do capabilities := capabilities ++
        [adaptedCapability ownerComponentId s!"mirrorgate.worker.v{version}" "experimental"]
      for runtime in runtimes do capabilities := capabilities ++
        [adaptedCapability ownerComponentId ("mirrorgate.runtime." ++ runtime) "experimental"]
      capabilities := capabilities ++ [adaptedCapability ownerComponentId
        "mirrorgate.generated-application.mirrorrust-v1"
        (if generatedRust then "experimental" else "unavailable")]
      capabilities := capabilities ++ [adaptedCapability ownerComponentId
        "mirrorgate.production-publication" (if published then "available" else "unavailable")]
      return capabilities : DecodeResult (List Capability)) with
    | .ok capabilities => .ok capabilities
    | .error problem => .error [problem]
  return adapted

private def validPinName (value : String) : Bool :=
  !value.isEmpty && value.toList.all fun char =>
    ('A' ≤ char && char ≤ 'Z') || ('0' ≤ char && char ≤ '9') || char == '_'

def adaptVersionPins (raw : String) : Except (List ValidationError) (List Dependency) := do
  let mut dependencies : List Dependency := []
  for (line, index) in raw.splitOn "\n" |>.zipIdx do
    let line := line.trimAscii.toString
    if !line.isEmpty && !line.startsWith "#" then
      match line.splitOn "=" with
      | [name, value] =>
          if !validPinName name || value.isEmpty then
            throw [ValidationError.mk "E-FCAT-SCHEMA-001" s!"line[{index}]"
              "pin must be uppercase NAME=VALUE"]
          if dependencies.any (·.dependencyId == name) then
            throw [ValidationError.mk "E-FCAT-DUPLICATE-001" s!"line[{index}]"
              s!"duplicate pin: {name}"]
          dependencies := dependencies ++ [Dependency.mk name (some value)
            "operator-host-prerequisite"]
      | _ => throw [ValidationError.mk "E-FCAT-SCHEMA-001" s!"line[{index}]"
          "pin must contain exactly one '='"]
  return dependencies

end Codec.FrameworkCatalog
