import Core.Tla.Elaboration
import Lean.Data.Json
import Lean.Data.Json.Parser
import Shell.Tla.ModuleResolver
import Shell.Tla.SourceProvider

/-!
# TLA+ elaboration specification (`tools/TlaElaborationSpec.lean`)

Conformance suite for the TF4 semantic-elaboration and TF5 `INSTANCE`
slices (`Docs/model-interface-compiler/tla-frontend-design.md`, §13 "Semantic
elaboration", §14 "`EXTENDS` semantics", §15 "`INSTANCE` and substitution",
§16 "Effective model facts", §20 "Diagnostics", and §21 "Resource and security
limits"; task packages TF4 and TF5 in
`Docs/model-interface-compiler/tla-frontend-tasks.md`).

The suite is pure over captured sources: it drives the frozen corpus in
`test/fixtures/tla-frontend/` through the TF3 resolver seam
(`Shell.Tla.resolve` with `Core.Tla.parseUnit`) and elaborates the resolved
graph with `Core.Tla.elaborate`. No network, Apalache, or private model
material is read.

What is checked:

* **Effective variables.** `acc-generic-transfer`,
  `acc-generic-transfer-audit`, `acc-diamond`, and `acc-generic-extends`
  produce exactly the `effectiveVariables` of their frozen summaries:
  declaration order, `declaredIn`, `declaredName`, and `importPath`.
* **The DumpLedger-shaped safety case.** The twelve inherited plus seven local
  variables resolve in full through an evidence probe, and a fabricated
  twentieth evidence name is an unknown-name error even though similarly
  spelled declarations exist elsewhere in the graph.
* **Levels.** `acc-levels` classifies constant, state, action, and temporal
  operators exactly as its summary pins them.
* **`LOCAL` visibility.** `acc-local` retains its local definition, an
  importer cannot see it, and `LOCAL EXTENDS` declarations stay visible in the
  importing module without being re-exported.
* **Instances and substitution.** The named, unnamed, implicit, chained, and
  `LOCAL` instance forms are driven from the corpus and from inline probes:
  substitution keeps the parent symbol in place of the child variable, keeps
  both dependency sources in provenance, re-exports unnamed instances (and the
  instance names they expose) unless `LOCAL` stops it, and composes levels
  through per-site frames. Duplicate, unknown-target, arity, and level
  rejections each carry their own code.
* **Scopes and arity.** `LET` shadowing, bound-name shadowing, `CHOOSE`,
  function binders, comprehension binders, higher-order parameters, and
  arity mismatches behave as §13.1–13.3 specify.
* **The whole corpus.** Every accepted fixture elaborates with no error
  diagnostics and matches its summary's effective variables and sources; every
  rejected fixture fails at the stage recorded in the manifest, and every
  rejection this slice owns also carries the manifest reason.
* **Limits.** Declaration, symbol, and diagnostic count and byte budgets are
  tested at the limit and at limit plus one.
* **Core purity.** `Core/Tla` imports no `Shell` module and only the pure
  SHA-256 codec from `Core.ModelInterface`.

Two commands run it:

* `lake env lean tools/TlaElaborationSpec.lean` — the elaboration check at the
  bottom of the file runs the suite, so a broken assertion fails this command;
* `lake env lean --run tools/TlaElaborationSpec.lean` — the `main` driver the
  build graph may wire as a `lean_exe`.
-/

namespace TlaElaborationSpec

open Lean
open Core.Tla

/-! ## Harness -/

abbrev Failures := IO.Ref (List String)

def check (fails : Failures) (name : String) (ok : Bool)
    (detail : String := "") : IO Unit := do
  if !ok then
    fails.modify fun items =>
      items ++ [if detail.isEmpty then name else s!"{name}: {detail}"]

def mark (fails : Failures) (message : String) : IO Unit :=
  fails.modify fun items => items ++ [message]

/-! ## Captures and providers -/

/-- One module wrapped in its header and terminator. -/
def moduleText (name body : String) : String :=
  "---- MODULE " ++ name ++ " ----\n" ++ body ++ "\n====\n"

def providerConfig (provider : Shell.Tla.SourceProvider) :
    Shell.Tla.ResolverConfig :=
  { provider, parse := Shell.Tla.pureParse Core.Tla.parseUnit }

/-- One resolved-and-elaborated attempt. A resolution failure carries its own
diagnostics and never reaches elaboration. -/
structure Run where
  graph? : Option ResolvedModuleGraph := none
  diagnostics : List Diagnostic := []
  module? : Option ElaboratedModule := none
  deriving BEq

def runProvider (provider : Shell.Tla.SourceProvider) (root : String)
    (limits : ElaborationLimits := {}) : IO Run := do
  match ← Shell.Tla.resolve (providerConfig provider)
      (Shell.Tla.ModuleRef.ofModuleName ⟨root⟩) with
  | .error failure => pure { diagnostics := failure.diagnostics.toList }
  | .ok graph =>
      match elaborate LanguageProfile.default limits graph with
      | .error diagnostics => pure { graph? := some graph, diagnostics }
      | .ok module => pure { graph? := some graph, module? := some module }

def runDirectory (directory root : String)
    (limits : ElaborationLimits := {}) : IO Run :=
  runProvider
    (Shell.Tla.SourceProvider.borrowedDirectory (System.FilePath.mk directory))
    root limits

def runInline (sources : Array (ModuleName × String)) (root : String)
    (limits : ElaborationLimits := {}) : IO Run :=
  runProvider (Shell.Tla.SourceProvider.inline sources) root limits

/-- Structural equality of two elaboration attempts. -/
def sameRun (left right : Run) : Bool :=
  left.graph? == right.graph? && left.diagnostics == right.diagnostics &&
    left.module? == right.module?

def detailOf (run : Run) : String :=
  s!"module?={run.module?.isSome} diagnostics={run.diagnostics.map (fun diagnostic => diagnostic.stage.toString ++ "/" ++ diagnostic.code)}"

/-! ## Corpus access -/

def readCorpusText (root relative : String) : IO (Except String String) := do
  let path := System.FilePath.mk (root ++ "/" ++ relative)
  if ← path.pathExists then
    try
      return .ok (← IO.FS.readFile path)
    catch error =>
      return .error s!"{relative}: {toString error}"
  else
    return .error s!"{relative}: missing corpus file"

def corpusRoot? (start : System.FilePath) : IO (Option System.FilePath) :=
  go start 8
where
  go (directory : System.FilePath) : Nat → IO (Option System.FilePath)
    | 0 => pure none
    | fuel + 1 => do
        let relative := directory.toString ++ "/test/fixtures/tla-frontend"
        let candidate := System.FilePath.mk (relative ++ "/manifest.json")
        if ← candidate.pathExists then
          return some (System.FilePath.mk relative)
        else
          match directory.parent with
          | some parent => go parent fuel
          | none => pure none

/-- The repository root, found by the root build file. -/
def repositoryRoot? (start : System.FilePath) : IO (Option System.FilePath) :=
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

/-! ## JSON decoding -/

def decodeStringField (json : Json) (key : String) : Except String String :=
  json.getObjVal? key >>= Json.getStr?

def decodeOptionalString (json : Json) (key : String) :
    Except String (Option String) :=
  match json.getObjVal? key with
  | .ok .null => .ok none
  | .ok value => (Json.getStr? value).map some
  | .error _ => .ok none

def decodeArrayField (json : Json) (key : String) : Except String (Array Json) :=
  json.getObjVal? key >>= Json.getArr?

def decodeOptionalArrayField (json : Json) (key : String) :
    Except String (Option (Array Json)) :=
  match json.getObjVal? key with
  | .ok value => (Json.getArr? value).map some
  | .error _ => .ok none

def decodeStringArrayField (json : Json) (key : String) :
    Except String (Array String) :=
  decodeArrayField json key >>= fun items => items.mapM Json.getStr?

/-- One `effectiveVariables` row of a frozen structural summary. -/
structure VariableFact where
  name : String
  declaredIn : String
  declaredName : String
  importPath : Array String
  deriving Repr, BEq

