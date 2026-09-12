import Codec.ModelInterfaceJson
import Codec.ModelInterfaceScaffoldJson
import Shell.ModelInterface.Compiler
import Shell.Tla.Frontend

/-!
# Unified TLA+ frontend integration gate (`tools/TlaFrontendSpec.lean`)

Drives the TF6 slice of `Docs/model-interface-compiler/tla-frontend-tasks.md`:
one frontend analysis supplies `scaffold`, `project-trace`, `resolve`, and
`check`; effective source variables must equal raw evidence variables before any
projection; source-only diagnostics keep their declaration origins while
evidence-only diagnostics invent none; and a dependency edit invalidates the
published lock.

The composed model mirrors the DumpLedgerTransfer shape: twelve variables
inherited through `EXTENDS` plus seven local variables, with `action_taken`
carried as the inherited action variable.
-/

namespace TlaFrontendSpec

open Core.ModelInterface
open Core.Tla
open Shell.Tla

abbrev Failures := IO.Ref (List String)

private def check (failures : Failures) (name : String) (condition : Bool)
    (detail : String := "") : IO Unit := do
  if !condition then
    failures.modify fun values =>
      values ++ [if detail.isEmpty then name else s!"{name}: {detail}"]

private def frontendDetail (failure : FrontendFailure) : String :=
  String.intercalate "; " (failure.diagnostics.toList.map (fun diagnostic =>
    s!"{diagnostic.code}: {diagnostic.message}"))

/-- The repository root, found from the current directory by the build file. -/
private def repositoryRoot? (start : System.FilePath) : IO (Option System.FilePath) :=
  go start 8
where
  go (directory : System.FilePath) : Nat → IO (Option System.FilePath)
    | 0 => pure none
    | fuel + 1 => do
        if ← (directory / "lakefile.lean").pathExists then
          return some directory
        else
          match directory.parent with
          | some parent => go parent fuel
          | none => pure none

/-! ## Composed source model -/

private def baseName : String := "FrontendBase"

private def transferName : String := "FrontendTransfer"

private def actionName : String := actionVariableV1

private def baseVariables : List String :=
  ["baseRecords", "baseCursor", "baseLimit", "targetRecords", "targetCursor",
   "targetLimit", "transferJournal", "transferCursor", "auditTrail",
   "auditCursor", "batchBuffer", actionName]

private def transferVariables : List String :=
  ["activeBatch", "batchStage", "stagedKey", "stagedValue", "retryCount",
   "commitPending", "verifyPending"]

private def transferNames : List String := baseVariables ++ transferVariables

private def declarationLines (names : List String) : List String :=
  names.mapIdx fun index name =>
    if index + 1 == names.length then "  " ++ name else "  " ++ name ++ ","

private def moduleSource (name parent : String) (variables : List String) : String :=
  String.intercalate "\n"
    (["---- MODULE " ++ name ++ " ----", "", "EXTENDS " ++ parent, "",
      "VARIABLES"] ++ declarationLines variables ++ ["", "====", ""])

private def baseSource : String := moduleSource baseName "Integers" baseVariables

private def transferSource : String :=
  moduleSource transferName baseName transferVariables

/-! ## Scenario: inline composed closure -/

private def scenarioInlineClosure (failures : Failures) : IO Unit := do
  let provider := SourceProvider.inline #[
    ({ name := baseName }, baseSource),
    ({ name := transferName }, transferSource)]
  match ← analyze provider { root := ModuleRef.ofModuleName { name := transferName } } with
  | .error failure =>
      check failures "inline closure analyzes" false (frontendDetail failure)
  | .ok result =>
      check failures "inline closure root identity" (result.root.name == transferName)
      check failures "inline closure effective variables"
        (result.variableNames == transferNames)
      let entries := result.variables.toList
      check failures "inline closure declaration origins"
        (entries.all fun entry =>
          entry.declaredIn.name ==
            (if baseVariables.contains entry.visibleName then baseName else transferName))
      check failures "inline closure import paths"
        (entries.all fun entry =>
          entry.importPath.toList.map (fun name => name.name) ==
            (if entry.declaredIn.name == transferName then [transferName]
             else [transferName, entry.declaredIn.name]))
      check failures "inline closure manifest names"
        (result.sourceManifest.toList.map (fun identity => identity.logicalPath) ==
          [baseName ++ ".tla", transferName ++ ".tla"])
      check failures "inline closure standard catalog"
        (result.graph.standardNames.toList.map (fun name => name.name) == ["Integers"])

