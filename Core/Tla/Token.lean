import Core.Tla.Source

/-!
# TLA+ tokens and trivia (Core/Tla/Token.lean)

Lossless token vocabulary for the general TLA+ frontend
(`Docs/model-interface-compiler/tla-frontend-design.md`, §9 "Lexer" and §10
"Concrete and abstract syntax").

Every byte of a normalized source unit is covered by exactly one token
spelling or trivia spelling, so `TokenStream.text` reproduces the captured
bytes. Trivia attachment follows one deterministic rule: trivia that follows a
token before the next line break is that token's `trailingTrivia`; the rest
becomes the next token's `leadingTrivia`, and trailing trivia at end of file
becomes the leading trivia of the final `eof` token.

Operator spellings are normalized through `Symbol.canonical`: equivalent ASCII
and Unicode spellings of one operator share a canonical spelling while
`Token.spelling` keeps the original bytes. Spellings outside the language
profile stay symbolic and are resolved by the parser, which is how user-defined
operators such as `\oplus` survive lexing.

Annotations are trivia: the lexer classifies a comment whose payload starts
with `@` as `TriviaKind.annotation` and never interprets the payload.
-/

namespace Core.Tla

/-! ## Trivia -/

/-- Trivia classification. `annotation` is a line or block comment whose first
non-blank payload character is `@` (for example `\* @type: Int;`). Annotation
items also carry the profile's annotation kind and payload
(`Docs/model-interface-compiler/tla-language-profile.md`, §4.6). -/
inductive TriviaKind where
  | whitespace
  | newline
  | lineComment
  | blockComment
  | annotation
  deriving Repr, BEq, DecidableEq, Inhabited

namespace TriviaKind

/-- Stable rendering used by inspection output and tests. -/
def toString : TriviaKind → String
  | .whitespace => "whitespace"
  | .newline => "newline"
  | .lineComment => "lineComment"
  | .blockComment => "blockComment"
  | .annotation => "annotation"

end TriviaKind

/-- A lossless trivia item. `spelling` is the original source slice. Annotation
items carry the profile's annotation kind (`apalache.type` or
`annotation:<name>`) and payload; the lexer records both without deriving any
semantic fact from them. -/
structure Trivia where
  kind : TriviaKind
  spelling : String
  range : SourceRange
  annotationKind : Option String := none
  annotationPayload : Option String := none
  deriving Repr, BEq, DecidableEq, Inhabited

/-! ## Tokens -/

/-- A normalized operator spelling. `canonical` is the spelling chosen by the
language profile for a set of aliases; it equals the literal spelling for
operators the profile does not know. -/
structure Symbol where
  canonical : String
  deriving Repr, BEq, DecidableEq

namespace Symbol

/-- The canonical spelling. -/
def toString (symbol : Symbol) : String := symbol.canonical

end Symbol

/-- Token kind. `keyword` keeps the canonical reserved-word spelling so that
ASCII and case-preserving spellings compare equal in the abstract syntax.
`integer` carries the value the profile's decimal, octal, hexadecimal, and
binary spellings normalize to, so no consumer re-reads a radix. -/
inductive TokenKind where
  | identifier
  | qualifiedName
  | keyword (canonical : String)
  | integer (value : Int)
  | string
  | symbol (symbol : Symbol)
  | moduleHeader
  | moduleEnd
  | eof
  deriving Repr, BEq, DecidableEq

namespace TokenKind

/-- `true` for the end-of-file marker. -/
def isEof : TokenKind → Bool
  | .eof => true
  | _ => false

/-- `true` when the kind is a reserved word with the given canonical spelling. -/
def isKeyword (kind : TokenKind) (canonical : String) : Bool :=
  match kind with
  | .keyword spelling => spelling == canonical
  | _ => false

/-- Canonical operator spelling when the kind is a symbol. -/
def symbolCanonical? : TokenKind → Option String
  | .symbol operator => some operator.canonical
  | _ => none

/-- Normalized value when the kind is an integer literal. -/
def integerValue? : TokenKind → Option Int
  | .integer value => some value
  | _ => none

end TokenKind

