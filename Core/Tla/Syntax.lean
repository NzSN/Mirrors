import Core.Tla.Source
import Core.Tla.Diagnostic
import Core.Tla.Token

/-!
# TLA+ concrete and abstract syntax (Core/Tla/Syntax.lean)

Types for the revision-1 TLA+ frontend
(`Docs/model-interface-compiler/tla-frontend-design.md`, §10 "Concrete and
abstract syntax"; task package TF2 in
`Docs/model-interface-compiler/tla-frontend-tasks.md`).

The concrete syntax tree is lossless: its leaves are the lexer's tokens, and a
token already carries its leading and trailing trivia. Concatenating leaf token
text in order therefore reproduces the captured source, including comments and
whitespace.

The abstract syntax removes trivia and records one normalized operator
spelling per operator identity. Source ranges are kept on every node so later
stages can report declaration origins without re-reading source text.

Two shapes here extend the design's sketch because the revision-1 corpus
requires the facts:

* `Declaration.extends` carries `EXTENDS` statements with their imported
  modules and source ranges, and `ParsedModule.dependencies` projects the
  resolver's edge list (`kind`, `moduleName`, `local`, `substitutions`,
  `range`) from `EXTENDS` and `INSTANCE` declarations in source order;
* every declaration kind records the extent of its whole statement, so
  `Declaration.range.start` is the introducing keyword line even when a
  `CONSTANT`, `VARIABLE`, or `RECURSIVE` name list begins on a later line;
* `Bound.domain` is optional, because `CHOOSE x : P` binds a name without a
  domain while quantifier and comprehension bounds always carry one.

Successful parsing never produces a module with error diagnostics. A
`ParseOutcome` may still carry a partial CST for diagnostics, but `module?` is
present only when the parser observed no error.
-/

namespace Core.Tla

/-! ## Concrete syntax -/

/-- Coarse classification of lossless concrete-syntax nodes. The kind is used
by diagnostics, inspection, and formatter experiments; the leaf tokens carry
the exact source spelling. -/
inductive CstKind where
  | moduleRoot
  | moduleHeader
  | moduleEnd
  | declaration
  | declarationGroup
  | extendsDeclaration
  | operatorDefinition
  | instanceDeclaration
  | assumption
  | theorem
  | proofRegion
  | expression
  | ifExpression
  | caseExpression
  | letExpression
  | quantifier
  | comprehension
  | tuple
  | record
  | set
  | function
  | parameterList
  | argumentList
  | boundList
  | recordFieldList
  | caseArmList
  | exceptSpecList
  | subscript
  | recovery
  deriving Repr, BEq, DecidableEq

namespace CstKind

/-- Stable rendering used by inspection output and tests. -/
def toString : CstKind → String
  | .moduleRoot => "moduleRoot"
  | .moduleHeader => "moduleHeader"
  | .moduleEnd => "moduleEnd"
  | .declaration => "declaration"
  | .declarationGroup => "declarationGroup"
  | .extendsDeclaration => "extendsDeclaration"
  | .operatorDefinition => "operatorDefinition"
  | .instanceDeclaration => "instanceDeclaration"
  | .assumption => "assumption"
  | .theorem => "theorem"
  | .proofRegion => "proofRegion"
  | .expression => "expression"
  | .ifExpression => "ifExpression"
  | .caseExpression => "caseExpression"
  | .letExpression => "letExpression"
  | .quantifier => "quantifier"
  | .comprehension => "comprehension"
  | .tuple => "tuple"
  | .record => "record"
  | .set => "set"
  | .function => "function"
  | .parameterList => "parameterList"
  | .argumentList => "argumentList"
  | .boundList => "boundList"
  | .recordFieldList => "recordFieldList"
  | .caseArmList => "caseArmList"
  | .exceptSpecList => "exceptSpecList"
  | .subscript => "subscript"
  | .recovery => "recovery"

end CstKind

/-- A lossless concrete-syntax node. `range` is the node's intended source
extent; it is stored so empty recovery nodes still have a well-defined range.
Token leaves retain their trivia, so every byte of normalized source is owned
by exactly one leaf. -/
inductive CstNode where
  | token (leaf : Token)
  | node (kind : CstKind) (range : SourceRange) (children : List CstNode)
  deriving Repr, BEq

namespace CstNode

/-- Source extent of a node. -/
def range : CstNode → SourceRange
  | .token leaf => leaf.range
  | .node _ range _ => range

/-- Direct children of a node; a token leaf has none. -/
def childrenList : CstNode → List CstNode
  | .token _ => []
  | .node _ _ children => children

