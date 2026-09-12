import Core.Tla.Syntax
import Core.Tla.Lexer

/-!
# TLA+ lossless parser (Core/Tla/Parser.lean)

Revision-1 parser for the general TLA+ frontend
(`Docs/model-interface-compiler/tla-frontend-design.md`, §10 "Concrete and
abstract syntax", §11 "Parsing behavior", §20 "Diagnostics", §21 "Resource and
security limits"; task package TF2 in
`Docs/model-interface-compiler/tla-frontend-tasks.md`).

The parser consumes a `TokenStream` from `Core.Tla.Lexer` and produces one
`ParseOutcome`: a lossless concrete tree whose leaves are exactly the stream's
tokens in order, an optional normalized `ParsedModule`, and bounded structured
diagnostics. It performs no filesystem access, module traversal, name
resolution, substitution, or level checking.

Precedence and associativity are data: `ParserProfile` carries the operator
table, and every entry point takes the parser profile it must use, so a caller
can substitute a modified table without touching parser code. Lexer spelling
normalization stays in `LanguageProfile`; the parser table only classifies the
already-normalized canonical spelling. Fixity comes from that table alone: a
symbolic spelling the table does not own is never an infix or prefix operator,
so `3 \frob 4` and `x \frob y == e` fail as the reference parser fails them.
The reference parser reads such a spelling as a user postfix operator, which is
why `3 \frob` applies it.

Diagnostics use bounded recovery at declaration and delimiter synchronization
points. A result containing an error diagnostic never carries a module.

Proof regions are opaque. `PROOF OMITTED` and `PROOF OBVIOUS` are one-token
terminals, a terminal `BY` step runs to the next module declaration, and a
structured `PROOF ... QED` region is scanned for step labels, nested proof
scopes, and delimiters. Proof-local declarations therefore never escape as
module declarations, and a region without its matching `QED` fails closed.

Termination has two bounds. Every recursively nested syntax form runs its
interior under one `withNesting` guard, so input deeper than `maxNestingDepth`
fails closed with `TLA-PARSE-NESTING-DEPTH` before a deep walk can exhaust the
stack. A structural fuel parameter stays as the separate totality backstop:
every recursive call consumes one unit of a budget initialized to thirty-two
units per token plus a fixed allowance, and exhaustion reports its own error
(`TLA-PARSE-RECURSION-LIMIT`).

`parseStream` admits one token stream only: the stream must carry exactly one
`eof` token in final position and its lossless text must reproduce the captured
unit. Any other stream fails without a module.
-/

namespace Core.Tla

/-! ## Limits and diagnostic codes -/

/-- Explicit parser limits (`Docs/model-interface-compiler/tla-language-profile.md` §8).
`maxDeclarations`, `maxDiagnostics`, and `maxNestingDepth` are frozen for
revision 1; the byte budget accompanies the count budget. -/
structure ParserLimits where
  /-- Maximum module declarations before a limit diagnostic stops the module. -/
  maxDeclarations : Nat := 4096
  /-- Maximum nested-expression depth; exceeding it is a limit failure, not a
  syntax error. -/
  maxNestingDepth : Nat := 256
  /-- Maximum accumulated diagnostics. -/
  maxDiagnostics : Nat := 64
  /-- Maximum accumulated diagnostic bytes. -/
  maxDiagnosticBytes : Nat := 1024 * 1024
  deriving Repr, BEq, DecidableEq

namespace ParserLimits

/-- Diagnostic budgets derived from the parser limits. -/
def diagnosticLimits (limits : ParserLimits) : DiagnosticLimits :=
  { maxCount := limits.maxDiagnostics, maxBytes := limits.maxDiagnosticBytes }

end ParserLimits

/- Stable parser diagnostic codes. -/
namespace ParseCode

/-- The module header is missing or malformed. -/
def moduleHeader : String := "TLA-PARSE-MODULE-HEADER"
/-- The module terminator `====` is missing before end of input. -/
def moduleEnd : String := "TLA-PARSE-MODULE-END"
/-- Tokens follow the module terminator. -/
def trailingContent : String := "TLA-PARSE-TRAILING-CONTENT"
/-- A reserved word appeared where a declared name is required. -/
def expectedIdentifier : String := "TLA-PARSE-EXPECTED-IDENTIFIER"
/-- A token appeared where an expression is required. -/
def expectedExpression : String := "TLA-PARSE-EXPECTED-EXPRESSION"
/-- A quantifier group wrote a bounded binder and then an unbounded name; the
group's extent is ambiguous, so it is rejected instead of guessed. -/
def mixedBounds : String := "TLA-PARSE-MIXED-BOUNDS"
/-- A specific token (keyword, delimiter, or operator) was required. -/
def expectedToken : String := "TLA-PARSE-EXPECTED-TOKEN"
/-- The declaration count limit stopped the module. -/
def declarationLimit : String := "TLA-PARSE-DECLARATION-LIMIT"
/-- Nested expressions exceeded `maxNestingDepth`. -/
def nestingDepth : String := "TLA-PARSE-NESTING-DEPTH"
/-- The parser's structural fuel was exhausted; no input can reach this without
first exceeding a checked limit. -/
def recursionLimit : String := "TLA-PARSE-RECURSION-LIMIT"
/-- Two operators at one precedence level were mixed or chained without
parentheses. -/
def precedenceConflict : String := "TLA-PARSE-PRECEDENCE-CONFLICT"
/-- A PlusCal module was captured; revision 1 rejects it instead of treating
the algorithm block as an inert comment. -/
def pluscal : String := "TLA-PARSE-PLUSCAL-STAGED"
/-- A spelling outside the revision-1 profile reached the parser. -/
def unsupportedSpelling : String := "TLA-PARSE-UNSUPPORTED-SPELLING"
/-- An opaque proof region reached the module terminator or end of input before
its matching top-level `QED`. -/
def proofTermination : String := "TLA-PARSE-PROOF-TERMINATION"
/-- Proof scanning met syntax it cannot keep opaque without ambiguity: a module
declaration keyword inside a proof region, a malformed or mismatched step
label, a `BY` step without arguments, or an unmatched delimiter. -/
def proofUnsupported : String := "TLA-PARSE-PROOF-UNSUPPORTED"
/-- The diagnostic budget dropped further diagnostics. -/
def diagnosticsTruncated : String := "TLA-PARSE-DIAGNOSTICS-TRUNCATED"
/-- The token stream is missing its final `eof`, duplicates `eof`, or carries
tokens after `eof`. -/
def streamEof : String := "TLA-PARSE-STREAM-EOF"
/-- The token stream's lossless text does not reproduce the captured unit. -/
def streamTextMismatch : String := "TLA-PARSE-STREAM-TEXT-MISMATCH"

end ParseCode

/-! ## Operator table -/

/-- Surface fixity of one operator spelling. -/
inductive SymbolFixity where
  | prefix
  | infix
  | postfix
  deriving Repr, BEq, DecidableEq

/-- How repeated operators at one precedence level combine. `none` rejects any
chain; `same` accepts repeats of one spelling and rejects mixing two; `left`
and `right` accept chains of any operators at the level. -/
inductive OperatorAssociation where
  | «none»
  | left
  | right
  | same
  deriving Repr, BEq, DecidableEq

/-- One operator identity: canonical spelling, fixity, precedence level, and how
chains combine. Spellings reach this table already normalized by the lexer's
`LanguageProfile`; the parser never re-implements alias normalization here. -/
structure OperatorEntry where
  canonical : String
  fixity : SymbolFixity
  level : Nat
  association : OperatorAssociation
  deriving Repr, BEq

namespace OperatorEntry

/-- `true` when `spelling` names this operator identity. -/
def accepts (entry : OperatorEntry) (spelling : String) : Bool :=
  entry.canonical == spelling

end OperatorEntry

/-- Precedence levels, loosest first. Level `0` is the implicit entry level
below every table operator; no `OperatorEntry` carries it. -/
def levelEquivalence : Nat := 1
def levelImplication : Nat := 2
def levelDisjunction : Nat := 3
def levelConjunction : Nat := 4
def levelRelational : Nat := 5
def levelRange : Nat := 6
def levelAdditive : Nat := 7
def levelMultiplicative : Nat := 8
def levelPower : Nat := 9
def levelPrefix : Nat := 10

/-- The parser-owned half of the language profile: the operator table that
fixes fixity, precedence, and associativity for one revision. Lexer spelling
normalization stays in `LanguageProfile`; this profile only classifies the
canonical spellings the lexer produces. -/
structure ParserProfile where
  name : String
  operators : Array OperatorEntry
  deriving Repr, BEq

namespace ParserProfile

