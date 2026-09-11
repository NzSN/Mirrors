import Core.ModelInterface.Sha256

/-!
# TLA+ source units and identity (Core/Tla/Source.lean)

Pure source capture for the general TLA+ frontend
(`Docs/model-interface-compiler/tla-frontend-design.md`, §8 "Source units and
identity" and §9 "Lexer").

Rules implemented here:

* line endings are normalized exactly as current model-source hashing
  specifies: `CRLF` and lone `CR` become `LF`;
* `contentSha256` hashes normalized UTF-8 bytes, never an AST or a
  pretty-printed form;
* ranges are half-open UTF-8 byte ranges that also carry one-based line and
  Unicode-scalar columns;
* physical paths never appear: only the logical path and the origin kind
  travel with a source unit.

The module reuses only the pure `Core.ModelInterface.Sha256` codec, which
contains no model-interface type, so the frontend interface stays
compiler-independent. The model-interface shell converts `SourceIdentity` to
its lock `SourceDigest` at its adapter seam.
-/

namespace Core.Tla

/-! ## Character classification -/

/-- ASCII letter test. Kept explicit so the frontend does not depend on the
Unicode definition of `Char.isAlpha` that the core library may revise. -/
def isAsciiLetter (character : Char) : Bool :=
  let code := character.toNat
  (0x41 ≤ code && code ≤ 0x5A) || (0x61 ≤ code && code ≤ 0x7A)

/-- ASCII digit test. -/
def isAsciiDigit (character : Char) : Bool :=
  let code := character.toNat
  0x30 ≤ code && code ≤ 0x39

/-- ASCII letter, digit, or underscore. -/
def isAsciiIdentifierChar (character : Char) : Bool :=
  isAsciiLetter character || isAsciiDigit character || character == '_'

/-! ## Module names -/

/-- A TLA+ module name: an ASCII letter or `_`, then ASCII letters, digits, or
`_`. The wrapper keeps validation at the boundary instead of re-checking
strings in every consumer. -/
structure ModuleName where
  name : String
  deriving Repr, BEq, DecidableEq

namespace ModuleName

/-- `true` when `raw` is a syntactically valid module name. -/
def valid (raw : String) : Bool :=
  match raw.toList with
  | [] => false
  | first :: rest =>
      (isAsciiLetter first || first == '_') && rest.all isAsciiIdentifierChar

/-- Checked constructor. Returns `none` for an invalid module name. -/
def ofString? (raw : String) : Option ModuleName :=
  if valid raw then some ⟨raw⟩ else none

/-- Unchecked accessor for callers that already validated the spelling. -/
def toString (moduleName : ModuleName) : String := moduleName.name

end ModuleName

instance : ToString ModuleName where
  toString := ModuleName.toString

/-! ## UTF-8 decoding -/

/-- Classification of a byte sequence that is not valid UTF-8. The offset is the
first byte of the offending sequence. -/
inductive Utf8Problem where
  /-- A continuation byte or a bad continuation byte appeared where a sequence
  start or a continuation byte was required. -/
  | unexpectedContinuationByte (offset : Nat)
  /-- The source ended inside a multi-byte sequence. -/
  | truncatedSequence (offset : Nat) (expectedBytes : Nat) (availableBytes : Nat)
  /-- A sequence encoded a scalar value below the minimum for its length. -/
  | overlongEncoding (offset : Nat)
  /-- A sequence encoded one of the surrogate code points U+D800..U+DFFF. -/
  | surrogateCodePoint (offset : Nat)
  /-- A sequence encoded a scalar above U+10FFFF or used an invalid lead byte. -/
  | codePointOutOfRange (offset : Nat)
  deriving Repr, BEq, DecidableEq

/-- An invalid UTF-8 occurrence at a byte offset. -/
structure Utf8Violation where
  offset : Nat
  problem : Utf8Problem
  deriving Repr, BEq, DecidableEq

private def byteAt (bytes : ByteArray) (offset : Nat) : UInt8 :=
  bytes.get! offset

private def continuationByte (bytes : ByteArray) (offset : Nat) : Bool :=
  let byte := byteAt bytes offset
  0x80 ≤ byte.toNat && byte.toNat ≤ 0xBF

/-- Strictly decode the scalar starting at byte `offset`.

The decoder accepts the canonical UTF-8 encodings only: overlong encodings,
surrogate code points, and values above U+10FFFF are reported instead of being
mapped to a replacement character. It returns the scalar and its byte width.
Callers must pass `offset < bytes.size`; other offsets report a truncated
sequence. -/
def decodeUtf8At (bytes : ByteArray) (offset : Nat) :
    Except Utf8Problem (Char × Nat) :=
  if offset ≥ bytes.size then
    .error (.truncatedSequence offset 1 0)
  else
    let lead := (byteAt bytes offset).toNat
    if lead ≤ 0x7F then
      .ok (Char.ofNat lead, 1)
    else if lead ≤ 0xBF then
      .error (.unexpectedContinuationByte offset)
    else if lead ≤ 0xC1 then
      .error (.overlongEncoding offset)
    else if lead ≤ 0xDF then
      if offset + 1 ≥ bytes.size then
        .error (.truncatedSequence offset 2 (bytes.size - offset))
      else if !(continuationByte bytes (offset + 1)) then
        .error (.unexpectedContinuationByte (offset + 1))
      else
        let value := (lead - 0xC0) * 0x40 + ((byteAt bytes (offset + 1)).toNat - 0x80)
        .ok (Char.ofNat value, 2)
    else if lead ≤ 0xEF then
      if offset + 2 ≥ bytes.size then
        .error (.truncatedSequence offset 3 (bytes.size - offset))
      else
        let second := (byteAt bytes (offset + 1)).toNat
        let third := (byteAt bytes (offset + 2)).toNat
        if lead == 0xE0 && second < 0xA0 then
          .error (.overlongEncoding offset)
        else if lead == 0xED && 0xA0 ≤ second then
          .error (.surrogateCodePoint offset)
        else if second < 0x80 || second > 0xBF then
          .error (.unexpectedContinuationByte (offset + 1))
        else if third < 0x80 || third > 0xBF then
          .error (.unexpectedContinuationByte (offset + 2))
        else
          let value := (lead - 0xE0) * 0x1000 + (second - 0x80) * 0x40 + (third - 0x80)
          .ok (Char.ofNat value, 3)
    else if lead ≤ 0xF4 then
      if offset + 3 ≥ bytes.size then
        .error (.truncatedSequence offset 4 (bytes.size - offset))
      else
        let second := (byteAt bytes (offset + 1)).toNat
        let third := (byteAt bytes (offset + 2)).toNat
        let fourth := (byteAt bytes (offset + 3)).toNat
        if lead == 0xF0 && second < 0x90 then
          .error (.overlongEncoding offset)
        else if lead == 0xF4 && 0x90 ≤ second then
          .error (.codePointOutOfRange offset)
        else if second < 0x80 || second > 0xBF then
          .error (.unexpectedContinuationByte (offset + 1))
        else if third < 0x80 || third > 0xBF then
          .error (.unexpectedContinuationByte (offset + 2))
        else if fourth < 0x80 || fourth > 0xBF then
          .error (.unexpectedContinuationByte (offset + 3))
        else
          let value := (lead - 0xF0) * 0x40000 + (second - 0x80) * 0x1000 +
            (third - 0x80) * 0x40 + (fourth - 0x80)
          .ok (Char.ofNat value, 4)
    else
      .error (.codePointOutOfRange offset)

/-- First invalid UTF-8 occurrence in `bytes`, if any. -/
def validateUtf8 (bytes : ByteArray) : Option Utf8Violation :=
  Id.run do
    let mut offset := 0
    let mut violation : Option Utf8Violation := none
    while offset < bytes.size && violation.isNone do
      match decodeUtf8At bytes offset with
      | .ok (_, width) => offset := offset + width
      | .error problem =>
        violation := some ⟨offset, problem⟩
        offset := offset + 1
    return violation

/-! ## Positions and ranges -/

/-- A position inside normalized source text. `offset` counts UTF-8 bytes and
`line` / `column` are one-based; `column` counts Unicode scalars, so a scalar
encoded as several bytes advances the column once. -/
structure SourcePosition where
  offset : Nat
  line : Nat
  column : Nat
  deriving Repr, BEq, DecidableEq, Inhabited

/-- A half-open source range `[start, stop)`. -/
structure SourceRange where
  start : SourcePosition
  stop : SourcePosition
  deriving Repr, BEq, DecidableEq, Inhabited

namespace SourceRange

/-- Number of bytes covered by the range. -/
def byteLength (range : SourceRange) : Nat := range.stop.offset - range.start.offset

/-- `true` when the range covers no bytes. -/
def isEmpty (range : SourceRange) : Bool := range.start.offset == range.stop.offset

/-- `true` when the range is well formed: offsets are ordered and the stop is
not before the start. -/
def wellFormed (range : SourceRange) : Bool := range.start.offset ≤ range.stop.offset

end SourceRange

/-! ## Source units and identity -/

/-- Where a captured source unit came from. Origins are logical: a borrowed
directory, a caller-supplied inline map, or the standard-module catalog. No
field carries a physical path. -/
inductive SourceOrigin where
  | borrowedDirectory
  | inlineSourceMap
  | standardModuleCatalog
  deriving Repr, BEq, DecidableEq

/-- Compiler-independent module source identity. The model-interface shell maps
it to its own lock digest at the adapter seam. -/
structure SourceIdentity where
  moduleName : ModuleName
  logicalPath : String
  contentSha256 : String
  deriving Repr, BEq, DecidableEq

/-- A captured source unit. `normalizedUtf8` is the authority for analysis and
for `contentSha256`; `normalizedText` is the same capture as text. -/
structure SourceUnit where
  logicalPath : String
  normalizedText : String
  normalizedUtf8 : ByteArray
  contentSha256 : String
  origin : SourceOrigin
  deriving BEq

/-- The current model-source normalization: `CRLF` and lone `CR` become `LF`. -/
def normalizeNewlines (text : String) : String :=
  (text.replace "\r\n" "\n").replace "\r" "\n"

namespace SourceUnit

/-- Capture a source unit from raw text. The caller supplies the logical path
and origin; physical locations stay outside this type. -/
def create (origin : SourceOrigin) (logicalPath : String) (rawText : String) :
    SourceUnit :=
  let normalizedText := normalizeNewlines rawText
  let normalizedUtf8 := normalizedText.toUTF8
  { logicalPath
    normalizedText
    normalizedUtf8
    contentSha256 := Core.ModelInterface.Sha256.digestHex normalizedUtf8
    origin }

/-- `true` when the captured text, bytes, and digest agree. Used by tests and by
providers that must not hand inconsistent captures to analysis. -/
def consistent (unit : SourceUnit) : Bool :=
  unit.normalizedText.toUTF8 == unit.normalizedUtf8 &&
    Core.ModelInterface.Sha256.digestHex unit.normalizedUtf8 == unit.contentSha256

/-- Compiler-independent identity of a captured module source. -/
def identity (unit : SourceUnit) (moduleName : ModuleName) : SourceIdentity :=
  { moduleName, logicalPath := unit.logicalPath, contentSha256 := unit.contentSha256 }

end SourceUnit

end Core.Tla
