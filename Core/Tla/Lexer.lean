import Core.Tla.Source
import Core.Tla.Diagnostic
import Core.Tla.Token

/-!
# TLA+ lexer (Core/Tla/Lexer.lean)

Pure, total-under-limits lexer for the general TLA+ frontend
(`Docs/model-interface-compiler/tla-frontend-design.md`, §9 "Lexer"), pinned to
the revision-1 language profile
(`Docs/model-interface-compiler/tla-language-profile.md`).

`lex` returns `Except (List Diagnostic) TokenStream`, so a successful result
cannot carry an error diagnostic. Every byte of the normalized source is
covered by exactly one token spelling or trivia spelling, and `TokenStream.text`
reproduces that capture.

## What the lexer recognizes

* module-header lines `---- MODULE Name ----` (at least four dashes on each
  side, on their own line) and module-end lines of at least four `=`;
* ASCII identifiers, `Name!Name` qualified names, and reserved words;
* prefix reserved words `WF_` and `SF_`, always split from the subscript that
  follows: `WF_x(Next)` lexes as `WF_`, `x`, `(`, ...;
* decimal integers and the octal `\o`, hexadecimal `\h`, and binary `\b`
  spellings the profile accepts, each normalized to one `Int` value; `1..2`
  stays `1`, `..`, `2`;
* strings with the escapes `\`, `"`, `t`, `n`, `r`, and `f`, reporting other
  escapes;
* punctuation, operator runs, and the profile's ASCII and word aliases (`/\`
  and `\land` share one canonical spelling);
* operator spellings outside the alias table, such as `\oplus`, as symbolic
  tokens whose canonical spelling is the literal spelling;
* line comments, nested block comments, and `@`-prefixed annotations as trivia
  that carry the profile's annotation kind and payload.

## Revision-1 limits

`maxSourceBytes`, `maxTokens`, `maxTokenBytes`, `maxIdentifierBytes`,
`maxIntegerDigits`, `maxCommentDepth`, and the diagnostic count and byte budgets
are explicit: every accumulating scan is bounded before it allocates. Invalid
UTF-8 and control characters are reported before token scanning starts, because
a token stream only carries textual spellings. Unicode operator glyphs and every
other non-ASCII scalar outside strings and comments are rejected; the profile
stages the Unicode spellings out and the diagnostic names the spelling. The scan
stops as soon as diagnostics can no longer be recorded, so hostile input stays
bounded.

## Diagnostic codes

`TLA-LEX-INVALID-UTF8`, `TLA-LEX-CONTROL-CHARACTER`, `TLA-LEX-UNICODE-STAGED`,
`TLA-LEX-UNKNOWN-CHARACTER`, `TLA-LEX-UNTERMINATED-STRING`,
`TLA-LEX-NEWLINE-IN-STRING`, `TLA-LEX-INVALID-ESCAPE`, `TLA-LEX-INVALID-NUMBER`,
`TLA-LEX-INTEGER-TOO-LARGE`, `TLA-LEX-IDENTIFIER-TOO-LARGE`,
`TLA-LEX-UNTERMINATED-COMMENT`, `TLA-LEX-COMMENT-NESTING`,
`TLA-LEX-TOKEN-TOO-LARGE`, `TLA-LEX-TOO-MANY-TOKENS`, `TLA-LEX-SOURCE-TOO-LARGE`,
and `TLA-LEX-DIAGNOSTICS-TRUNCATED`.
-/

namespace Core.Tla

/-! ## Language profile -/

/-- One operator with its canonical spelling and every accepted alias. -/
structure SymbolAlias where
  canonical : String
  spellings : Array String
  deriving Repr, BEq

/-- Reserved words of the executable TLA+ module language. `WF_` and `SF_` are
prefix reserved words and live in `defaultPrefixKeywords` instead. -/
def defaultKeywords : Array String := #[
  "ASSUME", "ASSUMPTION", "AXIOM", "BOOLEAN", "BY", "CASE", "CHOOSE",
  "CONSTANT", "CONSTANTS", "COROLLARY", "DEF", "DEFS", "DOMAIN", "ELSE",
  "ENABLED", "EXCEPT", "EXTENDS", "FALSE", "HAVE", "HIDE", "IF", "IN",
  "INSTANCE", "LEMMA", "LET", "LOCAL", "MODULE", "NEW", "OBVIOUS", "OMITTED",
  "ONLY", "OTHER", "PICK", "PROOF", "PROPOSITION", "PROVE", "QED", "RECURSIVE",
  "STATE", "STRING", "SUBSET", "TAKE", "THEOREM", "THEN", "TRUE", "UNCHANGED",
  "UNION", "VARIABLE", "VARIABLES", "WHEN", "WITNESS", "WITH"]

/-- Reserved words that always split from a following subscript. -/
def defaultPrefixKeywords : Array String := #["WF_", "SF_"]

/-- Canonical spellings and aliases of the revision-1 TLA+ operator vocabulary
(`Docs/model-interface-compiler/tla-language-profile.md`, §4.7). Spellings with
several entries normalize the symbolic ASCII and word ASCII forms of one
operator; single-character entries keep adjacent operators from merging into one
run. Unicode glyphs are deliberately absent: `stagedUnicodeOperatorSpellings`
lists them so the lexer can name them in a profile-limit diagnostic. -/
def defaultSymbolAliases : Array SymbolAlias := #[
  ⟨"==", #["=="]⟩,
  ⟨"/\\", #["/\\", "\\land"]⟩,
  ⟨"\\/", #["\\/", "\\lor"]⟩,
  ⟨"~", #["~", "\\lnot", "\\neg"]⟩,
  ⟨"=>", #["=>"]⟩,
  ⟨"<=>", #["<=>", "\\equiv"]⟩,
  ⟨"#", #["#", "/="]⟩,
  ⟨"=<", #["=<", "<=", "\\leq"]⟩,
  ⟨">=", #[">=", "\\geq"]⟩,
  ⟨"\\in", #["\\in"]⟩,
  ⟨"\\notin", #["\\notin"]⟩,
  ⟨"\\subseteq", #["\\subseteq"]⟩,
  ⟨"\\subset", #["\\subset"]⟩,
  ⟨"\\supseteq", #["\\supseteq"]⟩,
  ⟨"\\supset", #["\\supset"]⟩,
  ⟨"\\cup", #["\\cup", "\\union"]⟩,
  ⟨"\\cap", #["\\cap", "\\intersect"]⟩,
  ⟨"\\X", #["\\X", "\\times"]⟩,
  ⟨"\\o", #["\\o"]⟩,
  ⟨"\\div", #["\\div"]⟩,
  ⟨"\\circ", #["\\circ"]⟩,
  ⟨"\\oplus", #["\\oplus"]⟩,
  ⟨"\\prec", #["\\prec"]⟩,
  ⟨"\\succ", #["\\succ"]⟩,
  ⟨"\\sim", #["\\sim"]⟩,
  ⟨"\\approx", #["\\approx"]⟩,
  ⟨"\\bullet", #["\\bullet"]⟩,
  ⟨"\\star", #["\\star"]⟩,
  ⟨"\\bigcirc", #["\\bigcirc"]⟩,
  ⟨"\\A", #["\\A"]⟩,
  ⟨"\\E", #["\\E"]⟩,
  ⟨"\\", #["\\"]⟩,
  ⟨"..", #[".."]⟩,
  ⟨"|->", #["|->"]⟩,
  ⟨"<<", #["<<"]⟩,
  ⟨">>", #[">>"]⟩,
  ⟨"[]", #["[]"]⟩,
  ⟨"<>", #["<>"]⟩,
  ⟨"~>", #["~>"]⟩,
  ⟨"->", #["->"]⟩,
  ⟨"<-", #["<-"]⟩,
  ⟨"=", #["="]⟩,
  ⟨"<", #["<"]⟩,
  ⟨">", #[">"]⟩,
  ⟨"+", #["+"]⟩,
  ⟨"-", #["-"]⟩,
  ⟨"*", #["*"]⟩,
  ⟨"/", #["/"]⟩,
  ⟨"'", #["'"]⟩,
  ⟨"!", #["!"]⟩,
  ⟨"@", #["@"]⟩,
  ⟨".", #["."]⟩,
  ⟨":", #[":"]⟩,
  ⟨"%", #["%"]⟩,
  ⟨"^", #["^"]⟩,
  ⟨"|", #["|"]⟩,
  ⟨"&", #["&"]⟩,
  ⟨"?", #["?"]⟩,
  ⟨"$", #["$"]⟩,
  ⟨";", #[";"]⟩]

