import Ffi.Socket
import Lean
import Batteries -- for `while` do-notation

/-!
# Shell.Net.Http — a minimal pure-Lean HTTP/1.1 client (t14, design 9.2)

Exactly the explorer's HTTP surface and nothing more: JSON POSTs to
@http://localhost:<port>/rpc@ over loopback TCP. All HTTP framing
lives here in Lean. Two modes:

* one-shot POSTs with @Connection: close@ (@post@): the response is
  read to EOF; bodies honor @Content-Length@, chunked, and
  read-to-EOF framing. Used by the spike tests.
* a persistent keep-alive connection (@Conn@ / @openConn@ / @postKa@):
  requests read exactly one response by @Content-Length@ (or chunked)
  and leave the rest of the stream buffered for the next exchange.
  The apalache server (Jetty + async jsonrpc4s handlers) sporadically
  commits empty 200 responses when every request arrives on a fresh
  @Connection: close@ socket, so the RPC client pins one persistent
  connection per session — as the Haskell http-client does.

Recv timeouts bound every wait, so dead peers surface as errors.
The t14 decision (see @Ffi/Socket.lean@): pure Lean over a small
loopback C socket shim instead of libcurl FFI.
-/

namespace Shell.Net.Http

open Lean

/-- One parsed HTTP response. -/
structure HttpResponse where
  status : Nat
  body : String
deriving Repr

/-! ## Parsing helpers -/

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
  if s.isEmpty then none else go s.toList 0

private partial def crlfAtOrAfter (b : ByteArray) (i : Nat) : Option Nat :=
  if i + 1 >= b.size then none
  else if b.get! i == 13 && b.get! (i + 1) == 10 then some i
  else crlfAtOrAfter b (i + 1)

/-- Parse exactly one chunked body, including its trailers and final CRLF.
An incomplete prefix needs more bytes; a complete result includes the consumed
byte count so persistent connections retain the next response. Chunk boundaries
are byte boundaries and need not be Unicode scalar boundaries. -/
def parseChunkedPrefix (b : ByteArray) : Except String (Option (ByteArray × Nat)) := do
  let mut i := 0
  let mut acc := ByteArray.empty
  repeat
    let some lineEnd := crlfAtOrAfter b i | return none
    let some header := String.fromUTF8? (b.extract i lineEnd)
      | throw "bad chunk header"
    let some size := parseHex ((header.splitOn ";").head?.getD "")
      | throw "bad chunk size"
    i := lineEnd + 2
    if size == 0 then
      -- A zero-size chunk is followed by zero or more trailer fields and a
      -- blank line. Its own size-line CRLF is not the message terminator.
      repeat
        let some trailerEnd := crlfAtOrAfter b i | return none
        if trailerEnd == i then return some (acc, i + 2)
        let some trailer := String.fromUTF8? (b.extract i trailerEnd)
          | throw "bad chunk trailer"
        if !(trailer.contains ':') then throw "bad chunk trailer"
        i := trailerEnd + 2
    if i + size + 2 > b.size then return none
    if b.get! (i + size) != 13 || b.get! (i + size + 1) != 10 then
      throw "bad chunk data terminator"
    acc := acc.append (b.extract i (i + size))
    i := i + size + 2
  return none

private def utf8Body (bytes : ByteArray) : Except String String :=
  match String.fromUTF8? bytes with
  | some text => .ok text
  | none => .error "HTTP body is not valid UTF-8"

/-- Decode a complete chunked body, validating UTF-8 only after reassembly. -/
def decodeChunked (b : ByteArray) : Except String String := do
  let some (bytes, _) ← parseChunkedPrefix b
    | .error "truncated chunked body"
  utf8Body bytes

/-- Parse the status code from a raw HTTP status line. -/
def parseStatusLine (line : String) : Except String Nat :=
  match (line.splitOn " ").filter (· != "") with
  | _http :: code :: _ =>
      match code.toNat? with
      | some c => .ok c
      | none => .error s!"bad status line: {line}"
  | _ => .error s!"bad status line: {line}"