/-! ## Scenario: borrowed corpus closure -/

private def corpusTransferPath : List String :=
  ["test", "fixtures", "tla-frontend", "accepted", "generic-transfer",
   "GenericTransfer.tla"]

private def corpusFrozenDigests : List (String × String) :=
  [("GenericBase.tla",
     "598658048e6cc96595a0b112a552ded0f29cfd24734919c201c732e8c8c360bf"),
   ("GenericTransfer.tla",
     "5f284dc2223c39c667e060a2340d44007154bb9a5b8c2f2f683bc4314df4cd27")]

private def scenarioBorrowedCorpus (failures : Failures) (root : System.FilePath) :
    IO Unit := do
  let relative := corpusTransferPath.foldl (fun path segment => path ++ "/" ++ segment) ""
  let specPath := root.toString ++ relative
  match ← analyzeFile { specPath := specPath } with
  | .error failure =>
      check failures "borrowed corpus analyzes" false (frontendDetail failure)
  | .ok result =>
      check failures "borrowed corpus: nineteen effective variables"
        (result.variableNames.length == 19)
      check failures "borrowed corpus: twelve inherited variables"
        ((result.variables.toList.filter fun entry => entry.declaredIn.name == "GenericBase").length == 12)
      check failures "borrowed corpus: seven local variables"
        ((result.variables.toList.filter fun entry => entry.declaredIn.name == "GenericTransfer").length == 7)
      check failures "borrowed corpus: declaration ranges are one-based"
        (result.variables.toList.all fun entry => entry.declarationRange.start.line > 0)
      check failures "borrowed corpus: manifest matches the frozen corpus digests"
        (result.sourceManifest.toList.map (fun identity =>
            (identity.logicalPath, identity.contentSha256)) == corpusFrozenDigests)

/-! ## Scenario: borrowed root file names and capture classification -/

private def scenarioRootNames (failures : Failures) : IO Unit := do
  let root ← IO.FS.createTempDir
  try
    let spec := root / "RBT-stale.tla"
    IO.FS.writeFile spec "---- MODULE WeirdRoot ----\nVARIABLES lone\n====\n"
    match ← analyzeFile { specPath := spec.toString } with
    | .error failure =>
        check failures "root file name may differ from the module name" false
          (frontendDetail failure)
    | .ok result =>
        check failures "root file name discovery" (result.root.name == "WeirdRoot")
        check failures "root logical path stays the file name"
          ((result.logicalPath? result.root).getD "" == "RBT-stale.tla")
    match ← analyzeFile { specPath := (root / "Missing.tla").toString } with
    | .error failure =>
        check failures "missing root is a capture failure" failure.rootCaptureFailed
    | .ok _ =>
        check failures "missing root is a capture failure" false
    let malformed := root / "Malformed.tla"
    IO.FS.writeFile malformed "VARIABLES lone\n"
    match ← analyzeFile { specPath := malformed.toString } with
    | .error failure =>
        check failures "malformed root is a finding" (!failure.rootCaptureFailed)
    | .ok _ =>
        check failures "malformed root is a finding" false
  finally
    IO.FS.removeDirAll root

/-! ## Scenario: evidence admission -/

private def scenarioEvidenceAdmission (failures : Failures)
    (root : System.FilePath) : IO Unit := do
  let relative := corpusTransferPath.foldl (fun path segment => path ++ "/" ++ segment) ""
  match ← analyzeFile { specPath := root.toString ++ relative } with
  | .error failure =>
      check failures "admission baseline analyzes" false (frontendDetail failure)
  | .ok result =>
      let names := result.variableNames
      check failures "admission: exact effective set accepted"
        ((admitEvidence result names).isOk)
      match admitEvidence result (names ++ ["fabricatedState"]) with
      | .error (.mismatch sourceOnly evidenceOnly) =>
          check failures "admission: fabricated evidence is evidence-only"
            (sourceOnly.isEmpty && evidenceOnly.toList == ["fabricatedState"])
      | _ =>
          check failures "admission: fabricated evidence is evidence-only" false
      match admitEvidence result (names.drop 1) with
      | .error (.mismatch sourceOnly evidenceOnly) =>
          check failures "admission: source-only keeps its declaration origin"
            (evidenceOnly.isEmpty && sourceOnly.size == 1 &&
              sourceOnly.toList.head?.map (fun entry => entry.declaredIn.name) ==
                some "GenericBase")
      | _ =>
          check failures "admission: source-only keeps its declaration origin" false
      check failures "admission: duplicated evidence name is rejected"
        (match admitEvidence result (names ++ ["sourceRecords"]) with
         | .error (.duplicateEvidence name) => name == "sourceRecords"
         | _ => false)