/-- Unicode operator spellings that revision 1 stages out. Each one is a valid
TLA+ spelling of an ASCII operator, so the lexer names the spelling in a
profile-limit diagnostic instead of reporting malformed input. -/
def stagedUnicodeOperatorSpellings : Array String := #[
  "∧", "∨", "¬", "⇒", "⇔", "≡", "∈", "∉", "⊆", "⊂", "⊇", "⊃", "∪", "∩",
  "≠", "≤", "≥", "⟨", "⟩", "↦", "‥", "□", "◇", "≜", "→", "←", "∘", "×",
  "÷", "≺", "≻", "∼", "≈", "∙", "⋆", "○"]

/-- The language profile the lexer consumes. Precedence and associativity tables
belong to the parser; this profile owns spellings, reserved words, and the
staged Unicode spellings. -/
structure LanguageProfile where
  name : String
  keywords : Array String
  prefixKeywords : Array String
  symbols : Array SymbolAlias
  stagedUnicode : Array String
  deriving Repr

namespace LanguageProfile

/-- The executable TLA+ profile of this slice, pinned to
`mirrors-tla-frontend-profile-1`. Later revisions extend these tables instead of
changing lexer code. -/
def default : LanguageProfile :=
  { name := "mirrors-tla-frontend-profile-1"
    keywords := defaultKeywords
    prefixKeywords := defaultPrefixKeywords
    symbols := defaultSymbolAliases
    stagedUnicode := stagedUnicodeOperatorSpellings }

/-- Canonical keyword spelling when `spelling` is a reserved word. -/
def keyword? (profile : LanguageProfile) (spelling : String) : Option String :=
  if profile.keywords.contains spelling then some spelling else none

/-- Longest prefix reserved word of `spelling`, with its character count. -/
def prefixKeywordAt? (profile : LanguageProfile) (spelling : String) :
    Option (String × Nat) :=
  profile.prefixKeywords.foldl (fun found candidate =>
    let length := candidate.toList.length
    if spelling.startsWith candidate && length > (found.map Prod.snd).getD 0 then
      some (candidate, length)
    else found) none

/-- Canonical spelling of an exact operator spelling. -/
def canonicalFor? (profile : LanguageProfile) (spelling : String) :
    Option String :=
  profile.symbols.findSome? fun group =>
    if group.spellings.contains spelling then some group.canonical else none

/-- `true` when `spelling` is a Unicode operator spelling this profile revision
stages out. -/
def isStagedUnicode (profile : LanguageProfile) (spelling : String) : Bool :=
  profile.stagedUnicode.contains spelling

end LanguageProfile

/-! ## Limits -/

/-- Explicit lexer limits. `maxSourceBytes`, `maxIdentifierBytes`, and
`maxCommentDepth` are the revision-1 profile limits
(`Docs/model-interface-compiler/tla-language-profile.md`, §8); `maxTokens`
follows the frontend limits design; `maxTokenBytes` and `maxIntegerDigits` are
lexer-local bounds that keep one token and one numeric value small. The contract
is that every bound is checked at the boundary, so later measurements may adjust
a value without changing behavior. -/
structure LexerLimits where
  maxSourceBytes : Nat := 4 * 1024 * 1024
  maxTokens : Nat := 1_000_000
  maxTokenBytes : Nat := 1024 * 1024
  maxIdentifierBytes : Nat := 256
  maxIntegerDigits : Nat := 1024
  maxCommentDepth : Nat := 64
  maxDiagnostics : Nat := 64
  maxDiagnosticBytes : Nat := 1024 * 1024
  deriving Repr, BEq, DecidableEq

namespace LexerLimits

/-- Diagnostic budgets derived from the lexer limits. -/
def diagnosticLimits (limits : LexerLimits) : DiagnosticLimits :=
  { maxCount := limits.maxDiagnostics, maxBytes := limits.maxDiagnosticBytes }

end LexerLimits

/-! ## Diagnostic codes -/

namespace LexCode

def invalidUtf8 : String := "TLA-LEX-INVALID-UTF8"
def controlCharacter : String := "TLA-LEX-CONTROL-CHARACTER"
def unicodeStaged : String := "TLA-LEX-UNICODE-STAGED"
def unknownCharacter : String := "TLA-LEX-UNKNOWN-CHARACTER"
def unterminatedString : String := "TLA-LEX-UNTERMINATED-STRING"
def newlineInString : String := "TLA-LEX-NEWLINE-IN-STRING"
def invalidEscape : String := "TLA-LEX-INVALID-ESCAPE"
def invalidNumber : String := "TLA-LEX-INVALID-NUMBER"
def integerTooLarge : String := "TLA-LEX-INTEGER-TOO-LARGE"
def identifierTooLarge : String := "TLA-LEX-IDENTIFIER-TOO-LARGE"
def unterminatedComment : String := "TLA-LEX-UNTERMINATED-COMMENT"
def commentNesting : String := "TLA-LEX-COMMENT-NESTING"
def tokenTooLarge : String := "TLA-LEX-TOKEN-TOO-LARGE"
def tooManyTokens : String := "TLA-LEX-TOO-MANY-TOKENS"
def sourceTooLarge : String := "TLA-LEX-SOURCE-TOO-LARGE"
def diagnosticsTruncated : String := "TLA-LEX-DIAGNOSTICS-TRUNCATED"