private def ascii (b : ByteArray) : String :=
  String.fromUTF8? b |>.getD ""

/-! ## Buffered keep-alive connection -/

/-- An open HTTP/1.1 keep-alive connection with a read buffer. -/
structure Conn where
  fd : UInt64
  buf : IO.Ref ByteArray
  rbuf : ByteArray
  closed : IO.Ref Bool

/-- Resolve an IPv4 host name to a dotted address (getaddrinfo via the
shim); dotted literals and @localhost@ pass through unchanged. -/
def resolveHost (host : String) : IO (Except String String) := do
  if host == "localhost" then return .ok "127.0.0.1"
  if host == "127.0.0.1" then return .ok host
  let buf ← Ffi.freshBuffer 64
  let n ← Ffi.resolveHostRaw host buf 63
  if n == Ffi.fdError then
    return .error s!"cannot resolve host: {host}"
  return .ok (String.fromUTF8? (buf.extract 0 n.toNat) |>.getD "")

/-- t16: open a connection to an arbitrary IPv4 host (registry
addresses are configurable URLs, not loopback-only). -/
def openConnTo (host : String) (port : Nat) (timeoutMs : Nat) :
    IO (Except String Conn) := do
  match ← resolveHost host with
  | .error e => return .error e
  | .ok ip =>
    let fd ← Ffi.tcpSocket
    if fd == Ffi.fdError then return .error "socket creation failed"
    let _ ← Ffi.setRecvTimeoutMs fd (timeoutMs.toUInt64)
    let conn ← Ffi.connectIpv4 fd ip port.toUInt64
    if conn == Ffi.fdError then
      Ffi.closeFd fd
      return .error s!"connect to {host}:{port} failed"
    return .ok ⟨fd, ← IO.mkRef ByteArray.empty, ← Ffi.freshBuffer 65536, ← IO.mkRef false⟩

def openConn (port : Nat) (timeoutMs : Nat) : IO (Except String Conn) := do
  let fd ← Ffi.tcpSocket
  if fd == Ffi.fdError then return .error "socket creation failed"
  let _ ← Ffi.setRecvTimeoutMs fd (timeoutMs.toUInt64)
  let conn ← Ffi.connectLoopback fd port.toUInt64
  if conn == Ffi.fdError then
    Ffi.closeFd fd
    return .error s!"connect to localhost:{port} failed"
  return .ok ⟨fd, ← IO.mkRef ByteArray.empty, ← Ffi.freshBuffer 65536, ← IO.mkRef false⟩

/-- Idempotent even when EOF framing has already closed the socket. -/
def closeConn (c : Conn) : IO Unit := do
  unless ← c.closed.modifyGet (fun closed => (closed, true)) do
    Ffi.closeFd c.fd

private def fill (c : Conn) : IO Bool := do
  let n ← Ffi.recvSome c.fd c.rbuf 65536
  if n == 0 || n == Ffi.fdError then
    return false
  c.buf.modify (fun acc => acc.append (c.rbuf.extract 0 n.toNat))
  return true

private partial def bytesEqAt (b : ByteArray) (pat : List UInt8) (j : Nat) (i : Nat) : Bool :=
  if i >= pat.length then true
  else if j + i >= b.size then false
  else if b.get! (j + i) == (pat[i]?.getD 0) then bytesEqAt b pat j (i + 1) else false

private partial def hasPattern (b : ByteArray) (pat : List UInt8) (j : Nat) : Bool :=
  if j + pat.length > b.size then false
  else if bytesEqAt b pat j 0 then true
  else hasPattern b pat (j + 1)

