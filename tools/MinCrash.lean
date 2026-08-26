/-!
# MinCrash — 100% pure Lean variant harness (no FFI, no externals)

Purest form of the Windows task-teardown crash bisection harness
(Docs/lean-windows-teardown-analysis.md). No FFI modules, no external
objects (Std.Mutex/Semaphore removed too — they are runtime-C-backed
externals): only ordinary Lean heap objects in task closures.

The variants that actually crash (socket accept loop + dedicated task
capturing the connection record) were removed per request; they live in
git history (commit 078bd71 era) and on windows-dev at
/d/ModelMirrors/lean4-mincrash. Every variant below SURVIVES on Windows
— the control group establishing that pure-Lean task churn with heap
payloads does not trigger the crash.

Usage: mincrash <variant>
  record-sleep   task captures IO.Ref + 64 KiB ByteArray; main IO.sleep
  record-cycle   same task; main wake-cycles with small allocations
  spawn-loop     200 trivial dedicated tasks while main cycles
-/

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
  | ["spawn-loop"] => spawnLoopMain
  | _ => IO.eprintln "usage: mincrash <record-sleep|record-cycle|spawn-loop>"
