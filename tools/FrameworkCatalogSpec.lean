import Codec.FrameworkCatalog
import Shell.FrameworkCatalog
import Lean.Data.Json

namespace FrameworkCatalogSpec

open Core.FrameworkCatalog

abbrev Failures := IO.Ref (List String)

private def check (failures : Failures) (name : String) (condition : Bool)
    (detail : String := "") : IO Unit := do
  if !condition then failures.modify fun values =>
    values ++ [if detail.isEmpty then name else s!"{name}: {detail}"]

private def fixture (name : String) : System.FilePath :=
  System.FilePath.mk "test/fixtures/framework-catalog" / name

private def loadFixture (name : String) : IO (Except (List ValidationError) Codec.FrameworkCatalog.Decoded) := do
  Codec.FrameworkCatalog.decodeString <$> IO.FS.readFile (fixture name)

private def hasError (code path message : String) : List ValidationError → Bool :=
  (·.any fun error => error.code == code && error.path == path && error.message == message)

private def field? (name : String) : Lean.Json → Option Lean.Json
  | .obj fields => List.lookup name fields.toList
  | _ => none

private def stringField? (name : String) (json : Lean.Json) : Option String :=
  match field? name json with | some (.str value) => some value | _ => none

private def isError {ε α : Type} : Except ε α → Bool
  | .error _ => true
  | .ok _ => false

private def validScenarios (failures : Failures) : IO Unit := do
  for name in ["valid-minimal.json", "valid-full.json"] do
    match ← loadFixture name with
    | .ok decoded =>
        check failures (name ++ ": canonical output ends without whitespace")
          (!decoded.canonical.endsWith "\n")
        check failures (name ++ ": canonical output reparses")
          (Lean.Json.parse decoded.canonical).isOk
        check failures (name ++ ": selection digest is lowercase SHA-256")
          (decoded.selectionDigest.length == 64 && decoded.selectionDigest.toList.all fun char =>
            ('0' ≤ char && char ≤ '9') || ('a' ≤ char && char ≤ 'f'))
    | .error errors =>
        check failures (name ++ ": accepted") false (Shell.FrameworkCatalog.formatErrors errors)

private def rejectedScenarios (failures : Failures) : IO Unit := do
  let raw ← IO.FS.readFile (fixture "expected-errors.json")
  match Lean.Json.parse raw with
  | .error message => check failures "expected-errors parses" false message
  | .ok root => match field? "fixtures" root with
    | some (.arr cases) => for item in cases do
        match stringField? "file" item, field? "errors" item with
        | some name, some (.arr expected) =>
            match expected[0]? with
            | some first =>
                match stringField? "code" first, stringField? "path" first,
                    stringField? "message" first with
                | some code, some path, some message =>
                    match ← loadFixture name with
                    | .ok _ => check failures (name ++ ": rejected") false
                    | .error errors =>
                        check failures (name ++ ": exact error")
                          (hasError code path message errors)
                          (Shell.FrameworkCatalog.formatErrors errors)
                | _, _, _ => check failures (name ++ ": expected error shape") false
            | none => check failures (name ++ ": expected error absent") false
        | _, _ => check failures "expected fixture shape" false
    | _ => check failures "expected fixtures array" false

private def canonicalScenarios (failures : Failures) : IO Unit := do
  let raw ← IO.FS.readFile (fixture "canonicalization-vectors.json")
  match Lean.Json.parse raw with
  | .error message => check failures "canonical vectors parse" false message
  | .ok (.obj root) =>
      match List.lookup "vectors" root.toList with
      | some (.arr vectors) =>
          for (vector, index) in vectors.toList.zipIdx do
            match vector with
            | .obj fields =>
                match List.lookup "value" fields.toList, List.lookup "canonical" fields.toList with
                | some value, some (.str expected) =>
                    match Codec.FrameworkCatalog.canonicalize value with
                    | .ok actual =>
                        check failures s!"canonical vector {index}" (actual == expected)
                          s!"expected {expected}, got {actual}"
                    | .error message => check failures s!"canonical vector {index}" false message
                | _, _ => check failures s!"canonical vector {index} shape" false
            | _ => check failures s!"canonical vector {index} object" false
      | _ => check failures "canonical vectors array" false
  | .ok _ => check failures "canonical vectors root" false

