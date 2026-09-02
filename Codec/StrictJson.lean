import Lean.Data.Json

/-!
# Strict JSON preflight

`Lean.Json` stores objects in a tree map, so duplicate keys are no longer
observable after parsing.  This module validates raw bytes first: it enforces a
UTF-8 byte limit, rejects invalid UTF-8, scans the complete JSON grammar, and
rejects duplicate object keys after decoding JSON string escapes.  Only then
does `parseBytes` call `Lean.Json.parse`.

The scanner deliberately rejects unpaired UTF-16 surrogate escapes.  A valid
pair and the equivalent directly encoded Unicode scalar normalize to the same
key, so they are correctly detected as duplicates.
-/

namespace Codec.StrictJson

/-- Stable classes of strict-input failure. -/
inductive ErrorKind where
  | tooLarge
  | invalidUtf8
  | duplicateKey
  | invalidSyntax
  | tooDeep
  | leanParser
  deriving Repr, BEq

/-- A strict JSON error. `offset` is a character offset after UTF-8 decoding;
UTF-8 and byte-limit failures use byte-oriented offsets. -/
structure Error where
  kind : ErrorKind
  offset : Nat
  message : String
  deriving Repr, BEq

instance : ToString Error where
  toString e := s!"strict JSON error at offset {e.offset}: {e.message}"

/-- Resource limits applied before `Lean.Json.parse`. -/
structure Limits where
  /-- Maximum UTF-8 bytes in the raw JSON value. -/
  maxBytes : Nat := 65535
  /-- Maximum nested object/array depth. -/
  maxDepth : Nat := 128
  deriving Repr, BEq

/-- Defaults matching the protocol's maximum JSONL payload. -/
def defaultLimits : Limits := {}

private structure Cursor where
  chars : Array Char
  pos : Nat
  maxDepth : Nat

private abbrev ScanResult (α : Type) := Except Error α

private def Cursor.current (c : Cursor) : Option Char :=
  c.chars[c.pos]?

private def Cursor.advance (c : Cursor) (n : Nat := 1) : Cursor :=
  { c with pos := c.pos + n }

private def syntaxError (c : Cursor) (message : String) : ScanResult α :=
  .error (Error.mk .invalidSyntax c.pos message)

private def isJsonWhitespace (c : Char) : Bool :=
  c == ' ' || c == '\t' || c == '\n' || c == '\r'

private partial def skipWhitespace (c : Cursor) : Cursor :=
  match c.current with
  | some ch => if isJsonWhitespace ch then skipWhitespace c.advance else c
  | none => c

private def expectChar (c : Cursor) (expected : Char) : ScanResult Cursor :=
  match c.current with
  | some actual =>
      if actual == expected then .ok c.advance
      else syntaxError c s!"expected '{expected}'"
  | none => syntaxError c s!"expected '{expected}', reached end of input"

private def hexValue (c : Char) : Option Nat :=
  let n := c.toNat
  if '0'.toNat ≤ n && n ≤ '9'.toNat then some (n - '0'.toNat)
  else if 'a'.toNat ≤ n && n ≤ 'f'.toNat then some (10 + n - 'a'.toNat)
  else if 'A'.toNat ≤ n && n ≤ 'F'.toNat then some (10 + n - 'A'.toNat)
  else none

private def takeHex (c : Cursor) : ScanResult (Nat × Cursor) :=
  match c.current with
  | some ch =>
      match hexValue ch with
      | some n => .ok (n, c.advance)
      | none => syntaxError c "expected a hexadecimal digit"
  | none => syntaxError c "incomplete Unicode escape"

private def takeHex4 (c : Cursor) : ScanResult (Nat × Cursor) := do
  let (a, c) ← takeHex c
  let (b, c) ← takeHex c
  let (d, c) ← takeHex c
  let (e, c) ← takeHex c
  return (((a * 16 + b) * 16 + d) * 16 + e, c)

