import Core.Tla.Source
import Core.Tla.Syntax

/-!
# TLA+ resolved module graph (`Core/Tla/Graph.lean`)

Pure module-graph data for the general TLA+ frontend
(`Docs/model-interface-compiler/tla-frontend-design.md`, §7 "Frontend
interface", §12 "Module graph resolution", §13 "Semantic elaboration", and
§19 "Standard modules"). Task package TF3b in
`Docs/model-interface-compiler/tla-frontend-tasks.md`.

`Shell/Tla/ModuleResolver.lean` constructs these values and owns every effect:
bounded source reads, provider selection, parser invocation, limit enforcement,
and diagnostic construction. The declarations here stay pure so a Core
elaborator can consume a resolved graph without importing `Shell`.

A complete graph retains discovery order; `ResolvedModuleGraph.sortedNodes`,
`sourceIdentities`, and `canonicalEdges` provide the canonical presentation used
by summaries and manifest publication. Standard modules carry no node because no
source is captured for them.
-/

namespace Core.Tla

/-! ## Dependency resolution -/

/-- How a dependency was satisfied. `localSource` means a captured module node;
`standardCatalog` means a pinned standard-module identity with no captured
source. Structural summaries render these as `local` and `standard`. -/
inductive DependencyResolution where
  | localSource
  | standardCatalog
  deriving Repr, BEq, DecidableEq

namespace DependencyResolution

/-- Stable rendering used by structural summaries and tests. -/
def toString : DependencyResolution → String
  | .localSource => "local"
  | .standardCatalog => "standard"

end DependencyResolution

/-! ## Standard-module identity -/

/-- How a standard module's facts are owned. `filesystemSupplied` marks modules
that must still be captured like application sources before they can supply
facts. -/
inductive StandardModuleKind where
  | languageDefined
  | apalacheExtension
  | filesystemSupplied
  deriving Repr, BEq, DecidableEq

/-- A pinned standard-module identity. Declaration facts are deliberately not
modelled here: the module graph only needs to know that a dependency resolves to
a pinned standard identity rather than to a local file. -/
structure StandardModule where
  name : ModuleName
  kind : StandardModuleKind
  /-- Profile-pinned content identity when the module ships with the pinned
  baseline; `none` means the profile pins the name and kind only. -/
  contentIdentity : Option String
  deriving Repr, BEq, DecidableEq

/-! ## Captured graph -/

/-- One module dependency edge. `declarationOrder` is the index of the site in
the owner's dependency declarations, so canonical output keeps declaration
order within an owner. -/
structure ModuleEdge where
  owner : ModuleName
  dependency : ModuleName
  kind : DependencyKind
  resolution : DependencyResolution
  «local» : Bool
  substitutions : Array Substitution
  range : SourceRange
  declarationOrder : Nat
  deriving Repr, BEq

/-- One captured module. `unit` holds the exact bytes later analysis consumes;
`module` is the parsed view of those bytes. -/
structure ModuleNode where
  name : ModuleName
  logicalPath : String
  unit : SourceUnit
  module : ParsedModule
  deriving BEq

/-- A complete resolved graph. Nodes and edges are stored in deterministic
discovery order; `ResolvedModuleGraph.sortedNodes`, `sourceIdentities`, and
`canonicalEdges` provide the canonical presentation used by summaries and
manifest publication. Standard modules carry no node because no source is
captured for them. -/
structure ResolvedModuleGraph where
  root : ModuleName
  nodes : Array ModuleNode
  edges : Array ModuleEdge
  standardModules : Array StandardModule
  deriving BEq

namespace ResolvedModuleGraph

/-- The captured module with the given logical identity, if any. -/
def findNode? (graph : ResolvedModuleGraph) (name : ModuleName) :
    Option ModuleNode :=
  graph.nodes.find? fun node => node.name == name

/-- Captured modules in canonical module-name order. -/
def sortedNodes (graph : ResolvedModuleGraph) : Array ModuleNode :=
  graph.nodes.qsort fun left right => compare left.name.name right.name.name == .lt

/-- Captured module identities in canonical order. -/
def sourceIdentities (graph : ResolvedModuleGraph) : Array SourceIdentity :=
  graph.sortedNodes.map fun node => SourceUnit.identity node.unit node.name

/-- Edges in canonical output order: owners sorted by module name, edges in
declaration order within each owner. -/
def canonicalEdges (graph : ResolvedModuleGraph) : Array ModuleEdge :=
  graph.sortedNodes.foldl
    (fun acc node => acc ++ graph.edges.filter fun edge => edge.owner == node.name)
    (#[] : Array ModuleEdge)

/-- Standard-module identities in first-use order. -/
def standardNames (graph : ResolvedModuleGraph) : Array ModuleName :=
  graph.standardModules.map fun standard => standard.name

end ResolvedModuleGraph

end Core.Tla