end LexCode

/-! ## Decoded scalars -/

/-- One decoded scalar with its byte offset and UTF-8 width. -/
private structure SourceChar where
  character : Char
  offset : Nat
  width : Nat
  deriving Repr, Inhabited

/-- Total decoder used only after `lex` validated UTF-8. The fallback is
unreachable for validated input and keeps the scanners panic-free. -/
private def decodeChar (bytes : ByteArray) (offset : Nat) : Char × Nat :=
  match decodeUtf8At bytes offset with
  | .ok (character, width) => (character, width)
  | .error _ => (Char.ofNat 0xFFFD, 1)

private def decodeChars (bytes : ByteArray) : Array SourceChar :=
  Id.run do
    let mut characters : Array SourceChar := #[]
    let mut offset := 0
    while offset < bytes.size do
      let (character, width) := decodeChar bytes offset
      characters := characters.push ⟨character, offset, width⟩
      offset := offset + width
    return characters

private def byteOffsetAt (chars : Array SourceChar) (bytes : ByteArray)
    (index : Nat) : Nat :=
  if index < chars.size then chars[index]!.offset else bytes.size

private def charAt? (chars : Array SourceChar) (index : Nat) : Option Char :=
  if index < chars.size then some chars[index]!.character else none

private def slice (bytes : ByteArray) (start stop : Nat) : String :=
  match String.fromUTF8? (bytes.extract start stop) with
  | some text => text
  | none => ""

/-- Control scalars: C0 except tab and newline, DEL, and the C1 block. The
source pre-scan rejects them wherever they appear, including inside comments and
strings (`rej-control-character`). -/
private def isControlScalar (character : Char) : Bool :=
  let code := character.toNat
  (code < 0x20 && character != '\t' && character != '\n' && character != '\r') ||
    (0x7F ≤ code && code ≤ 0x9F)

private def utf8ProblemName : Utf8Problem → String
  | .unexpectedContinuationByte _ => "unexpectedContinuationByte"
  | .truncatedSequence _ _ _ => "truncatedSequence"
  | .overlongEncoding _ => "overlongEncoding"
  | .surrogateCodePoint _ => "surrogateCodePoint"
  | .codePointOutOfRange _ => "codePointOutOfRange"

private def lexDiagnostic (source : SourceUnit) (code : String)
    (message : String) (range : SourceRange) : Diagnostic :=
  Diagnostic.error code .lex message (SourceLocation.ofUnit source range)

private def pointRange (offset line column : Nat) : SourceRange :=
  { start := ⟨offset, line, column⟩, stop := ⟨offset, line, column⟩ }

private def spanRange (startOffset stopOffset line column : Nat) : SourceRange :=
  { start := ⟨startOffset, line, column⟩, stop := ⟨stopOffset, line, column⟩ }

/-! ## Source pre-scan -/

/-- Report invalid UTF-8 occurrences and control scalars, up to the diagnostic
budget. Both make the source unit unusable before token scanning starts. Lines
are counted from raw `0x0A` bytes and one scalar advances one column, so
positions stay deterministic for arbitrary input. -/
private def scanSourceProblems (limits : LexerLimits) (source : SourceUnit) :
    DiagnosticBuffer :=
  let bytes := source.normalizedUtf8
  Id.run do
    let mut buffer := DiagnosticBuffer.empty
    let mut offset := 0
    let mut line := 1
    let mut column := 1
    while offset < bytes.size && !buffer.truncated do
      match decodeUtf8At bytes offset with
      | .ok (character, width) =>
        if isControlScalar character then
          buffer := DiagnosticBuffer.push (LexerLimits.diagnosticLimits limits)
            buffer
            ((lexDiagnostic source LexCode.controlCharacter
              "control character is outside the revision-1 profile"
              (spanRange offset (offset + width) line column)).withArgument
              "code" (toString character.toNat))
        if character == '\n' then
          line := line + 1
          column := 1
        else
          column := column + 1
        offset := offset + width
      | .error problem =>
        let diagnostic :=
          (lexDiagnostic source LexCode.invalidUtf8 "source is not valid UTF-8"
            (spanRange offset (offset + 1) line column)).withArgument
            "problem" (utf8ProblemName problem)
        buffer := DiagnosticBuffer.push (LexerLimits.diagnosticLimits limits)
          buffer diagnostic
        offset := offset + 1
        column := column + 1
    return buffer

/-! ## Trivia -/

private structure TriviaRun where
  items : Array Trivia
  index : Nat
  line : Nat
  column : Nat
  diagnostics : Array Diagnostic

private def isHorizontalSpace (character : Char) : Bool :=
  character == ' ' || character == '\t'

private def isStructuralSymbol (character : Char) : Bool :=
  character == '(' || character == ')' || character == '[' || character == ']' ||
    character == '{' || character == '}' || character == ','

private def skipHorizontalSpaces (chars : Array SourceChar) (index : Nat) : Nat :=
  Id.run do
    let mut current := index
    while current < chars.size && isHorizontalSpace chars[current]!.character do
      current := current + 1
    return current

private def isAnnotationBlank (character : Char) : Bool :=
  isHorizontalSpace character || character == '\n'

/-- Drop leading horizontal space, and for block comments leading line breaks. -/
private def dropAnnotationBlank (skipNewlines : Bool) : List Char → List Char
  | [] => []
  | character :: rest =>
      if isHorizontalSpace character || (skipNewlines && character == '\n') then
        dropAnnotationBlank skipNewlines rest
      else
        character :: rest

private def isAnnotationNameChar (character : Char) : Bool :=
  isAsciiIdentifierChar character || character == '.' || character == '-'

private def takeAnnotationName : List Char → List Char
  | [] => []
  | character :: rest =>
      if isAnnotationNameChar character then character :: takeAnnotationName rest
      else []

private def dropAnnotationName : List Char → List Char
  | [] => []
  | character :: rest =>
      if isAnnotationNameChar character then dropAnnotationName rest
      else character :: rest

private def trimAnnotationBlank (characters : List Char) : List Char :=
  ((characters.dropWhile isAnnotationBlank).reverse.dropWhile isAnnotationBlank).reverse

/-- Drop one trailing `;` after trimming, the terminator Apalache annotations
use (`\* @type: Int;`). -/
private def stripAnnotationSemicolon (characters : List Char) : List Char :=
  match (trimAnnotationBlank characters).reverse with
  | ';' :: rest => trimAnnotationBlank rest.reverse
  | _ => trimAnnotationBlank characters