/-- The revision-1 operator table, in the lexer's canonical spellings.
Precedence follows TLA+: `*` binds tighter than `+`, arithmetic tighter than
relational operators, relational tighter than `/\`, and `/\` tighter than
`\/`; `~` binds tighter than `/\`; `=>` and `<=>` are
non-associative and neither chain nor mix. The word-ASCII spellings the profile
§4.7 publishes (`\circ`, `\oplus`, `\prec`, `\succ`, `\sim`, `\approx`,
`\bullet`, `\star`, `\bigcirc`) sit in their reference classes. A symbolic
spelling outside this table is never an infix operator; the reference parser
reads it as a user postfix operator only. -/
def revisionOneOperators : Array OperatorEntry := #[
  ⟨"~", .prefix, levelPrefix, .«none»⟩,
  ⟨"-", .prefix, levelPrefix, .«none»⟩,
  ⟨"[]", .prefix, levelPrefix, .«none»⟩,
  ⟨"<>", .prefix, levelPrefix, .«none»⟩,
  ⟨"<=>", .infix, levelEquivalence, .«none»⟩,
  ⟨"=>", .infix, levelImplication, .«none»⟩,
  ⟨"~>", .infix, levelImplication, .«none»⟩,
  ⟨"/\\", .infix, levelConjunction, .same⟩,
  ⟨"\\/", .infix, levelDisjunction, .same⟩,
  ⟨"=", .infix, levelRelational, .«none»⟩,
  ⟨"#", .infix, levelRelational, .«none»⟩,
  ⟨"<", .infix, levelRelational, .«none»⟩,
  ⟨">", .infix, levelRelational, .«none»⟩,
  ⟨"=<", .infix, levelRelational, .«none»⟩,
  ⟨">=", .infix, levelRelational, .«none»⟩,
  ⟨"\\in", .infix, levelRelational, .«none»⟩,
  ⟨"\\notin", .infix, levelRelational, .«none»⟩,
  ⟨"\\subseteq", .infix, levelRelational, .«none»⟩,
  ⟨"\\subset", .infix, levelRelational, .«none»⟩,
  ⟨"\\supseteq", .infix, levelRelational, .«none»⟩,
  ⟨"\\supset", .infix, levelRelational, .«none»⟩,
  ⟨"\\prec", .infix, levelRelational, .«none»⟩,
  ⟨"\\succ", .infix, levelRelational, .«none»⟩,
  ⟨"\\sim", .infix, levelRelational, .«none»⟩,
  ⟨"\\approx", .infix, levelRelational, .«none»⟩,
  ⟨"..", .infix, levelRange, .«none»⟩,
  ⟨"+", .infix, levelAdditive, .left⟩,
  ⟨"-", .infix, levelAdditive, .left⟩,
  ⟨"\\cup", .infix, levelAdditive, .left⟩,
  ⟨"\\cap", .infix, levelAdditive, .left⟩,
  ⟨"\\oplus", .infix, levelAdditive, .left⟩,
  ⟨"\\", .infix, levelAdditive, .left⟩,
  ⟨"*", .infix, levelMultiplicative, .left⟩,
  ⟨"/", .infix, levelMultiplicative, .left⟩,
  ⟨"\\circ", .infix, levelMultiplicative, .left⟩,
  ⟨"\\div", .infix, levelMultiplicative, .left⟩,
  ⟨"%", .infix, levelMultiplicative, .left⟩,
  ⟨"\\o", .infix, levelMultiplicative, .left⟩,
  ⟨"\\bullet", .infix, levelMultiplicative, .left⟩,
  ⟨"\\star", .infix, levelMultiplicative, .left⟩,
  ⟨"\\bigcirc", .infix, levelMultiplicative, .left⟩,
  ⟨"\\X", .infix, levelMultiplicative, .left⟩,
  ⟨"^", .infix, levelPower, .left⟩]

/-- The frozen revision-1 combination: operator table and profile name
`mirrors-tla-frontend-profile-1`. -/
def default : ParserProfile :=
  { name := "mirrors-tla-frontend-profile-1"
    operators := revisionOneOperators }

/-- The tightest precedence level the profile defines. Levels above it parse
prefix-first, and the prefix level itself stays tighter than every infix the
revision-1 grammar can write. -/
def tightestLevel (profile : ParserProfile) : Nat :=
  profile.operators.foldl (fun best entry => Nat.max best entry.level)
    (levelPrefix - 1)

/-- Operator identity of a canonical spelling with the requested fixity. `-` has
both a prefix and an infix entry, so lookups always name the fixity the grammar
expects. -/
def findOperator? (profile : ParserProfile) (spelling : String)
    (fixity : SymbolFixity) : Option OperatorEntry :=
  profile.operators.findSome? fun entry =>
    if entry.accepts spelling && entry.fixity == fixity then some entry else none

end ParserProfile

/-- Profile canonicalization of one symbol spelling, falling back to the
token's own canonical spelling for spellings outside the profile. -/
def symbolSpelling (profile : LanguageProfile) (token : Token) : String :=
  match token.kind with
  | .symbol symbol => (profile.canonicalFor? symbol.canonical).getD symbol.canonical
  | _ => token.spelling

/-- Spellings that never act as user-defined postfix operators even though the
profile does not know them. `\A` and `\E` are quantifiers, not operators. -/
def structuralOperatorExclusions : Array String := #["\\A", "\\E"]

/-- `true` for a spelling in the user-defined symbolic operator class: a
backslash spelling that is not a quantifier. The profile's table owns every
other operator, so only these spellings can act as user postfix operators. -/
def isUserOperatorSpelling (spelling : String) : Bool :=
  spelling.startsWith "\\" && !structuralOperatorExclusions.contains spelling

/-- `true` for a spelling the profile does not own as infix or prefix, which is
what lets the grammar read it as a user-defined postfix operator. `\A` and `\E`
stay quantifiers. -/
def isUserPostfixSpelling (parserProfile : ParserProfile)
    (spelling : String) : Bool :=
  isUserOperatorSpelling spelling &&
    (ParserProfile.findOperator? parserProfile spelling .infix).isNone &&
    (ParserProfile.findOperator? parserProfile spelling .prefix).isNone

/-- Infix operator identity of a symbol token. Only the profile's table defines
infix operators: a symbolic spelling outside the table is never infix, so
`3 \frob 4` and `x \frob y == e` fail as the reference parser fails them. -/
def infixOperatorOf? (parserProfile : ParserProfile) (profile : LanguageProfile)
    (token : Token) : Option OperatorEntry :=
  match token.kind with
  | .symbol _ =>
      ParserProfile.findOperator? parserProfile
        (symbolSpelling profile token) .infix
  | _ => none

/-- Prefix operator identity of a symbol token. -/
def prefixOperatorOf? (parserProfile : ParserProfile) (profile : LanguageProfile)
    (token : Token) : Option OperatorEntry :=
  match token.kind with
  | .symbol _ =>
      ParserProfile.findOperator? parserProfile (symbolSpelling profile token) .prefix
  | _ => none

/-- Postfix operator identity of a symbol token. -/
def postfixOperatorOf? (parserProfile : ParserProfile)
    (profile : LanguageProfile) (token : Token) : Option OperatorEntry :=
  match token.kind with
  | .symbol _ =>
      ParserProfile.findOperator? parserProfile (symbolSpelling profile token) .postfix
  | _ => none

/-- Canonical identity of a symbol that can introduce a postfix definition. A
profile postfix entry wins; otherwise a spelling the profile does not own is a
user-defined postfix operator. -/
def postfixDefinitionName? (parserProfile : ParserProfile)
    (profile : LanguageProfile) (token : Token) : Option String :=
  match token.kind with
  | .symbol _ =>
      let spelling := symbolSpelling profile token
      match postfixOperatorOf? parserProfile profile token with
      | some entry => some entry.canonical
      | none => if isUserPostfixSpelling parserProfile spelling then some spelling else none
  | _ => none

/-- Canonical identity of a symbol that can introduce a prefix definition. The
reference parser accepts `~ x == e` and `[] x == e` but rejects `- x == e`,
because `-` also has an infix entry; a prefix definition therefore needs a
prefix entry and no infix entry. -/
def prefixDefinitionOf? (parserProfile : ParserProfile) (profile : LanguageProfile)
    (token : Token) : Option String :=
  match token.kind with
  | .symbol _ =>
      let spelling := symbolSpelling profile token
      match ParserProfile.findOperator? parserProfile spelling .prefix with
      | some entry =>
          if (ParserProfile.findOperator? parserProfile spelling .infix).isSome then none
          else some entry.canonical
      | none => none
  | _ => none

/-! ## Parser state -/

/-- One open concrete-syntax frame. `children` are the already-consumed children
in source order; `fallback` is the extent of a frame that consumed nothing. -/
structure Frame where
  kind : CstKind
  fallback : SourceRange
  children : Array CstNode := #[]
  deriving Repr

/-- Parser state: the lexer profile, the parser profile with its operator table,
the limits, the captured unit, its token stream, the open frame stack, the
bounded diagnostics, and the declarations collected so far. `lastStop` is the
end position of the last consumed token, which is where an empty frame starts. -/
structure ParserState where
  profile : LanguageProfile
  parserProfile : ParserProfile
  limits : ParserLimits
  source : SourceUnit
  tokens : Array Token
  position : Nat := 0
  lastStop : SourcePosition := ⟨0, 1, 1⟩
  nesting : Nat := 0
  frames : List Frame := []
  diagnostics : DiagnosticBuffer := {}
  declarations : Array Declaration := #[]
  declarationCount : Nat := 0
  moduleName : Option ModuleName := none
  moduleRange : SourceRange := zeroRange
  /-- Column of an enclosing prefix-junction list. A `/\` or `\/` at this
  column starts the next list item instead of becoming part of the current
  item's expression. -/
  junctionBoundaryColumn : Option Nat := none
  halted : Bool := false

/-- The parser is a pure state-passing computation. -/
abbrev ParserM := StateT ParserState Id

/-! ## Frames and leaves -/

def pushChild (frames : List Frame) (child : CstNode) : List Frame :=
  match frames with
  | [] => []
  | frame :: rest => { frame with children := frame.children.push child } :: rest

/-- Extent of a node built from `children`: the first child's start through the
last child's stop, or the frame's fallback when it has no child. -/
def nodeRange (fallback : SourceRange) (children : List CstNode) : SourceRange :=
  match children with
  | [] => fallback
  | first :: _ =>
      match children.getLast? with
      | some last => ⟨first.range.start, last.range.stop⟩
      | none => fallback

def wrapFrame (frame : Frame) : CstNode :=
  let children := frame.children.toList
  .node frame.kind (nodeRange frame.fallback children) children

def emptyRoot : CstModule :=
  { root := .node .moduleRoot zeroRange [] }

/-! ## Token access -/

def peek? : ParserM (Option Token) := do
  let state ← get
  return state.tokens[state.position]?

def peekAt? (offset : Nat) : ParserM (Option Token) := do
  let state ← get
  return state.tokens[state.position + offset]?

/-- Extent of the token the parser is looking at, or of the last consumed token
at end of input. -/
def currentRange : ParserM SourceRange := do
  let state ← get
  match state.tokens[state.position]? with
  | some token => return token.range
  | none => return ⟨state.lastStop, state.lastStop⟩

def currentStop : ParserM SourcePosition := do
  let state ← get
  return state.lastStop

def position : ParserM Nat := do
  let state ← get
  return state.position

def halted? : ParserM Bool := do
  let state ← get
  return state.halted

def profileOf : ParserM LanguageProfile := do
  let state ← get
  return state.profile

def parserProfileOf : ParserM ParserProfile := do
  let state ← get
  return state.parserProfile

/-- Consume the current token as a leaf of the innermost frame. The `eof` token
is never consumed here; the final drain retains it. -/
def advance : ParserM Unit := do
  let state ← get
  match state.tokens[state.position]? with
  | none => pure ()
  | some token =>
      if token.kind.isEof then
        pure ()
      else
        set { state with
              position := state.position + 1
              lastStop := token.range.stop
              frames := pushChild state.frames (.token token) }

def openFrame (kind : CstKind) : ParserM Unit := do
  let state ← get
  set { state with
        frames := { kind, fallback := ⟨state.lastStop, state.lastStop⟩ } :: state.frames }

def closeFrame : ParserM Unit := do
  let state ← get
  match state.frames with
  | [] => pure ()
  | frame :: rest =>
      set { state with frames := pushChild rest (wrapFrame frame) }

/-- Close frames until `remaining` of them are open. `fuel` bounds the walk. -/
def closeFramesTo (fuel remaining : Nat) : ParserM Unit := do
  if fuel = 0 then
    pure ()
  else
    let state ← get
    if state.frames.length > remaining then
      closeFrame
      closeFramesTo (fuel - 1) remaining
    else
      pure ()

/-! ## Diagnostics -/

def stateLocation (state : ParserState) (range : SourceRange) : SourceLocation :=
  { moduleName := state.moduleName, logicalPath := state.source.logicalPath, range }

/-- Append one parse error, honouring the diagnostic count and byte budgets. -/
def emitError (code message : String) (range : SourceRange) : ParserM Unit := do
  let state ← get
  let diagnostic : Diagnostic :=
    { code
      severity := .error
      stage := .parse
      message
      primary := stateLocation state range
      related := #[]
      arguments := #[] }
  set { state with
        diagnostics := DiagnosticBuffer.push
          (ParserLimits.diagnosticLimits state.limits) state.diagnostics diagnostic }

/-- A limit or conflict failure stops the walk. The diagnostics accumulated so
far already make the outcome unusable, so no partial module can escape. -/
def haltParser : ParserM Unit :=
  modify fun state => { state with halted := true }

def emitLimit (code message : String) (range : SourceRange) : ParserM Unit := do
  emitError code message range
  haltParser

/-- Run `body` one nested syntax level deeper.

This guard is the single enforcement point for `maxNestingDepth`: when the
level would exceed the limit, the parser reports the limit failure at `opening`
and returns `none` without running `body`. Every path that runs `body` restores
the previous nesting state exactly, so a failed or halted nested walk cannot
leak depth into a sibling. -/
def withNesting (opening : SourceRange) (body : ParserM α) : ParserM (Option α) := do
  let state ← get
  if state.nesting + 1 > state.limits.maxNestingDepth then do
    emitLimit ParseCode.nestingDepth
      s!"nested syntax exceeds the depth limit of {state.limits.maxNestingDepth}"
      opening
    return none
  else do
    let saved := state.nesting
    set { state with nesting := saved + 1 }
    let result ← body
    modify fun current => { current with nesting := saved }
    return some result

/-- Bounded rendering of a token spelling for a diagnostic message. Source text
never enters a message beyond this bounded excerpt. -/
def renderSpelling (spelling : String) : String :=
  if spelling.length > 24 then (spelling.take 24).toString ++ "..." else spelling

/-- Decoded value of one validated string token. `spelling` is the raw source
text including its quotes; each escape the lexer admits (`\"`, `\\`, `\t`,
`\n`, `\r`, `\f`) is interpreted exactly once and every other character stays
verbatim. The CST keeps the spelling, so source fidelity does not depend on
this value and a decoded backslash is never decoded again. -/
def decodeStringLiteral (spelling : String) : String :=
  let body := match spelling.toList with
    | '"' :: rest =>
        match rest.reverse with
        | '"' :: reversed => reversed.reverse
        | _ => rest
    | other => other
  String.ofList (decodeEscapes body)