mutual
  /-- Number of token leaves, including the final `eof` token. -/
  def tokenCount : CstNode → Nat
    | .token _ => 1
    | .node _ _ children => countTokens children

  def countTokens : List CstNode → Nat
    | [] => 0
    | child :: rest => child.tokenCount + countTokens rest

  /-- Number of trivia items retained by token leaves. -/
  def triviaCount : CstNode → Nat
    | .token leaf => leaf.leadingTrivia.size + leaf.trailingTrivia.size
    | .node _ _ children => countTrivia children

  def countTrivia : List CstNode → Nat
    | [] => 0
    | child :: rest => child.triviaCount + countTrivia rest

  /-- Token leaves in source order. -/
  def leafTokens : CstNode → List Token
    | .token leaf => [leaf]
    | .node _ _ children => leafTokensList children

  def leafTokensList : List CstNode → List Token
    | [] => []
    | child :: rest => child.leafTokens ++ leafTokensList rest

  /-- Reconstructed source text, including trivia. -/
  def text : CstNode → String
    | .token leaf => Token.text leaf
    | .node _ _ children => textList children

  def textList : List CstNode → String
    | [] => ""
    | child :: rest => child.text ++ textList rest

  /-- `true` when every child range sits inside its parent and siblings are
  ordered without overlap. Ranges are byte offsets, so this check is cheap and
  independent of the surrounding source. -/
  def rangesNested : CstNode → Bool
    | .token _ => true
    | .node _ outer children => nestedList outer children

  def nestedList (outer : SourceRange) : List CstNode → Bool
    | [] => true
    | child :: rest =>
        decide (outer.start.offset ≤ child.range.start.offset) &&
          decide (child.range.stop.offset ≤ outer.stop.offset) &&
          child.rangesNested &&
          match rest with
          | [] => true
          | next :: _ =>
              decide (child.range.stop.offset ≤ next.range.start.offset) &&
                nestedList outer rest
end

end CstNode

/-- A lossless concrete syntax tree for one module. -/
structure CstModule where
  root : CstNode
  deriving Repr, BEq

namespace CstModule

/-- Number of token leaves in the tree. -/
def tokenCount (cst : CstModule) : Nat := cst.root.tokenCount

/-- Number of trivia items in the tree. -/
def triviaCount (cst : CstModule) : Nat := cst.root.triviaCount

/-- Reconstructed source text. It equals the captured normalized text exactly
when the parser retained every token, including `eof`. -/
def text (cst : CstModule) : String := cst.root.text

/-- `true` when every token of `stream` appears exactly once, in order. -/
def losslessAgainst (cst : CstModule) (stream : TokenStream) : Bool :=
  cst.tokenCount == stream.tokens.size && cst.text == stream.text

/-- `true` when every node range nests inside its parent. -/
def rangesNested (cst : CstModule) : Bool := cst.root.rangesNested

/-- `true` when the tree's root extent covers the whole captured source. -/
def coversSource (cst : CstModule) (source : SourceUnit) : Bool :=
  cst.root.range.start.offset == 0 && cst.root.range.stop.offset == source.normalizedUtf8.size

end CstModule

/-! ## Abstract syntax -/

/-- A module-qualified operator reference. `qualifier` is present for
`Module!Operator` references. `spelling` is the normalized operator spelling
from the language profile. -/
structure OperatorRef where
  qualifier : Option String
  spelling : String
  range : SourceRange
  deriving Repr, BEq, DecidableEq

/-- Fixity of an operator definition. -/
inductive OperatorFixity where
  | functional
  | prefix
  | infix
  | postfix
  deriving Repr, BEq, DecidableEq

/-- Bounded-quantifier kind. -/
inductive QuantifierKind where
  | forall
  | exists
  deriving Repr, BEq, DecidableEq

/-- A formal parameter of an operator definition. `arity` is nonzero for
higher-order operands such as `F(_)`. -/
structure OperatorParameter where
  name : String
  arity : Nat
  range : SourceRange
  deriving Repr, BEq, DecidableEq