/-- The profile's annotation kind and payload for one comment payload, or `none`
when the comment is not an annotation. `@type: ...;` becomes `apalache.type`;
any other `@name` prefix becomes `annotation:<name>`, and the payload is the
remainder with the optional colon and trailing `;` removed. The lexer records the
kind and payload without deriving any semantic fact. -/
private def annotationOfPayload? (block : Bool) (payload : List Char) :
    Option (String × String) :=
  match dropAnnotationBlank block payload with
  | '@' :: rest =>
      let name := String.ofList (takeAnnotationName rest)
      let afterName := dropAnnotationName rest
      let afterColon :=
        match afterName with
        | ':' :: tail => tail
        | _ => afterName
      let kind :=
        if name.isEmpty then "annotation"
        else if name == "type" then "apalache.type"
        else s!"annotation:{name}"
      some (kind, String.ofList (stripAnnotationSemicolon afterColon))
  | _ => none

/-- Payload text of a comment: everything between the opener and the terminator,
with the block-comment terminator removed when the comment closed. -/
private def commentPayload (bytes : ByteArray) (chars : Array SourceChar)
    (payloadIndex stopIndex : Nat) (block closed : Bool) : List Char :=
  let payloadStop := if block && closed then stopIndex - 2 else stopIndex
  (slice bytes (byteOffsetAt chars bytes payloadIndex)
    (byteOffsetAt chars bytes payloadStop)).toList

private def scanTrivia (source : SourceUnit) (limits : LexerLimits)
    (bytes : ByteArray) (chars : Array SourceChar)
    (startIndex startLine startColumn : Nat) : TriviaRun :=
  Id.run do
    let mut items : Array Trivia := #[]
    let mut diagnostics : Array Diagnostic := #[]
    let mut index := startIndex
    let mut line := startLine
    let mut column := startColumn
    let mut scanning := true
    while scanning && index < chars.size do
      let current := chars[index]!.character
      let next? := charAt? chars (index + 1)
      if isHorizontalSpace current then
        let itemOffset := chars[index]!.offset
        let itemLine := line
        let itemColumn := column
        while index < chars.size && isHorizontalSpace chars[index]!.character do
          index := index + 1
          column := column + 1
        let stopOffset := byteOffsetAt chars bytes index
        items := items.push
          { kind := .whitespace
            spelling := slice bytes itemOffset stopOffset
            range := { start := ⟨itemOffset, itemLine, itemColumn⟩
                       stop := ⟨stopOffset, line, column⟩ } }
      else if current == '\n' then
        let itemOffset := chars[index]!.offset
        let itemLine := line
        let itemColumn := column
        index := index + 1
        line := line + 1
        column := 1
        let stopOffset := byteOffsetAt chars bytes index
        items := items.push
          { kind := .newline
            spelling := slice bytes itemOffset stopOffset
            range := { start := ⟨itemOffset, itemLine, itemColumn⟩
                       stop := ⟨stopOffset, line, column⟩ } }
      else if current == '\\' && next? == some '*' then
        let itemOffset := chars[index]!.offset
        let itemLine := line
        let itemColumn := column
        let payloadIndex := index + 2
        index := index + 2
        column := column + 2
        while index < chars.size && chars[index]!.character != '\n' do
          index := index + 1
          column := column + 1
        let stopOffset := byteOffsetAt chars bytes index
        let annotation? :=
          annotationOfPayload? false (commentPayload bytes chars payloadIndex index false false)
        let (annotationKind, annotationPayload) :=
          match annotation? with
          | some (kind, payload) => (some kind, some payload)
          | none => (none, none)
        let kind := if annotation?.isSome then TriviaKind.annotation else .lineComment
        items := items.push
          { kind
            spelling := slice bytes itemOffset stopOffset
            range := { start := ⟨itemOffset, itemLine, itemColumn⟩
                       stop := ⟨stopOffset, line, column⟩ }
            annotationKind
            annotationPayload }
      else if current == '(' && next? == some '*' then
        let itemOffset := chars[index]!.offset
        let itemLine := line
        let itemColumn := column
        let payloadIndex := index + 2
        let mut depth := 0
        let mut nestingReported := false
        let mut done := false
        while !done && index < chars.size do
          let character := chars[index]!.character
          let nextCharacter? := charAt? chars (index + 1)
          if character == '(' && nextCharacter? == some '*' then
            depth := depth + 1
            if depth > limits.maxCommentDepth && !nestingReported then
              nestingReported := true
              diagnostics := diagnostics.push
                ((lexDiagnostic source LexCode.commentNesting
                  "block comment nesting exceeds the configured limit"
                  (spanRange chars[index]!.offset (byteOffsetAt chars bytes (index + 2))
                    line column)).withArgument "limit"
                  (toString limits.maxCommentDepth))
            index := index + 2
            column := column + 2
          else if character == '*' && nextCharacter? == some ')' then
            depth := depth - 1
            index := index + 2
            column := column + 2
            if depth == 0 then
              done := true
          else
            if character == '\n' then
              line := line + 1
              column := 1
            else
              column := column + 1
            index := index + 1
        if depth > 0 then
          diagnostics := diagnostics.push
            (lexDiagnostic source LexCode.unterminatedComment
              "block comment is not terminated before end of source"
              (spanRange itemOffset (byteOffsetAt chars bytes index) itemLine itemColumn))
        let stopOffset := byteOffsetAt chars bytes index
        let annotation? :=
          annotationOfPayload? true
            (commentPayload bytes chars payloadIndex index true done)
        let (annotationKind, annotationPayload) :=
          match annotation? with
          | some (kind, payload) => (some kind, some payload)
          | none => (none, none)
        let kind := if annotation?.isSome then TriviaKind.annotation else .blockComment
        items := items.push
          { kind
            spelling := slice bytes itemOffset stopOffset
            range := { start := ⟨itemOffset, itemLine, itemColumn⟩
                       stop := ⟨stopOffset, line, column⟩ }
            annotationKind
            annotationPayload }
      else
        scanning := false
    return { items, index, line, column, diagnostics }

/-! ## Operator aliases -/

private structure AliasEntry where
  spelling : String
  canonical : String
  characters : Array Char
  byteLength : Nat

private def bucketIndex (character : Char) : Nat :=
  let code := character.toNat
  if 0x21 ≤ code && code ≤ 0x7E then code - 0x21 else 94

private def aliasBefore (entry existing : AliasEntry) : Bool :=
  if entry.byteLength != existing.byteLength then
    entry.byteLength > existing.byteLength
  else
    entry.spelling < existing.spelling

private def insertAlias (entry : AliasEntry) (entries : Array AliasEntry) :
    Array AliasEntry :=
  Id.run do
    let mut result : Array AliasEntry := #[]
    let mut inserted := false
    for existing in entries do
      if !inserted && aliasBefore entry existing then
        result := result.push entry
        inserted := true
      result := result.push existing
    if !inserted then
      result := result.push entry
    return result

private def buildAliasBuckets (profile : LanguageProfile) : Array (Array AliasEntry) :=
  Id.run do
    let mut buckets : Array (Array AliasEntry) := Array.replicate 95 #[]
    for group in profile.symbols do
      for spelling in group.spellings do
        let entry : AliasEntry :=
          { spelling
            canonical := group.canonical
            characters := spelling.toList.toArray
            byteLength := spelling.toUTF8.size }
        match spelling.toList.head? with
        | none => pure ()
        | some first =>
          let index := bucketIndex first
          buckets := buckets.set! index (insertAlias entry buckets[index]!)
    return buckets