def decodeVariableFact (json : Json) : Except String VariableFact := do
  let name ← decodeStringField json "name"
  let declaredIn ← decodeStringField json "declaredIn"
  let declaredName ← decodeStringField json "declaredName"
  let importPath ← decodeStringArrayField json "importPath"
  return { name, declaredIn, declaredName, importPath }

def decodeVariableFacts (json : Json) : Except String (Array VariableFact) :=
  decodeArrayField json "effectiveVariables" >>= fun items =>
    items.mapM decodeVariableFact

/-- One `sources` row of a frozen structural summary. -/
structure SourceFact where
  logicalPath : String
  sha256 : String
  deriving Repr, BEq

def decodeSourceFact (json : Json) : Except String SourceFact := do
  let logicalPath ← decodeStringField json "logicalPath"
  let sha256 ← decodeStringField json "sha256"
  return { logicalPath, sha256 }

def decodeSourceFacts (json : Json) : Except String (Array SourceFact) :=
  decodeArrayField json "sources" >>= fun items => items.mapM decodeSourceFact

/-- The `levels` object of a frozen structural summary as name/level rows in
canonical name order. -/
def decodeLevelFacts (json : Json) : Except String (Array (String × String)) := do
  let levels ← json.getObjVal? "levels"
  let object ← Json.getObj? levels
  let rows ← object.toArray.mapM fun entry => do
    let level ← Json.getStr? entry.2
    return (entry.1, level)
  return rows.qsort fun left right => compare left.1 right.1 == .lt

/-! ## Corpus manifest views -/

structure InlineSourceView where
  logicalName : String
  file : String
  deriving Repr, BEq

structure FixtureView where
  id : String
  kind : String
  stage : String
  reason : String
  provider : String
  root : String
  sourceRoot : String
  summary : String
  files : Array String
  inlineSources : Array InlineSourceView
  deriving Repr, BEq

def decodeInlineSourceView (json : Json) : Except String InlineSourceView := do
  let logicalName ← decodeStringField json "logicalName"
  let file ← decodeStringField json "file"
  return { logicalName, file }

def decodeFixtureView (json : Json) : Except String FixtureView := do
  let id ← decodeStringField json "id"
  let kind ← decodeStringField json "kind"
  if kind != "accepted" && kind != "rejected" then
    throw s!"fixture {id}: unknown outcome {kind}"
  let stage ← decodeStringField json "stage"
  let reason := (← decodeOptionalString json "reason").getD ""
  if kind == "rejected" && reason.isEmpty then
    throw s!"fixture {id}: rejected fixture has no reason"
  let provider ← decodeStringField json "provider"
  let root ← decodeStringField json "root"
  let sourceRoot := (← decodeOptionalString json "sourceRoot").getD ""
  if provider == "borrowed-directory" && sourceRoot.isEmpty then
    throw s!"fixture {id}: borrowed-directory fixture has no sourceRoot"
  let summary := (← decodeOptionalString json "summary").getD ""
  if kind == "accepted" && summary.isEmpty then
    throw s!"fixture {id}: accepted fixture has no summary"
  let files ← decodeStringArrayField json "files"
  let inlineSources ←
    match ← decodeOptionalArrayField json "inlineSourceMap" with
    | some items => items.mapM decodeInlineSourceView
    | none => pure #[]
  if provider == "inline-source-map" && inlineSources.isEmpty then
    throw s!"fixture {id}: inline provider has no source map"
  return { id, kind, stage, reason, provider, root, sourceRoot, summary, files,
           inlineSources }

def decodeFixtureViews (text : String) : Except String (Array FixtureView) := do
  let json ← Json.parse text
  let items ← decodeArrayField json "fixtures"
  let views ← items.mapM decodeFixtureView
  let ids := views.toList.map fun view => view.id
  if ids.eraseDups.length != ids.length then
    throw "duplicate fixture id"
  return views

/-- Resolve and elaborate one manifest fixture. -/
def runFixture (root : String) (view : FixtureView)
    (limits : ElaborationLimits := {}) : IO (Except String Run) := do
  if view.provider == "inline-source-map" then do
    let mut sources : Array (ModuleName × String) := #[]
    for entry in view.inlineSources do
      match ← readCorpusText root entry.file with
      | .ok text => sources := sources.push (⟨entry.logicalName⟩, text)
      | .error message => return .error s!"{view.id}: {message}"
    return .ok (← runInline sources view.root limits)
  else
    return .ok (← runDirectory (root ++ "/" ++ view.sourceRoot) view.root limits)

/-- Read a fixture's frozen structural summary. -/
def summaryOf? (root : String) (view : FixtureView) :
    IO (Except String Json) := do
  match ← readCorpusText root view.summary with
  | .error message => return .error s!"{view.id}: {message}"
  | .ok text =>
      match Json.parse text with
      | .error message => return .error s!"{view.id}: summary parse: {message}"
      | .ok json => return .ok json

/-! ## Summary comparison -/

def moduleVariableFacts (module : ElaboratedModule) : Array VariableFact :=
  module.variables.map fun stateVariable =>
    { name := stateVariable.visibleName
      declaredIn := stateVariable.declaredIn.name
      declaredName := stateVariable.declaredName
      importPath := stateVariable.importPath.map fun name => name.name }

def moduleSourceFacts (module : ElaboratedModule) : Array SourceFact :=
  module.sourceManifest.map fun identity =>
    { logicalPath := identity.logicalPath, sha256 := identity.contentSha256 }

def renderVariableFacts (facts : Array VariableFact) : String :=
  String.intercalate ", " (facts.toList.map fun fact =>
    s!"{fact.name}@{fact.declaredIn}<-{String.intercalate "/" fact.importPath.toList}")

def checkSummaryIdentity (fails : Failures) (id : String) (view : FixtureView)
    (json : Json) : IO Unit := do
  match decodeStringField json "fixture", decodeStringField json "root" with
  | .ok fixture, .ok root =>
      check fails s!"{id}: the summary identifies the fixture"
        (fixture == view.id && root == view.root) s!"{fixture}/{root}"
  | _, _ => mark fails s!"{id}: the summary has no fixture/root field"

def checkSummaryVariables (fails : Failures) (id : String)
    (module : ElaboratedModule) (json : Json) : IO Unit := do
  match decodeVariableFacts json with
  | .error message => mark fails s!"{id}: summary effectiveVariables: {message}"
  | .ok expected =>
      let actual := moduleVariableFacts module
      check fails s!"{id}: effective variables match the summary"
        (actual == expected) (s!"actual={renderVariableFacts actual}")

def checkSummarySources (fails : Failures) (id : String)
    (module : ElaboratedModule) (json : Json) : IO Unit := do
  match decodeSourceFacts json with
  | .error message => mark fails s!"{id}: summary sources: {message}"
  | .ok expected => do
      let actual := moduleSourceFacts module
      check fails s!"{id}: source manifest matches the summary"
        (actual == expected)
        (s!"actual={actual.toList.map fun fact => fact.logicalPath}")

/-! ## Effective variables -/

def variableFixtures : List String :=
  ["acc-generic-transfer", "acc-generic-transfer-audit", "acc-diamond",
   "acc-generic-extends"]

