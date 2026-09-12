import Core.Tla.Diagnostic
import Core.Tla.Graph
import Core.Tla.Level
import Core.Tla.Names
import Core.Tla.Parser

/-!
# TLA+ semantic elaboration (`Core/Tla/Elaboration.lean`)

Names, `EXTENDS` visibility, operator arity, `INSTANCE` substitution,
effective model facts, and expression levels for the general TLA+ frontend
(`Docs/model-interface-compiler/tla-frontend-design.md`, §13 "Semantic
elaboration", §14 "`EXTENDS` semantics", §15 "`INSTANCE` and substitution",
§16 "Effective model facts", §20 "Diagnostics", and §21 "Resource and security
limits"; task packages TF4 and TF5 in
`Docs/model-interface-compiler/tla-frontend-tasks.md`).

The elaborator is pure over one resolved module graph
(`Core.Tla.ResolvedModuleGraph`): no IO, no filesystem access, no second source
read, and no re-lexing of captured text. Every captured module already carries
its normalized bytes (`Core.Tla.SourceUnit`) and its parsed declarations
(`Core.Tla.ParsedModule`), and every module-level dependency is a graph edge.

Revision-1 decisions recorded here:

* *Analysis-local symbols.* Each declaration gets a `SymbolId` numbered in
  tabulation order (module discovery order, then source order). Identifiers are
  never persisted; `Core.Tla.Names` keeps `declaredIn`, the declaration range,
  the import path, and the source hashes instead.
* *Closures, not concatenation.* Effective declarations are computed by the
  design's `stableUnique` recursion: for each directly extended module in source
  order its exported declarations, then the module's own declarations. The same
  resolved declaration reached through a diamond is deduplicated; two different
  declarations with one visible name are an ambiguity with primary and related
  declaration locations. `LOCAL` declarations stay visible inside their own
  module and are never re-exported.
* *Language-defined operators.* The revision-1 profile's operator table
  (`Core.Tla.ParserProfile`) owns the operator spellings the language itself
  provides, including the structural operators the parser writes in canonical
  spelling (`'`, `[]`, `<>`, `~>`, `[]_`, `<<>>_`, `ENABLED`, `UNCHANGED`,
  `WF_`, `SF_`, `DOMAIN`, `SUBSET`, `UNION`). A local declaration always
  shadows a language-defined spelling.
* *Standard-module facts.* Revision 1 seeds the four declaration facts the
  frozen corpus exercises (`Nat`, `Int`, `Append`, `Cardinality`) with the
  standard module each one comes from. Transitive standard-module visibility
  and the remaining catalog facts belong to the catalog-sourcing decision
  (design §30 item 5); a name whose facts are still pending is not invented
  here.
* *Instances, not concatenation.* A named `INSTANCE` contributes only its own
  qualified name (`I!Op`); an unnamed one exposes the instantiated module's
  operators unqualified and re-exports them through `EXTENDS`, unless the
  instance or the declaration is `LOCAL`. Every visible constant and variable
  of the instantiated module is substituted, explicitly by `WITH` or implicitly
  by a same-named 0-ary declaration of the instantiating module, so a child
  variable never becomes root state and a missing or illegal actual is a
  `substitution`-stage error instead of a guess. Substitution keeps the child
  declaration's origin, range, logical path, and source hash, and a chain of
  instances composes through per-site frames that the level pass follows
  (revision 1 bounds every substitution actual at `constant` or `state`
  level).
* *Bound names shadow declarations.* Formal parameters, `LET` definitions,
  quantifier and comprehension binders, `CHOOSE` names, and function binders
  take precedence over module-level declarations inside their scope. Duplicate
  declarations inside one module, ambiguous imports, unknown names, and arity
  mismatches are errors in the `nameResolution` stage.
* *Levels.* Levels are classified over the whole graph as the least fixpoint of
  the syntax-directed rules in `Core.Tla.Level`, starting from the bottom of the
  lattice. Variables start at `state`; every other symbol starts at `constant`.
  `ASSUME`, `ASSUMPTION`, and `AXIOM` statements must classify as `constant`;
  a violation is a `level`-stage error (profile §7.3).
* *Bounds.* Tabulation is bounded by `maxDeclarations` and `maxSymbols`,
  dependency traversal by an explicit fuel count, expression traversal by an
  explicit per-module fuel count derived from the captured bytes, the level
  fixpoint by the lattice height times the symbol count, and diagnostics by
  `maxDiagnostics` and `maxDiagnosticBytes`. Exhausting a bound is a `limit`
  failure, never a guessed result.
-/

namespace Core.Tla

/-! ## Limits -/

/-- Elaboration budgets. `maxDeclarations`, `maxDiagnostics`, and
`maxDiagnosticBytes` carry the revision-1 profile values; `maxSymbols` is the
frontend design's accumulated-symbol budget, checked at every allocation. -/
structure ElaborationLimits where
  /-- Maximum module-level declarations tabulated across every captured module. -/
  maxDeclarations : Nat := 4096
  /-- Maximum symbols allocated while tabulating every captured module. -/
  maxSymbols : Nat := 262144
  /-- Maximum accumulated diagnostics. -/
  maxDiagnostics : Nat := 64
  /-- Maximum accumulated diagnostic bytes. -/
  maxDiagnosticBytes : Nat := 1024 * 1024
  deriving Repr, BEq, DecidableEq

namespace ElaborationLimits

/-- Diagnostic budgets derived from the elaboration limits. -/
def diagnosticLimits (limits : ElaborationLimits) : DiagnosticLimits :=
  { maxCount := limits.maxDiagnostics, maxBytes := limits.maxDiagnosticBytes }

end ElaborationLimits

/-! ## Diagnostic codes -/

namespace ElabCode

def duplicateDeclaration : String := "TLA-ELAB-DUPLICATE-DECLARATION"
def ambiguousImport : String := "TLA-ELAB-AMBIGUOUS-IMPORT"
def unknownName : String := "TLA-ELAB-UNKNOWN-NAME"
def arityMismatch : String := "TLA-ELAB-ARITY-MISMATCH"
def assumptionLevel : String := "TLA-ELAB-ASSUMPTION-LEVEL"
def substitutionMissing : String := "TLA-ELAB-SUBSTITUTION-MISSING"
def substitutionInvalid : String := "TLA-ELAB-SUBSTITUTION-INVALID"
def substitutionDuplicate : String := "TLA-ELAB-SUBSTITUTION-DUPLICATE"
def substitutionArity : String := "TLA-ELAB-SUBSTITUTION-ARITY"
def substitutionLevel : String := "TLA-ELAB-SUBSTITUTION-LEVEL"
def declarationLimit : String := "TLA-ELAB-DECLARATION-LIMIT"
def symbolLimit : String := "TLA-ELAB-SYMBOL-LIMIT"
def fuelExhausted : String := "TLA-ELAB-FUEL-EXHAUSTED"
def diagnosticsTruncated : String := "TLA-ELAB-DIAGNOSTICS-TRUNCATED"

/-- `true` for a code that reports a resource bound rather than malformed input. -/
def isLimit (code : String) : Bool :=
  code == declarationLimit || code == symbolLimit ||
    code == fuelExhausted || code == diagnosticsTruncated

/-- Substitution diagnostics, in the order the substitution stage raises them.
Every one classifies as malformed: they mirror a reference-tool rejection, or
the uniform revision-1 level bound recorded in the language profile. -/
def substitutionCodes : List String :=
  [substitutionMissing, substitutionInvalid, substitutionDuplicate,
   substitutionArity, substitutionLevel]

/-- Corpus classification of one diagnostic code: `limit` for a resource bound
and `malformed` for every substitution or name-resolution rejection
(`tla-language-profile.md` §10.2). -/
def reason (code : String) : String :=
  if isLimit code then "limit" else "malformed"

end ElabCode

/-! ## Language-defined operator facts -/

/-- One language-defined operator identity: canonical spelling, the argument
counts the language admits, and its level. -/
structure LanguageOperator where
  name : String
  arities : Array Nat
  level : Level
  deriving Repr, BEq