private def matchesAliasAt (entry : AliasEntry) (chars : Array SourceChar)
    (index : Nat) : Bool :=
  if index + entry.characters.size > chars.size then
    false
  else
    Id.run do
      let mut offset := 0
      let mut matched := true
      while matched && offset < entry.characters.size do
        if chars[index + offset]!.character == entry.characters[offset]! then
          offset := offset + 1
        else
          matched := false
      return matched

private def aliasesAt (buckets : Array (Array AliasEntry)) (chars : Array SourceChar)
    (index : Nat) : Array AliasEntry :=
  if index < chars.size then buckets[bucketIndex chars[index]!.character]! else #[]

private def longestAliasMatch? (buckets : Array (Array AliasEntry))
    (chars : Array SourceChar) (index : Nat) : Option (String × Nat) :=
  (aliasesAt buckets chars index).findSome? fun entry =>
    if matchesAliasAt entry chars index then some (entry.canonical, entry.characters.size) else none

/-- Numeric value of `character` in `radix`, or `none` when the character is not
a digit of that radix. -/
private def radixDigitValue? (radix : Nat) (character : Char) : Option Nat :=
  let code := character.toNat
  let candidate :=
    if 0x30 ≤ code && code ≤ 0x39 then some (code - 0x30)
    else if 0x41 ≤ code && code ≤ 0x46 then some (code - 0x41 + 10)
    else if 0x61 ≤ code && code ≤ 0x66 then some (code - 0x61 + 10)
    else none
  match candidate with
  | some value => if value < radix then some value else none
  | none => none

/-- Fold validated digits into one value. The caller bounds the digit count, so
the accumulation is bounded as well. -/
private def foldRadixDigits (radix : Nat) (digits : List Char) : Int :=
  digits.foldl (fun value character =>
    match radixDigitValue? radix character with
    | some digit => value * (radix : Int) + (digit : Int)
    | none => value) 0


/-! ## Token scanning -/

private structure TokenPiece where
  kind : TokenKind
  startIndex : Nat
  stopIndex : Nat

private structure TokenScan where
  pieces : Array TokenPiece
  stopIndex : Nat
  diagnostics : Array Diagnostic