where
  /-- Decode the escape sequences inside one string body. Unknown escapes are
  kept, which keeps the helper total for hand-built streams. -/
  decodeEscapes : List Char → List Char
    | [] => []
    | '\\' :: escaped :: rest =>
        (match escaped with
          | '"' => '"'
          | '\\' => '\\'
          | 't' => '\t'
          | 'n' => '\n'
          | 'r' => '\r'
          | 'f' => Char.ofNat 12
          | other => other) :: decodeEscapes rest
    | '\\' :: [] => ['\\']
    | character :: rest => character :: decodeEscapes rest

/-! ## Token classification -/

def keywordOf? (token : Token) : Option String :=
  match token.kind with
  | .keyword spelling => some spelling
  | _ => none

def symbolOf? (profile : LanguageProfile) (token : Token) : Option String :=
  match token.kind with
  | .symbol _ => some (symbolSpelling profile token)
  | _ => none

def identifierOf? (token : Token) : Option String :=
  match token.kind with
  | .identifier => some token.spelling
  | _ => none

/-- Module name and operator name of a `Name!Declaration` token. -/
def qualifiedOf? (token : Token) : Option (String × String) :=
  match token.kind with
  | .qualifiedName =>
      match token.spelling.splitOn "!" with
      | [qualifier, name] => some (qualifier, name)
      | _ => none
  | _ => none

/-- `true` when the token is the symbol `canonical` under the profile. -/
def isSymbolToken (profile : LanguageProfile) (token : Token) (canonical : String) :
    Bool :=
  match symbolOf? profile token with
  | some spelling => spelling == canonical
  | none => false

def peekSymbol (canonical : String) : ParserM Bool := do
  let profile ← profileOf
  match ← peek? with
  | some token => return isSymbolToken profile token canonical
  | none => return false

def peekKeyword (canonical : String) : ParserM Bool := do
  match ← peek? with
  | some token => return token.kind.isKeyword canonical
  | none => return false

/-- Consume the current token when it is the symbol `canonical`. -/
def consumeSymbol (canonical : String) : ParserM Bool := do
  if (← peekSymbol canonical) then
    advance
    return true
  else
    return false

/-- Consume the current token when it is the reserved word `canonical`. -/
def consumeKeyword (canonical : String) : ParserM Bool := do
  if (← peekKeyword canonical) then
    advance
    return true
  else
    return false

/-- Consume the current token when it is an identifier. -/
def consumeIdentifier : ParserM (Option String) := do
  match ← peek? with
  | some token =>
      match identifierOf? token with
      | some name => do
          advance
          return some name
      | none => return none
  | none => return none

def expectSymbol (canonical : String) : ParserM Bool := do
  if (← consumeSymbol canonical) then
    return true
  else
    let range ← currentRange
    emitError ParseCode.expectedToken s!"expected '{canonical}'" range
    return false

def expectKeyword (canonical : String) : ParserM Bool := do
  if (← consumeKeyword canonical) then
    return true
  else
    let range ← currentRange
    emitError ParseCode.expectedToken s!"expected the reserved word '{canonical}'" range
    return false

/-- Consume a declared name, reporting a reserved word or any other token that
cannot be a name. -/
def expectName : ParserM (Option (String × SourceRange)) := do
  match ← peek? with
  | some token =>
      match identifierOf? token with
      | some name => do
          advance
          return some (name, token.range)
      | none => do
          emitError ParseCode.expectedIdentifier
            s!"expected a name but found '{renderSpelling token.spelling}'" token.range
          return none
  | none => do
      let range ← currentRange
      emitError ParseCode.expectedIdentifier "expected a name before end of input" range
      return none

/-! ## Declarations starting a module statement -/

def declarationKeywords : Array String := #[
  "CONSTANT", "CONSTANTS", "VARIABLE", "VARIABLES", "RECURSIVE", "LOCAL",
  "EXTENDS", "INSTANCE", "ASSUME", "ASSUMPTION", "AXIOM", "THEOREM", "LEMMA",
  "PROPOSITION", "COROLLARY"]

def isDeclarationKeyword (canonical : String) : Bool :=
  declarationKeywords.contains canonical

/-- `true` when `position` starts a module declaration. Recovery resumes here so
one malformed statement cannot hide the declarations that follow it. -/
def startsDeclarationAt? (profile : LanguageProfile) (tokens : Array Token)
    (position : Nat) : Bool :=
  match tokens[position]? with
  | none => false
  | some token =>
      match keywordOf? token with
      | some keyword => isDeclarationKeyword keyword
      | none =>
          match token.kind with
          | .identifier =>
              match tokens[position + 1]? with
              | some next =>
                  match symbolOf? profile next with
                  | some spelling => spelling == "=="
                  | none => false
              | none => false
          | _ => false

/-- `true` for comment trivia that carries a PlusCal marker. -/
def plusCalText? (spelling : String) : Bool :=
  (spelling.splitOn "--algorithm").length > 1 ||
    (spelling.splitOn "--fair algorithm").length > 1

def tokenPlusCalRange? (token : Token) : Option SourceRange :=
  let trivia := token.leadingTrivia ++ token.trailingTrivia
  trivia.findSome? fun item =>
    match item.kind with
    | .lineComment | .blockComment =>
        if plusCalText? item.spelling then some item.range else none
    | _ => none

/-- The first PlusCal marker of a captured module, if any. -/
def plusCalRange? (tokens : Array Token) : Option SourceRange :=
  tokens.findSome? tokenPlusCalRange?

/-! ## Expression construction helpers -/

/-- Placeholder expression for a halted path. It only appears in a diagnostic
tree: the halt already carries an error diagnostic, so `module?` is absent. -/
def placeholderExpression (range : SourceRange) : Expression :=
  .currentValue range

def applicationRange (start : SourcePosition) (arguments : Array Expression) :
    SourceRange :=
  match arguments.back? with
  | some last => ⟨start, last.range.stop⟩
  | none => ⟨start, start⟩

def applyOperator (spelling : String) (operatorRange : SourceRange)
    (arguments : Array Expression) (range : SourceRange) : Expression :=
  .apply { qualifier := none, spelling, range := operatorRange } arguments range

def infixApplication (entry : OperatorEntry) (left right : Expression) : Expression :=
  let range : SourceRange := ⟨left.range.start, right.range.stop⟩
  applyOperator entry.canonical range #[left, right] range

def prefixApplication (spelling : String) (argument : Expression)
    (operatorRange : SourceRange) : Expression :=
  let range : SourceRange := ⟨operatorRange.start, argument.range.stop⟩
  applyOperator spelling operatorRange #[argument] range

/-- Bound of `name \in domain`, the shape quantifier, comprehension, and
function bounds share. -/
def boundOf? (expression : Expression) : Option Bound :=
  match expression with
  | .apply operator arguments _ =>
      if operator.spelling == "\\in" && arguments.size == 2 then
        match (arguments[0]? : Option Expression) with
        | some (.name reference _) =>
            match (arguments[1]? : Option Expression) with
            | some domain =>
                some { name := reference.spelling
                       domain := some domain
                       range := expression.range }
            | none => none
        | _ => none
      else
        none
  | _ => none

def recordFieldName? (expression : Expression) : Option String :=
  match expression with
  | .name reference _ => if reference.qualifier.isNone then some reference.spelling else none
  | _ => none

/-- Run one junction-list item while retaining every other parser-state
change. -/
def withJunctionBoundary (column : Nat) (action : ParserM α) : ParserM α := do
  let previous := (← get).junctionBoundaryColumn
  modify fun state => { state with junctionBoundaryColumn := some column }
  let result ← action
  modify fun state => { state with junctionBoundaryColumn := previous }
  return result

/-- `true` when the current token begins the next item of an enclosing prefix
junction list. -/
def atJunctionBoundary : ParserM Bool := do
  let state ← get
  match state.junctionBoundaryColumn, state.tokens[state.position]? with
  | some column, some token =>
      let spelling := symbolSpelling state.profile token
      return (spelling == "/\\" || spelling == "\\/") &&
        token.range.start.column == column
  | _, _ => return false

/-- Message for a repeat that the profile does not define: chaining a
non-associative operator, or mixing two operators that share one precedence
level. `none` means the repeat is defined. -/
def associationConflict (first : Option OperatorEntry) (entry : OperatorEntry) :
    Option String :=
  match first with
  | none => none
  | some previous =>
      if previous.canonical == entry.canonical then
        match entry.association with
        | .«none» =>
            some s!"'{entry.canonical}' does not chain without parentheses"
        | _ => none
      else
        match entry.association with
        | .left => none
        | .right => none
        | _ =>
            some s!"'{previous.canonical}' and '{entry.canonical}' share one precedence level and need parentheses"

/-! ## Expression parsing -/

mutual

/-- Parse an expression at `level`: operators tighter than `level` bind inside
the operands. `fuel` is the explicit resource bound; every recursive call
consumes one unit. -/
def parseExpression (fuel level : Nat) : ParserM Expression := do
  if fuel = 0 then do
    let range ← currentRange
    emitLimit ParseCode.recursionLimit
      "parser resource budget exhausted before a checked limit" range
    return placeholderExpression range
  else
    openFrame .expression
    let expression ← parseExpressionLevel (fuel - 1) level
    closeFrame
    return expression

/-- One precedence level: a tighter operand, then the infix chain at this level.
Chains the profile does not define are conflicts, never a guess. -/
def parseExpressionLevel (fuel level : Nat) : ParserM Expression := do
  let parserProfile ← parserProfileOf
  if level > ParserProfile.tightestLevel parserProfile then
    parsePrefix fuel
  else
    -- A conjunction or disjunction list may open with its own operator, which
    -- is how the revision-1 corpus writes bullets (`Name ==` followed by
    -- `/\ ...` lines). Each item is a complete expression; a later junction
    -- at the opening column starts the next item even when the current item
    -- contains a looser operator such as `=>` or the other junction kind.
    match ← nextInfixAt? level with
    | some leading =>
        if leading.level == levelConjunction ||
            leading.level == levelDisjunction then
          let opening ← currentRange
          advance
          let mut left ← withJunctionBoundary opening.start.column
            (parseExpression fuel 0)
          let mut going := true
          while going do
            match ← nextInfixAt? level with
            | some entry =>
                let range ← currentRange
                if range.start.column == opening.start.column then
                  if entry.canonical == leading.canonical then
                    advance
                    let right ← withJunctionBoundary opening.start.column
                      (parseExpression fuel 0)
                    left := infixApplication leading left right
                  else
                    emitLimit ParseCode.precedenceConflict
                      s!"a prefix '{leading.canonical}' list cannot continue with '{entry.canonical}' at the same indentation"
                      range
                    going := false
                else
                  going := false
            | none => going := false
          return left
    | none => pure ()
    let mut first : Option OperatorEntry := none
    let mut left ← parseExpression fuel (level + 1)
    let mut going := true
    while going do
      if (← halted?) then
        going := false
      else
        if (← atJunctionBoundary) then
          going := false
        else match ← nextInfixAt? level with
        | none => going := false
        | some entry =>
            match associationConflict first entry with
            | some message =>
                let range ← currentRange
                emitLimit ParseCode.precedenceConflict message range
                going := false
            | none =>
                advance
                let right ← parseExpression fuel (level + 1)
                left := infixApplication entry left right
                if first.isNone then
                  first := some entry
    return left

/-- Infix operator at exactly `level` that the next token starts, if any. -/
def nextInfixAt? (level : Nat) : ParserM (Option OperatorEntry) := do
  let state ← get
  match state.tokens[state.position]? with
  | none => return none
  | some token =>
      match infixOperatorOf? state.parserProfile state.profile token with
      | none => return none
      | some entry => return if entry.level == level then some entry else none

/-- Prefix operators, quantifiers, and the operand itself. -/
def parsePrefix (fuel : Nat) : ParserM Expression := do
  let range ← currentRange
  match ← peek? with
  | none => do
      emitError ParseCode.expectedExpression "expected an expression before end of input" range
      return placeholderExpression range
  | some token =>
      match keywordOf? token with
      | some keyword =>
          match keyword with
          | "ENABLED" | "UNCHANGED" | "DOMAIN" | "SUBSET" | "UNION" => do
              advance
              match ← withNesting token.range (parseExpression fuel levelPrefix) with
              | some argument => return prefixApplication keyword argument token.range
              | none => return placeholderExpression token.range
          | "WF_" => parseFairness fuel "WF_"
          | "SF_" => parseFairness fuel "SF_"
          | "IF" => parseIf fuel
          | "CASE" => parseCase fuel
          | "LET" => parseLet fuel
          | "CHOOSE" => parseChoose fuel
          | _ => parseSymbolOrPrimary fuel
      | none => parseSymbolOrPrimary fuel

