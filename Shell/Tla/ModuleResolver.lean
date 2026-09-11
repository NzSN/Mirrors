import Core.Tla.Diagnostic
import Core.Tla.Graph
import Core.Tla.Syntax
import Shell.Tla.SourceProvider

/-!
# TLA+ module graph resolution (`Shell/Tla/ModuleResolver.lean`)

Effectful module-graph construction for the general TLA+ frontend
(`Docs/model-interface-compiler/tla-frontend-design.md`, §7.1 "Two
source-provider adapters", §12 "Module graph resolution", §19 "Standard
modules", §21 "Resource and security limits", and §25.2 "Module-resolution
tests"). Task package TF3 in
`Docs/model-interface-compiler/tla-frontend-tasks.md`.

The resolver owns every decision after a module is captured and parsed:

* the root must declare the requested module identity;
* a module is captured and parsed once per logical identity, so diamonds reuse
  one node instead of re-reading a file;
* edges retain owner, dependency, kind, `LOCAL`, substitutions, declaration
  order, resolution, and the source range of the declaration;
* a dependency resolves through the selected provider first and falls back to
  the pinned standard-module catalog only when the provider reports `notFound`;
* a dependency whose declared module name differs from the requested identity is
  rejected, and a declared name that is already bound is a duplicate identity;
* dependency cycles fail with the complete bounded cycle path; and
* module, depth, and edge limits apply before a graph or diagnostic grows
  without bound.

The graph values themselves are Core-owned (`Core/Tla/Graph.lean`); this module
constructs them and keeps every effect.

Two seams stay outside this module:

* `ResolverConfig.parse` is the TF2 parser (`Core.Tla.Parser`). It maps one
  captured unit to a `ParseOutcome`; the resolver never scans tokens itself.
* `ParsedModule.dependencies` is the TF2 dependency projection. It returns
  `EXTENDS` and `INSTANCE` declarations in source order as
  `DependencyDeclaration` values, so a dependency is known only after the
  parser produced a usable module, never from a lexical scan of the text.

Diagnostics are logical: a `SourceReadError`, `SourceLocation`, or failure
message never carries a physical path.
-/

namespace Shell.Tla

open Core.Tla

/-! ## Limits and configuration -/

/-- Graph-construction budgets. Defaults are the revision-1 frontend profile
values; they are provisional until measured against the conformance corpus
(`tla-language-profile.md` §8), but every traversal below is bounded by them. -/
structure ResolverLimits where
  /-- Maximum captured modules, including the root. -/
  maxModules : Nat := 128
  /-- Maximum dependency depth below the root. -/
  maxDependencyDepth : Nat := 64
  /-- Maximum dependency edges, including edges that reuse a captured node. -/
  maxDependencyEdges : Nat := 4096
  deriving Repr, BEq, DecidableEq

/-- Parser seam: the TF2 parser maps one captured unit to its outcome. The seam
is effectful only so callers can instrument, cache, or bound parser work; the
parser itself stays a pure function of the captured bytes. -/
abbrev ParseModule := Core.Tla.SourceUnit → IO Core.Tla.ParseOutcome

/-- Lift a pure parser into the resolver's parse seam. -/
def pureParse (parse : Core.Tla.SourceUnit → Core.Tla.ParseOutcome) :
    ParseModule :=
  fun unit => pure (parse unit)

/-- Everything the resolver needs from its caller. Dependencies come from the
parsed module itself (`Core.Tla.ParsedModule.dependencies`). -/
structure ResolverConfig where
  provider : SourceProvider
  parse : ParseModule
  limits : ResolverLimits := {}

/-- A failed resolution: bounded structured diagnostics and no partial graph. -/
structure ResolverFailure where
  diagnostics : Array Diagnostic
  deriving Repr, BEq

/-! ## Diagnostic codes -/

namespace GraphCode

def rootRead : String := "TLA-GRAPH-ROOT-READ"
def rootHeaderMismatch : String := "TLA-GRAPH-ROOT-HEADER-MISMATCH"
def dependencyRead : String := "TLA-GRAPH-DEPENDENCY-READ"
def dependencyHeaderMismatch : String := "TLA-GRAPH-DEPENDENCY-HEADER-MISMATCH"
def duplicateModule : String := "TLA-GRAPH-DUPLICATE-MODULE"
def missingModule : String := "TLA-GRAPH-MISSING-MODULE"
def cycle : String := "TLA-GRAPH-CYCLE"
def invalidCapture : String := "TLA-GRAPH-INVALID-CAPTURE"
def parseOutcome : String := "TLA-GRAPH-PARSE-OUTCOME"
def tooManyModules : String := "TLA-GRAPH-TOO-MANY-MODULES"
def dependencyTooDeep : String := "TLA-GRAPH-DEPENDENCY-TOO-DEEP"
def tooManyEdges : String := "TLA-GRAPH-TOO-MANY-EDGES"
def fuelExhausted : String := "TLA-GRAPH-FUEL-EXHAUSTED"

end GraphCode

/-! ## Internal resolution state -/

private structure ResolverState where
  nodes : Array ModuleNode := #[]
  edges : Array ModuleEdge := #[]
  standardModules : Array StandardModule := #[]

/-- One open dependency frame. `enteredBy` records the owner and range of the
site that required this module; the stack of open frames is the current
dependency path, which is what makes a bounded complete cycle path available. -/
private structure Frame where
  owner : ModuleName
  logicalPath : String
  sites : Array DependencyDeclaration
  next : Nat
  depth : Nat
  enteredBy : Option (ModuleName × String × SourceRange)

/-- The outcome of one dependency site: the updated state and, when the
dependency was captured, the frame that now trails it. -/
private structure Advance where
  state : ResolverState
  frame : Option Frame := none

private def zeroRange : SourceRange :=
  { start := { offset := 0, line := 1, column := 1 },
    stop := { offset := 0, line := 1, column := 1 } }

private def ownerLocation (owner : ModuleName) (ownerPath : String)
    (range : SourceRange) : SourceLocation :=
  { moduleName := some owner, logicalPath := ownerPath, range }

private def failure (diagnostic : Diagnostic) : ResolverFailure :=
  { diagnostics := #[diagnostic] }

private def graphError (code : String) (message : String)
    (location : SourceLocation) : ResolverFailure :=
  failure (Diagnostic.error code .moduleGraph message location)

private def indexOfOwner? : List Frame → ModuleName → Option Nat
  | [], _ => none
  | frame :: rest, name =>
      if frame.owner == name then some 0
      else (indexOfOwner? rest name).map (· + 1)

/-- Names on the cycle that ends with `dependency`, starting at its first open
occurrence. `stack` is top-first, so the frames up to the occurrence are the
cycle in reverse discovery order. -/
private def cyclePath (stack : List Frame) (dependency : ModuleName) :
    List ModuleName :=
  let index := (indexOfOwner? stack dependency).getD 0
  let segment := (stack.take (index + 1)).reverse
  segment.map (fun frame => frame.owner) ++ [dependency]

/-- Related locations for every captured edge on the cycle: one per frame whose
entry range is known. -/
private def cycleRelated (stack : List Frame) (dependency : ModuleName) :
    List RelatedLocation :=
  let index := (indexOfOwner? stack dependency).getD 0
  (stack.take (index + 1)).filterMap fun frame =>
    match frame.enteredBy with
    | some (parent, parentPath, range) =>
        some { message := s!"'{parent.name}' depends on '{frame.owner.name}'",
               location := ownerLocation parent parentPath range }
    | none => none

private def recordEdge (state : ResolverState) (frame : Frame)
    (site : DependencyDeclaration) (index : Nat) (resolution : DependencyResolution) :
    ResolverState :=
  { state with
    edges := state.edges.push
      { owner := frame.owner
        dependency := site.moduleName
        kind := site.kind
        resolution
        «local» := site.«local»
        substitutions := site.substitutions
        range := site.range
        declarationOrder := index } }

/-! ## Failure constructors -/

private def rootReadFailure (root : ModuleRef) (error : SourceReadError) :
    ResolverFailure :=
  graphError GraphCode.rootRead
    (s!"unable to read root module '{root.moduleName.name}': {error.message}")
    (ownerLocation root.moduleName root.logicalPath zeroRange)

private def rootHeaderMismatch (root : ModuleRef) (unit : SourceUnit)
    (parsed : ParsedModule) : ResolverFailure :=
  let diagnostic := Diagnostic.error GraphCode.rootHeaderMismatch .moduleGraph
    (s!"root source '{unit.logicalPath}' declares module '{parsed.name.name}', expected '{root.moduleName.name}'")
    (ownerLocation parsed.name unit.logicalPath parsed.range)
  failure ((diagnostic.withArgument "declared" parsed.name.name).withArgument
    "expected" root.moduleName.name)

private def dependencyReadFailure (frame : Frame) (site : DependencyDeclaration)
    (error : SourceReadError) : ResolverFailure :=
  graphError GraphCode.dependencyRead
    (s!"unable to read dependency '{site.moduleName.name}': {error.message}")
    (ownerLocation frame.owner frame.logicalPath site.range)

private def inconsistentCapture (frame : Frame) (site : DependencyDeclaration)
    (detail : String) : ResolverFailure :=
  graphError GraphCode.invalidCapture
    (s!"captured dependency '{site.moduleName.name}' is inconsistent: {detail}")
    (ownerLocation frame.owner frame.logicalPath site.range)

private def dependencyHeaderMismatch (frame : Frame) (site : DependencyDeclaration)
    (unit : SourceUnit) (declared : ModuleName) : ResolverFailure :=
  let diagnostic := Diagnostic.error GraphCode.dependencyHeaderMismatch .moduleGraph
    (s!"dependency source '{unit.logicalPath}' declares module '{declared.name}', expected '{site.moduleName.name}'")
    (ownerLocation frame.owner frame.logicalPath site.range)
  failure ((((diagnostic.withArgument "requested" site.moduleName.name).withArgument
    "declared" declared.name)).withRelated
      s!"'{unit.logicalPath}' declares '{declared.name}'"
      (ownerLocation declared unit.logicalPath zeroRange))

private def duplicateModule (frame : Frame) (site : DependencyDeclaration)
    (declared : ModuleName) (related : RelatedLocation) : ResolverFailure :=
  let diagnostic := Diagnostic.error GraphCode.duplicateModule .moduleGraph
    (s!"module identity '{declared.name}' is already bound; refused a second source")
    (ownerLocation frame.owner frame.logicalPath site.range)
  failure ((diagnostic.withArgument "module" declared.name).withRelated
    related.message related.location)

private def missingModule (frame : Frame) (site : DependencyDeclaration)
    (detail : String) : ResolverFailure :=
  let diagnostic := Diagnostic.error GraphCode.missingModule .moduleGraph
    (s!"dependency '{site.moduleName.name}' is neither a local source nor a pinned standard module")
    (ownerLocation frame.owner frame.logicalPath site.range)
  failure (diagnostic.withArgument "detail" detail)

private def cycleFailure (stack : List Frame) (frame : Frame)
    (site : DependencyDeclaration) : ResolverFailure :=
  let names := cyclePath stack site.moduleName
  let path := String.intercalate " -> " (names.map fun name => name.name)
  let primary := ownerLocation frame.owner frame.logicalPath site.range
  let diagnostic := (Diagnostic.error GraphCode.cycle .moduleGraph
    (s!"dependency cycle detected: {path}") primary).withArgument "cycle" path
  let related : List RelatedLocation :=
    cycleRelated stack site.moduleName ++
      [{ message := s!"'{frame.owner.name}' depends on '{site.moduleName.name}'",
         location := primary }]
  failure (related.foldl (fun acc item => acc.withRelated item.message item.location)
    diagnostic)

private def limitFailure (code : String) (frame : Frame) (site : DependencyDeclaration)
    (limit : Nat) (observed : Nat) : ResolverFailure :=
  let diagnostic := Diagnostic.error code .moduleGraph
    (s!"module graph exceeded its limit of {limit} while resolving '{site.moduleName.name}'")
    (ownerLocation frame.owner frame.logicalPath site.range)
  failure ((diagnostic.withArgument "limit" (toString limit)).withArgument
    "observed" (toString observed))

private def depthLimitFailure (frame : Frame) (site : DependencyDeclaration)
    (limit : Nat) : ResolverFailure :=
  let diagnostic := Diagnostic.error GraphCode.dependencyTooDeep .moduleGraph
    (s!"dependency depth exceeds the limit of {limit} at '{site.moduleName.name}'")
    (ownerLocation frame.owner frame.logicalPath site.range)
  failure ((diagnostic.withArgument "limit" (toString limit)).withArgument
    "from" frame.owner.name)

private def parseOutcomeFailure (location : SourceLocation) : ResolverFailure :=
  failure (Diagnostic.error GraphCode.parseOutcome .moduleGraph
    "the parser produced no usable module for the captured source" location)

private def parseFailure (location : SourceLocation)
    (diagnostics : Array Diagnostic) : ResolverFailure :=
  if diagnostics.isEmpty then
    { diagnostics := #[(Diagnostic.error GraphCode.parseOutcome .moduleGraph
        "the parser reported a failed module without diagnostics" location)] }
  else
    { diagnostics }