private def strictScenarios (failures : Failures) : IO Unit := do
  let duplicate := "{\"schemaVersion\":\"mirrors.framework-catalog/v1\",\"catalogId\":\"a\",\"catalogId\":\"b\"}"
  match Codec.FrameworkCatalog.decodeString duplicate with
  | .ok _ => check failures "duplicate raw key rejected" false
  | .error errors =>
      let correct := errors.any (·.code == "E-FCAT-DUPLICATE-001")
      check failures "duplicate raw key code" correct

  let full ← IO.FS.readFile (fixture "valid-full.json")
  let malformedRun := full.replace
    "\"projectionKind\": \"public\"" "\"projectionKind\": \"private\""
  check failures "nested runRef schema/projection rejected"
    (isError (Codec.FrameworkCatalog.decodeString malformedRun))
  let staleDependency := full
    |>.replace "\"declaredState\": \"candidate\"" "\"declaredState\": \"supported\""
    |>.replace "\"version\": \"24.15.0\"" "\"version\": \"23.0.0\""
  match Codec.FrameworkCatalog.decodeString staleDependency with
  | .ok _ => check failures "structured dependency constraint enforced" false
  | .error errors =>
      let correct := errors.any (·.message == "constraint is not satisfied: node-24.15.0")
      check failures "structured dependency constraint code" correct
  let semverConstraint := full
    |>.replace "\"declaredState\": \"candidate\"" "\"declaredState\": \"supported\""
    |>.replace "\"operator\": \"equals\"" "\"operator\": \"atLeastSemver\""
  check failures "atLeastSemver accepts equal version"
    (Codec.FrameworkCatalog.decodeString semverConstraint).isOk
  let oversized := " " ++ String.ofList (List.replicate (4 * 1024 * 1024) ' ') ++ "{}"
  match Codec.FrameworkCatalog.decodeString oversized with
  | .ok _ => check failures "catalog byte bound" false
  | .error errors =>
      let correct := errors.any (·.code == "E-FCAT-BOUND-001")
      check failures "catalog byte bound code" correct

private def adapterScenarios (failures : Failures) : IO Unit := do
  let gate ← IO.FS.readFile (fixture "gate-compatibility-v1.json")
  match Codec.FrameworkCatalog.adaptGateCompatibility gate with
  | .error errors =>
      let detail := Shell.FrameworkCatalog.formatErrors errors
      check failures "Gate compatibility adapter" false detail
  | .ok capabilities =>
      check failures "Gate adapter backend"
        (capabilities.any (·.capabilityId == "mirrorgate.backend.linux-bubblewrap-v1"))
      check failures "Gate adapter preserves unavailable generated Rust"
        (capabilities.any fun capability =>
          capability.capabilityId == "mirrorgate.generated-application.mirrorrust-v1" &&
            capability.declarationState == "unavailable")
  let pins ← IO.FS.readFile (fixture "version-pins.env")
  match Codec.FrameworkCatalog.adaptVersionPins pins with
  | .error errors =>
      let detail := Shell.FrameworkCatalog.formatErrors errors
      check failures "pin adapter" false detail
  | .ok dependencies =>
      check failures "pin adapter values"
        (dependencies.any fun dependency =>
          dependency.dependencyId == "NODE_VERSION" && dependency.version == some "24.15.0")

private def sharedReferenceScenarios (failures : Failures) : IO Unit := do
  let e1Rejected ← IO.FS.readFile "tools/evidence/fixtures/rejected-cases.json"
  check failures "E1 head-only dirty rejection remains shared"
    (e1Rejected.contains "head-only-dirty-identity")
  let minimal ← IO.FS.readFile (fixture "valid-minimal.json")
  let headOnly := minimal
    |>.replace "\"visibility\": \"public\"" "\"visibility\": \"private\""
    |>.replace "\"dirty\": false" "\"dirty\": true"
  match Codec.FrameworkCatalog.decodeString headOnly with
  | .ok _ => check failures "C2 rejects E1 head-only dirty identity" false
  | .error errors =>
      let correct := errors.any fun error =>
        error.path == "$.components[0].componentRef.dirtyContent" &&
          error.message == "dirty component requires dirtyContent"
      check failures "C2/E1 dirty identity parity" correct
  let emptyId := minimal.replace "\"catalogId\": \"fixture-minimal\"" "\"catalogId\": \"\""
  check failures "empty identity rejected"
    (isError (Codec.FrameworkCatalog.decodeString emptyId))

