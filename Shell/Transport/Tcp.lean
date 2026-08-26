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
  /-- t31: per-connection 64 KiB receive scratch. A single shared
module-level buffer was a latent cross-connection data race once
sessions run concurrently, and the shared constant was implicated in a
Windows-only heap corruption segfault; allocating it per connection
(in the accept thread, before the session task starts) removes both. -/
  rbuf : ByteArray

def tcpClose (t : TcpTransport) : IO Unit := Ffi.closeFd t.fd

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
          let n ← Ffi.recvSome t.fd t.rbuf 65536
          if n == 0 || n == Ffi.fdError then
            eof := true
          else
            acc := acc.append (t.rbuf.extract 0 n.toNat)
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
  return .ok (tcpTransport ⟨fd, ← IO.mkRef (ByteArray.mk (#[] : Array UInt8)),
    ByteArray.mk ((List.replicate 65536 0).toArray)⟩)

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
      let t := tcpTransport ⟨cfd, ← IO.mkRef (ByteArray.mk (#[] : Array UInt8)), ByteArray.mk ((List.replicate 65536 0).toArray)⟩
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

/-- t33: bounded connection queue for the worker-pool server model
(Docs/worker-pool-design.md). Two semaphores form the classic bounded
producer/consumer queue: workers block on @items@, the accept loop
blocks on @spaces@ when the backlog is full (the kernel listen backlog
then holds the clients — no drops, no silent loss). -/
structure ConnQueue where
  items : Std.Semaphore
  spaces : Std.Semaphore
  mu : Std.Mutex (List (UInt64 × String))

namespace ConnQueue

def new (capacity : Nat := 128) : BaseIO ConnQueue := do
  return { items := ← Std.Semaphore.new 0,
           spaces := ← Std.Semaphore.new (max 1 capacity),
           mu := ← Std.Mutex.new [] }

private def acquireWait (s : Std.Semaphore) : IO Unit := do
  let p ← s.acquire
  -- t33 fix: IO.wait, NOT Task.get — Task.get on the unresolved promise
  -- task returns immediately (Lean 4.33, both platforms, any task
  -- priority; Docs/worker-pool-impl-status.md §3), which spun workers
  -- on phantom queue entries and disabled the spaces bound. IO.wait is
  -- the documented blocking wait and probes clean.
  let _ ← IO.wait p.result?
  return ()

/-- Enqueue one accepted connection; blocks when the backlog is full. -/
def push (q : ConnQueue) (cfd : UInt64) (peer : String) : IO Unit := do
  acquireWait q.spaces
  q.mu.atomically (modify fun items => items ++ [(cfd, peer)])
  q.items.release

/-- Dequeue the oldest pending connection; blocks until one arrives. -/
partial def pop (q : ConnQueue) : IO (UInt64 × String) := do
  acquireWait q.items
  let item? ← q.mu.atomically do
    let items ← get
    match items with
    | [] => return none
    | x :: rest => set rest; return some x
  match item? with
  | some item =>
      q.spaces.release
      return item
  | none =>
      -- Unreachable while the semaphore counts entries. Re-wait instead
      -- of fabricating (0, "") (the old fallback): a phantom fd 0 went
      -- straight into session handlers and closeFd, closing the
      -- process's own stdin.
      IO.eprintln "tcp: ConnQueue.pop: permit without entry (queue desync); re-waiting"
      pop q

end ConnQueue

/-- t33: one long-lived connection worker (Docs/worker-pool-design.md):
block on the queue, handle one connection, loop. Workers NEVER return
in normal operation — the Lean 4.33 Windows task-teardown race
(Docs/lean-windows-teardown-analysis.md) fires on task COMPLETION, so
the pool removes completion instead of pacing it. -/
partial def connWorker (q : ConnQueue) (handle : UInt64 → String → IO Unit) : IO Unit := do
  let (cfd, peer) ← q.pop
  handle cfd peer
  connWorker q handle

/-- t33: spawn @max 1 workers@ dedicated pool workers on @q@. -/
def spawnPool (workers : Nat) (q : ConnQueue)
    (handle : UInt64 → String → IO Unit) : IO Unit := do
  for _ in [0:max 1 workers] do
    let _ ← IO.asTask (prio := Task.Priority.dedicated) (connWorker q handle)

/-- t33: the pool-model accept loop (Haskell concurrent serve shape):
signal-aware select poll, accept, enqueue. The loop never spawns a
session task; workers consume the queue. On the signal flag it returns
(the caller's direct-exit path then ends the process with workers still
parked — no exit-time teardown race). -/
partial def loopAcceptPool (lfd : UInt64) (q : ConnQueue) : IO Unit := do
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
      q.push cfd peer
  else if ready == Ffi.fdError then
    return ()
  loopAcceptPool lfd q

/-- Opt-in teardown tracing for the crash investigation (zero cost
unless DSH_TCP_DEBUG is set): timestamps the exact post-session steps
so a crash dump shows whether closeFd ran. -/
private def tcpDbg (msg : String) : IO Unit := do
  match ← IO.getEnv "DSH_TCP_DEBUG" with
  | some _ => IO.eprintln s!"[tcp] {msg}"
  | none => pure ()

/-- t31: per-connection body, top-level like @Shell.Jobs.jobThread@
(the store's job tasks, whose bodies are top-level functions, are the
one task shape that has never crashed on Windows). -/
private def runTcpConn (session : Transport → IO Unit) (peer : String)
    (cfd : UInt64) : IO Unit := do
  let t := tcpTransport ⟨cfd, ← IO.mkRef (ByteArray.mk (#[] : Array UInt8)),
      ByteArray.mk ((List.replicate 65536 0).toArray)⟩
  try
    session t
  catch e =>
    IO.eprintln s!"tcp: session with {peer} ended: {e}"
  tcpDbg s!"session body returned (fd={cfd})"
  Ffi.closeFd cfd
  tcpDbg s!"closeFd done (fd={cfd}) — task teardown next"

partial def serveTcpConcurrentOn (host : String) (port : Nat)
    (session : Transport → IO Unit) (workers : Nat := 4) : IO Unit := do
  match ← listenTcp host port with
  | .error e => throw (IO.userError s!"serveTcpConcurrentOn: {e}")
  | .ok (lfd, bound) =>
      IO.eprintln s!"tcp: listening on {if host.isEmpty then "*" else host}:{bound} (worker pool, {max 1 workers} workers)"
      let q ← ConnQueue.new
      spawnPool workers q (fun cfd peer => runTcpConn session peer cfd)
      loopAcceptPool lfd q

end Shell.Transport.Tcp