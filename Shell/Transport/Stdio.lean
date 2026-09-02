import Lean

/-!
# Stdio transport (Layer 3, design 5.4)

Port of the Haskell @Protocol.Transport.Core@ transport class and
@Protocol.Transport.Stdio@ (16 LOC): one JSON message per line on
stdin/stdout, flush after every send.

EOF on recv decodes as @none@ (the Haskell version returns the empty
string, which then fails message decoding; the driver turns that into a
@protocol_error@ / session end exactly like @recvMsg@ does).
-/

/-- A line-framed byte transport (Haskell @Transport t@ class as a
record: the Lean shell only needs @recv@/@send@, so the class becomes a
plain structure). -/
structure Shell.Transport.Transport where
  /- Receive one framed line; @none@ is EOF (peer closed). -/
  recv : IO (Option String)
  /- Send one framed line (implementation flushes). -/
  send : String → IO Unit

namespace Shell.Transport

/-- Maximum UTF-8 payload bytes in one JSONL protocol line (the trailing LF is
not included). Shared by stdio, TCP, and TLS so framing limits are uniform. -/
def maxProtocolLineBytes : Nat := 65535

/-- Validate an already-decoded protocol payload before send/dispatch. -/
def validateProtocolLine (s : String) : IO Unit := do
  if s.isEmpty then
    throw (IO.userError "protocol line must not be empty")
  if s.contains '\n' || s.contains '\r' then
    throw (IO.userError "protocol line contains an embedded newline")
  if s.toUTF8.size > maxProtocolLineBytes then
    throw (IO.userError s!"protocol line exceeds {maxProtocolLineBytes} UTF-8 bytes")

/-- Decode a bounded raw UTF-8 payload without silently replacing malformed
bytes by the empty string. -/
def decodeProtocolUtf8 (bytes : ByteArray) : IO String := do
  if bytes.size > maxProtocolLineBytes then
    throw (IO.userError s!"protocol line exceeds {maxProtocolLineBytes} UTF-8 bytes")
  match String.fromUTF8? bytes with
  | some s => pure s
  | none => throw (IO.userError "protocol line is not valid UTF-8")

private def stripEolAux : List Char → List Char
  | ['\n'] => []
  | ['\r'] => []
  | ['\r', '\n'] => []
  | c :: cs => c :: stripEolAux cs
  | [] => []

/-- Strip a trailing line terminator (LF, CRLF, or bare CR). -/
def stripEol (l : String) : String :=
  String.ofList (stripEolAux l.toList)

private partial def findLfByte (bytes : ByteArray) (index : Nat := 0) : Option Nat :=
  if index >= bytes.size then none
  else if bytes.get! index == 10 then some index
  else findLfByte bytes (index + 1)

private def stripTrailingCrByte (bytes : ByteArray) : ByteArray :=
  if bytes.size > 0 && bytes.get! (bytes.size - 1) == 13 then
    bytes.extract 0 (bytes.size - 1)
  else bytes

private def validateRawPrefix (bytes : ByteArray) : IO Unit := do
  match findLfByte bytes with
  | some index =>
      let payload := stripTrailingCrByte (bytes.extract 0 index)
      if payload.size > maxProtocolLineBytes then
        throw (IO.userError s!"stdio line exceeds {maxProtocolLineBytes} UTF-8 bytes")
  | none =>
      let crAllowance :=
        if bytes.size > 0 && bytes.get! (bytes.size - 1) == 13 then 1 else 0
      if bytes.size > maxProtocolLineBytes + crAllowance then
        throw (IO.userError s!"stdio line exceeds {maxProtocolLineBytes} UTF-8 bytes")

/-- Send one line on the transport. -/
def sendLine (t : Transport) (s : String) : IO Unit := t.send s

/-- Receive one line on the transport (@none@ = EOF). -/
def recvLine (t : Transport) : IO (Option String) := t.recv

/-- The default stdio transport: @IO.getStdin@/@IO.getStdout@ with line
framing, flush after each send (port of @StdioTransport@). -/
def stdio : IO Transport := do
  let stdin ← IO.getStdin
  let stdout ← IO.getStdout
  let buffered ← IO.mkRef ByteArray.empty
  pure
    { recv := do
        let mut acc ← buffered.get
        validateRawPrefix acc
        let mut eof := false
        while (findLfByte acc).isNone && !eof do
          -- Lean's buffered stdio `read n` may wait for all `n` bytes while
          -- the pipe remains open. Read one byte so a short JSONL request is
          -- delivered immediately at LF while the accumulator stays bounded.
          let chunk ← stdin.read 1
          if chunk.isEmpty then
            eof := true
          else
            acc := acc.append chunk
            validateRawPrefix acc
        if eof && acc.isEmpty then
          return none
        match findLfByte acc with
        | none =>
            buffered.set ByteArray.empty
            return some (← decodeProtocolUtf8 (stripTrailingCrByte acc))
        | some index =>
            let payload := stripTrailingCrByte (acc.extract 0 index)
            buffered.set (acc.extract (index + 1) acc.size)
            return some (← decodeProtocolUtf8 payload)
      send := fun s => do
        validateProtocolLine s
        stdout.putStr (s ++ "\n")
        stdout.flush }

end Shell.Transport