def scenarioEffectiveVariables (fails : Failures) (root : String)
    (views : Array FixtureView) : IO Unit := do
  for id in variableFixtures do
    match views.find? (fun view => view.id == id) with
    | none => mark fails s!"corpus: the manifest has no fixture {id}"
    | some view => do
        match ← runFixture root view with
        | .error message => mark fails message
        | .ok run =>
            match run.module? with
            | none => check fails s!"{id}: elaborates" false (detailOf run)
            | some module => do
                check fails s!"{id}: elaborates the manifest root"
                  (module.moduleName.name == view.root) module.moduleName.name
                match ← summaryOf? root view with
                | .error message => mark fails message
                | .ok json => do
                    checkSummaryIdentity fails id view json
                    checkSummaryVariables fails id module json
                    checkSummarySources fails id module json
                    if id == "acc-generic-transfer" then do
                      let inherited := module.variables.filter fun stateVariable =>
                        stateVariable.declaredIn.name == "GenericBase"
                      let own := module.variables.filter fun stateVariable =>
                        stateVariable.declaredIn.name == "GenericTransfer"
                      check fails
                        "acc-generic-transfer: nineteen effective variables"
                        (module.variables.size == 19) (toString module.variables.size)
                      check fails "acc-generic-transfer: twelve inherited variables"
                        (inherited.size == 12) (toString inherited.size)
                      check fails "acc-generic-transfer: seven local variables"
                        (own.size == 7) (toString own.size)
                      check fails
                        "acc-generic-transfer: inherited declarations keep declaration order"
                        ((module.variables.toList.take 12).all fun stateVariable =>
                          stateVariable.declaredIn.name == "GenericBase")
                        (renderVariableFacts (moduleVariableFacts module))
                      check fails
                        "acc-generic-transfer: every import path starts at the root"
                        (module.variables.all fun stateVariable =>
                          stateVariable.importPath[0]? == some module.moduleName)
                        (renderVariableFacts (moduleVariableFacts module))
                    if id == "acc-generic-transfer-audit" then
                      check fails
                        "acc-generic-transfer-audit: nineteen effective variables through the longer chain"
                        (module.variables.size == 19) (toString module.variables.size)
                    -- Negative self-test: the comparison detects a mutated
                    -- expectation instead of accepting any row set.
                    match decodeVariableFacts json with
                    | .error _ => pure ()
                    | .ok expected =>
                        check fails
                          s!"{id}: a dropped effective-variable row is detected"
                          (expected.size ≥ 2 &&
                            moduleVariableFacts module != expected.pop)
                          ""

/-! ## The DumpLedger-shaped evidence case -/

def scenarioNineteenEvidence (fails : Failures) (root : String) : IO Unit := do
  match ← readCorpusText root "accepted/generic-transfer/GenericBase.tla" with
  | .error message => mark fails s!"evidence: {message}"
  | .ok baseText =>
    match ← readCorpusText root "accepted/generic-transfer/GenericTransfer.tla" with
    | .error message => mark fails s!"evidence: {message}"
    | .ok transferText => do
        let corpus : Array (ModuleName × String) :=
          #[(⟨"GenericBase"⟩, baseText), (⟨"GenericTransfer"⟩, transferText)]
        let run ← runInline corpus "GenericTransfer"
        match run.module? with
        | none =>
            check fails "evidence: the transfer fixture elaborates" false (detailOf run)
        | some module => do
            let names := module.variables.map fun stateVariable => stateVariable.visibleName
            check fails "evidence: nineteen effective variables with distinct names"
              (names.size == 19 && names.toList.eraseDups.length == 19)
              (toString names.size)
            check fails "evidence: the fabricated name is not declared"
              (!names.contains "stagedBlob") ""
            let resolvable := String.intercalate "\n" (names.toList.map fun name =>
              s!"Use{name} == {name}")
            let probes : Array (ModuleName × String) :=
              corpus
                ++ #[(⟨"EvidenceProbe"⟩,
                        moduleText "EvidenceProbe"
                          ("EXTENDS GenericTransfer\n" ++ resolvable)),
                     (⟨"GhostProbe"⟩,
                        moduleText "GhostProbe"
                          "EXTENDS GenericTransfer\nGhost == stagedBlob"),
                     (⟨"TypoProbe"⟩,
                        moduleText "TypoProbe"
                          "EXTENDS GenericTransfer\nTypo == batchCounter")]
            let probe ← runInline probes "EvidenceProbe"
            match probe.module? with
            | none =>
                check fails "evidence: all nineteen names resolve in one module"
                  false (detailOf probe)
            | some probed =>
                check fails "evidence: the probe defines one operator per name"
                  ((probed.operators.filter fun operator =>
                      operator.declaredIn.name == "EvidenceProbe").size == 19)
                  (toString probed.operators.size)
            let ghost ← runInline probes "GhostProbe"
            check fails
              "evidence: the fabricated twentieth name has no declaration"
              (ghost.module?.isNone &&
                ghost.diagnostics.any (fun diagnostic =>
                  diagnostic.code == ElabCode.unknownName &&
                    diagnostic.stage == .nameResolution &&
                    diagnostic.arguments.any (fun argument =>
                      argument.1 == "name" && argument.2 == "stagedBlob")))
              (detailOf ghost)
            let typo ← runInline probes "TypoProbe"
            check fails
              "evidence: a similar spelling elsewhere in the graph is no fallback"
              (typo.module?.isNone &&
                typo.diagnostics.any (fun diagnostic =>
                  diagnostic.code == ElabCode.unknownName &&
                    diagnostic.arguments.any (fun argument =>
                      argument.1 == "name" && argument.2 == "batchCounter")))
              (detailOf typo)

/-! ## Operator levels -/

def scenarioLevels (fails : Failures) (root : String)
    (views : Array FixtureView) : IO Unit := do
  match views.find? (fun view => view.id == "acc-levels") with
  | none => mark fails "corpus: the manifest has no fixture acc-levels"
  | some view =>
      match ← runFixture root view with
      | .error message => mark fails message
      | .ok run =>
          match run.module? with
          | none => check fails "acc-levels: elaborates" false (detailOf run)
          | some module =>
              match ← summaryOf? root view with
              | .error message => mark fails message
              | .ok json =>
                  match decodeLevelFacts json with
                  | .error message => mark fails s!"acc-levels: summary levels: {message}"
                  | .ok expected => do
                      let actual := (module.operators.map fun operator =>
                        (operator.name, operator.level.toString)).qsort
                          (fun left right => compare left.1 right.1 == .lt)
                      check fails "acc-levels: operator levels match the summary"
                        (actual == expected) s!"actual={actual.toList}"
                      match ← runFixture root view with
                      | .error message => mark fails message
                      | .ok again =>
                          check fails "acc-levels: repeated elaboration is identical"
                            (sameRun again run) (detailOf again)

/-! ## `LOCAL` visibility -/