private def fuelFailure (stack : List Frame) : ResolverFailure :=
  let owner := match stack with
    | frame :: _ => frame.owner
    | [] => ⟨""⟩
  let path := match stack with
    | frame :: _ => frame.logicalPath
    | [] => ""
  graphError GraphCode.fuelExhausted
    "module graph construction exhausted its bounded work budget"
    (ownerLocation owner path zeroRange)

/-! ## Resolution -/

private def adopt (config : ResolverConfig) (frame : Frame) (site : DependencyDeclaration)
    (index : Nat) (state : ResolverState) (depth : Nat) (unit : SourceUnit) :
    IO (Except ResolverFailure Advance) := do
  if !SourceUnit.consistent unit then
    return .error (inconsistentCapture frame site "captured bytes and digest disagree")
  let location := ownerLocation frame.owner frame.logicalPath site.range
  let outcome ← config.parse unit
  if outcome.hasErrors then
    return .error (parseFailure location outcome.diagnostics)
  match outcome.module? with
  | none => return .error (parseOutcomeFailure location)
  | some parsed =>
      let declared := parsed.name
      match state.nodes.find? (fun node => node.name == declared) with
      | some original =>
          return .error (duplicateModule frame site declared
            { message := s!"'{declared.name}' was already captured from '{original.logicalPath}'"
              location := ownerLocation original.name original.logicalPath
                original.module.range })
      | none =>
          if state.standardModules.any (fun standard => standard.name == declared) then
            return .error (duplicateModule frame site declared
              { message := s!"'{declared.name}' is pinned as a standard module"
                location := ownerLocation declared (declared.name ++ ".tla") zeroRange })
          else if declared != site.moduleName then
            return .error (dependencyHeaderMismatch frame site unit declared)
          else
            let node : ModuleNode :=
              { name := declared, logicalPath := unit.logicalPath, unit, module := parsed }
            let state := recordEdge
              { state with nodes := state.nodes.push node }
              frame site index .localSource
            let next : Frame :=
              { owner := declared
                logicalPath := unit.logicalPath
                sites := parsed.dependencies
                next := 0
                depth
                enteredBy := some (frame.owner, frame.logicalPath, site.range) }
            return .ok { state, frame := some next }