/-- A lossless token: kind, original spelling, byte range, and surrounding
trivia. -/
structure Token where
  kind : TokenKind
  spelling : String
  range : SourceRange
  leadingTrivia : Array Trivia
  trailingTrivia : Array Trivia
  deriving Repr, BEq

namespace Token

/-- The token and its attached trivia, in source order. -/
def text (token : Token) : String :=
  String.join <|
    (token.leadingTrivia.toList.map Trivia.spelling) ++
      [token.spelling] ++
      (token.trailingTrivia.toList.map Trivia.spelling)

/-- Byte length of the token spelling itself. -/
def byteLength (token : Token) : Nat := token.range.byteLength

/-- `true` for the end-of-file marker. -/
def isEof (token : Token) : Bool := token.kind.isEof

/-- Normalized value of an integer-literal token. -/
def integerValue? (token : Token) : Option Int := token.kind.integerValue?

private def dropWhile (predicate : Char → Bool) : List Char → List Char
  | [] => []
  | character :: rest =>
      if predicate character then dropWhile predicate rest else character :: rest

private def isHeaderBlank (character : Char) : Bool :=
  character == ' ' || character == '\t'

private def isHeaderDash (character : Char) : Bool := character == '-'

private def isHeaderWordChar (character : Char) : Bool :=
  isAsciiIdentifierChar character

private def takeWord (characters : List Char) : String × List Char :=
  let rec go (acc : List Char) (rest : List Char) : List Char × List Char :=
    match rest with
    | [] => (acc.reverse, [])
    | character :: tail =>
        if isHeaderWordChar character then go (character :: acc) tail
        else (acc.reverse, rest)
  let (word, rest) := go [] characters
  (String.ofList word, rest)

/-- Module name carried by a module-header token, when the token is a header.
The parser uses this instead of re-lexing the header line. -/
def moduleHeaderName? (token : Token) : Option String :=
  if token.kind != .moduleHeader then
    none
  else
    let afterDashes := dropWhile isHeaderDash token.spelling.toList
    let afterBlank := dropWhile isHeaderBlank afterDashes
    let (firstWord, rest) := takeWord afterBlank
    if firstWord != "MODULE" then
      none
    else
      let (name, trailing) := takeWord (dropWhile isHeaderBlank rest)
      if ModuleName.valid name then
        some name
      else
        let _ := trailing
        none

end Token

/-- A lossless token stream. A successful `lex` produces a stream whose final
token is `TokenKind.eof`; a stream never carries error diagnostics because
`Core.Tla.lex` returns failures as `Except.error`. -/
structure TokenStream where
  tokens : Array Token
  deriving Repr, BEq

namespace TokenStream

/-- Number of tokens, including the final `eof` token. -/
def tokenCount (stream : TokenStream) : Nat := stream.tokens.size

/-- Number of tokens that are not `eof` markers. -/
def contentTokenCount (stream : TokenStream) : Nat :=
  stream.tokens.foldl (fun total token => if token.isEof then total else total + 1) 0

/-- Reconstructed source text: every token and trivia spelling in order. -/
def text (stream : TokenStream) : String :=
  String.join (stream.tokens.toList.map Token.text)

/-- The final token when it is the end-of-file marker. -/
def eof? (stream : TokenStream) : Option Token :=
  match stream.tokens.back? with
  | some token => if token.isEof then some token else none
  | none => none

/-- Annotation trivia in source order. Leading and trailing attachments are
both included, and the order matches the source because a token's trailing
trivia always precedes the next token's leading trivia. -/
def annotations (stream : TokenStream) : Array Trivia :=
  stream.tokens.foldl (fun found token =>
    found ++ token.leadingTrivia.filter (fun item => item.kind == .annotation) ++
      token.trailingTrivia.filter (fun item => item.kind == .annotation)) #[]

/-- Reserved-word spellings in source order. Comments and strings never appear
here, which is what distinguishes a real `EXTENDS` from one mentioned inside
trivia. -/
def keywordSpellings (stream : TokenStream) : Array String :=
  stream.tokens.filterMap fun token =>
    match token.kind with
    | .keyword spelling => some spelling
    | _ => none

end TokenStream

end Core.Tla