def scenarioLocal (fails : Failures) (root : String)
    (views : Array FixtureView) : IO Unit := do
  match views.find? (fun view => view.id == "acc-local") with
  | none => mark fails "corpus: the manifest has no fixture acc-local"
  | some view =>
      match ← runFixture root view with
      | .error message => mark fails message
      | .ok run =>
          match run.module? with
          | none => check fails "acc-local: elaborates" false (detailOf run)
          | some module => do
              check fails "acc-local: the local definition is retained"
                (module.operators.any fun operator =>
                  operator.name == "Helper" && operator.localDeclaration)
                (toString (module.operators.toList.map fun operator => operator.name))
              check fails "acc-local: the dependent definition is retained"
                (module.operators.any fun operator =>
                  operator.name == "UseHelper" && !operator.localDeclaration) ""
              match ← readCorpusText root "accepted/AcceptLocal.tla" with
              | .error message => mark fails s!"acc-local: {message}"
              | .ok text => do
                  let probes : Array (ModuleName × String) := #[
                    (⟨"AcceptLocal"⟩, text),
                    (⟨"LocalUser"⟩,
                      moduleText "LocalUser"
                        "EXTENDS AcceptLocal\nUsesHelper == UseHelper"),
                    (⟨"LocalPeek"⟩,
                      moduleText "LocalPeek"
                        "EXTENDS AcceptLocal\nPeek == Helper"),
                    (⟨"LocalBase"⟩,
                      moduleText "LocalBase" "Shown == 1\nLOCAL Hidden == 2"),
                    (⟨"LocalExtendsUser"⟩,
                      moduleText "LocalExtendsUser"
                        "LOCAL EXTENDS LocalBase\nUsesShown == Shown"),
                    (⟨"LocalExtendsPeek"⟩,
                      moduleText "LocalExtendsPeek"
                        "EXTENDS LocalExtendsUser\nPeekShown == Shown"),
                    (⟨"LocalBaseUser"⟩,
                      moduleText "LocalBaseUser"
                        "EXTENDS LocalBase\nPeekHidden == Hidden")]
                  let user ← runInline probes "LocalUser"
                  check fails "local: an importer sees the exported definition"
                    (user.module?.isSome && user.diagnostics.isEmpty) (detailOf user)
                  let peek ← runInline probes "LocalPeek"
                  check fails "local: an importer does not see the local definition"
                    (peek.module?.isNone &&
                      peek.diagnostics.any (fun diagnostic =>
                        diagnostic.code == ElabCode.unknownName &&
                          diagnostic.arguments.any (fun argument =>
                            argument.1 == "name" && argument.2 == "Helper")))
                    (detailOf peek)
                  let hidden ← runInline probes "LocalBaseUser"
                  check fails "local: a local declaration is invisible to importers"
                    (hidden.module?.isNone &&
                      hidden.diagnostics.any (fun diagnostic =>
                        diagnostic.code == ElabCode.unknownName &&
                          diagnostic.arguments.any (fun argument =>
                            argument.1 == "name" && argument.2 == "Hidden")))
                    (detailOf hidden)
                  let extendsUser ← runInline probes "LocalExtendsUser"
                  match extendsUser.module? with
                  | none =>
                      check fails "local: LOCAL EXTENDS stays usable in its module"
                        false (detailOf extendsUser)
                  | some localModule =>
                      check fails
                        "local: LOCAL EXTENDS marks the imported declaration local"
                        (localModule.operators.any fun operator =>
                          operator.name == "Shown" && operator.localDeclaration)
                        (toString (localModule.operators.toList.map fun operator =>
                          (operator.name, operator.localDeclaration)))
                  let extendsPeek ← runInline probes "LocalExtendsPeek"
                  check fails "local: LOCAL EXTENDS is not re-exported"
                    (extendsPeek.module?.isNone &&
                      extendsPeek.diagnostics.any (fun diagnostic =>
                        diagnostic.code == ElabCode.unknownName &&
                          diagnostic.arguments.any (fun argument =>
                            argument.1 == "name" && argument.2 == "Shown")))
                    (detailOf extendsPeek)

/-! ## Structured diagnostics -/

/-- Every error diagnostic this slice emits carries a stable code and logical
locations; ambiguity and duplicate diagnostics also relate the conflicting
declaration. -/
def scenarioStructuredDiagnostics (fails : Failures) (root : String)
    (views : Array FixtureView) : IO Unit := do
  let checkFixture (id : String) (code : String) (name : String)
      (related : Bool) (secondModule : Bool) : IO Unit := do
    match views.find? (fun view => view.id == id) with
    | none => mark fails s!"corpus: the manifest has no fixture {id}"
    | some view =>
        match ← runFixture root view with
        | .error message => mark fails message
        | .ok run =>
            match run.diagnostics with
            | [] => check fails s!"{id}: the fixture reports a diagnostic" false (detailOf run)
            | diagnostic :: _ => do
                check fails s!"{id}: the primary diagnostic carries {code}"
                  (diagnostic.code == code && diagnostic.severity == .error)
                  diagnostic.code
                check fails s!"{id}: the diagnostic names the primary declaration"
                  diagnostic.primary.moduleName.isSome ""
                check fails s!"{id}: the diagnostic names the primary range"
                  (diagnostic.primary.range.start.line > 0)
                  s!"{diagnostic.primary.range.start.line}:{diagnostic.primary.range.start.column}"
                check fails s!"{id}: the diagnostic carries the name argument"
                  (diagnostic.arguments.any fun argument =>
                    argument.1 == "name" && argument.2 == name)
                  (toString diagnostic.arguments.toList)
                if related then do
                  check fails s!"{id}: the diagnostic relates the conflicting declaration"
                    (diagnostic.related.size ≥ 1 &&
                      diagnostic.related.all fun entry =>
                        entry.location.moduleName.isSome)
                    (toString diagnostic.related.size)
                  if secondModule then
                    check fails s!"{id}: the related declaration is a second module"
                      (diagnostic.related.any fun entry =>
                        entry.location.moduleName != diagnostic.primary.moduleName)
                      ""
  checkFixture "rej-extends-ambiguity" ElabCode.ambiguousImport "state" true true
  checkFixture "rej-duplicate-declaration" ElabCode.duplicateDeclaration "N" true false
  checkFixture "rej-arity-mismatch" ElabCode.arityMismatch "F" true false
  match views.find? (fun view => view.id == "rej-arity-mismatch") with
  | none => pure ()
  | some view =>
      match ← runFixture root view with
      | .error message => mark fails message
      | .ok run =>
          match run.diagnostics with
          | [] => pure ()
          | diagnostic :: _ =>
              check fails "rej-arity-mismatch: the diagnostic records expected and actual counts"
                (diagnostic.arguments.any (fun argument =>
                    argument.1 == "expected" && argument.2 == "1") &&
                  diagnostic.arguments.any (fun argument =>
                    argument.1 == "actual" && argument.2 == "2"))
                (toString diagnostic.arguments.toList)

/-! ## The whole accepted corpus -/

def scenarioAcceptedCorpus (fails : Failures) (root : String)
    (views : Array FixtureView) : IO Unit := do
  let mut accepted := 0
  let mut elaborated := 0
  for view in views do
    if view.kind == "accepted" then do
      accepted := accepted + 1
      match ← runFixture root view with
      | .error message => mark fails message
      | .ok run =>
          match run.module? with
          | none =>
              check fails s!"corpus: {view.id} elaborates with no error diagnostics"
                false (detailOf run)
          | some module => do
              elaborated := elaborated + 1
              match ← summaryOf? root view with
              | .error message => mark fails message
              | .ok json => do
                  checkSummaryIdentity fails view.id view json
                  checkSummaryVariables fails view.id module json
                  checkSummarySources fails view.id module json
  check fails "corpus: at least one accepted fixture elaborated" (accepted > 0) ""
  IO.println s!"TLA ELABORATION CORPUS (accepted): {accepted} fixtures, {elaborated} elaborated and matched to their summaries"

/-! ## The whole rejected corpus -/

/-- Stages whose rejection this slice owns: a graph that resolves still has to
be rejected during elaboration. -/
def elaborationOwnedStages : List String :=
  ["nameResolution", "substitution", "level"]

def scenarioRejectedCorpus (fails : Failures) (root : String)
    (views : Array FixtureView) : IO Unit := do
  let mut rejected := 0
  let mut owned := 0
  for view in views do
    if view.kind == "rejected" then do
      rejected := rejected + 1
      match ← runFixture root view with
      | .error message => mark fails message
      | .ok run => do
          check fails s!"corpus: {view.id} is rejected"
            run.module?.isNone (detailOf run)
          check fails s!"corpus: {view.id} reports at the manifest stage"
            (run.diagnostics.any fun diagnostic =>
              diagnostic.stage.toString == view.stage)
            (detailOf run)
          let elaborationCodes := run.diagnostics.filter fun diagnostic =>
            diagnostic.code.startsWith "TLA-ELAB-"
          if elaborationOwnedStages.contains view.stage then do
            owned := owned + 1
            check fails s!"corpus: {view.id} is rejected during elaboration"
              (!elaborationCodes.isEmpty) (detailOf run)
            check fails s!"corpus: {view.id} carries the manifest reason"
              (run.diagnostics.any fun diagnostic =>
                diagnostic.stage.toString == view.stage &&
                  ElabCode.reason diagnostic.code == view.reason)
              (detailOf run ++ s!" expected={view.stage}/{view.reason}")
            check fails s!"corpus: {view.id} resolves before its own stage"
              run.graph?.isSome (detailOf run)
            if view.stage == "substitution" then
              check fails s!"corpus: {view.id} reports an instance-substitution code"
                (run.diagnostics.any fun diagnostic =>
                  diagnostic.stage == .substitution &&
                    ElabCode.substitutionCodes.contains diagnostic.code)
                (detailOf run)
          else do
            check fails s!"corpus: {view.id} fails before elaboration"
              elaborationCodes.isEmpty (detailOf run)
            check fails s!"corpus: {view.id} does not reach a resolved graph"
              run.graph?.isNone (detailOf run)
  check fails "corpus: at least one rejected fixture was driven" (rejected > 0) ""
  IO.println s!"TLA ELABORATION CORPUS (rejected): {rejected} fixtures, {owned} rejected by this slice's stages"

