import Core.Tla.Source
import Shell.Tla.SourceProvider
import Shell.Tla.ModuleResolver

/-!
# TLA+ module-resolution specification

Covers the frontend's source-provider and module-graph layers
(`Docs/model-interface-compiler/tla-frontend-design.md`, §7.1, §12, §19, §21,
and §25.2). Provider cases use freshly created temporary directories; no
network, Apalache, or private model material is required.

Run with `lake env lean --run tools/TlaModuleResolverSpec.lean` from the
repository root.
-/

namespace TlaModuleResolverSpec

open Core.Tla
open Shell.Tla

abbrev Failures := IO.Ref (List String)

def check (fails : Failures) (name : String) (ok : Bool)
    (detail : String := "") : IO Unit := do
  if !ok then
    fails.modify fun items =>
      items ++ [if detail.isEmpty then name else s!"{name}: {detail}"]

/-- Unchecked module-name literal for test data. -/
def moduleName (raw : String) : Core.Tla.ModuleName := ⟨raw⟩

/-- A minimal well-formed module source. -/
def moduleText (name : String) (body : String) : String :=
  s!"---- MODULE {name} ----\n\n{body}\n\n====\n"

def writeModule (dir : System.FilePath) (name : String)
    (body : String) : IO Unit :=
  IO.FS.writeFile (dir / (name ++ ".tla")) (moduleText name body)

def makeSymlink (target link : System.FilePath) : IO (Except String Unit) := do
  let output ← IO.Process.output {
    cmd := "ln"
    args := #["-s", "--", target.toString, link.toString]
  }
  if output.exitCode == 0 then return .ok ()
  return .error output.stderr

def unitOf? : Except SourceReadError Core.Tla.SourceUnit →
    Option Core.Tla.SourceUnit
  | .ok unit => some unit
  | .error _ => none

def errorOf? : Except SourceReadError Core.Tla.SourceUnit →
    Option SourceReadError
  | .ok _ => none
  | .error error => some error

def isOk : Except ε α → Bool
  | .ok _ => true
  | .error _ => false

/-! ## Canonical logical names -/

def scenarioLogicalNames (fails : Failures) : IO Unit := do
  check fails "logical names: canonical accepted"
    (Shell.Tla.ModuleRef.validLogicalPath "Root.tla"
      && Shell.Tla.ModuleRef.validLogicalPath "_Private2.tla")
  check fails "logical names: path traversal rejected"
    (!Shell.Tla.ModuleRef.validLogicalPath "../Root.tla"
      && !Shell.Tla.ModuleRef.validLogicalPath "dir/Root.tla"
      && !Shell.Tla.ModuleRef.validLogicalPath "dir\\Root.tla")
  check fails "logical names: extension enforced"
    (!Shell.Tla.ModuleRef.validLogicalPath "Root.txt"
      && !Shell.Tla.ModuleRef.validLogicalPath "Root.tla.bak"
      && !Shell.Tla.ModuleRef.validLogicalPath ".tla")
  check fails "logical names: stem must be a module name"
    (!Shell.Tla.ModuleRef.validLogicalPath "1Bad.tla"
      && !Shell.Tla.ModuleRef.validLogicalPath "has-dash.tla"
      && !Shell.Tla.ModuleRef.validLogicalPath "has space.tla")
  check fails "logical names: canonical reference constructor"
    ((Shell.Tla.ModuleRef.ofModuleName (moduleName "Counter")).logicalPath
      == "Counter.tla")

/-! ## Inline provider -/

def scenarioInlineProvider (fails : Failures) : IO Unit := do
  let provider := Shell.Tla.SourceProvider.inline #[
    (moduleName "Root", moduleText "Root" "EXTENDS Base"),
    (moduleName "Base", moduleText "Base" "VARIABLE shared")
  ]
  match ← provider.readRoot (Shell.Tla.ModuleRef.ofModuleName (moduleName "Root")) with
  | .error error =>
      check fails "inline: root reads" false (Shell.Tla.SourceReadError.message error)
  | .ok unit =>
      check fails "inline: root reads" true
      check fails "inline: logical path is canonical" (unit.logicalPath == "Root.tla")
      check fails "inline: capture is self-consistent" (Core.Tla.SourceUnit.consistent unit)
      check fails "inline: origin is the source map"
        (unit.origin == .inlineSourceMap)
  match ← provider.readDependency (moduleName "Base") with
  | .error error =>
      check fails "inline: dependency reads" false (Shell.Tla.SourceReadError.message error)
  | .ok unit =>
      check fails "inline: dependency reads" true
      check fails "inline: dependency digest is stable"
        (unit.contentSha256 ==
          (Core.Tla.SourceUnit.create .inlineSourceMap "Base.tla"
            (moduleText "Base" "VARIABLE shared")).contentSha256)
  check fails "inline: unknown module is not found"
    (errorOf? (← provider.readDependency (moduleName "Missing")) ==
      some (.notFound (moduleName "Missing")))
  check fails "inline: unknown root is not found"
    ((errorOf? (← provider.readRoot
        (Shell.Tla.ModuleRef.ofModuleName (moduleName "Missing")))).isSome)
  check fails "inline: standard lookup succeeds"
    (isOk (← provider.resolveStandard (moduleName "Naturals")))
  check fails "inline: unknown standard module is reported"
    (match ← provider.resolveStandard (moduleName "NotARealModule") with
      | .error (.standardModuleUnavailable _) => true
      | _ => false)