private def singlePiece (kind : TokenKind) (startIndex stopIndex : Nat) : TokenScan :=
  { pieces := #[⟨kind, startIndex, stopIndex⟩]
    stopIndex
    diagnostics := #[] }

private def isIdentifierStart (character : Char) : Bool :=
  isAsciiLetter character || character == '_'

private def isOperatorRunChar (character : Char) : Bool :=
  !isAsciiIdentifierChar character && !isHorizontalSpace character &&
    character != '\n' && !isStructuralSymbol character && character != '"' &&
    !isControlScalar character

private def maxOperatorRunStop (chars : Array SourceChar) (startIndex : Nat) : Nat :=
  Id.run do
    let mut index := startIndex
    let mut scanning := true
    while scanning && index < chars.size do
      let character := chars[index]!.character
      let commentStart := character == '\\' && charAt? chars (index + 1) == some '*'
      if isOperatorRunChar character && !commentStart then
        index := index + 1
      else
        scanning := false
    return index

private def dashRunStop (chars : Array SourceChar) (index : Nat) : Nat :=
  Id.run do
    let mut current := index
    while current < chars.size && chars[current]!.character == '-' do
      current := current + 1
    return current

private def wordRunStop (chars : Array SourceChar) (index : Nat) : Nat :=
  Id.run do
    let mut current := index
    while current < chars.size && isAsciiIdentifierChar chars[current]!.character do
      current := current + 1
    return current

private def endOfLineAt (chars : Array SourceChar) (index : Nat) : Bool :=
  let current := skipHorizontalSpaces chars index
  current ≥ chars.size || chars[current]!.character == '\n'

private def moduleHeaderStop? (chars : Array SourceChar) (bytes : ByteArray)
    (startIndex : Nat) : Option Nat :=
  Id.run do
    let dashesStop := dashRunStop chars startIndex
    if dashesStop - startIndex < 4 then return none
    let keywordStart := skipHorizontalSpaces chars dashesStop
    let keywordStop := wordRunStop chars keywordStart
    if keywordStop == keywordStart then return none
    let keyword := slice bytes (byteOffsetAt chars bytes keywordStart)
      (byteOffsetAt chars bytes keywordStop)
    if keyword != "MODULE" then return none
    let nameStart := skipHorizontalSpaces chars keywordStop
    let nameStop := wordRunStop chars nameStart
    let name := slice bytes (byteOffsetAt chars bytes nameStart)
      (byteOffsetAt chars bytes nameStop)
    if !ModuleName.valid name then return none
    let trailingStart := skipHorizontalSpaces chars nameStop
    let trailingStop := dashRunStop chars trailingStart
    if trailingStop - trailingStart < 4 then return none
    if !endOfLineAt chars trailingStop then return none
    return some trailingStop

private def moduleEndStop? (chars : Array SourceChar) (startIndex : Nat) : Option Nat :=
  Id.run do
    let mut index := startIndex
    while index < chars.size && chars[index]!.character == '=' do
      index := index + 1
    if index - startIndex < 4 then return none
    if !endOfLineAt chars index then return none
    return some index

private def indexPosition (chars : Array SourceChar) (bytes : ByteArray)
    (line column startIndex : Nat) (index : Nat) : SourcePosition :=
  ⟨byteOffsetAt chars bytes index, line, column + (index - startIndex)⟩

private def scanString (source : SourceUnit) (bytes : ByteArray)
    (chars : Array SourceChar) (startIndex line column : Nat) : TokenScan :=
  Id.run do
    let mut diagnostics : Array Diagnostic := #[]
    let mut index := startIndex + 1
    let mut closed := false
    let mut lineBreak := false
    while !closed && !lineBreak && index < chars.size do
      let character := chars[index]!.character
      if character == '\\' then
        if index + 1 < chars.size then
          let escaped := chars[index + 1]!.character
          let supported := escaped == '"' || escaped == '\\' || escaped == 't' ||
            escaped == 'n' || escaped == 'r' || escaped == 'f'
          if !supported then
            diagnostics := diagnostics.push
              ((lexDiagnostic source LexCode.invalidEscape
                "unsupported string escape"
                (spanRange (byteOffsetAt chars bytes index)
                  (byteOffsetAt chars bytes (index + 2)) line (column + (index - startIndex)))).withArgument
                "escape" (String.ofList ['\\', escaped]))
          index := index + 2
        else
          index := index + 1
      else if character == '"' then
        closed := true
        index := index + 1
      else if character == '\n' then
        lineBreak := true
      else
        index := index + 1
    let stopIndex := index
    if lineBreak then
      diagnostics := diagnostics.push
        (lexDiagnostic source LexCode.newlineInString
          "string literal is not terminated before the end of the line"
          (spanRange (byteOffsetAt chars bytes startIndex)
            (byteOffsetAt chars bytes stopIndex) line column))
    else if !closed then
      diagnostics := diagnostics.push
        (lexDiagnostic source LexCode.unterminatedString
          "string literal is not terminated before end of source"
          (spanRange (byteOffsetAt chars bytes startIndex)
            (byteOffsetAt chars bytes stopIndex) line column))
    return { pieces := #[⟨.string, startIndex, stopIndex⟩], stopIndex, diagnostics }

/-- Extent of an identifier or qualified name and the `Name!Declaration` parts
inside it. -/
private def scanWordParts (chars : Array SourceChar) (startIndex : Nat) :
    Nat × Array (Nat × Nat) :=
  Id.run do
    let mut index := startIndex
    while index < chars.size && isAsciiIdentifierChar chars[index]!.character do
      index := index + 1
    let mut parts : Array (Nat × Nat) := #[(startIndex, index)]
    let mut stop := index
    let mut extending := true
    while extending do
      if stop + 1 < chars.size && chars[stop]!.character == '!' &&
          isIdentifierStart chars[stop + 1]!.character then
        let partStart := stop + 1
        let mut partStop := partStart
        while partStop < chars.size && isAsciiIdentifierChar chars[partStop]!.character do
          partStop := partStop + 1
        parts := parts.push (partStart, partStop)
        stop := partStop
      else
        extending := false
    return (stop, parts)

private def scanIdentifier (profile : LanguageProfile) (limits : LexerLimits)
    (source : SourceUnit) (bytes : ByteArray) (chars : Array SourceChar)
    (startIndex line column : Nat) : TokenScan :=
  Id.run do
    let (stop, parts) := scanWordParts chars startIndex
    let firstStop := parts[0]!.2
    let spelling := slice bytes (byteOffsetAt chars bytes startIndex)
      (byteOffsetAt chars bytes firstStop)
    match profile.prefixKeywordAt? spelling with
    | some (prefixSpelling, count) =>
      return singlePiece (.keyword prefixSpelling) startIndex (min (startIndex + count) firstStop)
    | none =>
      match profile.keyword? spelling with
      | some canonical => return singlePiece (.keyword canonical) startIndex firstStop
      | none =>
        let mut diagnostics : Array Diagnostic := #[]
        for part in parts do
          let partBytes := byteOffsetAt chars bytes part.2 - byteOffsetAt chars bytes part.1
          if partBytes > limits.maxIdentifierBytes then
            diagnostics := diagnostics.push
              (((lexDiagnostic source LexCode.identifierTooLarge
                "identifier exceeds the configured byte limit"
                ⟨⟨byteOffsetAt chars bytes part.1, line, column + (part.1 - startIndex)⟩,
                 ⟨byteOffsetAt chars bytes part.2, line, column + (part.2 - startIndex)⟩⟩).withArgument
                "limit" (toString limits.maxIdentifierBytes)).withArgument
                "observed" (toString partBytes))
        let kind := if parts.size > 1 then TokenKind.qualifiedName else TokenKind.identifier
        return { pieces := #[⟨kind, startIndex, stop⟩], stopIndex := stop, diagnostics }

/-- Radix of an alternate integer spelling whose `\o`, `\h`, or `\b` prefix
starts at `startIndex`, or `none` when the text is an operator word. The profile
prefers the numeric reading as soon as the prefix is followed by a digit of its
alphabet. -/
private def radixPrefix? (chars : Array SourceChar) (startIndex : Nat) : Option Nat :=
  match charAt? chars (startIndex + 1), charAt? chars (startIndex + 2) with
  | some prefixCharacter, some third =>
    if prefixCharacter == 'o' && isAsciiDigit third then some 8
    else if prefixCharacter == 'h' && (radixDigitValue? 16 third).isSome then some 16
    else if prefixCharacter == 'b' && isAsciiDigit third then some 2
    else none
  | _, _ => none

private def isRadixDigit (radix : Nat) (character : Char) : Bool :=
  if radix == 16 then (radixDigitValue? 16 character).isSome else isAsciiDigit character

/-- Scan one octal, hexadecimal, or binary integer spelling after its prefix. -/
private def scanRadixNumber (source : SourceUnit) (limits : LexerLimits)
    (bytes : ByteArray) (chars : Array SourceChar) (startIndex line column : Nat)
    (radix : Nat) : TokenScan :=
  Id.run do
    let mut digits : Array Char := #[]
    let mut index := startIndex + 2
    while index < chars.size && isRadixDigit radix chars[index]!.character do
      digits := digits.push chars[index]!.character
      index := index + 1
    let startOffset := byteOffsetAt chars bytes startIndex
    let stopOffset := byteOffsetAt chars bytes index
    let spelling := slice bytes startOffset stopOffset
    let range : SourceRange :=
      ⟨⟨startOffset, line, column⟩, ⟨stopOffset, line, column + (index - startIndex)⟩⟩
    if digits.any (fun character => (radixDigitValue? radix character).isNone) then
      return ({
        pieces := #[⟨.symbol ⟨spelling⟩, startIndex, index⟩]
        stopIndex := index
        diagnostics := #[
          (lexDiagnostic source LexCode.invalidNumber
            "digit is outside the radix of this integer spelling" range).withArgument
            "radix" (toString radix)] } : TokenScan)
    if digits.size > limits.maxIntegerDigits then
      return ({
        pieces := #[⟨.symbol ⟨spelling⟩, startIndex, index⟩]
        stopIndex := index
        diagnostics := #[
          ((lexDiagnostic source LexCode.integerTooLarge
            "integer literal exceeds the configured digit limit" range).withArgument
            "limit" (toString limits.maxIntegerDigits)).withArgument
            "observed" (toString digits.size)] } : TokenScan)
    return singlePiece (.integer (foldRadixDigits radix digits.toList)) startIndex index

/-- Scan a decimal integer. Revision 1 rejects decimal fractions and exponents,
so those spellings report `TLA-LEX-INVALID-NUMBER` instead of becoming tokens. -/
private def scanDecimal (source : SourceUnit) (limits : LexerLimits)
    (bytes : ByteArray) (chars : Array SourceChar) (startIndex line column : Nat) :
    TokenScan :=
  Id.run do
    let mut digits : Array Char := #[]
    let mut index := startIndex
    while index < chars.size && isAsciiDigit chars[index]!.character do
      digits := digits.push chars[index]!.character
      index := index + 1
    let mut unsupported := false
    let mut unsupportedStop := index
    if index + 1 < chars.size && chars[index]!.character == '.' &&
        isAsciiDigit chars[index + 1]!.character then
      unsupported := true
      unsupportedStop := index + 2
      while unsupportedStop < chars.size && isAsciiDigit chars[unsupportedStop]!.character do
        unsupportedStop := unsupportedStop + 1
    else if index < chars.size &&
        (chars[index]!.character == 'e' || chars[index]!.character == 'E') then
      let afterMarker := index + 1
      let signed :=
        if afterMarker < chars.size &&
            (chars[afterMarker]!.character == '+' || chars[afterMarker]!.character == '-')
        then afterMarker + 1 else afterMarker
      if signed < chars.size && isAsciiDigit chars[signed]!.character then
        unsupported := true
        unsupportedStop := signed + 1
        while unsupportedStop < chars.size && isAsciiDigit chars[unsupportedStop]!.character do
          unsupportedStop := unsupportedStop + 1
    let startOffset := byteOffsetAt chars bytes startIndex
    let stopOffset := byteOffsetAt chars bytes unsupportedStop
    let range : SourceRange :=
      ⟨⟨startOffset, line, column⟩, ⟨stopOffset, line, column + (unsupportedStop - startIndex)⟩⟩
    if unsupported then
      return ({
        pieces := #[⟨.symbol ⟨slice bytes startOffset stopOffset⟩, startIndex, unsupportedStop⟩]
        stopIndex := unsupportedStop
        diagnostics := #[
          lexDiagnostic source LexCode.invalidNumber
            "decimal fractions and exponents are outside the revision-1 profile" range] } : TokenScan)
    if digits.size > limits.maxIntegerDigits then
      return ({
        pieces := #[⟨.symbol ⟨slice bytes startOffset (byteOffsetAt chars bytes index)⟩,
                       startIndex, index⟩]
        stopIndex := index
        diagnostics := #[
          ((lexDiagnostic source LexCode.integerTooLarge
            "integer literal exceeds the configured digit limit"
            ⟨⟨startOffset, line, column⟩,
             ⟨byteOffsetAt chars bytes index, line, column + (index - startIndex)⟩⟩).withArgument
            "limit" (toString limits.maxIntegerDigits)).withArgument
            "observed" (toString digits.size)] } : TokenScan)
    return singlePiece (.integer (foldRadixDigits 10 digits.toList)) startIndex index

