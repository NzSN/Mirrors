# t33 Worker-Pool — Implementation Status & Validation Blockers

> Status: **BLOCKED — two defects found, release held** (2026-08-26)
> Companion to: `worker-pool-design.md` (the t33 design / acceptance bar)
> Head under test: `1f47435` ("t33: worker-pool accept loops on both
> platforms …"), Linux x86_64 + windows-dev (Lean 4.33, MinGW-w64).
> All local experiments were apalache-free (compile + TLS-handshake level
> only); apalache runs happen on r-windev only.

## 1. Implementation status vs. the design

| Design item | Status |
| ----------- | ------ |
| `ConnQueue` (Mutex + two semaphores, bounded 128) | ✅ `Shell/Transport/Tcp.lean:184` |
| Never-completing dedicated workers, `loopAcceptPool` | ✅ `Tcp.lean:225–259`; reused by TLS |
| API unchanged (`serveTcpConcurrentOn`/`serveTlsConcurrentOn`), Windows sync branch deleted | ✅ pool on both platforms from `Cli.lean` |
| `--jobs N` sizes the pool on `--server` | ✅ `serveTlsConcurrentOn … (workers := max 1 opts.jobs)` |
| `--serve` gains `--jobs` | ⚠️ **deviation** — `parseServeCli` still parses only `port [--bind]`; pool size is the hardcoded default 4 |
| `async_spec` Windows self-skip removed | ✅ (`APALACHE_MC` gate retained) |
| windows-dev tree synced + built | ✅ `D:\ModelMirrors\lean4-pool` byte-identical to HEAD (sha256 of all four touched files match), binaries built Aug 26 17:07 |

## 2. Acceptance criteria verdict

1. **Linux `lake test` 10/10** — *not yet verified* (local `lake build`
   green; apalache-gated tiers deferred to r-windev per machine policy).
2. **Windows `async_spec` un-skipped and green** — ❌ **FAILED**
   (run Aug 26 18:28, `D:\ModelMirrors\tmp\async-pool2.log`): TCP and
   mTLS scenarios passed; capacity scenario failed with
   `6: mTLS connect: TLS handshake failed`, amid **1,395,410
   `tls: handshake rejected` lines in 28 s** (~50k/s).
3. **300-cycle stress** — attempted (`pool-mtls.log` 1.78M lines/4.3s,
   `churn.log` 1.43M lines/3.4s): both are pure spam storms, not clean
   stress runs (~**414k rejected handshakes/s with 4 workers**).
4. **Service redeploy** — not done; the live service still runs the
   Aug 25 binary (`SERVICE_RUNNING`, PID 47176); no
   `ModelMirrors.exe.old18` backup exists.
5. **Hard rollback condition** — effectively triggered; hold the
   release until the fixes below land and re-validate.
6. **Docs** — only `worker-pool-design.md` exists;
   `async-enablement-design.md` §6 re-enable note, CHANGELOG, README and
   cutover updates are all still pending.

## 3. Defect A — the semaphore wait never blocks (critical)

`ConnQueue.acquireWait` (and the job store's `acquireSlot`) wait on
`Std.Semaphore.acquire`'s promise with:

```lean
let p ← s.acquire
let _acquired : Option Unit := Task.get p.result?
```

**`Task.get` on the unresolved promise task returns immediately** — it
does not park the thread. Confirmed with a 50-line network-free probe
(appendix): four workers parked on a 0-permit semaphore produced
**2.8M phantom acquires in 3 s** on Linux. Matrix:

| Wait pattern | dedicated prio | default prio |
| ------------ | -------------- | ------------ |
| `Task.get p.result?` (current code) | ❌ 2.80M phantoms/3s | ❌ 2.80M/3s |
| `Task.get p.result!` | ❌ 2.89M/3s | ❌ 2.92M/3s |
| `IO.wait p.result?` | ✅ **0** | ✅ **0** |

Consequences in the t33 pool:

- Workers spin-pop the "unreachable" `(0, "")` empty-queue fallback at
  full CPU. The TLS handler prints one `tls: handshake rejected` per
  phantom — this exactly reproduces the ~100k/s-per-worker storms in
  the windows-dev logs (1.3–1.8M lines per run).
- Every phantom also runs `closeFd 0` — i.e. **closes the server's own
  stdin**, then keeps failing cheaply forever.
- Plain-TCP workers storm *silently* (phantom recv → EOF → session
  ends without an error print), which is why the Windows TCP leg
  "looked" clean (zero `session with`/`accept failed` lines in
  `async-pool2.log`) while burning CPU identically.
- The 128-entry `spaces` bound is inoperative: `push` never blocks, so
  the accept loop never applies backpressure.

The same latent defect sits in `Shell/Jobs/Store.lean:191`
(`acquireSlot`): the `--jobs` worker-slot semaphore has never actually
throttled since t31. Masked so far because `slots == capacity` and the
store's capacity list-check fires first, so nothing observable breaks —
but the throttle is dead code as written.

**Fix (one line per site):**

```lean
let p ← s.acquire
let _ ← IO.wait p.result?
```

Proven by the probe (0 phantom acquires, both priorities).

## 4. Defect B — silent-connection starvation + test probe leak

Pool-model-specific: a connected-but-**silent** client parks a worker
forever — server-side accepted sockets carry no recv/handshake timeout,
so `SSL_accept` (and the plain-TCP session's first `recv`) block
indefinitely. N silent connections wedge the entire pool (trivial DoS).
The t31 dedicated-task model absorbed this (unbounded tasks); the
bounded pool makes workers a scarce resource — the design doc did not
account for it.

Compounding it, `async_spec`'s own up-polls (`waitServer`,
`scenarioMtls`, `scenarioCapacity`) `connectTcp` and then **drop the
`Transport` without closing** — the fd leaks for the process lifetime,
leaving exactly such a silent connection. In the `--jobs 1` capacity
scenario the leaked probe permanently parks the *only* worker, so the
real mTLS client's handshake starves until its 5 s `SO_RCVTIMEO` fires
— the deterministic `6: mTLS connect` failure seen on Windows.
Reproduced on Linux as well: after plain probes, a real mTLS handshake
to a pool server hung indefinitely.

**Fixes:**

- Test hygiene: close the up-poll probe (needs an explicit close on the
  probe connection, or poll with a real `connectTls` retry loop instead
  of bare TCP).
- Server defense: apply a bounded handshake timeout on accepted fds
  before `tlsAcceptRaw` (shim `SO_RCVTIMEO`, e.g. 10 s, cleared after
  the handshake completes).
- TCP mode: document the silent-client limitation as an accepted
  divergence from Haskell's unbounded-thread model, or add a session
  read timeout as a follow-up decision.
- Hardening: make `ConnQueue.pop`'s empty case panic (or re-wait)
  instead of returning `(0, "")`, whose downstream `closeFd 0` closes
  fd 0 on any future regression.

## 5. Recommended sequence

1. Apply the two `IO.wait` fixes (pool + job store) and the `pop`
   hardening; rebuild; re-run the appendix probe (expect 0 phantoms).
2. Fix the `async_spec` probe leak; add the TLS handshake timeout.
3. Linux: full non-apalache gates green.
4. r-windev: rebuild, `async_spec` with `APALACHE_MC` (must be green),
   300-cycle stress (submit/await/cancel mix) with zero crashes and
   **zero spam** — the log must not grow without real connections.
5. Only then: redeploy (backup `.old18`), live mTLS validate, 100-cycle
   hammer, and the §6/CHANGELOG/README/cutover doc updates.

## Appendix — phantom-acquire repro (SemProbe2)

Compile: `lake env lean -c SemProbe2.c SemProbe2.lean && lake env leanc -o SemProbe2 SemProbe2.c`
Run: `./SemProbe2 <taskget|iowait|resultbang> <ded|def>` — correct
semaphore behavior is 0 phantom acquires.

```lean
import Std.Sync.Semaphore
import Std.Sync.Mutex

def acquireTaskGet (s : Std.Semaphore) : IO Unit := do
  let p ← s.acquire
  let _acquired : Option Unit := Task.get p.result?
  return ()

def acquireIoWait (s : Std.Semaphore) : IO Unit := do
  let p ← s.acquire
  let r ← IO.wait p.result?
  return ()

def acquireResultBang (s : Std.Semaphore) : IO Unit := do
  let p ← s.acquire
  let _acquired : Unit := Task.get p.result!
  return ()

partial def worker (wait : Std.Semaphore → IO Unit) (items : Std.Semaphore)
    (count : IO.Ref Nat) (id : Nat) : IO Unit := do
  wait items
  count.modify (·+1)
  worker wait items count id

def main (args : List String) : IO UInt32 := do
  let wait ← match args.headD "taskget" with
    | "taskget" => pure acquireTaskGet
    | "iowait" => pure acquireIoWait
    | "resultbang" => pure acquireResultBang
    | _ => pure acquireTaskGet
  let prio := match args.getD 1 "ded" with
    | "ded" => Task.Priority.dedicated
    | _ => Task.Priority.default
  let items ← Std.Semaphore.new 0
  let count ← IO.mkRef 0
  for i in [0:4] do
    let _ ← IO.asTask (prio := prio) (worker wait items count i)
  IO.sleep 3000
  let n ← count.get
  IO.eprintln s!"{args.headD ""}/{args.getD 1 ""}: phantom acquires in 3s: {n}"
  return 0
```

Note: whether `Task.get`-on-promise-task returning early is a Lean
4.33 runtime defect or an API-contract subtlety is unresolved — it
belongs in the drafted upstream issue
(`Drafts/lean4-windows-task-teardown-crash.md`) as a second data point
if confirmed. Either way, `IO.wait` is the documented-correct blocking
wait and is what the fix uses.