private def resolveStandard (config : ResolverConfig) (frame : Frame)
    (site : DependencyDeclaration) (index : Nat) (state : ResolverState) :
    IO (Except ResolverFailure Advance) := do
  match ← config.provider.resolveStandard site.moduleName with
  | .ok standard =>
      if standard.kind == .filesystemSupplied then
        return .error (missingModule frame site
          "the pinned catalog requires a captured source for this module")
      return .ok
        { state := recordEdge
            { state with standardModules := state.standardModules.push standard }
            frame site index .standardCatalog }
  | .error error =>
      return .error (missingModule frame site error.message)

private def resolveDependency (config : ResolverConfig) (stack : List Frame)
    (frame : Frame) (site : DependencyDeclaration) (state : ResolverState) :
    IO (Except ResolverFailure Advance) := do
  let index := frame.next
  if state.edges.size + 1 > config.limits.maxDependencyEdges then
    return .error (limitFailure GraphCode.tooManyEdges frame site
      config.limits.maxDependencyEdges (state.edges.size + 1))
  if stack.any (fun entry => entry.owner == site.moduleName) then
    return .error (cycleFailure stack frame site)
  if (state.nodes.find? (fun node => node.name == site.moduleName)).isSome then
    return .ok { state := recordEdge state frame site index .localSource }
  if state.standardModules.any (fun standard => standard.name == site.moduleName) then
    return .ok { state := recordEdge state frame site index .standardCatalog }
  let depth := frame.depth + 1
  if depth > config.limits.maxDependencyDepth then
    return .error (depthLimitFailure frame site config.limits.maxDependencyDepth)
  if state.nodes.size + 1 > config.limits.maxModules then
    return .error (limitFailure GraphCode.tooManyModules frame site
      config.limits.maxModules (state.nodes.size + 1))
  match ← config.provider.readDependency site.moduleName with
  | .error (.notFound _) =>
      resolveStandard config frame site index state
  | .error error =>
      return .error (dependencyReadFailure frame site error)
  | .ok unit =>
      adopt config frame site index state depth unit

