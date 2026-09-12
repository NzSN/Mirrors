import Core.Tla.Parser
import Lean.Data.Json
import Lean.Data.Json.Parser

/-!
# TLA+ parser specification (tools/TlaParserSpec.lean)

Conformance suite for the TF2 lossless parser slice
(`Docs/model-interface-compiler/tla-frontend-design.md`, §10 "Concrete and
abstract syntax", §11 "Parsing behavior", §20 "Diagnostics", §21 "Resource and
security limits"; packages TF2A and TF2B of
`Docs/model-interface-compiler/tf2-acceptance-tasks.md`) against the pinned
revision-1 language profile
(`Docs/model-interface-compiler/tla-language-profile.md`). The parser checks
are pure; the TF2D corpus tier below reads the repository's
`test/fixtures/tla-frontend` manifest, sources, and summaries.

The suite covers the fail-closed outcome invariant, diagnostic count and byte
budgets, one nesting budget for every recursive syntax family, repeated prefix
and conditional/quantifier forms, token-stream admission, and deterministic
repeated failures. TF2B adds: the operator table as parser-profile data (a
modified profile changes precedence and associativity while `parseUnit` stays
on the frozen revision-1 combination), bounded and unbounded quantifier
groups, functional/infix/prefix/postfix operator definitions with their
applications, and decoded string values whose spelling stays in the CST. TF2C
adds the opaque proof treatment: `PROOF OMITTED` and `PROOF OBVIOUS` terminals,
terminal `BY` steps, and structured `PROOF ... QED` regions whose step labels,
nested scopes, and delimiters are scanned so proof-local declarations cannot
escape as module declarations and a missing `QED` fails closed. TF2D adds the
corpus-driven acceptance tier: every fixture in
`test/fixtures/tla-frontend/manifest.json` is decoded through a strict,
closed-vocabulary JSON decoder and driven to its declared stage behavior, and
every accepted fixture is checked against its parser-owned structural summary,
CST losslessness, alias equivalence group, and deterministic repeat output,
plus generated adversarial families. No network, Apalache, or private model
material is read.

Two commands run it:

* `lake env lean tools/TlaParserSpec.lean` — the elaboration check at the bottom
  of the file runs the suite, so a broken assertion fails this command;
* `lake env lean --run tools/TlaParserSpec.lean` — the `main` driver the build
  graph may wire as a `lean_exe`.
-/

namespace TlaParserSpec

open Lean
open Core.Tla

/-! ## Harness -/

abbrev Failures := IO.Ref (List String)

def check (fails : Failures) (name : String) (ok : Bool)
    (detail : String := "") : IO Unit := do
  if !ok then
    fails.modify fun items =>
      items ++ [if detail.isEmpty then name else s!"{name}: {detail}"]

/-! ## Captures, streams, and outcome views -/

/-- Logical path used by every capture in this suite. Physical paths never
appear in the frontend. -/
def specPath : String := "specs/TlaParserSpec.tla"

def capture (text : String) : SourceUnit :=
  SourceUnit.create .inlineSourceMap specPath text

def moduleText (body : String) : String :=
  "---- MODULE TlaParserSpec ----\n" ++ body ++ "\n====\n"

def lexStream? (source : SourceUnit) : Option TokenStream :=
  match lex LanguageProfile.default {} source with
  | .ok stream => some stream
  | .error _ => none

/-- Capture, lex, and parse one module body under an explicit parser profile:
what lets a test show that parsing follows the profile it is handed. -/
def parseWith? (parserProfile : ParserProfile) (limits : ParserLimits)
    (body : String) : Option (SourceUnit × TokenStream × ParseOutcome) := do
  let source := capture (moduleText body)
  let stream ← lexStream? source
  return (source, stream,
    parseStream LanguageProfile.default parserProfile limits source stream)

/-- Capture, lex, and parse one module body under explicit parser limits and the
frozen revision-1 combination. -/
def detailed? (limits : ParserLimits) (body : String) :
    Option (SourceUnit × TokenStream × ParseOutcome) :=
  parseWith? ParserProfile.default limits body

def parseBody? (limits : ParserLimits) (body : String) : Option ParseOutcome :=
  match detailed? limits body with
  | some (_, _, outcome) => some outcome
  | none => none

def outcomeCodes (outcome : ParseOutcome) : List String :=
  outcome.diagnostics.toList.map Diagnostic.code

def hasCode (outcome : ParseOutcome) (code : String) : Bool :=
  (outcomeCodes outcome).contains code

/-- The fail-closed invariant: an outcome carrying any error-severity
diagnostic never exposes a module. -/
def closed (outcome : ParseOutcome) : Bool :=
  !outcome.hasErrors || outcome.module?.isNone

def acceptedAt (limits : ParserLimits) (body : String) : Bool :=
  match parseBody? limits body with
  | some outcome => outcome.succeeded && closed outcome
  | none => false

/-- `parserProfile` accepts `body`: one recorded module without error
diagnostics. -/
def acceptedWith (parserProfile : ParserProfile) (limits : ParserLimits)
    (body : String) : Bool :=
  match parseWith? parserProfile limits body with
  | some (_, _, outcome) => outcome.succeeded && closed outcome
  | none => false

def nestingRejectedAt (limits : ParserLimits) (body : String) : Bool :=
  match parseBody? limits body with
  | some outcome =>
      outcome.module?.isNone && outcome.hasErrors &&
        hasCode outcome ParseCode.nestingDepth && closed outcome
  | none => false

def outcomeDetail (outcome : ParseOutcome) : String :=
  s!"module?={outcome.module?.isSome} diagnostics={outcomeCodes outcome}"

def detailOf? (outcome? : Option ParseOutcome) : String :=
  match outcome? with
  | some outcome => outcomeDetail outcome
  | none => "capture did not lex"

def checkAccepted (fails : Failures) (name : String) (limits : ParserLimits)
    (body : String) : IO Unit :=
  check fails name (acceptedAt limits body) (detailOf? (parseBody? limits body))

def checkNestingRejected (fails : Failures) (name : String) (limits : ParserLimits)
    (body : String) : IO Unit :=
  check fails name (nestingRejectedAt limits body) (detailOf? (parseBody? limits body))

/-- Count reported as dropped by the truncation notice, or `0` without one. -/
def droppedOf (outcome : ParseOutcome) : Nat :=
  match outcome.diagnostics.toList.find? (fun diagnostic =>
      diagnostic.code == ParseCode.diagnosticsTruncated) with
  | none => 0
  | some notice =>
      match notice.arguments.toList.find? (fun argument => argument.1 == "dropped") with
      | some argument => argument.2.toNat?.getD 0
      | none => 0

/-! ## Depth construction helpers -/

/-- `wrapper` applied `k` times around `base`. -/
def nested (wrapper : String → String) : Nat → String → String
  | 0, base => base
  | k + 1, base => wrapper (nested wrapper k base)

def repeated (count : Nat) (piece : String) : String :=
  String.join (List.replicate count piece)

def nestedIfThen : Nat → String
  | 0 => "1"
  | k + 1 => "IF TRUE THEN " ++ nestedIfThen k ++ " ELSE 1"

def nestedIfElse : Nat → String
  | 0 => "1"
  | k + 1 => "IF TRUE THEN 1 ELSE " ++ nestedIfElse k

/-- `k` nested higher-order operand lists: `p`, `p(q)`, `p(q(r))`, ... -/
def nestOperand : Nat → String
  | 0 => "p"
  | k + 1 => "p(" ++ nestOperand k ++ ")"

/-- `k` nested arity specifications: `f(_)`, `f(g(_))`, ... -/
def nestArity : Nat → String
  | 0 => "f(_)"
  | k + 1 => "f(" ++ nestArity k ++ ")"

/-- One builder per nested syntax family TF2A names. `builder k` is the module
body whose minimal accepted `maxNestingDepth` is exactly `k`. -/
def families : List (String × (Nat → String)) := [
  ("parentheses", fun k => "x == " ++ nested (fun inner => "(" ++ inner ++ ")") k "1"),
  ("tuples", fun k => "x == " ++ nested (fun inner => "<<" ++ inner ++ ">>") k "1"),
  ("sets", fun k => "x == " ++ nested (fun inner => "{" ++ inner ++ "}") k "1"),
  ("functions", fun k => "x == " ++ nested (fun inner => "[i \\in S |-> " ++ inner ++ "]") k "1"),
  ("function sets", fun k => "x == " ++ nested (fun inner => "[S -> " ++ inner ++ "]") k "S"),
  ("records", fun k => "x == " ++ nested (fun inner => "[a |-> " ++ inner ++ "]") k "1"),
  ("bracket forms", fun k => "x == " ++ nested (fun inner => "f[" ++ inner ++ "]") k "1"),
  ("prefix chains", fun k => "x == " ++ nested (fun inner => "~" ++ inner) k "TRUE"),
  ("temporal prefixes", fun k => "x == " ++ nested (fun inner => "[]" ++ inner) k "TRUE"),
  ("keyword prefixes", fun k => "x == " ++ nested (fun inner => "ENABLED " ++ inner) k "TRUE"),
  ("IF", fun k => "x == " ++ nestedIfThen k),
  ("ELSE-branch IF", fun k => "x == " ++ nestedIfElse k),
  ("CASE", fun k => "x == " ++ nested (fun inner => "CASE TRUE -> " ++ inner ++ " [] OTHER -> 1") k "1"),
  ("LET", fun k => "x == " ++ nested (fun inner => "LET x == " ++ inner ++ " IN x") k "1"),
  ("CHOOSE", fun k => "x == " ++ nested (fun inner => "CHOOSE x : " ++ inner) k "TRUE"),
  ("quantifiers", fun k => "x == " ++ nested (fun inner => "\\A x \\in S : " ++ inner) k "TRUE"),
  ("fairness", fun k => "x == " ++ nested (fun inner => "WF_x(" ++ inner ++ ")") k "TRUE"),
  ("argument lists", fun k => "x == " ++ nested (fun inner => "f(" ++ inner ++ ")") k "1"),
  ("comprehensions", fun k => "x == " ++ nested (fun inner => "{ x \\in S : " ++ inner ++ " }") k "TRUE"),
  ("EXCEPT", fun k => "x == " ++ nested (fun inner => "[f EXCEPT ![1] = " ++ inner ++ "]") k "1"),
  ("declaration parameter lists", fun k => "f(" ++ nestOperand (k - 1) ++ ") == 1"),
  ("RECURSIVE arity", fun k => "RECURSIVE " ++ nestArity (k - 1))
]

/-! ## Scenarios -/

def scenarioWellFormed (fails : Failures) : IO Unit := do
  let body :=
    "EXTENDS Integers\n\nCONSTANT N\nVARIABLE x\n\nDouble(v) == 2 * v\n\nInv == x = x"
  match detailed? {} body with
  | none => check fails "well-formed: the capture lexes" false
  | some (source, stream, outcome) => do
      check fails "well-formed: the module is accepted"
        (outcome.succeeded && closed outcome) (outcomeDetail outcome)
      check fails "well-formed: the module name is recorded"
        (outcome.module?.map (fun module => module.name.name) == some "TlaParserSpec")
      check fails "well-formed: every declaration is recorded"
        (outcome.module?.map (fun module => module.declarations.size) == some 5)
      check fails "well-formed: the CST reproduces the stream exactly"
        (outcome.cst.losslessAgainst stream)
      check fails "well-formed: the CST text equals the captured text"
        (outcome.cst.text == source.normalizedText)
      check fails "well-formed: CST ranges nest"
        (outcome.cst.rangesNested)
      check fails "well-formed: the CST covers the whole capture"
        (outcome.cst.coversSource source)
  check fails "well-formed: a one-line definition parses"
    (acceptedAt {} "x == 1")
  check fails "well-formed: malformed input does not parse"
    (match parseBody? {} "x == )" with
     | some outcome => !outcome.succeeded && closed outcome
     | none => false)
  check fails "well-formed: an empty module is valid TLA+"
    (acceptedAt {} "")

def scenarioTruncationOrdering (fails : Failures) : IO Unit := do
  let single := "x == )"
  let double := "x == )\ny == )"
  let singleCodes := [ParseCode.expectedExpression, ParseCode.expectedToken]
  let doubleCodes := singleCodes ++ singleCodes
  let checkBudget (label : String) (body : String) (expected : List String) : IO Unit := do
    let count := expected.length
    match parseBody? { maxDiagnostics := 0 } body with
    | none => check fails s!"{label}: the capture lexes" false
    | some outcome => do
        check fails s!"{label}: budget 0 exposes no module"
          (outcome.module?.isNone && closed outcome) (outcomeDetail outcome)
        check fails s!"{label}: budget 0 materializes one forced error notice"
          (outcome.diagnostics.size == 1 &&
            hasCode outcome ParseCode.diagnosticsTruncated &&
            outcome.diagnostics.toList.all (fun diagnostic => diagnostic.severity.isError))
          (outcomeDetail outcome)
        check fails s!"{label}: budget 0 counts every dropped diagnostic"
          (droppedOf outcome == count) s!"dropped={droppedOf outcome}"
    match parseBody? { maxDiagnostics := 1 } body with
    | none => check fails s!"{label}: the capture lexes" false
    | some outcome => do
        check fails s!"{label}: budget 1 keeps one diagnostic and the notice"
          (outcome.diagnostics.size == 2 && droppedOf outcome == count - 1)
          (outcomeDetail outcome)
        check fails s!"{label}: budget 1 preserves diagnostic order"
          (outcomeCodes outcome == expected.take 1 ++ [ParseCode.diagnosticsTruncated])
          (outcomeDetail outcome)
        check fails s!"{label}: budget 1 exposes no module"
          (outcome.module?.isNone && closed outcome) (outcomeDetail outcome)
    match parseBody? { maxDiagnostics := count } body with
    | none => check fails s!"{label}: the capture lexes" false
    | some outcome => do
        check fails s!"{label}: the exact budget keeps every diagnostic"
          (outcomeCodes outcome == expected && droppedOf outcome == 0)
          (outcomeDetail outcome)
        check fails s!"{label}: the exact budget exposes no module"
          (outcome.module?.isNone && closed outcome) (outcomeDetail outcome)
    match parseBody? { maxDiagnostics := count + 1 } body with
    | none => check fails s!"{label}: the capture lexes" false
    | some outcome =>
        check fails s!"{label}: limit plus one keeps every diagnostic"
          (outcomeCodes outcome == expected && droppedOf outcome == 0)
          (outcomeDetail outcome)
  checkBudget "truncation single" single singleCodes
  checkBudget "truncation double" double doubleCodes
  match parseBody? { maxDiagnosticBytes := 0 } single with
  | none => check fails "truncation bytes: the capture lexes" false
  | some outcome =>
      check fails "truncation bytes: a zero byte budget also fails closed"
        (outcome.module?.isNone && outcome.diagnostics.size == 1 &&
          droppedOf outcome == 2 && hasCode outcome ParseCode.diagnosticsTruncated)
        (outcomeDetail outcome)
  check fails "truncation: an unused budget never truncates"
    (acceptedAt { maxDiagnostics := 0 } "x == 1")