/-- Ensure the buffer contains at least @n@ bytes; false on EOF. -/
private partial def ensureLen (c : Conn) (n : Nat) : IO Bool := do
  let buf0 ← c.buf.get
  let mut got := buf0.size
  let mut ok := true
  while got < n && ok do
    let more ← fill c
    if !more then ok := false
    let b1 ← c.buf.get
    got := b1.size
  return ok

/-- Read until the buffer contains @pat@; false on EOF without it. -/
private partial def ensurePat (c : Conn) (pat : List UInt8) : IO Bool := do
  let b0 ← c.buf.get
  let mut b := b0
  let mut ok := true
  while !hasPattern b pat 0 && ok do
    let more ← fill c
    if !more then ok := false
    let b1 ← c.buf.get
    b := b1
  return ok

private partial def blankIdx (b : ByteArray) : Option Nat :=
  let rec go (i : Nat) : Option Nat :=
    if i + 4 > b.size then none
    else if b.get! i == 13 && b.get! (i+1) == 10 && b.get! (i+2) == 13 && b.get! (i+3) == 10
      then some i
      else go (i + 1)
  go 0

private partial def readChunked (c : Conn) : IO (Except String String) := do
  let bytes ← c.buf.get
  match parseChunkedPrefix bytes with
  | .error error => return .error error
  | .ok (some (body, consumed)) =>
      c.buf.set (bytes.extract consumed bytes.size)
      return utf8Body body
  | .ok none =>
      if ← fill c then readChunked c
      else return .error "eof in chunked body"

