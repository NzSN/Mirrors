import Ffi.Socket
import Shell.Transport.Stdio
import Shell.Net.Http
import Batteries

/-!
# TCP transport (t15, design 5.4)

Port of @Protocol.Transport.Tcp@ (151 LOC Haskell) onto the @Ffi.Socket@
shim: one protocol session per connection, sequential accept loop; a
client that drops mid-session logs to stderr and the loop survives.
Line framing identical to the stdio transport (one JSON message per
line, LF/CRLF stripped on receive, LF appended and flushed on send).

Addresses: the shim is IPv4; @localhost@ resolves to @127.0.0.1@, and
@serveTcpOn ""@ binds the all-interfaces wildcard like the Haskell
version. Any other host must be an IPv4 dotted literal.
-/

namespace Shell.Transport.Tcp

open Shell.Transport

private def peerDesc (fd : UInt64) : IO String := do
  let buf := ByteArray.mk ((List.replicate 64 0).toArray)
  let n ← Ffi.peerDescRaw fd buf 63
  if n == Ffi.fdError then return "?"
  return String.fromUTF8? (buf.extract 0 n.toNat) |>.getD "?"

/-- A buffered line-framed transport over one connected TCP socket. -/
structure TcpTransport where
  fd : UInt64
  buf : IO.Ref ByteArray

def tcpClose (t : TcpTransport) : IO Unit := Ffi.closeFd t.fd

/-- t31: initialize (not def) so the shared 64 KiB receive buffer is
allocated once on the main thread at startup — a plain def thunk first
evaluated inside a session task raced the runtime and segfaulted the
Windows build on quick connect/disconnect cycles. -/
private initialize recvBuf : ByteArray ← do
  return ByteArray.mk ((List.replicate 65536 0).toArray)

private def hasLf (b : ByteArray) : Bool :=
  let rec go (i : Nat) : Bool :=
    if i >= b.size then false else if b.get! i == 10 then true else go (i + 1)
  go 0

private partial def findLf (b : ByteArray) (i : Nat) : Option Nat :=
  if i >= b.size then none
  else if b.get! i == 10 then some i
  else findLf b (i + 1)