/-- Prefix operator symbols, quantifiers, and the primary operand. -/
def parseSymbolOrPrimary (fuel : Nat) : ParserM Expression := do
  let profile ← profileOf
  let parserProfile ← parserProfileOf
  let range ← currentRange
  match ← peek? with
  | none => do
      emitError ParseCode.expectedExpression "expected an expression before end of input" range
      return placeholderExpression range
  | some token =>
      match symbolOf? profile token with
      | some "\\A" => parseQuantifier fuel .forall
      | some "\\E" => parseQuantifier fuel .exists
      | some spelling =>
          match ParserProfile.findOperator? parserProfile spelling .prefix with
          | some entry => do
              advance
              match ← withNesting token.range (parseExpression fuel levelPrefix) with
              | some argument =>
                  return prefixApplication entry.canonical argument token.range
              | none => return placeholderExpression token.range
          | none => parseOperand fuel
      | none => parseOperand fuel

/-- A primary expression followed by its postfix operators. -/
def parseOperand (fuel : Nat) : ParserM Expression := do
  let primary ← parsePrimary fuel true
  parsePostfix fuel primary

def parsePrimary (fuel : Nat) (allowApplication : Bool) : ParserM Expression := do
  let range ← currentRange
  match ← peek? with
  | none => do
      emitError ParseCode.expectedExpression "expected an expression before end of input" range
      return placeholderExpression range
  | some token =>
      match token.kind with
      | .integer value => do
          advance
          return .integer value token.range
      | .string => do
          advance
          return .string (decodeStringLiteral token.spelling) token.range
      | .keyword "TRUE" => do
          advance
          return .boolean true token.range
      | .keyword "FALSE" => do
          advance
          return .boolean false token.range
      | .keyword "BOOLEAN" => do
          advance
          return .name { qualifier := none, spelling := "BOOLEAN", range := token.range } token.range
      | .keyword "STRING" => do
          advance
          return .name { qualifier := none, spelling := "STRING", range := token.range } token.range
      | .identifier => parseNamedApplication fuel token allowApplication
      | .qualifiedName => parseNamedApplication fuel token allowApplication
      | .symbol symbol =>
          match symbol.canonical with
          | "(" => parseParenthesized fuel
          | "<<" => parseAngle fuel
          | "{" => parseBrace fuel
          | "[" => parseBracket fuel
          | "@" => do
              advance
              return .currentValue token.range
          | _ =>
              match keywordOf? token with
              | some _ => do
                  emitError ParseCode.expectedExpression
                    s!"expected an expression but found '{renderSpelling token.spelling}'"
                    token.range
                  return placeholderExpression range
              | none => do
                  emitError ParseCode.expectedExpression
                    s!"expected an expression but found '{renderSpelling token.spelling}'"
                    token.range
                  return placeholderExpression range
      | _ => do
          emitError ParseCode.expectedExpression
            s!"expected an expression but found '{renderSpelling token.spelling}'" token.range
          return placeholderExpression range

/-- A declared-name use, optionally applied to an argument list. -/
def parseNamedApplication (fuel : Nat) (token : Token) (allowApplication : Bool) :
    ParserM Expression := do
  advance
  let reference : OperatorRef :=
    match qualifiedOf? token with
    | some (qualifier, name) =>
        { qualifier := some qualifier, spelling := name, range := token.range }
    | none =>
        { qualifier := none, spelling := token.spelling, range := token.range }
  if allowApplication && (← peekSymbol "(") then
    let opening ← currentRange
    let _ ← consumeSymbol "("
    match ← withNesting opening (parseDelimitedExpressions fuel ")") with
    | none =>
        let _ ← consumeSymbol ")"
        return .name reference token.range
    | some (arguments, ok) =>
        if ok then
          let range := applicationRange token.range.start arguments
          return .apply reference arguments range
        else
          return .name reference token.range
  else
    return .name reference token.range

/-- Comma-separated expressions up to the closing symbol, which is consumed on
success. -/
def parseDelimitedExpressions (fuel : Nat) (closing : String) :
    ParserM (Array Expression × Bool) := do
  let mut items : Array Expression := #[]
  let mut ok := true
  let mut done := false
  while !done do
    if (← peekSymbol closing) then
      done := true
    else if (← halted?) then
      done := true
      ok := false
    else
      let item ← parseExpression fuel 0
      items := items.push item
      if (← peekSymbol closing) then
        done := true
      else if (← consumeSymbol ",") then
        pure ()
      else
        let range ← currentRange
        emitError ParseCode.expectedToken
          s!"expected ',' or '{closing}' in a list" range
        ok := false
        done := true
  if ok then
    let _ ← consumeSymbol closing
    pure ()
  return (items, ok)

/-- Comma-separated expressions up to `}` or the `:` of a comprehension. The
closing token is not consumed; the caller decides which form it read. -/
def parseSetItems (fuel : Nat) : ParserM (Array Expression × Bool × Bool) := do
  let mut items : Array Expression := #[]
  let mut ok := true
  let mut comprehension := false
  let mut done := false
  while !done do
    if (← peekSymbol "}") then
      done := true
    else if (← peekSymbol ":") then
      comprehension := true
      done := true
    else if (← halted?) then
      done := true
      ok := false
    else
      let item ← parseExpression fuel 0
      items := items.push item
      if (← peekSymbol "}") then
        done := true
      else if (← peekSymbol ":") then
        comprehension := true
        done := true
      else if (← consumeSymbol ",") then
        pure ()
      else
        let range ← currentRange
        emitError ParseCode.expectedToken
          "expected ',', ':', or '}' in a set expression" range
        ok := false
        done := true
  return (items, ok, comprehension)

/-- `( e )`, `( e, ... )`, or a parenthesized expression. -/
def parseParenthesized (fuel : Nat) : ParserM Expression := do
  let startSpan ← currentRange
  advance
  let body : ParserM (Array Expression × Bool) := parseDelimitedExpressions fuel ")"
  match ← withNesting startSpan body with
  | none =>
      let _ ← consumeSymbol ")"
      return placeholderExpression startSpan
  | some (items, ok) =>
      if !ok then
        match items[0]? with
        | some first => return first
        | none => return placeholderExpression startSpan
      else
        match items[0]?, items.size with
        | some only, 1 => return only
        | _, _ =>
            let stop ← currentStop
            return .tuple items ⟨startSpan.start, stop⟩

/-- `<< e, ... >>`, or the angle action subscript `<<A>>_v`. -/
def parseAngle (fuel : Nat) : ParserM Expression := do
  let startSpan ← currentRange
  advance
  let body : ParserM Expression := do
    let (items, ok) ← parseDelimitedExpressions fuel ">>"
    if !ok then
      match items[0]? with
      | some first => return first
      | none => return placeholderExpression startSpan
    else
      let stop ← currentStop
      let tuple := Expression.tuple items ⟨startSpan.start, stop⟩
      if (← subscriptFollows?) then
        let subscript ← parseSubscriptElement fuel
        let range := ⟨startSpan.start, subscript.range.stop⟩
        return applyOperator "<<>>_" startSpan #[tuple, subscript] range
      else
        return tuple
  match ← withNesting startSpan body with
  | some expression => return expression
  | none =>
      let _ ← consumeSymbol ">>"
      return placeholderExpression startSpan

/-- `{ ... }`: the empty set, a set literal, a set filter, or a set builder. -/
def parseBrace (fuel : Nat) : ParserM Expression := do
  let startSpan ← currentRange
  advance
  let body : ParserM Expression := do
    if (← consumeSymbol "}") then do
      let stop ← currentStop
      return .set #[] ⟨startSpan.start, stop⟩
    else
      let (items, ok, comprehension) ← parseSetItems fuel
      if !ok then
        match items[0]? with
        | some first => return first
        | none => return placeholderExpression startSpan
      else if !comprehension then
        let _ ← expectSymbol "}"
        let stop ← currentStop
        return .set items ⟨startSpan.start, stop⟩
      else
        -- `{... : ...}`: bounds when every item is a bound, else one element.
        let _ ← consumeSymbol ":"
        let bounds := items.filterMap boundOf?
        if !items.isEmpty && bounds.size == items.size then
          let predicate ← parseExpression fuel 0
          let _ ← expectSymbol "}"
          let stop ← currentStop
          return .setFilter bounds predicate ⟨startSpan.start, stop⟩
        else
          match items[0]? with
          | none => return placeholderExpression startSpan
          | some element =>
              let bounds ← parseBounds fuel false
              let _ ← expectSymbol "}"
              let stop ← currentStop
              return .setBuilder element bounds ⟨startSpan.start, stop⟩
  match ← withNesting startSpan body with
  | some expression => return expression
  | none =>
      let _ ← consumeSymbol "}"
      return placeholderExpression startSpan

/-- `[ ... ]`: a record, a function, a function set, an `EXCEPT` update, or an
action subscript. -/
def parseBracket (fuel : Nat) : ParserM Expression := do
  let startSpan ← currentRange
  advance
  match ← withNesting startSpan (parseBracketBody fuel startSpan) with
  | some result => return result
  | none =>
      let _ ← consumeSymbol "]"
      return placeholderExpression startSpan

def parseBracketBody (fuel : Nat) (startSpan : SourceRange) : ParserM Expression := do
  let first ← parseExpression fuel 0
  if (← consumeSymbol ":") then
    match recordFieldName? first with
    | none =>
        let range ← currentRange
        emitError ParseCode.expectedExpression
          "expected a field name before ':'" range
        return placeholderExpression startSpan
    | some name => do
        let domain ← parseExpression fuel 0
        let mut fields : Array RecordField :=
          #[{ name, value := domain
              range := ⟨first.range.start, domain.range.stop⟩ }]
        while (← consumeSymbol ",") do
          let fieldRange ← currentRange
          match ← expectName with
          | none => pure ()
          | some (fieldName, _) => do
              let _ ← expectSymbol ":"
              let fieldDomain ← parseExpression fuel 0
              fields := fields.push
                { name := fieldName, value := fieldDomain
                  range := ⟨fieldRange.start, fieldDomain.range.stop⟩ }
        let _ ← expectSymbol "]"
        let stop ← currentStop
        return .recordSet fields ⟨startSpan.start, stop⟩
  else if (← consumeSymbol "|->") then
    match boundOf? first with
    | some bound => do
        let mut bounds : Array Bound := #[bound]
        while (← peekSymbol ",") do
          let _ ← consumeSymbol ","
          let item ← parseExpression fuel 0
          match boundOf? item with
          | some next => bounds := bounds.push next
          | none =>
              let range ← currentRange
              emitError ParseCode.expectedExpression
                "expected a bound 'name \\in domain' after ','" range
        let body ← parseExpression fuel 0
        let _ ← expectSymbol "]"
        let stop ← currentStop
        return .function bounds body ⟨startSpan.start, stop⟩
    | none =>
        match recordFieldName? first with
        | none =>
            let range ← currentRange
            emitError ParseCode.expectedExpression
              "expected a field name before '|->'" range
            return placeholderExpression startSpan
        | some name => do
            let value ← parseExpression fuel 0
            let mut fields : Array RecordField :=
              #[{ name, value, range := ⟨first.range.start, value.range.stop⟩ }]
            while (← consumeSymbol ",") do
              let fieldRange ← currentRange
              match ← expectName with
              | none => pure ()
              | some (fieldName, _) => do
                  let _ ← expectSymbol "|->"
                  let fieldValue ← parseExpression fuel 0
                  fields := fields.push
                    { name := fieldName, value := fieldValue
                      range := ⟨fieldRange.start, fieldValue.range.stop⟩ }
            let _ ← expectSymbol "]"
            let stop ← currentStop
            return .record fields ⟨startSpan.start, stop⟩
  else if (← consumeSymbol "->") then
    let codomain ← parseExpression fuel 0
    let _ ← expectSymbol "]"
    let stop ← currentStop
    return .functionSet first codomain ⟨startSpan.start, stop⟩
  else if (← consumeKeyword "EXCEPT") then
    let mut specifications : Array ExceptSpec := #[]
    let mut going := true
    while going do
      if (← peekSymbol "]") then
        going := false
      else
        let specification ← parseExceptSpec fuel
        specifications := specifications.push specification
        if !(← consumeSymbol ",") then
          going := false
    let _ ← expectSymbol "]"
    let stop ← currentStop
    return .except first specifications ⟨startSpan.start, stop⟩
  else if (← consumeSymbol "]") then
    if (← subscriptFollows?) then
      let subscript ← parseSubscriptElement fuel
      let range := ⟨startSpan.start, subscript.range.stop⟩
      return applyOperator "[]_" startSpan #[first, subscript] range
    else
      let range ← currentRange
      emitError ParseCode.expectedToken "expected a subscript after ']'" range
      return first
  else
    let range ← currentRange
    emitError ParseCode.expectedToken
      "expected '|->', '->', 'EXCEPT', or ']' inside brackets" range
    return first

