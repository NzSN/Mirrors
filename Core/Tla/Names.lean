import Core.Tla.Graph
import Core.Tla.Level
import Core.Tla.Source

/-!
# TLA+ resolved names and effective model facts (`Core/Tla/Names.lean`)

Elaboration output shapes for the general TLA+ frontend
(`Docs/model-interface-compiler/tla-frontend-design.md`, §13.1 "Names and
scopes", §14 "`EXTENDS` semantics", and §16 "Effective model facts"; task
package TF4 in `Docs/model-interface-compiler/tla-frontend-tasks.md`).

These types are pure data, so the elaborator stays in `Core` and every effect
(source capture, parser invocation, graph construction) remains in `Shell`.

Two decisions are recorded here:

* `SymbolId` is analysis-local and never persisted. Persisted artifacts carry
  `declaredIn`, the declaration range, the import path, and source hashes, so a
  later run recomputes the same facts from the same sources without trusting an
  earlier identifier.
* `importPath` is the module-name chain from the elaborated root to the module
  that declares the symbol, root first. The frozen corpus summaries render the
  same chain (`expected/acc-generic-transfer.json`), and a diamond keeps the
  first path that reached the shared declaration.
-/

namespace Core.Tla

/-- Stable analysis-local symbol identity. Symbols are numbered per elaboration
run in discovery order; the identity is never persisted. -/
abbrev SymbolId := Nat

/-- What a resolved name declares. `recursive` is a `RECURSIVE` declaration
with or without its later definition; `definition` is a plain operator
definition. -/
inductive SymbolKind where
  | constant
  | variable
  | recursive
  | definition
  | assumption
  | theorem
  | «instance»
  deriving Repr, BEq, DecidableEq

namespace SymbolKind

/-- Stable lowercase rendering used by inspection output. -/
def toString : SymbolKind → String
  | .constant => "constant"
  | .variable => "variable"
  | .recursive => "recursive"
  | .definition => "definition"
  | .assumption => "assumption"
  | .theorem => "theorem"
  | .«instance» => "instance"

end SymbolKind

/-- One resolved constant declaration. -/
structure ResolvedConstant where
  symbol : SymbolId
  name : String
  declaredIn : ModuleName
  declarationRange : SourceRange
  importPath : Array ModuleName
  /-- `true` when the declaration is `LOCAL` to `declaredIn`. -/
  localDeclaration : Bool
  deriving Repr, BEq

/-- One effective state variable with its declaration origin, matching the
design's `ResolvedVariable` and the frozen corpus summaries. -/
structure ResolvedVariable where
  symbol : SymbolId
  visibleName : String
  declaredName : String
  declaredIn : ModuleName
  declarationRange : SourceRange
  importPath : Array ModuleName
  localDeclaration : Bool
  deriving Repr, BEq

/-- One resolved operator with arity and classified level. -/
structure ResolvedOperator where
  symbol : SymbolId
  name : String
  arity : Nat
  fixity : OperatorFixity
  level : Level
  declaredIn : ModuleName
  declarationRange : SourceRange
  importPath : Array ModuleName
  localDeclaration : Bool
  deriving Repr, BEq

/-- One resolved assumption-like declaration with its classified level. -/
structure ResolvedAssumption where
  symbol : SymbolId
  kind : AssumptionKind
  body : Expression
  level : Level
  declaredIn : ModuleName
  declarationRange : SourceRange
  importPath : Array ModuleName
  localDeclaration : Bool
  deriving Repr, BEq

/-- The elaborated root facts consumed by later stages (`§16`). -/
structure EffectiveModelFacts where
  moduleName : ModuleName
  constants : Array ResolvedConstant
  variables : Array ResolvedVariable
  operators : Array ResolvedOperator
  assumptions : Array ResolvedAssumption
  sourceManifest : Array SourceIdentity
  deriving Repr, BEq

/-- One successfully elaborated module graph: the effective facts of the root
plus the bounded symbol accounting of the whole run. -/
structure ElaboratedModule where
  moduleName : ModuleName
  constants : Array ResolvedConstant
  variables : Array ResolvedVariable
  operators : Array ResolvedOperator
  assumptions : Array ResolvedAssumption
  sourceManifest : Array SourceIdentity
  /-- Symbols assigned while tabulating every captured module. -/
  symbolCount : Nat
  deriving Repr, BEq

namespace ElaboratedModule

/-- The downstream-facing projection of one elaborated module. -/
def facts (module : ElaboratedModule) : EffectiveModelFacts :=
  { moduleName := module.moduleName
    constants := module.constants
    variables := module.variables
    operators := module.operators
    assumptions := module.assumptions
    sourceManifest := module.sourceManifest }

/-- The effective variables whose declaration lives in `moduleName`. -/
def ownVariables (module : ElaboratedModule) (name : ModuleName) :
    Array ResolvedVariable :=
  module.variables.filter fun entry => entry.declaredIn == name

/-- The effective operators whose declaration lives in `moduleName`. -/
def ownOperators (module : ElaboratedModule) (name : ModuleName) :
    Array ResolvedOperator :=
  module.operators.filter fun entry => entry.declaredIn == name

end ElaboratedModule

end Core.Tla