private partial def scanStringBody (c : Cursor) (reversed : List Nat) :
    ScanResult (List Nat × Cursor) :=
  match c.current with
  | none => syntaxError c "unterminated string"
  | some '"' => .ok (reversed.reverse, c.advance)
  | some '\\' => do
      let escaped := c.advance
      match escaped.current with
      | none => syntaxError escaped "unterminated escape"
      | some '"' => scanStringBody escaped.advance ('"'.toNat :: reversed)
      | some '\\' => scanStringBody escaped.advance ('\\'.toNat :: reversed)
      | some '/' => scanStringBody escaped.advance ('/'.toNat :: reversed)
      | some 'b' => scanStringBody escaped.advance (8 :: reversed)
      | some 'f' => scanStringBody escaped.advance (12 :: reversed)
      | some 'n' => scanStringBody escaped.advance (10 :: reversed)
      | some 'r' => scanStringBody escaped.advance (13 :: reversed)
      | some 't' => scanStringBody escaped.advance (9 :: reversed)
      | some 'u' => do
          let (unit, afterUnit) ← takeHex4 escaped.advance
          if 0xd800 ≤ unit && unit ≤ 0xdbff then
            let afterSlash ← expectChar afterUnit '\\'
            let afterU ← expectChar afterSlash 'u'
            let (low, afterLow) ← takeHex4 afterU
            if 0xdc00 ≤ low && low ≤ 0xdfff then
              let scalar := 0x10000 + (unit - 0xd800) * 0x400 + (low - 0xdc00)
              scanStringBody afterLow (scalar :: reversed)
            else
              syntaxError afterU "high surrogate is not followed by a low surrogate"
          else if 0xdc00 ≤ unit && unit ≤ 0xdfff then
            syntaxError escaped "unpaired low surrogate"
          else
            scanStringBody afterUnit (unit :: reversed)
      | some _ => syntaxError escaped "invalid string escape"
  | some ch =>
      if ch.toNat < 0x20 then syntaxError c "unescaped control character in string"
      else scanStringBody c.advance (ch.toNat :: reversed)

private def scanString (c : Cursor) : ScanResult (List Nat × Cursor) := do
  let body ← expectChar c '"'
  scanStringBody body []

private def isDigit (c : Char) : Bool :=
  '0'.toNat ≤ c.toNat && c.toNat ≤ '9'.toNat

private def isNonzeroDigit (c : Char) : Bool :=
  '1'.toNat ≤ c.toNat && c.toNat ≤ '9'.toNat

private partial def consumeDigits (c : Cursor) : Cursor :=
  match c.current with
  | some ch => if isDigit ch then consumeDigits c.advance else c
  | none => c

private def requireDigit (c : Cursor) (message : String) : ScanResult Cursor :=
  match c.current with
  | some ch => if isDigit ch then .ok c else syntaxError c message
  | none => syntaxError c message

private def scanNumber (start : Cursor) : ScanResult Cursor := do
  let c := match start.current with
    | some '-' => start.advance
    | _ => start
  let c ← match c.current with
    | some '0' => .ok c.advance
    | some ch =>
        if isNonzeroDigit ch then .ok (consumeDigits c.advance)
        else syntaxError c "invalid number integer part"
    | none => syntaxError c "incomplete number"
  let c ← match c.current with
    | some '.' => do
        let first ← requireDigit c.advance "fraction requires at least one digit"
        pure (consumeDigits first)
    | _ => .ok c
  match c.current with
  | some ch =>
      if ch == 'e' || ch == 'E' then do
        let exponent := c.advance
        let exponent := match exponent.current with
          | some sign => if sign == '+' || sign == '-' then exponent.advance else exponent
          | none => exponent
        let first ← requireDigit exponent "exponent requires at least one digit"
        return consumeDigits first
      else return c
  | _ => return c

private def scanLiteral (c : Cursor) (literal : String) : ScanResult Cursor :=
  literal.toList.foldlM expectChar c

