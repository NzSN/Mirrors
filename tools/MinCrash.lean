import Shell.Transport.Tcp
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

def main : IO Unit := do
  let mux ← Std.Mutex.new 0
  let sem ← Std.Semaphore.new 1
  let store := (⟨mux, sem⟩ : FakeStore)
  IO.eprintln "mincrash: listening on 127.0.0.1:19500"
  Shell.Transport.Tcp.serveTcpConcurrentOn "127.0.0.1" 19500 (session store)
