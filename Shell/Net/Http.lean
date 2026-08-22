import Ffi.Socket
import Lean

/-!
# Shell.Net.Http — a minimal pure-Lean HTTP/1.1 client (t14, design 9.2)

Exactly the explorer's HTTP surface and nothing more: one-shot JSON
POSTs to @http://localhost:<port>/rpc@ over loopback TCP. All HTTP
framing lives here in Lean:

* requests always carry @Content-Length@ and @Connection: close@;
* responses honor @Transfer-Encoding: chunked@, @Content-Length@, and
  read-to-EOF (connection-close) bodies;
* a recv timeout bounds each wait (default 30 s; @connect@ has a 5 s
  deadline in the shim), so dead peers surface as errors, not hangs.

The t14 decision (see @Ffi/Socket.lean@): pure Lean over a ~150-line
loopback C socket shim instead of libcurl FFI.
-/

namespace Shell.Net.Http

/-- One parsed HTTP response. -/
structure HttpResponse where
  status : Nat
  body : String
deriving Repr

private def recvBuf : ByteArray :=
  ByteArray.mk ((List.replicate 65536 0).toArray)

/-- Read from the fd until EOF (Connection: close), accumulating. -/
private def recvAll (fd : Int) : IO (Except String ByteArray) := do
  let bufRef ← IO.mkRef (ByteArray.mk (#[] : Array UInt8))
  let mut loop := true
  while loop do
    let n ← Ffi.recvSome fd recvBuf
    if n < 0 then
      return .error "recv failed (timeout or connection error)"
    else if n == 0 then
      loop := false
    else
      bufRef.modify (fun acc => acc.append (recvBuf.extract 0 n.toNat))
  return .ok (← bufRef.get)

/-- Index of the first @\r\n\r\n@ in the byte array, if any. -/
private partial def blankLineAt (b : ByteArray) : Option Nat :=
  let rec go (i : Nat) : Option Nat :=
    if i + 4 > b.size then none
    else if b.get! i == 13 && b.get! (i+1) == 10 && b.get! (i+2) == 13 && b.get! (i+3) == 10
      then some i
      else go (i + 1)
  go 0

private def ascii (b : ByteArray) : String :=
  String.fromUTF8? b |>.getD ""

/-- Case-insensitive header lookup over raw header text; trimmed value. -/
private def headerValue (headers : String) (name : String) : Option String :=
  let rec go : List String → Option String
    | [] => none
    | l :: ls =>
        match l.splitOn ":" with
        | [k, v] =>
            if ((k.toList.filter (· != ' ')).asString).toLower == name.toLower
            then some ((v.toList.filter (· != ' ')).asString)
            else go ls
        | _ => go ls
  go ((headers.splitOn "\r\n").filter (· != ""))

private def hexVal (c : Char) : Option Nat :=
  match c with
  | '0' => some 0 | '1' => some 1 | '2' => some 2 | '3' => some 3
  | '4' => some 4 | '5' => some 5 | '6' => some 6 | '7' => some 7
  | '8' => some 8 | '9' => some 9
  | 'a' | 'A' => some 10 | 'b' | 'B' => some 11 | 'c' | 'C' => some 12
  | 'd' | 'D' => some 13 | 'e' | 'E' => some 14 | 'f' | 'F' => some 15
  | _ => none

private def parseHex (s : String) : Option Nat :=
  let rec go (cs : List Char) (acc : Nat) : Option Nat :=
    match cs with
    | [] => some acc
    | c :: rest => match hexVal c with
      | some v => go rest (acc * 16 + v)
      | none => none
  go s.toList 0

/-- Decode a chunked body per RFC 7230 (hex size lines; 0-size ends). -/
private def decodeChunked (b : ByteArray) : Except String String := do
  let mut i := 0
  let mut acc := ""
  let mut done := false
  let mut err : Option String := none
  while !done && err.isNone do
    if i >= b.size then err := some "truncated chunked body"
    else
      let mut hexS := ""
      while i < b.size && b.get! i != 13 do
        hexS := hexS ++ (String.ofList [Char.ofNat (b.get! i).toNat])
        i := i + 1
      if i + 1 >= b.size || b.get! (i+1) != 10 then
        err := some "bad chunk header"
      else
        i := i + 2
        match parseHex hexS with
        | none => err := some s!"bad chunk size: {hexS}"
        | some 0 => done := true
        | some size =>
            if i + size > b.size then err := some "truncated chunk"
            else
              acc := acc ++ (String.fromUTF8? (b.extract i (i + size)) |>.getD "")
              i := i + size
              if i + 1 < b.size && b.get! i == 13 && b.get! (i+1) == 10 then i := i + 2
  match err with
  | some e => .error e
  | none => .ok acc

/-- Parse a full response (status line + headers + body) from the raw
bytes of one @Connection: close@ exchange. -/
def parseResponse (raw : ByteArray) : Except String HttpResponse := do
  let (head, body) ← match blankLineAt raw with
    | some i => pure (raw.extract 0 i, raw.extract (i + 4) raw.size)
    | none => .error "no header/body boundary in response"
  let headLines := (ascii head).splitOn "\r\n"
  let status ← match headLines.head? with
    | some line =>
        match (line.splitOn " ").filter (· != "") with
        | _http :: code :: _ =>
            match code.toNat? with
            | some c => pure c
            | none => .error s!"bad status line: {line}"
        | _ => .error s!"bad status line: {line}"
    | none => .error "empty response"
  let hdrs := String.intercalate "\r\n" (headLines.tail?.getD [])
  match headerValue hdrs "Transfer-Encoding" with
  | some te =>
      if te.toLower == "chunked" then
        match decodeChunked body with
        | .ok s => return ⟨status, s⟩
        | .error e => .error e
      else
        match headerValue hdrs "Content-Length" with
        | some len => match len.toNat? with
          | some n =>
              return ⟨status, String.fromUTF8? (body.extract 0 (min n body.size)) |>.getD ""⟩
          | none => .error s!"bad Content-Length: {len}"
        | none => return ⟨status, ascii body⟩
  | none =>
      match headerValue hdrs "Content-Length" with
      | some len => match len.toNat? with
        | some n =>
            return ⟨status, String.fromUTF8? (body.extract 0 (min n body.size)) |>.getD ""⟩
        | none => .error s!"bad Content-Length: {len}"
      | none =>
          -- read-to-EOF body (Connection: close)
          return ⟨status, ascii body⟩

/-- One-shot HTTP/1.1 POST of a JSON body to @localhost:<port><path>@
with a bounded wait. -/
def post (port : Nat) (path : String) (body : String)
    (timeoutMs : Nat := 30000) : IO (Except String HttpResponse) := do
  let fd ← Ffi.tcpSocket
  if fd < 0 then .error "socket creation failed"
  let _ ← Ffi.setRecvTimeoutMs fd timeoutMs
  let conn ← Ffi.connectLoopback fd port
  if conn < 0 then
    Ffi.closeFd fd
    .error s!"connect to localhost:{port} failed"
  let req := "POST " ++ path ++ " HTTP/1.1\r\n"
    ++ "Host: localhost:" ++ toString port ++ "\r\n"
    ++ "Content-Type: application/json\r\n"
    ++ "Content-Length: " ++ toString body.length ++ "\r\n"
    ++ "Connection: close\r\n\r\n"
    ++ body
  let sent ← Ffi.sendAll fd req.toUTF8
  if sent < 0 then
    Ffi.closeFd fd
    .error "send failed"
  let raw ← recvAll fd
  Ffi.closeFd fd
  match raw with
  | .error e => .error e
  | .ok bs => return parseResponse bs

end Shell.Net.Http