mutual
  /-- Normalized abstract syntax for the executable TLA+ expression surface of
  the revision-1 profile. Operator applications use canonical spellings; the
  parser keeps the original spelling in the CST.

  Compound operators that have no dedicated constructor are application nodes
  with the profile's canonical spelling: `'` (prime), `[]` (always), `<>`
  (eventually), `~>` (leadsto), `[]_` (action subscript `[A]_v`), `<<>>_`
  (angle subscript `<<A>>_v`), `ENABLED`, `UNCHANGED`, `DOMAIN`, `SUBSET`,
  `UNION`, `WF_`, and `SF_`. A `WF_v(A)` application carries the subscript as
  its first argument.

  A `.string` node carries the decoded value of the literal: every escape the
  lexer admits (`\"`, `\\`, `\t`, `\n`, `\r`, `\f`) is interpreted exactly
  once, so `"a\nb"` holds a newline while `"a\\nb"` keeps a backslash. The
  concrete syntax retains the original spelling, which is what preserves source
  fidelity. -/
  inductive Expression where
    | name (reference : OperatorRef) (range : SourceRange)
    | boolean (value : Bool) (range : SourceRange)
    | integer (value : Int) (range : SourceRange)
    | string (value : String) (range : SourceRange)
    | tuple (items : Array Expression) (range : SourceRange)
    | set (items : Array Expression) (range : SourceRange)
    | record (fields : Array RecordField) (range : SourceRange)
    | recordSet (fields : Array RecordField) (range : SourceRange)
    | function (bounds : Array Bound) (body : Expression) (range : SourceRange)
    | functionSet (domain : Expression) (codomain : Expression)
        (range : SourceRange)
    | apply (operator : OperatorRef) (arguments : Array Expression)
        (range : SourceRange)
    | functionApply (func index : Expression) (range : SourceRange)
    | select (base : Expression) (field : String) (range : SourceRange)
    | ifThenElse (condition thenBranch elseBranch : Expression)
        (range : SourceRange)
    | case (arms : Array CaseArm) (range : SourceRange)
    | letIn (definitions : Array OperatorDefinition) (body : Expression)
        (range : SourceRange)
    | choose (bounds : Array Bound) (body : Expression) (range : SourceRange)
    | quantifier (kind : QuantifierKind) (bounds : Array Bound)
        (body : Expression) (range : SourceRange)
    | setBuilder (element : Expression) (bounds : Array Bound)
        (range : SourceRange)
    | setFilter (bounds : Array Bound) (predicate : Expression)
        (range : SourceRange)
    | except (base : Expression) (specifications : Array ExceptSpec)
        (range : SourceRange)
    | currentValue (range : SourceRange)
    deriving Repr, BEq

  /-- A bound name with its domain expression. `domain` is `none` for an
  unbound `CHOOSE` name and for an unbounded quantifier binder (`\A x : P`,
  `\E x, y : P`). -/
  structure Bound where
    name : String
    domain : Option Expression
    range : SourceRange
    deriving Repr, BEq

  /-- A record field. -/
  structure RecordField where
    name : String
    value : Expression
    range : SourceRange
    deriving Repr, BEq

  /-- A `CASE` arm. `guard` is `none` for the `OTHER` arm. -/
  structure CaseArm where
    guard : Option Expression
    value : Expression
    range : SourceRange
    deriving Repr, BEq

  /-- One selector in an `EXCEPT` path. -/
  inductive ExceptPathElement where
    | field (name : String) (range : SourceRange)
    | index (index : Expression) (range : SourceRange)
    deriving Repr, BEq

  /-- One `EXCEPT` update. -/
  structure ExceptSpec where
    path : Array ExceptPathElement
    value : Expression
    range : SourceRange
    deriving Repr, BEq

  /-- An operator definition, used both at module level and in `LET`. -/
  structure OperatorDefinition where
    name : String
    nameRange : SourceRange
    fixity : OperatorFixity
    parameters : Array OperatorParameter
    body : Expression
    range : SourceRange
    deriving Repr, BEq
end

namespace Expression

/-- Source extent of an expression. Lean does not generate field projections for
the mutually recursive syntax, so the projection is written out here. -/
def range : Expression → SourceRange
  | .name _ range => range
  | .boolean _ range => range
  | .integer _ range => range
  | .string _ range => range
  | .tuple _ range => range
  | .set _ range => range
  | .record _ range => range
  | .recordSet _ range => range
  | .function _ _ range => range
  | .functionSet _ _ range => range
  | .apply _ _ range => range
  | .functionApply _ _ range => range
  | .select _ _ range => range
  | .ifThenElse _ _ _ range => range
  | .case _ range => range
  | .letIn _ _ range => range
  | .choose _ _ range => range
  | .quantifier _ _ _ range => range
  | .setBuilder _ _ range => range
  | .setFilter _ _ range => range
  | .except _ _ range => range
  | .currentValue range => range

end Expression

namespace ExceptPathElement

/-- Source extent of one `EXCEPT` path element. -/
def range : ExceptPathElement → SourceRange
  | .field _ range => range
  | .index _ range => range

end ExceptPathElement

/-- A declared variable name. -/
structure NameDecl where
  name : String
  range : SourceRange
  deriving Repr, BEq, DecidableEq

