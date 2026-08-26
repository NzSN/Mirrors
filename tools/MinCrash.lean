import Std.Sync.Mutex
import Std.Sync.Semaphore

/-!
# MinCrash — PURE variant harness (FFI-free)

FFI-free companion of the Windows task-teardown crash investigation
(Docs/lean-windows-teardown-analysis.md). The socket-based variants that
actually crash (accept loop + dedicated task capturing the connection
record) were REMOVED per request — they live in git history (commit
078bd71 era) and on windows-dev at /d/ModelMirrors/lean4-mincrash.

What remains is the pure-Lean control/bisection harness: dedicated tasks
capturing various closure payloads (records, toolchain externals) under
different main-thread parking patterns. All variants SURVIVE on Windows
(0 crashes) — that is the finding: within this matrix, the crash needs
the socket-FFI accept lifecycle in conjunction with the task closure.

Usage: mincrash-lean <variant>
  record-sleep   task captures IO.Ref + 64 KiB ByteArray; main IO.sleep
  record-cycle   same task; main wake-cycles with small allocations
  externals      task binds Std.Mutex + Std.Semaphore; main sleeps
  spawn-loop     200 trivial dedicated tasks while main cycles
-/

structure FakeStore where
  mux : Std.Mutex Nat
  sem : Std.Semaphore

def bigPayload : ByteArray := ByteArray.mk ((List.replicate 65536 0).toArray)

def recordSleep : IO Unit := do
  let ref ← IO.mkRef bigPayload
  let _t ← IO.asTask (prio := .dedicated) (do
    let b ← ref.get
    IO.eprintln s!"task ran, payload {b.size} bytes")
  IO.eprintln "record-sleep: main parking 5s"
  IO.sleep 5000
  IO.eprintln "record-sleep: survived"

def recordCycle : IO Unit := do
  let ref ← IO.mkRef bigPayload
  let _t ← IO.asTask (prio := .dedicated) (do
    let b ← ref.get
    IO.eprintln s!"task ran, payload {b.size} bytes")
  IO.eprintln "record-cycle: main wake-cycling 5s"
  for _ in [0:25] do
    IO.sleep 200
    let _junk := ByteArray.mk ((List.replicate 128 0).toArray)
  IO.eprintln "record-cycle: survived"

def externals : IO Unit := do
  let store : FakeStore := ⟨← Std.Mutex.new 0, ← Std.Semaphore.new 1⟩
  let _t ← IO.asTask (prio := .dedicated) (do
    store.mux.atomically (pure ())
    let _sem := store.sem
    IO.eprintln "task ran, externals bound")
  IO.eprintln "externals: main parking 5s"
  IO.sleep 5000
  IO.eprintln "externals: survived"

partial def spawnLoop (n : Nat) : IO Unit := do
  if n == 0 then return ()
  let _t ← IO.asTask (prio := .dedicated) (pure ())
  IO.sleep 50
  spawnLoop (n - 1)

def spawnLoopMain : IO Unit := do
  IO.eprintln "spawn-loop: 200 trivial dedicated tasks"
  spawnLoop 200
  IO.sleep 2000
  IO.eprintln "spawn-loop: survived"

def main (args : List String) : IO Unit := do
  match args with
  | ["record-sleep"] => recordSleep
  | ["record-cycle"] => recordCycle
  | ["externals"] => externals
  | ["spawn-loop"] => spawnLoopMain
  | _ => IO.eprintln "usage: mincrash-lean <record-sleep|record-cycle|externals|spawn-loop>"