private def scanBackslashWord (profile : LanguageProfile) (bytes : ByteArray)
    (chars : Array SourceChar) (startIndex : Nat) : TokenScan :=
  Id.run do
    let mut index := startIndex + 1
    while index < chars.size && isAsciiIdentifierChar chars[index]!.character do
      index := index + 1
    let spelling := slice bytes (byteOffsetAt chars bytes startIndex)
      (byteOffsetAt chars bytes index)
    let canonical := (profile.canonicalFor? spelling).getD spelling
    return singlePiece (.symbol ⟨canonical⟩) startIndex index

/-- Split an operator run that has no canonical spelling of its own: the longest
profile alias wins at each scalar, and a scalar that starts no alias becomes a
one-scalar symbolic piece. The result is `none` when the run would stay one
piece, so the caller keeps an unknown run as a single symbolic token. -/
private def decomposeRun? (buckets : Array (Array AliasEntry))
    (chars : Array SourceChar) (startIndex stopIndex : Nat) :
    Option (Array TokenPiece) :=
  Id.run do
    let mut pieces : Array TokenPiece := #[]
    let mut index := startIndex
    while index < stopIndex do
      match longestAliasMatch? buckets chars index with
      | some (canonical, length) =>
        if index + length ≤ stopIndex then
          pieces := pieces.push ⟨.symbol ⟨canonical⟩, index, index + length⟩
          index := index + length
        else
          pieces := pieces.push
            ⟨.symbol ⟨String.ofList [chars[index]!.character]⟩, index, index + 1⟩
          index := index + 1
      | none =>
        pieces := pieces.push
          ⟨.symbol ⟨String.ofList [chars[index]!.character]⟩, index, index + 1⟩
        index := index + 1
    if pieces.size ≥ 2 then return some pieces else return none

