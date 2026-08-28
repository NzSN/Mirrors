# t33 Worker-Pool — Implementation Status & Validation Blockers

> Status: **REDEPLOYED + VALIDATED; Defect D fixed & verified — second redeploy (Defect-D build) + round-2 FFI commit pending**
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
3. **300-cycle stress** — ⚠️ **RUN 2026-08-27/28, new defect signal
   (see §4b)**. 4× full 300-cycle mixes (submit/await/cancel, 4-conn
   pool) on the dev tree: 100/100 trace-gen+cancel cycles clean, zero
   crashes/hangs/spam (server logs stayed at the single listening line;
   the 10 s handshake guard fired correctly on a stalled accept) — but
   all validate awaits returned instant `{"validate":{"invalid":""}}`
   **without apalache ever spawning** after a per-instance onset of
   0–24 healthy jobs. Short runs (≤16 cycles) and the live hammer were
   unaffected. Pre-fix attempts (`pool-mtls.log` 1.78M lines,
   `churn.log` 1.43M lines) were pure spam storms.
4. **Service redeploy** — ✅ **DONE 2026-08-28**: `.old18` backup
   (sha-verified), live service now runs the fixed build
   (`1adbbbcb…`, nssm, PID 25704, `--jobs 4`). Live validation:
   single + 4-way concurrent async validates all `valid` (cross-conn
   visibility OK), 10 plain probes survived, log 1:1 with activity,
   `mirror.exe validate --host 192.168.150.219` → VALID (note: the
   production cert SAN is `IP:192.168.150.219` only — not localhost).
   100-cycle live hammer: 100/100 valid, avg 4.16 s/job, service WSS
   54.2 → 73.4 MB (+35% over 101 validates — monitor).
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

## 4a. Defect C — `closeFd` void/`BaseIO Unit` ABI mismatch (critical) — ✅ FIXED in `3b85848` (2026-08-27)

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

## 4b. Defect D — instant `invalid ""` without apalache under sustained load — ✅ FIXED (verified 2026-08-28)

Found by the 300-cycle stress (2026-08-28, artifacts
`D:\ModelMirrors\tmp\stress300.*`): on dev-tree instances driven
with a 4-connection pool through 300 submit/await/cancel cycles,
validate jobs begin returning `{"validate":{"invalid":""}}`
**instantly with no apalache process ever spawned**. Onset varies per
server instance (job #0–#24); 4/4 long runs affected, short runs
(≤16 cycles) and the 100-cycle live hammer never hit it.

**Root cause (proven 2026-08-28, defect-d-hunt team):** Lean 4.33
`IO.Process.spawn` on Windows **leaks one inheritable handle per
child when `stdin := .null`** (runtime: the NUL-device handle is
created inheritable and never closed in the parent; measured linear
growth, e.g. 161 → 2161 handles over 2000 spawns). Every
`CreateProcess` duplicates the accumulated leaked set into the new
child's handle table; once it bloats past the loader's tolerance the
child dies **before `main()`** with exit `0xC0000142` (3221225794)
and empty output — which `validateSpecVia` mapped to
`.ok (.invalid "")` (exit ∉ {0, 255}), so the mirror *lied* that the
spec was invalid. Explains the varying onset (table-size threshold),
the instant empty-output failures, and why manual python spawns never
reproduced it (clean parent handle tables). Both async and SYNC paths
leaked: `IO.Process.output` forces `stdin := .null` regardless of
the config field.

**Fix (this change):**
1. `Shell/Apalache/Cli.lean`: new `spawnApalacheEof` helper —
   `stdin := .piped`, then `child.takeStdin` and drop the write end
   (child still sees stdin EOF; verified **0-leak**). Both
   `runApalache` (rewritten off `IO.Process.output`) and
   `runApalacheCancellable` route through it; drain/wait/cancel-kill
   semantics unchanged.
2. Mapping hardening in `validateSpecVia` + `generateTraceFilesIn`:
   a child exiting nonzero with **empty** stdout+stderr (or an exit
   code outside apalache's documented 120/12 spec-verdict set) now
   reports `infraError "apalache produced no output (exit N)"`
   instead of a bogus `invalid ""`.
Local verification: build green, branch-logic #eval 6/6, gates green.
The Lean-runtime handle leak itself is an upstream-candidate issue.

**Remote verification (2026-08-28, lean4-ffi):** 300/300 mixed cycles
(200 real-apalache validates, 100 cancels, 0 failures/transients, wall
854 s) with a **flat handle trend (184 → 185**; pre-fix reference:
184 → 782); async_spec ALL GREEN ×2; cancel-kill spot-check passed
(cancelled trace-gen terminates its java child). A secondary retention
was found and fixed during verification: the cancel-token kill-closure
pinned each Child (~3 handles/job) until session close — now dropped
after child exit. Independent re-validation (empiricist): clean-box
fresh server 3/3 VALID, handles stable.
**Runbook note:** a box that has run leaky builds carries a
stray-process handle/desktop-heap reservoir — children of ANY new
server then die at the loader with 0xC0000142 (also the classic
Session-0 desktop-heap exhaustion symptom). Sweep stray
mirror/java/python processes (by explicit PID — never
`taskkill /IM`) before judging any run.
**Go/no-go for any green-run window:** `tasklist` must show ZERO
mirror/java/python strays except production (`ModelMirrors.exe`,
PID 25704) and any designated specimen; sweep otherwise.
**Deployment note:** the live service binary (1adbbbcb) predates this
fix and still leaks ~1 handle per apalache spawn — a second redeploy
with the Defect-D-fixed binary is owed.

**Box-level caveat (2026-08-28 final pass):** the windows-dev box
carries a *cumulative* session-0 spawn-resource debt that recovers by
idle time: after a burst of ~30 cumulative spawns across test servers,
ALL mirror instances' children flip to 0xC0000142 loader death in
unison (fresh servers start green, then flip). Under nonzero debt the
clang-built apalache wrapper is more fragile than the gcc one (dies
first); at zero debt both are clean (20/20 VALID each). The pre-fix
production binary degrades after ~3 own-spawns under debt (old
`invalid ""` lie), while the fixed build at worst reports the honest
infraError. One unresolved observation: during one heavily-indebted
run the FIXED dev server itself exited mid-run — not reproduced in the
clean-window 300-cycle stress; watch under future load. Production
(8999) stayed alive and serving throughout all of this.

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
5. ⚠️ **MOSTLY DONE** — redeploy (`.old18` backup) ✅, live mTLS
   validate ✅, 100-cycle hammer ✅ (all 2026-08-28, see §2 items 3–4).
   Remaining: resolve §4b (Defect D), then the §6/CHANGELOG/README/
   cutover doc updates. The `--serve --jobs` deviation (§1) also
   remains open.

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