/-- One `EXCEPT` update: `!path = value`. -/
def parseExceptSpec (fuel : Nat) : ParserM ExceptSpec := do
  let startSpan ← currentRange
  let mut path : Array ExceptPathElement := #[]
  let _ ← expectSymbol "!"
  let mut going := true
  while going do
    match ← peek? with
    | none => going := false
    | some token =>
        let profile ← profileOf
        if isSymbolToken profile token "." then do
          advance
          let segmentRange ← currentRange
          match ← expectName with
          | none => going := false
          | some (name, _) =>
              path := path.push (.field name segmentRange)
        else if isSymbolToken profile token "[" then do
          advance
          let index ← parseExpression fuel 0
          let _ ← expectSymbol "]"
          let stop ← currentStop
          path := path.push (.index index ⟨token.range.start, stop⟩)
        else
          going := false
  let _ ← expectSymbol "="
  let value ← parseExpression fuel 0
  return { path, value, range := ⟨startSpan.start, value.range.stop⟩ }

/-- `name`, `_name`, or a bracketed subscript after `]` or `>>`. -/
def parseSubscriptElement (fuel : Nat) : ParserM Expression := do
  let range ← currentRange
  match ← peek? with
  | none => do
      emitError ParseCode.expectedExpression "expected a subscript" range
      return placeholderExpression range
  | some token =>
      match token.kind with
      | .identifier =>
          if token.spelling == "_" then do
            advance
            parseExpression fuel levelPrefix
          else if token.spelling.startsWith "_" then do
            advance
            return .name
              { qualifier := none, spelling := (token.spelling.drop 1).toString, range := token.range }
              token.range
          else do
            emitError ParseCode.expectedExpression
              s!"expected a subscript but found '{renderSpelling token.spelling}'"
              token.range
            return placeholderExpression range
      | _ => do
          emitError ParseCode.expectedExpression
            s!"expected a subscript but found '{renderSpelling token.spelling}'" token.range
          return placeholderExpression range

/-- `true` when a subscript marker follows, which is how `[A]_v`, `[A]_<<v>>`,
and `<<A>>_v` are recognized. -/
def subscriptFollows? : ParserM Bool := do
  match ← peek? with
  | some token =>
      match token.kind with
      | .identifier => return token.spelling.startsWith "_"
      | _ => return false
  | none => return false

/-- Postfix `'`, function selection `f[i]`, and field selection `r.f`. -/
def parsePostfix (fuel : Nat) (expression : Expression) : ParserM Expression := do
  let mut result := expression
  let mut going := true
  while going do
    if (← halted?) then
      going := false
    else
      let profile ← profileOf
      let parserProfile ← parserProfileOf
      match ← peek? with
      | none => going := false
      | some token =>
          match symbolOf? profile token with
          | some "'" => do
              advance
              result := applyOperator "'" token.range #[result]
                ⟨result.range.start, token.range.stop⟩
          | some "[" => do
              let opening ← currentRange
              advance
              match ← withNesting opening (parseExpression fuel 0) with
              | some index =>
                  let _ ← expectSymbol "]"
                  let stop ← currentStop
                  result := .functionApply result index ⟨result.range.start, stop⟩
              | none =>
                  let _ ← consumeSymbol "]"
                  going := false
          | some "." => do
              advance
              match ← expectName with
              | none => going := false
              | some (name, fieldRange) =>
                  result := .select result name ⟨result.range.start, fieldRange.stop⟩
          | some spelling => do
              match postfixOperatorOf? parserProfile profile token with
              | some entry => do
                  advance
                  result := applyOperator entry.canonical token.range #[result]
                    ⟨result.range.start, token.range.stop⟩
              | none =>
                  if isUserPostfixSpelling parserProfile spelling then do
                    advance
                    result := applyOperator spelling token.range #[result]
                      ⟨result.range.start, token.range.stop⟩
                  else
                    going := false
          | none => going := false
  return result

/-- `IF c THEN a ELSE b`. -/
def parseIf (fuel : Nat) : ParserM Expression := do
  let startSpan ← currentRange
  advance
  openFrame .ifExpression
  let interior : ParserM Expression := do
    let condition ← parseExpression fuel 0
    let _ ← expectKeyword "THEN"
    let thenBranch ← parseExpression fuel 0
    let _ ← expectKeyword "ELSE"
    let elseBranch ← parseExpression fuel 0
    return .ifThenElse condition thenBranch elseBranch
      ⟨startSpan.start, elseBranch.range.stop⟩
  let parsed? ← withNesting startSpan interior
  closeFrame
  match parsed? with
  | some expression => return expression
  | none => return placeholderExpression startSpan

/-- `CASE g -> v [] ... [OTHER -> v]`. -/
def parseCase (fuel : Nat) : ParserM Expression := do
  let startSpan ← currentRange
  advance
  openFrame .caseExpression
  let interior : ParserM Expression := do
    let mut arms : Array CaseArm := #[]
    let mut going := true
    while going do
      if (← halted?) || (← peekSymbol "====") then
        going := false
      else
        let armStart ← currentRange
        if (← peekKeyword "OTHER") then do
          advance
          let _ ← expectSymbol "->"
          let value ← parseExpression fuel 0
          arms := arms.push
            { guard := none, value, range := ⟨armStart.start, value.range.stop⟩ }
          going := false
        else do
          let guard ← parseExpression fuel 0
          if !(← consumeSymbol "->") then do
            let range ← currentRange
            emitError ParseCode.expectedToken "expected '->' in a CASE arm" range
            going := false
          else do
            let value ← parseExpression fuel 0
            arms := arms.push
              { guard := some guard, value, range := ⟨armStart.start, value.range.stop⟩ }
            if !(← consumeSymbol "[]") then
              going := false
    let stop ← currentStop
    return .case arms ⟨startSpan.start, stop⟩
  let parsed? ← withNesting startSpan interior
  closeFrame
  match parsed? with
  | some expression => return expression
  | none => return placeholderExpression startSpan

/-- `LET definition ... IN body`. -/
def parseLet (fuel : Nat) : ParserM Expression := do
  let startSpan ← currentRange
  advance
  openFrame .letExpression
  let interior : ParserM Expression := do
    let mut definitions : Array OperatorDefinition := #[]
    let mut going := true
    while going do
      if (← peekKeyword "IN") || (← halted?) then
        going := false
      else
        match ← peek? with
        | none => going := false
        | some token =>
            match identifierOf? token with
            | none =>
                let range ← currentRange
                emitError ParseCode.expectedIdentifier
                  "expected a LET definition name" range
                going := false
            | some name => do
                advance
                let mut parameters : Array OperatorParameter := #[]
                if (← consumeSymbol "(") then
                  parameters ← parseParameterList fuel
                if (← consumeSymbol "==") then
                  let body ← parseExpression fuel 0
                  definitions := definitions.push
                    { name
                      nameRange := token.range
                      fixity := .functional
                      parameters
                      body
                      range := ⟨token.range.start, body.range.stop⟩ }
                else
                  let range ← currentRange
                  emitError ParseCode.expectedToken "expected '==' in a LET definition" range
                  going := false
    let _ ← expectKeyword "IN"
    let body ← parseExpression fuel 0
    return .letIn definitions body ⟨startSpan.start, body.range.stop⟩
  let parsed? ← withNesting startSpan interior
  closeFrame
  match parsed? with
  | some expression => return expression
  | none => return placeholderExpression startSpan

/-- `CHOOSE x \in S : P` and the unbound `CHOOSE x : P`. -/
def parseChoose (fuel : Nat) : ParserM Expression := do
  let startSpan ← currentRange
  advance
  openFrame .quantifier
  let interior : ParserM Expression := do
    match ← expectName with
    | none => return placeholderExpression startSpan
    | some (name, nameRange) => do
        if (← consumeSymbol "\\in") then do
          let domain ← parseExpression fuel 0
          let _ ← expectSymbol ":"
          let body ← parseExpression fuel 0
          return .choose
            #[{ name, domain := some domain, range := ⟨nameRange.start, body.range.stop⟩ }]
            body ⟨startSpan.start, body.range.stop⟩
        else do
          let _ ← expectSymbol ":"
          let body ← parseExpression fuel 0
          return .choose
            #[{ name, domain := none, range := ⟨nameRange.start, body.range.stop⟩ }]
            body ⟨startSpan.start, body.range.stop⟩
  let parsed? ← withNesting startSpan interior
  closeFrame
  match parsed? with
  | some expression => return expression
  | none => return placeholderExpression startSpan

/-- `\A` and `\E` with one or more bounds. -/
def parseQuantifier (fuel : Nat) (kind : QuantifierKind) : ParserM Expression := do
  let startSpan ← currentRange
  advance
  openFrame .quantifier
  let interior : ParserM Expression := do
    let bounds ← parseBounds fuel true
    let _ ← expectSymbol ":"
    let body ← parseExpression fuel 0
    return .quantifier kind bounds body ⟨startSpan.start, body.range.stop⟩
  let parsed? ← withNesting startSpan interior
  closeFrame
  match parsed? with
  | some expression => return expression
  | none => return placeholderExpression startSpan

/-- Comma-separated bounds `name \in domain`. With `allowUnbounded`, a name
without `\in` becomes an unbounded binder (`domain = none`), which is what the
quantifier forms `\A x : P` and `\E x, y : P` write. A bounded binder may not be
followed by an unbounded name: the group would then have no unambiguous extent.
Without `allowUnbounded` (set builders), a missing `\in` stays an error. -/
def parseBounds (fuel : Nat) (allowUnbounded : Bool) : ParserM (Array Bound) := do
  let mut bounds : Array Bound := #[]
  let mut bounded := false
  let mut going := true
  while going do
    let boundStart ← currentRange
    match ← expectName with
    | none => going := false
    | some (name, nameRange) => do
        if (← consumeSymbol "\\in") then
          let domain ← parseExpression fuel 0
          bounded := true
          bounds := bounds.push
            { name, domain := some domain, range := ⟨boundStart.start, domain.range.stop⟩ }
          if !(← consumeSymbol ",") then
            going := false
        else if allowUnbounded && !bounded then
          bounds := bounds.push
            { name, domain := none, range := ⟨boundStart.start, nameRange.stop⟩ }
          if !(← consumeSymbol ",") then
            going := false
        else if allowUnbounded then
          emitError ParseCode.mixedBounds
            "a bounded quantifier binder cannot be followed by an unbounded name"
            nameRange
          going := false
        else
          let range ← currentRange
          emitError ParseCode.expectedToken "expected '\\in' in a bound" range
          going := false
  return bounds

/-- `WF_v(A)` and `SF_v(A)`; the subscript becomes the first argument. -/
def parseFairness (fuel : Nat) (spelling : String) : ParserM Expression := do
  let startSpan ← currentRange
  advance
  let interior : ParserM Expression := do
    let subscript ← parsePrimary fuel false
    if (← consumeSymbol "(") then
      let (arguments, ok) ← parseDelimitedExpressions fuel ")"
      if ok then
        let all := #[subscript] ++ arguments
        return .apply
          { qualifier := none, spelling, range := startSpan }
          all (applicationRange startSpan.start all)
      else
        return prefixApplication spelling subscript startSpan
    else
      return prefixApplication spelling subscript startSpan
  match ← withNesting startSpan interior with
  | some expression => return expression
  | none => return placeholderExpression startSpan

