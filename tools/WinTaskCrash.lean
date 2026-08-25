/-
Copyright (c) 2026 ModelMirrors contributors. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/

import Std.Sync.Mutex
import Std.Sync.Semaphore

/-!
# t32: minimal repro for the Lean 4.33 Windows task-teardown crash

NOT wired into any gate. Reproduces the r-windev segfault observed in
the t31 follow-up (Docs/async-enablement-design.md sec 6): a fresh
process whose FIRST task binds a Std.Mutex / Std.Semaphore (external
objects) crashes on Windows shortly after the task completes, while
the main thread keeps allocating. Never reproduces on Linux.

Usage: wintaskcrash a|b|c|d|e [seconds]
  a  task binds a Std.Mutex created on the main thread   (expected: crash on Windows)
  b  task binds a Std.Semaphore created on the main thread (expected: crash on Windows)
  c  task binds nothing                                    (expected: clean)
  d  task creates and binds a Std.Mutex inside the task    (expected: crash on Windows)
  e  main creates a Std.Mutex but the task does not bind it (expected: clean)
-/

def allocALittle : IO Unit := do
  -- mimic the accept loop's per-iteration allocations (refs, strings)
  let r ← IO.mkRef (List.replicate 8 (0 : Nat))
  r.modify (fun a => a.length :: a)
  let s := toString (← r.get).length
  if s.length > 1000 then IO.eprintln s

def runVariant (v : String) (secs : Nat) : IO UInt32 := do
  let m ← Std.Mutex.new (0 : Nat)
  let sem ← Std.Semaphore.new 1
  let bind : IO Unit :=
    match v with
    | "a" => do let _ := m; pure ()          -- bind mutex only
    | "b" => do sem.release
    | "c" => pure ()
    | "d" => do
        let m2 ← Std.Mutex.new (0 : Nat)
        m2.atomically (fun _ => pure ())
    | "e" => pure ()                          -- mutex exists but unbound
    | _ => pure ()
  let task ← IO.asTask (prio := .dedicated) do
    -- closer to the real session body: bind the externals AND do
    -- worker-thread IO + allocations (refs, list building)
    bind
    let r ← IO.mkRef ([] : List Nat)
    for i in [0:2000] do
      r.modify (fun l => i :: l)
    let n := (← r.get).length
    if n > 100000 then IO.eprintln "impossible"
  let _ := task
  -- main thread keeps running and allocating like the accept loop
  for _ in [0:secs * 20] do
    allocALittle
    IO.sleep 50
  IO.println s!"VARIANT {v} SURVIVED"
  return 0

def main (argv : List String) : IO UInt32 := do
  let v := argv.headD "a"
  let secs := (argv.drop 1).headD "3" |>.toNat?.getD 3
  runVariant v secs