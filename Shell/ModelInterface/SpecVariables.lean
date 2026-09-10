/-!
# Bounded TLA+ variable declaration scanning

This is a conservative lexical scanner for top-level `VARIABLE` and
`VARIABLES` declarations. It is intentionally not a general TLA+ parser. The
scanner removes comments and strings before recognizing declaration lines so
stale trace variable evidence cannot be accepted because declaration-like text
appeared in documentation or a literal.
-/

namespace Shell.ModelInterface.SpecVariables

/-- Resource limits for the pure source scanner. -/
structure Limits where
  maxSourceBytes : Nat := 4 * 1024 * 1024
  maxDeclarations : Nat := 4096
  maxIdentifierBytes : Nat := 256
  maxCommentDepth : Nat := 64
  deriving Repr, BEq

def defaultLimits : Limits := {}

private inductive ScanMode where
  | code
  | lineComment
  | blockComment (depth : Nat)
  | stringLiteral

private partial def codeOnlyChars (limits : Limits) (remaining : List Char)
    (mode : ScanMode) (reversed : List Char) : Except String (List Char) := do
  match mode, remaining with
  | .code, [] | .lineComment, [] => return reversed.reverse
  | .blockComment _, [] => throw "unterminated block comment in TLA+ source"
  | .stringLiteral, [] => throw "unterminated string literal in TLA+ source"
  | .code, '\\' :: '*' :: rest =>
      codeOnlyChars limits rest .lineComment (' ' :: ' ' :: reversed)
  | .code, '(' :: '*' :: rest =>
      if limits.maxCommentDepth == 0 then
        throw "TLA+ block comment exceeds depth limit 0"
      codeOnlyChars limits rest (.blockComment 1) (' ' :: ' ' :: reversed)
  | .code, '"' :: rest =>
      codeOnlyChars limits rest .stringLiteral (' ' :: reversed)
  | .code, character :: rest =>
      codeOnlyChars limits rest .code (character :: reversed)
  | .lineComment, '\n' :: rest =>
      codeOnlyChars limits rest .code ('\n' :: reversed)
  | .lineComment, _ :: rest =>
      codeOnlyChars limits rest .lineComment (' ' :: reversed)
  | .blockComment depth, '(' :: '*' :: rest =>
      if depth >= limits.maxCommentDepth then
        throw s!"TLA+ block comment exceeds depth limit {limits.maxCommentDepth}"
      codeOnlyChars limits rest (.blockComment (depth + 1)) (' ' :: ' ' :: reversed)
  | .blockComment depth, '*' :: ')' :: rest =>
      if depth == 1 then
        codeOnlyChars limits rest .code (' ' :: ' ' :: reversed)
      else
        codeOnlyChars limits rest (.blockComment (depth - 1)) (' ' :: ' ' :: reversed)
  | .blockComment depth, '\n' :: rest =>
      codeOnlyChars limits rest (.blockComment depth) ('\n' :: reversed)
  | .blockComment depth, _ :: rest =>
      codeOnlyChars limits rest (.blockComment depth) (' ' :: reversed)
  | .stringLiteral, '\\' :: _ :: rest =>
      codeOnlyChars limits rest .stringLiteral (' ' :: ' ' :: reversed)
  | .stringLiteral, '"' :: rest =>
      codeOnlyChars limits rest .code (' ' :: reversed)
  | .stringLiteral, '\n' :: _ =>
      throw "newline in TLA+ string literal"
  | .stringLiteral, _ :: rest =>
      codeOnlyChars limits rest .stringLiteral (' ' :: reversed)

private def codeOnlySource (source : String) (limits : Limits) : Except String String := do
  if source.toUTF8.size > limits.maxSourceBytes then
    throw s!"TLA+ source exceeds byte limit {limits.maxSourceBytes}"
  return String.ofList (← codeOnlyChars limits source.toList .code [])

private def isIdentifierStart (character : Char) : Bool :=
  character.isAlpha || character == '_'

private def isIdentifierRest (character : Char) : Bool :=
  character.isAlphanum || character == '_'

private def keywordRemainder? (line keyword : String) : Option String :=
  if line == keyword then some ""
  else if line.startsWith (keyword ++ " ") || line.startsWith (keyword ++ "\t") then
    some (line.drop keyword.length |>.toString)
  else none

private structure ParsedLine where
  names : List String
  continues : Bool