/-- Arity of one parenthesized operand list: a `RECURSIVE` arity specification
or the higher-order operands of a definition parameter, up to and including its
closing `)`. Every operand list is a guarded nesting level; `fuel` remains the
separate totality backstop for nested operand lists. -/
def parseAritySpec (fuel : Nat) : ParserM Nat := do
  let opening ← currentRange
  let interior : ParserM Nat := do
    if fuel = 0 then do
      let range ← currentRange
      emitLimit ParseCode.recursionLimit
        "parser resource budget exhausted in an arity specification" range
      return 0
    else
      let mut arity := 0
      let mut going := true
      while going do
        if (← peekSymbol ")") || (← halted?) then
          going := false
        else
          let named ← consumeIdentifier
          match named with
          | some _ =>
              if (← consumeSymbol "(") then
                let inner ← parseAritySpec (fuel - 1)
                arity := arity + (if inner == 0 then 1 else inner)
              else
                arity := arity + 1
          | none =>
              let underscore ← consumeSymbol "_"
              if underscore then
                arity := arity + 1
              else
                let _ ← expectName
          if !(← consumeSymbol ",") then
            going := false
      let _ ← expectSymbol ")"
      return arity
  match ← withNesting opening interior with
  | some arity => return arity
  | none => return 0

/-- Argument list of a parameterized operator: `(p, P(_), ...)`. The list
interior and every higher-order operand list are guarded nesting levels;
`fuel` remains the separate totality backstop for nested operand lists. -/
def parseParameterList (fuel : Nat) : ParserM (Array OperatorParameter) := do
  let opening ← currentRange
  let interior : ParserM (Array OperatorParameter) := do
    let mut parameters : Array OperatorParameter := #[]
    let mut going := true
    while going do
      if (← peekSymbol ")") || (← halted?) then
        going := false
      else
        let parameterRange ← currentRange
        match ← expectName with
        | none => going := false
        | some (name, _) => do
            let mut arity := 0
            if (← consumeSymbol "(") then
              let parsed ← parseAritySpec (fuel - 1)
              arity := if parsed == 0 then 1 else parsed
            parameters := parameters.push
              { name, arity, range := ⟨parameterRange.start, (← currentStop)⟩ }
            if !(← consumeSymbol ",") then
              going := false
    let _ ← expectSymbol ")"
    return parameters
  match ← withNesting opening interior with
  | some parameters => return parameters
  | none => return #[]

end

/-! ## Declaration parsing -/

/-- Record one complete declaration. -/
def recordDeclaration (declaration : Declaration) : ParserM Unit :=
  modify fun state =>
    { state with
      declarations := state.declarations.push declaration
      declarationCount := state.declarationCount + 1 }

/-- `EXTENDS Module, Module ...` -/
def parseExtends (_fuel : Nat) (isLocal : Bool) (startRange : SourceRange) :
    ParserM (Option Declaration) := do
  openFrame .extendsDeclaration
  advance
  let mut modules : Array ImportedModule := #[]
  let mut ok := true
  let mut going := true
  while going do
    match ← expectName with
    | none => do
        ok := false
        going := false
    | some (name, nameRange) => do
        match ModuleName.ofString? name with
        | some moduleName =>
            modules := modules.push { name := moduleName, range := nameRange }
        | none => do
            emitError ParseCode.expectedIdentifier
              s!"'{renderSpelling name}' is not a module name" nameRange
            ok := false
        if !(← consumeSymbol ",") then
          going := false
  closeFrame
  if ok && !modules.isEmpty then
    return some (.«extends»
      { modules, «local» := isLocal, range := ⟨startRange.start, (← currentStop)⟩ })
  else
    return none

/-- `CONSTANT` / `CONSTANTS` with a comma list that may continue on the next
line. -/
def parseConstants (startRange : SourceRange) : ParserM (Option Declaration) := do
  openFrame .declaration
  advance
  let mut names : Array OperatorDecl := #[]
  let mut ok := true
  let mut going := true
  while going do
    match ← expectName with
    | none => do
        ok := false
        going := false
    | some (name, nameRange) => do
        names := names.push { name, arity := 0, range := nameRange }
        if !(← consumeSymbol ",") then
          going := false
  closeFrame
  if ok && !names.isEmpty then
    return some (.constant ⟨startRange.start, (← currentStop)⟩ names)
  else
    return none

/-- `VARIABLE` / `VARIABLES` with a comma list that may continue on the next
line. Declaration order is preserved. -/
def parseVariables (startRange : SourceRange) : ParserM (Option Declaration) := do
  openFrame .declaration
  advance
  let mut names : Array NameDecl := #[]
  let mut ok := true
  let mut going := true
  while going do
    match ← expectName with
    | none => do
        ok := false
        going := false
    | some (name, nameRange) => do
        names := names.push { name, range := nameRange }
        if !(← consumeSymbol ",") then
          going := false
  closeFrame
  if ok && !names.isEmpty then
    return some (.variable ⟨startRange.start, (← currentStop)⟩ names)
  else
    return none

/-- `RECURSIVE Name(_, _), ...` with explicit arity. -/
def parseRecursive (fuel : Nat) (startRange : SourceRange) : ParserM (Option Declaration) := do
  openFrame .declaration
  advance
  let mut operators : Array OperatorDecl := #[]
  let mut ok := true
  let mut going := true
  while going do
    match ← expectName with
    | none => do
        ok := false
        going := false
    | some (name, nameRange) => do
        let mut arity := 0
        if (← consumeSymbol "(") then
          arity ← parseAritySpec fuel
        operators := operators.push
          { name, arity, range := ⟨nameRange.start, (← currentStop)⟩ }
        if !(← consumeSymbol ",") then
          going := false
  closeFrame
  if ok && !operators.isEmpty then
    return some (.recursive ⟨startRange.start, (← currentStop)⟩ operators)
  else
    return none

/-- `ASSUME`, `ASSUMPTION`, or `AXIOM`, optionally with `Name ==`. -/
def parseAssumption (kind : AssumptionKind) (fuel : Nat) (startRange : SourceRange) :
    ParserM (Option Declaration) := do
  openFrame .assumption
  advance
  let mut name : Option String := none
  let first? ← peek?
  let second? ← peekAt? 1
  match first?, second? with
  | some first, some second =>
      match identifierOf? first, symbolOf? (← profileOf) second with
      | some candidate, some "==" => do
          advance
          advance
          name := some candidate
      | _, _ => pure ()
  | _, _ => pure ()
  let body ← parseExpression fuel 0
  closeFrame
  return some (.assumption
    { kind, name, body, range := ⟨startRange.start, body.range.stop⟩ })

/-! ## Opaque proof regions -/

/-- Module-declaration keywords that cannot appear inside an opaque proof
region. `ASSUME` and `ASSUMPTION` are proof steps, so they stay opaque. -/
def foreignProofDeclarationKeyword (canonical : String) : Bool :=
  isDeclarationKeyword canonical && canonical != "ASSUME" && canonical != "ASSUMPTION"

/-- The delimiter that closes an opening delimiter spelling, when the spelling
opens a delimited form. -/
def delimiterCloser? : String → Option String
  | "(" => some ")"
  | "[" => some "]"
  | "{" => some "}"
  | "<<" => some ">>"
  | _ => none

/-- The delimiter that opens a closing delimiter spelling, when the spelling
closes a delimited form. -/
def delimiterOpener? : String → Option String
  | ")" => some "("
  | "]" => some "["
  | "}" => some "{"
  | ">>" => some "<<"
  | _ => none

/-- Maximum number of tokens one step label may spend after its `<level>`
prefix. -/
def proofLabelTokenLimit : Nat := 8

/-- Index of the `.` that closes a step label, or `none` when the run after the
prefix is longer than `proofLabelTokenLimit` or is not a label body. -/
def proofLabelDot? (profile : LanguageProfile) (tokens : Array Token)
    (position : Nat) : Option Nat :=
  let rec go (index count remaining : Nat) : Option Nat :=
    match remaining with
    | 0 => none
    | remaining + 1 =>
        match tokens[index]? with
        | none => none
        | some token =>
            match token.kind with
            | .identifier => go (index + 1) (count + 1) remaining
            | .integer _ => go (index + 1) (count + 1) remaining
            | .symbol _ =>
                if count > 0 && symbolSpelling profile token == "." then
                  some index
                else
                  none
            | _ => none
  go position 0 (proofLabelTokenLimit + 1)

/-- One proof-step label `<level>label.` at a token position: the step level it
opens and the number of tokens the label occupies. -/
structure ProofStepLabel where
  level : Nat
  length : Nat
  deriving Repr, BEq

/-- Recognise one proof-step label. Step labels are the only proof tokens the
scan interprets; every other proof token stays opaque. -/
def proofStepLabelAt? (profile : LanguageProfile) (tokens : Array Token)
    (position : Nat) : Option ProofStepLabel :=
  match tokens[position]?, tokens[position + 1]?, tokens[position + 2]? with
  | some opening, some levelToken, some closing =>
      if symbolSpelling profile opening != "<" ||
          symbolSpelling profile closing != ">" then
        none
      else
        match levelToken.kind with
        | .integer level =>
            if level ≤ 0 then
              none
            else
              match proofLabelDot? profile tokens (position + 3) with
              | some dot =>
                  some { level := level.toNat, length := dot - position + 1 }
              | none => none
        | _ => none
  | _, _, _ => none

/-- One open proof scope inside an opaque region: a nested `PROOF ... QED`
region or the proof of one numbered step. -/
inductive ProofScope where
  | region
  | step (level : Nat) (charged : Bool)
  deriving Repr, BEq

namespace ProofScope

/-- `true` when opening the scope spent one `maxNestingDepth` level. The first
step level of a region is free; deeper step levels and nested `PROOF` regions
are charged. -/
def charged : ProofScope → Bool
  | .region => true
  | .step _ charged => charged

end ProofScope

/-- Scan one opaque proof region forward to the `QED` that ends it. The caller
has consumed the `PROOF` keyword; the scan consumes through the matching
top-level `QED`.

Revision 1 keeps proofs opaque: no proof node reaches the abstract syntax and
no proof rule runs. The scan tracks just enough structure to find the region
end reliably, so proof-local text can never escape as a module declaration:

* a step label `<level>label.` (for example `<1>2.`) marks the next token as
  that step's statement, so a `QED` step ends its own step instead of the
  region;
* numbered step proofs and nested `PROOF ... QED` regions push scopes: a
  labelled `QED` closes the innermost numbered step proof, a bare `QED` inside
  a nested region closes that region, and a bare `QED` without an open nested
  region ends the region;
* `(`/`[`/`{`/`<<` hide every structural token until the delimiter closes;
* module-declaration keywords and unmatched delimiters are ambiguous, so the
  scan reports one bounded error and stops.