def scenarioNestingFamilies (fails : Failures) : IO Unit := do
  check fails "nesting: a non-nested module still parses at depth limit 0"
    (acceptedAt { maxNestingDepth := 0 } "x == 1")
  match parseBody? { maxNestingDepth := 0, maxDiagnostics := 0 } "x == )" with
  | none => check fails "nesting: the budget capture lexes" false
  | some outcome =>
      check fails "nesting: a zero budget still fails closed at depth limit 0"
        (!outcome.succeeded && outcome.module?.isNone && closed outcome)
        (outcomeDetail outcome)
  for (name, builder) in families do
    let baseDetail := detailOf? (parseBody? { maxNestingDepth := 0 } (builder 1))
    check fails s!"nesting: {name} is rejected at depth limit 0"
      (nestingRejectedAt { maxNestingDepth := 0 } (builder 1)) baseDetail
    for k in [1, 2, 3] do
      let limits : ParserLimits := { maxNestingDepth := k }
      checkAccepted fails s!"nesting: {name} of depth {k} parses at limit {k}"
        limits (builder k)
      checkNestingRejected fails
        s!"nesting: {name} of depth {k} is rejected at limit {k - 1}"
        { maxNestingDepth := k - 1 } (builder k)
      checkNestingRejected fails
        s!"nesting: {name} of depth {k + 1} is rejected at limit {k}"
        limits (builder (k + 1))
      checkAccepted fails
        s!"nesting: {name} of depth {k + 1} parses at limit {k + 1}"
        { maxNestingDepth := k + 1 } (builder (k + 1))
  checkNestingRejected fails "nesting: LOCAL declaration wrappers are rejected at limit 0"
    { maxNestingDepth := 0 } "LOCAL x == 1"
  checkAccepted fails "nesting: a LOCAL declaration parses at limit 1"
    { maxNestingDepth := 1 } "LOCAL x == 1"

def scenarioNestedCstLosslessness (fails : Failures) : IO Unit := do
  for (name, builder) in families do
    match detailed? { maxNestingDepth := 3 } (builder 3) with
    | none => check fails s!"CST: {name} of depth 3 lexes" false
    | some (source, stream, outcome) => do
        check fails s!"CST: {name} of depth 3 is accepted"
          (outcome.succeeded && closed outcome) (outcomeDetail outcome)
        check fails s!"CST: {name} of depth 3 reproduces the stream exactly"
          (outcome.cst.losslessAgainst stream)
        check fails s!"CST: {name} of depth 3 covers the whole capture"
          (outcome.cst.coversSource source)
        check fails s!"CST: {name} of depth 3 has nested ranges"
          (outcome.cst.rangesNested)

def scenarioRepeatedForms (fails : Failures) : IO Unit := do
  let prefix8 := "x == " ++ repeated 8 "~" ++ "TRUE"
  checkAccepted fails "repeated prefix: eight chains parse at limit 8"
    { maxNestingDepth := 8 } prefix8
  checkNestingRejected fails "repeated prefix: eight chains fail at limit 7"
    { maxNestingDepth := 7 } prefix8
  let temporal4 := "x == " ++ repeated 4 "[]" ++ "TRUE"
  checkAccepted fails "repeated temporal prefix: four chains parse at limit 4"
    { maxNestingDepth := 4 } temporal4
  checkNestingRejected fails "repeated temporal prefix: four chains fail at limit 3"
    { maxNestingDepth := 3 } temporal4
  let ifThen4 := "x == " ++ nestedIfThen 4
  checkAccepted fails "nested IF: four then-branch conditionals parse at limit 4"
    { maxNestingDepth := 4 } ifThen4
  checkNestingRejected fails "nested IF: four then-branch conditionals fail at limit 3"
    { maxNestingDepth := 3 } ifThen4
  let ifElse4 := "x == " ++ nestedIfElse 4
  checkAccepted fails "nested IF: four else-branch conditionals parse at limit 4"
    { maxNestingDepth := 4 } ifElse4
  checkNestingRejected fails "nested IF: four else-branch conditionals fail at limit 3"
    { maxNestingDepth := 3 } ifElse4
  let quantifier4 := "x == " ++ nested (fun inner => "\\A x \\in S : " ++ inner) 4 "TRUE"
  checkAccepted fails "nested quantifiers: four levels parse at limit 4"
    { maxNestingDepth := 4 } quantifier4
  checkNestingRejected fails "nested quantifiers: four levels fail at limit 3"
    { maxNestingDepth := 3 } quantifier4
  let mixed := "x == ((IF TRUE THEN \\A y \\in S : [i \\in S |-> 1] ELSE 2))"
  checkAccepted fails "mixed nesting: five levels parse at limit 5"
    { maxNestingDepth := 5 } mixed
  checkNestingRejected fails "mixed nesting: five levels fail at limit 4"
    { maxNestingDepth := 4 } mixed
  let deep := "x == " ++ nested (fun inner => "(" ++ inner ++ ")") 300 "1"
  checkNestingRejected fails "deep nesting: 300 levels exceed the default limit"
    {} deep
  match parseBody? {} deep with
  | none => check fails "deep nesting: the capture lexes" false
  | some outcome =>
      check fails "deep nesting: the nesting limit, not fuel, is reported"
        (!hasCode outcome ParseCode.recursionLimit && closed outcome)
        (outcomeDetail outcome)

def scenarioNestingRestoration (fails : Failures) : IO Unit := do
  checkAccepted fails "restore: sibling forms share one nesting level"
    { maxNestingDepth := 1 } "a == (1)\nb == (2)"
  checkAccepted fails "restore: sibling prefix forms share one nesting level"
    { maxNestingDepth := 1 } "a == ~1\nb == ~2"
  match parseBody? { maxNestingDepth := 1 } "a == [i \\in S |-> ]\nb == (2)" with
  | none => check fails "restore: the diagnostic-path capture lexes" false
  | some outcome => do
      check fails "restore: the diagnostic path still reports the error"
        (!outcome.succeeded && outcome.module?.isNone) (outcomeDetail outcome)
      check fails "restore: an error inside a nested form does not leak depth"
        (!hasCode outcome ParseCode.nestingDepth) (outcomeDetail outcome)
      check fails "restore: the diagnostic path reports only the intended error"
        (outcomeCodes outcome == [ParseCode.expectedExpression]) (outcomeDetail outcome)
      check fails "restore: the diagnostic path fails closed" (closed outcome)