private def scanSymbol (profile : LanguageProfile) (bytes : ByteArray)
    (chars : Array SourceChar) (buckets : Array (Array AliasEntry))
    (startIndex : Nat) : TokenScan :=
  match longestAliasMatch? buckets chars startIndex with
  | some (canonical, length) =>
    singlePiece (.symbol ⟨canonical⟩) startIndex (startIndex + length)
  | none =>
    let current := chars[startIndex]!.character
    if isStructuralSymbol current then
      singlePiece (.symbol ⟨String.ofList [current]⟩) startIndex (startIndex + 1)
    else
      let runStop := maxOperatorRunStop chars startIndex
      let run := slice bytes (byteOffsetAt chars bytes startIndex)
        (byteOffsetAt chars bytes runStop)
      match profile.canonicalFor? run with
      | some canonical => singlePiece (.symbol ⟨canonical⟩) startIndex runStop
      | none =>
        match decomposeRun? buckets chars startIndex runStop with
        | some pieces => { pieces, stopIndex := runStop, diagnostics := #[] }
        | none => singlePiece (.symbol ⟨run⟩) startIndex runStop

private def scanToken (profile : LanguageProfile) (limits : LexerLimits)
    (source : SourceUnit) (bytes : ByteArray) (chars : Array SourceChar)
    (buckets : Array (Array AliasEntry)) (startIndex line column : Nat) : TokenScan :=
  let current := chars[startIndex]!.character
  let lineStart := startIndex == 0 || chars[startIndex - 1]!.character == '\n'
  let next? := charAt? chars (startIndex + 1)
  if current.toNat > 0x7F then
    let startOffset := byteOffsetAt chars bytes startIndex
    let stopOffset := byteOffsetAt chars bytes (startIndex + 1)
    let spelling := slice bytes startOffset stopOffset
    let staged := profile.isStagedUnicode spelling
    let code := if staged then LexCode.unicodeStaged else LexCode.unknownCharacter
    let message :=
      if staged then
        "Unicode operator spelling is staged out of the revision-1 profile"
      else
        "character is outside the ASCII revision-1 profile"
    let diagnostic :=
      ((lexDiagnostic source code message
        ⟨⟨startOffset, line, column⟩, ⟨stopOffset, line, column + 1⟩⟩).withArgument
        "spelling" spelling).withArgument "code" (toString current.toNat)
    { pieces := #[⟨.symbol ⟨spelling⟩, startIndex, startIndex + 1⟩]
      stopIndex := startIndex + 1
      diagnostics := #[diagnostic] }
  else if current == '"' then
    scanString source bytes chars startIndex line column
  else if current == '-' && lineStart then
    match moduleHeaderStop? chars bytes startIndex with
    | some stopIndex => singlePiece .moduleHeader startIndex stopIndex
    | none => scanSymbol profile bytes chars buckets startIndex
  else if current == '=' && lineStart then
    match moduleEndStop? chars startIndex with
    | some stopIndex => singlePiece .moduleEnd startIndex stopIndex
    | none => scanSymbol profile bytes chars buckets startIndex
  else if isIdentifierStart current then
    scanIdentifier profile limits source bytes chars startIndex line column
  else if isAsciiDigit current then
    scanDecimal source limits bytes chars startIndex line column
  else if current == '\\' then
    match radixPrefix? chars startIndex with
    | some radix => scanRadixNumber source limits bytes chars startIndex line column radix
    | none =>
      match next? with
      | some nextCharacter =>
        if isAsciiIdentifierChar nextCharacter then
          scanBackslashWord profile bytes chars startIndex
        else
          scanSymbol profile bytes chars buckets startIndex
      | none => scanSymbol profile bytes chars buckets startIndex
  else
    scanSymbol profile bytes chars buckets startIndex

/-! ## Main loop -/

private structure TokenScanResult where
  tokens : Array Token
  diagnostics : DiagnosticBuffer
  endPosition : SourcePosition
  aborted : Bool

private def scanTokens (profile : LanguageProfile) (limits : LexerLimits)
    (source : SourceUnit) (bytes : ByteArray) (chars : Array SourceChar) :
    TokenScanResult :=
  Id.run do
    let buckets := buildAliasBuckets profile
    let diagnosticLimits := LexerLimits.diagnosticLimits limits
    let mut buffer := DiagnosticBuffer.empty
    let mut tokens : Array Token := #[]
    let mut pendingLeading : Array Trivia := #[]
    let mut previous : Option Token := none
    let mut index := 0
    let mut line := 1
    let mut column := 1
    let mut aborted := false
    while !aborted && index < chars.size do
      let run := scanTrivia source limits bytes chars index line column
      for diagnostic in run.diagnostics do
        buffer := DiagnosticBuffer.push diagnosticLimits buffer diagnostic
      let mut boundary := 0
      while boundary < run.items.size && run.items[boundary]!.kind != TriviaKind.newline do
        boundary := boundary + 1
      let before := run.items.extract 0 boundary
      let after := run.items.extract boundary run.items.size
      match previous with
      | some token =>
        tokens := tokens.push { token with trailingTrivia := before }
        previous := none
      | none => pendingLeading := pendingLeading ++ before
      pendingLeading := pendingLeading ++ after
      line := run.line
      column := run.column
      index := run.index
      if buffer.truncated then
        aborted := true
      else if index < chars.size then
        let emitted := tokens.size + (if previous.isSome then 1 else 0)
        if emitted ≥ limits.maxTokens then
          buffer := DiagnosticBuffer.push diagnosticLimits buffer
            ((lexDiagnostic source LexCode.tooManyTokens
              "token count exceeds the configured limit"
              (pointRange (byteOffsetAt chars bytes index) line column)).withArgument
              "limit" (toString limits.maxTokens))
          aborted := true
        else
          let scanned := scanToken profile limits source bytes chars buckets index line column
          let scan :=
            if scanned.stopIndex > index then
              scanned
            else
              -- Every accepted scalar advances the cursor. A scalar that no
              -- scanner accepts is only reachable when a diagnostic budget
              -- dropped the pre-scan problem, so consume exactly that scalar
              -- instead of looping on a zero-width piece.
              { pieces := #[⟨.symbol ⟨String.ofList [chars[index]!.character]⟩,
                            index, index + 1⟩]
                stopIndex := index + 1
                diagnostics := scanned.diagnostics }
          for diagnostic in scan.diagnostics do
            buffer := DiagnosticBuffer.push diagnosticLimits buffer diagnostic
          let mut first := true
          for piece in scan.pieces do
            let startOffset := byteOffsetAt chars bytes piece.startIndex
            let stopOffset := byteOffsetAt chars bytes piece.stopIndex
            let startPosition : SourcePosition :=
              ⟨startOffset, line, column + (piece.startIndex - index)⟩
            let stopPosition : SourcePosition :=
              ⟨stopOffset, line, column + (piece.stopIndex - index)⟩
            let token : Token :=
              { kind := piece.kind
                spelling := slice bytes startOffset stopOffset
                range := ⟨startPosition, stopPosition⟩
                leadingTrivia := if first then pendingLeading else #[]
                trailingTrivia := #[] }
            match previous with
            | some pending => tokens := tokens.push pending
            | none => pure ()
            previous := some token
            first := false
            if stopOffset - startOffset > limits.maxTokenBytes then
              buffer := DiagnosticBuffer.push diagnosticLimits buffer
                ((lexDiagnostic source LexCode.tokenTooLarge
                  "token exceeds the configured byte limit"
                  ⟨startPosition, stopPosition⟩).withArgument
                  "limit" (toString limits.maxTokenBytes))
          pendingLeading := #[]
          column := column + (scan.stopIndex - index)
          index := scan.stopIndex
          if buffer.truncated then
            aborted := true
    match previous with
    | some token => tokens := tokens.push token
    | none => pure ()
    let endPosition : SourcePosition := ⟨bytes.size, line, column⟩
    tokens := tokens.push
      { kind := .eof
        spelling := ""
        range := ⟨endPosition, endPosition⟩
        leadingTrivia := pendingLeading
        trailingTrivia := #[] }
    return { tokens, diagnostics := buffer, endPosition, aborted }

/-! ## Entry point -/

private def finishDiagnostics (source : SourceUnit) (buffer : DiagnosticBuffer)
    (endPosition : SourcePosition) : List Diagnostic :=
  let collected := buffer.diagnostics.toList
  if buffer.truncated then
    collected ++
      [((lexDiagnostic source LexCode.diagnosticsTruncated
        "diagnostic budget exhausted; further diagnostics were dropped"
        ⟨endPosition, endPosition⟩).withArgument "dropped" (toString buffer.dropped))]
  else
    collected

/-- Lex a captured source unit. A successful result has no error diagnostic and
whose final token is `TokenKind.eof`; failures carry bounded diagnostics and
never a partial token stream. -/
def lex (profile : LanguageProfile) (limits : LexerLimits) (source : SourceUnit) :
    Except (List Diagnostic) TokenStream :=
  let bytes := source.normalizedUtf8
  if bytes.size > limits.maxSourceBytes then
    .error [((lexDiagnostic source LexCode.sourceTooLarge
      "source exceeds the configured byte limit" (pointRange 0 1 1)).withArgument
      "limit" (toString limits.maxSourceBytes)).withArgument
      "observed" (toString bytes.size)]
  else
    let problemBuffer := scanSourceProblems limits source
    if problemBuffer.truncated || !problemBuffer.diagnostics.isEmpty then
      .error (finishDiagnostics source problemBuffer ⟨bytes.size, 1, 1⟩)
    else
      let chars := decodeChars bytes
      let result := scanTokens profile limits source bytes chars
      if result.diagnostics.diagnostics.any Diagnostic.hasErrorSeverity ||
          result.diagnostics.truncated then
        .error (finishDiagnostics source result.diagnostics result.endPosition)
      else
        .ok { tokens := result.tokens }

end Core.Tla