/-! ## Scopes, arity, and levels on generated modules -/

def declBody (count : Nat) : String :=
  String.intercalate "\n" ((List.range count).map fun index => s!"x{index} == {index}")

def unknownBody (count : Nat) : String :=
  String.intercalate "\n" ((List.range count).map fun index =>
    s!"u{index} == Missing{index}")

def levelOfOperator? (run : Run) (name : String) : Option String := do
  let module ← run.module?
  let operator ← module.operators.find? fun operator => operator.name == name
  return operator.level.toString

/-- Every operator level of one attempt, for diagnostic messages. -/
def levelTable (run : Run) : String :=
  match run.module? with
  | none => "no module"
  | some module =>
      toString (module.operators.map fun operator =>
        (operator.name, operator.level.toString)).toList

def checkLevel (fails : Failures) (run : Run) (name : String)
    (expected : String) : IO Unit :=
  check fails s!"scope: {name} is classified {expected} level"
    (levelOfOperator? run name == some expected)
    (s!"actual={levelOfOperator? run name} levels={levelTable run} {detailOf run}")

def scenarioScopes (fails : Failures) : IO Unit := do
  -- A LET definition shadows a variable of the same name and stays constant.
  let letProbe ← runInline
    #[(⟨"LetProbe"⟩, moduleText "LetProbe"
        "VARIABLE v\nProbe == LET v == 1 IN v + 1")] "LetProbe"
  check fails "scope: a shadowing LET definition resolves"
    letProbe.module?.isSome (detailOf letProbe)
  checkLevel fails letProbe "Probe" "constant"
  -- A bound name shadows a variable of the same name.
  let boundProbe ← runInline
    #[(⟨"BoundProbe"⟩, moduleText "BoundProbe"
        "VARIABLE x\nShadowed == \\E x \\in {1}: x = 1\nVisible == \\E y \\in {1}: y = x")] "BoundProbe"
  check fails "scope: bound names shadow declarations"
    boundProbe.module?.isSome (detailOf boundProbe)
  checkLevel fails boundProbe "Shadowed" "constant"
  checkLevel fails boundProbe "Visible" "state"
  -- Function, CHOOSE, set-builder, and set-filter binders classify their domains
  -- in the scope of the names bound before them.
  let binderProbe ← runInline
    #[(⟨"BinderProbe"⟩, moduleText "BinderProbe"
        "VARIABLE x\nFn == [y \\in {1} |-> y + 1]\nStateFn == [y \\in {1} |-> x]\nChosen == CHOOSE y \\in {1}: y = 1\nStateChosen == CHOOSE y \\in {x}: y = x\nBuilt == {y * 2 : y \\in {1, 2}}\nFiltered == {y \\in {1, 2} : y > x}")] "BinderProbe"
  check fails "scope: binder forms resolve"
    binderProbe.module?.isSome (detailOf binderProbe)
  checkLevel fails binderProbe "Fn" "constant"
  checkLevel fails binderProbe "StateFn" "state"
  checkLevel fails binderProbe "Chosen" "constant"
  checkLevel fails binderProbe "StateChosen" "state"
  checkLevel fails binderProbe "Built" "constant"
  checkLevel fails binderProbe "Filtered" "state"
  -- A LET definition carries its own parameter arity.
  let letArityProbe ← runInline
    #[(⟨"LetArityProbe"⟩, moduleText "LetArityProbe"
        "CONSTANT N\nProbe == LET F(p) == p + N IN F(1)")] "LetArityProbe"
  check fails "scope: a LET definition resolves with its parameter arity"
    letArityProbe.module?.isSome (detailOf letArityProbe)
  checkLevel fails letArityProbe "Probe" "constant"
  -- A higher-order parameter is applied with its declared arity.
  let higherOrder ← runInline
    #[(⟨"HigherOrder"⟩, moduleText "HigherOrder"
        "Apply(F(_), v) == F(v)\nNullary == 1\nBadArity(F(_)) == F(1, 2)\nBadNullary == Nullary(1)")] "HigherOrder"
  check fails "scope: a higher-order parameter application resolves"
    (higherOrder.diagnostics.any fun diagnostic =>
      diagnostic.code == ElabCode.arityMismatch &&
        diagnostic.arguments.any (fun argument =>
          argument.1 == "name" && argument.2 == "F"))
    (detailOf higherOrder)
  check fails "scope: a nullary operator is applied with no arguments"
    (higherOrder.diagnostics.any fun diagnostic =>
      diagnostic.code == ElabCode.arityMismatch &&
        diagnostic.arguments.any (fun argument =>
          argument.1 == "name" && argument.2 == "Nullary"))
    (detailOf higherOrder)
  let applyProbe ← runInline
    #[(⟨"ApplyProbe"⟩, moduleText "ApplyProbe" "Apply(F(_), v) == F(v)")] "ApplyProbe"
  check fails "scope: a definition that applies its parameter elaborates"
    applyProbe.module?.isSome (detailOf applyProbe)
  checkLevel fails applyProbe "Apply" "constant"
  -- Standard-module facts are visible only through the module that provides
  -- them: `Int` through `Integers`, but `Nat` only through `Naturals`.
  let standardProbe : Array (ModuleName × String) := #[
    (⟨"StandardVisible"⟩,
      moduleText "StandardVisible" "EXTENDS Integers\nVisible == Int"),
    (⟨"StandardHidden"⟩,
      moduleText "StandardHidden" "EXTENDS Integers\nHidden == Nat")]
  let visible ← runInline standardProbe "StandardVisible"
  check fails "scope: a provided standard-module fact resolves"
    (levelOfOperator? visible "Visible" == some "constant") (detailOf visible)
  let hidden ← runInline standardProbe "StandardHidden"
  check fails "scope: an unprovided standard-module fact is an unknown name"
    (hidden.module?.isNone &&
      hidden.diagnostics.any fun diagnostic =>
        diagnostic.code == ElabCode.unknownName &&
          diagnostic.arguments.any fun argument =>
            argument.1 == "name" && argument.2 == "Nat")
    (detailOf hidden)
  let composedFacts ← runInline #[(⟨"ComposedFacts"⟩,
    moduleText "ComposedFacts"
      "EXTENDS Sequences\nFlagDomain == BOOLEAN\nTextDomain == STRING\nSize == Len(<<1>>)")]
    "ComposedFacts"
  check fails "scope: composed-source standard and language facts resolve"
    (composedFacts.module?.isSome &&
      levelOfOperator? composedFacts "FlagDomain" == some "constant" &&
      levelOfOperator? composedFacts "TextDomain" == some "constant" &&
      levelOfOperator? composedFacts "Size" == some "constant")
    (detailOf composedFacts)
  -- Elaboration is deterministic for equal captures.
  let first ← runInline
    #[(⟨"Det"⟩, moduleText "Det" "CONSTANT N\nVARIABLE x\nP == N + x")] "Det"
  let second ← runInline
    #[(⟨"Det"⟩, moduleText "Det" "CONSTANT N\nVARIABLE x\nP == N + x")] "Det"
  check fails "scope: repeated elaboration is identical" (first == second)
    s!"{detailOf first} vs {detailOf second}"

/-! ## `INSTANCE` and substitution -/

/-- One diagnostic with the given code at the given stage. -/
def hasDiagnostic (run : Run) (code : String) (stage : DiagnosticStage) : Bool :=
  run.diagnostics.any fun diagnostic =>
    diagnostic.code == code && diagnostic.stage == stage

