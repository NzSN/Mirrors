# DRAFT — Upstream issue for leanprover/lean4 (NOT FILED)

> Status: draft, awaiting the repo owner's decision to file.
> Target: https://github.com/leanprover/lean4/issues
> Full analysis: `Docs/lean-windows-teardown-analysis.md`
> Repro assets: windows-dev `/d/ModelMirrors/lean4-async` (vulnerable
> build) + `/d/ModelMirrors/tmp/onecrash.py` (3-line driver);
> cdb captures `/d/t32.log`, `/d/t33.log`; map-linked relink
> `/d/mm2.exe` + `/d/mm2.map`.

---

## Title

Windows (MinGW-w64/UCRT): access violation in `lean_dec_ref_cold` during dedicated-task teardown — RC cascade frees/reads a NULL object field

## Summary

On Windows builds of Lean 4.33.0, a process's **first dedicated task**
that carries external objects (e.g. `Std.Mutex`, `Std.Semaphore`) in
its closure graph crashes with an access violation (`0xC0000005`)
shortly after the task completes. Disassembly and a symbolized stack
show the reference-count teardown cascade dereferencing a NULL
`lean_object*` field — consistent with a double-free/use-after-free in
task teardown. The same code is stable on Linux (300-connection stress
clean).

## Environment

- Lean toolchain: `leanprover/lean4:v4.33.0` (elan), Windows 10,
  git-bash/MinGW-w64 UCRT64, static libleanshared + mimalloc
- Host machine: windows-dev (192.168.150.219); x86_64

## Reproduction

The reliable reproducer (3-line python driver, `onecrash.py`):

1. Start the vulnerable binary: `mirror.exe --serve PORT --bind 127.0.0.1`
   (a TCP server whose accept loop spawns each connection's session on a
   `Task.Priority.dedicated` task; the session closure binds a shared
   store containing `Std.Mutex`/`Std.Semaphore`).
2. `sleep 3` (let the accept loop park).
3. Connect to the port and close immediately (no protocol bytes).

Result: the server process exits with `0xC0000005` **11–16 ms after the
client closes**, 8/8 runs. Notably:

- Session duration does not matter: 0 ms–10 s holds all crash (0/5
  survival at every hold time tested).
- It must be the **first** connection of a **fresh process**; later
  connections on one process never crash (measured: 60–300 cycles clean
  when the first teardown does not fire).
- Trivial tasks (300 spawn/complete cycles): clean. Sync sessions on
  task threads: clean.

### Minimal demo (`tools/MinCrash.lean`, non-gate target)

A ~70-line program using the real `serveTcpConcurrentOn` accept loop
with a dummy per-connection session (no protocol, no store) crashes
6/6 with the same bare connect/close. Bisection matrix:

| Variant | Result |
| --- | --- |
| full MinCrash (accept loop + session task) | DEAD 6/6 |
| session task does not `recv` (binds the transport only) | DEAD 6/6 |
| no store at all — task captures just the connection record (fd + `IO.Ref` + 64 KiB `ByteArray`) | DEAD 6/6 |
| no client — trivial dedicated tasks while main parks in `waitReadable`, no accept | ALIVE |
| first dedicated task binding `Std.Mutex`/`Std.Semaphore`, no accept loop (`tools/WinTaskCrash.lean` a–e) | ALIVE |

So external objects are **not necessary**: the necessary ingredients
are the accept loop spawning a task that captures the connection
record. An earlier hypothesis that binding external objects suffices
was an artifact of the server's wider closure graph; they may still
widen the teardown race window but are not required.

## Stack (cdb, map + nm symbolized, image base 0x140000000)

```
lean_dec_ref_cold+0x7a      <- AV: mov r9d,[r8], r8 == NULL
lean_apply_1+0x1b10          (closure-application tail, slow-path dec)
lean_apply_2+0x246
lthread::imp::_main+0x1c     (dedicated worker thread entry)
KERNEL32!BaseThreadInitThunk
```

All frames are inside libleanshared static code; no application or shim
frames appear in the crashing stack.

## Analysis

Disassembly of `lean_dec_ref_cold` in the crashing binary shows the
faulting sequence is the constructor-field free loop:

```
mov  0x8(rcx,rax), r8    ; load field i of the object being freed
mov  (r8), r9d           ; read that field's refcount  -> r8 == NULL
```

An ordinary ctor-like object with a NULL field slot is being freed on
the worker thread. Since no legitimate Lean path stores NULL in an
object field, and mimalloc zeroes/recycles freed small blocks, the
consistent reading is that the block was **already freed and its memory
recycled**, and the RC cascade walks it a second time.

Relevant runtime structure (v4.33.0, `src/runtime/object.cpp`):

- Spawn: `lean_task_spawn_core` (object.cpp:1156) → `alloc_task` →
  `lean_mark_mt(c)` — **non-atomic** refcount sign-flips over the whole
  closure graph on the spawning thread — then `task_manager->enqueue`.
- Teardown: `run_task`/`resolve_core`/`deactivate_task_core` hand
  imp/closure ownership over **under** the task-manager mutex, but the
  `lean_dec_ref` cascades (incl. the `lean_apply_1/2` tails and
  `free_task_imp`) run **outside** it.

So a worker's teardown dec cascade and another actor's dec of the same
graph (main thread dropping its task reference, or the keep-alive
self-decrement) can interleave. On Linux the timing never loses; on
Windows the losing interleaving is reachable — matching the measured
first-task-only, duration-independent, ~15 ms post-completion behavior.

The external objects (`Std.Mutex`/`Std.Semaphore`) appear to matter
by shaping the closure graph's width and teardown timing, **not** via
their finalizers (mutex.cpp finalizers are plain C++ deletes of
SRWLOCK/CONDITION_VARIABLE wrappers, and in the crashing flow they are
still referenced elsewhere and never run on the worker).

## Suggested next step for maintainers

A debug runtime with `MI_DEBUG=full` (mimalloc verification) on Windows
should turn the NULL-field read into an immediate poison signature at
the first free, pinpointing the double-freed object. We can provide the
full repro package (binary + driver + cdb captures) and test patches.

## Workaround (ours, for the record)

We branch Windows server modes to sequential (non-task) sessions; the
concurrent async path is enabled on Linux only.

## Notes

- The bug survives a relink (map-linked rebuild crashes 3/3), so it is
  not build nondeterminism.
- `lean_dec` skips only scalars; NULL is treated as a heap object and
  dereferenced — a defensive NULL check in the free loop would turn this
  AV into a no-op, but the real defect is the double-visit, not the
  missing check.