Nested proof scopes spend the parser's `maxNestingDepth` budget (the first step
level of a region is free) and one unit of the structural fuel each, and the
walk visits every token at most once, so proof scanning is bounded by the
stream's token budget and the same two limits as the rest of the parser. A
region that reaches the module terminator or end of input before its matching
`QED` fails closed. -/
def scanProofRegion (fuel : Nat) : ParserM Unit := do
  let mut scopes : Array ProofScope := #[]
  let mut delimiters : Array String := #[]
  let mut depth := 0
  let mut budget := fuel
  let mut pendingLevel : Option Nat := none
  let mut going := true
  while going do
    if (← halted?) then
      going := false
    else do
      let state ← get
      let profile := state.profile
      match state.tokens[state.position]? with
      | none => do
          emitError ParseCode.proofTermination
            "proof region reaches end of input before its matching QED"
            ⟨state.lastStop, state.lastStop⟩
          haltParser
          going := false
      | some token =>
          if token.kind.isEof || token.kind == .moduleEnd then do
            emitError ParseCode.proofTermination
              "proof region reaches the module terminator before its matching QED"
              token.range
            haltParser
            going := false
          else do
            let spelling := symbolSpelling profile token
            match delimiterOpener? spelling with
            | some _ =>
                if delimiters.back? == some spelling then do
                  advance
                  delimiters := delimiters.pop
                  pendingLevel := none
                else do
                  emitError ParseCode.proofUnsupported
                    s!"proof region closes '{renderSpelling spelling}' without a matching delimiter"
                    token.range
                  haltParser
                  going := false
            | none =>
                match delimiterCloser? spelling with
                | some closer => do
                    advance
                    delimiters := delimiters.push closer
                    pendingLevel := none
                | none =>
                    if delimiters.size > 0 then do
                      advance
                      pendingLevel := none
                    else if token.kind.isKeyword "QED" then
                      match pendingLevel, scopes.back? with
                      | some level, some (.step openLevel charged) =>
                          if level == openLevel then do
                            advance
                            pendingLevel := none
                            if charged then
                              depth := depth - 1
                            scopes := scopes.pop
                            if scopes.isEmpty then
                              going := false
                          else do
                            emitError ParseCode.proofUnsupported
                              "a QED step label does not close the innermost open step proof"
                              token.range
                            haltParser
                            going := false
                      | some _, _ => do
                          emitError ParseCode.proofUnsupported
                            "a QED step label does not close the innermost open step proof"
                            token.range
                          haltParser
                          going := false
                      | none, some .region => do
                          advance
                          depth := depth - 1
                          scopes := scopes.pop
                      | none, some (.step _ _) => do
                          advance
                          scopes := scopes.pop
                          going := false
                      | none, none => do
                          advance
                          going := false
                    else if token.kind.isKeyword "PROOF" then
                      let terminal :=
                        match state.tokens[state.position + 1]? with
                        | some next =>
                            next.kind.isKeyword "OMITTED" ||
                              next.kind.isKeyword "OBVIOUS"
                        | none => false
                      if terminal then do
                        advance
                        advance
                        pendingLevel := none
                      else if budget = 0 then do
                        emitLimit ParseCode.recursionLimit
                          "parser resource budget exhausted inside a proof region"
                          token.range
                        going := false
                      else if state.nesting + depth + 1 >
                          state.limits.maxNestingDepth then do
                        emitLimit ParseCode.nestingDepth
                          s!"nested proof scope exceeds the depth limit of {state.limits.maxNestingDepth}"
                          token.range
                        going := false
                      else do
                        budget := budget - 1
                        depth := depth + 1
                        advance
                        scopes := scopes.push .region
                        pendingLevel := none
                    else
                      match proofStepLabelAt? profile state.tokens state.position with
                      | some label =>
                          let previous := scopes.back?
                          let opensLevel :=
                            match previous with
                            | some (.step openLevel _) => label.level == openLevel + 1
                            | _ => true
                          let levelOk :=
                            match previous with
                            | some (.step openLevel _) =>
                                label.level == openLevel || label.level == openLevel + 1
                            | _ => true
                          let charged := opensLevel && !scopes.isEmpty
                          if !levelOk then do
                            emitError ParseCode.proofUnsupported
                              "proof step levels must repeat the open level or open the next one"
                              token.range
                            haltParser
                            going := false
                          else if charged && budget = 0 then do
                            emitLimit ParseCode.recursionLimit
                              "parser resource budget exhausted inside a proof region"
                              token.range
                            going := false
                          else if charged && state.nesting + depth + 1 >
                              state.limits.maxNestingDepth then do
                            emitLimit ParseCode.nestingDepth
                              s!"nested proof scope exceeds the depth limit of {state.limits.maxNestingDepth}"
                              token.range
                            going := false
                          else do
                            for _ in [:label.length] do
                              advance
                            if opensLevel then do
                              if charged then
                                budget := budget - 1
                                depth := depth + 1
                              scopes := scopes.push (.step label.level charged)
                            pendingLevel := some label.level
                      | none =>
                          match keywordOf? token with
                          | some keyword =>
                              if foreignProofDeclarationKeyword keyword then do
                                emitError ParseCode.proofUnsupported
                                  s!"'{keyword}' cannot appear inside an opaque proof region"
                                  token.range
                                haltParser
                                going := false
                              else do
                                advance
                                pendingLevel := none
                          | none => do
                              advance
                              pendingLevel := none

/-- Scan the argument text of a terminal `BY` proof step: it runs to the next
module declaration, the module terminator, or end of input, and it carries at
least one argument token. Proof structure inside the argument text is
ambiguous, so the scan reports one bounded error instead of guessing. -/
def scanProofByTerminal : ParserM Unit := do
  let mut delimiters : Array String := #[]
  let mut arguments := 0
  let mut going := true
  while going do
    if (← halted?) then
      going := false
    else do
      let state ← get
      let profile := state.profile
      match state.tokens[state.position]? with
      | none => going := false
      | some token =>
          if token.kind.isEof || token.kind == .moduleEnd then
            going := false
          else if delimiters.isEmpty &&
              startsDeclarationAt? profile state.tokens state.position then
            going := false
          else do
            let spelling := symbolSpelling profile token
            match delimiterOpener? spelling with
            | some _ =>
                if delimiters.back? == some spelling then do
                  advance
                  delimiters := delimiters.pop
                  arguments := arguments + 1
                else do
                  emitError ParseCode.proofUnsupported
                    s!"BY proof step closes '{renderSpelling spelling}' without a matching delimiter"
                    token.range
                  haltParser
                  going := false
            | none =>
                match delimiterCloser? spelling with
                | some closer => do
                    advance
                    delimiters := delimiters.push closer
                    arguments := arguments + 1
                | none =>
                    if delimiters.isEmpty &&
                        (token.kind.isKeyword "QED" || token.kind.isKeyword "PROOF" ||
                          (proofStepLabelAt? profile state.tokens state.position).isSome) then do
                      emitError ParseCode.proofUnsupported
                        "a terminal BY proof step cannot carry nested proof syntax"
                        token.range
                      haltParser
                      going := false
                    else do
                      advance
                      arguments := arguments + 1
  if !(← halted?) then
    if arguments == 0 then do
      let range ← currentRange
      emitError ParseCode.proofUnsupported
        "a BY proof step needs at least one argument" range
      haltParser
    else if !delimiters.isEmpty then do
      let range ← currentRange
      emitError ParseCode.proofUnsupported
        "BY proof step leaves a delimiter unclosed" range
      haltParser

/-- `THEOREM`, `LEMMA`, `PROPOSITION`, or `COROLLARY` with an optional proof
region. -/
def parseTheorem (kind : TheoremKind) (fuel : Nat) (startRange : SourceRange) :
    ParserM (Option Declaration) := do
  openFrame .theorem
  advance
  let mut name : Option String := none
  let first? ← peek?
  let second? ← peekAt? 1
  match first?, second? with
  | some first, some second =>
      match identifierOf? first, symbolOf? (← profileOf) second with
      | some candidate, some "==" => do
          advance
          advance
          name := some candidate
      | _, _ => pure ()
  | _, _ => pure ()
  let statement ← parseExpression fuel 0
  let proofStart ← currentRange
  let mut proof : Option ProofRegion := none
  if (← peekKeyword "PROOF") then do
    openFrame .proofRegion
    advance
    if (← consumeKeyword "OMITTED") then
      proof := some { treatment := .omitted, range := ⟨proofStart.start, (← currentStop)⟩ }
    else if (← consumeKeyword "OBVIOUS") then
      proof := some { treatment := .opaque, range := ⟨proofStart.start, (← currentStop)⟩ }
    else do
      scanProofRegion fuel
      proof := some { treatment := .opaque, range := ⟨proofStart.start, (← currentStop)⟩ }
    closeFrame
  else if (← peekKeyword "BY") then do
    openFrame .proofRegion
    advance
    scanProofByTerminal
    closeFrame
    proof := some { treatment := .opaque, range := ⟨proofStart.start, (← currentStop)⟩ }
  closeFrame
  return some (.«theorem»
    { kind, name, statement, proof, range := ⟨startRange.start, (← currentStop)⟩ })

/-- The body of an `INSTANCE`, shared by named and unnamed forms. -/
def parseInstanceBody (fuel : Nat) (name : Option String) (isLocal : Bool)
    (startRange : SourceRange) : ParserM (Option InstanceDeclaration) := do
  openFrame .instanceDeclaration
  let _ ← consumeKeyword "INSTANCE"
  match ← expectName with
  | none => do
      closeFrame
      return none
  | some (moduleRaw, _) => do
      match ModuleName.ofString? moduleRaw with
      | none => do
          emitError ParseCode.expectedIdentifier
            s!"'{renderSpelling moduleRaw}' is not a module name" startRange
          closeFrame
          return none
      | some moduleName => do
          let mut substitutions : Array Substitution := #[]
          if (← consumeKeyword "WITH") then
            let mut going := true
            while going do
              let formalStart ← currentRange
              match ← expectName with
              | none => going := false
              | some (formal, formalRange) => do
                  let mut formalArity := 0
                  if (← consumeSymbol "(") then
                    formalArity ← parseAritySpec fuel
                  let _ ← expectSymbol "<-"
                  let actual ← parseExpression fuel 0
                  substitutions := substitutions.push
                    { formal
                      formalArity
                      formalRange
                      actual
                      range := ⟨formalStart.start, actual.range.stop⟩ }
                  if !(← consumeSymbol ",") then
                    going := false
          closeFrame
          return some
            { name, moduleName, substitutions, «local» := isLocal
              range := ⟨startRange.start, (← currentStop)⟩ }

/-- `~ x == e`, `[] x == e`, and the prefix keyword forms such as
`DOMAIN f == e`: one operand name between the operator and `==`. The caller has
already consumed the operator spelling and passes its canonical identity. -/
def parsePrefixDefinition (fuel : Nat) (startRange operatorRange : SourceRange)
    (canonical : String) : ParserM (Option Declaration) := do
  openFrame .operatorDefinition
  match ← expectName with
  | none => do
      closeFrame
      return none
  | some (name, nameRange) => do
      let _ ← expectSymbol "=="
      let body ← parseExpression fuel 0
      closeFrame
      return some (.operator
        { name := canonical
          nameRange := operatorRange
          fixity := .prefix
          parameters := #[{ name, arity := 0, range := nameRange }]
          body
          range := ⟨startRange.start, body.range.stop⟩ })

/-- A module-level operator definition, or a named `INSTANCE`. Functional,
infix, prefix, and postfix definitions meet here; each records the canonical
operator identity, its fixity, the parameters in source order, and the source
ranges. -/
def parseDefinitionOrInstance (fuel : Nat) (startRange : SourceRange) :
    ParserM (Option Declaration) := do
  openFrame .operatorDefinition
  match ← expectName with
  | none => do
      closeFrame
      return none
  | some (name, nameRange) => do
      let mut parameters : Array OperatorParameter := #[]
      if (← consumeSymbol "(") then
        parameters ← parseParameterList fuel
      let profile ← profileOf
      let parserProfile ← parserProfileOf
      let next? ← peek?
      let after? ← peekAt? 1
      -- A postfix definition writes the operator after the left operand name:
      -- `y \frob == e`. It is only a definition when `==` follows the operator,
      -- so `x \frob y == e` stays an infix definition.
      let postfixName? : Option (String × SourceRange) :=
        match next? with
        | some token =>
            match postfixDefinitionName? parserProfile profile token with
            | some canonical =>
                if parameters.isEmpty then
                  match after? with
                  | some after =>
                      if isSymbolToken profile after "==" then
                        some (canonical, token.range)
                      else none
                  | none => none
                else none
            | none => none
        | none => none
      let postfixDefinition (canonical : String) (operatorRange : SourceRange) :
          ParserM (Option Declaration) := do
        advance
        let _ ← expectSymbol "=="
        let body ← parseExpression fuel 0
        closeFrame
        return some (.operator
          { name := canonical
            nameRange := operatorRange
            fixity := .postfix
            parameters := #[{ name, arity := 0, range := nameRange }]
            body
            range := ⟨startRange.start, body.range.stop⟩ })
      let infix? : Option (OperatorEntry × SourceRange) :=
        match next? with
        | some token =>
            match token.kind with
            | .symbol _ =>
                match infixOperatorOf? parserProfile profile token with
                | some entry => some (entry, token.range)
                | none => none
            | _ => none
        | none => none
      match infix? with
      | some (entry, operatorRange) => do
          match postfixName? with
          | some (canonical, nameRange) => postfixDefinition canonical nameRange
          | none =>
              advance
              match ← expectName with
              | none => do
                  closeFrame
                  return none
              | some (rightName, rightRange) => do
                  let _ ← expectSymbol "=="
                  let body ← parseExpression fuel 0
                  closeFrame
                  return some (.operator
                    { name := entry.canonical
                      nameRange := operatorRange
                      fixity := .infix
                      parameters := #[{ name, arity := 0, range := nameRange },
                                      { name := rightName, arity := 0, range := rightRange }]
                      body
                      range := ⟨startRange.start, body.range.stop⟩ })
      | none =>
          match postfixName? with
          | some (canonical, nameRange) => postfixDefinition canonical nameRange
          | none => do
              let _ ← expectSymbol "=="
              if (← peekKeyword "INSTANCE") then
                match ← parseInstanceBody fuel (some name) false startRange with
                | some declaration => do
                    closeFrame
                    return some (.«instance» declaration)
                | none => do
                    closeFrame
                    return none
              else do
                let body ← parseExpression fuel 0
                closeFrame
                return some (.operator
                  { name
                    nameRange
                    fixity := .functional
                    parameters
                    body
                    range := ⟨startRange.start, body.range.stop⟩ })