private partial def parseDeclarationLine (raw : String) (limits : Limits) :
    Except String ParsedLine := do
  let rec parseIdent (chars : List Char) (reversed : List Char) : String × List Char :=
    match chars with
    | character :: rest =>
        if isIdentifierRest character then parseIdent rest (character :: reversed)
        else (String.ofList reversed.reverse, chars)
    | [] => (String.ofList reversed.reverse, [])
  let rec go (chars : List Char) (names : List String) (expectName : Bool) :
      Except String ParsedLine := do
    let chars := chars.dropWhile (fun character => character == ' ' || character == '\t' || character == '\r')
    match chars with
    | [] =>
        if expectName then return { names, continues := true }
        return { names, continues := false }
    | character :: rest =>
        if !expectName then
          if character == ',' then go rest names true
          else throw s!"malformed TLA+ variable declaration near '{String.ofList chars}'"
        else if isIdentifierStart character then
          let (name, remaining) := parseIdent rest [character]
          if name.toUTF8.size > limits.maxIdentifierBytes then
            throw s!"TLA+ variable name exceeds byte limit {limits.maxIdentifierBytes}"
          go remaining (names ++ [name]) false
        else
          throw s!"malformed TLA+ variable declaration near '{String.ofList chars}'"
  go raw.toList [] true

private def appendNames (limits : Limits) (declared additions : List String) :
    Except String (List String) := do
  let rec go (combined : List String) : List String → Except String (List String)
    | [] => return combined
    | name :: rest =>
        if combined.contains name then
          throw s!"duplicate TLA+ variable declaration '{name}'"
        else
          go (combined ++ [name]) rest
  let combined ← go declared additions
  if combined.length > limits.maxDeclarations then
    throw s!"TLA+ variable declarations exceed count limit {limits.maxDeclarations}"
  return combined

private partial def extractLines (lines : List String) (limits : Limits)
    (continuing : Bool) (declared : List String) : Except String (List String) := do
  match lines with
  | [] =>
      if continuing then throw "incomplete TLA+ variable declaration"
      return declared
  | rawLine :: rest =>
      let line := rawLine.trimAscii.toString
      if continuing then
        if line.isEmpty then
          extractLines rest limits true declared
        else
          let parsed ← parseDeclarationLine line limits
          let declared ← appendNames limits declared parsed.names
          extractLines rest limits parsed.continues declared
      else
        let remainder? :=
          match keywordRemainder? line "VARIABLES" with
          | some remainder => some remainder
          | none => keywordRemainder? line "VARIABLE"
        match remainder? with
        | none => extractLines rest limits false declared
        | some remainder =>
            let parsed ← parseDeclarationLine remainder limits
            let declared ← appendNames limits declared parsed.names
            extractLines rest limits parsed.continues declared

/-- Extract all names from top-level `VARIABLE`/`VARIABLES` declarations in
declaration order. Comments and strings are ignored; malformed declarations and
resource-limit violations are errors. -/
def extract (source : String) (limits : Limits := defaultLimits) :
    Except String (List String) := do
  let code ← codeOnlySource source limits
  extractLines (code.replace "\r\n" "\n" |>.replace "\r" "\n" |>.splitOn "\n")
    limits false []

private def sortedStrings (values : List String) : List String :=
  values.toArray.qsort (fun left right => compare left right == .lt) |>.toList

/-- Require trace/evidence variables to match the variables declared by the
current TLA+ source. The diagnostic names both directions of a stale mismatch. -/
def validateEvidenceVariables (source : String) (evidenceVariables : List String)
    (limits : Limits := defaultLimits) : Except String Unit := do
  let declared ← extract source limits
  if evidenceVariables.length > limits.maxDeclarations then
    throw s!"evidence variables exceed count limit {limits.maxDeclarations}"
  if evidenceVariables.any fun name => name.toUTF8.size > limits.maxIdentifierBytes then
    throw s!"evidence variable name exceeds byte limit {limits.maxIdentifierBytes}"
  let duplicate := evidenceVariables.find? fun name =>
    (evidenceVariables.filter (· == name)).length > 1
  if let some name := duplicate then
    throw s!"duplicate evidence variable '{name}'"
  let sourceOnly := sortedStrings (declared.filter (!evidenceVariables.contains ·))
  let evidenceOnly := sortedStrings (evidenceVariables.filter (!declared.contains ·))
  if sourceOnly.isEmpty && evidenceOnly.isEmpty then return ()
  throw s!"stale variable evidence: source-only={sourceOnly}, evidence-only={evidenceOnly}"

end Shell.ModelInterface.SpecVariables
