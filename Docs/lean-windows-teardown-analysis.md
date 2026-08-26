# Lean 4.33 (MinGW-w64/Windows) task-teardown crash — analysis (t32)

Outcome: the crash is pinned to a **NULL object pointer reaching
`lean_dec_ref_cold` inside the Lean runtime** while a dedicated task
worker thread tears down / executes the session-task closure chain.
It is a memory-safety bug in the runtime/compiler stack on Windows,
not in mirror code. A standalone <60-line repro did NOT reproduce it;
the repro condition so far requires the real server's session graph.
Everything below is measured on windows-dev (elan v4.33.0,
MinGW-w64/UCRT64 static libleanshared, mimalloc).

## Measured facts

Trigger (from the t31 follow-up + this task's runs):
- fresh process + FIRST connection's session task; session duration
  irrelevant (0ms-10s all crash); death 11-16ms after the client
  closes; one-process-many-sessions never crashes.
- sync sessions on task threads: clean. Trivial tasks (300 cycles):
  clean. Merely BINDING the shared JobStore (Std.Mutex /
  Std.Semaphore = LeanExternal objects) in the task body is
  sufficient; the store need not be used.
- A 3-line python one-cycle driver against the vulnerable binary
  (spawn `--serve`, sleep 3, connect, close) crashes 3/3 (exit
  0xC0000005). Under cdb the same flow crashes deterministically.

## Stack (cdb + linker map + nm symbol table, image base 0x140000000)

Crashing thread (dedicated task worker, second-chance AV):

    lean_dec_ref_cold+0x7a      <- mov r9d,[r8] with r8 == 0  (FAULT)
    lean_apply_1+0x1b10         (compiled-closure application tail:
                                 the slow-path dec of the applied
                                 closure / its fields)
    lean_apply_2+0x246          (closure application chain of the
                                 compiled session code)
    lthread::imp::_main+0x1c    (dedicated worker thread entry)
    KERNEL32!BaseThreadInitThunk

i.e. during/after the session-task closure application, the runtime
decrements the reference count of a **NULL** `lean_object*`.
`lean_dec` only skips *scalars* (tagged small integers); a NULL is
treated as a heap object and dereferenced. There is no application
path in Lean 4 that legitimately stores NULL in an object field, so
either

  a) a closure/task object was freed and its memory reused/zeroed
     before the worker's dec cascade reached it (use-after-free), or
  b) an uninitialized (zero-filled) object slot was consumed as an
     object reference.

Both are runtime-level defects; the timing (11-16ms post-close, first
task of the process, external objects in the closure graph being the
differentiator) fits a **task-completion teardown race**: the worker
frees the closure graph (`resolve_core` -> `free_task_imp`, the
`lean_dec_ref(f)` tails in `lean_apply_1/2`, `deactivate_task`'s
`dec_ref(c)`) while another actor (main thread dropping the task
reference, or the keep-alive self-decrement) concurrently walks the
same objects. object.cpp `run_task`/`resolve_core`/
`deactivate_task_core` perform the imp/closure ownership handovers
under the task-manager mutex, but the *RC decrements themselves* are
outside it; the Windows scheduler/timing makes the losing interleaving
reachable where Linux does not.

Why the externals matter (hypothesis, not proven): the
`Std.Mutex`/`Std.Semaphore` external objects give the closure graph
a wide, shallow shape with LeanExternal leaves whose finalizer
(`delete mutex`) runs on whichever thread's dec hits zero; that
widens the teardown window in which the losing interleaving can pick
up a freed/zeroed slot.

## Minimal demo (t32 follow-up, captain)

`tools/MinCrash.lean` (~50 lines + the socket shim) reproduces the
crash **6/6** on Windows with a bare connect/close client, distilling
the server to: concurrent accept loop (main parks in the shim's
`select`), first connection spawns a dedicated task whose closure
captures the connection record, task ends at client close.

Bisection variants (all 6/6 on Windows unless noted):

| Variant | Closure captures | Result |
| ------- | ---------------- | ------ |
| default | store (mutex+sem) + transport, recv to EOF | DEAD |
| `no-recv` | store + transport, returns immediately | DEAD |
| `no-store` | transport only (fd + IO.Ref + 64 KiB scratch), recv to EOF | DEAD |
| `no-client` | nothing — trivial dedicated tasks while main parks in `waitReadable`, no accept | **ALIVE** |
| `accept-trivial` | nothing — real accept, but the task is trivial and never touches the fd | **ALIVE** (0/6) |
| `pure-sleep` | record (IO.Ref + 64 KiB ByteArray), main in `IO.sleep` — no FFI at all | **ALIVE** (0/3) |
| `pure-park` | record, main parked in the shim's `select`, no accept | **ALIVE** (0/3) |
| `pure-cycle` | record, main wake-cycling with allocations — no FFI at all | **ALIVE** (0/5) |

**Is the FFI necessary?** Empirically yes for every repro we have:
the crash needs the CONJUNCTION of (a) a real accepted connection
(`acceptFd`'s fresh fd, closed during teardown) and (b) the session
task capturing the connection record. Neither alone suffices
(accept-trivial and pure-* are all clean). The FFI's role is
structural — it manufactures the per-connection fd lifecycle that
interleaves with the task teardown; the fault itself is 100% inside
libleanshared (no shim frames in the stack). A universal negative
(some pure-Lean program could never trigger the same race) is NOT
proven — the honest statement is: within this matrix, FFI involvement
is necessary.

So the external objects (Std.Mutex/Semaphore) are **not necessary**;
the necessary ingredients are: (a) fresh process, (b) main thread in
the accept loop, (c) a dedicated task capturing the accepted
connection's record (fd + IO.Ref + big ByteArray closure graph), (d)
quick completion. Compare `tools/WinTaskCrash.lean` (task + mutex, no
accept loop): survives — the accept-loop/transport-capture ingredient
is the missing piece there.

## Minimal repro status (honest)

`tools/WinTaskCrash.lean` (committed, NOT wired into gates) spawns
the process's first dedicated task with variants: (a) bind a
Std.Mutex, (b) use a Std.Semaphore, (c) nothing, (d) create+bind a
mutex inside the task, (e) mutex exists but unbound; the main thread
keeps allocating like the accept loop. **All variants survive on
Windows.** So the binding of external objects alone is not sufficient;
the real server's session task additionally carries the transport/IO
closure graph and is spawned from the accept loop while the main
thread parks in the shim's `select`. The reliable reproducer remains
the real binary + the one-cycle driver
(`/d/ModelMirrors/tmp/onecrash.py` on windows-dev: spawn vulnerable
mirror --serve PORT, sleep 3, connect, close, poll rc ->
0xC0000005).

## Artifacts on windows-dev (scratch, may be deleted)

- /d/mm2.exe + /d/mm2.map — map-linked rebuild of the vulnerable
  tree (crashes 3/3 without cdb, so the relink preserves the bug).
- /d/t32.log, /d/t33.log — cdb captures (the t33 one holds the
  crashing-thread stack quoted above).
- /d/ModelMirrors/tmp/onecrash.py, connclose.py — minimal drivers.
- /d/ModelMirrors/lean4-async — vulnerable checkout + wintaskcrash.

## Recommendation

Upstream issue with: the stack above, the v4.33.0 runtime frames, the
one-cycle driver, and the observation that the task closure graph must
contain external objects for the losing interleaving to be reachable.
On our side, keep the t31 follow-up mitigation (Windows serves sync
sequential sessions; async server sessions are Linux-only) until a
fixed Lean release lands.
