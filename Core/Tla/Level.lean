import Core.Tla.Syntax

/-!
# TLA+ expression levels (`Core/Tla/Level.lean`)

Level classification for the general TLA+ frontend
(`Docs/model-interface-compiler/tla-frontend-design.md`, §13.3 "Expression
levels"; task package TF4 in
`Docs/model-interface-compiler/tla-frontend-tasks.md`).

The lattice is `constant < state < action < temporal`. Classification is
syntactic: the caller supplies a lookup for module-level symbols and a list of
names bound by parameters, quantifiers, comprehensions, functions, and `LET`, so
one traversal classifies an operator definition, an assumption, and a probe
expression without re-reading source text.

Every traversal is bounded by an explicit `fuel` count and returns `none` when
the bound is exhausted, so level checking can never run without a resource
bound and can never report a level it did not compute. The elaborator supplies
one unit per captured source byte: every abstract-syntax node is produced from
at least one token and every token owns at least one byte, so the corpus and
production modules always fit. A caller that exhausts the bound fails closed
with a limit diagnostic instead of guessing a level.

Revision-1 decisions recorded here:

* the profile operator table owns the composite operators; `[]`, `<>`, `~>`,
  `ENABLED`, `WF_`, and `SF_` are temporal and `'`, `[]_`, `<<>>_`, and
  `UNCHANGED` are action level;
* an application is the least upper bound of the operator's own level and its
  arguments, so a higher-order parameter takes the level of the argument it is
  applied to;
* `@` (`.currentValue`) is constant level: the enclosing `EXCEPT` base already
  contributes its own level to the `EXCEPT` result;
* `LET` definitions are classified in the scope of the definitions written
  before them, which keeps the corpus `LET doubled == 2 * N IN doubled + 1`
  constant;
* an unresolved name is constant level. Name resolution runs first and rejects
  unresolved names, so this case cannot reach a successful elaboration.

`referenceKey` is the lookup key of one operator reference: the qualified
spelling when a qualifier is present, the bare spelling otherwise.
-/

namespace Core.Tla

/-- Expression level lattice `constant < state < action < temporal`. -/
inductive Level where
  | constant
  | state
  | action
  | temporal
  deriving Repr, BEq, DecidableEq

namespace Level

/-- Position of a level in the lattice. -/
def rank : Level → Nat
  | .constant => 0
  | .state => 1
  | .action => 2
  | .temporal => 3

/-- The level at a lattice position, when the position is one. -/
def ofRank? : Nat → Option Level
  | 0 => some .constant
  | 1 => some .state
  | 2 => some .action
  | 3 => some .temporal
  | _ => none

/-- Least upper bound of two levels. -/
def max (left right : Level) : Level :=
  if left.rank ≥ right.rank then left else right

/-- Least upper bound of an array of levels; the empty array is `constant`. -/
def join (levels : Array Level) : Level :=
  levels.foldl Level.max .constant

/-- Stable lowercase rendering used by structural summaries and inspection. -/
def toString : Level → String
  | .constant => "constant"
  | .state => "state"
  | .action => "action"
  | .temporal => "temporal"

instance : ToString Level where
  toString := Level.toString

end Level

/-- Level of one visible or qualified module symbol. `none` means the name is
not known to this lookup. -/
abbrev SymbolLevels := String → Option Level

/-- Lookup key of one operator reference: `qualifier!spelling` when a qualifier
is present, the bare spelling otherwise. -/
def referenceKey (reference : OperatorRef) : String :=
  (reference.qualifier.map (fun qualifier => qualifier ++ "!")).getD ""
    ++ reference.spelling

/-- Level of one reference: the bound-name list wins over the module-symbol
lookup, and an unresolved name is constant level. -/
def referenceLevel (symbols : SymbolLevels) (bounds : Array (String × Level))
    (reference : OperatorRef) : Level :=
  let key := referenceKey reference
  match bounds.find? (fun bound => bound.1 == key) with
  | some bound => bound.2
  | none => (symbols key).getD Level.constant

/-- Least upper bound of a list of optional levels: `none` propagates, and the
empty list is `constant`. -/
def levelJoin (levels : Array (Option Level)) : Option Level :=
  levels.foldl
    (fun total level =>
      match total, level with
      | some left, some right => some (Level.max left right)
      | _, _ => none)
    (some Level.constant)

/-- Application level: the profile's temporal and action operators dominate,
every other application is the least upper bound of the operator symbol and the
arguments. -/
def applicationLevel (operator arguments : Level) (spelling : String) : Level :=
  match spelling with
  | "[]" | "<>" | "~>" | "ENABLED" | "WF_" | "SF_" => Level.temporal
  | "'" | "[]_" | "<<>>_" | "UNCHANGED" => Level.max Level.action arguments
  | _ => Level.max operator arguments

/-- The bound-name list extended with one constant-level bound list. -/
def bindings (bounds : Array (String × Level))
    (boundList : Array Bound) : Array (String × Level) :=
  bounds ++ boundList.map (fun bound => (bound.name, Level.constant))

/-- Level of one expression under a module-symbol lookup and a bound-name list.
`fuel` bounds the number of visited syntax nodes; exhaustion returns `none`.