private def renderScenarios (failures : Failures) : IO Unit := do
  match ← loadFixture "valid-full.json" with
  | .error errors =>
      let detail := Shell.FrameworkCatalog.formatErrors errors
      check failures "render fixture" false detail
  | .ok decoded =>
      let root ← IO.FS.createTempDir
      let jsonOut := root / "catalog.json"
      let markdownOut := root / "support.md"
      IO.FS.writeFile markdownOut
        "preserved before\n<!-- BEGIN GENERATED FRAMEWORK SUPPORT -->old<!-- END GENERATED FRAMEWORK SUPPORT -->\npreserved after\n"
      match ← Shell.FrameworkCatalog.render decoded jsonOut markdownOut false with
      | .error message => check failures "render writes" false message
      | .ok _ =>
          let firstJson ← IO.FS.readFile jsonOut
          let firstMarkdown ← IO.FS.readFile markdownOut
          check failures "render preserves Markdown prose"
            (firstMarkdown.startsWith "preserved before\n" && firstMarkdown.endsWith "preserved after\n")
          check failures "render check passes"
            (← Shell.FrameworkCatalog.render decoded jsonOut markdownOut true).isOk
          IO.FS.writeFile jsonOut (firstJson ++ " ")
          check failures "render drift detected"
            (isError (← Shell.FrameworkCatalog.render decoded jsonOut markdownOut true))

private def migratedCatalogScenarios (failures : Failures) : IO Unit := do
  match ← Shell.FrameworkCatalog.load "catalog/framework-catalog.json" with
  | .error errors =>
      check failures "selected catalog validates" false
        (Shell.FrameworkCatalog.formatErrors errors)
  | .ok decoded =>
      check failures "selected catalog remains private candidate"
        (decoded.catalog.visibility == "private" && decoded.catalog.evidenceRefs.isEmpty &&
          decoded.catalog.combinations.all (·.declaredState == "candidate"))
      let rustEmitter := decoded.catalog.capabilities.find?
        (·.capabilityId == "mirrors.compiler.target.mirrorrust-v1")
      check failures "Rust emitter is source-only"
        (match rustEmitter with
        | some capability => capability.sourceState == "present" &&
            capability.observations.all (·.state == "unknown")
        | none => false)
      let gateRust := decoded.catalog.capabilities.find?
        (·.capabilityId == "mirrorgate.generated-application.mirrorrust-v1")
      check failures "Gate generic generated Rust remains unavailable"
        (match gateRust with
        | some capability => capability.declarationState == "unavailable" &&
            capability.sourceState == "absent"
        | none => false)
      check failures "selected generated outputs are current"
        (← Shell.FrameworkCatalog.render decoded "catalog/framework-catalog.compact.json"
          "Docs/framework-map.md" true).isOk
  match ← Shell.FrameworkCatalog.load "catalog/components/mirrors.json" with
  | .error errors =>
      let detail := Shell.FrameworkCatalog.formatErrors errors
      check failures "Mirrors component record validates" false detail
  | .ok component =>
      check failures "Mirrors component record owns only Mirrors facts"
        (component.catalog.components.length == 1 &&
          component.catalog.capabilities.all (·.ownerComponentId == "mirrors"))

def run : IO UInt32 := do
  let failures ← IO.mkRef ([] : List String)
  validScenarios failures
  rejectedScenarios failures
  canonicalScenarios failures
  strictScenarios failures
  adapterScenarios failures
  sharedReferenceScenarios failures
  renderScenarios failures
  migratedCatalogScenarios failures
  let values ← failures.get
  if values.isEmpty then
    IO.println "FRAMEWORK CATALOG SPEC GREEN"
    return 0
  for failure in values do IO.eprintln s!"FAIL {failure}"
  IO.eprintln s!"{values.length} FAILURES"
  return 1

end FrameworkCatalogSpec

def main : IO UInt32 := FrameworkCatalogSpec.run