/-! ## Borrowed-directory provider -/

def scenarioBorrowedProvider (fails : Failures) : IO Unit := do
  let root ← IO.FS.createTempDir
  let directory := root / "specs"
  IO.FS.createDir directory
  writeModule directory "Root" "EXTENDS Base"
  writeModule directory "Base" "VARIABLE shared"
  let provider := Shell.Tla.SourceProvider.borrowedDirectory directory
  match ← provider.readRoot (Shell.Tla.ModuleRef.ofModuleName (moduleName "Root")) with
  | .error error =>
      check fails "borrowed: root reads" false (Shell.Tla.SourceReadError.message error)
  | .ok unit =>
      check fails "borrowed: root reads" true
      check fails "borrowed: capture is self-consistent"
        (Core.Tla.SourceUnit.consistent unit)
      check fails "borrowed: origin is the directory" (unit.origin == .borrowedDirectory)
  check fails "borrowed: dependency reads"
    (isOk (← provider.readDependency (moduleName "Base")))
  check fails "borrowed: missing dependency is not found"
    (errorOf? (← provider.readDependency (moduleName "Missing")) ==
      some (.notFound (moduleName "Missing")))
  check fails "borrowed: missing root is not found"
    ((errorOf? (← provider.readRoot
        (Shell.Tla.ModuleRef.ofModuleName (moduleName "Missing")))) ==
      some (.notFound (moduleName "Missing")))
  check fails "borrowed: traversal reference rejected"
    (match errorOf? (← provider.readRoot
        { moduleName := moduleName "Root", logicalPath := "../Root.tla" }) with
      | some (.invalidReference _ _) => true
      | _ => false)
  check fails "borrowed: nested reference rejected"
    (match errorOf? (← provider.readRoot
        { moduleName := moduleName "Root", logicalPath := "nested/Root.tla" }) with
      | some (.invalidReference _ _) => true
      | _ => false)
  check fails "borrowed: non-.tla reference rejected"
    (match errorOf? (← provider.readRoot
        { moduleName := moduleName "Root", logicalPath := "Root.txt" }) with
      | some (.invalidReference _ _) => true
      | _ => false)

  -- A directory that happens to be named like a module is not a source file.
  IO.FS.createDir (directory / "Weird.tla")
  check fails "borrowed: special file rejected"
    (errorOf? (← provider.readDependency (moduleName "Weird")) ==
      some (.notRegularFile "Weird.tla"))

  -- Borrowed and inline adapters agree on logical identity for equal captures.
  let inlineProvider := Shell.Tla.SourceProvider.inline #[
    (moduleName "Root", moduleText "Root" "EXTENDS Base")
  ]
  let borrowedRoot ← provider.readRoot
    (Shell.Tla.ModuleRef.ofModuleName (moduleName "Root"))
  let inlineRoot ← inlineProvider.readRoot
    (Shell.Tla.ModuleRef.ofModuleName (moduleName "Root"))
  match borrowedRoot, inlineRoot with
  | .ok borrowedUnit, .ok inlineUnit =>
      check fails "adapters: equal logical identity"
        ((Core.Tla.SourceUnit.identity borrowedUnit (moduleName "Root")) ==
          (Core.Tla.SourceUnit.identity inlineUnit (moduleName "Root")))
      check fails "adapters: distinct origins"
        (borrowedUnit.origin != inlineUnit.origin)
  | _, _ =>
      check fails "adapters: equal logical identity" false "root read failed"

  if System.Platform.isWindows then
    IO.println "SKIP borrowed symlink case on Windows"
  else
    match ← makeSymlink (directory / "Root.tla") (directory / "Alias.tla") with
    | .error error =>
        check fails "borrowed: symlink case created" false error
    | .ok () =>
        check fails "borrowed: symlink rejected"
          (match errorOf? (← provider.readDependency (moduleName "Alias")) with
            | some (.symbolicLink "Alias.tla") => true
            | _ => false)

  -- Per-file byte bounds are enforced before and during the read.
  let rootBytes := (moduleText "Root" "EXTENDS Base").toUTF8.size
  let tiny := Shell.Tla.SourceProvider.borrowedDirectory directory
    { maxFileBytes := 16 }
  check fails "borrowed: oversize rejected at limit"
    (match errorOf? (← tiny.readRoot
        (Shell.Tla.ModuleRef.ofModuleName (moduleName "Root"))) with
      | some (.tooLarge "Root.tla" 16 _) => true
      | _ => false)
  let exactLimit := Shell.Tla.SourceProvider.borrowedDirectory directory
    { maxFileBytes := rootBytes }
  check fails "borrowed: exact byte limit accepted"
    (isOk (← exactLimit.readRoot
      (Shell.Tla.ModuleRef.ofModuleName (moduleName "Root"))))
  let underLimit := Shell.Tla.SourceProvider.borrowedDirectory directory
    { maxFileBytes := rootBytes - 1 }
  check fails "borrowed: limit-plus-one rejected"
    (match errorOf? (← underLimit.readRoot
        (Shell.Tla.ModuleRef.ofModuleName (moduleName "Root"))) with
      | some (.tooLarge "Root.tla" _ _) => true
      | _ => false)
  IO.FS.removeDirAll root

/-! ## Standard-module catalog -/