/-- Build the line-framed @Transport@ over a connected socket. -/
def tcpTransport (t : TcpTransport) : Transport :=
  { recv := do
      let mut acc ← t.buf.get
      let mut found := true
      let mut eof := false
      while found && !eof do
        if hasLf acc then
          found := false
        else
          let n ← Ffi.recvSome t.fd recvBuf 65536
          if n == 0 || n == Ffi.fdError then
            eof := true
          else
            acc := acc.append (recvBuf.extract 0 n.toNat)
      if eof && acc.isEmpty then
        return none
      else
        match findLf acc 0 with
        | none =>
            t.buf.set (ByteArray.mk (#[] : Array UInt8))
            return some (stripEol (String.fromUTF8? acc |>.getD ""))
        | some i =>
            let line := acc.extract 0 i
            t.buf.set (acc.extract (i + 1) acc.size)
            return some (stripEol (String.fromUTF8? line |>.getD ""))
    send := fun s => do
      let bs := (s ++ "\n").toUTF8
      let r ← Ffi.sendAll t.fd bs bs.size.toUInt64
      if r == Ffi.fdError then
        throw (IO.userError "tcp send failed") }

/-- Connect to @host:port@ and return a ready transport (Haskell
@connectTcp@). @host@ is @localhost@ or an IPv4 dotted literal. -/
def connectTcp (host : String) (port : Nat) : IO (Except String Transport) := do
  let ip := if host == "localhost" || host.isEmpty then "127.0.0.1" else host
  let fd ← Ffi.tcpSocket
  if fd == Ffi.fdError then return .error "socket creation failed"
  let r ← Ffi.connectIpv4 fd ip port.toUInt64
  if r == Ffi.fdError then
    Ffi.closeFd fd
    return .error s!"connect to {host}:{port} failed"
  return .ok (tcpTransport ⟨fd, ← IO.mkRef (ByteArray.mk (#[] : Array UInt8))⟩)

/-- Open a listening socket bound to @host@ and return the listener fd
plus the bound port (port 0 picks an ephemeral port). Empty host = the
all-interfaces wildcard; otherwise the address is resolved (IPv4
literals directly, names via getaddrinfo — Haskell @serveTcpOn@ uses
AI_PASSIVE resolution the same way). An unresolvable or unbindable
host is a HARD error: t27 removed the old silent wildcard fallback
that exposed an unauthenticated --bind-restricted server on every
interface. -/
def listenTcp (host : String) (port : Nat) : IO (Except String (UInt64 × Nat)) := do
  let fd ← Ffi.tcpSocket
  if fd == Ffi.fdError then return .error "socket creation failed"
  match host with
  | "" =>
      let r ← Ffi.bindAny fd port.toUInt64
      if r == Ffi.fdError then
        Ffi.closeFd fd
        return .error s!"bind {host}:{port} failed"
  | h =>
      match ← Shell.Net.Http.resolveHost h with
      | .error e =>
          Ffi.closeFd fd
          return .error s!"cannot resolve bind address {h}: {e}"
      | .ok ip =>
          let r ← Ffi.bindAddr fd ip port.toUInt64
          if r == Ffi.fdError then
            Ffi.closeFd fd
            return .error s!"bind {h} ({ip}):{port} failed"
  let lrc ← Ffi.listenFd fd
  if lrc == Ffi.fdError then
    Ffi.closeFd fd
    return .error "listen failed"
  let actual ← Ffi.localPort fd
  if actual == Ffi.fdError then
    Ffi.closeFd fd
    return .error "getsockname failed"
  return .ok (fd, actual.toNat)

private partial def loopAccept (lfd : UInt64) (session : Transport → IO Unit) : IO Unit := do
  -- poll instead of blocking in accept(2): check the signal flag
  -- every iteration (the signal may land on any thread) so cleanup
  -- happens promptly and other tasks stay schedulable
  let sig0 ← Ffi.signalFired
  if sig0 == 1 then
    return ()
  let ready ← Ffi.waitReadable lfd 200
  if ready == 1 then
    let cfd ← Ffi.acceptFd lfd
    if cfd == Ffi.fdError then
      let sig ← Ffi.signalFired
      if sig == 1 then
        return ()
      else
        IO.eprintln "tcp: accept failed; continuing"
    else
      let peer ← peerDesc cfd
      let t := tcpTransport ⟨cfd, ← IO.mkRef (ByteArray.mk (#[] : Array UInt8))⟩
      try
        session t
      catch e =>
        IO.eprintln s!"tcp: session with {peer} ended: {e}"
      Ffi.closeFd cfd
  else if ready == Ffi.fdError then
    return ()
  loopAccept lfd session

/-- Serve one session per accepted connection, sequentially, forever
(Haskell @serveTcpOn@ / @serveTcp@). Session errors and abrupt peer
drops are logged to stderr and the accept loop survives; the loop only
exits if binding the listener fails. -/
partial def serveTcpOn (host : String) (port : Nat)
    (session : Transport → IO Unit) : IO Unit := do
  match ← listenTcp host port with
  | .error e => throw (IO.userError s!"serveTcpOn: {e}")
  | .ok (lfd, bound) =>
      IO.eprintln s!"tcp: listening on {if host.isEmpty then "*" else host}:{bound}"
      loopAccept lfd session

/-- Haskell @serveTcp@: bind the all-interfaces wildcard. -/
def serveTcp (port : Nat) (session : Transport → IO Unit) : IO Unit :=
  serveTcpOn "" port session

/--- t31: concurrent variant of @serveTcpOn@ (Haskell
@serveTcpConcurrent@): each accepted connection gets its session on a
task, so slow or async-job-holding sessions never block the
accept loop or each other. Connection lifecycle (close on drop) moves
into the per-connection task. -/
/-- t31: per-connection body, top-level like @Shell.Jobs.jobThread@
(the store's job tasks, whose bodies are top-level functions, are the
one task shape that has never crashed on Windows). -/
private def runTcpConn (session : Transport → IO Unit) (peer : String)
    (cfd : UInt64) : IO Unit := do
  let t := tcpTransport ⟨cfd, ← IO.mkRef (ByteArray.mk (#[] : Array UInt8))⟩
  try
    session t
  catch e =>
    IO.eprintln s!"tcp: session with {peer} ended: {e}"
  Ffi.closeFd cfd

private partial def loopAcceptConcurrent (lfd : UInt64)
    (liveTasks : IO.Ref (Array (Task (Except IO.Error Unit))))
    (session : Transport → IO Unit) : IO Unit := do
  let sig0 ← Ffi.signalFired
  if sig0 == 1 then
    return ()
  let ready ← Ffi.waitReadable lfd 200
  if ready == 1 then
    let cfd ← Ffi.acceptFd lfd
    if cfd == Ffi.fdError then
      let sig ← Ffi.signalFired
      if sig == 1 then
        return ()
      else
        IO.eprintln "tcp: accept failed; continuing"
    else
      let peer ← peerDesc cfd
      let task ← IO.asTask (prio := .dedicated) (runTcpConn session peer cfd)
      -- keep the task reference live until the runtime retires it:
      -- dropping the only reference immediately lets the GC free the
      -- task object (and its closure) while the worker thread may
      -- still be tearing down (observed as a Windows-only segfault on
      -- quick connect-disconnect cycles)
      liveTasks.modify (fun ts => ts.push task)
      if (← liveTasks.get).size > 128 then
        liveTasks.set (#[] : Array (Task (Except IO.Error Unit)))
  else if ready == Ffi.fdError then
    return ()
  loopAcceptConcurrent lfd liveTasks session

partial def serveTcpConcurrentOn (host : String) (port : Nat)
    (session : Transport → IO Unit) : IO Unit := do
  match ← listenTcp host port with
  | .error e => throw (IO.userError s!"serveTcpConcurrentOn: {e}")
  | .ok (lfd, bound) =>
      IO.eprintln s!"tcp: listening on {if host.isEmpty then "*" else host}:{bound} (concurrent)"
      let liveTasks ← IO.mkRef (#[] : Array (Task (Except IO.Error Unit)))
      loopAcceptConcurrent lfd liveTasks session

end Shell.Transport.Tcp