/-- The effective variable names of one elaboration attempt. -/
def variableNames (run : Run) : Array String :=
  match run.module? with
  | none => #[]
  | some module => module.variables.map fun stateVariable => stateVariable.visibleName

/-- Run one manifest fixture and verify its attempt. -/
def withFixture (fails : Failures) (root : String) (views : Array FixtureView)
    (id : String) (verify : Run → IO Unit) : IO Unit := do
  match views.find? (fun view => view.id == id) with
  | none => mark fails s!"corpus: the manifest has no fixture {id}"
  | some view =>
      match ← runFixture root view with
      | .error message => mark fails message
      | .ok run => verify run

def scenarioInstances (fails : Failures) (root : String)
    (views : Array FixtureView) : IO Unit := do
  -- A named, fully substituted instance contributes no unqualified names: the
  -- effective constants are the instantiating module's own.
  withFixture fails root views "rej-instance-definition-only" fun run => do
    check fails "instance: the named definition-only instance elaborates"
      run.module?.isSome (detailOf run)
    check fails "instance: only the instantiating module's constant is effective"
      (run.module?.map (fun module =>
        module.constants.map fun entry => entry.name) == some #["RootLimit"])
      (detailOf run)
    checkLevel fails run "RootOp" "constant"
    check fails "instance: the substituted child source stays in provenance"
      (run.module?.map (fun module => module.sourceManifest.size) == some 2)
      (detailOf run)
  -- A substituted child variable never becomes root state, and the instantiated
  -- operator takes the level of the substituted expression.
  withFixture fails root views "rej-instance-variable-substituted" fun run => do
    check fails "instance: the child variable does not become root state"
      (variableNames run == #["parentState"]) (detailOf run)
    checkLevel fails run "RootOp" "action"
    check fails "instance: substitution keeps both dependency sources"
      (run.module?.map (fun module => module.sourceManifest.size) == some 2)
      (detailOf run)
  -- An unnamed instance exposes the child operators unqualified.
  withFixture fails root views "rej-instance-unnamed" fun run => do
    check fails "instance: an unnamed instance keeps one root variable"
      (variableNames run == #["rootState"]) (detailOf run)
    check fails "instance: an unnamed instance exposes the child operator"
      (run.module?.map (fun module => module.operators.any fun operator =>
        operator.name == "ChildOp") == some true)
      (detailOf run)
  -- An instance without WITH uses the same-named parent declaration.
  withFixture fails root views "rej-instance-implicit-substitution" fun run => do
    check fails "instance: implicit substitution keeps one root variable"
      (variableNames run == #["shared"]) (detailOf run)
    checkLevel fails run "RootOp" "action"
  -- A constant substituted by a state expression is legal and shifts the
  -- instantiated operator to state level.
  withFixture fails root views "rej-substitution-constant-by-state" fun run => do
    check fails "instance: a state substitution keeps one root variable"
      (variableNames run == #["rootState"]) (detailOf run)
    checkLevel fails run "RootOp" "state"
  withFixture fails root views "rej-instance-unsubstituted" fun run => do
    check fails "instance: a missing substitution is rejected"
      (run.module?.isNone &&
        hasDiagnostic run ElabCode.substitutionMissing .substitution)
      (detailOf run)
  withFixture fails root views "rej-instance-invalid-substitution" fun run => do
    check fails "instance: an undeclared substitution target is rejected"
      (run.module?.isNone &&
        hasDiagnostic run ElabCode.substitutionInvalid .substitution)
      (detailOf run)
  -- Chained instances: the middle module's qualified reference is instantiated
  -- through the outer substitution.
  let chain : Array (ModuleName × String) := #[
    (⟨"ChainChild"⟩, moduleText "ChainChild"
      "EXTENDS Integers\nCONSTANT ChildLimit\nChildOp == ChildLimit + 1"),
    (⟨"ChainMid"⟩, moduleText "ChainMid"
      "CONSTANT MidLimit\nM == INSTANCE ChainChild WITH ChildLimit <- MidLimit\nMidOp == M!ChildOp"),
    (⟨"ChainRoot"⟩, moduleText "ChainRoot"
      "CONSTANT RootLimit\nI == INSTANCE ChainMid WITH MidLimit <- RootLimit\nRootOp == I!MidOp")]
  let chained ← runInline chain "ChainRoot"
  check fails "instance: a chained instance resolves"
    chained.module?.isSome (detailOf chained)
  check fails "instance: a chain keeps only the root constant"
    (chained.module?.map (fun module =>
      module.constants.map fun entry => entry.name) == some #["RootLimit"])
    (detailOf chained)
  checkLevel fails chained "RootOp" "constant"
  -- The same chain with a state substitution two instances deep: the level of
  -- the inner operator is composed through both frames.
  let levelChain : Array (ModuleName × String) := #[
    (⟨"LevelChainChild"⟩, moduleText "LevelChainChild"
      "CONSTANT ChildLimit\nChildOp == ChildLimit"),
    (⟨"LevelChainMid"⟩, moduleText "LevelChainMid"
      "CONSTANT MidLimit\nM == INSTANCE LevelChainChild WITH ChildLimit <- MidLimit\nMidOp == M!ChildOp"),
    (⟨"LevelChainRoot"⟩, moduleText "LevelChainRoot"
      "VARIABLE rootState\nI == INSTANCE LevelChainMid WITH MidLimit <- rootState\nRootOp == I!MidOp")]
  let levelChainRun ← runInline levelChain "LevelChainRoot"
  check fails "instance: a chained state shift elaborates"
    levelChainRun.module?.isSome (detailOf levelChainRun)
  checkLevel fails levelChainRun "RootOp" "state"
  -- `LOCAL INSTANCE` stays visible in its own module and is not re-exported.
  let localSources : Array (ModuleName × String) := #[
    (⟨"LocalChild"⟩, moduleText "LocalChild"
      "CONSTANT ChildLimit\nChildOp == ChildLimit\nLOCAL HiddenOp == ChildLimit"),
    (⟨"LocalRoot"⟩, moduleText "LocalRoot"
      "CONSTANT RootLimit\nLOCAL INSTANCE LocalChild WITH ChildLimit <- RootLimit\nRootOp == ChildOp"),
    (⟨"LocalUser"⟩, moduleText "LocalUser"
      "EXTENDS LocalRoot\nUserOp == ChildOp"),
    (⟨"LocalHidden"⟩, moduleText "LocalHidden"
      "EXTENDS LocalRoot\nPeek == HiddenOp"),
    (⟨"ReexportChild"⟩, moduleText "ReexportChild"
      "CONSTANT ChildLimit\nChildOp == ChildLimit"),
    (⟨"ReexportRoot"⟩, moduleText "ReexportRoot"
      "CONSTANT RootLimit\nINSTANCE ReexportChild WITH ChildLimit <- RootLimit"),
    (⟨"ReexportUser"⟩, moduleText "ReexportUser"
      "EXTENDS ReexportRoot\nUserOp == ChildOp")]
  let localRoot ← runInline localSources "LocalRoot"
  check fails "instance: LOCAL INSTANCE serves its own module"
    localRoot.module?.isSome (detailOf localRoot)
  let localUser ← runInline localSources "LocalUser"
  check fails "instance: LOCAL INSTANCE is not re-exported"
    (localUser.module?.isNone &&
      hasDiagnostic localUser ElabCode.unknownName .nameResolution)
    (detailOf localUser)
  let localHidden ← runInline localSources "LocalHidden"
  check fails "instance: a child LOCAL declaration is not exposed"
    (localHidden.module?.isNone &&
      hasDiagnostic localHidden ElabCode.unknownName .nameResolution)
    (detailOf localHidden)
  let reexport ← runInline localSources "ReexportUser"
  check fails "instance: a non-local unnamed instance is re-exported"
    reexport.module?.isSome (detailOf reexport)
  -- An unnamed instance re-exports the nested instance names of its child.
  let nested : Array (ModuleName × String) := #[
    (⟨"NestBase"⟩, moduleText "NestBase"
      "CONSTANT BaseLimit\nBaseOp == BaseLimit"),
    (⟨"NestChild"⟩, moduleText "NestChild"
      "CONSTANT ChildLimit\nJ == INSTANCE NestBase WITH BaseLimit <- ChildLimit\nChildOp == J!BaseOp"),
    (⟨"NestRoot"⟩, moduleText "NestRoot"
      "CONSTANT RootLimit\nINSTANCE NestChild WITH ChildLimit <- RootLimit\nR1 == J!BaseOp\nR2 == ChildOp")]
  let nestedRun ← runInline nested "NestRoot"
  check fails "instance: an unnamed instance re-exports nested instance names"
    nestedRun.module?.isSome (detailOf nestedRun)
  check fails "instance: a nested chain keeps only the root constant"
    (nestedRun.module?.map (fun module =>
      module.constants.map fun entry => entry.name) == some #["RootLimit"])
    (detailOf nestedRun)
  -- A same-named parent definition substitutes implicitly.
  let implicitDefinition ← runInline #[
    (⟨"ImplDefChild"⟩, moduleText "ImplDefChild"
      "CONSTANT c\nVARIABLE v\nOp == c"),
    (⟨"ImplDefRoot"⟩, moduleText "ImplDefRoot"
      "VARIABLE v\nc == 1\nI == INSTANCE ImplDefChild\nR == I!Op")] "ImplDefRoot"
  check fails "instance: a same-named definition substitutes implicitly"
    implicitDefinition.module?.isSome (detailOf implicitDefinition)
  -- Rejections.
  let duplicate ← runInline #[
    (⟨"DupChild"⟩, moduleText "DupChild" "CONSTANT c\nVARIABLE v\nOp == c"),
    (⟨"DupRoot"⟩, moduleText "DupRoot"
      "I == INSTANCE DupChild WITH c <- 1, c <- 2, v <- 3\nR == I!Op")] "DupRoot"
  check fails "instance: a duplicate substitution is rejected"
    (duplicate.module?.isNone &&
      hasDiagnostic duplicate ElabCode.substitutionDuplicate .substitution)
    (detailOf duplicate)
  check fails "instance: a duplicate substitution relates the earlier site"
    (duplicate.diagnostics.any fun diagnostic =>
      diagnostic.code == ElabCode.substitutionDuplicate &&
        diagnostic.related.size ≥ 1 &&
        diagnostic.related.all fun entry => entry.location.moduleName.isSome)
    (toString (duplicate.diagnostics.map (fun diagnostic => diagnostic.related.size)))
  let arity ← runInline #[
    (⟨"ArityChild"⟩, moduleText "ArityChild" "CONSTANT c\nOp == c"),
    (⟨"ArityRoot"⟩, moduleText "ArityRoot"
      "I == INSTANCE ArityChild WITH c(_) <- 1\nR == I!Op")] "ArityRoot"
  check fails "instance: an arity mismatch is rejected"
    (arity.module?.isNone &&
      hasDiagnostic arity ElabCode.substitutionArity .substitution)
    (detailOf arity)
  let levelVariable ← runInline #[
    (⟨"LevelVarChild"⟩, moduleText "LevelVarChild" "VARIABLE v\nOp == v' = v"),
    (⟨"LevelVarRoot"⟩, moduleText "LevelVarRoot"
      "VARIABLE x\nI == INSTANCE LevelVarChild WITH v <- x'\nR == TRUE")] "LevelVarRoot"
  check fails "instance: an action-level variable substitution is rejected"
    (levelVariable.module?.isNone &&
      hasDiagnostic levelVariable ElabCode.substitutionLevel .substitution)
    (detailOf levelVariable)
  let levelTemporal ← runInline #[
    (⟨"LevelTmpChild"⟩, moduleText "LevelTmpChild" "VARIABLE v\nOp == v' = v"),
    (⟨"LevelTmpRoot"⟩, moduleText "LevelTmpRoot"
      "VARIABLE x\nI == INSTANCE LevelTmpChild WITH v <- []x\nR == TRUE")] "LevelTmpRoot"
  check fails "instance: a temporal variable substitution is rejected"
    (levelTemporal.module?.isNone &&
      hasDiagnostic levelTemporal ElabCode.substitutionLevel .substitution)
    (detailOf levelTemporal)
  let levelConstant ← runInline #[
    (⟨"LevelConstChild"⟩, moduleText "LevelConstChild" "CONSTANT c\nOp == c"),
    (⟨"LevelConstRoot"⟩, moduleText "LevelConstRoot"
      "VARIABLE x\nI == INSTANCE LevelConstChild WITH c <- x'\nR == I!Op")] "LevelConstRoot"
  check fails "instance: revision 1 applies the uniform state bound to constants"
    (levelConstant.module?.isNone &&
      hasDiagnostic levelConstant ElabCode.substitutionLevel .substitution)
    (detailOf levelConstant)
  -- Standard modules: a pinned instance exposes only its modelled facts, and
  -- those facts are not substitution targets.
  let standardRun ← runInline #[
    (⟨"StandardRoot"⟩, moduleText "StandardRoot"
      "EXTENDS Integers\nI == INSTANCE Integers\nR == I!Int")] "StandardRoot"
  check fails "instance: a standard-module instance resolves its pinned facts"
    standardRun.module?.isSome (detailOf standardRun)
  let standardSub ← runInline #[
    (⟨"StandardSub"⟩, moduleText "StandardSub"
      "EXTENDS Integers\nI == INSTANCE Integers WITH Int <- 1\nR == TRUE")] "StandardSub"
  check fails "instance: a pinned fact is not a substitution target"
    (standardSub.module?.isNone &&
      hasDiagnostic standardSub ElabCode.substitutionInvalid .substitution)
    (detailOf standardSub)
  let qualifiedConstant ← runInline #[
    (⟨"QualConstChild"⟩, moduleText "QualConstChild" "CONSTANT c\nOp == c"),
    (⟨"QualConstRoot"⟩, moduleText "QualConstRoot"
      "I == INSTANCE QualConstChild WITH c <- 1\nR == I!c")] "QualConstRoot"
  check fails "instance: a constant is not visible through the instance qualifier"
    (qualifiedConstant.module?.isNone &&
      hasDiagnostic qualifiedConstant ElabCode.unknownName .nameResolution)
    (detailOf qualifiedConstant)