/-! ## Scenario: compiler integration through the CLI -/

private def invokeScaffold (spec evidence proposal : System.FilePath) :
    IO IO.Process.Output :=
  IO.Process.output {
    cmd := ".lake/build/bin/model_interface_gen"
    args := #["scaffold", "--spec", spec.toString, "--evidence", evidence.toString,
      "--proposal", proposal.toString, "--diagnostics", "json"]
  }

private def invokeResolve (spec contract evidence lock : System.FilePath) :
    IO IO.Process.Output :=
  IO.Process.output {
    cmd := ".lake/build/bin/model_interface_gen"
    args := #["resolve", "--spec", spec.toString, "--contract", contract.toString,
      "--evidence", evidence.toString, "--lock", lock.toString,
      "--diagnostics", "json"]
  }

private def invokeGenerate (lock out : System.FilePath) : IO IO.Process.Output :=
  IO.Process.output {
    cmd := ".lake/build/bin/model_interface_gen"
    args := #["generate", "--lock", lock.toString, "--target", "mirrorecma-v1",
      "--out", out.toString, "--diagnostics", "json"]
  }

private def invokeCheck (spec contract evidence lock out : System.FilePath) :
    IO IO.Process.Output :=
  IO.Process.output {
    cmd := ".lake/build/bin/model_interface_gen"
    args := #["check", "--spec", spec.toString, "--contract", contract.toString,
      "--evidence", evidence.toString, "--lock", lock.toString,
      "--target", "mirrorecma-v1", "--out", out.toString,
      "--diagnostics", "json"]
  }

private def evidenceJson (variables : List String) : String :=
  let varTypes := String.intercalate ","
    (variables.map fun name =>
      s!"\"{name}\":\"{if name == actionName then "Str" else "Int"}\"")
  let vars := String.intercalate "," (variables.map fun name => s!"\"{name}\"")
  let state (index : Nat) (action : String) : String :=
    let values := variables.map fun name =>
      if name == actionName then s!"\"{name}\":\"{action}\""
      else "\"" ++ name ++ "\":{\"#bigint\":\"0\"}"
    "{\"#meta\":{\"index\":" ++ toString index ++ "}," ++
      String.intercalate "," values ++ "}"
  "{\"#meta\":{\"format\":\"ITF\",\"varTypes\":{" ++ varTypes ++ "}}," ++
    "\"vars\":[" ++ vars ++ "]," ++
    "\"states\":[" ++ state 0 "init" ++ "," ++ state 1 "step" ++ "]}"

private def upperCamel (name : String) : String :=
  match name.toList with
  | [] => ""
  | first :: rest => String.ofList (Char.toUpper first :: rest)

private def genericContract : ContractV1 := {
  schema := contractSchemaV1
  interfaceVersion := "1.0.0"
  model := { moduleName := transferName, source := "specs/" ++ transferName ++ ".tla" }
  wire := { actionVariable := actionName, parameterVariable := none }
  initializers := [{ id := "Initialize", wireAction := "init" }]
  actions := [{ id := "Step", wireAction := "step" }]
  observations := (transferNames.filter fun name => name != actionName).map
    fun name => { id := upperCamel name, wireName := name }
}