/-- One module declaration, without recording it. `fuel` bounds nested `LOCAL`
wrappers; every other declaration consumes no fuel. -/
def parseDeclarationBody (fuel : Nat) : ParserM (Option Declaration) := do
  if fuel = 0 then do
    let range ← currentRange
    emitLimit ParseCode.recursionLimit
      "parser resource budget exhausted in a declaration" range
    return none
  else
    let startRange ← currentRange
    match ← peek? with
    | none => do
        emitError ParseCode.expectedToken "expected a declaration before end of input" startRange
        return none
    | some token =>
        match keywordOf? token with
        | some "EXTENDS" => parseExtends fuel false startRange
        | some "CONSTANT" => parseConstants startRange
        | some "CONSTANTS" => parseConstants startRange
        | some "VARIABLE" => parseVariables startRange
        | some "VARIABLES" => parseVariables startRange
        | some "RECURSIVE" => parseRecursive fuel startRange
        | some "ASSUME" => parseAssumption .assume fuel startRange
        | some "ASSUMPTION" => parseAssumption .assumption fuel startRange
        | some "AXIOM" => parseAssumption .«axiom» fuel startRange
        | some "THEOREM" => parseTheorem .«theorem» fuel startRange
        | some "LEMMA" => parseTheorem .lemma fuel startRange
        | some "PROPOSITION" => parseTheorem .proposition fuel startRange
        | some "COROLLARY" => parseTheorem .corollary fuel startRange
        | some "LOCAL" => do
            openFrame .declaration
            advance
            let inner? ← withNesting startRange (parseDeclarationBody (fuel - 1))
            closeFrame
            match inner? with
            | some (some declaration) =>
                return some (.«local» ⟨startRange.start, (← currentStop)⟩ declaration)
            | _ => return none
        | some "INSTANCE" => do
            match ← parseInstanceBody fuel none false startRange with
            | some declaration => return some (.«instance» declaration)
            | none => return none
        | some "ENABLED" =>
            parsePrefixDefinition fuel startRange token.range "ENABLED"
        | some "UNCHANGED" =>
            parsePrefixDefinition fuel startRange token.range "UNCHANGED"
        | some "DOMAIN" =>
            parsePrefixDefinition fuel startRange token.range "DOMAIN"
        | some "SUBSET" =>
            parsePrefixDefinition fuel startRange token.range "SUBSET"
        | some "UNION" =>
            parsePrefixDefinition fuel startRange token.range "UNION"
        | some _ => do
            emitError ParseCode.expectedToken
              s!"expected a declaration but found '{renderSpelling token.spelling}'"
              token.range
            return none
        | none =>
            match token.kind with
            | .identifier => parseDefinitionOrInstance fuel startRange
            | .symbol _ => do
                let parserProfile ← parserProfileOf
                let profile ← profileOf
                match prefixDefinitionOf? parserProfile profile token with
                | some canonical => do
                    advance
                    parsePrefixDefinition fuel startRange token.range canonical
                | none => do
                    emitError ParseCode.expectedToken
                      s!"expected a declaration but found '{renderSpelling token.spelling}'"
                      token.range
                    return none
            | _ => do
                emitError ParseCode.expectedToken
                  s!"expected a declaration but found '{renderSpelling token.spelling}'"
                  token.range
                return none

/-- One module declaration, recording it when it is complete. -/
def parseDeclaration (fuel : Nat) : ParserM Bool := do
  let state ← get
  let startRange ← currentRange
  if state.declarationCount + 1 > state.limits.maxDeclarations then do
    emitLimit ParseCode.declarationLimit
      s!"declaration count exceeds the limit of {state.limits.maxDeclarations}"
      startRange
    return false
  else
    match ← parseDeclarationBody fuel with
    | some declaration => do
        recordDeclaration declaration
        return true
    | none => return false

/-! ## Module parsing -/

def consumeModuleEnd : ParserM Bool := do
  match ← peek? with
  | some token =>
      if token.kind == .moduleEnd then do
        advance
        return true
      else
        return false
  | none => return false

/-- Parse the captured module: header, declarations, terminator. -/
def parseModuleCore (fuel : Nat) : ParserM Unit := do
  openFrame .moduleRoot
  let headerRange ← currentRange
  let first? ← peek?
  match first? with
  | none =>
      emitError ParseCode.moduleHeader "expected a module header line" headerRange
  | some token =>
      if token.kind == .moduleHeader then do
        advance
        let name := token.moduleHeaderName?
        modify fun state => { state with moduleName := name.bind ModuleName.ofString? }
        if name.isNone then
          emitError ParseCode.moduleHeader
            "the module header does not name a module" token.range
      else
        emitError ParseCode.moduleHeader
          s!"expected a module header line but found '{renderSpelling token.spelling}'"
          token.range
  let state ← get
  match plusCalRange? state.tokens with
  | some range =>
      emitError ParseCode.pluscal
        "PlusCal algorithm blocks are staged out of the revision-1 profile; pre-translate the module first"
        range
  | none => pure ()
  let mut going := true
  while going do
    if (← halted?) then
      going := false
    else
      let state ← get
      match state.tokens[state.position]? with
      | none => going := false
      | some token =>
          if token.kind.isEof || token.kind == .moduleEnd then
            going := false
          else do
            let before := state.position
            let _ ← parseDeclaration fuel
            let after ← position
            if after == before && !(← halted?) then do
              openFrame .recovery
              advance
              closeFrame
  let endRange ← currentRange
  if !(← consumeModuleEnd) then
    emitError ParseCode.moduleEnd
      "module terminator '====' is missing before end of input" endRange
  let state ← get
  match state.tokens[state.position]? with
  | some token =>
      if !token.kind.isEof then
        emitError ParseCode.trailingContent "tokens follow the module terminator" token.range
  | none => pure ()
  set { state with moduleRange := ⟨headerRange.start, state.lastStop⟩ }

/-- Append the truncation notice when the diagnostic budget refused items. -/
def truncationDiagnostic (state : ParserState) : Diagnostic :=
  { code := ParseCode.diagnosticsTruncated
    severity := .error
    stage := .parse
    message := "diagnostic budget exhausted; further diagnostics were dropped"
    primary := stateLocation state ⟨state.lastStop, state.lastStop⟩
    related := #[]
    arguments := #[("dropped", toString state.diagnostics.dropped)] }

/-- Retain every remaining token, close every frame, and assemble the outcome. -/
def finishParser (fuel : Nat) : ParserM ParseOutcome := do
  let mut going := true
  while going do
    let state ← get
    match state.tokens[state.position]? with
    | none => going := false
    | some token =>
        set { state with
              position := state.position + 1
              lastStop := token.range.stop
              frames := pushChild state.frames (.token token) }
  closeFramesTo fuel 1
  let state ← get
  let rootNode : CstNode :=
    match state.frames with
    | frame :: _ => wrapFrame frame
    | [] => emptyRoot.root
  let mut diagnostics := state.diagnostics.diagnostics
  if state.diagnostics.truncated then
    diagnostics := diagnostics.push (truncationDiagnostic state)
  -- Failure is decided after the truncation notice is materialized. A dropped
  -- diagnostic may have been the only error, and the notice is itself an error,
  -- so any outcome carrying an error diagnostic exposes no module.
  let failed := diagnostics.any Diagnostic.hasErrorSeverity
  let module? : Option ParsedModule :=
    if failed then
      none
    else
      match state.moduleName with
      | some name =>
          some { name, declarations := state.declarations, range := state.moduleRange }
      | none => none
  return { cst := { root := rootNode }, module?, diagnostics }

def parseModule (fuel : Nat) : ParserM ParseOutcome := do
  parseModuleCore fuel
  finishParser fuel

/-! ## Entry points -/

/-- A stream-validation failure: no module and one error diagnostic. -/
def streamFailure (source : SourceUnit) (code message : String)
    (range : SourceRange) : ParseOutcome :=
  { cst := emptyRoot
    module? := none
    diagnostics := #[
      { code
        severity := .error
        stage := .parse
        message
        primary := SourceLocation.ofUnit source range
        related := #[]
        arguments := #[] }] }

/-- The first structural problem with a candidate stream, if any: it must carry
exactly one `eof` token in final position, and its lossless text must reproduce
the captured unit. The check runs before any grammar step, so an inconsistent
source/stream pair fails closed instead of being analyzed. -/
def streamProblem? (source : SourceUnit) (stream : TokenStream) :
    Option ParseOutcome :=
  match stream.tokens.back? with
  | none =>
      some (streamFailure source ParseCode.streamEof
        "token stream carries no tokens; one final eof is required" zeroRange)
  | some last =>
      if !last.isEof then
        some (streamFailure source ParseCode.streamEof
          "token stream must end with exactly one eof token" last.range)
      else
        match (stream.tokens.take (stream.tokens.size - 1)).findSome?
            (fun token => if token.isEof then some token else none) with
        | some earlier =>
            some (streamFailure source ParseCode.streamEof
              "token stream carries more than one eof token" earlier.range)
        | none =>
            if TokenStream.text stream != source.normalizedText then
              some (streamFailure source ParseCode.streamTextMismatch
                "token stream text does not reproduce the captured unit" last.range)
            else
              none

/-- Parse one lexed token stream under one parser profile, which owns fixity,
precedence, and associativity. Streams that do not carry exactly one final
`eof` or do not reproduce the captured text fail without a module. -/
def parseStream (profile : LanguageProfile) (parserProfile : ParserProfile)
    (limits : ParserLimits) (source : SourceUnit) (stream : TokenStream) :
    ParseOutcome :=
  match streamProblem? source stream with
  | some failure => failure
  | none =>
      let fuel := 32 * stream.tokens.size + 4096
      let state : ParserState :=
        { profile, parserProfile, limits, source, tokens := stream.tokens }
      (parseModule fuel).run state |>.1

/-- Lex and parse one captured unit under one parser profile. A failed lex never
reaches the parser: the outcome carries the lex diagnostics and no module. -/
def parseSource (profile : LanguageProfile) (parserProfile : ParserProfile)
    (lexerLimits : LexerLimits) (limits : ParserLimits) (source : SourceUnit) :
    ParseOutcome :=
  match lex profile lexerLimits source with
  | .ok stream => parseStream profile parserProfile limits source stream
  | .error diagnostics =>
      { cst := emptyRoot, module? := none, diagnostics := diagnostics.toArray }

/-- The parser seam of the module resolver: one captured unit in, one outcome
out, with the revision-1 profile and limits. -/
def parseUnit (source : SourceUnit) : ParseOutcome :=
  parseSource LanguageProfile.default ParserProfile.default {} {} source

end Core.Tla