/-! ## Resource limits -/

def scenarioLimits (fails : Failures) : IO Unit := do
  let defaults : ElaborationLimits := {}
  check fails "limits: maxDeclarations default is the frozen profile value"
    (defaults.maxDeclarations == 4096) (toString defaults.maxDeclarations)
  check fails "limits: maxSymbols default is the accumulated-symbol budget"
    (defaults.maxSymbols == 262144) (toString defaults.maxSymbols)
  check fails "limits: maxDiagnostics default is the profile value"
    (defaults.maxDiagnostics == 64) (toString defaults.maxDiagnostics)
  check fails "limits: maxDiagnosticBytes default is one MiB"
    (defaults.maxDiagnosticBytes == 1024 * 1024)
    (toString defaults.maxDiagnosticBytes)
  let declarationProbe (count : Nat) : Array (ModuleName × String) :=
    #[(⟨"DeclProbe"⟩, moduleText "DeclProbe" (declBody count))]
  let exactDeclarations ← runInline (declarationProbe 4) "DeclProbe"
    { maxDeclarations := 4 }
  check fails "limits: the declaration limit admits an exact fit"
    (exactDeclarations.module?.isSome && exactDeclarations.diagnostics.isEmpty)
    (detailOf exactDeclarations)
  let overDeclarations ← runInline (declarationProbe 4) "DeclProbe"
    { maxDeclarations := 3 }
  check fails "limits: the declaration limit rejects limit plus one"
    (overDeclarations.module?.isNone &&
      overDeclarations.diagnostics.any (fun diagnostic =>
        diagnostic.code == ElabCode.declarationLimit))
    (detailOf overDeclarations)
  -- The budget counts every module-level declaration, including dependency
  -- declarations; the parser's frozen budget counts parsed declarations the
  -- same way. This graph holds five declarations across two modules: the
  -- EXTENDS site plus two definitions in each module.
  let twoModules : Array (ModuleName × String) := #[
    (⟨"LimitRoot"⟩, moduleText "LimitRoot" "EXTENDS LimitBase\na == 1\nb == 2"),
    (⟨"LimitBase"⟩, moduleText "LimitBase" "c == 3\nd == 4")]
  let graphExact ← runInline twoModules "LimitRoot" { maxDeclarations := 5 }
  check fails "limits: the declaration budget admits a whole graph at the limit"
    (graphExact.module?.isSome) (detailOf graphExact)
  let graphOver ← runInline twoModules "LimitRoot" { maxDeclarations := 4 }
  check fails "limits: the declaration budget spans the captured graph"
    (graphOver.module?.isNone &&
      graphOver.diagnostics.any (fun diagnostic =>
        diagnostic.code == ElabCode.declarationLimit))
    (detailOf graphOver)
  let symbolLimits (symbols : Nat) : ElaborationLimits :=
    { maxDeclarations := 64, maxSymbols := symbols }
  let exactSymbols ← runInline (declarationProbe 4) "DeclProbe" (symbolLimits 4)
  check fails "limits: the symbol limit admits an exact fit"
    (exactSymbols.module?.isSome && exactSymbols.diagnostics.isEmpty)
    (detailOf exactSymbols)
  let overSymbols ← runInline (declarationProbe 4) "DeclProbe" (symbolLimits 3)
  check fails "limits: the symbol limit rejects limit plus one"
    (overSymbols.module?.isNone &&
      overSymbols.diagnostics.any (fun diagnostic =>
        diagnostic.code == ElabCode.symbolLimit))
    (detailOf overSymbols)
  let unknownProbe (count : Nat) : Array (ModuleName × String) :=
    #[(⟨"DiagProbe"⟩, moduleText "DiagProbe" (unknownBody count))]
  let countExact ← runInline (unknownProbe 3) "DiagProbe"
    { maxDiagnostics := 3, maxDiagnosticBytes := 1024 * 1024 }
  check fails "limits: the diagnostic count admits an exact fit"
    (countExact.module?.isNone && countExact.diagnostics.length == 3 &&
      !countExact.diagnostics.any (fun diagnostic =>
        diagnostic.code == ElabCode.diagnosticsTruncated))
    (detailOf countExact)
  let countOver ← runInline (unknownProbe 3) "DiagProbe"
    { maxDiagnostics := 2, maxDiagnosticBytes := 1024 * 1024 }
  check fails "limits: the diagnostic count reports truncation at limit plus one"
    (countOver.diagnostics.any (fun diagnostic =>
      diagnostic.code == ElabCode.diagnosticsTruncated &&
        diagnostic.arguments.any (fun argument =>
          argument.1 == "dropped" && argument.2 == "1")))
    (detailOf countOver)
  let unitRun ← runInline (unknownProbe 1) "DiagProbe"
  match unitRun.diagnostics with
  | [diagnostic] => do
      let weight := Diagnostic.byteWeight diagnostic
      let bytesExact ← runInline (unknownProbe 1) "DiagProbe"
        { maxDiagnostics := 64, maxDiagnosticBytes := weight }
      check fails "limits: the diagnostic byte budget admits an exact fit"
        (bytesExact.diagnostics.length == 1 &&
          bytesExact.diagnostics.head?.map (fun item => item.code) ==
            some ElabCode.unknownName)
        (detailOf bytesExact)
      let bytesOver ← runInline (unknownProbe 1) "DiagProbe"
        { maxDiagnostics := 64, maxDiagnosticBytes := weight - 1 }
      check fails "limits: the diagnostic byte budget truncates below the fit"
        (bytesOver.diagnostics.length == 1 &&
          bytesOver.diagnostics.head?.map (fun item => item.code) ==
            some ElabCode.diagnosticsTruncated)
        (detailOf bytesOver)
  | _ =>
      check fails "limits: one unknown name reports one diagnostic"
        false (detailOf unitRun)