def scenarioStandardCatalog (fails : Failures) : IO Unit := do
  let catalog := Shell.Tla.StandardModuleCatalog.default
  check fails "catalog: profile identity pinned"
    (catalog.profile.profileId == "mirrors-standard-modules/v1")
  check fails "catalog: production names preserved"
    ((catalog.modules.map (fun entry => entry.name.name)).toList ==
      ["Naturals", "Integers", "Reals", "Sequences", "FiniteSets", "Bags",
       "TLC", "TLCExt", "Toolbox", "Randomization", "RealTime", "Json",
       "CSV", "IOUtils", "Option", "Variants", "Apalache"])
  check fails "catalog: language module kind"
    ((catalog.find? (moduleName "Naturals")).map (fun entry => entry.kind) ==
      some .languageDefined)
  check fails "catalog: extension module kind"
    ((catalog.find? (moduleName "Apalache")).map (fun entry => entry.kind) ==
      some .apalacheExtension)
  check fails "catalog: unknown module absent"
    ((catalog.find? (moduleName "MyLocalModule")).isNone)

/-! ## Repository corpus -/

/-- Read the checked-in module-resolution corpus when it is present. -/
def scenarioCorpus (fails : Failures) : IO Unit := do
  let corpus := ("./test/fixtures/tla-frontend/accepted/diamond" : System.FilePath)
  if !(← corpus.pathExists) then
    IO.println "SKIP corpus tier: test/fixtures/tla-frontend/accepted/diamond is absent"
    return
  let provider := Shell.Tla.SourceProvider.borrowedDirectory corpus
  for name in ["DiamondRoot", "DiamondLeft", "DiamondRight", "DiamondBase"] do
    match ← provider.readDependency (moduleName name) with
    | .error error =>
        check fails s!"corpus: {name} reads" false (Shell.Tla.SourceReadError.message error)
    | .ok unit =>
        check fails s!"corpus: {name} reads" true
        check fails s!"corpus: {name} digest stable"
          (Core.Tla.SourceUnit.consistent unit &&
            unit.contentSha256.length == 64)


/-! ## Resolver harness -/

/-- The empty range used by stub declarations. -/
def zeroRange : Core.Tla.SourceRange :=
  { start := { offset := 0, line := 1, column := 1 }
    stop := { offset := 0, line := 1, column := 1 } }

/-- A stub dependency site at `line`. -/
def rangeAt (line : Nat) : Core.Tla.SourceRange :=
  { start := { offset := 0, line, column := 1 }
    stop := { offset := 0, line, column := 1 } }

/-- A stub `EXTENDS` declaration, parsed by TF2's projection. -/
def extendsDecl (dependency : String) (isLocal : Bool := false)
    (line : Nat := 3) : Core.Tla.Declaration :=
  .«extends»
    { modules := #[{ name := moduleName dependency, range := rangeAt line }]
      «local» := isLocal
      range := rangeAt line }

