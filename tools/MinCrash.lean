import Shell.Transport.Tcp
import Shell.Cli
import Std.Sync.Mutex
import Std.Sync.Semaphore

/-!
# Minimal crash demo — Lean 4.33 Windows task-teardown AV

Distills the vulnerable mirror configuration to its skeleton:

* main thread runs the concurrent accept loop, parking in the socket
  shim's select between connections;
* the FIRST connection of a fresh process spawns a dedicated task whose
  closure binds a record of Std.Mutex / Std.Semaphore external objects
  plus the connection transport;
* the task recvs until EOF and returns.

On Windows (MinGW-w64, Lean 4.33.0) the process segfaults
(0xC0000005 in lean_dec_ref_cold) ~11-16ms after the client closes.
On Linux it is stable. See Docs/lean-windows-teardown-analysis.md.

Driver: spawn, sleep 3, connect, close, poll for exit code.
-/

structure FakeStore where
  mux : Std.Mutex Nat
  sem : Std.Semaphore

/-- The session task body: bind the store's externals (touch the mutex),
then drain the transport to EOF, exactly like the mirror's recv loop. -/
partial def session (store : FakeStore) (t : Shell.Transport.Transport) : IO Unit := do
  store.mux.atomically (pure ())
  let _sem := store.sem          -- binding suffices per the analysis
  match ← t.recv with
  | none => return ()
  | some _ => session store t

/-- Variant: bind the store but never recv (task returns immediately
after accept). -/
def sessionNoRecv (store : FakeStore) (_t : Shell.Transport.Transport) : IO Unit := do
  store.mux.atomically (pure ())
  let _sem := store.sem
  return ()

/-- Variant: recv to EOF but no external objects in the closure. -/
partial def sessionNoStore (t : Shell.Transport.Transport) : IO Unit := do
  match ← t.recv with
  | none => return ()
  | some _ => sessionNoStore t

/-- Variant: PURE — no shim calls at all. One dedicated task captures a
fresh record (IO.Ref + 64 KiB ByteArray, the same shape the connection
closure carries); the main thread then parks in IO.sleep (a runtime
condvar wait, NOT our FFI). Tests whether the FFI is necessary at all. -/
def pureSleep : IO Unit := do
  let big := ByteArray.mk ((List.replicate 65536 0).toArray)
  let ref ← IO.mkRef big
  let t ← IO.asTask (prio := .dedicated) (do
    let b ← ref.get
    IO.eprintln s!"task ran, payload {b.size} bytes")
  IO.eprintln "pure-sleep: main parking 5s while task tears down"
  IO.sleep 5000
  IO.eprintln s!"pure-sleep: survived (task: {t.get.isOk})"

/-- Variant: PURE-PARK — same task, but the main thread parks in the
shim's blocking select (waitReadable on a listener, no accept).
Separates "parked in blocking FFI" from "parked in runtime sleep". -/
def purePark : IO Unit := do
  match ← Shell.Transport.Tcp.listenTcp "127.0.0.1" 19502 with
  | .error e => throw (IO.userError e)
  | .ok (lfd, _) =>
      let big := ByteArray.mk ((List.replicate 65536 0).toArray)
      let ref ← IO.mkRef big
      let _t ← IO.asTask (prio := .dedicated) (do
        let b ← ref.get
        IO.eprintln s!"task ran, payload {b.size} bytes")
      IO.eprintln "pure-park: main parking in shim select 5s"
      let _ ← Ffi.waitReadable lfd 5000
      IO.eprintln "pure-park: survived"

/-- Variant: NO CLIENT AT ALL. Hypothesis: the trigger is a dedicated
task completing while the main thread is parked inside a BLOCKING FFI
call (the shim's select), not sockets per se. Listen, then loop:
spawn a trivial dedicated task, park 200ms in waitReadable. -/
partial def noClientLoop (lfd : UInt64) : IO Unit := do
  let _t ← IO.asTask (prio := .dedicated) (pure ())
  let _ ← Ffi.waitReadable lfd 200
  noClientLoop lfd

/-- Variant: ACCEPT-TRIVIAL — accept a real connection (main does the
full wake/accept/FFI cycle) but the spawned task is trivial (captures
nothing, never touches the fd). Separates accept-cycle timing from
closure-graph content. -/
partial def acceptTrivialLoop (lfd : UInt64) : IO Unit := do
  let ready ← Ffi.waitReadable lfd 200
  if ready == 1 then
    let cfd ← Ffi.acceptFd lfd
    if cfd != Ffi.fdError then
      let _t ← IO.asTask (prio := .dedicated) (pure ())
      Ffi.closeFd cfd
  acceptTrivialLoop lfd

/-- Variant: PURE-CYCLE — the last cell. Task captures the record
(IO.Ref + 64 KiB ByteArray, like the connection closure) and finishes;
the main thread does the accept-loop's WAKE-CYCLE pattern (200ms sleep,
small allocation) but never touches the shim. If this crashes, the FFI
is not necessary at all. -/
def pureCycle : IO Unit := do
  let big := ByteArray.mk ((List.replicate 65536 0).toArray)
  let ref ← IO.mkRef big
  let _t ← IO.asTask (prio := .dedicated) (do
    let b ← ref.get
    IO.eprintln s!"task ran, payload {b.size} bytes")
  IO.eprintln "pure-cycle: main wake-cycling 5s (no FFI)"
  for _ in [0:25] do
    IO.sleep 200
    let _junk := ByteArray.mk ((List.replicate 128 0).toArray)
  IO.eprintln "pure-cycle: survived"

def main : IO Unit := do
  let mux ← Std.Mutex.new 0
  let sem ← Std.Semaphore.new 1
  let store := (⟨mux, sem⟩ : FakeStore)
  let args ← _root_.getArgsIO
  match args with
  | ["pure-sleep"] => pureSleep
  | ["pure-park"] => purePark
  | ["pure-cycle"] => pureCycle
  | ["accept-trivial"] =>
      match ← Shell.Transport.Tcp.listenTcp "127.0.0.1" 19503 with
      | .error e => throw (IO.userError e)
      | .ok (lfd, _) =>
          IO.eprintln "mincrash accept-trivial: listening on 19503"
          acceptTrivialLoop lfd
  | ["no-client"] =>
      match ← Shell.Transport.Tcp.listenTcp "127.0.0.1" 19501 with
      | .error e => throw (IO.userError e)
      | .ok (lfd, _) =>
          IO.eprintln "mincrash no-client: spawning tasks while parked in select"
          noClientLoop lfd
  | _ =>
      IO.eprintln "mincrash: listening on 127.0.0.1:19500"
      match args with
      | ["no-recv"]  => Shell.Transport.Tcp.serveTcpConcurrentOn "127.0.0.1" 19500 (sessionNoRecv store)
      | ["no-store"] => Shell.Transport.Tcp.serveTcpConcurrentOn "127.0.0.1" 19500 sessionNoStore
      | _ => Shell.Transport.Tcp.serveTcpConcurrentOn "127.0.0.1" 19500 (session store)