/-- A declared constant or recursive operator with explicit arity. -/
structure OperatorDecl where
  name : String
  arity : Nat
  range : SourceRange
  deriving Repr, BEq, DecidableEq

/-- One `INSTANCE ... WITH` substitution: the child-side formal name (with its
own arity for operator substitutions) replaced by the source-side expression. -/
structure Substitution where
  formal : String
  formalArity : Nat
  formalRange : SourceRange
  actual : Expression
  range : SourceRange
  deriving Repr, BEq

/-- A named or unnamed `INSTANCE`. `name` is present for the definition form
`I == INSTANCE M ...`; `local` records a `LOCAL INSTANCE`. -/
structure InstanceDeclaration where
  name : Option String
  moduleName : ModuleName
  substitutions : Array Substitution
  «local» : Bool
  range : SourceRange
  deriving Repr, BEq

/-- One imported module of an `EXTENDS` statement. -/
structure ImportedModule where
  name : ModuleName
  range : SourceRange
  deriving Repr, BEq

/-- An `EXTENDS` statement. `local` records `LOCAL EXTENDS`. -/
structure ExtendsDeclaration where
  modules : Array ImportedModule
  «local» : Bool
  range : SourceRange
  deriving Repr, BEq

/-- Assumption-like declaration kind. -/
inductive AssumptionKind where
  | assume
  | assumption
  | «axiom»
  deriving Repr, BEq, DecidableEq

/-- An `ASSUME`, `ASSUMPTION`, or `AXIOM` declaration. -/
structure Assumption where
  kind : AssumptionKind
  name : Option String
  body : Expression
  range : SourceRange
  deriving Repr, BEq

/-- Theorem-like declaration kind. `LEMMA`, `PROPOSITION`, and `COROLLARY`
are carried with their own kind and summarized as `theorem`. -/
inductive TheoremKind where
  | «theorem»
  | lemma
  | proposition
  | corollary
  deriving Repr, BEq, DecidableEq

/-- How an opaque proof region was written. Revision 1 retains the span and
does not parse the proof body (`syntax.proof.opaque`). -/
inductive ProofTreatment where
  | omitted
  | opaque
  deriving Repr, BEq, DecidableEq

/-- An opaque proof region. -/
structure ProofRegion where
  treatment : ProofTreatment
  range : SourceRange
  deriving Repr, BEq

/-- A theorem-like declaration with an optional opaque proof region. -/
structure Theorem where
  kind : TheoremKind
  name : Option String
  statement : Expression
  proof : Option ProofRegion
  range : SourceRange
  deriving Repr, BEq

/-- A module-level declaration in source order. -/
inductive Declaration where
  | constant (range : SourceRange) (names : Array OperatorDecl)
  | variable (range : SourceRange) (names : Array NameDecl)
  | recursive (range : SourceRange) (operators : Array OperatorDecl)
  | operator (definition : OperatorDefinition)
  | «local» (range : SourceRange) (declaration : Declaration)
  | «instance» (declaration : InstanceDeclaration)
  | assumption (declaration : Assumption)
  | «theorem» (declaration : Theorem)
  | «extends» (declaration : ExtendsDeclaration)
  deriving Repr, BEq

/-- Degenerate range used only when an impossible empty declaration appears. -/
def zeroRange : SourceRange :=
  { start := ⟨0, 1, 1⟩, stop := ⟨0, 1, 1⟩ }

/-- Smallest range covering `ranges` in order. -/
def arraySpan (ranges : Array SourceRange) : SourceRange :=
  match ranges[0]?, ranges.back? with
  | some first, some last => { start := first.start, stop := last.stop }
  | _, _ => zeroRange

namespace Declaration

/-- Source extent of a declaration statement: the introducing keyword (when the
grammar has one) through the end of the statement. -/
def range : Declaration → SourceRange
  | .constant statement _ => statement
  | .variable statement _ => statement
  | .recursive statement _ => statement
  | .operator definition => definition.range
  | .«local» statement _ => statement
  | .«instance» declaration => declaration.range
  | .assumption declaration => declaration.range
  | .«theorem» declaration => declaration.range
  | .«extends» declaration => declaration.range

/-- Declaration kind as recorded by the revision-1 structural summary. -/
def summaryKind : Declaration → String
  | .constant _ _ => "constant"
  | .variable _ _ => "variable"
  | .recursive _ _ => "recursive"
  | .operator _ => "operator"
  | .«local» _ declaration => declaration.summaryKind
  | .«instance» _ => "instance"
  | .assumption declaration =>
      match declaration.kind with
      | .assume => "assumption"
      | .assumption => "assumption"
      | .«axiom» => "axiom"
  | .«theorem» _ => "theorem"
  | .«extends» _ => "extends"

