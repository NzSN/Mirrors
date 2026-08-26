# Worker-Pool Server Concurrency — Design

> Status: **approved, in implementation** (t33, shell-engineer)
> Supersedes: the per-connection dedicated-task model of t31, and the
> t31-follow-up Windows sync fallback.
> Context docs: `lean-windows-teardown-analysis.md` (the crash),
> `async-enablement-design.md` (the async operations this restores on
> Windows).

## 1. Problem

The async server (t31) spawns one dedicated `Task` per connection.
On Windows (Lean 4.33, MinGW-w64) the **completion** of such a task —
in the accept-loop + connection-record-closure configuration — trips a
reference-count teardown race inside the runtime
(`lean_dec_ref_cold` NULL-field read, ~15 ms after session end,
100 % reproducible on the first connection of a fresh process;
measured and disassembly-pinned in the teardown analysis).

Options weighed:

| Option | Verdict |
| ------ | ------- |
| Status quo: Windows sync-only | Rejected by the user — async must work on Windows |
| Pacing (`IO.sleep 1` before task return) | Measured 0/8 crashes, but a *timing* patch: fragile against any runtime/library timing shift |
| **Worker pool: tasks never complete** | **Chosen** — eliminates the hazard *structurally* |

## 2. Design

```
accept loop (main thread)                 N long-lived workers
  signal flag check                       (spawned once at startup,
  park in select(200ms) ──┐                never return in normal
  acceptFd ───────────────┴─► bounded ──►  operation)
                                queue      worker_i: sem.wait → pop →
                           (Mutex+Sem+     runTcpConn → loop)
                            IO.Ref List)
```

1. **Unchanged API.** `serveTcpConcurrentOn` /`serveTlsConcurrentOn`
   keep names and signatures; `Shell/Cli.lean` does not change. The
   Windows sync branch in `Cli.lean` is deleted — the pool replaces it
   on both platforms (uniformity beats special cases; Linux gains a
   bounded-thread server too).
2. **Queue.** `Std.Mutex` + `Std.Semaphore` + `IO.Ref (List …)`.
   Workers block on the semaphore (no spin), pop under the mutex, and
   run the existing `runTcpConn` unchanged (transport construction,
   exception containment, `closeFd`). Bounded pending queue (128);
   beyond that the accept loop simply waits — the kernel listen backlog
   holds the clients (no drop-oldest, no silent loss).
3. **Sizing.** Pool size = `--jobs N` (default 4) on both server
   modes; `--serve` gains the flag (Haskell-compatible usage
   preserved: port and `--bind` keep their positions).
4. **Shutdown.** Signal flag → stop accepting → the shim's direct
   `dsh_exit` (it exists precisely because parked dedicated tasks keep
   the runtime alive). Workers are never torn down — no exit-time race
   either.
5. **Untouched:** the job store's per-job tasks (proven safe on Windows
   by jobstore_spec — they lack the accept-loop/connection lifecycle),
   Core.Jobs, all proofs, all codecs.

## 3. Safety argument

The crash's necessary conditions (measured bisection matrix): fresh
process + accept loop + a dedicated task that captures the connection
record **and completes**. The pool removes task completion from normal
operation entirely: workers are created once and block in the semaphore
between sessions. No per-connection spawn, no per-connection teardown,
no window. This is why it beats pacing (which only shrinks the window).

Residual risk: shutdown-time teardown — addressed by `dsh_exit` with
workers parked (section 2.4). Lean-side queue state is plain heap data,
no new external objects.

## 4. Acceptance criteria (t33 exit bar)

1. Full `lake test` 10/10 green on Linux.
2. On windows-dev: build green; `async_spec` **un-skipped and green**
   (it self-skips on Windows today).
3. **Stress**: 300 rapid connect/disconnect cycles with real async
   sessions (submit/await/cancel mix) against a locally-run pool
   `mirror.exe` — zero crashes.
4. Service redeploy on r-windev (backup `ModelMirrors.exe.old18`):
   `SERVICE_RUNNING`, live mTLS validate `VALID`, plus a 100-cycle
   hammer against the live service.
5. **Hard rollback condition**: any crash in the Windows stress run →
   restore the sync branch, do not ship.
6. Docs: this file, `async-enablement-design.md` §6 re-enable note,
   README/CHANGELOG/cutover updates.

## 5. Follow-ups (out of scope here)

- The upstream Lean issue remains drafted, unfiled
  (`Drafts/lean4-windows-task-teardown-crash.md`); the pool is our
  mitigation regardless of an upstream fix.
- The 1 ms pacing patch remains available as defense-in-depth but is
  not applied under the pool model.
