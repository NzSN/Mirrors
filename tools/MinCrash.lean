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

/-- Variant: NO CLIENT AT ALL. Hypothesis: the trigger is a dedicated
task completing while the main thread is parked inside a BLOCKING FFI
call (the shim's select), not sockets per se. Listen, then loop:
spawn a trivial dedicated task, park 200ms in waitReadable. -/
partial def noClientLoop (lfd : UInt64) : IO Unit := do
  let _t ← IO.asTask (prio := .dedicated) (pure ())
  let _ ← Ffi.waitReadable lfd 200
  noClientLoop lfd

def main : IO Unit := do
  let mux ← Std.Mutex.new 0
  let sem ← Std.Semaphore.new 1
  let store := (⟨mux, sem⟩ : FakeStore)
  let args ← _root_.getArgsIO
  match args with
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