/-- A stub instance declaration; `name` selects the named form. -/
def instanceDecl (dependency : String) (name : Option String := none)
    (isLocal : Bool := false)
    (substitutions : Array Core.Tla.Substitution := #[])
    (line : Nat := 3) : Core.Tla.Declaration :=
  .«instance»
    { name
      moduleName := moduleName dependency
      substitutions
      «local» := isLocal
      range := rangeAt line }

/-- A stub module for resolver scenarios: the declared header name plus the
dependency declarations the parser reports. Parser behavior itself is covered by
the TF2 suite; these scenarios exercise graph construction. -/
structure StubModule where
  declared : String
  declarations : Array Core.Tla.Declaration := #[]

/-- The smallest lossless tree a stub outcome can carry. -/
def emptyCst : Core.Tla.CstModule :=
  { root :=
      .token
        { kind := .eof
          spelling := ""
          range := zeroRange
          leadingTrivia := #[]
          trailingTrivia := #[] } }

def stubOutcome (stub : StubModule) : Core.Tla.ParseOutcome :=
  { cst := emptyCst
    module? :=
      some
        { name := moduleName stub.declared
          declarations := stub.declarations
          range := zeroRange }
    diagnostics := #[] }

def stubFailure (unit : Core.Tla.SourceUnit) : Core.Tla.ParseOutcome :=
  { cst := emptyCst
    module? := none
    diagnostics :=
      #[Diagnostic.error "SPEC-STUB-UNKNOWN" .parse
        s!"resolver stub has no module for '{unit.logicalPath}'"
        (SourceLocation.ofUnit unit zeroRange)] }

def stubParser (stubs : List (String × StubModule)) : Shell.Tla.ParseModule :=
  fun unit =>
    match stubs.find? (fun entry => entry.1 == unit.logicalPath) with
    | some entry => pure (stubOutcome entry.2)
    | none => pure (stubFailure unit)

def countingProvider (reads : IO.Ref (List String))
    (inner : Shell.Tla.SourceProvider) : Shell.Tla.SourceProvider :=
  { readRoot := fun reference => do
      reads.modify (fun log => log ++ [reference.moduleName.name])
      inner.readRoot reference
    readDependency := fun name => do
      reads.modify (fun log => log ++ [name.name])
      inner.readDependency name
    resolveStandard := inner.resolveStandard }

def countingParse (parses : IO.Ref (List String))
    (inner : Shell.Tla.ParseModule) : Shell.Tla.ParseModule :=
  fun unit => do
    parses.modify (fun log => log ++ [unit.logicalPath])
    inner unit

def resolverConfig (provider : Shell.Tla.SourceProvider)
    (stubs : List (String × StubModule))
    (limits : Shell.Tla.ResolverLimits)
    (reads parses : IO.Ref (List String)) : Shell.Tla.ResolverConfig :=
  { provider := countingProvider reads provider
    parse := countingParse parses (stubParser stubs)
    limits }

/-- Logical graph shape without provider origins, for adapter-equivalence
checks. -/
structure EdgeShape where
  owner : String
  dependency : String
  kind : Core.Tla.DependencyKind
  resolution : Core.Tla.DependencyResolution
  «local» : Bool
  line : Nat
  order : Nat
  substitutions : Nat
  deriving BEq, Repr

structure GraphShape where
  root : String
  modules : List (String × String)
  standards : List String
  edges : List EdgeShape
  deriving BEq, Repr

def shapeOf (graph : Core.Tla.ResolvedModuleGraph) : GraphShape :=
  { root := graph.root.name
    modules :=
      graph.sortedNodes.toList.map (fun node => (node.name.name, node.unit.contentSha256))
    standards := graph.standardNames.toList.map (fun name => name.name)
    edges :=
      graph.canonicalEdges.toList.map (fun edge =>
        { owner := edge.owner.name
          dependency := edge.dependency.name
          kind := edge.kind
          resolution := edge.resolution
          «local» := edge.«local»
          line := edge.range.start.line
          order := edge.declarationOrder
          substitutions := edge.substitutions.size }) }

def messageOf (failure : Shell.Tla.ResolverFailure) : String :=
  String.intercalate "; "
    (failure.diagnostics.toList.map (fun item => item.message))

def codesOf (failure : Shell.Tla.ResolverFailure) : List String :=
  failure.diagnostics.toList.map (fun item => item.code)

def hasCode (failure : Shell.Tla.ResolverFailure) (code : String) : Bool :=
  (codesOf failure).any (fun item => item == code)

/-! ## Resolver graph cases -/

def scenarioResolverDiamond (fails : Failures) : IO Unit := do
  let sources : Array (Core.Tla.ModuleName × String) := #[
    (moduleName "DiamondRoot", moduleText "DiamondRoot" "EXTENDS DiamondLeft, DiamondRight"),
    (moduleName "DiamondLeft", moduleText "DiamondLeft" "EXTENDS DiamondBase"),
    (moduleName "DiamondRight", moduleText "DiamondRight" "EXTENDS DiamondBase"),
    (moduleName "DiamondBase", moduleText "DiamondBase" "VARIABLE shared")]
  let stubs : List (String × StubModule) := [
    ("DiamondRoot.tla",
      { declared := "DiamondRoot", declarations := #[extendsDecl "DiamondLeft", extendsDecl "DiamondRight"] }),
    ("DiamondLeft.tla", { declared := "DiamondLeft", declarations := #[extendsDecl "DiamondBase"] }),
    ("DiamondRight.tla", { declared := "DiamondRight", declarations := #[extendsDecl "DiamondBase"] }),
    ("DiamondBase.tla", { declared := "DiamondBase" })]
  let reads ← IO.mkRef ([] : List String)
  let parses ← IO.mkRef ([] : List String)
  let config := resolverConfig (Shell.Tla.SourceProvider.inline sources) stubs {} reads parses
  match ← Shell.Tla.resolve config
      (Shell.Tla.ModuleRef.ofModuleName (moduleName "DiamondRoot")) with
  | .error failure =>
      check fails "resolver diamond: resolves" false (messageOf failure)
  | .ok graph =>
      check fails "resolver diamond: four nodes" (graph.nodes.size == 4)
      check fails "resolver diamond: four edges" (graph.edges.size == 4)
      let readLog ← reads.get
      check fails "resolver diamond: reads each module once"
        (readLog == ["DiamondRoot", "DiamondLeft", "DiamondBase", "DiamondRight"])
        (String.intercalate "," readLog)
      let parseLog ← parses.get
      check fails "resolver diamond: parses each module once"
        (parseLog == ["DiamondRoot.tla", "DiamondLeft.tla", "DiamondBase.tla", "DiamondRight.tla"])
        (String.intercalate "," parseLog)
      check fails "resolver diamond: canonical modules"
        (graph.sortedNodes.toList.map (fun node => node.name.name)
          == ["DiamondBase", "DiamondLeft", "DiamondRight", "DiamondRoot"])
      check fails "resolver diamond: canonical edges"
        (graph.canonicalEdges.toList.map (fun edge => (edge.owner.name, edge.dependency.name))
          == [("DiamondLeft", "DiamondBase"), ("DiamondRight", "DiamondBase"),
              ("DiamondRoot", "DiamondLeft"), ("DiamondRoot", "DiamondRight")])
      check fails "resolver diamond: local resolution"
        (graph.edges.all (fun edge => edge.resolution == .localSource))
      check fails "resolver diamond: capture digests stable"
        (graph.nodes.all (fun node =>
          Core.Tla.SourceUnit.consistent node.unit &&
            node.unit.contentSha256.length == 64))

def scenarioResolverCycle (fails : Failures) : IO Unit := do
  let sources : Array (Core.Tla.ModuleName × String) := #[
    (moduleName "CycleA", moduleText "CycleA" "EXTENDS CycleB"),
    (moduleName "CycleB", moduleText "CycleB" "EXTENDS CycleA")]
  let stubs : List (String × StubModule) := [
    ("CycleA.tla", { declared := "CycleA", declarations := #[extendsDecl "CycleB"] }),
    ("CycleB.tla", { declared := "CycleB", declarations := #[extendsDecl "CycleA"] })]
  let reads ← IO.mkRef ([] : List String)
  let parses ← IO.mkRef ([] : List String)
  let config := resolverConfig (Shell.Tla.SourceProvider.inline sources) stubs {} reads parses
  match ← Shell.Tla.resolve config
      (Shell.Tla.ModuleRef.ofModuleName (moduleName "CycleA")) with
  | .ok _ =>
      check fails "resolver cycle: rejected" false
  | .error failure =>
      check fails "resolver cycle: diagnostic code"
        (codesOf failure == ["TLA-GRAPH-CYCLE"]) (messageOf failure)
      check fails "resolver cycle: complete bounded path"
        ((failure.diagnostics.toList.map (fun item => item.message))
          == ["dependency cycle detected: CycleA -> CycleB -> CycleA"])
      check fails "resolver cycle: structured cycle argument"
        (failure.diagnostics.toList.any (fun item =>
          (item.arguments.toList.map (fun argument => argument.2)).contains
            "CycleA -> CycleB -> CycleA"))
      check fails "resolver cycle: both cycle edges located"
        (failure.diagnostics.toList.all (fun item => item.related.size == 2))

def scenarioResolverMissing (fails : Failures) : IO Unit := do
  let sources : Array (Core.Tla.ModuleName × String) := #[
    (moduleName "MissingRoot", moduleText "MissingRoot" "EXTENDS NoSuchModule")]
  let stubs : List (String × StubModule) := [
    ("MissingRoot.tla", { declared := "MissingRoot", declarations := #[extendsDecl "NoSuchModule"] })]
  let reads ← IO.mkRef ([] : List String)
  let parses ← IO.mkRef ([] : List String)
  let config := resolverConfig (Shell.Tla.SourceProvider.inline sources) stubs {} reads parses
  match ← Shell.Tla.resolve config
      (Shell.Tla.ModuleRef.ofModuleName (moduleName "MissingRoot")) with
  | .ok _ =>
      check fails "resolver missing: rejected" false
  | .error failure =>
      check fails "resolver missing: diagnostic code"
        (codesOf failure == ["TLA-GRAPH-MISSING-MODULE"]) (messageOf failure)

def scenarioResolverIdentity (fails : Failures) : IO Unit := do
  -- Declared root identity must equal the requested identity.
  let rootSources : Array (Core.Tla.ModuleName × String) := #[
    (moduleName "MismatchRoot", moduleText "DifferentName" "MismatchOp == TRUE")]
  let rootStubs : List (String × StubModule) := [
    ("MismatchRoot.tla", { declared := "DifferentName" })]
  let rootReads ← IO.mkRef ([] : List String)
  let rootParses ← IO.mkRef ([] : List String)
  let rootConfig := resolverConfig (Shell.Tla.SourceProvider.inline rootSources)
    rootStubs {} rootReads rootParses
  match ← Shell.Tla.resolve rootConfig
      (Shell.Tla.ModuleRef.ofModuleName (moduleName "MismatchRoot")) with
  | .ok _ =>
      check fails "resolver identity: root mismatch rejected" false
  | .error failure =>
      check fails "resolver identity: root mismatch code"
        (codesOf failure == ["TLA-GRAPH-ROOT-HEADER-MISMATCH"]) (messageOf failure)

  -- A dependency source that declares a fresh foreign identity is rejected.
  let aliasSources : Array (Core.Tla.ModuleName × String) := #[
    (moduleName "AliasRoot", moduleText "AliasRoot" "EXTENDS Alias"),
    (moduleName "Alias", moduleText "Other" "AliasOp == TRUE")]
  let aliasStubs : List (String × StubModule) := [
    ("AliasRoot.tla", { declared := "AliasRoot", declarations := #[extendsDecl "Alias"] }),
    ("Alias.tla", { declared := "Other" })]
  let aliasReads ← IO.mkRef ([] : List String)
  let aliasParses ← IO.mkRef ([] : List String)
  let aliasConfig := resolverConfig (Shell.Tla.SourceProvider.inline aliasSources)
    aliasStubs {} aliasReads aliasParses
  match ← Shell.Tla.resolve aliasConfig
      (Shell.Tla.ModuleRef.ofModuleName (moduleName "AliasRoot")) with
  | .ok _ =>
      check fails "resolver identity: dependency mismatch rejected" false
  | .error failure =>
      check fails "resolver identity: dependency mismatch code"
        (codesOf failure == ["TLA-GRAPH-DEPENDENCY-HEADER-MISMATCH"]) (messageOf failure)

  -- An alias that re-declares a captured identity is a duplicate, not a reuse.
  let dupSources : Array (Core.Tla.ModuleName × String) := #[
    (moduleName "DupRoot", moduleText "DupRoot" "EXTENDS DupShared, DupAlias"),
    (moduleName "DupShared", moduleText "DupShared" "VARIABLE dupState"),
    (moduleName "DupAlias", moduleText "DupShared" "VARIABLE aliasState")]
  let dupStubs : List (String × StubModule) := [
    ("DupRoot.tla", { declared := "DupRoot", declarations := #[extendsDecl "DupShared", extendsDecl "DupAlias"] }),
    ("DupShared.tla", { declared := "DupShared" }),
    ("DupAlias.tla", { declared := "DupShared" })]
  let dupReads ← IO.mkRef ([] : List String)
  let dupParses ← IO.mkRef ([] : List String)
  let dupConfig := resolverConfig (Shell.Tla.SourceProvider.inline dupSources)
    dupStubs {} dupReads dupParses
  match ← Shell.Tla.resolve dupConfig
      (Shell.Tla.ModuleRef.ofModuleName (moduleName "DupRoot")) with
  | .ok _ =>
      check fails "resolver identity: duplicate rejected" false
  | .error failure =>
      check fails "resolver identity: duplicate code"
        (codesOf failure == ["TLA-GRAPH-DUPLICATE-MODULE"]) (messageOf failure)
      check fails "resolver identity: duplicate names the original source"
        (failure.diagnostics.toList.any (fun item =>
          item.related.toList.any (fun related =>
            (related.location.logicalPath == "DupShared.tla") ||
              (related.message.contains "DupShared.tla"))))

def scenarioResolverStandard (fails : Failures) : IO Unit := do
  let sources : Array (Core.Tla.ModuleName × String) := #[
    (moduleName "StdRoot", moduleText "StdRoot" "EXTENDS Naturals, LocalBase, Integers"),
    (moduleName "LocalBase", moduleText "LocalBase" "VARIABLE base")]
  let stubs : List (String × StubModule) := [
    ("StdRoot.tla",
      { declared := "StdRoot",
        declarations := #[extendsDecl "Naturals", extendsDecl "LocalBase", extendsDecl "Integers"] }),
    ("LocalBase.tla", { declared := "LocalBase" })]
  let reads ← IO.mkRef ([] : List String)
  let parses ← IO.mkRef ([] : List String)
  let config := resolverConfig (Shell.Tla.SourceProvider.inline sources) stubs {} reads parses
  match ← Shell.Tla.resolve config
      (Shell.Tla.ModuleRef.ofModuleName (moduleName "StdRoot")) with
  | .error failure =>
      check fails "resolver standard: resolves" false (messageOf failure)
  | .ok graph =>
      check fails "resolver standard: first-use order"
        (graph.standardNames.toList.map (fun name => name.name) == ["Naturals", "Integers"])
      check fails "resolver standard: only local nodes captured"
        (graph.sortedNodes.toList.map (fun node => node.name.name) == ["LocalBase", "StdRoot"])
      check fails "resolver standard: resolution kinds"
        (graph.canonicalEdges.toList.map (fun edge => edge.resolution)
          == [.standardCatalog, .localSource, .standardCatalog])
      check fails "resolver standard: provider probed before the catalog"
        ((← reads.get) == ["StdRoot", "Naturals", "LocalBase", "Integers"])

  -- A local file for a catalog name shadows the catalog: the provider is asked
  -- first and only a missing file falls back to the pinned identity.
  let shadowSources : Array (Core.Tla.ModuleName × String) := #[
    (moduleName "ShadowRoot", moduleText "ShadowRoot" "EXTENDS Naturals"),
    (moduleName "Naturals", moduleText "Naturals" "ShadowOp == TRUE")]
  let shadowStubs : List (String × StubModule) := [
    ("ShadowRoot.tla", { declared := "ShadowRoot", declarations := #[extendsDecl "Naturals"] }),
    ("Naturals.tla", { declared := "Naturals" })]
  let shadowReads ← IO.mkRef ([] : List String)
  let shadowParses ← IO.mkRef ([] : List String)
  let shadowConfig := resolverConfig (Shell.Tla.SourceProvider.inline shadowSources)
    shadowStubs {} shadowReads shadowParses
  match ← Shell.Tla.resolve shadowConfig
      (Shell.Tla.ModuleRef.ofModuleName (moduleName "ShadowRoot")) with
  | .error failure =>
      check fails "resolver standard: shadowing resolves" false (messageOf failure)
  | .ok graph =>
      check fails "resolver standard: shadowing captures a local node"
        (graph.sortedNodes.toList.map (fun node => node.name.name) == ["Naturals", "ShadowRoot"])
      check fails "resolver standard: shadowing uses no catalog identity"
        (graph.standardModules.isEmpty &&
          graph.edges.all (fun edge => edge.resolution == .localSource))

def scenarioResolverLimits (fails : Failures) : IO Unit := do
  let sources : Array (Core.Tla.ModuleName × String) := #[
    (moduleName "LimitRoot", moduleText "LimitRoot" "EXTENDS LimitA"),
    (moduleName "LimitA", moduleText "LimitA" "EXTENDS LimitB"),
    (moduleName "LimitB", moduleText "LimitB" "LimitOp == TRUE")]
  let stubs : List (String × StubModule) := [
    ("LimitRoot.tla", { declared := "LimitRoot", declarations := #[extendsDecl "LimitA"] }),
    ("LimitA.tla", { declared := "LimitA", declarations := #[extendsDecl "LimitB"] }),
    ("LimitB.tla", { declared := "LimitB" })]
  let runWith (limits : Shell.Tla.ResolverLimits) : IO (List String) := do
    let reads ← IO.mkRef ([] : List String)
    let parses ← IO.mkRef ([] : List String)
    let config := resolverConfig (Shell.Tla.SourceProvider.inline sources) stubs limits reads parses
    match ← Shell.Tla.resolve config
        (Shell.Tla.ModuleRef.ofModuleName (moduleName "LimitRoot")) with
    | .ok _ => pure []
    | .error failure => pure (codesOf failure)
  check fails "resolver limits: depth bound"
    ((← runWith { maxDependencyDepth := 1 }) == ["TLA-GRAPH-DEPENDENCY-TOO-DEEP"])
  check fails "resolver limits: module bound"
    ((← runWith { maxModules := 2 }) == ["TLA-GRAPH-TOO-MANY-MODULES"])
  check fails "resolver limits: edge bound"
    ((← runWith { maxDependencyEdges := 1 }) == ["TLA-GRAPH-TOO-MANY-EDGES"])

def scenarioResolverInstances (fails : Failures) : IO Unit := do
  let substitution : Core.Tla.Substitution :=
    { formal := "x"
      formalArity := 0
      formalRange := zeroRange
      actual := .name ⟨none, "y", zeroRange⟩ zeroRange
      range := zeroRange }
  let sources : Array (Core.Tla.ModuleName × String) := #[
    (moduleName "InstRoot", moduleText "InstRoot" "I == INSTANCE InstBase WITH x <- y"),
    (moduleName "InstBase", moduleText "InstBase" "VARIABLE x")]
  let stubs : List (String × StubModule) := [
    ("InstRoot.tla",
      { declared := "InstRoot",
        declarations :=
          #[instanceDecl "InstBase" (some "I") true #[substitution] 3,
            instanceDecl "InstBase" none false #[] 4] }),
    ("InstBase.tla", { declared := "InstBase" })]
  let reads ← IO.mkRef ([] : List String)
  let parses ← IO.mkRef ([] : List String)
  let config := resolverConfig (Shell.Tla.SourceProvider.inline sources) stubs {} reads parses
  match ← Shell.Tla.resolve config
      (Shell.Tla.ModuleRef.ofModuleName (moduleName "InstRoot")) with
  | .error failure =>
      check fails "resolver instances: resolves" false (messageOf failure)
  | .ok graph =>
      check fails "resolver instances: two edges"
        (graph.edges.size == 2)
      check fails "resolver instances: kinds, LOCAL, order retained"
        (graph.canonicalEdges.toList.map (fun edge =>
            (edge.kind, edge.«local», edge.declarationOrder, edge.range.start.line))
          == [(.namedInstance, true, 0, 3), (.unnamedInstance, false, 1, 4)])
      check fails "resolver instances: substitutions retained"
        (graph.canonicalEdges.toList.map (fun edge => edge.substitutions) ==
          #[#[substitution], #[]].toList)

def scenarioResolverFilesystem (fails : Failures) : IO Unit := do
  if System.Platform.isWindows then
    IO.println "SKIP resolver filesystem case on Windows"
    return
  let root ← IO.FS.createTempDir
  writeModule root "FsRoot" "EXTENDS Alias"
  writeModule root "AliasTarget" "TargetOp == TRUE"
  let stubs : List (String × StubModule) := [
    ("FsRoot.tla", { declared := "FsRoot", declarations := #[extendsDecl "Alias"] }),
    ("AliasTarget.tla", { declared := "AliasTarget" })]
  match ← makeSymlink (root / "AliasTarget.tla") (root / "Alias.tla") with
  | .error error =>
      check fails "resolver filesystem: symlink case created" false error
  | .ok () =>
      let reads ← IO.mkRef ([] : List String)
      let parses ← IO.mkRef ([] : List String)
      let config := resolverConfig (Shell.Tla.SourceProvider.borrowedDirectory root)
        stubs {} reads parses
      match ← Shell.Tla.resolve config
          (Shell.Tla.ModuleRef.ofModuleName (moduleName "FsRoot")) with
      | .ok _ =>
          check fails "resolver filesystem: symlink leaves no partial graph" false
      | .error failure =>
          check fails "resolver filesystem: symlink is a read failure"
            (codesOf failure == ["TLA-GRAPH-DEPENDENCY-READ"]) (messageOf failure)
  IO.FS.removeDirAll root

/-- A borrowed dependency mutated between two resolutions must be captured
again: no node is reused from a stale read, and the changed bytes produce a
changed source identity. -/
def scenarioResolverMutation (fails : Failures) : IO Unit := do
  let root ← IO.FS.createTempDir
  writeModule root "MutRoot" "EXTENDS MutBase"
  writeModule root "MutBase" "VARIABLE before"
  let stubs : List (String × StubModule) := [
    ("MutRoot.tla",
      { declared := "MutRoot", declarations := #[extendsDecl "MutBase"] }),
    ("MutBase.tla", { declared := "MutBase" })]
  let reads ← IO.mkRef ([] : List String)
  let parses ← IO.mkRef ([] : List String)
  let config := resolverConfig (Shell.Tla.SourceProvider.borrowedDirectory root)
    stubs {} reads parses
  let rootRef := Shell.Tla.ModuleRef.ofModuleName (moduleName "MutRoot")
  let digest (graph : Core.Tla.ResolvedModuleGraph) (name : String) : Option String :=
    (graph.findNode? (moduleName name)).map (fun node => node.unit.contentSha256)
  match ← Shell.Tla.resolve config rootRef with
  | .error failure =>
      check fails "resolver mutation: first resolve" false (messageOf failure)
  | .ok first =>
      check fails "resolver mutation: base captured" (digest first "MutBase").isSome
      writeModule root "MutBase" "VARIABLE after"
      match ← Shell.Tla.resolve config rootRef with
      | .error failure =>
          check fails "resolver mutation: second resolve" false (messageOf failure)
      | .ok second =>
          check fails "resolver mutation: changed dependency is recaptured"
            (digest second "MutBase" != digest first "MutBase")
          check fails "resolver mutation: unchanged root digest"
            (digest second "MutRoot" == digest first "MutRoot")
          check fails "resolver mutation: one node per module"
            (second.nodes.size == 2)
  IO.FS.removeDirAll root

def scenarioResolverEquivalence (fails : Failures) : IO Unit := do
  let dir := ("./test/fixtures/tla-frontend/accepted/diamond" : System.FilePath)
  if !(← dir.pathExists) then
    IO.println "SKIP resolver equivalence: accepted/diamond is absent"
    return
  let stubs : List (String × StubModule) := [
    ("DiamondRoot.tla",
      { declared := "DiamondRoot", declarations := #[extendsDecl "DiamondLeft", extendsDecl "DiamondRight"] }),
    ("DiamondLeft.tla", { declared := "DiamondLeft", declarations := #[extendsDecl "DiamondBase"] }),
    ("DiamondRight.tla", { declared := "DiamondRight", declarations := #[extendsDecl "DiamondBase"] }),
    ("DiamondBase.tla", { declared := "DiamondBase" })]
  let rootRef := Shell.Tla.ModuleRef.ofModuleName (moduleName "DiamondRoot")
  let borrowedReads ← IO.mkRef ([] : List String)
  let borrowedParses ← IO.mkRef ([] : List String)
  let borrowedConfig := resolverConfig (Shell.Tla.SourceProvider.borrowedDirectory dir)
    stubs {} borrowedReads borrowedParses
  match ← Shell.Tla.resolve borrowedConfig rootRef with
  | .error failure =>
      check fails "resolver equivalence: borrowed resolves" false (messageOf failure)
  | .ok borrowed =>
      let mut sources : Array (Core.Tla.ModuleName × String) := #[]
      for name in ["DiamondBase", "DiamondLeft", "DiamondRight", "DiamondRoot"] do
        let text ← IO.FS.readFile (dir / (name ++ ".tla"))
        sources := sources.push (moduleName name, text)
      let inlineReads ← IO.mkRef ([] : List String)
      let inlineParses ← IO.mkRef ([] : List String)
      let inlineConfig := resolverConfig (Shell.Tla.SourceProvider.inline sources)
        stubs {} inlineReads inlineParses
      match ← Shell.Tla.resolve inlineConfig rootRef with
      | .error failure =>
          check fails "resolver equivalence: inline resolves" false (messageOf failure)
      | .ok inline =>
          check fails "resolver equivalence: equal logical graphs"
            (shapeOf borrowed == shapeOf inline)
          check fails "resolver equivalence: distinct origins"
            (borrowed.nodes.all (fun node => node.unit.origin == .borrowedDirectory) &&
              inline.nodes.all (fun node => node.unit.origin == .inlineSourceMap))

def scenarioResolverCorpus (fails : Failures) : IO Unit := do
  let dir := ("./test/fixtures/tla-frontend/accepted/generic-extends" : System.FilePath)
  if !(← dir.pathExists) then
    IO.println "SKIP resolver corpus: accepted/generic-extends is absent"
    return
  let stubs : List (String × StubModule) := [
    ("GenericExtendsRoot.tla",
      { declared := "GenericExtendsRoot", declarations := #[extendsDecl "GenericExtendsBase"] }),
    ("GenericExtendsBase.tla",
      { declared := "GenericExtendsBase", declarations := #[extendsDecl "Integers"] })]
  let reads ← IO.mkRef ([] : List String)
  let parses ← IO.mkRef ([] : List String)
  let config := resolverConfig (Shell.Tla.SourceProvider.borrowedDirectory dir)
    stubs {} reads parses
  match ← Shell.Tla.resolve config
      (Shell.Tla.ModuleRef.ofModuleName (moduleName "GenericExtendsRoot")) with
  | .error failure =>
      check fails "resolver corpus: generic-extends resolves" false (messageOf failure)
  | .ok graph =>
      check fails "resolver corpus: modules"
        (graph.sortedNodes.toList.map (fun node => node.name.name)
          == ["GenericExtendsBase", "GenericExtendsRoot"])
      check fails "resolver corpus: standard modules"
        (graph.standardNames.toList.map (fun name => name.name) == ["Integers"])
      check fails "resolver corpus: canonical edges"
        (graph.canonicalEdges.toList.map (fun edge =>
            (edge.owner.name, edge.dependency.name, edge.range.start.line))
          == [("GenericExtendsBase", "Integers", 3), ("GenericExtendsRoot", "GenericExtendsBase", 3)])
      check fails "resolver corpus: manifest digests stable"
        (graph.sourceIdentities.all (fun identity => identity.contentSha256.length == 64))

def run : IO UInt32 := do
  let fails ← IO.mkRef ([] : List String)
  scenarioLogicalNames fails
  scenarioInlineProvider fails
  scenarioBorrowedProvider fails
  scenarioStandardCatalog fails
  scenarioCorpus fails
  scenarioResolverDiamond fails
  scenarioResolverCycle fails
  scenarioResolverMissing fails
  scenarioResolverIdentity fails
  scenarioResolverStandard fails
  scenarioResolverLimits fails
  scenarioResolverInstances fails
  scenarioResolverFilesystem fails
  scenarioResolverMutation fails
  scenarioResolverEquivalence fails
  scenarioResolverCorpus fails
  let failures ← fails.get
  if failures.isEmpty then
    IO.println "TLA MODULE RESOLVER SPEC GREEN"
    return 0
  else
    for failure in failures do
      IO.eprintln s!"FAIL {failure}"
    IO.eprintln s!"{failures.length} FAILURES"
    return 1

end TlaModuleResolverSpec

def main : IO UInt32 :=
  TlaModuleResolverSpec.run