/-- Declared names in source order. Assumptions and `EXTENDS` statements have
no declared name; instances contribute their definition name. -/
def summaryNames : Declaration → Array String
  | .constant _ names => names.map (fun name => name.name)
  | .variable _ names => names.map (fun name => name.name)
  | .recursive _ operators => operators.map (fun operator => operator.name)
  | .operator definition => #[definition.name]
  | .«local» _ declaration => declaration.summaryNames
  | .«instance» declaration => match declaration.name with
      | some name => #[name]
      | none => #[]
  | .assumption declaration => match declaration.name with
      | some name => #[name]
      | none => #[]
  | .«theorem» declaration => match declaration.name with
      | some name => #[name]
      | none => #[]
  | .«extends» _ => #[]

/-- Declared names paired with their operator arity. Constants and variables
have no arity; recursive and operator definitions carry one. -/
def operatorArities : Declaration → Array (String × Nat)
  | .recursive _ operators => operators.map (fun operator => (operator.name, operator.arity))
  | .operator definition => #[(definition.name, definition.parameters.size)]
  | .«local» _ declaration => declaration.operatorArities
  | _ => #[]

/-- First source line of a declaration, one-based. -/
def firstLine (declaration : Declaration) : Nat := declaration.range.start.line

end Declaration

/-- A parsed module. This mirrors the frontend design's `ParsedModule` shape. -/
structure ParsedModule where
  name : ModuleName
  declarations : Array Declaration
  range : SourceRange
  deriving Repr, BEq

/-- Module dependency kind, matching the resolver's edge kinds. -/
inductive DependencyKind where
  | «extends»
  | namedInstance
  | unnamedInstance
  deriving Repr, BEq, DecidableEq

namespace DependencyKind

/-- Stable rendering used by structural summaries and tests. -/
def toString : DependencyKind → String
  | .«extends» => "extends"
  | .namedInstance => "namedInstance"
  | .unnamedInstance => "unnamedInstance"

end DependencyKind

/-- A parsed dependency declaration: what the module resolver turns into one
`ModuleEdge`. `local` records `LOCAL EXTENDS` or `LOCAL INSTANCE`. -/
structure DependencyDeclaration where
  kind : DependencyKind
  moduleName : ModuleName
  «local» : Bool
  substitutions : Array Substitution
  range : SourceRange
  deriving Repr, BEq

namespace Declaration

/-- Dependency declarations contributed by one declaration, in source order. -/
def dependencies : Declaration → Array DependencyDeclaration
  | .«extends» declaration =>
      declaration.modules.map fun imported =>
        { kind := .«extends»
          moduleName := imported.name
          «local» := declaration.«local»
          substitutions := #[]
          range := imported.range }
  | .«instance» declaration =>
      #[{ kind := if declaration.name.isSome then .namedInstance else .unnamedInstance
          moduleName := declaration.moduleName
          «local» := declaration.«local»
          substitutions := declaration.substitutions
          range := declaration.range }]
  | .«local» _ declaration =>
      (declaration.dependencies).map (fun dependency => { dependency with «local» := true })
  | _ => #[]

end Declaration

namespace ParsedModule

/-- Dependency declarations of a module in source order. This is the interface
the module resolver consumes; nothing here resolves a module or reads files. -/
def dependencies (module : ParsedModule) : Array DependencyDeclaration :=
  module.declarations.foldl (fun accumulated declaration =>
    accumulated ++ declaration.dependencies) #[]

end ParsedModule

/-- A successful parse: normalized module plus its lossless tree. -/
structure ParseResult where
  module : ParsedModule
  cst : CstModule
  deriving Repr, BEq

/-- The parser's total outcome. `module?` is present only when no error
diagnostic was produced; `cst` may still be a partial tree for diagnostics. -/
structure ParseOutcome where
  cst : CstModule
  module? : Option ParsedModule
  diagnostics : Array Diagnostic
  deriving Repr, BEq

namespace ParseOutcome

/-- `true` when at least one error-severity diagnostic was produced. -/
def hasErrors (outcome : ParseOutcome) : Bool :=
  outcome.diagnostics.any (fun diagnostic => diagnostic.hasErrorSeverity)

/-- `true` only for a usable parse result: no errors and a module present. -/
def succeeded (outcome : ParseOutcome) : Bool :=
  !outcome.hasErrors && outcome.module?.isSome

end ParseOutcome

end Core.Tla