def eofCopy (stream : TokenStream) : Token :=
  match stream.tokens.back? with
  | some token =>
      { token with
        kind := .eof
        spelling := ""
        leadingTrivia := #[]
        trailingTrivia := #[] }
  | none =>
      { kind := .eof
        spelling := ""
        range := zeroRange
        leadingTrivia := #[]
        trailingTrivia := #[] }

def scenarioStreamValidation (fails : Failures) : IO Unit := do
  match (do
      let source := capture (moduleText "x == 1")
      let stream ← lexStream? source
      pure (source, stream)) with
  | none => check fails "stream: the control capture lexes" false
  | some (source, stream) =>
      let outcome := parseStream LanguageProfile.default ParserProfile.default {} source stream
      check fails "stream: a consistent capture and stream are admitted"
        (outcome.succeeded) (outcomeDetail outcome)
  let sourceOf (text : String) : SourceUnit := capture (moduleText text)
  let streamOf? (text : String) : Option TokenStream := lexStream? (sourceOf text)
  let checkStreamFailure (name : String) (source : SourceUnit) (stream : TokenStream)
      (code : String) : IO Unit := do
    let outcome := parseStream LanguageProfile.default ParserProfile.default {} source stream
    check fails name
      (outcome.module?.isNone && outcome.hasErrors && outcome.cst.tokenCount == 0 &&
        outcomeCodes outcome == [code] &&
        outcome.diagnostics.toList.all (fun diagnostic =>
          diagnostic.severity.isError && diagnostic.stage == .parse))
      (outcomeDetail outcome)
  match streamOf? "x == 1", streamOf? "y == 2" with
  | some first, some second =>
      checkStreamFailure "stream: mismatched source and stream text"
        (sourceOf "x == 1") second ParseCode.streamTextMismatch
      checkStreamFailure "stream: tampered token spelling"
        (sourceOf "x == 1")
        { tokens := first.tokens.map (fun token =>
            if token.spelling == "1" then { token with spelling := "2" } else token) }
        ParseCode.streamTextMismatch
      checkStreamFailure "stream: absent final eof"
        (sourceOf "x == 1") { tokens := first.tokens.pop } ParseCode.streamEof
      checkStreamFailure "stream: duplicate final eof"
        (sourceOf "x == 1") { tokens := first.tokens.push (eofCopy first) }
        ParseCode.streamEof
      let withoutEof := first.tokens.pop
      let lastContent := match withoutEof.back? with
        | some token => token
        | none => eofCopy first
      checkStreamFailure "stream: a single eof that is not final"
        (sourceOf "x == 1")
        { tokens := withoutEof.push (eofCopy first) |>.push lastContent }
        ParseCode.streamEof
  | _, _ => check fails "stream: the comparison captures lex" false
  checkStreamFailure "stream: an empty token stream"
    (sourceOf "x == 1") { tokens := #[] } ParseCode.streamEof

def scenarioDeterminism (fails : Failures) : IO Unit := do
  let cases : List (String × ParserLimits × String) := [
    ("malformed", {}, "x == )"),
    ("truncated", { maxDiagnostics := 1 }, "x == )\ny == )"),
    ("nesting", { maxNestingDepth := 2 },
      "x == [i \\in S |-> [j \\in S |-> [k \\in S |-> 1]]]")
  ]
  for (name, limits, body) in cases do
    match parseBody? limits body with
    | none => check fails s!"determinism: {name} lexes" false
    | some first => do
        check fails s!"determinism: {name} is a bounded failure"
          (!first.succeeded && closed first) (outcomeDetail first)
        check fails s!"determinism: {name} repeats identically"
          (parseBody? limits body == some first &&
            parseBody? limits body == some first)
          (outcomeDetail first)
  let source := capture (moduleText "x == (1)")
  match lexStream? source with
  | none => check fails "determinism: the success capture lexes" false
  | some stream =>
      let first := parseStream LanguageProfile.default ParserProfile.default {} source stream
      let second := parseStream LanguageProfile.default ParserProfile.default {} source stream
      check fails "determinism: a successful parse repeats identically"
        (first == second && first.cst.text == second.cst.text && first.succeeded)
        (outcomeDetail first)
  let crlf := SourceUnit.create .inlineSourceMap specPath
    "---- MODULE TlaParserSpec ----\r\nx == 1\r\n====\r\n"
  match lexStream? crlf with
  | none => check fails "determinism: the CRLF capture lexes" false
  | some stream =>
      let outcome := parseStream LanguageProfile.default ParserProfile.default {} crlf stream
      check fails "determinism: normalized CRLF source is admitted"
        (outcome.succeeded && outcome.cst.text == crlf.normalizedText)
        (outcomeDetail outcome)

/-! ## Grammar views (TF2B) -/

/-- The operator definition named `name`, when the outcome recorded one. -/
def definitionOf? (outcome : ParseOutcome) (name : String) :
    Option OperatorDefinition :=
  match outcome.module? with
  | none => none
  | some parsedModule =>
      parsedModule.declarations.findSome? fun declaration =>
        match declaration with
        | .operator definition =>
            if definition.name == name then some definition else none
        | _ => none

/-- An operator application: its canonical spelling and arguments. -/
def applicationView? : Expression → Option (String × Array Expression)
  | .apply operator arguments _ => some (operator.spelling, arguments)
  | _ => none

/-- The normalized spelling of a name reference. -/
def nameView? : Expression → Option String
  | .name reference _ => some reference.spelling
  | _ => none

/-- The decoded value of a string literal node. -/
def stringView? : Expression → Option String
  | .string value _ => some value
  | _ => none

/-- A function application `f[i]`. -/
def functionApplyView? : Expression → Option (Expression × Expression)
  | .functionApply func index _ => some (func, index)
  | _ => none

/-- A field selection `r.field`. -/
def selectView? : Expression → Option (Expression × String)
  | .select base field _ => some (base, field)
  | _ => none

/-- A quantifier: its kind, bounds, and body. -/
def quantifierView? : Expression → Option (QuantifierKind × Array Bound × Expression)
  | .quantifier kind bounds body _ => some (kind, bounds, body)
  | _ => none

def boundNames (bounds : Array Bound) : List String :=
  bounds.toList.map fun bound => bound.name

/-- `true` per bound with a domain, i.e. `name \in S`. -/
def boundedFlags (bounds : Array Bound) : List Bool :=
  bounds.toList.map fun bound => bound.domain.isSome

/-- A copy of a parser profile with one operator's precedence level changed. -/
def withLevel (parserProfile : ParserProfile) (spelling : String) (level : Nat) :
    ParserProfile :=
  { parserProfile with
    operators := parserProfile.operators.map fun entry =>
      if entry.canonical == spelling then { entry with level } else entry }

/-- A copy of a parser profile with one operator's association changed. -/
def withAssociation (parserProfile : ParserProfile) (spelling : String)
    (association : OperatorAssociation) : ParserProfile :=
  { parserProfile with
    operators := parserProfile.operators.map fun entry =>
      if entry.canonical == spelling then { entry with association } else entry }

/-- Operator spelling of an argument: its own application spelling, its name,
or the empty string for a literal. -/
def argumentSpelling (expression : Expression) : String :=
  match applicationView? expression with
  | some (spelling, _) => spelling
  | none =>
      match expression with
      | .name reference _ => reference.spelling
      | _ => ""

/-- The application spelling and the spellings of its arguments, for shape
assertions about grouping. -/
def applicationSpellings? (expression : Expression) :
    Option (String × List String) :=
  (applicationView? expression).map fun view =>
    (view.1, view.2.toList.map argumentSpelling)

/-! ## TF2B scenarios -/

/-- The operator table is profile data: a modified profile changes parsing, and
the default profile is the frozen revision-1 combination. -/
def scenarioProfileOwnership (fails : Failures) : IO Unit := do
  check fails "profile: the default profile is the frozen revision-1 combination"
    (ParserProfile.default.name == "mirrors-tla-frontend-profile-1")
    ParserProfile.default.name
  match parseBody? {} "x == A = B = C" with
  | none => check fails "profile: the chained equality capture lexes" false
  | some outcome =>
      check fails "profile: the default table rejects a chained '='"
        (!outcome.succeeded && outcome.module?.isNone &&
          hasCode outcome ParseCode.precedenceConflict && closed outcome)
        (outcomeDetail outcome)
  check fails "profile: a modified association parses the same chain"
    (acceptedWith (withAssociation ParserProfile.default "=" .left) {}
      "x == A = B = C")
    "the modified profile did not accept 'A = B = C'"
  let unitAccepted := parseUnit (capture (moduleText "x == 1"))
  check fails "profile: the parseUnit convenience path accepts a module"
    unitAccepted.succeeded (outcomeDetail unitAccepted)
  let unitChained := parseUnit (capture (moduleText "x == A = B = C"))
  check fails "profile: parseUnit selects the default table"
    (!unitChained.succeeded && unitChained.module?.isNone &&
      hasCode unitChained ParseCode.precedenceConflict)
    (outcomeDetail unitChained)
  match parseWith? ParserProfile.default {} "x == A + B * C" with
  | none => check fails "profile: the default grouping capture lexes" false
  | some (_, _, outcome) =>
      check fails "profile: the default table groups '+' over '*'"
        (match definitionOf? outcome "x" with
         | some definition =>
             match applicationView? definition.body with
             | some (spelling, arguments) =>
                 spelling == "+" && arguments.size == 2 &&
                   (match arguments[1]? with
                    | some right =>
                        (applicationView? right).map (fun view => view.1) == some "*"
                    | none => false)
             | none => false
         | none => false)
        (outcomeDetail outcome)
  let swapped :=
    withLevel (withLevel ParserProfile.default "+" levelMultiplicative)
      "*" levelAdditive
  match parseWith? swapped {} "x == A + B * C" with
  | none => check fails "profile: the swapped grouping capture lexes" false
  | some (_, _, outcome) =>
      check fails "profile: swapping the levels moves the root to '*'"
        (match definitionOf? outcome "x" with
         | some definition =>
             match applicationView? definition.body with
             | some (spelling, arguments) =>
                 spelling == "*" && arguments.size == 2 &&
                   (match arguments[0]? with
                    | some left =>
                        (applicationView? left).map (fun view => view.1) == some "+"
                    | none => false)
             | none => false
         | none => false)
        (outcomeDetail outcome)

/-- The frozen table groups the corpus precedence fixture the way its expected
renderings do: `A + B * C` is `A + (B * C)`, `A + B < C * 2` is
`(A + B) < (C * 2)`, and so on. -/
def scenarioPrecedenceShapes (fails : Failures) : IO Unit := do
  let fixture :=
    "CONSTANT A, B, C\n" ++
    "Arithmetic == A + B * C\n" ++
    "Comparison == A + B < C * 2\n" ++
    "Implication == (A /\\ B) => C\n" ++
    "Disjunction == (A \\/ B) => C\n" ++
    "MixedJunction == A /\\ B \\/ C\n" ++
    "Negation == ~ A /\\ B\n" ++
    "Range == 1..C\n" ++
    "Grouping == (A => B) => C"
  match parseBody? {} fixture with
  | none => check fails "precedence: the fixture capture lexes" false
  | some outcome => do
      check fails "precedence: the fixture module parses"
        (outcome.succeeded && closed outcome) (outcomeDetail outcome)
      let shapeOf? (name : String) : Option (String × List String) :=
        (definitionOf? outcome name).bind fun definition =>
          applicationSpellings? definition.body
      let checkShape (name : String) (spelling : String)
          (arguments : List String) : IO Unit :=
        check fails s!"precedence: '{name}' groups as '{spelling}' over {arguments}"
          (shapeOf? name == some (spelling, arguments)) (outcomeDetail outcome)
      checkShape "Arithmetic" "+" ["A", "*"]
      checkShape "Comparison" "<" ["+", "*"]
      checkShape "Implication" "=>" ["/\\", "C"]
      checkShape "Disjunction" "=>" ["\\/", "C"]
      checkShape "MixedJunction" "\\/" ["/\\", "C"]
      checkShape "Negation" "/\\" ["~", "B"]
      checkShape "Grouping" "=>" ["=>", "C"]
      check fails "precedence: the range operator keeps both operands"
        (match definitionOf? outcome "Range" with
         | some definition =>
             match applicationView? definition.body with
             | some (spelling, arguments) =>
                 spelling == ".." && arguments.size == 2 &&
                   (match arguments[0]? with
                    | some left =>
                        (match left with
                         | .integer value _ => value == 1
                         | _ => false)
                    | none => false)
             | none => false
         | none => false)
        (outcomeDetail outcome)

/-- Colon-form record sets remain distinct from record values and retain
field/domain order and ranges. -/
def scenarioRecordSets (fails : Failures) : IO Unit := do
  let body :=
    "CONSTANT S\n" ++
    "Types == [case: S \\cup {0}, token: S]\n" ++
    "Value == [case |-> 0, token |-> 1]"
  match detailed? {} body with
  | none => check fails "record set: the capture lexes" false
  | some (source, stream, outcome) => do
      check fails "record set: the module parses losslessly"
        (outcome.succeeded && closed outcome &&
          outcome.cst.losslessAgainst stream && outcome.cst.rangesNested &&
          outcome.cst.coversSource source)
        (outcomeDetail outcome)
      check fails "record set: colon fields have a distinct AST node"
        (match definitionOf? outcome "Types" with
         | some definition =>
             match definition.body with
             | .recordSet fields range =>
                 fields.map (·.name) == #["case", "token"] &&
                   fields.all (fun field =>
                     field.range.start.offset < field.range.stop.offset) &&
                   range.start.offset < range.stop.offset
             | _ => false
         | _ => false)
        (outcomeDetail outcome)
      check fails "record set: value fields retain the record-value node"
        (match definitionOf? outcome "Value" with
         | some definition =>
             match definition.body with
             | .record fields _ => fields.map (·.name) == #["case", "token"]
             | _ => false
         | _ => false)
        (outcomeDetail outcome)
/-- Bounded and unbounded quantifier groups, their order, and their failures. -/
def scenarioQuantifiers (fails : Failures) : IO Unit := do
  let checkBounds (name : String) (body : String) (expected : List String)
      (flags : List Bool) : IO Unit := do
    match detailed? {} body with
    | none => check fails s!"quantifiers: {name} capture lexes" false
    | some (source, stream, outcome) =>
        let view? :=
          match definitionOf? outcome "x" with
          | some definition => quantifierView? definition.body
          | none => none
        let ok :=
          match view? with
          | some (_, bounds, _) =>
              boundNames bounds == expected && boundedFlags bounds == flags
          | none => false
        check fails s!"quantifiers: {name}" ok (outcomeDetail outcome)
        check fails s!"quantifiers: {name} keeps a lossless CST"
          (outcome.cst.text == source.normalizedText &&
            outcome.cst.losslessAgainst stream && outcome.cst.rangesNested)
          (outcomeDetail outcome)
  checkBounds "one bounded binder" "x == \\A y \\in S : P" ["y"] [true]
  checkBounds "one unbounded binder" "x == \\A y : P" ["y"] [false]
  checkBounds "two unbounded binders keep source order" "x == \\E y, z : P"
    ["y", "z"] [false, false]
  checkBounds "two bounded binders" "x == \\E y \\in S, z \\in T : P"
    ["y", "z"] [true, true]
  checkBounds "an unbounded binder may precede a bounded one"
    "x == \\A y, z \\in S : P" ["y", "z"] [false, true]
  match parseBody? {} "x == \\E y : P" with
  | none => check fails "quantifiers: the exists capture lexes" false
  | some outcome =>
      check fails "quantifiers: the '\\E' kind is recorded"
        (match definitionOf? outcome "x" with
         | some definition =>
             (match quantifierView? definition.body with
              | some (kind, _, _) => kind == QuantifierKind.exists
              | none => false)
         | none => false)
        (outcomeDetail outcome)
  let checkRejected (name : String) (body : String) (code : String) : IO Unit := do
    match parseBody? {} body with
    | none => check fails s!"quantifiers: {name} capture lexes" false
    | some outcome =>
        check fails s!"quantifiers: {name}"
          (!outcome.succeeded && outcome.module?.isNone &&
            hasCode outcome code && closed outcome)
          (outcomeDetail outcome)
  checkRejected "a bounded binder cannot be followed by an unbounded name"
    "x == \\A y \\in S, z : P" ParseCode.mixedBounds
  checkRejected "a missing ':' is an error" "x == \\A y \\in S P"
    ParseCode.expectedToken
  checkRejected "a missing ',' is an error" "x == \\A y \\in S z : P"
    ParseCode.expectedToken
  checkAccepted fails "quantifiers: two unbounded levels parse at depth limit 2"
    { maxNestingDepth := 2 } "x == \\A y : \\E z : P"
  checkNestingRejected fails
    "quantifiers: two unbounded levels fail at depth limit 1"
    { maxNestingDepth := 1 } "x == \\A y : \\E z : P"

/-- Functional, infix, prefix, and postfix definitions and applications. -/
def scenarioUserOperators (fails : Failures) : IO Unit := do
  let definitions :=
    "Double(v) == 2 * v\n" ++
    "a \\oplus b == a + b\n" ++
    "~ p == p\n" ++
    "value \\frob == value + 1"
  match detailed? {} definitions with
  | none => check fails "operators: the definition capture lexes" false
  | some (source, stream, outcome) => do
      check fails "operators: the definition module parses"
        (outcome.succeeded && closed outcome) (outcomeDetail outcome)
      check fails "operators: the definition module keeps a lossless CST"
        (outcome.cst.text == source.normalizedText &&
          outcome.cst.losslessAgainst stream && outcome.cst.rangesNested)
        (outcomeDetail outcome)
      let checkDefinition (name : String) (fixity : OperatorFixity)
          (parameters : List String) : IO Unit :=
        match definitionOf? outcome name with
        | none =>
            check fails s!"operators: '{name}' is recorded" false
              (outcomeDetail outcome)
        | some definition => do
            let parameterNames :=
              definition.parameters.toList.map fun parameter => parameter.name
            check fails s!"operators: '{name}' records fixity and parameter order"
              (definition.fixity == fixity &&
                parameterNames == parameters)
              s!"fixity={repr definition.fixity} parameters={parameterNames}"
            check fails s!"operators: '{name}' records source ranges"
              (definition.nameRange.start.offset < definition.nameRange.stop.offset &&
                definition.range.start.offset < definition.range.stop.offset &&
                definition.parameters.toList.all (fun parameter =>
                  parameter.range.start.offset < parameter.range.stop.offset))
              (outcomeDetail outcome)
      checkDefinition "Double" .functional ["v"]
      checkDefinition "\\oplus" .infix ["a", "b"]
      checkDefinition "~" .prefix ["p"]
      checkDefinition "\\frob" .postfix ["value"]
  let applications :=
    "Double(v) == 2 * v\n" ++
    "Functional == Double(3)\n" ++
    "Prefix == ~ TRUE\n" ++
    "Apply == Double(3) \\oplus (4 \\frob)\n" ++
    "Prime == (4 \\frob)'\n" ++
    "Index == ff[1]\n" ++
    "Field == record.field\n" ++
    "Post == 4 \\frob\n" ++
    "Order == 3 \\frob - 4"
  match detailed? {} applications with
  | none => check fails "operators: the application capture lexes" false
  | some (source, stream, outcome) => do
      check fails "operators: the application module parses"
        (outcome.succeeded && closed outcome) (outcomeDetail outcome)
      check fails "operators: the application module keeps a lossless CST"
        (outcome.cst.text == source.normalizedText &&
          outcome.cst.losslessAgainst stream && outcome.cst.rangesNested)
        (outcomeDetail outcome)
      let bodyOf? (name : String) : Option Expression :=
        (definitionOf? outcome name).map fun definition => definition.body
      check fails "operators: 'Double(3)' is one functional application"
        (match bodyOf? "Functional" with
         | some body =>
             match applicationView? body with
             | some (spelling, arguments) =>
                 spelling == "Double" && arguments.size == 1
             | none => false
         | none => false)
        (outcomeDetail outcome)
      check fails "operators: '~ TRUE' is one prefix application"
        (match bodyOf? "Prefix" with
         | some body =>
             match applicationView? body with
             | some (spelling, arguments) =>
                 spelling == "~" && arguments.size == 1
             | none => false
         | none => false)
        (outcomeDetail outcome)
      check fails "operators: 'Double(3) \\oplus (4 \\frob)' applies both fixities"
        (match bodyOf? "Apply" with
         | some body =>
             match applicationView? body with
             | some (spelling, arguments) =>
                 spelling == "\\oplus" && arguments.size == 2 &&
                   (match arguments[0]? with
                    | some left =>
                        (applicationView? left).map (fun view => view.1) ==
                          some "Double"
                    | none => false) &&
                   (match arguments[1]? with
                    | some right =>
                        (applicationView? right).map (fun view => view.1) ==
                          some "\\frob"
                    | none => false)
             | none => false
         | none => false)
        (outcomeDetail outcome)
      check fails "operators: prime stays distinct from the user postfix operator"
        (match bodyOf? "Prime" with
         | some body =>
             match applicationView? body with
             | some (spelling, arguments) =>
                 spelling == "'" && arguments.size == 1 &&
                   (match arguments[0]? with
                    | some inner =>
                        (applicationView? inner).map (fun view => view.1) ==
                          some "\\frob"
                    | none => false)
             | none => false
         | none => false)
        (outcomeDetail outcome)
      check fails "operators: '4 \\frob' is one postfix application"
        (match bodyOf? "Post" with
         | some body =>
             match applicationView? body with
             | some (spelling, arguments) =>
                 spelling == "\\frob" && arguments.size == 1
             | none => false
         | none => false)
        (outcomeDetail outcome)
      check fails "operators: a user postfix binds tighter than the infix '-'"
        (match bodyOf? "Order" with
         | some body =>
             match applicationView? body with
             | some (spelling, arguments) =>
                 spelling == "-" && arguments.size == 2 &&
                   (match arguments[0]? with
                    | some left =>
                        (applicationView? left).map (fun view => view.1) ==
                          some "\\frob"
                    | none => false)
             | none => false
         | none => false)
        (outcomeDetail outcome)
      check fails "operators: function application stays distinct"
        (match bodyOf? "Index" with
         | some body =>
             (match functionApplyView? body with
              | some (func, _) => nameView? func == some "ff"
              | none => false)
         | none => false)
        (outcomeDetail outcome)
      check fails "operators: field selection stays distinct"
        (match bodyOf? "Field" with
         | some body =>
             (selectView? body).map (fun view => view.2) == some "field"
         | none => false)
        (outcomeDetail outcome)
  let checkRejected (name : String) (body : String) : IO Unit := do
    match parseBody? {} body with
    | none => check fails s!"operators: {name} capture lexes" false
    | some outcome =>
        check fails s!"operators: {name}"
          (!outcome.succeeded && outcome.module?.isNone && closed outcome)
          (outcomeDetail outcome)
  checkRejected "an unknown spelling cannot start a prefix definition"
    "\\frob x == 1"
  checkRejected "an unknown spelling cannot be an infix application"
    "R == 3 \\frob 4"
  checkRejected "an unknown spelling cannot define an infix operator"
    "x \\frob y == x + y"
  checkRejected "an unknown spelling cannot begin an application operand"
    "R == \\frob 4"
  checkRejected "'-' cannot start a prefix definition while it has an infix entry"
    "- x == 1"
  checkRejected "an infix definition needs its right parameter" "a + == 1"
  checkRejected "a repeated '=' is not an operand" "x == a = = b"

/-- The AST carries the decoded literal value while the CST keeps the spelling. -/
def scenarioStringValues (fails : Failures) : IO Unit := do
  let formFeed := String.ofList ['a', Char.ofNat 12, 'b']
  let cases : List (String × String × String) := [
    ("ordinary", "x == \"ab\"", "ab"),
    ("escaped quote", "x == \"a\\\"b\"", "a\"b"),
    ("backslash", "x == \"a\\\\b\"", "a\\b"),
    ("tab", "x == \"a\\tb\"", "a\tb"),
    ("newline", "x == \"a\\nb\"", "a\nb"),
    ("carriage return", "x == \"a\\rb\"", "a\rb"),
    ("form feed", "x == \"a\\fb\"", formFeed),
    ("decoded exactly once", "x == \"a\\\\nb\"", "a\\nb")
  ]
  for (name, body, expected) in cases do
    match detailed? {} body with
    | none => check fails s!"strings: {name} capture lexes" false
    | some (source, stream, outcome) => do
        let value? :=
          match definitionOf? outcome "x" with
          | some definition => stringView? definition.body
          | none => none
        check fails s!"strings: {name} decodes to its semantic value"
          (outcome.succeeded && value? == some expected) (outcomeDetail outcome)
        check fails s!"strings: {name} keeps the spelling in the CST"
          (outcome.cst.text == source.normalizedText &&
            outcome.cst.losslessAgainst stream)
          (outcomeDetail outcome)

/-! ## TF2C scenarios -/

/-- The theorem-like declaration named `name`, when the outcome recorded one. -/
def theoremOf? (outcome : ParseOutcome) (name : String) : Option Theorem :=
  match outcome.module? with
  | none => none
  | some parsedModule =>
      parsedModule.declarations.findSome? fun declaration =>
        match declaration with
        | .«theorem» thm =>
            if thm.name == some name then some thm else none
        | _ => none

/-- Declaration kinds and names in source order. -/
def declarationShape (outcome : ParseOutcome) : List (String × List String) :=
  match outcome.module? with
  | none => []
  | some parsedModule =>
      parsedModule.declarations.toList.map fun declaration =>
        match declaration with
        | .constant _ names => ("constant", names.toList.map (fun item => item.name))
        | .variable _ names => ("variable", names.toList.map (fun item => item.name))
        | .recursive _ operators =>
            ("recursive", operators.toList.map (fun item => item.name))
        | .operator definition => ("operator", [definition.name])
        | .«local» _ _ => ("local", [])
        | .«instance» _ => ("instance", [])
        | .assumption _ => ("assumption", [])
        | .«theorem» thm => ("theorem", thm.name.toList)
        | .«extends» _ => ("extends", [])

/-- Number of concrete-syntax nodes with the given kind. -/
def nodeCount (kind : CstKind) : CstNode → Nat
  | .token _ => 0
  | .node nodeKind _ children =>
      (if nodeKind == kind then 1 else 0) +
        children.foldl (fun total child => total + nodeCount kind child) 0

/-- Ranges of the concrete-syntax nodes with the given kind, in source order. -/
def kindRanges (kind : CstKind) : CstNode → List SourceRange
  | .token _ => []
  | .node nodeKind range children =>
      (if nodeKind == kind then [range] else []) ++
        children.foldl (fun total child => total ++ kindRanges kind child) []

/-- Byte offset of the first occurrence of `needle`; the fixtures are ASCII. -/
def offsetOf (text needle : String) : Nat :=
  ((text.splitOn needle).head?.getD "").length

/-- A capture that fails closed with exactly `codes` and a lossless tree. -/
def checkProofCodes (fails : Failures) (name : String) (limits : ParserLimits)
    (body : String) (codes : List String) : IO Unit := do
  match detailed? limits body with
  | none => check fails s!"{name}: the capture lexes" false
  | some (source, stream, outcome) =>
      check fails s!"{name}: fails closed with exactly {codes}"
        (!outcome.succeeded && outcome.module?.isNone && closed outcome &&
          outcomeCodes outcome == codes && outcome.cst.losslessAgainst stream &&
          outcome.cst.text == source.normalizedText && outcome.cst.rangesNested)
        (outcomeDetail outcome)

/-- A capture that fails closed carrying `code`, with a lossless tree. -/
def checkProofRejected (fails : Failures) (name : String) (limits : ParserLimits)
    (body : String) (code : String) : IO Unit := do
  match detailed? limits body with
  | none => check fails s!"{name}: the capture lexes" false
  | some (source, stream, outcome) =>
      check fails s!"{name}: fails closed with {code}"
        (!outcome.succeeded && outcome.module?.isNone && closed outcome &&
          hasCode outcome code && outcome.cst.losslessAgainst stream &&
          outcome.cst.text == source.normalizedText && outcome.cst.rangesNested)
        (outcomeDetail outcome)

/-- Legal proof-local steps, including the declaration-shaped
`name == expression` text an opaque scan must not mistake for a module
declaration. -/
def proofLocalRegionText : String :=
  "PROOF\n" ++
    "  ASSUME A\n" ++
    "  HAVE B == A\n" ++
    "  DEFINE C == 1\n" ++
    "  SUFFICES A\n" ++
    "  TAKE x\n" ++
    "  PICK y\n" ++
    "  WITNESS 1\n" ++
    "  CASE A\n" ++
    "  USE B\n" ++
    "  HIDE A\n" ++
    "  LET d == 2\n" ++
    "  e == 3\n" ++
    "QED"

/-- The proof-local region followed by two real module declarations. -/
def proofLocalBody : String :=
  "THEOREM T == TRUE\n" ++ proofLocalRegionText ++ "\nVARIABLE v\nReal == 4"

/-- `items` joined with line breaks and no trailing line break: recorded proof
ranges stop at the keyword that ends the region, not at the next newline. -/
def proofLines (items : List String) : String :=
  String.intercalate "\n" items

/-- One theorem at `depth` nested numbered step levels; the proof text runs
from `PROOF` through the final labelled `QED`. -/
def nestedStepProofText (depth : Nat) : String :=
  let opens := (List.range depth).map fun index =>
    s!"{repeated (index + 1) "  "}<{index + 1}>1. STEP {index + 1}"
  let closes := (List.range depth).reverse.map fun index =>
    s!"{repeated (index + 1) "  "}<{index + 1}>2. QED"
  proofLines ("PROOF" :: opens ++ closes)

/-- One theorem at `depth` nested `PROOF ... QED` scopes; the proof text runs
from the region's own `PROOF` through its final `QED`. -/
def nestedRegionProofText (depth : Nat) : String :=
  proofLines
    ("PROOF" :: List.replicate depth "PROOF" ++ ["  HAVE A == TRUE"] ++
      List.replicate depth "QED" ++ ["QED"])

/-- The opaque proof treatment of theorem `T`: the module is accepted, the
recorded region covers exactly `regionText` (from its `PROOF` or `BY` keyword
through the keyword that ends the region), the CST keeps one proof-region node
with that range, the tree stays lossless, and the parse repeats identically. -/
def checkProofRegion (fails : Failures) (name : String) (body : String)
    (regionText : String) (treatment : ProofTreatment) : IO Unit := do
  match detailed? {} body with
  | none => check fails s!"{name}: the capture lexes" false
  | some (source, stream, outcome) => do
      let theorem? := theoremOf? outcome "T"
      check fails s!"{name}: the module is accepted"
        (outcome.succeeded && closed outcome) (outcomeDetail outcome)
      check fails s!"{name}: the theorem records one {toString (repr treatment)} region"
        (((theorem?.bind (fun thm => thm.proof)).map
            (fun region => region.treatment)) == some treatment)
        (outcomeDetail outcome)
      match theorem?, theorem?.bind (fun thm => thm.proof) with
      | some thm, some region => do
          let start := offsetOf source.normalizedText regionText
          let stop := start + regionText.length
          check fails s!"{name}: the region starts at its proof keyword"
            (region.range.start.offset == start)
            s!"start={region.range.start.offset} expected={start}"
          check fails s!"{name}: the region stops at the keyword that ends it"
            (region.range.stop.offset == stop)
            s!"stop={region.range.stop.offset} expected={stop}"
          check fails s!"{name}: the theorem range covers the region"
            (thm.range.start.offset ≤ region.range.start.offset &&
              region.range.stop.offset ≤ thm.range.stop.offset)
            (outcomeDetail outcome)
      | _, _ => check fails s!"{name}: the region is recorded" false
      check fails s!"{name}: the CST has exactly one opaque proof region"
        (nodeCount .proofRegion outcome.cst.root == 1)
        s!"proofRegion nodes={nodeCount .proofRegion outcome.cst.root}"
      check fails s!"{name}: the CST region range is the recorded range"
        (kindRanges .proofRegion outcome.cst.root ==
          ((theorem?.bind (fun thm => thm.proof)).toList.map
            (fun region => region.range)))
        (outcomeDetail outcome)
      check fails s!"{name}: the CST stays lossless"
        (outcome.cst.losslessAgainst stream && outcome.cst.text == source.normalizedText &&
          outcome.cst.rangesNested && outcome.cst.coversSource source)
        (outcomeDetail outcome)
      check fails s!"{name}: the parse repeats identically"
        (parseBody? {} body == some outcome)
        (outcomeDetail outcome)

/-- One theorem whose proof text (from its `PROOF` or `BY` keyword through the
keyword that ends the region) is `proofText`, followed by a real `VARIABLE`
declaration that must still be found as its own declaration. -/
def checkProofTheorem (fails : Failures) (name : String) (proofText : String)
    (treatment : ProofTreatment) : IO Unit := do
  let body := "THEOREM T == TRUE\n" ++ proofText ++ "\nVARIABLE v"
  checkProofRegion fails name body proofText treatment
  match parseBody? {} body with
  | none => check fails s!"{name}: the capture lexes" false
  | some outcome =>
      check fails s!"{name}: the following declaration is still found"
        (declarationShape outcome == [("theorem", ["T"]), ("variable", ["v"])])
        (outcomeDetail outcome)

def scenarioProofTerminals (fails : Failures) : IO Unit := do
  match detailed? {} "THEOREM T == TRUE\nVARIABLE v" with
  | none => check fails "proof: the no-proof capture lexes" false
  | some (_, _, outcome) =>
      check fails "proof: a theorem statement without a proof is accepted"
        (outcome.succeeded && closed outcome) (outcomeDetail outcome)
      check fails "proof: a theorem statement without a proof has no region"
        ((theoremOf? outcome "T").bind (fun thm => thm.proof) == none)
        (outcomeDetail outcome)
      check fails "proof: the following declaration is still found"
        (declarationShape outcome == [("theorem", ["T"]), ("variable", ["v"])])
        (outcomeDetail outcome)
      check fails "proof: a statement-only theorem records no proof region node"
        (nodeCount .proofRegion outcome.cst.root == 0)
        (outcomeDetail outcome)
  checkProofTheorem fails "omitted terminal" "PROOF OMITTED" .omitted
  checkProofTheorem fails "obvious terminal" "PROOF OBVIOUS" .opaque
  checkAccepted fails "proof: a terminal region parses at depth limit 0"
    { maxNestingDepth := 0 } "THEOREM T == TRUE PROOF OMITTED"
  checkAccepted fails "proof: a theorem statement parses at depth limit 0"
    { maxNestingDepth := 0 } "THEOREM T == TRUE"

def scenarioProofOpacity (fails : Failures) : IO Unit := do
  checkProofRegion fails "opaque region" proofLocalBody proofLocalRegionText .opaque
  match parseBody? {} proofLocalBody with
  | none => check fails "proof: the proof-local capture lexes" false
  | some outcome => do
      check fails "proof: the proof-local capture records only real declarations"
        (declarationShape outcome ==
          [("theorem", ["T"]), ("variable", ["v"]), ("operator", ["Real"])])
        (outcomeDetail outcome)
      for leaked in ["B", "C", "d", "e"] do
        check fails s!"proof: proof-local definition '{leaked}' stays inside the region"
          ((definitionOf? outcome leaked).isNone) (outcomeDetail outcome)
      check fails "proof: the theorem's proof region is opaque"
        (((theoremOf? outcome "T").bind (fun thm => thm.proof)).map
            (fun region => region.treatment) == some .opaque)
        (outcomeDetail outcome)
  checkProofTheorem fails "labelled steps"
    "PROOF\n  <1>1. STEP\n  <1>2. QED" .opaque
  checkProofTheorem fails "a first-level QED step label"
    "PROOF\n  <2>1. QED" .opaque
  checkProofTheorem fails "nested step levels" (nestedStepProofText 2) .opaque
  checkProofTheorem fails "nested proof regions" (nestedRegionProofText 1) .opaque
  checkProofTheorem fails "a balanced delimiter stays opaque"
    "PROOF\n  HAVE A == [i \\in S |-> (1)]\nQED" .opaque
  checkAccepted fails "proof: a labelled proof parses at depth limit 0"
    { maxNestingDepth := 0 }
    "THEOREM T == TRUE\nPROOF\n  <1>1. A\n  <1>2. QED\nVARIABLE v"
  let stepLevelsTwo := "THEOREM T == TRUE\n" ++ nestedStepProofText 2 ++ "\nVARIABLE v"
  checkAccepted fails "proof: one nested step level parses at limit 1"
    { maxNestingDepth := 1 } stepLevelsTwo
  checkNestingRejected fails "proof: one nested step level is rejected at limit 0"
    { maxNestingDepth := 0 } stepLevelsTwo
  let stepLevelsThree := "THEOREM T == TRUE\n" ++ nestedStepProofText 3 ++ "\nVARIABLE v"
  checkAccepted fails "proof: two nested step levels parse at limit 2"
    { maxNestingDepth := 2 } stepLevelsThree
  checkNestingRejected fails "proof: two nested step levels are rejected at limit 1"
    { maxNestingDepth := 1 } stepLevelsThree
  let nestedRegion := "THEOREM T == TRUE\n" ++ nestedRegionProofText 1 ++ "\nVARIABLE v"
  checkAccepted fails "proof: one nested region parses at limit 1"
    { maxNestingDepth := 1 } nestedRegion
  checkNestingRejected fails "proof: one nested region is rejected at limit 0"
    { maxNestingDepth := 0 } nestedRegion

def scenarioProofFailClosed (fails : Failures) : IO Unit := do
  checkProofCodes fails "missing QED" {}
    "THEOREM T == TRUE\nPROOF\n  HAVE A == TRUE" [ParseCode.proofTermination]
  checkProofCodes fails "missing QED after a labelled step" {}
    "THEOREM T == TRUE\nPROOF\n  <1>1. A\n  <1>2. STEP" [ParseCode.proofTermination]
  checkProofRejected fails "a declaration keyword inside a proof region" {}
    "THEOREM T == TRUE\nPROOF\n  HAVE A == TRUE\nVARIABLE v" ParseCode.proofUnsupported
  checkProofRejected fails "a theorem inside a proof region" {}
    "THEOREM T == TRUE\nPROOF\n  THEOREM U == TRUE\nQED" ParseCode.proofUnsupported
  checkProofRejected fails "an unmatched closing delimiter" {}
    "THEOREM T == TRUE\nPROOF\n  HAVE A == 1)\nQED" ParseCode.proofUnsupported
  checkProofRejected fails "a mismatched delimiter pair" {}
    "THEOREM T == TRUE\nPROOF\n  HAVE A == (1]\nQED" ParseCode.proofUnsupported
  checkProofRejected fails "a step level that skips a level" {}
    "THEOREM T == TRUE\nPROOF\n  <1>1. A\n    <3>1. B\n  QED" ParseCode.proofUnsupported
  checkProofRejected fails "a BY step without arguments" {}
    "THEOREM T == TRUE BY\nVARIABLE v" ParseCode.proofUnsupported

def scenarioProofByTerminal (fails : Failures) : IO Unit := do
  checkProofTheorem fails "BY terminal" "BY DEF T" .opaque
  checkProofTheorem fails "BY argument list" "BY A, B" .opaque
  checkAccepted fails "proof: a BY terminal parses at depth limit 0"
    { maxNestingDepth := 0 } "THEOREM T == TRUE BY DEF T\nVARIABLE v"
  checkProofRejected fails "a BY step with nested proof syntax" {}
    "THEOREM T == TRUE BY QED\nVARIABLE v" ParseCode.proofUnsupported
/-! ## Corpus-driven acceptance (TF2D) -/

namespace Corpus

/-! ### Strict manifest and summary decoding -/

def manifestSchema : String := "mirrors.tla-frontend-corpus/1"

def summarySchema : String := "mirrors.tla-frontend-summary/1"

/-- Closed frontend-stage vocabulary, matching `DiagnosticStage`. -/
def frontendStages : List String :=
  ["lex", "parse", "moduleGraph", "nameResolution", "substitution", "level",
   "sourceEvidence"]

def frontendOutcomes : List String := ["accepted", "rejected"]

def frontendReasons : List String := ["malformed", "limit", "profile_limit"]

def frontendProviders : List String := ["borrowed-directory", "inline-source-map"]

def declarationKinds : List String :=
  ["constant", "variable", "recursive", "operator", "local", "instance",
   "assumption", "axiom", "theorem"]

def dependencyKinds : List String := ["extends", "namedInstance", "unnamedInstance"]

def proofTreatmentNames : List String := ["none", "omitted", "opaque"]

def decodeStringField (json : Json) (key : String) : Except String String :=
  json.getObjVal? key >>= Json.getStr?

def decodeNatField (json : Json) (key : String) : Except String Nat :=
  json.getObjVal? key >>= Json.getNat?

def decodeBoolField (json : Json) (key : String) : Except String Bool :=
  json.getObjVal? key >>= Json.getBool?

/-- An optional field: absent or `null` is `none`, any other value must decode. -/
def decodeOptionalString (json : Json) (key : String) :
    Except String (Option String) :=
  match json.getObjVal? key with
  | .ok .null => .ok none
  | .ok value => (Json.getStr? value).map some
  | .error _ => .ok none

def decodeOptionalNat (json : Json) (key : String) : Except String (Option Nat) :=
  match json.getObjVal? key with
  | .ok value => (Json.getNat? value).map some
  | .error _ => .ok none

def decodeArrayField (json : Json) (key : String) : Except String (Array Json) :=
  json.getObjVal? key >>= Json.getArr?

def decodeOptionalArrayField (json : Json) (key : String) :
    Except String (Option (Array Json)) :=
  match json.getObjVal? key with
  | .ok value => (Json.getArr? value).map some
  | .error _ => .ok none

def decodeStringArray (json : Json) : Except String (Array String) :=
  Json.getArr? json >>= fun items => items.mapM Json.getStr?

def decodeStringArrayField (json : Json) (key : String) : Except String (Array String) :=
  decodeArrayField json key >>= fun items => items.mapM Json.getStr?

def decodeOptionalStringArray (json : Json) (key : String) :
    Except String (Option (Array String)) :=
  match json.getObjVal? key with
  | .error _ => .ok none
  | .ok value =>
      ((Json.getArr? value) >>= fun items => items.mapM Json.getStr?).map some

/-- Provider-relative path admission: no absolute path and no `..` segment. -/
def checkRelativePath (path : String) : Except String String :=
  if path.isEmpty then
    .error "fixture path is empty"
  else if path.startsWith "/" then
    .error s!"fixture path is absolute: {path}"
  else if (path.splitOn "/").contains ".." then
    .error s!"fixture path escapes its provider root: {path}"
  else
    .ok path

structure InlineSource where
  logicalName : String
  file : String
  deriving Repr, BEq

structure Fixture where
  id : String
  kind : String
  stage : String
  reason : Option String
  provider : String
  root : String
  files : Array String
  sourceRoot : String
  summary : Option String
  inlineSourceMap : Array InlineSource
  minDiagnostics : Option Nat
  equivalenceGroup : Option String
  branches : Array String
  deriving Repr, BEq

structure Manifest where
  schema : String
  profile : String
  status : String
  stages : Array String
  branches : Array String
  fixtures : Array Fixture
  deriving Repr, BEq

def decodeInlineSource (json : Json) : Except String InlineSource := do
  let logicalName ← decodeStringField json "logicalName"
  let file ← decodeStringField json "file"
  return { logicalName, file }

def decodeFixture (stages : Array String) (json : Json) : Except String Fixture := do
  let id ← decodeStringField json "id"
  let kind ← decodeStringField json "kind"
  if !frontendOutcomes.contains kind then
    throw s!"fixture {id}: unknown outcome {kind}"
  let stage ← decodeStringField json "stage"
  if !stages.contains stage then
    throw s!"fixture {id}: unknown stage {stage}"
  let reason ← decodeOptionalString json "reason"
  match kind, reason with
  | "accepted", some value =>
      throw s!"fixture {id}: accepted outcome carries reason {value}"
  | "rejected", none =>
      throw s!"fixture {id}: rejected outcome has no reason"
  | "rejected", some value =>
      if !frontendReasons.contains value then
        throw s!"fixture {id}: unknown reason {value}"
  | _, _ => pure ()
  let provider ← decodeStringField json "provider"
  if !frontendProviders.contains provider then
    throw s!"fixture {id}: unknown provider {provider}"
  let root ← decodeStringField json "root"
  let files ← decodeStringArrayField json "files"
  let files ← files.mapM checkRelativePath
  if files.isEmpty then
    throw s!"fixture {id}: no source files"
  let sourceRoot ← decodeOptionalString json "sourceRoot"
  match sourceRoot with
  | some path => discard (checkRelativePath path)
  | none => pure ()
  if provider == "borrowed-directory" && sourceRoot.isNone then
    throw s!"fixture {id}: borrowed-directory provider has no sourceRoot"
  let summary ← decodeOptionalString json "summary"
  if kind == "accepted" && summary.isNone then
    throw s!"fixture {id}: accepted fixture has no summary"
  let inlineSourceMap ←
    match ← decodeOptionalArrayField json "inlineSourceMap" with
    | some items => items.mapM decodeInlineSource
    | none => pure #[]
  if provider == "inline-source-map" then do
    if inlineSourceMap.isEmpty then
      throw s!"fixture {id}: inline provider has an empty source map"
    for entry in inlineSourceMap do
      if !files.contains entry.file then
        throw s!"fixture {id}: inline file {entry.file} is not listed in files"
  let minDiagnostics ← decodeOptionalNat json "minDiagnostics"
  match minDiagnostics with
  | some value =>
      if value == 0 then throw s!"fixture {id}: minDiagnostics must be positive"
  | none => pure ()
  let equivalenceGroup ← decodeOptionalString json "equivalenceGroup"
  match equivalenceGroup with
  | some value =>
      if value.isEmpty then throw s!"fixture {id}: empty equivalence group"
  | none => pure ()
  let branches ← decodeStringArrayField json "branches"
  return { id, kind, stage, reason, provider, root, files,
           sourceRoot := sourceRoot.getD "", summary, inlineSourceMap,
           minDiagnostics, equivalenceGroup, branches }

/-- Strict corpus decoding: closed vocabularies, unique ids, relative paths,
declared summaries, and branch references that exist in the manifest. -/
def decodeManifest (text : String) : Except String Manifest := do
  let json ← Json.parse text
  let schema ← decodeStringField json "schema"
  if schema != manifestSchema then
    throw s!"unknown corpus schema {schema}"
  let profile ← decodeStringField json "profile"
  let status ← decodeStringField json "status"
  let stages ← decodeStringArrayField json "stages"
  if stages.isEmpty then
    throw "the manifest declares no stages"
  for stage in stages do
    if !frontendStages.contains stage then
      throw s!"unknown stage {stage}"
  if stages.toList.eraseDups.length != stages.size then
    throw "duplicate stage in the manifest"
  let branchItems ← decodeArrayField json "branches"
  let branches ← branchItems.mapM fun item => decodeStringField item "id"
  if branches.toList.eraseDups.length != branches.size then
    throw "duplicate branch id"
  let fixtureItems ← decodeArrayField json "fixtures"
  let fixtures ← fixtureItems.mapM (decodeFixture stages)
  let ids := fixtures.toList.map fun fixture => fixture.id
  if ids.eraseDups.length != ids.length then
    throw "duplicate fixture id"
  for fixture in fixtures do
    for branch in fixture.branches do
      if !branches.contains branch then
        throw s!"fixture {fixture.id}: unknown branch {branch}"
  return { schema, profile, status, stages, branches, fixtures }

structure WrappedDeclaration where
  kind : String
  names : Array String
  arity : Option Nat
  deriving Repr, BEq

structure SummaryDeclaration where
  module : String
  kind : String
  names : Option (Array String)
  arity : Option Nat
  proof : Option String
  wraps : Option WrappedDeclaration
  line : Nat
  deriving Repr, BEq

structure SummarySubstitution where
  formal : String
  formalArity : Nat
  renderedActual : Option String
  deriving Repr, BEq

structure SummaryDependency where
  owner : String
  module : String
  kind : String
  «local» : Bool
  line : Nat
  substitutions : Array SummarySubstitution
  deriving Repr, BEq

structure Summary where
  schema : String
  fixture : String
  root : String
  profile : String
  modules : Array String
  declarations : Array SummaryDeclaration
  dependencies : Array SummaryDependency
  renderings : Array (String × String)
  deriving Repr, BEq

def decodeWrapped (json : Json) : Except String WrappedDeclaration := do
  let kind ← decodeStringField json "kind"
  if kind != "operator" && kind != "recursive" then
    throw s!"summary: unsupported wrapped kind {kind}"
  let names ← decodeStringArrayField json "names"
  let arity ← decodeOptionalNat json "arity"
  return { kind, names, arity }

def decodeSummaryDeclaration (json : Json) : Except String SummaryDeclaration := do
  let module ← decodeStringField json "module"
  let kind ← decodeStringField json "kind"
  if !declarationKinds.contains kind then
    throw s!"summary: unknown declaration kind {kind}"
  let line ← decodeNatField json "line"
  if line == 0 then
    throw "summary: declaration line 0"
  let names ← decodeOptionalStringArray json "names"
  let arity ← decodeOptionalNat json "arity"
  let proof ← decodeOptionalString json "proof"
  let wraps ←
    match json.getObjVal? "wraps" with
    | .ok value => (decodeWrapped value).map some
    | .error _ => .ok none
  if kind == "local" then do
    if names.isSome then
      throw "summary: local declaration carries names"
    if wraps.isNone then
      throw "summary: local declaration has no wrapped declaration"
  else do
    if names.isNone then
      throw s!"summary: {kind} declaration has no names"
    if wraps.isSome then
      throw s!"summary: {kind} declaration carries a wrapped declaration"
  if kind == "operator" || kind == "recursive" then do
    if arity.isNone then
      throw s!"summary: {kind} declaration has no arity"
  else if arity.isSome then
    throw s!"summary: {kind} declaration carries an arity"
  if kind == "theorem" then do
    match proof with
    | none => throw "summary: theorem declaration has no proof treatment"
    | some value =>
        if !proofTreatmentNames.contains value then
          throw s!"summary: unknown proof treatment {value}"
  else if proof.isSome then
    throw s!"summary: {kind} declaration carries a proof treatment"
  return { module, kind, names, arity, proof, wraps, line }

def decodeSummarySubstitution (json : Json) : Except String SummarySubstitution := do
  let formal ← decodeStringField json "formal"
  let formalArity ← decodeNatField json "formalArity"
  let renderedActual ← decodeOptionalString json "actual"
  return { formal, formalArity, renderedActual }

def decodeSummaryDependency (json : Json) : Except String SummaryDependency := do
  let owner ← decodeStringField json "owner"
  let module ← decodeStringField json "module"
  let kind ← decodeStringField json "kind"
  if !dependencyKinds.contains kind then
    throw s!"summary: unknown dependency kind {kind}"
  let isLocal ← decodeBoolField json "local"
  let line ← decodeNatField json "line"
  let substitutionItems ← decodeArrayField json "substitutions"
  let substitutions ← substitutionItems.mapM decodeSummarySubstitution
  return { owner, module, kind, «local» := isLocal, line, substitutions }

def decodeRenderings (json : Json) : Except String (Array (String × String)) :=
  match json.getObjVal? "renderings" with
  | .error _ => .ok #[]
  | .ok value =>
      match value with
      | .obj entries =>
          entries.toList.toArray.mapM fun entry =>
            (Json.getStr? entry.2).map fun rendered => (entry.1, rendered)
      | _ => .error "summary: renderings must be an object"

/-- The parser-owned allowlist of one expected summary: modules, declarations,
dependencies, and renderings. `standardModules`, `effectiveVariables`,
`sources`, `levels`, `annotations`, `resolution`, and every other later-stage
field stay outside this decoder by construction. -/
def decodeSummary (text : String) : Except String Summary := do
  let json ← Json.parse text
  let schema ← decodeStringField json "schema"
  if schema != summarySchema then
    throw s!"unknown summary schema {schema}"
  let fixture ← decodeStringField json "fixture"
  let root ← decodeStringField json "root"
  let profile ← decodeStringField json "profile"
  let modules ← decodeStringArrayField json "modules"
  let declarationItems ← decodeArrayField json "declarations"
  let declarations ← declarationItems.mapM decodeSummaryDeclaration
  let dependencyItems ← decodeArrayField json "dependencies"
  let dependencies ← dependencyItems.mapM decodeSummaryDependency
  let renderings ← decodeRenderings json
  return { schema, fixture, root, profile, modules, declarations, dependencies, renderings }

/-! ### Parser-owned projection -/

def mark (fails : Failures) (message : String) : IO Unit :=
  fails.modify fun items => items ++ [message]

def recordProblems (fails : Failures) (problems : List String) : IO Unit :=
  for problem in problems do
    mark fails problem

/-- Canonical rendering of one operator reference, including its qualifier. -/
def renderOperatorName (reference : OperatorRef) : String :=
  (reference.qualifier.map (fun qualifier => qualifier ++ "!")).getD ""
    ++ reference.spelling

/-- Spellings the renderer writes in infix position. This mirrors the frozen
revision-1 profile; it exists only so parser-owned renderings are comparable. -/
def infixRenderings : List String :=
  ["<=>", "=>", "~>", "/\\", "\\/", "=", "#", "/=", "<", ">", "=<", ">=",
   "\\in", "\\notin", "\\subseteq", "\\subset", "\\supseteq", "\\supset",
   "\\prec", "\\succ", "\\sim", "\\approx", "..", "+", "-", "\\cup", "\\cap",
   "\\oplus", "\\", "*", "/", "\\circ", "\\div", "%", "\\o", "\\bullet",
   "\\star", "\\bigcirc", "\\X", "^"]

/-- Spellings the renderer writes in prefix position. -/
def prefixRenderings : List String :=
  ["~", "-", "[]", "<>", "ENABLED", "UNCHANGED", "DOMAIN", "SUBSET", "UNION",
   "WF_", "SF_"]

/-- Renderable operands that need no parentheses inside a larger application. -/
def atomicExpression : Expression → Bool
  | .name _ _ => true
  | .boolean _ _ => true
  | .integer _ _ => true
  | .string _ _ => true
  | .tuple _ _ => true
  | .set _ _ => true
  | .record _ _ => true
  | .recordSet _ _ => true
  | .select _ _ _ => true
  | .functionApply _ _ _ => true
  | .currentValue _ => true
  | _ => false

/-- Escape a decoded string value back to one-line profile spelling. -/
def escapeString (value : String) : String :=
  value.replace "\\" "\\\\" |>.replace "\"" "\\\"" |>.replace "\n" "\\n"
    |>.replace "\t" "\\t" |>.replace "\r" "\\r"
    |>.replace "\x0c" "\\f"

mutual
  /-- Canonical prefix rendering of one expression: operator applications nest
  with parenthesized compound operands. -/
  partial def renderExpression (expression : Expression) : String :=
    match expression with
    | .name reference _ => renderOperatorName reference
    | .boolean value _ => if value then "TRUE" else "FALSE"
    | .integer value _ => toString value
    | .string value _ => "\"" ++ escapeString value ++ "\""
    | .tuple items _ => "<<" ++ renderItemList items.toList ++ ">>"
    | .set items _ => "{" ++ renderItemList items.toList ++ "}"
    | .record fields _ => "[" ++ renderFieldList fields.toList ++ "]"
    | .recordSet fields _ => "[" ++ renderRecordSetFieldList fields.toList ++ "]"
    | .function bounds body _ =>
        "[" ++ renderBoundList bounds.toList ++ " |-> "
          ++ renderExpression body ++ "]"
    | .functionSet domain codomain _ =>
        "[" ++ renderExpression domain ++ " -> "
          ++ renderExpression codomain ++ "]"
    | .apply operator arguments _ => renderApplication operator arguments
    | .functionApply func index _ =>
        renderOperand func ++ "[" ++ renderExpression index ++ "]"
    | .select base field _ => renderOperand base ++ "." ++ field
    | .ifThenElse condition thenBranch elseBranch _ =>
        "IF " ++ renderExpression condition ++ " THEN "
          ++ renderExpression thenBranch ++ " ELSE "
          ++ renderExpression elseBranch
    | .case arms _ => "CASE " ++ renderArmList arms.toList
    | .letIn definitions body _ =>
        "LET " ++ renderDefinitionList definitions.toList ++ " IN "
          ++ renderExpression body
    | .choose bounds body _ =>
        "CHOOSE " ++ renderBoundList bounds.toList ++ " : "
          ++ renderExpression body
    | .quantifier kind bounds body _ =>
        (match kind with
          | .forall => "\\A "
          | .exists => "\\E ")
          ++ renderBoundList bounds.toList ++ " : " ++ renderExpression body
    | .setBuilder element bounds _ =>
        "{" ++ renderExpression element ++ " : "
          ++ renderBoundList bounds.toList ++ "}"
    | .setFilter bounds predicate _ =>
        "{" ++ renderBoundList bounds.toList ++ " : "
          ++ renderExpression predicate ++ "}"
    | .except base specifications _ =>
        "[" ++ renderExpression base ++ " EXCEPT "
          ++ renderSpecList specifications.toList ++ "]"
    | .currentValue _ => "@"

  /-- One operand inside a larger application: compound expressions are wrapped
  so the rendering records the AST shape rather than the source layout. -/
  partial def renderOperand (expression : Expression) : String :=
    if atomicExpression expression then renderExpression expression
    else "(" ++ renderExpression expression ++ ")"

  partial def renderItemList : List Expression → String
    | [] => ""
    | [item] => renderExpression item
    | item :: rest => renderExpression item ++ ", " ++ renderItemList rest

  partial def renderFieldList : List RecordField → String
    | [] => ""
    | [field] => field.name ++ " |-> " ++ renderExpression field.value
    | field :: rest =>
        field.name ++ " |-> " ++ renderExpression field.value ++ ", "
          ++ renderFieldList rest

  partial def renderRecordSetFieldList : List RecordField → String
    | [] => ""
    | [field] => field.name ++ ": " ++ renderExpression field.value
    | field :: rest =>
        field.name ++ ": " ++ renderExpression field.value ++ ", "
          ++ renderRecordSetFieldList rest

  partial def renderBoundList : List Bound → String
    | [] => ""
    | [bound] => renderBound bound
    | bound :: rest => renderBound bound ++ ", " ++ renderBoundList rest

  partial def renderBound (bound : Bound) : String :=
    match bound.domain with
    | none => bound.name
    | some domain => bound.name ++ " \\in " ++ renderExpression domain

  partial def renderArmList : List CaseArm → String
    | [] => ""
    | [arm] => renderArm arm
    | arm :: rest => renderArm arm ++ " [] " ++ renderArmList rest

  partial def renderArm (arm : CaseArm) : String :=
    match arm.guard with
    | none => "OTHER -> " ++ renderExpression arm.value
    | some guard => renderExpression guard ++ " -> " ++ renderExpression arm.value

  partial def renderDefinitionList : List OperatorDefinition → String
    | [] => ""
    | [definition] => renderDefinition definition
    | definition :: rest =>
        renderDefinition definition ++ " " ++ renderDefinitionList rest

  partial def renderDefinition (definition : OperatorDefinition) : String :=
    match definition.fixity, definition.parameters.toList with
    | .infix, left :: right :: _ =>
        left.name ++ " " ++ definition.name ++ " " ++ right.name
    | .postfix, operand :: _ => operand.name ++ " " ++ definition.name
    | .prefix, operand :: _ => definition.name ++ " " ++ operand.name
    | _, parameters =>
        definition.name ++ "(" ++ renderParameterList parameters ++ ")"

  partial def renderParameterList : List OperatorParameter → String
    | [] => ""
    | [parameter] => parameter.name
    | parameter :: rest =>
        parameter.name ++ ", " ++ renderParameterList rest

  partial def renderSpecList : List ExceptSpec → String
    | [] => ""
    | [specification] => renderSpec specification
    | specification :: rest =>
        renderSpec specification ++ ", " ++ renderSpecList rest

  partial def renderSpec (specification : ExceptSpec) : String :=
    "!" ++ renderPathList specification.path.toList ++ " = "
      ++ renderExpression specification.value

  partial def renderPathList : List ExceptPathElement → String
    | [] => ""
    | [element] => renderPathElement element
    | element :: rest => renderPathElement element ++ renderPathList rest

  partial def renderPathElement : ExceptPathElement → String
    | .field name _ => "." ++ name
    | .index index _ => "[" ++ renderExpression index ++ "]"

  partial def renderApplication (operator : OperatorRef)
      (arguments : Array Expression) : String :=
    let name := renderOperatorName operator
    let functional := name ++ "(" ++ renderItemList arguments.toList ++ ")"
    match arguments.toList with
    | [first, second] =>
        if infixRenderings.contains operator.spelling then
          renderOperand first ++ " " ++ name ++ " " ++ renderOperand second
        else functional
    | [operand] =>
        if prefixRenderings.contains operator.spelling then
          name ++ " " ++ renderOperand operand
        else if operator.spelling == "'" then
          renderExpression operand ++ "'"
        else functional
    | _ => functional

end

/-! ### Structural rows -/

def summaryRow (module : String) (range : SourceRange) (kind : String)
    (names : Option (Array String)) (arity : Option Nat) (proof : Option String)
    (wraps : Option WrappedDeclaration) : SummaryDeclaration :=
  { module, kind, names, arity, proof, wraps, line := range.start.line }

def optionalNames (name : Option String) : Option (Array String) :=
  some (name.map (fun value => #[value]) |>.getD #[])

def proofTreatmentName (declaration : Theorem) : String :=
  match declaration.proof with
  | none => "none"
  | some region =>
      match region.treatment with
      | .omitted => "omitted"
      | .opaque => "opaque"

/-- The `wraps` record of a `LOCAL` declaration: `LOCAL` wraps an operator or a
recursive declaration in the revision-1 surface. -/
def wrappedOfDeclaration (declaration : Declaration) : Option WrappedDeclaration :=
  match declaration with
  | .operator definition =>
      some { kind := "operator", names := #[definition.name]
             arity := some definition.parameters.size }
  | .recursive _ operators =>
      some { kind := "recursive"
             names := operators.map (fun operator => operator.name)
             arity := operators[0]?.map (fun operator => operator.arity) }
  | _ => none

/-- Parser-owned structural rows of one declaration, in source order. `EXTENDS`
contributes dependencies, not declaration rows; a `RECURSIVE` statement
contributes one row per declared operator. -/
def rowsOfDeclaration (module : String) (declaration : Declaration) :
    Array SummaryDeclaration :=
  match declaration with
  | .extends _ => #[]
  | .constant range names =>
      #[summaryRow module range "constant"
          (some (names.map (fun name => name.name))) none none none]
  | .variable range names =>
      #[summaryRow module range "variable"
          (some (names.map (fun name => name.name))) none none none]
  | .recursive range operators =>
      operators.map fun operator =>
        summaryRow module range "recursive" (some #[operator.name])
          (some operator.arity) none none
  | .operator definition =>
      #[summaryRow module definition.range "operator" (some #[definition.name])
          (some definition.parameters.size) none none]
  | .«local» range inner =>
      match wrappedOfDeclaration inner with
      | none => #[summaryRow module range "local" none none none none]
      | some wraps =>
          #[summaryRow module range "local" none none none (some wraps)]
  | .«instance» declaration =>
      #[summaryRow module declaration.range "instance"
          (optionalNames declaration.name) none none none]
  | .assumption declaration =>
      let kind :=
        match declaration.kind with
        | .assume => "assumption"
        | .assumption => "assumption"
        | .«axiom» => "axiom"
      #[summaryRow module declaration.range kind (some #[]) none none none]
  | .«theorem» declaration =>
      #[summaryRow module declaration.range "theorem"
          (optionalNames declaration.name) none
          (some (proofTreatmentName declaration)) none]

def declarationRows (module : String) (parsed : ParsedModule) :
    Array SummaryDeclaration :=
  parsed.declarations.foldl
    (fun rows declaration => rows ++ rowsOfDeclaration module declaration) #[]

def substitutionRow (substitution : Substitution) : SummarySubstitution :=
  { formal := substitution.formal
    formalArity := substitution.formalArity
    renderedActual := some (renderExpression substitution.actual) }

def dependencyRow (owner : String) (dependency : DependencyDeclaration) :
    SummaryDependency :=
  { owner, module := dependency.moduleName.name,
    kind := dependency.kind.toString, «local» := dependency.«local»,
    line := dependency.range.start.line,
    substitutions := dependency.substitutions.map substitutionRow }

def dependencyRows (owner : String) (parsed : ParsedModule) :
    Array SummaryDependency :=
  parsed.dependencies.map (dependencyRow owner)

/-! ### Captures, staged outcomes, and bundles -/

inductive Staged where
  | lexRejected (source : SourceUnit) (diagnostics : Array Diagnostic)
  | parseRejected (source : SourceUnit) (stream : TokenStream)
      (outcome : ParseOutcome)
  | parsed (source : SourceUnit) (stream : TokenStream) (outcome : ParseOutcome)

inductive LoadedFile where
  | failed (message : String)
  | staged (value : Staged)

structure LoadedSource where
  file : String
  logicalName : String
  source : SourceUnit
  stream : TokenStream
  outcome : ParseOutcome

def baseName (path : String) : String :=
  match (path.splitOn "/").reverse with
  | head :: _ => head
  | [] => path

def streamTriviaCount (stream : TokenStream) : Nat :=
  stream.tokens.foldl
    (fun total token => total + token.leadingTrivia.size + token.trailingTrivia.size) 0

def diagnosticCodeList (diagnostics : Array Diagnostic) : List String :=
  diagnostics.toList.map (fun diagnostic => diagnostic.code)

/-- Capture one corpus text the way its provider declares it: a borrowed
directory keeps the physical basename, a closed inline map supplies the
logical name. -/
def stagedOfTexts (fixture : Fixture) (texts : Array (String × String)) :
    Array (String × LoadedFile) :=
  texts.map fun entry =>
    let file := entry.1
    let logicalName :=
      match fixture.inlineSourceMap.toList.find?
          (fun source => source.file == file) with
      | some source => source.logicalName
      | none => baseName file
    let origin :=
      if fixture.provider == "inline-source-map" then
        SourceOrigin.inlineSourceMap
      else
        SourceOrigin.borrowedDirectory
    let source := SourceUnit.create origin logicalName entry.2
    let loaded :=
      match lex LanguageProfile.default {} source with
      | .error diagnostics => .staged (.lexRejected source diagnostics.toArray)
      | .ok stream =>
          let outcome :=
            parseStream LanguageProfile.default ParserProfile.default {} source stream
          if outcome.succeeded then
            .staged (.parsed source stream outcome)
          else
            .staged (.parseRejected source stream outcome)
    (file, loaded)

/-- Corpus-mandated CST evidence for one accepted capture. -/
def cstProblems (label : String) (source : SourceUnit) (stream : TokenStream)
    (outcome : ParseOutcome) : List String :=
  let repeated? :=
    match lex LanguageProfile.default {} source with
    | .ok repeatedStream =>
        some (parseStream LanguageProfile.default ParserProfile.default {}
          source repeatedStream)
    | .error _ => none
  let checks : List (String × Bool) := [
    ("reproduces the token stream", outcome.cst.losslessAgainst stream),
    ("reproduces the captured text", outcome.cst.text == source.normalizedText),
    ("keeps every token leaf in order",
      outcome.cst.root.leafTokens == stream.tokens.toList),
    ("keeps every trivia item", outcome.cst.triviaCount == streamTriviaCount stream),
    ("covers the whole capture", outcome.cst.coversSource source),
    ("has nested ordered ranges", outcome.cst.rangesNested),
    ("repeats identically", repeated? == some outcome)]
  checks.filterMap fun entry =>
    if entry.2 then none else some s!"{label}: CST check failed: {entry.1}"

def expectedLexCode? (fixtureId : String) : Option String :=
  (List.lookup fixtureId [
    -- The frozen profile ends an open string literal at the line break, so an
    -- unterminated spelling reports the newline code before end of input.
    ("rej-unterminated-string", LexCode.newlineInString),
    ("rej-newline-in-string", LexCode.newlineInString),
    ("rej-open-comment", LexCode.unterminatedComment),
    ("rej-comment-depth", LexCode.commentNesting),
    ("rej-identifier-size", LexCode.identifierTooLarge),
    ("rej-control-character", LexCode.controlCharacter),
    ("rej-unicode-spelling", LexCode.unicodeStaged),
    ("rej-real-literal", LexCode.invalidNumber)]).map id

def expectedParseCode? (fixtureId : String) : Option String :=
  (List.lookup fixtureId [
    ("rej-no-terminator", ParseCode.moduleEnd),
    ("rej-keyword-identifier", ParseCode.expectedIdentifier),
    ("rej-multiple-errors", ParseCode.expectedToken),
    ("rej-pluscal", ParseCode.pluscal),
    ("rej-precedence-mix", ParseCode.precedenceConflict),
    ("rej-precedence-chain", ParseCode.precedenceConflict)]).map id

/-- Drive one manifest fixture to its declared stage behavior. Unknown stage or
outcome combinations fail instead of being silently skipped. -/
def classificationProblems (fixture : Fixture)
    (files : Array (String × LoadedFile)) : List String :=
  let readProblems := files.toList.filterMap fun entry =>
    match entry.2 with
    | .failed message => some s!"{fixture.id}: {entry.1}: {message}"
    | .staged _ => none
  if !readProblems.isEmpty then readProblems
  else
    match fixture.kind with
    | "accepted" =>
        files.toList.flatMap fun entry =>
          match entry.2 with
          | .staged (.parsed source stream outcome) =>
              cstProblems s!"{fixture.id}: {entry.1}" source stream outcome
          | .staged (.lexRejected _ diagnostics) =>
              [s!"{fixture.id}: {entry.1}: accepted fixture failed at lex ({String.intercalate ", " (diagnosticCodeList diagnostics)})"]
          | .staged (.parseRejected _ _ outcome) =>
              [s!"{fixture.id}: {entry.1}: accepted fixture failed at parse ({outcomeDetail outcome})"]
          | .failed message => [s!"{fixture.id}: {entry.1}: {message}"]
    | "rejected" =>
        match fixture.stage with
        | "lex" =>
            match expectedLexCode? fixture.id with
            | none => [s!"{fixture.id}: lex-stage fixture has no expected code"]
            | some code =>
                let codes := files.toList.flatMap fun entry =>
                  match entry.2 with
                  | .staged (.lexRejected _ diagnostics) =>
                      diagnosticCodeList diagnostics
                  | _ => []
                let early := files.toList.filterMap fun entry =>
                  match entry.2 with
                  | .staged (.parseRejected _ _ outcome) =>
                      some s!"{fixture.id}: {entry.1}: lex-stage fixture reached parse ({outcomeDetail outcome})"
                  | _ => none
                (if codes.contains code then []
                  else [s!"{fixture.id}: expected lex code {code}, recorded {String.intercalate ", " codes}"])
                  ++ early
        | "parse" =>
            match expectedParseCode? fixture.id with
            | none => [s!"{fixture.id}: parse-stage fixture has no expected code"]
            | some code =>
                let failures := files.toList.filterMap fun entry =>
                  match entry.2 with
                  | .staged (.parseRejected source stream outcome) =>
                      some (entry.1, source, stream, outcome)
                  | _ => none
                let reported := failures.flatMap fun failure =>
                  let label := s!"{fixture.id}: {failure.1}"
                  if failure.2.2.2.module?.isSome then
                    [s!"{label}: parse-stage failure exposed a module"]
                  else if !failure.2.2.2.hasErrors then
                    [s!"{label}: parse-stage failure carried no error"]
                  else if !hasCode failure.2.2.2 code then
                    [s!"{label}: expected parse code {code}, recorded {outcomeCodes failure.2.2.2}"]
                  else
                    cstProblems label failure.2.1 failure.2.2.1 failure.2.2.2
                let lexEarly := files.toList.filterMap fun entry =>
                  match entry.2 with
                  | .staged (.lexRejected _ _) =>
                      some s!"{fixture.id}: {entry.1}: parse-stage fixture failed at lex"
                  | _ => none
                let minimum :=
                  match fixture.minDiagnostics with
                  | none => []
                  | some expected =>
                      if failures.any
                          (fun failure => failure.2.2.2.diagnostics.size ≥ expected) then
                        []
                      else
                        [s!"{fixture.id}: expected at least {expected} diagnostics"]
                if failures.isEmpty then
                  [s!"{fixture.id}: no file failed at parse"]
                else
                  reported ++ lexEarly ++ minimum
        | "moduleGraph" | "nameResolution" | "substitution" | "level" =>
            files.toList.filterMap fun entry =>
              match entry.2 with
              | .staged (.parsed _ _ _) => none
              | .staged (.lexRejected _ diagnostics) =>
                  some s!"{fixture.id}: {entry.1}: later-stage fixture failed at lex ({String.intercalate ", " (diagnosticCodeList diagnostics)})"
              | .staged (.parseRejected _ _ outcome) =>
                  some s!"{fixture.id}: {entry.1}: later-stage fixture was preempted by parse ({outcomeDetail outcome})"
              | .failed message => some s!"{fixture.id}: {entry.1}: {message}"
        | stage =>
            [s!"{fixture.id}: unclassified rejected stage {stage}"]
    | kind => [s!"{fixture.id}: unclassified fixture outcome {kind}"]

structure ParsedBundle where
  root : String
  modules : Array String
  declarations : Array SummaryDeclaration
  dependencies : Array SummaryDependency
  definitions : Array (String × String)

/-- Parser-owned projection of one parsed bundle: module names, declaration and
dependency rows in source order, and the canonical rendering of every root
module operator definition. -/
def bundleOf (fixture : Fixture) (files : Array (String × LoadedFile)) :
    Option ParsedBundle :=
  let parsedFiles := files.toList.mapM fun entry =>
    match entry.2 with
    | .staged (.parsed _ _ outcome) => outcome.module?
    | _ => none
  match parsedFiles with
  | none => none
  | some parsed =>
      let rows := parsed.foldl
        (fun accumulated module => accumulated ++ declarationRows module.name.name module) #[]
      let dependencies := parsed.foldl
        (fun accumulated module => accumulated ++ dependencyRows module.name.name module) #[]
      let definitions :=
        match parsed.find? (fun module => module.name.name == fixture.root) with
        | none => #[]
        | some rootModule =>
            rootModule.declarations.filterMap fun declaration =>
              match declaration with
              | .operator definition =>
                  some (definition.name, renderExpression definition.body)
              | _ => none
      some { root := fixture.root
             modules := parsed.toArray.map (fun module => module.name.name)
             declarations := rows
             dependencies
             definitions }

def sameStringSet (expected actual : Array String) : Bool :=
  expected.size == actual.size && expected.all (fun item => actual.contains item)

def substitutionMatches (expected : Array SummarySubstitution)
    (actual : Array SummarySubstitution) : Bool :=
  expected.size == actual.size &&
    (expected.toList.zip actual.toList).all fun pair =>
      pair.1.formal == pair.2.formal && pair.1.formalArity == pair.2.formalArity &&
        match pair.1.renderedActual with
        | none => true
        | some rendered => some rendered == pair.2.renderedActual

def declarationProblems (fixture : Fixture) (bundle : ParsedBundle)
    (summary : Summary) : List String :=
  let expected := summary.declarations
  let actual := bundle.declarations
  if expected.size != actual.size then
    [s!"{fixture.id}: declarations: expected {expected.size} rows, parser recorded {actual.size}: expected {repr expected}, parser recorded {repr actual}"]
  else
    (expected.toList.zip actual.toList).filterMap fun pair =>
      if pair.1 == pair.2 then none
      else
        some s!"{fixture.id}: declaration mismatch: expected {repr pair.1}, parser recorded {repr pair.2}"

def dependencyProblems (fixture : Fixture) (bundle : ParsedBundle)
    (summary : Summary) : List String :=
  let expected := summary.dependencies
  let actual := bundle.dependencies
  if expected.size != actual.size then
    [s!"{fixture.id}: dependencies: expected {expected.size} rows, parser recorded {actual.size}: expected {repr expected}, parser recorded {repr actual}"]
  else
    (expected.toList.zip actual.toList).filterMap fun pair =>
      let want := pair.1
      let got := pair.2
      if want.owner == got.owner && want.module == got.module
          && want.kind == got.kind && want.«local» == got.«local»
          && want.line == got.line
          && substitutionMatches want.substitutions got.substitutions then
        none
      else
        some s!"{fixture.id}: dependency mismatch: expected {repr want}, parser recorded {repr got}"

def renderingProblems (fixture : Fixture) (bundle : ParsedBundle)
    (summary : Summary) : List String :=
  summary.renderings.toList.filterMap fun entry =>
    match bundle.definitions.toList.find? (fun definition => definition.1 == entry.1) with
    | none =>
        some s!"{fixture.id}: rendering {entry.1}: no operator definition in {fixture.root}"
    | some definition =>
        if definition.2 == entry.2 then none
        else
          some s!"{fixture.id}: rendering {entry.1}: expected {entry.2}, parser rendered {definition.2}"

/-- Parser-owned comparison of one accepted fixture against its expected
summary. Later-stage summary fields are outside the decoder by construction. -/
def summaryProblems (fixture : Fixture) (bundle : ParsedBundle)
    (summary : Summary) : List String :=
  let checks : List (String × Bool) := [
    ("summary schema", summary.schema == summarySchema),
    ("summary fixture id", summary.fixture == fixture.id),
    ("summary root module", summary.root == fixture.root),
    ("summary profile", summary.profile == ParserProfile.default.name),
    ("module set", sameStringSet summary.modules bundle.modules),
    ("unique module names",
      bundle.modules.toList.eraseDups.length == bundle.modules.size),
    ("root module present", bundle.modules.contains fixture.root)]
  let header := checks.filterMap fun entry =>
    if entry.2 then none else some s!"{fixture.id}: {entry.1} mismatch"
  header ++ declarationProblems fixture bundle summary
    ++ dependencyProblems fixture bundle summary
    ++ renderingProblems fixture bundle summary

def pairsOf {α : Type} : List α → List (α × α)
  | [] => []
  | head :: rest => rest.map (fun item => (head, item)) ++ pairsOf rest

/-- ASCII alias groups are compared through the canonical rendering, which
erases layout and spelling while preserving operator identity and arity. -/
def aliasPairProblems (group : String) (first second : Fixture × ParsedBundle) :
    List String :=
  let shared := first.2.definitions.toList.filterMap fun definition =>
    match second.2.definitions.toList.find?
        (fun other => other.1 == definition.1) with
    | none => none
    | some other => some (definition.1, definition.2, other.2)
  if shared.length < 2 then
    [s!"alias group {group}: {first.1.id} and {second.1.id} share fewer than two operator names"]
  else
    shared.filterMap fun entry =>
      if entry.2.1 == entry.2.2 then none
      else
        s!"alias group {group}: {entry.1} differs between {first.1.id} and {second.1.id}"

/-! ### Corpus driver -/

def readCorpusText (root relative : String) : IO (Except String String) := do
  let path := System.FilePath.mk (root ++ "/" ++ relative)
  if ← path.pathExists then
    try
      return .ok (← IO.FS.readFile path)
    catch error =>
      return .error s!"{relative}: {toString error}"
  else
    return .error s!"{relative}: missing corpus file"

def readFixtureTexts (root : String) (fixture : Fixture) :
    IO (Array (String × String) × List String) := do
  let mut texts : Array (String × String) := #[]
  let mut problems : List String := []
  for file in fixture.files do
    match ← readCorpusText root file with
    | .ok text => texts := texts.push (file, text)
    | .error message => problems := problems ++ [s!"{fixture.id}: {message}"]
  return (texts, problems)

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

def runCorpus (fails : Failures) (root : String) (manifest : Manifest) :
    IO Unit := do
  let acceptedRef ← IO.mkRef (0 : Nat)
  let rejectedRef ← IO.mkRef (0 : Nat)
  let firstAccepted ← IO.mkRef (none : Option (Fixture × ParsedBundle × Summary × Array (String × LoadedFile)))
  let firstRendering ← IO.mkRef (none : Option (Fixture × ParsedBundle × Summary))
  let firstParseRejected ← IO.mkRef (none : Option (Fixture × Array (String × LoadedFile)))
  let firstLexRejected ← IO.mkRef (none : Option (Fixture × Array (String × LoadedFile)))
  let aliasMembers ← IO.mkRef ([] : List (String × Fixture × ParsedBundle))
  check fails "corpus: the manifest selects the frozen profile"
    (manifest.profile == ParserProfile.default.name) manifest.profile
  let fixtureStages := manifest.fixtures.toList.map (fun fixture => fixture.stage)
  for stage in manifest.stages do
    check fails s!"corpus: stage {stage} has a fixture"
      (fixtureStages.contains stage) ""
  for fixture in manifest.fixtures do
    let (texts, readProblems) ← readFixtureTexts root fixture
    recordProblems fails readProblems
    let files := stagedOfTexts fixture texts
    recordProblems fails (classificationProblems fixture files)
    if fixture.kind == "accepted" then
      acceptedRef.modify (· + 1)
      if (← firstLexRejected.get).isNone then
        match files.toList.find? (fun entry =>
            match entry.2 with
            | .staged (.lexRejected _ _) => true
            | _ => false) with
        | some _ => firstLexRejected.set (some (fixture, files))
        | none => pure ()
      match bundleOf fixture files with
      | none => pure ()
      | some bundle => do
          match fixture.summary with
          | none => pure ()
          | some summaryPath =>
              match ← readCorpusText root summaryPath with
              | .error message => mark fails s!"{fixture.id}: summary {message}"
              | .ok summaryText =>
                  match decodeSummary summaryText with
                  | .error message => mark fails s!"{fixture.id}: summary {message}"
                  | .ok summary => do
                      recordProblems fails (summaryProblems fixture bundle summary)
                      if (← firstAccepted.get).isNone then
                        firstAccepted.set (some (fixture, bundle, summary, files))
                      if !summary.renderings.isEmpty &&
                          (← firstRendering.get).isNone then
                        firstRendering.set (some (fixture, bundle, summary))
                      match fixture.equivalenceGroup with
                      | some group =>
                          aliasMembers.modify (· ++ [(group, fixture, bundle)])
                      | none => pure ()
    else
      rejectedRef.modify (· + 1)
      if fixture.stage == "parse" && (← firstParseRejected.get).isNone then
        firstParseRejected.set (some (fixture, files))
      if fixture.stage == "lex" && (← firstLexRejected.get).isNone then
        firstLexRejected.set (some (fixture, files))
  -- Alias-equivalence groups from the manifest must actually be exercised.
  let members ← aliasMembers.get
  for group in members.map (fun entry => entry.1) |>.eraseDups do
    let groupMembers := members.filter (fun entry => entry.1 == group)
    check fails s!"alias group {group}: at least two parsed members"
      (groupMembers.length ≥ 2) ""
    for pair in pairsOf groupMembers do
      recordProblems fails
        (aliasPairProblems group (pair.1.2.1, pair.1.2.2) (pair.2.2.1, pair.2.2.2))
  -- Negative self-tests: mutated expectations and misclassified fixtures must
  -- be detected by the same checkers that drive the live corpus.
  match ← firstAccepted.get with
  | none => mark fails "corpus: no accepted fixture produced a parsed bundle"
  | some (fixture, bundle, summary, files) => do
      check fails "corpus mutation: a dropped declaration row is detected"
        (!summary.declarations.isEmpty &&
          !(summaryProblems fixture bundle
              { summary with declarations := summary.declarations.pop }).isEmpty)
        ""
      match summary.declarations.toList with
      | [] => pure ()
      | head :: _ =>
          check fails "corpus mutation: a shifted declaration line is detected"
            (!(summaryProblems fixture bundle
                { summary with declarations :=
                    (summary.declarations.set! 0 { head with line := head.line + 1 }) }).isEmpty)
            ""
      match summary.dependencies.toList with
      | [] => pure ()
      | head :: _ => do
          check fails "corpus mutation: a renamed dependency is detected"
            (!(summaryProblems fixture bundle
                { summary with dependencies :=
                    (summary.dependencies.set! 0 { head with module := "Mutated" }) }).isEmpty)
            ""
          check fails "corpus mutation: a flipped dependency locality is detected"
            (!(summaryProblems fixture bundle
                { summary with dependencies :=
                    (summary.dependencies.set! 0
                      { head with «local» := !head.«local» }) }).isEmpty)
            ""
      let rejectedView :=
        { fixture with kind := "rejected", stage := "lex", reason := some "malformed" }
      check fails "corpus mutation: an accepted bundle is not a lex failure"
        (!(classificationProblems rejectedView files).isEmpty) ""
  match ← firstRendering.get with
  | none => mark fails "corpus: no accepted fixture carried parser renderings"
  | some (fixture, bundle, summary) =>
      match summary.renderings.toList with
      | [] => mark fails "corpus: the rendering baseline has no entries"
      | head :: _ => do
          check fails "corpus mutation: a corrupted rendering is detected"
            (!(summaryProblems fixture bundle
                { summary with renderings :=
                    (summary.renderings.set! 0 (head.1, "Mutated Rendering")) }).isEmpty)
            ""
          check fails "corpus mutation: a renamed rendering key is detected"
            (!(summaryProblems fixture bundle
                { summary with renderings :=
                    (summary.renderings.set! 0 ("MutatedRendering", head.2)) }).isEmpty)
            ""
  match ← firstParseRejected.get with
  | none => mark fails "corpus: no parse-stage rejection was examined"
  | some (fixture, files) =>
      check fails "corpus mutation: a parse-stage rejection is not accepted"
        (!(classificationProblems
            { fixture with kind := "accepted", reason := none } files).isEmpty)
        ""
  match ← firstLexRejected.get with
  | none => mark fails "corpus: no lex-stage rejection was examined"
  | some (fixture, files) =>
      check fails "corpus mutation: a lex-stage rejection is not accepted"
        (!(classificationProblems
            { fixture with kind := "accepted", reason := none } files).isEmpty)
        ""
  let links := manifest.fixtures.foldl
    (fun accumulated fixture => accumulated ++ fixture.branches.toList) #[]
  for branch in manifest.branches do
    check fails s!"corpus: branch {branch} is referenced by a fixture"
      (links.contains branch) ""
  check fails "corpus: every fixture is counted once"
    ((← acceptedRef.get) + (← rejectedRef.get) == manifest.fixtures.size) ""
  let acceptedCount ← acceptedRef.get
  let rejectedCount ← rejectedRef.get
  IO.println s!"TLA PARSER CORPUS: {manifest.fixtures.size} fixtures ({acceptedCount} accepted, {rejectedCount} rejected), {manifest.branches.size} branches, {links.size} fixture-branch links"

/-- The durable TF2D tier: locate the corpus, decode it strictly, and drive
every fixture to its declared stage behavior. -/
def scenarioCorpus (fails : Failures) : IO Unit := do
  match ← corpusRoot? "." with
  | none =>
      mark fails "corpus: test/fixtures/tla-frontend/manifest.json not found"
  | some root => do
      let rootText := root.toString
      match ← readCorpusText rootText "manifest.json" with
      | .error message => mark fails s!"corpus manifest: {message}"
      | .ok text =>
          match decodeManifest text with
          | .error message => mark fails s!"corpus manifest: {message}"
          | .ok manifest => runCorpus fails rootText manifest

/-! ### Generated adversarial families -/

def declarationListBody (count : Nat) : String :=
  String.intercalate "\n" ((List.range count).map fun index => s!"x{index} == {index}")

def malformedDeclarationLines (count : Nat) : String :=
  String.intercalate "\n"
    ((List.range count).map fun index => s!"x{index} == )")

def checkClosedFailure (fails : Failures) (name : String) (limits : ParserLimits)
    (body : String) (code : String) : IO Unit := do
  match parseBody? limits body with
  | none => check fails s!"{name}: the capture lexes" false ""
  | some outcome =>
      check fails s!"{name}: fails closed with {code}"
        (!outcome.succeeded && outcome.module?.isNone && closed outcome &&
          hasCode outcome code) (outcomeDetail outcome)

def checkRecoveredFailure (fails : Failures) (name : String) (body : String) : IO Unit := do
  match detailed? {} body with
  | none => check fails s!"{name}: the capture lexes" false ""
  | some (source, stream, outcome) => do
      check fails s!"{name}: fails closed"
        (!outcome.succeeded && outcome.module?.isNone && closed outcome)
        (outcomeDetail outcome)
      check fails s!"{name}: recovery stays lossless"
        (outcome.cst.losslessAgainst stream &&
          outcome.cst.text == source.normalizedText &&
          outcome.cst.rangesNested)
        (outcomeDetail outcome)
      check fails s!"{name}: repeats identically"
        (parseBody? {} body == some outcome) (outcomeDetail outcome)

def checkStreamFailure (fails : Failures) (name : String) (source : SourceUnit)
    (stream : TokenStream) (code : String) : IO Unit := do
  let outcome :=
    parseStream LanguageProfile.default ParserProfile.default {} source stream
  check fails s!"{name}: fails closed with {code}"
    (!outcome.succeeded && outcome.module?.isNone && closed outcome &&
      hasCode outcome code) (outcomeDetail outcome)
  check fails s!"{name}: repeats identically"
    (parseStream LanguageProfile.default ParserProfile.default {} source stream
      == outcome) ""

def scenarioCorpusAdversarial (fails : Failures) : IO Unit := do
  -- Deep recursive syntax: every TF2A family still terminates near its bound.
  for (name, builder) in families do
    checkAccepted fails s!"adversarial: {name} of depth 48 parses at limit 48"
      { maxNestingDepth := 48 } (builder 48)
    checkNestingRejected fails
      s!"adversarial: {name} of depth 49 is rejected at limit 48"
      { maxNestingDepth := 48 } (builder 49)
  -- Long declaration lists at the exact count limit and at the default.
  checkAccepted fails "adversarial: 512 declarations parse at the exact limit"
    { maxDeclarations := 512 } (declarationListBody 512)
  checkClosedFailure fails "adversarial: 513 declarations exceed the exact limit"
    { maxDeclarations := 512 } (declarationListBody 513) ParseCode.declarationLimit
  checkAccepted fails "adversarial: 4096 declarations parse at the default limit"
    {} (declarationListBody 4096)
  checkClosedFailure fails "adversarial: 4097 declarations exceed the default limit"
    {} (declarationListBody 4097) ParseCode.declarationLimit
  -- Diagnostic count and byte budgets exhaust into one closed notice.
  let malformed := malformedDeclarationLines 32
  match parseBody? { maxDiagnostics := 4 } malformed with
  | none => check fails "adversarial: the diagnostic-count capture lexes" false ""
  | some outcome =>
      check fails "adversarial: a four-diagnostic budget truncates and fails closed"
        (outcome.module?.isNone && closed outcome &&
          hasCode outcome ParseCode.diagnosticsTruncated && droppedOf outcome > 0)
        (outcomeDetail outcome)
  match parseBody? { maxDiagnosticBytes := 1 } malformed with
  | none => check fails "adversarial: the diagnostic-byte capture lexes" false ""
  | some outcome =>
      check fails "adversarial: a one-byte diagnostic budget truncates and fails closed"
        (outcome.module?.isNone && closed outcome &&
          hasCode outcome ParseCode.diagnosticsTruncated && droppedOf outcome > 0)
        (outcomeDetail outcome)
  -- Malformed delimiters recover losslessly and fail closed.
  for (name, body) in [
      ("unclosed parenthesis", "x == (1"),
      ("unclosed set", "x == {1"),
      ("unclosed tuple", "x == <<1"),
      ("unclosed bracket", "x == f[1"),
      ("unclosed record", "x == [a |-> 1"),
      ("record set missing domain", "CONSTANT S\nx == [a: S, b:]"),
      ("record set missing colon", "CONSTANT S\nx == [a: S, b S]"),
      ("unclosed function", "x == [i \\in S |-> 1"),
      ("unclosed comprehension", "x == { y \\in S : TRUE"),
      ("unterminated IF", "x == IF TRUE THEN 1"),
      ("CASE missing arm value", "x == CASE TRUE ->"),
      ("unclosed EXCEPT", "x == [f EXCEPT ![1] = 1"),
      ("LET missing IN", "x == LET y == 1"),
      ("quantifier missing colon", "x == \\A y \\in S TRUE")] do
    checkRecoveredFailure fails s!"adversarial delimiter: {name}" body
  -- Proof-like declaration text stays opaque inside its region.
  for depth in [2, 3, 4] do
    let body := "THEOREM T == TRUE\n" ++ nestedStepProofText depth
      ++ "\nVARIABLE v\nReal == 4"
    let limit := depth - 1
    checkAccepted fails
      s!"adversarial proof: depth {depth} parses at limit {limit}"
      { maxNestingDepth := limit } body
    checkNestingRejected fails
      s!"adversarial proof: depth {depth} is rejected at limit {limit - 1}"
      { maxNestingDepth := limit - 1 } body
    match parseBody? { maxNestingDepth := limit } body with
    | none => check fails s!"adversarial proof: depth {depth} capture lexes" false ""
    | some outcome => do
        check fails
          s!"adversarial proof: depth {depth} leaks no proof-local declaration"
          (declarationShape outcome ==
            [("theorem", ["T"]), ("variable", ["v"]), ("operator", ["Real"])])
          (outcomeDetail outcome)
        check fails s!"adversarial proof: depth {depth} keeps one proof region"
          (nodeCount .proofRegion outcome.cst.root == 1)
          s!"proofRegion nodes={nodeCount .proofRegion outcome.cst.root}"
  -- Source/stream inconsistencies over three independent captures.
  for (index, body) in
      (List.range 3).zip ["x == 1", "CONSTANT N", "x == f(1)"] do
    match detailed? {} body with
    | none => check fails s!"adversarial stream {index}: the capture lexes" false ""
    | some (source, stream, _) =>
      match stream.tokens.toList with
      | [] => check fails s!"adversarial stream {index}: the capture has tokens" false ""
      | first :: _ => do
        let tampered : TokenStream :=
          { tokens := stream.tokens.set! 0 { first with spelling := first.spelling ++ " " } }
        checkStreamFailure fails s!"adversarial stream {index}: tampered spelling"
          source tampered ParseCode.streamTextMismatch
        let truncated : TokenStream := { tokens := stream.tokens.pop }
        checkStreamFailure fails s!"adversarial stream {index}: missing final eof"
          source truncated ParseCode.streamEof
        let duplicated : TokenStream :=
          { tokens := (stream.tokens.pop.push (eofCopy stream)).push (eofCopy stream) }
        checkStreamFailure fails s!"adversarial stream {index}: duplicated eof"
          source duplicated ParseCode.streamEof
        let displaced : TokenStream :=
          { tokens := (stream.tokens.pop.push (eofCopy stream)).push first }
        checkStreamFailure fails s!"adversarial stream {index}: non-final eof"
          source displaced ParseCode.streamEof

end Corpus

def allScenarios (fails : Failures) : IO Unit := do
  scenarioWellFormed fails
  scenarioTruncationOrdering fails
  scenarioNestingFamilies fails
  scenarioNestedCstLosslessness fails
  scenarioRepeatedForms fails
  scenarioNestingRestoration fails
  scenarioStreamValidation fails
  scenarioDeterminism fails
  scenarioProfileOwnership fails
  scenarioPrecedenceShapes fails
  scenarioRecordSets fails
  scenarioQuantifiers fails
  scenarioUserOperators fails
  scenarioStringValues fails
  scenarioProofTerminals fails
  scenarioProofOpacity fails
  scenarioProofFailClosed fails
  scenarioProofByTerminal fails
  Corpus.scenarioCorpus fails
  Corpus.scenarioCorpusAdversarial fails

def failuresOf : IO (List String) := do
  let fails ← IO.mkRef ([] : List String)
  allScenarios fails
  fails.get

def report (items : List String) : IO UInt32 := do
  if items.isEmpty then
    IO.println "TLA PARSER SPEC GREEN"
    return 0
  else
    for item in items do
      IO.eprintln s!"FAIL {item}"
    IO.eprintln s!"{items.length} FAILURES"
    return 1

def run : IO UInt32 := do
  report (← failuresOf)

end TlaParserSpec

def main : IO UInt32 :=
  TlaParserSpec.run

-- The acceptance command `lake env lean tools/TlaParserSpec.lean` only
-- elaborates this file, so run the suite here as well: a failing check makes
-- the command fail instead of compiling unattended assertions.
#eval do
  let code ← TlaParserSpec.run
  if code != 0 then
    throw (IO.userError "TLA parser specification failed")