/-! ## Core purity -/

def identifierTokens (line : String) : List String :=
  let step (state : List String × List Char) (character : Char) :=
    if Core.Tla.isAsciiLetter character || Core.Tla.isAsciiDigit character ||
        character == '_' then
      (state.1, state.2 ++ [character])
    else
      match state.2 with
      | [] => (state.1, [])
      | word => (state.1 ++ [String.ofList word], [])
  let scanned := line.toList.foldl step ([], [])
  match scanned.2 with
  | [] => scanned.1
  | word => scanned.1 ++ [String.ofList word]

def scenarioCorePurity (fails : Failures) : IO Unit := do
  match ← repositoryRoot? "." with
  | none => mark fails "purity: the repository root was not found"
  | some repo => do
      let directory := repo / "Core" / "Tla"
      let entries ← directory.readDir
      let mut sources := 0
      for entry in entries do
        if entry.path.extension == some "lean" then do
          sources := sources + 1
          let text ← IO.FS.readFile entry.path
          for line in text.splitOn "\n" do
            let trimmed := line.trimAscii.toString
            let tokens := identifierTokens trimmed
            if tokens.contains "sorry" || tokens.contains "admit" then
              mark fails s!"purity: {entry.fileName} uses a proof hole: {trimmed}"
            if trimmed.startsWith "axiom " then
              mark fails s!"purity: {entry.fileName} declares an axiom: {trimmed}"
            if trimmed.startsWith "import Shell" then
              mark fails s!"purity: {entry.fileName} imports Shell: {trimmed}"
            if trimmed.startsWith "import Core.ModelInterface" &&
                trimmed != "import Core.ModelInterface.Sha256" then
              mark fails s!"purity: {entry.fileName} imports the model-interface compiler: {trimmed}"
      check fails "purity: the frontend sources were scanned" (sources > 0) ""

/-! ## Driver -/

def allScenarios (fails : Failures) : IO Unit := do
  match ← corpusRoot? "." with
  | none =>
      mark fails "corpus: test/fixtures/tla-frontend/manifest.json not found"
  | some root => do
      let rootText := root.toString
      scenarioNineteenEvidence fails rootText
      match ← readCorpusText rootText "manifest.json" with
      | .error message => mark fails s!"corpus manifest: {message}"
      | .ok text =>
          match decodeFixtureViews text with
          | .error message => mark fails s!"corpus manifest: {message}"
          | .ok views => do
              scenarioEffectiveVariables fails rootText views
              scenarioLevels fails rootText views
              scenarioLocal fails rootText views
              scenarioInstances fails rootText views
              scenarioStructuredDiagnostics fails rootText views
              scenarioAcceptedCorpus fails rootText views
              scenarioRejectedCorpus fails rootText views
  scenarioScopes fails
  scenarioLimits fails
  scenarioCorePurity fails

def failuresOf : IO (List String) := do
  let fails ← IO.mkRef ([] : List String)
  allScenarios fails
  fails.get

def report (items : List String) : IO UInt32 := do
  if items.isEmpty then
    IO.println "TLA ELABORATION SPEC GREEN"
    return 0
  else
    for item in items do
      IO.eprintln s!"FAIL {item}"
    IO.eprintln s!"{items.length} FAILURES"
    return 1

def run : IO UInt32 := do
  report (← failuresOf)

end TlaElaborationSpec

def main : IO UInt32 :=
  TlaElaborationSpec.run

-- The acceptance command `lake env lean tools/TlaElaborationSpec.lean` only
-- elaborates this file, so run the suite here as well: a failing check makes
-- the command fail instead of compiling unattended assertions.
#eval do
  let code ← TlaElaborationSpec.run
  if code != 0 then
    throw (IO.userError "TLA elaboration specification failed")