/-- One request/response exchange on a persistent connection: POST
without @Connection: close@, read exactly one response. The leftover
buffer stays for the next exchange. -/
def postKa (c : Conn) (port : Nat) (path : String) (body : String) :
    IO (Except String HttpResponse) := do
  if ← c.closed.get then return .error "connection is closed"
  let req := "POST " ++ path ++ " HTTP/1.1\r\n"
    ++ "Host: localhost:" ++ toString port ++ "\r\n"
    ++ "Content-Type: application/json\r\n"
    ++ "Content-Length: " ++ toString body.utf8ByteSize ++ "\r\n"
    ++ "Accept: application/json\r\n\r\n"
    ++ body
  let sent ← Ffi.sendAll c.fd req.toUTF8 (req.toUTF8.size.toUInt64)
  if sent == Ffi.fdError then return .error "send failed"
  let gotHdr ← ensurePat c [13, 10, 13, 10]
  if !gotHdr then return .error "eof in response headers"
  let b ← c.buf.get
  let some hEnd := blankIdx b | return .error "no header boundary"
  let hdrs := ascii (b.extract 0 hEnd)
  c.buf.set (b.extract (hEnd + 4) b.size)
  let lines := hdrs.splitOn "\r\n"
  let statusE := parseStatusLine (lines.head?.getD "")
  let status := match statusE with | .ok s => s | .error _ => 0
  if status == 0 then
    return .error (match statusE with | .error e => e | .ok _ => "bad status")
  let hdrTail := String.intercalate "\r\n" (lines.tail?.getD [])
  let isChunked := (((headerValue hdrTail "Transfer-Encoding").getD "").toLower == "chunked")
  if isChunked then
    match ← readChunked c with
    | .ok s => return .ok ⟨status, s⟩
    | .error e => return .error e
  else
    let lenField := headerValue hdrTail "Content-Length"
    match lenField with
    | some len =>
        match len.toNat? with
        | some n =>
            let got ← ensureLen c n
            if !got then return .error "eof in body"
            let b3 ← c.buf.get
            let bodyBytes := b3.extract 0 n
            c.buf.set (b3.extract n b3.size)
            return .ok ⟨status, ascii bodyBytes⟩
        | none => return .error s!"bad Content-Length: {len}"
    | none =>
        -- read to EOF; the connection cannot be reused afterwards
        let mut live := true
        while live do
          live ← fill c
        let b4 ← c.buf.get
        c.buf.set (ByteArray.mk (#[] : Array UInt8))
        closeConn c
        return .ok ⟨status, ascii b4⟩

/-! ## One-shot mode (spike tests) -/

/-- Read from the fd until EOF (Connection: close), accumulating. -/
private def recvAll (fd : UInt64) : IO (Except String ByteArray) := do
  let recvBuf ← Ffi.freshBuffer 65536
  let bufRef ← IO.mkRef (ByteArray.mk (#[] : Array UInt8))
  let mut loop := true
  while loop do
    let n ← Ffi.recvSome fd recvBuf 65536
    if n == Ffi.fdError then
      return .error "recv failed (timeout or connection error)"
    else if n == 0 then
      loop := false
    else
      bufRef.modify (fun acc => acc.append (recvBuf.extract 0 n.toNat))
  return .ok (← bufRef.get)

/-- t16: one-shot request with an arbitrary method to an arbitrary
IPv4 host (registry URLs use PUT). -/
def requestTo (method : String) (host : String) (port : Nat) (path : String)
    (body : String) (timeoutMs : Nat := 30000) : IO (Except String HttpResponse) := do
  match ← openConnTo host port timeoutMs with
  | .error e => return .error e
  | .ok c =>
      let req := method ++ " " ++ path ++ " HTTP/1.1\r\n"
        ++ "Host: " ++ host ++ ":" ++ toString port ++ "\r\n"
        ++ "Content-Type: application/json\r\n"
        ++ "Content-Length: " ++ toString body.utf8ByteSize ++ "\r\n"
        ++ "Connection: close\r\n\r\n"
        ++ body
      let sent ← Ffi.sendAll c.fd req.toUTF8 (req.toUTF8.size.toUInt64)
      if sent == Ffi.fdError then
        closeConn c
        return .error "send failed"
      let raw ← recvAll c.fd
      closeConn c
      match raw with
      | .error e => return .error e
      | .ok bs =>
          let some hEnd := blankIdx bs | return .error "no header boundary"
          let hdrs := ascii (bs.extract 0 hEnd)
          let bodyB := bs.extract (hEnd + 4) bs.size
          let lines := hdrs.splitOn "\r\n"
          let statusE := parseStatusLine (lines.head?.getD "")
          let status := match statusE with | .ok s => s | .error _ => 0
          if status == 0 then
            return .error (match statusE with | .error e => e | .ok _ => "bad status")
          let hdrTail := String.intercalate "\r\n" (lines.tail?.getD [])
          let isChunked := (((headerValue hdrTail "Transfer-Encoding").getD "").toLower == "chunked")
          if isChunked then
            match decodeChunked bodyB with
            | .ok s => return .ok ⟨status, s⟩
            | .error e => return .error e
          else
            match (headerValue hdrTail "Content-Length") >>= (·.toNat?) with
            | some n => return .ok ⟨status, ascii (bodyB.extract 0 (min n bodyB.size))⟩
            | none => return .ok ⟨status, ascii bodyB⟩

/-- t16: one-shot POST to an arbitrary IPv4 host (registry URLs). -/
def postTo (host : String) (port : Nat) (path : String) (body : String)
    (timeoutMs : Nat := 30000) : IO (Except String HttpResponse) :=
  requestTo "POST" host port path body timeoutMs

/-- t16: one-shot PUT (Consul's agent API verbs). -/
def putTo (host : String) (port : Nat) (path : String) (body : String)
    (timeoutMs : Nat := 30000) : IO (Except String HttpResponse) :=
  requestTo "PUT" host port path body timeoutMs

/-- One-shot HTTP/1.1 POST of a JSON body to @localhost:<port><path>@
with a bounded wait (Connection: close, response read to EOF). -/
def post (port : Nat) (path : String) (body : String)
    (timeoutMs : Nat := 30000) : IO (Except String HttpResponse) :=
  postTo "localhost" port path body timeoutMs

end Shell.Net.Http