mutual

  private partial def scanValue (input : Cursor) (depth : Nat) : ScanResult Cursor := do
    let c := skipWhitespace input
    match c.current with
    | none => syntaxError c "expected a JSON value"
    | some '{' =>
        if depth ≥ c.maxDepth then
          .error (Error.mk .tooDeep c.pos
            s!"JSON nesting exceeds limit {c.maxDepth}")
        else scanObject c.advance (depth + 1)
    | some '[' =>
        if depth ≥ c.maxDepth then
          .error (Error.mk .tooDeep c.pos
            s!"JSON nesting exceeds limit {c.maxDepth}")
        else scanArray c.advance (depth + 1)
    | some '"' => return (← scanString c).2
    | some 't' => scanLiteral c "true"
    | some 'f' => scanLiteral c "false"
    | some 'n' => scanLiteral c "null"
    | some '-' => scanNumber c
    | some ch =>
        if isDigit ch then scanNumber c
        else syntaxError c "unexpected character while reading a JSON value"

  private partial def scanObject (input : Cursor) (depth : Nat) : ScanResult Cursor := do
    let c := skipWhitespace input
    match c.current with
    | some '}' => return c.advance
    | _ => scanMembers c depth []

  private partial def scanMembers (input : Cursor) (depth : Nat)
      (keys : List (List Nat)) : ScanResult Cursor := do
    let keyStart := skipWhitespace input
    let (key, afterKey) ← scanString keyStart
    if keys.contains key then
      .error (Error.mk .duplicateKey keyStart.pos "duplicate object key")
    else
      let afterColon ← expectChar (skipWhitespace afterKey) ':'
      let afterValue ← scanValue afterColon depth
      let delimiter := skipWhitespace afterValue
      match delimiter.current with
      | some ',' => scanMembers delimiter.advance depth (key :: keys)
      | some '}' => return delimiter.advance
      | some _ => syntaxError delimiter "expected ',' or '}' after object member"
      | none => syntaxError delimiter "unterminated object"

  private partial def scanArray (input : Cursor) (depth : Nat) : ScanResult Cursor := do
    let c := skipWhitespace input
    match c.current with
    | some ']' => return c.advance
    | _ => scanElements c depth

  private partial def scanElements (input : Cursor) (depth : Nat) : ScanResult Cursor := do
    let afterValue ← scanValue input depth
    let delimiter := skipWhitespace afterValue
    match delimiter.current with
    | some ',' => scanElements delimiter.advance depth
    | some ']' => return delimiter.advance
    | some _ => syntaxError delimiter "expected ',' or ']' after array element"
    | none => syntaxError delimiter "unterminated array"

end

private def validateText (text : String) (limits : Limits) : Except Error Unit := do
  let start := Cursor.mk text.toList.toArray 0 limits.maxDepth
  let afterValue ← scanValue start 0
  let rest := skipWhitespace afterValue
  if rest.pos == rest.chars.size then return ()
  else syntaxError rest "trailing characters after JSON value"

/-- Validate size, UTF-8, JSON syntax, nesting, and duplicate object keys.
Returns the decoded text for a subsequent parser without decoding it twice. -/
def preflightBytes (raw : ByteArray) (limits : Limits := defaultLimits) :
    Except Error String := do
  if raw.size > limits.maxBytes then
    throw (Error.mk .tooLarge raw.size
      s!"JSON payload is {raw.size} bytes; limit is {limits.maxBytes}")
  let text ← match String.fromUTF8? raw with
    | some text => .ok text
    | none => .error (Error.mk .invalidUtf8 0 "input is not valid UTF-8")
  validateText text limits
  return text

/-- String form of `preflightBytes`; size is still measured in UTF-8 bytes. -/
def preflightString (text : String) (limits : Limits := defaultLimits) :
    Except Error Unit := do
  let _ ← preflightBytes text.toUTF8 limits
  return ()

/-- Strictly validate raw bytes and only then call `Lean.Json.parse`. -/
def parseBytes (raw : ByteArray) (limits : Limits := defaultLimits) :
    Except Error Lean.Json := do
  let text ← preflightBytes raw limits
  match Lean.Json.parse text with
  | .ok json => return json
  | .error message =>
      throw (Error.mk .leanParser 0
        s!"Lean JSON parser rejected preflighted input: {message}")

/-- Strictly validate and parse a Lean string, measuring its UTF-8 encoding. -/
def parseString (text : String) (limits : Limits := defaultLimits) :
    Except Error Lean.Json :=
  parseBytes text.toUTF8 limits

/-! ## Executable smoke checks -/

/-- Escaped and unescaped spellings of the same key are duplicates. -/
def escapedDuplicateRejected : Bool :=
  match parseString "{\"a\":1,\"\\u0061\":2}" with
  | .error e => e.kind == .duplicateKey
  | .ok _ => false

/-- Equal keys in different nested objects are legal. -/
def nestedKeysAccepted : Bool :=
  (parseString "{\"left\":{\"x\":1},\"right\":{\"x\":2}}" ).isOk

/-- Direct UTF-8 and a surrogate-pair escape normalize to the same key. -/
def surrogateDuplicateRejected : Bool :=
  match parseString "{\"𝄞\":1,\"\\uD834\\uDD1E\":2}" with
  | .error e => e.kind == .duplicateKey
  | .ok _ => false

/-- One Boolean suitable for a lightweight test-suite self-check. -/
def smokeChecksOk : Bool :=
  escapedDuplicateRejected && nestedKeysAccepted && surrogateDuplicateRejected

end Codec.StrictJson