private def loop (config : ResolverConfig) (fuel : Nat) (stack : List Frame)
    (state : ResolverState) : IO (Except ResolverFailure ResolverState) := do
  match fuel with
  | 0 => return .error (fuelFailure stack)
  | budget + 1 =>
      match stack with
      | [] => return .ok state
      | frame :: rest =>
          match frame.sites[frame.next]? with
          | none => loop config budget rest state
          | some site =>
              let frame' := { frame with next := frame.next + 1 }
              match ← resolveDependency config (frame :: rest) frame site state with
              | .error failure => return .error failure
              | .ok advance =>
                  match advance.frame with
                  | some opened =>
                      loop config budget (opened :: frame' :: rest) advance.state
                  | none =>
                      loop config budget (frame' :: rest) advance.state

/-- Resolve one root reference into a complete module graph. The result is
either a usable graph or a failure with bounded diagnostics; a partial graph
never crosses the success path. -/
def resolve (config : ResolverConfig) (root : ModuleRef) :
    IO (Except ResolverFailure ResolvedModuleGraph) := do
  match ← config.provider.readRoot root with
  | .error error => pure (.error (rootReadFailure root error))
  | .ok unit =>
      let location := ownerLocation root.moduleName unit.logicalPath zeroRange
      if !SourceUnit.consistent unit then
        pure (.error (graphError GraphCode.invalidCapture
          "captured root bytes and digest disagree" location))
      else
        let outcome ← config.parse unit
        if outcome.hasErrors then
          pure (.error (parseFailure location outcome.diagnostics))
        else
          match outcome.module? with
          | none => pure (.error (parseOutcomeFailure location))
          | some parsed =>
              if parsed.name != root.moduleName then
                pure (.error (rootHeaderMismatch root unit parsed))
              else
                let node : ModuleNode :=
                  { name := parsed.name
                    logicalPath := unit.logicalPath
                    unit
                    module := parsed }
                let frame : Frame :=
                  { owner := parsed.name
                    logicalPath := unit.logicalPath
                    sites := parsed.dependencies
                    next := 0
                    depth := 0
                    enteredBy := none }
                let fuel := config.limits.maxModules + config.limits.maxDependencyEdges + 4
                match ← loop config fuel [frame] { nodes := #[node] } with
                | .error failure => pure (.error failure)
                | .ok state =>
                    pure (.ok
                      { root := root.moduleName
                        nodes := state.nodes
                        edges := state.edges
                        standardModules := state.standardModules })

end Shell.Tla
