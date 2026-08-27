# t33 Worker-Pool — Implementation Status & Validation Blockers

> Status: **r-windev FULLY GREEN — stress & redeploy pending**
> (updated 2026-08-27; defects §3/§4 fixed in `7d5f47d`; defect §4a —
> the crash that blocked the re-validation — root-caused and fixed
> 2026-08-27 in the `Ffi/socket_shim.c` / `Ffi/Socket.lean` /
> `Shell/Cli.lean` change carrying this doc update)
> Companion to: `worker-pool-design.md` (the t33 design / acceptance bar)
> Head under test: `1f47435` ("t33: worker-pool accept loops on both
> platforms …") when the defects below were found; fix head `7d5f47d`
> ("t33 fixes: blocking semaphore waits (IO.wait) + TLS handshake
> timeout + async_spec probe-leak fix"), Linux x86_64 + windows-dev
> (Lean 4.33, MinGW-w64).
> All local experiments were apalache-free (compile + TLS-handshake level
> only); apalache runs happen on r-windev only.

## 1. Implementation status vs. the design

| Design item | Status |
| ----------- | ------ |
| `ConnQueue` (Mutex + two semaphores, bounded 128) | ✅ `Shell/Transport/Tcp.lean:184` |
| Never-completing dedicated workers, `loopAcceptPool` | ✅ `Tcp.lean:255–273` (fix head); reused by TLS |
| API unchanged (`serveTcpConcurrentOn`/`serveTlsConcurrentOn`), Windows sync branch deleted | ✅ pool on both platforms from `Cli.lean` |
| `--jobs N` sizes the pool on `--server` | ✅ `serveTlsConcurrentOn … (workers := max 1 opts.jobs)` |
| `--serve` gains `--jobs` | ⚠️ **deviation** — `parseServeCli` still parses only `port [--bind]`; pool size is the hardcoded default 4 |
| `async_spec` Windows self-skip removed | ✅ (`APALACHE_MC` gate retained) |
| windows-dev tree synced + built | ✅ `D:\ModelMirrors\lean4-pool` byte-identical to HEAD + the §4a fix (sha256-verified both directions 2026-08-27; remote `lake build` 479 jobs green) |

## 2. Acceptance criteria verdict

1. **Linux `lake test` 10/10** — ✅ **GREEN at fix head `7d5f47d`**
   (all 10 gates; counter/async self-skip without `APALACHE_MC`;
   apalache-gated tiers still deferred to r-windev per machine policy).
   The pool TLS server also idles silent, rejects 3 plain probes 1:1,
   and completes a real mTLS handshake (per the `7d5f47d` commit log).
   **Windows `lake test` 10/10 — ✅ GREEN** (2026-08-27, r-windev,
   `APALACHE_MC=D:\ModelMirrors\bin\apalache-mc.exe`, log
   `D:\ModelMirrors\tmp\lake-test-full.log`): all 10 gates incl.
   counter_spec and async_spec against real apalache — "ALL LAKE TESTS
   GREEN". The earlier `explorer_spec` deadlock observed during this
   validation was the §4a bug itself (`Http.lean closeConn` was a
   tail-position `closeFd`) and is fixed with it.
2. **Windows `async_spec` un-skipped and green** — ✅ **GREEN**
   (2026-08-27, r-windev, `APALACHE_MC=D:\ModelMirrors\bin\apalache-mc.exe`;
   TCP + mTLS + capacity scenarios all pass, zero spam). Two
   intermediate blockers were found and fixed first — the §4a
   `closeFd` ABI crash and the unspawnable bare `apalache-mc` (only
   `.bat`/`.sh` exist in `/d/Programs/apalache/bin`; the
   `bin\apalache-mc.exe` wrapper is the spawnable path). Pre-fix run
   Aug 26 18:28 (`D:\ModelMirrors\tmp\async-pool2.log`) FAILED with
   **1,395,410 `tls: handshake rejected` lines in 28 s** — the §3/§4
   defects, superseded.
3. **300-cycle stress** — ⏳ **AWAITING RE-RUN**. Pre-fix attempts
   (`pool-mtls.log` 1.78M lines/4.3s, `churn.log` 1.43M lines/3.4s)
   were pure spam storms, not clean stress runs (~**414k rejected
   handshakes/s with 4 workers**).
4. **Service redeploy** — not done; the live service still runs the
   Aug 25 binary (`SERVICE_RUNNING`, PID 47176); no
   `ModelMirrors.exe.old18` backup exists.
5. **Hard rollback condition** — was triggered by the pre-fix
   failure; the release stays held until the fixed head re-validates on
   r-windev (§5 steps 4–5).
6. **Docs** — `worker-pool-design.md` and the `architecture-overview.md`
   "Server concurrency (t33 worker pool)" section now exist;
   `async-enablement-design.md` §6 re-enable note, CHANGELOG, README and
   cutover updates are all still pending.

## 3. Defect A — the semaphore wait never blocks (critical) — ✅ FIXED in `7d5f47d`

> **Resolution (same day):** both sites now use `IO.wait`
> (`ConnQueue.acquireWait` at `Shell/Transport/Tcp.lean:196–204`,
> `Shell.Jobs.Store.acquireSlot` at `Shell/Jobs/Store.lean:196`), and
> `ConnQueue.pop` re-waits on a permit-without-entry desync instead of
> fabricating `(0, "")` (`Tcp.lean:224–230`). The narrative below is
> kept as the record of the defect and the probe that pinned it down.

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

## 4. Defect B — silent-connection starvation + test probe leak — ✅ FIXED in `7d5f47d` (TCP-mode caveat open)

> **Resolution (same day):** accepted fds get a 10 s `SO_RCVTIMEO` for
> the handshake, cleared on success so session reads stay blocking
> (`Shell/Transport/Tls.lean:243–253`; the shim treats the read
> timeout as handshake failure), and `async_spec`'s up-polls no longer
> leak probe connections (`probeTcp` closes its fd; `waitServer`
> polls liveness only). The remaining open item is the plain-TCP
> silent-client limitation (last bullet of "Fixes" below — still an
> undocumented accepted divergence).

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

## 4a. Defect C — `closeFd` void/`BaseIO Unit` ABI mismatch (critical) — ✅ FIXED 2026-08-27 (uncommitted)

Found during the r-windev re-validation: after `7d5f47d`, the pool
mTLS server **segfaulted (exit 139 / 0xC0000005) deterministically** on
the first rejected plain-TCP probe. Two independent analyses (binary
disassembly of the remote `mirror.exe`; audit of the compiler-generated
`.lake/build/ir/*.c`) converged:

- `dsh_close_fd` was `LEAN_EXPORT void` (`Ffi/socket_shim.c:261`)
  while the Lean decl was `closeFd : @& UInt64 → BaseIO Unit`
  (`Ffi/Socket.lean:73`). Lean 4.33 codegen consumes `BaseIO Unit`
  externs as `lean_object*` and builds the io-ok envelope with the raw
  RAX as field 0 (`Tls.c:2217–2223`):
  `v609 = dsh_close_fd(cfd); env = lean_alloc_ctor(0,1,0);
  lean_ctor_set(env,0,v609)`. `closesocket` success → RAX=0 →
  **io-ok payload NULL** → `connWorker`'s bind dec-refs it →
  `mov (%rcx),%edx` with rcx=0 → SIGSEGV (cdb-confirmed).
- **Why `7d5f47d`'s reject path was the first to hit it:** the
  `serveTlsConcurrentOn` handler lambda ends with `Ffi.closeFd cfd` in
  TAIL position, and the phantom spins never crashed because
  `closesocket((SOCKET)0)` fails with `SOCKET_ERROR=-1` — an **odd**
  value, i.e. a tagged scalar, which the dec-ref skips. Real sockets
  close with 0 = NULL. Latent on Linux too (same generated tail);
  masked there by caller patterns.
- Not a cross-thread race; the `dsh_set_rcvtimeo_ms` "missing world
  token" suspicion was disproven (v4.33 externs receive **no** world
  token — trailing `unused` params elsewhere are vestigial).

**Fix (landed variant — C-only for `closeFd`):** `dsh_close_fd` keeps
its `BaseIO Unit` decl and now returns `lean_object*` /
`lean_box(0)` — the tagged scalar the io-ok envelope needs (dec-safe).
An intermediate `BaseIO UInt64` + 21-call-site variant also worked but
was reverted as needless churn (this mirrors the `tlsClose` ABI lesson
already documented in `Ffi/Tls.lean:64–66`). Same-class hardening for
`dsh_install_exit_signals` / `dsh_exit` took the `BaseIO UInt64`
route instead (`Ffi/Socket.lean` decls + `Shell/Cli.lean` call sites
bind with `let _ ←`). Verified on r-windev: 20/20 + 6/6 + 4/4 reject
probes survive (rejects logged 1:1, zero spam), 4/4 full mTLS session
cycles, 20/20 TCP churn, `async_spec` ALL GREEN ×3, full
`lake test` GREEN (10/10, real apalache).

## 5. Recommended sequence — status at `7d5f47d`

1. ✅ **DONE** — the two `IO.wait` fixes (pool + job store) and the
   `pop` re-wait hardening are in `7d5f47d`.
2. ✅ **DONE** — `async_spec` probe leak fixed; 10 s TLS handshake
   timeout added.
3. ✅ **DONE** — Linux: `lake build` + all 10 non-apalache gates green;
   live probe/mTLS smoke passed (see `7d5f47d` commit log).
4. ⚠️ **PARTIAL** — r-windev rebuild ✅, `async_spec` with
   `APALACHE_MC=D:\ModelMirrors\bin\apalache-mc.exe` ✅ GREEN
   (2026-08-27, after the §4a fix; 3 consecutive green runs; zero spam —
   logs grow only with real connections, rejects 1:1), full
   `lake test` ✅ GREEN. 300-cycle stress (submit/await/cancel mix)
   still owed. One transient seen once: a `tcp send failed` in
   async_spec's TCP scenario plus a leaked server child holding the
   capture pipe (3 subsequent runs of the same binary clean — likely a
   test-side send race on a closing socket; watch for recurrence).
5. ⏳ **PENDING** — only then: redeploy (backup `.old18`), live mTLS
   validate, 100-cycle hammer, and the §6/CHANGELOG/README/cutover doc
   updates. The `--serve --jobs` deviation (§1) also remains open.

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
