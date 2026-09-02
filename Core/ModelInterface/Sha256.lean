/-!
# Pure SHA-256 primitives

This module implements SHA-256 in Lean without FFI or `IO`.  The
domain-separated helpers use the convention employed by the model-interface
descriptor designs:

```text
UTF8(domain) || 0x00 || payload
```

Domain labels are therefore expected to be fixed, nonempty, NUL-free ASCII
strings.  `validDomain` is provided for callers that accept a label dynamically.
-/

namespace Core.ModelInterface.Sha256

/-- A SHA-256 digest.  Values returned by this module always contain 32 bytes. -/
structure Digest where
  bytes : ByteArray
  deriving BEq

private structure HashState where
  a : UInt32
  b : UInt32
  c : UInt32
  d : UInt32
  e : UInt32
  f : UInt32
  g : UInt32
  h : UInt32

private def initialState : HashState where
  a := 0x6a09e667
  b := 0xbb67ae85
  c := 0x3c6ef372
  d := 0xa54ff53a
  e := 0x510e527f
  f := 0x9b05688c
  g := 0x1f83d9ab
  h := 0x5be0cd19

private def roundConstants : Array UInt32 := #[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
]

private def rotateRight (x n : UInt32) : UInt32 :=
  (x >>> n) ||| (x <<< (32 - n))

private def choose (x y z : UInt32) : UInt32 :=
  (x &&& y) ^^^ ((~~~x) &&& z)

private def majority (x y z : UInt32) : UInt32 :=
  (x &&& y) ^^^ (x &&& z) ^^^ (y &&& z)

private def bigSigma0 (x : UInt32) : UInt32 :=
  rotateRight x 2 ^^^ rotateRight x 13 ^^^ rotateRight x 22

private def bigSigma1 (x : UInt32) : UInt32 :=
  rotateRight x 6 ^^^ rotateRight x 11 ^^^ rotateRight x 25

private def smallSigma0 (x : UInt32) : UInt32 :=
  rotateRight x 7 ^^^ rotateRight x 18 ^^^ (x >>> 3)

private def smallSigma1 (x : UInt32) : UInt32 :=
  rotateRight x 17 ^^^ rotateRight x 19 ^^^ (x >>> 10)

private def readWordBE (input : ByteArray) (offset : Nat) : UInt32 :=
  (UInt32.ofNat (input.get! offset).toNat <<< 24) |||
  (UInt32.ofNat (input.get! (offset + 1)).toNat <<< 16) |||
  (UInt32.ofNat (input.get! (offset + 2)).toNat <<< 8) |||
  UInt32.ofNat (input.get! (offset + 3)).toNat

private def messageSchedule (input : ByteArray) (offset : Nat) : Array UInt32 := Id.run do
  let mut words := Array.replicate 64 (0 : UInt32)
  for i in [0:16] do
    words := words.set! i (readWordBE input (offset + 4 * i))
  for i in [16:64] do
    let next := smallSigma1 words[i - 2]! + words[i - 7]! +
      smallSigma0 words[i - 15]! + words[i - 16]!
    words := words.set! i next
  return words

private def compress (state : HashState) (input : ByteArray) (offset : Nat) : HashState := Id.run do
  let words := messageSchedule input offset
  let mut a := state.a
  let mut b := state.b
  let mut c := state.c
  let mut d := state.d
  let mut e := state.e
  let mut f := state.f
  let mut g := state.g
  let mut h := state.h
  for i in [0:64] do
    let t1 := h + bigSigma1 e + choose e f g + roundConstants[i]! + words[i]!
    let t2 := bigSigma0 a + majority a b c
    h := g
    g := f
    f := e
    e := d + t1
    d := c
    c := b
    b := a
    a := t1 + t2
  return {
    a := state.a + a
    b := state.b + b
    c := state.c + c
    d := state.d + d
    e := state.e + e
    f := state.f + f
    g := state.g + g
    h := state.h + h
  }

