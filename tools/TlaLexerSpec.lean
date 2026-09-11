import Core.Tla.Lexer

/-!
# TLA+ lexer specification (tools/TlaLexerSpec.lean)

Pure, filesystem-free conformance suite for the TF1 foundation slice: source
units and identity, tokens and trivia, and the lexer
(`Docs/model-interface-compiler/tla-frontend-design.md`, §8 "Source units and
identity", §9 "Lexer", §20 "Diagnostics", §21 "Resource and security limits")
against the pinned revision-1 language profile
(`Docs/model-interface-compiler/tla-language-profile.md`).

The suite covers capture normalization and identity, module delimiters, the
reserved-word and operator vocabulary, numeric spellings, trivia and annotation
classification, lossless reconstruction, UTF-8 byte ranges with one-based
scalar columns, every lexer limit at the limit and at limit plus one, bracketed
hostile input, and deterministic fail-closed behavior. It reads no file, the
network, Apalache, or private model material: every case is an embedded literal
or a directly constructed byte array.

Two commands run it:

* `lake env lean tools/TlaLexerSpec.lean` — the elaboration check at the bottom
  of the file runs the suite, so a broken assertion fails this command;
* `lake env lean --run tools/TlaLexerSpec.lean` — the `main` driver the build
  graph may wire as a `lean_exe`.
-/

namespace TlaLexerSpec

open Core.Tla

/-! ## Harness -/

abbrev Failures := IO.Ref (List String)

def check (fails : Failures) (name : String) (ok : Bool)
    (detail : String := "") : IO Unit := do
  if !ok then
    fails.modify fun items =>
      items ++ [if detail.isEmpty then name else s!"{name}: {detail}"]

/-! ## Capture helpers -/

/-- Logical path used by every capture in this suite. Physical paths never
appear in the frontend. -/
def specPath : String := "specs/TlaLexerSpec.tla"

def captureText (logicalPath text : String) : SourceUnit :=
  SourceUnit.create .inlineSourceMap logicalPath text

def capture (text : String) : SourceUnit := captureText specPath text

/-- A capture whose bytes are supplied directly, which is how the suite reaches
invalid UTF-8 that a `String` cannot represent. -/
def captureBytes (logicalPath : String) (bytes : ByteArray) : SourceUnit :=
  { logicalPath
    normalizedText := ""
    normalizedUtf8 := bytes
    contentSha256 := Core.ModelInterface.Sha256.digestHex bytes
    origin := .inlineSourceMap }

def lexText (text : String) : Except (List Diagnostic) TokenStream :=
  lex LanguageProfile.default {} (capture text)

def lexWith (limits : LexerLimits) (text : String) :
    Except (List Diagnostic) TokenStream :=
  lex LanguageProfile.default limits (capture text)

def lexBytes (limits : LexerLimits) (bytes : ByteArray) :
    Except (List Diagnostic) TokenStream :=
  lex LanguageProfile.default limits (captureBytes specPath bytes)

/-- One scalar with the given code point, written without literal escapes. -/
def controlChar (code : Nat) : String := String.ofList [Char.ofNat code]

/-- U+1D538 MATHEMATICAL DOUBLE-STRUCK CAPITAL A, a four-byte scalar. The `\u`
escape covers the basic multilingual plane only, so the scalar is built from its
code point. -/
def mathbbA : String := String.ofList [Char.ofNat 0x1D538]

/-- `n` nested block comments around `x`: the shape of the profile's
comment-depth fixture. -/
def nestedComment (n : Nat) : String :=
  String.join (List.replicate n "(*") ++ "x" ++ String.join (List.replicate n "*)")

def repeated (count : Nat) (piece : String) : String :=
  String.join (List.replicate count piece)

/-- A half-open range used by the source-unit checks. -/
def sampleRange : SourceRange := ⟨⟨2, 1, 3⟩, ⟨5, 1, 6⟩⟩

/-- The profile's declared defaults. -/
def defaultLimits : LexerLimits := {}

/-- A diagnostic and budgets used by the buffer checks. -/
def sampleDiagnostic : Diagnostic :=
  Diagnostic.error "TLA-LEX-TEST" .lex "message"
    (SourceLocation.ofUnit (capture "x") ⟨⟨0, 1, 1⟩, ⟨0, 1, 1⟩⟩)

def sampleLimits : DiagnosticLimits := { maxCount := 1, maxBytes := 1024 }
def sampleLimitsZeroCount : DiagnosticLimits := { maxCount := 0, maxBytes := 1024 }
def sampleLimitsZeroBytes : DiagnosticLimits := { maxCount := 1, maxBytes := 0 }

/-! ## Result and stream views -/

def diagnostics : Except (List Diagnostic) TokenStream → List Diagnostic
  | .ok _ => []
  | .error items => items

def errorCodes (result : Except (List Diagnostic) TokenStream) : List String :=
  (diagnostics result).map Diagnostic.code

def streamOf? : Except (List Diagnostic) TokenStream → Option TokenStream
  | .ok stream => some stream
  | .error _ => none

def failed (result : Except (List Diagnostic) TokenStream) : Bool :=
  !(diagnostics result).isEmpty

/-- A structurally comparable view of a lexer result. `Except` itself carries no
`BEq` instance, so equal-run checks compare this key. -/
def resultKey (result : Except (List Diagnostic) TokenStream) :
    String × Option TokenStream × List Diagnostic :=
  match result with
  | .ok stream => ("ok", some stream, [])
  | .error items => ("error", none, items)

def failsWith (result : Except (List Diagnostic) TokenStream)
    (code : String) : Bool :=
  errorCodes result == [code]

def failsOn (result : Except (List Diagnostic) TokenStream)
    (code : String) : Bool :=
  (errorCodes result).contains code

def firstDiagnostic? : Except (List Diagnostic) TokenStream → Option Diagnostic
  | .ok _ => none
  | .error (item :: _) => some item
  | .error [] => none

def lastDiagnostic? : Except (List Diagnostic) TokenStream → Option Diagnostic
  | .ok _ => none
  | .error items => items.getLast?

def argument? (diagnostic : Diagnostic) (name : String) : Option String :=
  (diagnostic.arguments.toList.find? (fun argument => argument.1 == name)).map
    Prod.snd

def firstArgument? (result : Except (List Diagnostic) TokenStream)
    (name : String) : Option String :=
  (firstDiagnostic? result).bind (fun diagnostic => argument? diagnostic name)

def tokenList (stream : TokenStream) : List Token := stream.tokens.toList

def contentTokenList (stream : TokenStream) : List Token :=
  (tokenList stream).filter (fun token => !token.isEof)

def kindListOf (stream : TokenStream) : List TokenKind :=
  (tokenList stream).map Token.kind

def contentKindList (stream : TokenStream) : List TokenKind :=
  (contentTokenList stream).map Token.kind

def spellingListOf (stream : TokenStream) : List String :=
  (contentTokenList stream).map Token.spelling

def canonicalListOf (stream : TokenStream) : List String :=
  (tokenList stream).filterMap (fun token => token.kind.symbolCanonical?)

def integerListOf (stream : TokenStream) : List Int :=
  (tokenList stream).filterMap Token.integerValue?

def keywordListOf (stream : TokenStream) : List String :=
  stream.keywordSpellings.toList

def tokenAt? (stream : TokenStream) (index : Nat) : Option Token :=
  ((tokenList stream).drop index).head?

def contentAt? (stream : TokenStream) (index : Nat) : Option Token :=
  ((contentTokenList stream).drop index).head?

def canonicalAt? (stream : TokenStream) (index : Nat) : Option String :=
  (contentAt? stream index).bind (fun token => token.kind.symbolCanonical?)

def triviaList (stream : TokenStream) : List Trivia :=
  (tokenList stream).foldl (fun found token =>
    found ++ token.leadingTrivia.toList ++ token.trailingTrivia.toList) []

def triviaKindListOf (stream : TokenStream) : List TriviaKind :=
  (triviaList stream).map Trivia.kind

def triviaSpellingListOf (stream : TokenStream) : List String :=
  (triviaList stream).map Trivia.spelling

def annotationFacts (stream : TokenStream) : List (String × String) :=
  (triviaList stream).filterMap fun item =>
    match item.annotationKind, item.annotationPayload with
    | some kind, some payload => some (kind, payload)
    | _, _ => none

/-! ## Text-level assertions -/

def kindList (text : String) : List TokenKind :=
  match lexText text with
  | .ok stream => kindListOf stream
  | .error _ => []

def contentKinds (text : String) : List TokenKind :=
  match lexText text with
  | .ok stream => contentKindList stream
  | .error _ => []

def spellingList (text : String) : List String :=
  match lexText text with
  | .ok stream => spellingListOf stream
  | .error _ => []

def canonicalList (text : String) : List String :=
  match lexText text with
  | .ok stream => canonicalListOf stream
  | .error _ => []

def integerList (text : String) : List Int :=
  match lexText text with
  | .ok stream => integerListOf stream
  | .error _ => []

def keywordList (text : String) : List String :=
  match lexText text with
  | .ok stream => keywordListOf stream
  | .error _ => []

def triviaKindList (text : String) : List TriviaKind :=
  match lexText text with
  | .ok stream => triviaKindListOf stream
  | .error _ => []

def annotationList (text : String) : List (String × String) :=
  match lexText text with
  | .ok stream => annotationFacts stream
  | .error _ => []

/-- One-based line and scalar column of `targetOffset`, or `none` when the
offset is not a scalar boundary. This walk is independent of the lexer's own
position counters, so it verifies scalar-column accounting rather than
restating it. -/
def positionOf (text : String) (targetOffset : Nat) : Option (Nat × Nat) :=
  let rec walk (characters : List Char) (offset line column : Nat) :
      Option (Nat × Nat) :=
    if offset == targetOffset then
      some (line, column)
    else if offset > targetOffset then
      none
    else
      match characters with
      | [] => none
      | character :: rest =>
          let width := character.toString.toUTF8.size
          if character == '\n' then
            walk rest (offset + width) (line + 1) 1
          else
            walk rest (offset + width) line (column + 1)
  walk text.toList 0 1 1

def sliceOf (bytes : ByteArray) (range : SourceRange) : Option String :=
  String.fromUTF8? (bytes.extract range.start.offset range.stop.offset)

/-- Every token and trivia spelling equals the bytes its range selects. -/
def rangesAgree (unit : SourceUnit) (stream : TokenStream) : Bool :=
  (tokenList stream).all fun token =>
    token.range.wellFormed &&
      sliceOf unit.normalizedUtf8 token.range == some token.spelling &&
      (token.leadingTrivia.toList ++ token.trailingTrivia.toList).all
        (fun item =>
          item.range.wellFormed &&
            sliceOf unit.normalizedUtf8 item.range == some item.spelling)

private def coverTrivia (cursor : Nat) (items : List Trivia) : Nat × Bool :=
  items.foldl (fun (state : Nat × Bool) item =>
    (item.range.stop.offset,
      state.2 && item.range.wellFormed && item.range.start.offset == state.1))
    (cursor, true)

/-- Trivia and token ranges tile the capture: they start at byte zero, never
leave a gap or an overlap, follow each other, and end at the capture size. -/
def coversSource (unit : SourceUnit) (stream : TokenStream) : Bool :=
  let final := (tokenList stream).foldl (fun (state : Nat × Bool) token =>
    let leading := coverTrivia state.1 token.leadingTrivia.toList
    let tokenStop :=
      (token.range.stop.offset,
        leading.2 && token.range.wellFormed && token.range.start.offset == leading.1)
    coverTrivia tokenStop.1 token.trailingTrivia.toList)
    (0, true)
  final.2 && final.1 == unit.normalizedUtf8.size

/-- Token and trivia positions agree with the independent scalar walk. -/
def positionsAgree (unit : SourceUnit) (stream : TokenStream) : Bool :=
  (tokenList stream).all fun token =>
    positionOf unit.normalizedText token.range.start.offset ==
        some (token.range.start.line, token.range.start.column) &&
      positionOf unit.normalizedText token.range.stop.offset ==
        some (token.range.stop.line, token.range.stop.column) &&
      (token.leadingTrivia.toList ++ token.trailingTrivia.toList).all
        (fun item =>
          positionOf unit.normalizedText item.range.start.offset ==
              some (item.range.start.line, item.range.start.column) &&
            positionOf unit.normalizedText item.range.stop.offset ==
              some (item.range.stop.line, item.range.stop.column))

/-- The lossless property: concatenated token and trivia spellings reproduce the
normalized capture exactly. -/
def lossless (unit : SourceUnit) (stream : TokenStream) : Bool :=
  stream.text == unit.normalizedText

/-! ## Scenarios -/

def scenarioSourceUnits (fails : Failures) : IO Unit := do
  let unit := capture "a\r\nb\rc"
  check fails "source: CRLF and lone CR normalize to LF"
    (unit.normalizedText == "a\nb\nc") s!"text={unit.normalizedText.length} bytes"
  check fails "source: normalized UTF-8 follows normalized text"
    (unit.normalizedUtf8 == "a\nb\nc".toUTF8)
  check fails "source: digest hashes normalized UTF-8, not the raw capture"
    (unit.contentSha256 == Core.ModelInterface.Sha256.digestHex "a\nb\nc".toUTF8)
  check fails "source: capture is self-consistent" unit.consistent
  let identity := unit.identity ⟨"SourceProbe"⟩
  check fails "source: identity carries module name, logical path, and digest"
    (identity.moduleName == ⟨"SourceProbe"⟩ && identity.logicalPath == specPath &&
      identity.contentSha256 == unit.contentSha256)
  check fails "source: module names accept letters, digits, and underscore"
    (ModuleName.valid "Foo_1" && ModuleName.valid "_x" &&
      !ModuleName.valid "9Foo" && !ModuleName.valid "Foo-Bar" &&
      !ModuleName.valid "")
  check fails "source: checked module-name constructor rejects invalid spellings"
    ((ModuleName.ofString? "A1").map ModuleName.toString == some "A1" &&
      ModuleName.ofString? "A1!" == none)
  check fails "source: range helpers are half open"
    (sampleRange.byteLength == 3 && !sampleRange.isEmpty &&
      sampleRange.wellFormed &&
      (SourceRange.wellFormed ⟨⟨5, 1, 6⟩, ⟨2, 1, 3⟩⟩ == false))

def scenarioModuleDelimiters (fails : Failures) : IO Unit := do
  check fails "delimiters: module header is one lossless token carrying its name"
    (match lexText "---- MODULE Foo ----\n" with
      | .ok stream =>
          kindListOf stream == [.moduleHeader, .eof] &&
            (tokenAt? stream 0).bind Token.moduleHeaderName? == some "Foo"
      | .error _ => false)
  check fails "delimiters: five dashes and no space are still a header"
    (kindList "----- MODULE Foo -----\n" == [.moduleHeader, .eof] &&
      kindList "----MODULE Foo ----\n" == [.moduleHeader, .eof])
  check fails "delimiters: three leading dashes are operator tokens"
    (match lexText "--- MODULE Foo ---\n" with
      | .ok stream =>
          canonicalAt? stream 0 == some "-" && canonicalAt? stream 1 == some "-" &&
            (tokenAt? stream 0).bind Token.moduleHeaderName? == none
      | .error _ => false)
  check fails "delimiters: an invalid module name is not a header"
    (match lexText "---- MODULE 9Foo ----\n" with
      | .ok stream =>
          canonicalAt? stream 0 == some "-" &&
            !(kindListOf stream).contains .moduleHeader
      | .error _ => false)
  check fails "delimiters: trailing text after the header dashes is not a header"
    (match lexText "---- MODULE Foo ---- x\n" with
      | .ok stream => !(kindListOf stream).contains .moduleHeader
      | .error _ => false)
  check fails "delimiters: module end accepts four or more equals at line start"
    (kindList "====\n" == [.moduleEnd, .eof] &&
      kindList "=====\n" == [.moduleEnd, .eof] &&
      (match lexText "====\n" with
        | .ok stream => canonicalAt? stream 0 == none &&
            (contentAt? stream 0).map Token.spelling == some "===="
        | .error _ => false))
  check fails "delimiters: three equals are operator tokens"
    (canonicalList "===\n" == ["==", "="])
  check fails "delimiters: an indented or inline equals run is not a module end"
    (!(kindList "  ====\n").contains .moduleEnd &&
      !(kindList "x ====\n").contains .moduleEnd)
  check fails "delimiters: a complete module keeps header and end order"
    (match lexText "---- MODULE M ----\n\nx == 1\n\n====\n" with
      | .ok stream =>
          (tokenAt? stream 0).map Token.kind == some .moduleHeader &&
            (contentTokenList stream).getLast?.map Token.kind == some .moduleEnd &&
            stream.eof?.isSome
      | .error _ => false)

def scenarioVocabulary (fails : Failures) : IO Unit := do
  let keywordSample : String := String.intercalate " " [
    "ASSUME", "ASSUMPTION", "AXIOM", "BOOLEAN", "BY", "CASE", "CHOOSE",
    "CONSTANT", "CONSTANTS", "COROLLARY", "DEF", "DEFS", "DOMAIN", "ELSE",
    "ENABLED", "EXCEPT", "EXTENDS", "FALSE", "HAVE", "HIDE", "IF", "IN",
    "INSTANCE", "LEMMA", "LET", "LOCAL", "MODULE", "NEW", "OBVIOUS", "OMITTED",
    "ONLY", "OTHER", "PICK", "PROOF", "PROPOSITION", "PROVE", "QED",
    "RECURSIVE", "STATE", "STRING", "SUBSET", "TAKE", "THEOREM", "THEN",
    "TRUE", "UNCHANGED", "UNION", "VARIABLE", "VARIABLES", "WHEN", "WITNESS",
    "WITH"]
  check fails "vocabulary: every reserved word is a keyword token"
    (keywordList keywordSample == keywordSample.splitOn " ")
  check fails "vocabulary: BOOLEAN and STRING are reserved words"
    (keywordList "BOOLEAN STRING" == ["BOOLEAN", "STRING"] &&
      (keywordList "boolean string").isEmpty)
  check fails "vocabulary: lower-case spellings stay identifiers"
    (keywordList "module constant" == [] &&
      spellingList "module constant" == ["module", "constant"])
  check fails "vocabulary: WF_ and SF_ split from their subscripts"
    (spellingList "WF_vars(Next)" == ["WF_", "vars", "(", "Next", ")"] &&
      keywordList "WF_vars(Next)" == ["WF_"] &&
      keywordList "SF_x" == ["SF_"] &&
      keywordList "WF" == [] && spellingList "WF" == ["WF"] &&
      spellingList "xWF_y" == ["xWF_y"])
  check fails "vocabulary: qualified names are one token"
    (contentKinds "A!B!C" == [.qualifiedName] &&
      spellingList "A!B!C" == ["A!B!C"] &&
      spellingList "A ! B" == ["A", "!", "B"] &&
      canonicalList "A ! B" == ["!"] &&
      spellingList "A!" == ["A", "!"] &&
      canonicalList "A!" == ["!"])
  check fails "vocabulary: identifiers keep their original spelling"
    (spellingList "_x1 y_2" == ["_x1", "y_2"] &&
      spellingList "x'" == ["x", "'"] && canonicalList "x'" == ["'"])

def scenarioSymbols (fails : Failures) : IO Unit := do
  let aliasPairs : List (String × String) := [
    ("/\\", "\\land"), ("\\/", "\\lor"), ("~", "\\lnot"), ("~", "\\neg"),
    ("<=>", "\\equiv"), ("#", "/="), ("=<", "<="), ("=<", "\\leq"),
    (">=", "\\geq"), ("\\cup", "\\union"), ("\\cap", "\\intersect"),
    ("\\X", "\\times")]
  check fails "symbols: ASCII and word spellings share one canonical spelling"
    (aliasPairs.all (fun pair => canonicalList pair.1 == canonicalList pair.2))
  check fails "symbols: the original spelling survives canonicalization"
    (spellingList "x \\land y" == ["x", "\\land", "y"] &&
      canonicalList "x \\land y" == ["/\\"])
  check fails "symbols: structural punctuation keeps its spelling"
    (canonicalList "( ) [ ] { } ," == ["(", ")", "[", "]", "{", "}", ","])
  check fails "symbols: an operator run decomposes at known aliases"
    (canonicalList "++" == ["+", "+"] && canonicalList "***" == ["*", "*", "*"] &&
      canonicalList "<>[]<->" == ["<>", "[]", "<-", ">"] &&
      canonicalList "<<>>" == ["<<", ">>"] && canonicalList "===" == ["==", "="])
  check fails "symbols: temporal, action, and prefix operators are recognized"
    (canonicalList "[] <> ~> -> <- .. |-> ' ! @ : ;" ==
      ["[]", "<>", "~>", "->", "<-", "..", "|->", "'", "!", "@", ":", ";"])
  check fails "symbols: user-defined operator words stay symbolic"
    (canonicalList "a \\oplus b" == ["\\oplus"] &&
      canonicalList "\\prec \\succ \\bigcirc \\A \\E" ==
        ["\\prec", "\\succ", "\\bigcirc", "\\A", "\\E"] &&
      canonicalList "\\hG" == ["\\hG"])
  check fails "symbols: a backslash word stops at the first non-identifier scalar"
    (spellingList "\\oplus+" == ["\\oplus", "+"])

def scenarioNumerics (fails : Failures) : IO Unit := do
  check fails "numerics: decimal integers normalize to values"
    (integerList "0 1 42 007" == [0, 1, 42, 7])
  check fails "numerics: radix spellings normalize without re-reading a radix"
    (integerList "\\o377 \\hFF \\b11111111 \\h0 \\o10" == [255, 255, 255, 0, 8])
  check fails "numerics: a radix prefix needs an adjacent digit"
    (integerList "\\o 10" == [10] && canonicalList "\\o 10" == ["\\o"])
  check fails "numerics: a digit outside the radix is an invalid number"
    (failsWith (lexText "\\o19\n") LexCode.invalidNumber &&
      firstArgument? (lexText "\\o19\n") "radix" == some "8" &&
      failsWith (lexText "\\b12\n") LexCode.invalidNumber &&
      firstArgument? (lexText "\\b12\n") "radix" == some "2")
  check fails "numerics: decimal fractions and exponents are staged out"
    (["1.5", "1.5e3", "1e3", "2E+4", "0.5"].all
      (fun text => failsOn (lexText text) LexCode.invalidNumber))
  check fails "numerics: an unsupported spelling never yields a value"
    (((streamOf? (lexText "1.5")).map integerListOf) == none)

def scenarioTrivia (fails : Failures) : IO Unit := do
  check fails "trivia: line and block comments keep their spelling"
    (match lexText "\\* line\n(* block *)\nx\n" with
      | .ok stream =>
          triviaSpellingListOf stream ==
              ["\\* line", "\n", "(* block *)", "\n", "\n"] &&
            triviaKindListOf stream ==
              [.lineComment, .newline, .blockComment, .newline, .newline]
      | .error _ => false)
  check fails "trivia: comments nest without ending at an inner terminator"
    (match lexText "(* a (* b *) c *)x\n" with
      | .ok stream =>
          (triviaList stream).head?.map Trivia.spelling == some "(* a (* b *) c *)" &&
            triviaKindListOf stream == [.blockComment, .newline]
      | .error _ => false)
  check fails "trivia: a comment-adjacent newline is separate trivia"
    (triviaKindList "(* a\nb *)\n" == [.blockComment, .newline])
  check fails "trivia: trailing trivia follows the token before the line break"
    (match lexText "  x\n\n  y  \n" with
      | .ok stream =>
          match tokenAt? stream 0, tokenAt? stream 1, tokenAt? stream 2 with
          | some first, some second, some last =>
              first.leadingTrivia.toList.map Trivia.spelling == ["  "] &&
                first.trailingTrivia.isEmpty &&
                second.leadingTrivia.toList.map Trivia.spelling == ["\n", "\n", "  "] &&
                second.trailingTrivia.toList.map Trivia.spelling == ["  "] &&
                last.isEof &&
                last.leadingTrivia.toList.map Trivia.spelling == ["\n"]
          | _, _, _ => false
      | .error _ => false)
  check fails "trivia: annotation comments carry kind and payload"
    (annotationList "\\* @type: Int;\n" == [("apalache.type", "Int")] &&
      annotationList "\\* @type Int\n" == [("apalache.type", "Int")] &&
      annotationList "\\* @ 5\n" == [("annotation", "5")] &&
      annotationList "(* @foo bar *)x\n" == [("annotation:foo", "bar")] &&
      annotationList "(*\n  @type: Int;\n*)x\n" == [("apalache.type", "Int")] &&
      (annotationList "(* out (* @type: Int; *) *)\n").isEmpty)
  check fails "trivia: an annotation is classified as annotation trivia"
    (triviaKindList "\\* @type: Int;\n" == [.annotation, .newline] &&
      triviaKindList "\\* plain\n" == [.lineComment, .newline] &&
      triviaKindList "(* plain *)\n" == [.blockComment, .newline])
  check fails "trivia: annotations are exposed in source order"
    (annotationList "\\* @type: Int;\n\\* @foo: bar;\nx == 1\n" ==
      [("apalache.type", "Int"), ("annotation:foo", "bar")])
  check fails "trivia: a line comment may end the file without a newline"
    (match lexText "x \\* tail" with
      | .ok stream =>
          triviaKindListOf stream == [.whitespace, .lineComment] && stream.eof?.isSome
      | .error _ => false)

def losslessCorpus : List String := [
  "",
  "   ",
  "x",
  "x\n",
  "---- MODULE M ----\n\nEXTENDS Integers\n\nVARIABLES a, b\n\nInit == a = 0\n\nNext == a' = a + 1\n\n====\n",
  "\\* @type: Int;\nx\n",
  "(* nested (* comment *) here *)\nx\n",
  "\"quoted \\\" text\\\\\"\n",
  "a\r\nb\rc\nd",
  "x /\\ y \\/ ~z <=> (a =< b)\n",
  "WF_vars(Next) /\\ SF_x(Other)\n",
  "\\o377 + \\hFF + \\b1010 - 007\n",
  "[]<>[][Next]_vars\n",
  "(*\r\n  @type: Set(Int);\r\n*)\r\nS == {1, 2, 3}\n"
]

def scenarioLosslessness (fails : Failures) : IO Unit := do
  check fails "lossless: every corpus capture lexes"
    (losslessCorpus.all (fun text => (streamOf? (lexText text)).isSome))
  check fails "lossless: token and trivia spellings reproduce the capture"
    (losslessCorpus.all fun text =>
      match lexText text with
      | .ok stream => lossless (capture text) stream
      | .error _ => false)
  check fails "lossless: ranges select the bytes they claim"
    (losslessCorpus.all fun text =>
      match lexText text with
      | .ok stream => rangesAgree (capture text) stream
      | .error _ => false)
  check fails "lossless: ranges tile the capture without gaps"
    (losslessCorpus.all fun text =>
      match lexText text with
      | .ok stream => coversSource (capture text) stream
      | .error _ => false)
  check fails "lossless: line and scalar column agree with an independent walk"
    (losslessCorpus.all fun text =>
      match lexText text with
      | .ok stream => positionsAgree (capture text) stream
      | .error _ => false)
  check fails "lossless: the stream ends with exactly one eof token"
    (losslessCorpus.all fun text =>
      match lexText text with
      | .ok stream =>
          stream.eof?.isSome && (tokenList stream).getLast?.map Token.isEof == some true
      | .error _ => false)
  check fails "lossless: interleaved trivia and tokens rebuild the capture"
    (losslessCorpus.all fun text =>
      match lexText text with
      | .ok stream =>
          let pieces := (tokenList stream).foldl (fun found token =>
            found ++ token.leadingTrivia.toList.map Trivia.spelling ++
              [token.spelling] ++ token.trailingTrivia.toList.map Trivia.spelling)
            []
          String.join pieces == (capture text).normalizedText
      | .error _ => false)
  check fails "lossless: the eof token sits at the end of the capture"
    (losslessCorpus.all fun text =>
      match lexText text with
      | .ok stream =>
          stream.eof?.map (fun token => token.range.start.offset ==
            (capture text).normalizedUtf8.size) == some true
      | .error _ => false)

def scenarioMultibyte (fails : Failures) : IO Unit := do
  check fails "positions: multibyte scalars advance columns once and offsets by bytes"
    (match lexText ("(* " ++ "\u00e9\u00e9\u00e9" ++ " " ++ mathbbA ++ " *) X\n") with
      | .ok stream =>
          (contentAt? stream 0).map (fun token =>
            (token.spelling, token.range.start.offset, token.range.start.line,
              token.range.start.column)) == some ("X", 18, 1, 13)
      | .error _ => false)
  check fails "positions: a comment before a token shifts the token position"
    (match lexText "(* \u00e9 *) x\n" with
      | .ok stream =>
          (contentAt? stream 0).map (fun token =>
            (token.range.start.offset, token.range.start.column)) == some (9, 9)
      | .error _ => false)
  check fails "positions: eof follows the last line break"
    (match lexText "a\n" with
      | .ok stream =>
          stream.eof?.map (fun token =>
            (token.range.start.offset, token.range.start.line,
              token.range.start.column)) == some (2, 2, 1)
      | .error _ => false)
  check fails "positions: eof after text without a final newline"
    (match lexText "a" with
      | .ok stream =>
          stream.eof?.map (fun token =>
            (token.range.start.offset, token.range.start.line,
              token.range.start.column)) == some (1, 1, 2)
      | .error _ => false)
  check fails "positions: a multibyte scalar outside a comment is a diagnostic"
    (match lexText "\u00b6" with
      | .error (diagnostic :: _) =>
          diagnostic.code == LexCode.unknownCharacter &&
            argument? diagnostic "spelling" == some "\u00b6" &&
            argument? diagnostic "code" == some "182" &&
            diagnostic.primary.range.stop.offset - diagnostic.primary.range.start.offset == 2
      | _ => false)
  check fails "positions: a four-byte scalar reports its full byte range"
    (match lexText mathbbA with
      | .error (diagnostic :: _) =>
          diagnostic.code == LexCode.unknownCharacter &&
            argument? diagnostic "spelling" == some mathbbA &&
            diagnostic.primary.range.stop.offset - diagnostic.primary.range.start.offset == 4
      | _ => false)
  check fails "positions: a staged Unicode operator names its spelling"
    (failsWith (lexText "\u225c") LexCode.unicodeStaged &&
      firstArgument? (lexText "\u225c") "spelling" == some "\u225c")
  check fails "positions: multibyte scalars inside a string stay lossless"
    (match lexText "\"\u00e9\"\n" with
      | .ok stream =>
          spellingListOf stream == ["\"\u00e9\""] &&
            lossless (capture "\"\u00e9\"\n") stream
      | .error _ => false)

def scenarioFailures (fails : Failures) : IO Unit := do
  check fails "failures: an unknown ASCII-range scalar is rejected"
    (failsWith (lexText "\u00a4") LexCode.unknownCharacter &&
      firstArgument? (lexText "\u00a4") "spelling" == some "\u00a4" &&
      firstArgument? (lexText "\u00a4") "code" == some "164")
  check fails "failures: staged Unicode operators name the spelling"
    (failsWith (lexText "x \u2227 y\n") LexCode.unicodeStaged &&
      firstArgument? (lexText "x \u2227 y\n") "spelling" == some "\u2227" &&
      firstArgument? (lexText "x \u2227 y\n") "code" == some "8743")
  check fails "failures: control characters are rejected with their code"
    (failsWith (lexText (controlChar 0)) LexCode.controlCharacter &&
      firstArgument? (lexText (controlChar 0)) "code" == some "0" &&
      failsWith (lexText (controlChar 0x7F)) LexCode.controlCharacter &&
      firstArgument? (lexText (controlChar 0x7F)) "code" == some "127" &&
      failsWith (lexText (controlChar 0x85)) LexCode.controlCharacter &&
      firstArgument? (lexText (controlChar 0x85)) "code" == some "133")
  check fails "failures: tab and newline are not control characters"
    ((streamOf? (lexText "a\tb\nc\n")).isSome)
  check fails "failures: control characters are rejected inside comments and strings"
    (failsWith (lexText ("(* a" ++ controlChar 1 ++ " *)")) LexCode.controlCharacter &&
      failsWith (lexText ("\"a" ++ controlChar 1 ++ "b\"")) LexCode.controlCharacter)
  check fails "failures: an unterminated string at end of source"
    (failsWith (lexText "\"ab") LexCode.unterminatedString)
  check fails "failures: a newline inside a string"
    (failsOn (lexText "\"ab\ncd\"\n") LexCode.newlineInString)
  check fails "failures: an unsupported string escape names the escape"
    (failsWith (lexText "\"a\\qb\"") LexCode.invalidEscape &&
      firstArgument? (lexText "\"a\\qb\"") "escape" == some "\\q")
  check fails "failures: supported string escapes are accepted"
    ((streamOf? (lexText "\"a\\nb\\\"c\\\\d\"\n")).isSome)
  check fails "failures: an unterminated block comment"
    (failsWith (lexText "(* ab\n") LexCode.unterminatedComment &&
      failsWith (lexText "(* ab") LexCode.unterminatedComment)
  check fails "failures: comment nesting stops at the configured depth"
    ((streamOf? (lexText (nestedComment 64))).isSome &&
      failsWith (lexText (nestedComment 65)) LexCode.commentNesting &&
      firstArgument? (lexText (nestedComment 65)) "limit" == some "64")
  check fails "failures: every rejected sample carries at least one diagnostic"
    (["\u00a4", controlChar 1, "\"ab", "(* ab", "1.5", "\u2227",
        nestedComment 65].all fun text => failed (lexText text))

def scenarioInvalidUtf8 (fails : Failures) : IO Unit := do
  let cases : List (String × ByteArray × String × Nat) := [
    ("lone continuation byte", ByteArray.mk #[0x61, 0x80, 0x62],
      "unexpectedContinuationByte", 1),
    ("truncated three-byte sequence", ByteArray.mk #[0x61, 0xE2, 0x82],
      "truncatedSequence", 1),
    ("truncated four-byte sequence", ByteArray.mk #[0x61, 0xF0, 0x9F],
      "truncatedSequence", 1),
    ("overlong encoding", ByteArray.mk #[0xC0, 0xAF], "overlongEncoding", 0),
    ("surrogate code point", ByteArray.mk #[0xED, 0xA0, 0x80],
      "surrogateCodePoint", 0),
    ("scalar above U+10FFFF", ByteArray.mk #[0xF5, 0x80, 0x80, 0x80],
      "codePointOutOfRange", 0),
    ("invalid lead byte", ByteArray.mk #[0xFF], "codePointOutOfRange", 0)]
  for (name, bytes, problem, offset) in cases do
    check fails s!"invalid utf8: {name} is rejected as invalid UTF-8"
      (failsOn (lexBytes {} bytes) LexCode.invalidUtf8 &&
        firstArgument? (lexBytes {} bytes) "problem" == some problem &&
        (firstDiagnostic? (lexBytes {} bytes)).map
          (fun diagnostic => diagnostic.primary.range.start.offset) == some offset)
  check fails "invalid utf8: valid multibyte bytes decode instead of failing UTF-8"
    (!failsOn (lexBytes {} "\u00e9".toUTF8) LexCode.invalidUtf8 &&
      failsOn (lexBytes {} "\u00e9".toUTF8) LexCode.unknownCharacter)
  check fails "invalid utf8: an empty byte capture is an empty stream"
    (match lexBytes {} (ByteArray.mk #[]) with
      | .ok stream => stream.contentTokenCount == 0 && stream.eof?.isSome &&
          coversSource (captureBytes specPath (ByteArray.mk #[])) stream
      | .error _ => false)
  check fails "invalid utf8: a trailing truncated sequence is reported"
    (failsOn (lexBytes {} (ByteArray.mk #[0x61, 0xC3])) LexCode.invalidUtf8 &&
      firstArgument? (lexBytes {} (ByteArray.mk #[0x61, 0xC3])) "problem" ==
        some "truncatedSequence")

def scenarioLimits (fails : Failures) : IO Unit := do
  let limitCase (name : String) (code : String)
      (atLimit plusOne : Except (List Diagnostic) TokenStream) : IO Unit := do
    check fails s!"limits: {name} accepts the limit value"
      (!failsOn atLimit code) s!"codes={errorCodes atLimit}"
    check fails s!"limits: {name} rejects limit plus one"
      (failsOn plusOne code) s!"codes={errorCodes plusOne}"
    check fails s!"limits: {name} failure is deterministic"
      (errorCodes plusOne == errorCodes plusOne)
  limitCase "maxSourceBytes" LexCode.sourceTooLarge
    (lexWith { maxSourceBytes := 32 } (repeated 32 "a"))
    (lexWith { maxSourceBytes := 32 } (repeated 33 "a"))
  check fails "limits: maxSourceBytes counts bytes, not scalars"
    ((streamOf? (lexWith { maxSourceBytes := 32 }
        ("(* " ++ repeated 13 "\u00e9" ++ " *)"))).isSome &&
      failsOn (lexWith { maxSourceBytes := 32 }
        ("(* " ++ repeated 14 "\u00e9" ++ " *)")) LexCode.sourceTooLarge)
  limitCase "maxTokens" LexCode.tooManyTokens
    (lexWith { maxTokens := 3 } "a b c")
    (lexWith { maxTokens := 3 } "a b c d")
  check fails "limits: maxTokens ignores trailing trivia"
    ((streamOf? (lexWith { maxTokens := 3 } "a b c  \n")).isSome)
  limitCase "maxTokenBytes" LexCode.tokenTooLarge
    (lexWith { maxTokenBytes := 4 } "abcd")
    (lexWith { maxTokenBytes := 4 } "abcde")
  check fails "limits: maxTokenBytes does not bound comment trivia"
    (!failsOn (lexWith { maxTokenBytes := 4 } "(* abcd *)\nx\n")
      LexCode.tokenTooLarge)
  limitCase "maxIdentifierBytes" LexCode.identifierTooLarge
    (lexWith { maxIdentifierBytes := 4 } "abcd")
    (lexWith { maxIdentifierBytes := 4 } "abcde")
  check fails "limits: maxIdentifierBytes applies to each qualified part"
    ((streamOf? (lexWith { maxIdentifierBytes := 4 } "A!abcd")).isSome &&
      failsOn (lexWith { maxIdentifierBytes := 4 } "A!abcde")
        LexCode.identifierTooLarge &&
      firstArgument? (lexWith { maxIdentifierBytes := 4 } "A!abcde") "observed" ==
        some "5")
  check fails "limits: maxIdentifierBytes matches the frozen profile value"
    ((streamOf? (lexText (repeated 256 "a"))).isSome &&
      failsOn (lexText (repeated 257 "a")) LexCode.identifierTooLarge)
  limitCase "maxIntegerDigits" LexCode.integerTooLarge
    (lexWith { maxIntegerDigits := 4 } "1234")
    (lexWith { maxIntegerDigits := 4 } "12345")
  check fails "limits: maxIntegerDigits bounds radix spellings too"
    ((streamOf? (lexWith { maxIntegerDigits := 4 } "\\hFFFF")).isSome &&
      failsOn (lexWith { maxIntegerDigits := 4 } "\\hFFFFF")
        LexCode.integerTooLarge &&
      firstArgument? (lexWith { maxIntegerDigits := 4 } "\\hFFFFF") "limit" ==
        some "4")
  limitCase "maxCommentDepth" LexCode.commentNesting
    (lexWith { maxCommentDepth := 2 } (nestedComment 2))
    (lexWith { maxCommentDepth := 2 } (nestedComment 3))
  check fails "limits: maxCommentDepth matches the frozen profile value"
    ((streamOf? (lexText (nestedComment 64))).isSome &&
      failsOn (lexText (nestedComment 65)) LexCode.commentNesting)

def scenarioDiagnosticBudgets (fails : Failures) : IO Unit := do
  check fails "budgets: maxDiagnostics keeps exactly the limit"
    (errorCodes (lexWith { maxDiagnostics := 2 } (repeated 2 (controlChar 1))) ==
      [LexCode.controlCharacter, LexCode.controlCharacter] &&
      errorCodes (lexWith { maxDiagnostics := 3 } (repeated 3 (controlChar 1))) ==
        [LexCode.controlCharacter, LexCode.controlCharacter,
          LexCode.controlCharacter])
  check fails "budgets: maxDiagnostics plus one truncates with a notice"
    (failsOn (lexWith { maxDiagnostics := 2 } (repeated 3 (controlChar 1)))
        LexCode.diagnosticsTruncated &&
      (errorCodes (lexWith { maxDiagnostics := 2 } (repeated 3 (controlChar 1)))).length == 3 &&
      (lastDiagnostic? (lexWith { maxDiagnostics := 2 } (repeated 3 (controlChar 1)))).bind
        (fun diagnostic => argument? diagnostic "dropped") == some "1")
  check fails "budgets: a zero diagnostic count fails closed"
    (failsWith (lexWith { maxDiagnostics := 0 } (controlChar 1))
      LexCode.diagnosticsTruncated)
  match lexText (controlChar 1) with
  | .error (diagnostic :: _) =>
      let weight := Diagnostic.byteWeight diagnostic
      check fails "budgets: a diagnostic fits its own byte weight"
        (failsWith (lexWith { maxDiagnosticBytes := weight } (controlChar 1))
            LexCode.controlCharacter &&
          !failsOn (lexWith { maxDiagnosticBytes := weight } (controlChar 1))
            LexCode.diagnosticsTruncated)
      check fails "budgets: one byte less truncates the diagnostic"
        (failsWith (lexWith { maxDiagnosticBytes := weight - 1 } (controlChar 1))
            LexCode.diagnosticsTruncated &&
          (lastDiagnostic? (lexWith { maxDiagnosticBytes := weight - 1 }
            (controlChar 1))).bind (fun item => argument? item "dropped") == some "1")
  | _ =>
      check fails "budgets: the control-character sample reports a diagnostic" false
  match lexText "\"a\\qb\"" with
  | .error (diagnostic :: _) =>
      let weight := Diagnostic.byteWeight diagnostic
      check fails "budgets: a token-scan diagnostic fits its own byte weight"
        (failsWith (lexWith { maxDiagnosticBytes := weight } "\"a\\qb\"")
          LexCode.invalidEscape)
      check fails "budgets: one byte less truncates a token-scan diagnostic"
        (failsWith (lexWith { maxDiagnosticBytes := weight - 1 } "\"a\\qb\"")
          LexCode.diagnosticsTruncated)
  | _ =>
      check fails "budgets: the invalid-escape sample reports a diagnostic" false

def scenarioTermination (fails : Failures) : IO Unit := do
  let hostile := repeated 1000 (controlChar 1)
  check fails "termination: a thousand control scalars stay bounded"
    (failsOn (lexWith { maxDiagnostics := 4 } hostile) LexCode.controlCharacter &&
      (errorCodes (lexWith { maxDiagnostics := 4 } hostile)).length <= 5 &&
      failsOn (lexWith { maxDiagnostics := 4 } hostile) LexCode.diagnosticsTruncated)
  check fails "termination: a positive token followed by control scalars stays bounded"
    (failed (lexWith { maxDiagnostics := 4 } ("a " ++ hostile)) &&
      (errorCodes (lexWith { maxDiagnostics := 4 } ("a " ++ hostile))).length <= 5)
  check fails "termination: a dropped pre-scan problem still fails closed"
    (failsWith (lexWith { maxDiagnostics := 0 } (controlChar 1))
        LexCode.diagnosticsTruncated &&
      failsWith (lexWith { maxDiagnosticBytes := 1 } (controlChar 1))
        LexCode.diagnosticsTruncated &&
      failsWith (lexWith { maxDiagnostics := 0 } ("a" ++ controlChar 1))
        LexCode.diagnosticsTruncated)
  check fails "termination: an oversized identifier fails instead of folding"
    (failsOn (lexText (repeated 4096 "a")) LexCode.identifierTooLarge &&
      firstArgument? (lexText (repeated 4096 "a")) "observed" == some "4096")
  check fails "termination: a long operator run still terminates"
    (match lexText (repeated 512 "+") with
      | .ok stream => stream.contentTokenCount == 512
      | .error _ => false)

def scenarioDeterminism (fails : Failures) : IO Unit := do
  let samples : List String := losslessCorpus ++ [
    "\u00b6", "\u2227", controlChar 1, "\"ab", "(* ab", "1.5", nestedComment 65,
    "\\o19", "A!B!C", "WF_x(Next) /\\ ~y"]
  check fails "determinism: repeated runs produce equal results"
    (samples.all (fun text => resultKey (lexText text) == resultKey (lexText text)))
  check fails "determinism: the logical path does not change tokens"
    (samples.all fun text =>
      match lexText text, lex (LanguageProfile.default)
          ({} : LexerLimits) (captureText "other/Path.tla" text) with
      | .ok left, .ok right => left == right
      | .error left, .error right =>
          left.map Diagnostic.code == right.map Diagnostic.code
      | _, _ => false)
  check fails "determinism: truncated attempts are equal byte for byte"
    (let first := lexWith { maxDiagnostics := 2 } (repeated 3 (controlChar 1))
     let second := lexWith { maxDiagnostics := 2 } (repeated 3 (controlChar 1))
     resultKey first == resultKey second)
  check fails "determinism: success carries no diagnostics and ends with eof"
    (samples.all fun text =>
      match lexText text with
      | .ok stream => stream.eof?.isSome
      | .error _ => true)
  check fails "determinism: every failure carries error-severity diagnostics"
    (samples.all fun text => (diagnostics (lexText text)).all Diagnostic.hasErrorSeverity)
  check fails "determinism: rejected input never yields a token stream"
    (["\u00b6", "\u2227", controlChar 1, "\"ab", "(* ab", "1.5",
        nestedComment 65, "\\o19"].all fun text =>
      (streamOf? (lexText text)).isNone && failed (lexText text))

def scenarioProfileTables (fails : Failures) : IO Unit := do
  check fails "profile: the revision-1 name is pinned"
    (LanguageProfile.default.name == "mirrors-tla-frontend-profile-1")
  check fails "profile: keywords and prefix keywords are disjoint"
    (LanguageProfile.default.keywords.toList.all fun keyword =>
      !(LanguageProfile.default.prefixKeywords.contains keyword))
  check fails "profile: the frozen limits keep their declared values"
    (defaultLimits.maxSourceBytes == 4 * 1024 * 1024 &&
      defaultLimits.maxIdentifierBytes == 256 &&
      defaultLimits.maxCommentDepth == 64 &&
      defaultLimits.maxTokens == 1_000_000 &&
      defaultLimits.maxDiagnostics == 64)
  check fails "profile: canonical lookup normalizes aliases and keeps unknowns"
    ((LanguageProfile.default.canonicalFor? "\\land" == some "/\\") &&
      LanguageProfile.default.canonicalFor? "\\leq" == some "=<" &&
      LanguageProfile.default.canonicalFor? "\\oplus" == some "\\oplus" &&
      LanguageProfile.default.canonicalFor? "\\notanalias" == none)
  check fails "profile: keyword lookup is exact and case sensitive"
    ((LanguageProfile.default.keyword? "THEOREM" == some "THEOREM") &&
      LanguageProfile.default.keyword? "theorem" == none &&
      LanguageProfile.default.prefixKeywordAt? "WF_x" == some ("WF_", 3) &&
      LanguageProfile.default.prefixKeywordAt? "WF" == none)
  check fails "profile: staged Unicode spellings are listed, ASCII is not"
    (LanguageProfile.default.isStagedUnicode "\u225c" &&
      LanguageProfile.default.isStagedUnicode "\u2227" &&
      !LanguageProfile.default.isStagedUnicode "/\\")
  check fails "diagnostics: severity and stage rendering is stable"
    (Severity.toString .error == "error" && Severity.isError .error &&
      !Severity.isError .warning &&
      DiagnosticStage.toString .lex == "lex" &&
      DiagnosticStage.toString .moduleGraph == "moduleGraph")
  check fails "diagnostics: the buffer is bounded by count and bytes"
    (Diagnostic.byteWeight sampleDiagnostic > 0 &&
      (DiagnosticBuffer.push sampleLimits DiagnosticBuffer.empty
        sampleDiagnostic).dropped == 0 &&
      (DiagnosticBuffer.push sampleLimitsZeroCount DiagnosticBuffer.empty
        sampleDiagnostic).dropped == 1 &&
      (DiagnosticBuffer.push sampleLimitsZeroBytes DiagnosticBuffer.empty
        sampleDiagnostic).dropped == 1 &&
      (DiagnosticBuffer.push sampleLimits DiagnosticBuffer.empty
        sampleDiagnostic).byteWeight == Diagnostic.byteWeight sampleDiagnostic &&
      (DiagnosticBuffer.pushForced DiagnosticBuffer.empty
        sampleDiagnostic).truncated == false)

def allScenarios (fails : Failures) : IO Unit := do
  scenarioSourceUnits fails
  scenarioModuleDelimiters fails
  scenarioVocabulary fails
  scenarioSymbols fails
  scenarioNumerics fails
  scenarioTrivia fails
  scenarioLosslessness fails
  scenarioMultibyte fails
  scenarioFailures fails
  scenarioInvalidUtf8 fails
  scenarioLimits fails
  scenarioDiagnosticBudgets fails
  scenarioTermination fails
  scenarioDeterminism fails
  scenarioProfileTables fails

def failuresOf : IO (List String) := do
  let fails ← IO.mkRef ([] : List String)
  allScenarios fails
  fails.get

def report (items : List String) : IO UInt32 := do
  if items.isEmpty then
    IO.println "TLA LEXER SPEC GREEN"
    return 0
  else
    for item in items do
      IO.eprintln s!"FAIL {item}"
    IO.eprintln s!"{items.length} FAILURES"
    return 1

def run : IO UInt32 := do
  report (← failuresOf)

end TlaLexerSpec

def main : IO UInt32 :=
  TlaLexerSpec.run

-- The acceptance command `lake env lean tools/TlaLexerSpec.lean` only
-- elaborates this file, so run the suite here as well: a failing check makes
-- the command fail instead of compiling unattended assertions.
#eval do
  let code ← TlaLexerSpec.run
  if code != 0 then
    throw (IO.userError "TLA lexer specification failed")
