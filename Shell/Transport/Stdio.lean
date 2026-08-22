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

private def stripEolAux : List Char → List Char
  | ['\n'] => []
  | ['\r'] => []
  | ['\r', '\n'] => []
  | c :: cs => c :: stripEolAux cs
  | [] => []

/-- Strip a trailing line terminator (LF, CRLF, or bare CR). -/
def stripEol (l : String) : String :=
  String.ofList (stripEolAux l.toList)

/-- Send one line on the transport. -/
def sendLine (t : Transport) (s : String) : IO Unit := t.send s

/-- Receive one line on the transport (@none@ = EOF). -/
def recvLine (t : Transport) : IO (Option String) := t.recv

/-- The default stdio transport: @IO.getStdin@/@IO.getStdout@ with line
framing, flush after each send (port of @StdioTransport@). -/
def stdio : IO Transport := do
  let stdin ← IO.getStdin
  let stdout ← IO.getStdout
  pure
    { recv := do
        let l ← stdin.getLine
        if l.isEmpty then
          return none
        else
          -- strip the trailing newline (and a possible CR)
          return some (stripEol l)
      send := fun s => do
        stdout.putStr (s ++ "\n")
        stdout.flush }

end Shell.Transport