private def padded (input : ByteArray) : ByteArray := Id.run do
  let bitLength := UInt64.ofNat (input.size * 8)
  let mut out := input.push 0x80
  let zeroCount := (56 + 64 - out.size % 64) % 64
  for _ in [0:zeroCount] do
    out := out.push 0
  for shift in #[56, 48, 40, 32, 24, 16, 8, 0] do
    out := out.push (UInt8.ofNat ((bitLength.toNat >>> shift) % 256))
  return out

private def appendWordBE (word : UInt32) (out : ByteArray) : ByteArray :=
  out
    |>.push ((word >>> 24).toUInt8)
    |>.push ((word >>> 16).toUInt8)
    |>.push ((word >>> 8).toUInt8)
    |>.push word.toUInt8

/-- Compute a SHA-256 digest from arbitrary bytes. -/
def digest (input : ByteArray) : Digest :=
  let input := padded input
  let state := Id.run do
    let mut state := initialState
    for block in [0:input.size / 64] do
      state := compress state input (block * 64)
    return state
  ⟨ByteArray.empty
    |> appendWordBE state.a
    |> appendWordBE state.b
    |> appendWordBE state.c
    |> appendWordBE state.d
    |> appendWordBE state.e
    |> appendWordBE state.f
    |> appendWordBE state.g
    |> appendWordBE state.h⟩

private def hexDigit (n : Nat) : Char :=
  if n < 10 then Char.ofNat ('0'.toNat + n)
  else Char.ofNat ('a'.toNat + n - 10)

/-- Render a digest as exactly 64 lowercase hexadecimal characters. -/
def Digest.toHex (d : Digest) : String :=
  String.ofList (d.bytes.data.toList.flatMap fun b =>
    [hexDigit (b.toNat / 16), hexDigit (b.toNat % 16)])

/-- Compute SHA-256 and render it as lowercase hexadecimal. -/
def digestHex (input : ByteArray) : String :=
  (digest input).toHex

/-- Compute SHA-256 over a UTF-8 string. -/
def digestString (input : String) : Digest :=
  digest input.toUTF8

/-- Compute SHA-256 over a UTF-8 string and render it in lowercase hex. -/
def digestStringHex (input : String) : String :=
  (digestString input).toHex

/-- True when `domain` is a nonempty, NUL-free ASCII domain label. -/
def validDomain (domain : String) : Bool :=
  !domain.isEmpty && domain.toList.all fun c => c != '\u0000' && c.toNat < 128

/-- Construct the domain-separated bytes `UTF8(domain) || 0x00 || payload`.
Callers accepting dynamic domains should first require `validDomain domain`. -/
def domainSeparatedInput (domain : String) (payload : ByteArray) : ByteArray :=
  (domain.toUTF8.push 0).append payload

/-- SHA-256 with the model-interface domain-separation convention. -/
def digestDomain (domain : String) (payload : ByteArray) : Digest :=
  digest (domainSeparatedInput domain payload)

/-- Domain-separated SHA-256 rendered as lowercase hexadecimal. -/
def digestDomainHex (domain : String) (payload : ByteArray) : String :=
  (digestDomain domain payload).toHex

/-! ## Executable known-vector self-checks -/

/-- NIST/SHA-256 vector for the empty message. -/
def emptyVectorOk : Bool :=
  digestStringHex "" ==
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

/-- NIST/SHA-256 vector for `abc`. -/
def abcVectorOk : Bool :=
  digestStringHex "abc" ==
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

/-- NIST/SHA-256 multi-block vector. -/
def multiBlockVectorOk : Bool :=
  digestStringHex
      "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq" ==
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"

/-- Common SHA-256 vector for the quick-brown-fox sentence. -/
def quickBrownFoxVectorOk : Bool :=
  digestStringHex "The quick brown fox jumps over the lazy dog" ==
    "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"

/-- One Boolean suitable for a lightweight startup or test-suite self-check. -/
def knownVectorsOk : Bool :=
  emptyVectorOk && abcVectorOk && multiBlockVectorOk && quickBrownFoxVectorOk

end Core.ModelInterface.Sha256