/-- The profile operator table as language operator facts. Every entry is
`constant` level except the temporal and action spellings rewritten below; a
spelling with both a prefix and an infix entry (`-`) keeps both argument
counts. -/
private def profileOperatorFacts : Array LanguageOperator :=
  ParserProfile.revisionOneOperators.foldl
    (fun facts entry =>
      let arity :=
        match entry.fixity with
        | .prefix => 1
        | .postfix => 1
        | .infix => 2
      match facts.find? (fun fact => fact.name == entry.canonical) with
      | some existing =>
          if existing.arities.contains arity then facts
          else facts.map fun fact =>
            if fact.name == entry.canonical then
              { fact with arities := fact.arities.push arity }
            else fact
      | none =>
          facts.push { name := entry.canonical, arities := #[arity],
                       level := .constant })
    #[]

/-- Language-defined operator facts for the revision-1 profile: the profile's
own operator table plus the structural spellings the parser writes in canonical
form. -/
def languageOperatorFacts : Array LanguageOperator :=
  let temporal := profileOperatorFacts.map fun fact =>
    match fact.name with
    | "[]" | "<>" | "~>" => { fact with level := .temporal }
    | _ => fact
  let structural : Array LanguageOperator := #[
    { name := "'", arities := #[1], level := .action },
    { name := "[]_", arities := #[2], level := .action },
    { name := "<<>>_", arities := #[2], level := .action },
    { name := "UNCHANGED", arities := #[1], level := .action },
    { name := "ENABLED", arities := #[1], level := .temporal },
    { name := "WF_", arities := #[2], level := .temporal },
    { name := "SF_", arities := #[2], level := .temporal },
    { name := "DOMAIN", arities := #[1], level := .constant },
    { name := "SUBSET", arities := #[1], level := .constant },
    { name := "UNION", arities := #[1], level := .constant },
    { name := "BOOLEAN", arities := #[0], level := .constant },
    { name := "STRING", arities := #[0], level := .constant }]
  structural.foldl
    (fun facts fact =>
      if facts.any (fun existing => existing.name == fact.name) then facts
      else facts.push fact)
    temporal

/-! ## Standard-module operator facts -/

/-- One standard-module declaration fact: operator name, arity, level, and the
standard module whose declarations provide it. -/
structure StandardOperatorFact where
  name : String
  arity : Nat
  level : Level
  module : ModuleName
  deriving Repr, BEq

/-- The seeded revision-1 standard-module facts. Only operators exercised by
the generic corpus and composed-source acceptance cases are modelled; growing
the catalog is the reviewed
catalog-revision decision of design §30 item 5
(`tla-language-profile.md` §6.3). -/
def standardOperatorFacts : Array StandardOperatorFact := #[
  { name := "Nat", arity := 0, level := .constant, module := ⟨"Naturals"⟩ },
  { name := "Int", arity := 0, level := .constant, module := ⟨"Integers"⟩ },
  { name := "Append", arity := 2, level := .constant, module := ⟨"Sequences"⟩ },
  { name := "Len", arity := 1, level := .constant, module := ⟨"Sequences"⟩ },
  { name := "Cardinality", arity := 1, level := .constant,
    module := ⟨"FiniteSets"⟩ }]

/-! ## Elaboration state -/

/-- One `INSTANCE` site: the parsed declaration plus how the module resolver
satisfied its target. A `standardCatalog` target carries no captured node. -/
private structure InstanceSite where
  declaration : InstanceDeclaration
  resolution : DependencyResolution
  deriving BEq

/-- One substitution frame. `site` is the `INSTANCE ... WITH` whose formal names
belong to the module being classified, and `viewer` is the module where that
site's actual expressions are written. Frames compose innermost first: the
next frame's formals are names of `viewer`, so a frame chain always ends in the
elaborated root.
-/
private structure InstanceFrame where
  site : InstanceSite
  viewer : ModuleName
  deriving BEq

/-- One module-level symbol. `name` is empty for an unnamed assumption or
theorem; such a symbol never participates in visible-name merging. -/
private structure SymbolInfo where
  symbol : SymbolId
  kind : SymbolKind
  name : String
  arity : Nat
  fixity : OperatorFixity
  localDeclaration : Bool
  declaredIn : ModuleName
  logicalPath : String
  declarationRange : SourceRange
  definition? : Option OperatorDefinition := none
  assumption? : Option Assumption := none
  theorem? : Option Theorem := none
  /-- The `INSTANCE` site of a `.instance` symbol. -/
  instanceSite? : Option InstanceSite := none

/-- One tabulated module: its own declarations and the dependencies it
contributed. `sourceBytes` bounds expression traversal for the module. -/
private structure ModuleTable where
  name : ModuleName
  logicalPath : String
  sourceBytes : Nat
  entries : Array SymbolInfo := #[]
  extendsEdges : Array ModuleEdge := #[]
  /-- Every declared `INSTANCE` site in source order. -/
  instanceSites : Array InstanceSite := #[]

/-- One effective declaration: the symbol, the module-name chain from the
elaborated root to the declaring module (root first), and the substitution
frames under which the declaration is instantiated. An empty frame chain is a
declaration visible through `EXTENDS` alone. -/
private structure ClosureEntry where
  info : SymbolInfo
  importPath : Array ModuleName
  frames : List InstanceFrame := []

namespace ClosureEntry

/-- Location of the declaration this entry came from. -/
def location (entry : ClosureEntry) : SourceLocation :=
  { moduleName := some entry.info.declaredIn
    logicalPath := entry.info.logicalPath
    range := entry.info.declarationRange }

end ClosureEntry

/-- The effective declarations of one module plus the standard modules its
non-local `EXTENDS` closure makes available. -/
private structure ClosureResult where
  entries : Array ClosureEntry := #[]
  /-- Standard modules visible inside this module. -/
  availableStandards : Array ModuleName := #[]
  /-- Standard modules this module re-exports to its importers. -/
  exportedStandards : Array ModuleName := #[]

/-- The elaboration accumulator. -/
private structure ElabState where
  limits : ElaborationLimits
  anchor : SourceLocation
  tables : Array ModuleTable := #[]
  closures : Array (ModuleName × ClosureResult) := #[]
  levels : Array (SymbolId × Level) := #[]
  buffer : DiagnosticBuffer := DiagnosticBuffer.empty
  nextSymbol : Nat := 0
  declarationCount : Nat := 0
  truncatedNotified : Bool := false
  halted : Bool := false

private abbrev ElabM := StateM ElabState

/-! ## Reporting -/

private def locationOfRange (table : ModuleTable) (range : SourceRange) :
    SourceLocation :=
  { moduleName := some table.name, logicalPath := table.logicalPath, range }

private def locationOfSymbol (info : SymbolInfo) : SourceLocation :=
  { moduleName := some info.declaredIn, logicalPath := info.logicalPath,
    range := info.declarationRange }

/-- Append one diagnostic, respecting the count and byte budgets. The first
refusal adds a single truncation notice carrying the dropped count. -/
private def report (diagnostic : Diagnostic) : ElabM Unit := do
  let state ← get
  let buffer := DiagnosticBuffer.push
    (ElaborationLimits.diagnosticLimits state.limits) state.buffer diagnostic
  if buffer.truncated && !state.truncatedNotified then
    let notice :=
      { Diagnostic.error ElabCode.diagnosticsTruncated .nameResolution
          "elaboration diagnostic budget exhausted; further diagnostics were dropped"
          state.anchor with
        arguments := #[("dropped", toString buffer.dropped)] }
    set { state with
          buffer := DiagnosticBuffer.pushForced buffer notice
          truncatedNotified := true }
  else
    set { state with buffer }

private def halt : ElabM Unit := do
  let state ← get
  set { state with halted := true }

/-- `true` once elaboration can no longer succeed: a limit bound was hit or an
error diagnostic was recorded. -/
private def failed (state : ElabState) : Bool :=
  state.halted ||
    state.buffer.diagnostics.any (fun diagnostic => diagnostic.hasErrorSeverity)

private def stageDone : ElabM Bool := do
  let state ← get
  return failed state

private def whenNotDone (action : ElabM Unit) : ElabM Unit := do
  let done ← stageDone
  if done then pure () else action

/-! ## Tabulation -/

private def expressionFuel (table : ModuleTable) : Nat :=
  4 * (table.sourceBytes + 1) + 256

private def allocateSymbol (table : ModuleTable) (kind : SymbolKind)
    (name : String) (arity : Nat) (fixity : OperatorFixity)
    (localDeclaration : Bool) (range : SourceRange) :
    ElabM (Option SymbolInfo) := do
  let state ← get
  if state.halted then
    return none
  else if state.nextSymbol ≥ state.limits.maxSymbols then do
    report ((Diagnostic.error ElabCode.symbolLimit .nameResolution
      s!"module '{table.name.name}' declares more symbols than the configured limit"
      (locationOfRange table range))
      |>.withArgument "limit" (toString state.limits.maxSymbols)
      |>.withArgument "module" table.name.name)
    halt
    return none
  else do
    let info : SymbolInfo :=
      { symbol := state.nextSymbol, kind, name, arity, fixity, localDeclaration,
        declaredIn := table.name, logicalPath := table.logicalPath,
        declarationRange := range }
    set { state with nextSymbol := state.nextSymbol + 1 }
    return some info

/-- Record one declaration in a module table. A definition completing a
`RECURSIVE` declaration of the same name and arity updates that symbol instead
of adding a second one; every other repeated visible name is a duplicate. -/
private def insertEntry (table : ModuleTable) (entry : SymbolInfo) :
    ElabM ModuleTable := do
  match table.entries.find? (fun existing =>
      !entry.name.isEmpty && existing.name == entry.name) with
  | none => return { table with entries := table.entries.push entry }
  | some existing =>
      if existing.kind == .recursive && entry.kind == .definition then
        if existing.arity == entry.arity then
          return { table with entries := table.entries.map fun other =>
            if other.symbol == existing.symbol then
              { other with fixity := entry.fixity, definition? := entry.definition? }
            else other }
        else do
          report ((Diagnostic.error ElabCode.arityMismatch .nameResolution
            s!"definition '{entry.name}' completes a RECURSIVE declaration with a different arity"
            (locationOfSymbol entry))
            |>.withRelated "the RECURSIVE declaration is here"
              (locationOfSymbol existing)
            |>.withArgument "name" entry.name
            |>.withArgument "expected" (toString existing.arity)
            |>.withArgument "actual" (toString entry.arity))
          return table
      else do
        report ((Diagnostic.error ElabCode.duplicateDeclaration .nameResolution
          s!"declaration '{entry.name}' duplicates an earlier declaration in module '{table.name.name}'"
          (locationOfSymbol entry))
          |>.withRelated "the earlier declaration is here"
            (locationOfSymbol existing)
          |>.withArgument "name" entry.name
          |>.withArgument "module" table.name.name)
        return table

private def tabulateDeclaration (table : ModuleTable)
    (declaration : Declaration) (inheritedLocal : Bool) :
    ElabM ModuleTable := do
  match declaration with
  | .constant _ names =>
      let mut current := table
      for declared in names do
        match ← allocateSymbol current .constant declared.name 0 .functional
            inheritedLocal declared.range with
        | some info => current ← insertEntry current info
        | none => pure ()
      return current
  | .variable _ names =>
      let mut current := table
      for declared in names do
        match ← allocateSymbol current .variable declared.name 0 .functional
            inheritedLocal declared.range with
        | some info => current ← insertEntry current info
        | none => pure ()
      return current
  | .recursive _ operators =>
      let mut current := table
      for declared in operators do
        match ← allocateSymbol current .recursive declared.name declared.arity
            .functional inheritedLocal declared.range with
        | some info => current ← insertEntry current info
        | none => pure ()
      return current
  | .operator definition =>
      match ← allocateSymbol table .definition definition.name
          definition.parameters.size definition.fixity inheritedLocal
          definition.nameRange with
      | some info => insertEntry table { info with definition? := some definition }
      | none => pure table
  | .«local» _ inner => tabulateDeclaration table inner true
  | .«instance» instanceDeclaration =>
      -- `LOCAL INSTANCE M` parses as a `LOCAL` wrapper around an instance, so
      -- the inherited flag has to reach the site: it decides whether the
      -- exposed copies and the instance symbol are re-exported through
      -- `EXTENDS`.
      let declaration :=
        if inheritedLocal then { instanceDeclaration with «local» := true }
        else instanceDeclaration
      return { table with
        instanceSites := table.instanceSites.push
          { declaration, resolution := .localSource } }
  | .assumption declared =>
      match ← allocateSymbol table .assumption (declared.name.getD "") 0
          .functional inheritedLocal declared.range with
      | some info => insertEntry table { info with assumption? := some declared }
      | none => pure table
  | .«theorem» declared =>
      match ← allocateSymbol table .theorem (declared.name.getD "") 0
          .functional inheritedLocal declared.range with
      | some info => insertEntry table { info with theorem? := some declared }
      | none => pure table
  | .«extends» _ => pure table

/-- Charge one declaration against the declaration budget. Returns `false`
after reporting the limit and halting elaboration. -/
private def countDeclaration (table : ModuleTable) (range : SourceRange) :
    ElabM Bool := do
  let state ← get
  if state.declarationCount + 1 > state.limits.maxDeclarations then do
    report ((Diagnostic.error ElabCode.declarationLimit .nameResolution
      "module declaration count exceeds the configured limit"
      (locationOfRange table range))
      |>.withArgument "limit" (toString state.limits.maxDeclarations)
      |>.withArgument "module" table.name.name)
    halt
    return false
  else
    set { state with declarationCount := state.declarationCount + 1 }
    return true

/-- Attach the resolver's outcome to one tabulated instance site. The edge
carries the site's source range, so the two lists match without trusting an
index. -/
private def resolveInstanceSite (graph : ResolvedModuleGraph) (owner : ModuleName)
    (site : InstanceSite) : InstanceSite :=
  match graph.edges.find? (fun edge =>
      edge.owner == owner && edge.range == site.declaration.range) with
  | some edge => { site with resolution := edge.resolution }
  | none => site

private def buildTable (graph : ResolvedModuleGraph) (node : ModuleNode) :
    ElabM ModuleTable := do
  let mut table : ModuleTable :=
    { name := node.name
      logicalPath := node.unit.logicalPath
      sourceBytes := node.unit.normalizedUtf8.size
      extendsEdges := graph.edges.filter (fun edge =>
        edge.owner == node.name && edge.kind == .«extends») }
  for declaration in node.module.declarations do
    if (← countDeclaration table declaration.range) then
      table ← tabulateDeclaration table declaration false
  return { table with
    instanceSites := table.instanceSites.map (resolveInstanceSite graph node.name) }

private def tabulateGraph (graph : ResolvedModuleGraph) : ElabM Unit := do
  for node in graph.nodes do
    let state ← get
    if state.halted then
      pure ()
    else do
      let table ← buildTable graph node
      let latest ← get
      set { latest with tables := latest.tables.push table }

/-! ## Effective closures -/

private def pushUnique (names : Array ModuleName) (name : ModuleName) :
    Array ModuleName :=
  if names.contains name then names else names.push name

private def pushUniqueMany (names extra : Array ModuleName) : Array ModuleName :=
  extra.foldl pushUnique names

/-- Merge one effective declaration into a closure. The same resolved symbol is
deduplicated (diamond reuse); a different symbol with the same visible name is
an ambiguity reported with primary and related declaration locations. -/
private def mergeEntry (entries : Array ClosureEntry) (entry : ClosureEntry) :
    ElabM (Array ClosureEntry) := do
  if entry.info.name.isEmpty then
    if entries.any (fun existing => existing.info.symbol == entry.info.symbol) then
      return entries
    else
      return entries.push entry
  else
    match entries.find? (fun existing => existing.info.name == entry.info.name) with
    | none => return entries.push entry
    | some existing =>
        if existing.info.symbol == entry.info.symbol then
          return entries
        else do
          report ((Diagnostic.error ElabCode.ambiguousImport .nameResolution
            s!"visible name '{entry.info.name}' is ambiguous: it is declared in both '{existing.info.declaredIn.name}' and '{entry.info.declaredIn.name}'"
            (ClosureEntry.location entry))
            |>.withRelated
              s!"the conflicting declaration is in '{existing.info.declaredIn.name}'"
              (ClosureEntry.location existing)
            |>.withArgument "name" entry.info.name
            |>.withArgument "module" entry.info.declaredIn.name)
          return entries

/-- Kinds an `INSTANCE` exposes unqualified: the child's own operators and the
instance names it re-exports. Constants, variables, assumptions, and theorems
are either substituted or remain the child's private obligations. -/
private def exposedKind (kind : SymbolKind) : Bool :=
  kind == .definition || kind == .recursive || kind == .«instance»

/-- Allocate a fresh symbol for one instance-exposed declaration. The origin
and declaration range stay the child's, so provenance survives substitution,
while the fresh identity lets the copy carry its own instantiated level. -/
private def allocateCopy (table : ModuleTable) (source : SymbolInfo)
    (site : InstanceSite) : ElabM (Option SymbolInfo) := do
  match ← allocateSymbol table source.kind source.name source.arity
      source.fixity site.declaration.«local» source.declarationRange with
  | none => pure none
  | some info =>
      pure (some { info with
        declaredIn := source.declaredIn
        logicalPath := source.logicalPath
        definition? := source.definition?
        instanceSite? := source.instanceSite? })

/-- Allocate the symbol of a named `INSTANCE` visible name. -/
private def mergeInstanceEntry (table : ModuleTable) (entries : Array ClosureEntry)
    (site : InstanceSite) : ElabM (Array ClosureEntry) :=
  match site.declaration.name with
  | none => pure entries
  | some instanceName => do
      match ← allocateSymbol table .«instance» instanceName 0 .functional
          site.declaration.«local» site.declaration.range with
      | none => pure entries
      | some info =>
          mergeEntry entries
            { info := { info with instanceSite? := some site }
              importPath := #[table.name] }

/-- Effective declarations of one captured module, memoized. The traversal is
recursive over an explicit fuel count, so a hand-built cyclic graph fails
closed with a limit diagnostic instead of diverging. -/
private def closureOf (fuel : Nat) (name : ModuleName) :
    ElabM ClosureResult := do
  let state ← get
  match state.closures.find? (fun memo => memo.1 == name) with
  | some memo => return memo.2
  | none =>
      match fuel with
      | 0 => do
        report ((Diagnostic.error ElabCode.fuelExhausted .nameResolution
          "module dependency elaboration exceeded its recursion bound"
          state.anchor)
          |>.withArgument "module" name.name)
        halt
        return {}
      | fuel' + 1 =>
        match state.tables.find? (fun table => table.name == name) with
        | none => return {}
        | some table => do
            let mut result : ClosureResult := {}
            for edge in table.extendsEdges do
              let current ← get
              if !current.halted then
                match current.tables.find? (fun other =>
                    other.name == edge.dependency) with
                | none =>
                    if edge.resolution == .standardCatalog then
                      result :=
                        { result with
                          availableStandards :=
                            pushUnique result.availableStandards edge.dependency }
                      if !edge.«local» then
                        result :=
                          { result with
                            exportedStandards :=
                              pushUnique result.exportedStandards edge.dependency }
                | some _ => do
                    let nested ← closureOf fuel' edge.dependency
                    for nestedEntry in nested.entries do
                      if !nestedEntry.info.localDeclaration then
                        let imported : ClosureEntry :=
                          { info := { nestedEntry.info with
                                      localDeclaration := edge.«local» }
                            importPath := #[name] ++ nestedEntry.importPath
                            frames := nestedEntry.frames }
                        let entries ← mergeEntry result.entries imported
                        result := { result with entries }
                    if !edge.«local» then
                      result :=
                        { result with
                          availableStandards :=
                            pushUniqueMany result.availableStandards
                              nested.exportedStandards
                          exportedStandards :=
                            pushUniqueMany result.exportedStandards
                              nested.exportedStandards }
                    else
                      result :=
                        { result with
                          availableStandards :=
                            pushUniqueMany result.availableStandards
                              nested.availableStandards }
            for entry in table.entries do
              let entries ← mergeEntry result.entries
                { info := entry, importPath := #[name] }
              result := { result with entries }
            for site in table.instanceSites do
              let current ← get
              if !current.halted then
                let siteFrame : InstanceFrame := { site, viewer := name }
                match site.resolution with
                | .standardCatalog =>
                    if site.declaration.name.isSome then do
                      let entries ← mergeInstanceEntry table result.entries site
                      result := { result with entries }
                    else do
                      result :=
                        { result with
                          availableStandards :=
                            pushUnique result.availableStandards
                              site.declaration.moduleName }
                      if !site.declaration.«local» then
                        result :=
                          { result with
                            exportedStandards :=
                              pushUnique result.exportedStandards
                                site.declaration.moduleName }
                | .localSource =>
                    match current.tables.find? (fun other =>
                        other.name == site.declaration.moduleName) with
                    | none => pure ()
                    | some _ => do
                        let nested ← closureOf fuel' site.declaration.moduleName
                        match site.declaration.name with
                        | some _ => do
                            let entries ← mergeInstanceEntry table result.entries site
                            result := { result with entries }
                        | none => do
                            result :=
                              { result with
                                availableStandards :=
                                  pushUniqueMany result.availableStandards
                                    nested.availableStandards }
                            if !site.declaration.«local» then
                              result :=
                                { result with
                                  exportedStandards :=
                                    pushUniqueMany result.exportedStandards
                                      nested.availableStandards }
                            for nestedEntry in nested.entries do
                              if !nestedEntry.info.localDeclaration &&
                                  exposedKind nestedEntry.info.kind then
                                match ← allocateCopy table nestedEntry.info site with
                                | none => pure ()
                                | some info => do
                                    let entries ← mergeEntry result.entries
                                      { info
                                        importPath := #[name] ++ nestedEntry.importPath
                                        frames := nestedEntry.frames ++ [siteFrame] }
                                    result := { result with entries }
            let latest ← get
            set { latest with closures := latest.closures.push (name, result) }
            return result

private def computeClosures (graph : ResolvedModuleGraph) : ElabM Unit := do
  let fuel := graph.nodes.size + 1
  for node in graph.nodes do
    let state ← get
    if state.halted then
      pure ()
    else do
      let _ ← closureOf fuel node.name
      pure ()

/-! ## Instance substitution

`INSTANCE M WITH c <- e` replaces a visible constant or variable of `M` with an
expression written in the instantiating module. The reference baseline accepts
a substitution target only when it is a declared `CONSTANT` or `VARIABLE` of
the instantiated module, and requires every other visible constant or variable
to have a same-named declaration in the instantiating module (implicit
substitution, which may be a definition as well as a declaration). The checks
below mirror both rules, so an instance never turns a child variable into root
state and never guesses a missing actual. -/

/-- The explicit `WITH` substitution for one formal name, if any. -/
private def explicitSubstitution? (site : InstanceSite) (formal : String) :
    Option Substitution :=
  site.declaration.substitutions.find? fun substitution =>
    substitution.formal == formal

/-- The visible constants and variables of one effective closure. These are the
only legal substitution targets. -/
private def substitutionTargets (closure : ClosureResult) : Array ClosureEntry :=
  closure.entries.filter fun entry =>
    !entry.info.localDeclaration &&
      (entry.info.kind == .constant || entry.info.kind == .variable)

/-- The implicit same-name actual of one substitution: a visible 0-ary
declaration of the instantiating module, excluding instance names. -/
private def implicitActual? (closure : ClosureResult) (name : String) :
    Option ClosureEntry :=
  closure.entries.find? fun entry =>
    !entry.info.name.isEmpty && entry.info.name == name &&
      (entry.info.kind == .constant || entry.info.kind == .variable ||
       entry.info.kind == .definition || entry.info.kind == .recursive)

/-- Validate the explicit substitutions of one site: each target must name a
visible constant or variable of the instantiated module, appear once, and carry
that declaration's arity. A pinned standard target has no captured
declarations, so every substitution against it is illegal. -/
private def checkExplicitSubstitutions (table : ModuleTable) (site : InstanceSite)
    (targets : Array ClosureEntry) : ElabM Unit := do
  let mut seen : Array (String × SourceRange) := #[]
  for substitution in site.declaration.substitutions do
    match seen.find? (fun earlier => earlier.1 == substitution.formal) with
    | some earlier =>
        report ((Diagnostic.error ElabCode.substitutionDuplicate .substitution
          s!"symbol '{substitution.formal}' is substituted more than once"
          (locationOfRange table substitution.range))
          |>.withRelated "the earlier substitution is here"
            (locationOfRange table earlier.2)
          |>.withArgument "name" substitution.formal
          |>.withArgument "module" site.declaration.moduleName.name)
    | none => do
      seen := seen.push (substitution.formal, substitution.range)
      match targets.find? (fun entry => entry.info.name == substitution.formal) with
      | none =>
          report ((Diagnostic.error ElabCode.substitutionInvalid .substitution
            s!"'{substitution.formal}' is not a declared constant or variable of module '{site.declaration.moduleName.name}'"
            (locationOfRange table substitution.range))
            |>.withArgument "name" substitution.formal
            |>.withArgument "module" site.declaration.moduleName.name)
      | some entry =>
          if entry.info.arity != substitution.formalArity then
            report ((Diagnostic.error ElabCode.substitutionArity .substitution
              s!"'{substitution.formal}' is declared with arity {entry.info.arity} but the substitution gives arity {substitution.formalArity}"
              (locationOfRange table substitution.range))
              |>.withRelated "declared here" (ClosureEntry.location entry)
              |>.withArgument "name" substitution.formal
              |>.withArgument "expected" (toString entry.info.arity)
              |>.withArgument "actual" (toString substitution.formalArity))

/-- Validate the implicit substitution of one site: every visible constant and
variable of the instantiated module without an explicit `WITH` entry must have
a same-named 0-ary declaration in the instantiating module. -/
private def checkImplicitSubstitutions (table : ModuleTable) (closure : ClosureResult)
    (site : InstanceSite) (targets : Array ClosureEntry) : ElabM Unit := do
  let location := locationOfRange table site.declaration.range
  for target in targets do
    match explicitSubstitution? site target.info.name with
    | some _ => pure ()
    | none =>
        match implicitActual? closure target.info.name with
        | none =>
            report ((Diagnostic.error ElabCode.substitutionMissing .substitution
              s!"substitution missing for symbol '{target.info.name}' declared in module '{target.info.declaredIn.name}'"
              location)
              |>.withRelated "the missing declaration is here"
                (ClosureEntry.location target)
              |>.withArgument "name" target.info.name
              |>.withArgument "module" target.info.declaredIn.name)
        | some actual =>
            if actual.info.arity != 0 then
              report ((Diagnostic.error ElabCode.substitutionArity .substitution
                s!"the implicit substitution for '{target.info.name}' must be 0-ary, but '{actual.info.name}' takes {actual.info.arity}"
                location)
                |>.withRelated "the actual is declared here"
                  (ClosureEntry.location actual)
                |>.withArgument "name" target.info.name
                |>.withArgument "actual" (toString actual.info.arity))

/-- Validate every `INSTANCE` site of one module. -/
private def checkModuleInstances (table : ModuleTable)
    (closure : ClosureResult) : ElabM Unit := do
  let state ← get
  for site in table.instanceSites do
    if site.resolution == .standardCatalog then
      checkExplicitSubstitutions table site #[]
    else
      match state.closures.find? (fun memo =>
          memo.1 == site.declaration.moduleName) with
      | none => pure ()
      | some child => do
          checkExplicitSubstitutions table site (substitutionTargets child.2)
          checkImplicitSubstitutions table closure site
            (substitutionTargets child.2)

private def checkInstances : ElabM Unit := do
  let state ← get
  for table in state.tables do
    let latest ← get
    if !latest.halted then
      match latest.closures.find? (fun memo => memo.1 == table.name) with
      | none => pure ()
      | some memo => checkModuleInstances table memo.2

/-! ## Name resolution -/

/-- Profile canonical spelling of one reference spelling. The parser already
normalizes through the profile; this keeps a hand-built tree on the same
identity. -/
private def canonicalSpelling (profile : LanguageProfile) (spelling : String) :
    String :=
  (profile.canonicalFor? spelling).getD spelling

private def renderReference (profile : LanguageProfile)
    (reference : OperatorRef) : String :=
  (reference.qualifier.map (fun qualifier => qualifier ++ "!")).getD ""
    ++ canonicalSpelling profile reference.spelling

private def reportArity (table : ModuleTable) (range : SourceRange)
    (rendered : String) (argumentCount expected : Nat)
    (declaration? : Option SymbolInfo) : ElabM Unit := do
  let mut diagnostic :=
    (Diagnostic.error ElabCode.arityMismatch .nameResolution
      s!"'{rendered}' is applied to {argumentCount} arguments but takes {expected}"
      (locationOfRange table range))
      |>.withArgument "name" rendered
      |>.withArgument "expected" (toString expected)
      |>.withArgument "actual" (toString argumentCount)
  if let some info := declaration? then
    diagnostic := diagnostic.withRelated "declared here" (locationOfSymbol info)
  report diagnostic

/-- Resolve one operator reference against formal parameters and bound names,
the module's effective declarations, the language-defined operator facts, and
the available standard-module facts, in that order. -/
private def resolveReference (profile : LanguageProfile) (table : ModuleTable)
    (closure : ClosureResult) (names : Array (String × Nat))
    (reference : OperatorRef) (argumentCount : Nat) : ElabM Unit := do
  let spelling := canonicalSpelling profile reference.spelling
  let rendered := renderReference profile reference
  match reference.qualifier with
  | some qualifier => do
      let state ← get
      let unknownReference : ElabM Unit :=
        report ((Diagnostic.error ElabCode.unknownName .nameResolution
          s!"qualified reference '{rendered}' has no operator declaration in module '{table.name.name}'"
          (locationOfRange table reference.range))
          |>.withArgument "name" rendered
          |>.withArgument "module" table.name.name)
      match closure.entries.find? (fun entry =>
          entry.info.kind == .«instance» && entry.info.name == qualifier) with
      | none => unknownReference
      | some instanceEntry =>
          match instanceEntry.info.instanceSite? with
          | none => unknownReference
          | some site =>
              match site.resolution with
              | .standardCatalog =>
                  match standardOperatorFacts.find? (fun fact =>
                      fact.name == spelling &&
                        fact.module == site.declaration.moduleName) with
                  | some fact =>
                      if fact.arity == argumentCount then
                        pure ()
                      else
                        reportArity table reference.range rendered argumentCount
                          fact.arity none
                  | none => unknownReference
              | .localSource =>
                  match state.closures.find? (fun memo =>
                      memo.1 == site.declaration.moduleName) with
                  | none => unknownReference
                  | some child =>
                      match child.2.entries.find? (fun entry =>
                          !entry.info.name.isEmpty && entry.info.name == spelling &&
                            !entry.info.localDeclaration &&
                            (entry.info.kind == .definition ||
                             entry.info.kind == .recursive)) with
                      | none => unknownReference
                      | some declared =>
                          if declared.info.arity == argumentCount then
                            pure ()
                          else
                            reportArity table reference.range rendered argumentCount
                              declared.info.arity (some declared.info)
  | none =>
      match names.find? (fun entry => entry.1 == spelling) with
      | some bound =>
          if bound.2 == argumentCount then
            pure ()
          else
            reportArity table reference.range rendered argumentCount bound.2 none
      | none =>
          match closure.entries.find? (fun entry =>
              !entry.info.name.isEmpty && entry.info.name == spelling &&
                entry.info.kind != .«instance») with
          | some entry =>
              if entry.info.arity == argumentCount then
                pure ()
              else
                reportArity table reference.range rendered argumentCount
                  entry.info.arity (some entry.info)
          | none =>
              match languageOperatorFacts.find? (fun fact =>
                  fact.name == spelling) with
              | some fact =>
                  if fact.arities.contains argumentCount then
                    pure ()
                  else
                    reportArity table reference.range rendered argumentCount
                      (match fact.arities[0]? with
                        | some arity => arity
                        | none => 0) none
              | none =>
                  match standardOperatorFacts.find? (fun fact =>
                      fact.name == spelling &&
                        closure.availableStandards.contains fact.module) with
                  | some fact =>
                      if fact.arity == argumentCount then
                        pure ()
                      else
                        reportArity table reference.range rendered argumentCount
                          fact.arity none
                  | none =>
                      report ((Diagnostic.error ElabCode.unknownName .nameResolution
                        s!"name '{rendered}' has no declaration in module '{table.name.name}' or its imports"
                        (locationOfRange table reference.range))
                        |>.withArgument "name" rendered
                        |>.withArgument "module" table.name.name)

mutual
/-- Resolve the bound names of one binder group in order: each domain is
resolved in the scope of the names bound before it. -/
private def resolveBounds (profile : LanguageProfile) (table : ModuleTable)
    (closure : ClosureResult) (fuel : Nat) (names : Array (String × Nat))
    (bounds : Array Bound) : ElabM (Array (String × Nat)) := do
  let mut current := names
  for bound in bounds do
    match bound.domain with
    | some domain =>
        resolveExpression profile table closure fuel current domain
    | none => pure ()
    current := current.push (bound.name, 0)
  return current

/-- Resolve every operator reference of one expression. The traversal is
recursive over an explicit fuel count; exhausting it fails closed. -/
private def resolveExpression (profile : LanguageProfile) (table : ModuleTable)
    (closure : ClosureResult) (fuel : Nat) (names : Array (String × Nat))
    (expression : Expression) : ElabM Unit := do
  match fuel with
  | 0 =>
      report ((Diagnostic.error ElabCode.fuelExhausted .nameResolution
        "expression traversal exceeded its resource bound"
        (locationOfRange table (Expression.range expression)))
        |>.withArgument "module" table.name.name)
      halt
  | fuel' + 1 =>
      match expression with
      | .name reference _ =>
          resolveReference profile table closure names reference 0
      | .boolean _ _ => pure ()
      | .integer _ _ => pure ()
      | .string _ _ => pure ()
      | .tuple items _ =>
          for item in items do
            resolveExpression profile table closure fuel' names item
      | .set items _ =>
          for item in items do
            resolveExpression profile table closure fuel' names item
      | .record fields _ =>
          for field in fields do
            resolveExpression profile table closure fuel' names field.value
      | .recordSet fields _ =>
          for field in fields do
            resolveExpression profile table closure fuel' names field.value
      | .function bounds body _ => do
          let extended ← resolveBounds profile table closure fuel' names bounds
          resolveExpression profile table closure fuel' extended body
      | .functionSet domain codomain _ => do
          resolveExpression profile table closure fuel' names domain
          resolveExpression profile table closure fuel' names codomain
      | .apply reference arguments _ => do
          resolveReference profile table closure names reference arguments.size
          for argument in arguments do
            resolveExpression profile table closure fuel' names argument
      | .functionApply func index _ => do
          resolveExpression profile table closure fuel' names func
          resolveExpression profile table closure fuel' names index
      | .select base _ _ =>
          resolveExpression profile table closure fuel' names base
      | .ifThenElse condition thenBranch elseBranch _ => do
          resolveExpression profile table closure fuel' names condition
          resolveExpression profile table closure fuel' names thenBranch
          resolveExpression profile table closure fuel' names elseBranch
      | .case arms _ =>
          for arm in arms do
            match arm.guard with
            | some guard =>
                resolveExpression profile table closure fuel' names guard
            | none => pure ()
            resolveExpression profile table closure fuel' names arm.value
      | .letIn definitions body _ => do
          let extended := definitions.foldl
            (fun accumulated definition =>
              accumulated.push (definition.name, definition.parameters.size))
            names
          for definition in definitions do
            let withParameters := definition.parameters.foldl
              (fun accumulated parameter =>
                accumulated.push (parameter.name, parameter.arity))
              extended
            resolveExpression profile table closure fuel' withParameters
              definition.body
          resolveExpression profile table closure fuel' extended body
      | .choose bounds body _ => do
          let extended ← resolveBounds profile table closure fuel' names bounds
          resolveExpression profile table closure fuel' extended body
      | .quantifier _ bounds body _ => do
          let extended ← resolveBounds profile table closure fuel' names bounds
          resolveExpression profile table closure fuel' extended body
      | .setBuilder element bounds _ => do
          let extended ← resolveBounds profile table closure fuel' names bounds
          resolveExpression profile table closure fuel' extended element
      | .setFilter bounds predicate _ => do
          let extended ← resolveBounds profile table closure fuel' names bounds
          resolveExpression profile table closure fuel' extended predicate
      | .except base specifications _ => do
          resolveExpression profile table closure fuel' names base
          for specification in specifications do
            for element in specification.path do
              match element with
              | .index index _ =>
                  resolveExpression profile table closure fuel' names index
              | .field _ _ => pure ()
            resolveExpression profile table closure fuel' names
              specification.value
      | .currentValue _ => pure ()

end

private def parameterNames (definition : OperatorDefinition) :
    Array (String × Nat) :=
  definition.parameters.map fun parameter => (parameter.name, parameter.arity)

/-- Resolve every declaration body of one module in that module's scope. -/
private def resolveModule (profile : LanguageProfile) (table : ModuleTable)
    (closure : ClosureResult) : ElabM Unit := do
  let fuel := expressionFuel table
  for entry in table.entries do
    match entry.definition? with
    | some definition =>
        resolveExpression profile table closure fuel
          (parameterNames definition) definition.body
    | none => pure ()
    match entry.assumption? with
    | some declaration =>
        resolveExpression profile table closure fuel
          (#[] : Array (String × Nat)) declaration.body
    | none => pure ()
    match entry.theorem? with
    | some declaration =>
        resolveExpression profile table closure fuel
          (#[] : Array (String × Nat)) declaration.statement
    | none => pure ()

private def resolveNode (profile : LanguageProfile) (node : ModuleNode) :
    ElabM Unit := do
  let state ← get
  match state.closures.find? (fun memo => memo.1 == node.name) with
  | none => pure ()
  | some memo =>
      match state.tables.find? (fun table => table.name == node.name) with
      | none => pure ()
      | some table =>
          if state.halted then pure ()
          else resolveModule profile table memo.2

private def resolveGraph (profile : LanguageProfile)
    (graph : ResolvedModuleGraph) : ElabM Unit := do
  for node in graph.nodes do
    let state ← get
    if state.halted then
      pure ()
    else
      resolveNode profile node

/-! ## Expression levels -/

private def levelOf? (levels : Array (SymbolId × Level)) (symbol : SymbolId) :
    Option Level :=
  match levels.find? (fun entry => entry.1 == symbol) with
  | none => none
  | some entry => some entry.2

/-- Name lookup for one module's effective declarations. -/
private def scopeLevels (entries : Array ClosureEntry)
    (levels : Array (SymbolId × Level)) : SymbolLevels :=
  fun key =>
    match entries.find? (fun entry =>
        !entry.info.name.isEmpty && entry.info.name == key) with
    | none => none
    | some entry => levelOf? levels entry.info.symbol

/-- Evaluation fuel for instantiated level classification: one unit per
captured byte plus one per allocated symbol, so every frame chain and body
expansion of a captured graph fits while a hand-built cycle still fails
closed. -/
private def levelFuel (state : ElabState) : Nat :=
  state.tables.foldl (fun total table => total + expressionFuel table) 0 +
    state.nextSymbol + 16

/-- One module's memoized effective closure, if it was computed. -/
private def closureOf? (state : ElabState) (name : ModuleName) :
    Option ClosureResult :=
  match state.closures.find? (fun memo => memo.1 == name) with
  | some memo => some memo.2
  | none => none

/-- Level of one name in an instantiated context. `origin` is the module whose
declarations the name is written against and `frames` the substitution frames
that apply to it, innermost first: `frames[0].site` substitutes the names of
`origin`, and each later frame substitutes the names of the previous frame's
viewer. A frame's explicit `WITH` actual replaces the name; a constant or
variable without an explicit actual falls through to the same-named declaration
of the frame's viewer (implicit substitution); an operator is expanded under
the same frames, so a definition inherits the level shift of the constants it
mentions. An unknown name is unclassified, which `referenceLevel` reads as
constant, matching the name-resolution stage that rejects it first. -/
private def instancedKeyLevel (state : ElabState) (fuel : Nat) (origin : ModuleName)
    (frames : List InstanceFrame) (key : String) : Option Level :=
  match fuel with
  | 0 => none
  | fuel + 1 =>
      match key.splitOn "!" with
      | [qualifier, name] =>
          match (closureOf? state origin).bind (fun closure =>
              closure.entries.find? fun entry =>
                entry.info.kind == .«instance» && entry.info.name == qualifier) with
          | none => none
          | some entry =>
              match entry.info.instanceSite? with
              | none => none
              | some site =>
                  match site.resolution with
                  | .standardCatalog =>
                      match standardOperatorFacts.find? (fun fact =>
                          fact.name == name &&
                            fact.module == site.declaration.moduleName) with
                      | some fact => some fact.level
                      | none => none
                  | .localSource =>
                      match (closureOf? state site.declaration.moduleName).bind
                          (fun target => target.entries.find? fun other =>
                            !other.info.name.isEmpty && other.info.name == name &&
                              !other.info.localDeclaration &&
                              (other.info.kind == .definition ||
                               other.info.kind == .recursive)) with
                      | none => none
                      | some declared =>
                          let scope : SymbolLevels := fun inner =>
                            instancedKeyLevel state fuel declared.info.declaredIn
                              (declared.frames ++
                                ({ site, viewer := entry.info.declaredIn } :
                                  InstanceFrame) ::
                                entry.frames ++ frames) inner
                          match declared.info.definition? with
                          | none => levelOf? state.levels declared.info.symbol
                          | some definition =>
                              definitionLevel fuel scope #[] definition
      | _ =>
          match frames with
          | [] =>
              match (closureOf? state origin).bind (fun closure =>
                  closure.entries.find? fun entry =>
                    !entry.info.name.isEmpty && entry.info.name == key) with
              | none => none
              | some entry =>
                  match entry.info.kind with
                  | .definition | .recursive =>
                      let scope : SymbolLevels := fun inner =>
                        instancedKeyLevel state fuel entry.info.declaredIn
                          (entry.frames ++ frames) inner
                      match entry.info.definition? with
                      | none => levelOf? state.levels entry.info.symbol
                      | some definition =>
                          definitionLevel fuel scope #[] definition
                  | _ => levelOf? state.levels entry.info.symbol
          | frame :: rest =>
              match explicitSubstitution? frame.site key with
              | some substitution =>
                  expressionLevel fuel
                    (fun inner =>
                      instancedKeyLevel state fuel frame.viewer rest inner)
                    #[] substitution.actual
              | none =>
                  match (closureOf? state origin).bind (fun closure =>
                      closure.entries.find? fun entry =>
                        !entry.info.name.isEmpty && entry.info.name == key) with
                  | some entry =>
                      if entry.info.kind == .constant ||
                          entry.info.kind == .variable then
                        instancedKeyLevel state fuel frame.viewer rest key
                      else
                        let scope : SymbolLevels := fun inner =>
                          instancedKeyLevel state fuel entry.info.declaredIn
                            (entry.frames ++ frames) inner
                        match entry.info.definition? with
                        | none => levelOf? state.levels entry.info.symbol
                        | some definition =>
                            definitionLevel fuel scope #[] definition
                  | none => none

private def raiseLevel (levels : Array (SymbolId × Level)) (symbol : SymbolId)
    (candidate : Level) : Array (SymbolId × Level) × Bool :=
  match levels.find? (fun entry => entry.1 == symbol) with
  | none => (levels, false)
  | some entry =>
      let joined := Level.max entry.2 candidate
      if joined == entry.2 then
        (levels, false)
      else
        (levels.map (fun other =>
          if other.1 == symbol then (symbol, joined) else other), true)

/-- One level-fixpoint pass: classify every operator definition and
assumption-like body against the current symbol levels. -/
private structure LevelPass where
  levels : Array (SymbolId × Level)
  changed : Bool
  failed : Bool

private def levelPass (state : ElabState) : LevelPass := Id.run do
  let mut levels := state.levels
  let mut changed := false
  let mut failed := false
  for table in state.tables do
    match state.closures.find? (fun memo => memo.1 == table.name) with
    | none => pure ()
    | some memo =>
        for entry in table.entries do
          -- Plain names are answered from the memoized symbol levels; a
          -- qualified `I!Op` reference (or any name the flat table cannot
          -- answer) is classified through the instance frames, which is also
          -- where the substitution shifts the operator's level.
          let current := { state with levels }
          let scope : SymbolLevels := fun key =>
            match scopeLevels memo.2.entries levels key with
            | some level => some level
            | none =>
                instancedKeyLevel current (levelFuel state)
                  entry.declaredIn [] key
          match entry.definition? with
          | some definition =>
              match definitionLevel (expressionFuel table) scope
                  (#[] : Array (String × Level)) definition with
              | some candidate =>
                  let (next, changedHere) :=
                    raiseLevel levels entry.symbol candidate
                  levels := if changedHere then next else levels
                  changed := changed || changedHere
              | none => failed := true
          | none => pure ()
          match entry.assumption? with
          | some declaration =>
              match expressionLevel (expressionFuel table) scope
                  (#[] : Array (String × Level)) declaration.body with
              | some candidate =>
                  let (next, changedHere) :=
                    raiseLevel levels entry.symbol candidate
                  levels := if changedHere then next else levels
                  changed := changed || changedHere
              | none => failed := true
          | none => pure ()
        -- Declarations an `INSTANCE` exposed: their bodies are classified
        -- under the substitution frames instead of the module's own scope.
        for entry in memo.2.entries do
          if !entry.frames.isEmpty then
            match entry.info.definition? with
            | none => pure ()
            | some definition =>
                let current := { state with levels }
                match definitionLevel (expressionFuel table)
                    (fun key => instancedKeyLevel current (levelFuel state)
                      entry.info.declaredIn entry.frames key)
                    #[] definition with
                | some candidate =>
                    let (next, changedHere) :=
                      raiseLevel levels entry.info.symbol candidate
                    levels := if changedHere then next else levels
                    changed := changed || changedHere
                | none => failed := true
  return { levels, changed, failed }

/-- Classify levels over the whole graph as the least fixpoint of the
syntax-directed rules. The lattice has height four, so `3 * symbols + 2`
iterations bound the number of raising passes; failing to stabilize would be a
defect and is reported as a limit failure rather than guessed. -/
private def computeLevels : ElabM Unit := do
  let state ← get
  let mut levels : Array (SymbolId × Level) := #[]
  for table in state.tables do
    for entry in table.entries do
      let base : Level :=
        match entry.kind with
        | .variable => .state
        | _ => .constant
      levels := levels.push (entry.symbol, base)
  -- Instance-exposed declarations start at the bottom of the lattice too;
  -- their bodies raise them through the substitution frames.
  for table in state.tables do
    match state.closures.find? (fun memo => memo.1 == table.name) with
    | none => pure ()
    | some memo =>
        for entry in memo.2.entries do
          if !entry.frames.isEmpty &&
              (entry.info.kind == .definition || entry.info.kind == .recursive) then
            levels := levels.push (entry.info.symbol, .constant)
  set { state with levels }
  let symbolCount := state.nextSymbol
  let budget := 3 * symbolCount + 2
  let mut iteration := 0
  let mut running := true
  let mut failed := false
  while running && iteration < budget do
    let current ← get
    let pass := levelPass current
    set { current with levels := pass.levels }
    running := pass.changed
    if pass.failed then
      running := false
      failed := true
    iteration := iteration + 1
  let final ← get
  if failed || running then do
    report ((Diagnostic.error ElabCode.fuelExhausted .level
      "level classification did not reach a fixpoint within its bound"
      final.anchor)
      |>.withArgument "iterations" (toString budget))
    halt

/-- Substituted actuals must classify at constant or state level: a variable may
not be replaced by a primed or temporal expression, and revision 1 applies the
same uniform bound to constant substitutions instead of the reference tool's
occurrence-sensitive bound (`tla-language-profile.md` §7.4 and §9). -/
private def checkSubstitutionLevels : ElabM Unit := do
  let state ← get
  for table in state.tables do
    let latest ← get
    if !latest.halted then
      match latest.closures.find? (fun memo => memo.1 == table.name) with
      | none => pure ()
      | some memo => do
          -- Substitution actuals are written in the instantiating module, so
          -- their levels come from that module's own scope; a qualified
          -- reference in an actual is classified through the instance frames.
          let scope : SymbolLevels := fun key =>
            match scopeLevels memo.2.entries latest.levels key with
            | some level => some level
            | none =>
                instancedKeyLevel latest (levelFuel latest) table.name [] key
          for site in table.instanceSites do
            if site.resolution == .localSource then do
              for substitution in site.declaration.substitutions do
                match expressionLevel (expressionFuel table) scope
                    (#[] : Array (String × Level)) substitution.actual with
                | some level =>
                    if level.rank > Level.state.rank then
                      report ((Diagnostic.error ElabCode.substitutionLevel .substitution
                        s!"the expression substituted for '{substitution.formal}' is classified {level} but substitution actuals must be constant or state level"
                        (locationOfRange table substitution.range))
                        |>.withArgument "name" substitution.formal
                        |>.withArgument "level" level.toString)
                | none =>
                    report ((Diagnostic.error ElabCode.fuelExhausted .substitution
                      "substitution level classification exhausted its bound"
                      (locationOfRange table substitution.range))
                      |>.withArgument "module" table.name.name)
              match latest.closures.find? (fun memo =>
                  memo.1 == site.declaration.moduleName) with
              | none => pure ()
              | some child =>
                  for target in substitutionTargets child.2 do
                    match explicitSubstitution? site target.info.name with
                    | some _ => pure ()
                    | none =>
                        match implicitActual? memo.2 target.info.name with
                        | none => pure ()
                        | some actual =>
                            let level :=
                              (levelOf? latest.levels actual.info.symbol).getD
                                .constant
                            if level.rank > Level.state.rank then
                              report ((Diagnostic.error ElabCode.substitutionLevel .substitution
                                s!"the implicit substitution for '{target.info.name}' is classified {level} but substitution actuals must be constant or state level"
                                (locationOfRange table site.declaration.range))
                                |>.withArgument "name" target.info.name
                                |>.withArgument "level" level.toString)

/-- `ASSUME`, `ASSUMPTION`, and `AXIOM` statements must be constant level. -/
private def checkAssumptions : ElabM Unit := do
  let state ← get
  for table in state.tables do
    for entry in table.entries do
      match entry.assumption? with
      | none => pure ()
      | some _ =>
          let level := (levelOf? state.levels entry.symbol).getD .constant
          if level != .constant then
            report ((Diagnostic.error ElabCode.assumptionLevel .level
              s!"assumption in module '{table.name.name}' is classified {level} but assumptions must be constant level"
              (locationOfSymbol entry))
              |>.withArgument "module" table.name.name
              |>.withArgument "level" level.toString)

/-! ## Results -/

private def resolvedConstantOf (entry : ClosureEntry) : ResolvedConstant :=
  { symbol := entry.info.symbol
    name := entry.info.name
    declaredIn := entry.info.declaredIn
    declarationRange := entry.info.declarationRange
    importPath := entry.importPath
    localDeclaration := entry.info.localDeclaration }

private def resolvedVariableOf (entry : ClosureEntry) : ResolvedVariable :=
  { symbol := entry.info.symbol
    visibleName := entry.info.name
    declaredName := entry.info.name
    declaredIn := entry.info.declaredIn
    declarationRange := entry.info.declarationRange
    importPath := entry.importPath
    localDeclaration := entry.info.localDeclaration }

private def resolvedOperatorOf (levels : Array (SymbolId × Level))
    (entry : ClosureEntry) : ResolvedOperator :=
  { symbol := entry.info.symbol
    name := entry.info.name
    arity := entry.info.arity
    fixity := entry.info.fixity
    level := (levelOf? levels entry.info.symbol).getD .constant
    declaredIn := entry.info.declaredIn
    declarationRange := entry.info.declarationRange
    importPath := entry.importPath
    localDeclaration := entry.info.localDeclaration }

private def resolvedAssumptionOf (levels : Array (SymbolId × Level))
    (entry : ClosureEntry) (declaration : Assumption) : ResolvedAssumption :=
  { symbol := entry.info.symbol
    kind := declaration.kind
    body := declaration.body
    level := (levelOf? levels entry.info.symbol).getD .constant
    declaredIn := entry.info.declaredIn
    declarationRange := entry.info.declarationRange
    importPath := entry.importPath
    localDeclaration := entry.info.localDeclaration }

private def assemble (graph : ResolvedModuleGraph) (state : ElabState) :
    ElaboratedModule :=
  let closure : ClosureResult :=
    match state.closures.find? (fun memo => memo.1 == graph.root) with
    | some memo => memo.2
    | none => {}
  let constants := closure.entries.filterMap (fun entry =>
    match entry.info.kind with
    | .constant => some (resolvedConstantOf entry)
    | _ => none)
  let variables := closure.entries.filterMap (fun entry =>
    match entry.info.kind with
    | .variable => some (resolvedVariableOf entry)
    | _ => none)
  let operators := closure.entries.filterMap (fun entry =>
    match entry.info.kind with
    | .recursive => some (resolvedOperatorOf state.levels entry)
    | .definition => some (resolvedOperatorOf state.levels entry)
    | _ => none)
  let assumptions := closure.entries.filterMap (fun entry =>
    match entry.info.assumption? with
    | some declaration =>
        some (resolvedAssumptionOf state.levels entry declaration)
    | none => none)
  { moduleName := graph.root
    constants
    variables
    operators
    assumptions
    sourceManifest := graph.sourceIdentities
    symbolCount := state.nextSymbol }

private def elaborateCore (profile : LanguageProfile)
    (graph : ResolvedModuleGraph) : ElabM Unit := do
  tabulateGraph graph
  whenNotDone (computeClosures graph)
  whenNotDone checkInstances
  whenNotDone (resolveGraph profile graph)
  whenNotDone computeLevels
  whenNotDone checkSubstitutionLevels
  whenNotDone checkAssumptions

/-- Elaborate one resolved module graph. The result is either the effective
facts of the root module or the bounded structured diagnostics that rejected
the graph; a result carrying an error diagnostic never takes the success path.
Revision 1 emits no warnings, so the success path drops no information. -/
def elaborate (profile : LanguageProfile) (limits : ElaborationLimits)
    (graph : ResolvedModuleGraph) : Except (List Diagnostic) ElaboratedModule :=
  let anchor : SourceLocation :=
    match graph.findNode? graph.root with
    | some node => SourceLocation.ofUnit node.unit zeroRange |>.withModule node.name
    | none =>
        { moduleName := some graph.root
          logicalPath := graph.root.name ++ ".tla"
          range := zeroRange }
  let initial : ElabState := { limits, anchor }
  let (_, final) := (elaborateCore profile graph).run initial
  if final.buffer.diagnostics.any (fun diagnostic =>
      diagnostic.hasErrorSeverity) then
    .error final.buffer.diagnostics.toList
  else
    .ok (assemble graph final)

end Core.Tla