private def scenarioCompilerIntegration (failures : Failures) : IO Unit := do
  let root ← IO.FS.createTempDir
  try
    let basePath := root / (baseName ++ ".tla")
    let transferPath := root / (transferName ++ ".tla")
    IO.FS.writeFile basePath baseSource
    IO.FS.writeFile transferPath transferSource
    let evidencePath := root / "transfer.itf.json"
    IO.FS.writeFile evidencePath (evidenceJson transferNames)
    let contractPath := root / (transferName ++ ".mirror-interface.json")
    IO.FS.writeBinFile contractPath
      (Codec.ModelInterfaceJson.canonicalFileBytes
        (Codec.ModelInterfaceJson.encodeContract genericContract))
    let proposalPath := root / "transfer.proposal.json"
    let scaffolded ← invokeScaffold transferPath evidencePath proposalPath
    check failures "scaffold: composed-source evidence is admitted"
      (scaffolded.exitCode == 0) scaffolded.stderr
    if !(← proposalPath.pathExists) then
      check failures "scaffold: proposal is written" false
        (scaffolded.stdout ++ scaffolded.stderr)
    else
      match Codec.ModelInterfaceScaffoldJson.parseProposalBytes
          (← IO.FS.readBinFile proposalPath) with
      | .error error => check failures "scaffold: proposal is strict" false error
      | .ok proposal =>
          check failures "scaffold: proposal names the root module"
            (proposal.source.moduleName == transferName)
          check failures "scaffold: observations cover the inherited variables"
            (proposal.contract.observations.length == 18)
    let fabricatedEvidence := root / "fabricated.itf.json"
    IO.FS.writeFile fabricatedEvidence (evidenceJson (transferNames ++ ["fabricatedState"]))
    let fabricatedProposal := root / "fabricated.proposal.json"
    let fabricated ← invokeScaffold transferPath fabricatedEvidence fabricatedProposal
    check failures "scaffold: a fabricated twentieth evidence variable is rejected"
      (fabricated.exitCode == 1 && fabricated.stderr.contains "fabricatedState")
      fabricated.stderr
    check failures "scaffold: evidence-only diagnostics invent no origin"
      (!(fabricated.stderr.contains "declared in module")) fabricated.stderr
    check failures "scaffold: rejected evidence writes no proposal"
      (!(← fabricatedProposal.pathExists))
    let extraPath := root / "ExtraTransfer.tla"
    IO.FS.writeFile extraPath
      (transferSource.replace "VARIABLES" "VARIABLES\n  extraState,")
    let lockPath := root / "transfer.lock.json"
    let resolved ← invokeResolve transferPath contractPath evidencePath lockPath
    check failures "resolve: composed-source lock is accepted"
      (resolved.exitCode == 0) resolved.stderr
    let rejectedLock := root / "rejected.lock.json"
    let rejected ← invokeResolve extraPath contractPath evidencePath rejectedLock
    check failures "resolve: a source-only mismatch is refused"
      (rejected.exitCode == 1 && rejected.stderr.contains "MIC-S-SOURCE-001" &&
        rejected.stderr.contains "declared in module") rejected.stderr
    check failures "resolve: refused source/evidence writes no lock"
      (!(← rejectedLock.pathExists))
    let evidenceLock := root / "evidence.lock.json"
    let evidenceOnly ← invokeResolve transferPath contractPath fabricatedEvidence evidenceLock
    check failures "resolve: an evidence-only mismatch is refused"
      (evidenceOnly.exitCode == 1 &&
        evidenceOnly.stderr.contains "MIC-S-SOURCE-001" &&
        !(evidenceOnly.stderr.contains "declared in module")) evidenceOnly.stderr
    let out := root / "generated"
    let generated ← invokeGenerate lockPath out
    check failures "generate: composed-source lock emits" (generated.exitCode == 0)
      generated.stderr
    let clean ← invokeCheck transferPath contractPath evidencePath lockPath out
    check failures "check: composed-source lock is clean" (clean.exitCode == 0)
      clean.stderr
    let checkedMismatch ← invokeCheck extraPath contractPath evidencePath lockPath out
    check failures "check: a source/evidence mismatch is refused"
      (checkedMismatch.exitCode == 1 &&
        checkedMismatch.stderr.contains "MIC-S-SOURCE-001") checkedMismatch.stderr
    IO.FS.writeFile basePath ((← IO.FS.readFile basePath) ++ "\\* dependency edit\n")
    let stale ← invokeCheck transferPath contractPath evidencePath lockPath out
    check failures "check: a dependency edit invalidates the captured provenance"
      (stale.exitCode == 1 &&
        (stale.stdout.contains "stale:" || stale.stderr.contains "stale:"))
      (stale.stdout ++ stale.stderr)
  finally
    IO.FS.removeDirAll root

def run : IO UInt32 := do
  let failures ← IO.mkRef ([] : List String)
  match ← repositoryRoot? (System.FilePath.mk ".") with
  | none => check failures "repository root is discoverable" false
  | some root =>
      scenarioInlineClosure failures
      scenarioBorrowedCorpus failures root
      scenarioRootNames failures
      scenarioEvidenceAdmission failures root
      scenarioCompilerIntegration failures
  let found ← failures.get
  if found.isEmpty then
    IO.println "TLA FRONTEND SPEC GREEN"
    return 0
  for failure in found do IO.eprintln s!"FAIL {failure}"
  IO.eprintln s!"{found.length} FAILURES"
  return 1

end TlaFrontendSpec

def main : IO UInt32 := TlaFrontendSpec.run