Compound forms that carry no dedicated constructor (`[]`, `'`, `WF_`, …) are
applications whose canonical spelling selects the profile's level rule. -/
def expressionLevel (fuel : Nat) (symbols : SymbolLevels)
    (bounds : Array (String × Level)) (expression : Expression) : Option Level :=
  match fuel with
  | 0 => none
  | fuel + 1 =>
      let recur := expressionLevel fuel symbols bounds
      match expression with
      | .name reference _ => some (referenceLevel symbols bounds reference)
      | .boolean _ _ => some Level.constant
      | .integer _ _ => some Level.constant
      | .string _ _ => some Level.constant
      | .tuple items _ => levelJoin (items.map recur)
      | .set items _ => levelJoin (items.map recur)
      | .record fields _ => levelJoin (fields.map (fun field => recur field.value))
      | .recordSet fields _ => levelJoin (fields.map (fun field => recur field.value))
      | .function boundList body _ =>
          let extended := bindings bounds boundList
          match
            levelJoin (boundList.map (fun bound =>
              match bound.domain with
              | some domain => recur domain
              | none => some Level.constant)),
            expressionLevel fuel symbols extended body with
          | some domains, some result => some (Level.max domains result)
          | _, _ => none
      | .functionSet domain codomain _ =>
          match recur domain, recur codomain with
          | some left, some right => some (Level.max left right)
          | _, _ => none
      | .apply reference arguments _ =>
          match levelJoin (arguments.map recur) with
          | some argumentsLevel =>
              some (applicationLevel
                (referenceLevel symbols bounds reference) argumentsLevel
                reference.spelling)
          | none => none
      | .functionApply func index _ =>
          match recur func, recur index with
          | some left, some right => some (Level.max left right)
          | _, _ => none
      | .select base _ _ => recur base
      | .ifThenElse condition thenBranch elseBranch _ =>
          match recur condition, recur thenBranch, recur elseBranch with
          | some first, some second, some third =>
              some (Level.max first (Level.max second third))
          | _, _, _ => none
      | .case arms _ =>
          levelJoin (arms.map (fun arm =>
            match arm.guard with
            | some guard =>
                match recur guard, recur arm.value with
                | some guardLevel, some valueLevel =>
                    some (Level.max guardLevel valueLevel)
                | _, _ => none
            | none => recur arm.value))
      | .letIn definitions body _ =>
          let extended := definitions.foldl
            (fun accumulated definition =>
              match expressionLevel fuel symbols
                  (accumulated ++ definition.parameters.map
                    (fun parameter => (parameter.name, Level.constant)))
                  definition.body with
              | some level => accumulated ++ [(definition.name, level)]
              | none => accumulated)
            bounds
          expressionLevel fuel symbols extended body
      | .choose boundList body _ =>
          let extended := bindings bounds boundList
          match
            levelJoin (boundList.map (fun bound =>
              match bound.domain with
              | some domain => recur domain
              | none => some Level.constant)),
            expressionLevel fuel symbols extended body with
          | some domains, some result => some (Level.max domains result)
          | _, _ => none
      | .quantifier _ boundList body _ =>
          let extended := bindings bounds boundList
          match
            levelJoin (boundList.map (fun bound =>
              match bound.domain with
              | some domain => recur domain
              | none => some Level.constant)),
            expressionLevel fuel symbols extended body with
          | some domains, some result => some (Level.max domains result)
          | _, _ => none
      | .setBuilder element boundList _ =>
          let extended := bindings bounds boundList
          match
            levelJoin (boundList.map (fun bound =>
              match bound.domain with
              | some domain => recur domain
              | none => some Level.constant)),
            expressionLevel fuel symbols extended element with
          | some domains, some elementLevel => some (Level.max domains elementLevel)
          | _, _ => none
      | .setFilter boundList predicate _ =>
          let extended := bindings bounds boundList
          match
            levelJoin (boundList.map (fun bound =>
              match bound.domain with
              | some domain => recur domain
              | none => some Level.constant)),
            expressionLevel fuel symbols extended predicate with
          | some domains, some predicateLevel => some (Level.max domains predicateLevel)
          | _, _ => none
      | .except base specifications _ =>
          match recur base,
              levelJoin (specifications.map (fun specification =>
                match
                  levelJoin (specification.path.map (fun element =>
                    match element with
                    | .field _ _ => some Level.constant
                    | .index index _ => recur index)),
                  recur specification.value with
                | some indices, some value => some (Level.max indices value)
                | _, _ => none)) with
          | some baseLevel, some specificationLevel =>
              some (Level.max baseLevel specificationLevel)
          | _, _ => none
      | .currentValue _ => some Level.constant

/-- Level of one operator definition body: formal parameters are constant level
until an application supplies a higher-level argument. -/
def definitionLevel (fuel : Nat) (symbols : SymbolLevels)
    (bounds : Array (String × Level)) (definition : OperatorDefinition) :
    Option Level :=
  expressionLevel fuel symbols
    (bounds ++ definition.parameters.map
      (fun parameter => (parameter.name, Level.constant)))
    definition.body

end Core.Tla
