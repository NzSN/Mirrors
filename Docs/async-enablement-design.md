# Async Operations Enablement — Design

> Explanatory types and judgments use the [shared semantic notation](https://github.com/NzSN/Mirrors/blob/main/Docs/semantic-notation.md).

> Status: **implemented** (t31 server wiring, superseded by the t33 connection
> pool on both Linux and Windows). Current source checked 2026-09-08; the
> Windows incident and rollout sections retain their historical evidence.
> Scope: expose the already-built, already-proven async job machinery —
> validate-only (`register_validate_async`) and trace-gen-only
> (`register_trace_gen_async`) — in the production server modes.
> Upstream reference: ModelMirros `docs/async-operations-design.md`
> (its job model is formalized by our §6.4 proofs).

## 1. Background

The wire protocol has five async messages: `register_validate_async`,
`register_trace_gen_async`, `query_job`, `await_job`,
`cancel_job`. The pure job laws are machine-checked; the shell supplies the
effectful implementation and runtime tests:

- **`Core.Jobs`** — the job state machine with §6.4 machine-checked:
  terminal phases absorbing; `JobUnknown` exactly for
  never-submitted/evicted ids (by construction, `StoredPhase`);
  **outcome congruence** — a completed async validate's `job_result`
  payload equals the synchronous `register_validate` reply;
  bound enforcement [1, 100] on both paths.
- **`Shell.Jobs`** — Mutex + Semaphore store, one dedicated
  `Task` per job, cooperative `CancelToken` cancellation that kills
  the apalache child; 10/10 Haskell `AsyncJobsSpec` parity scenarios
  green; `newJobStoreWith capacity runner` already parameterized.
- **`Shell.Mirror.runAsync`** — the async session loop: submit →
  `job_accepted`, `query_job`/`await_job` → `job_status` or
  `job_result`, `cancel_job` → `job_status` with the resulting phase
  (`cancelled` for a live job that was cancelled). A sync registration still
  runs inline. EOF/decode-failure cancels and evicts only that connection's
  jobs; the process-shared store and other connections' jobs remain available.
- **`Shell.Apalache.Runner`** — the real runner (per-job session dir,
  owned-spec release, cancel-kill) already plugs into the store.

**Original gap, now closed:** t31 connected `runAsync` to both server modes.
The current CLI creates one store per server, and t33 dispatches connections
through long-lived workers on both platforms. Stdio remains synchronous.
This document concerns model-checking jobs, not the separate promise-returning
application ports in `mirrorecma-async-v1`.

## 2. Implemented topology

Let `ρ` name a server process, `J` its one shared store, and `σ` a
connection session. The target topology has these interface judgments:

```text
Γ ⊢ J : JobStore(ρ, N)    Γ ⊢ c : Connection(ρ, σ)
────────────────────────────────────────────────────
Γ ⊢ serveAsync(c, J) ÷ 1

Γ ⊢ J : JobStore(ρ, N)    Γ ⊢ id : JobName(ρ)
────────────────────────────────────────────────────
Γ ⊢ queryStatus(J, id) ÷ JobStatus
```

Every session receives the same `J`, while a stored job records its owning
session separately. `JobName(ρ)` identifies the lookup namespace, not evidence
that an ID is currently stored: an absent or evicted ID still yields
`unknown`. Queries are store operations under the connection's existing
protocol discipline; these types do not authorize an out-of-phase first
message. Per-job commands own their Apalache children and the store's bounded
execution slots.

- **One store per server process.** Job ids are unique per store; any
  connection may `query_job`/`await_job`/`cancel_job` any id —
  matches the Haskell store's process-wide visibility.
- **One async session per connection**, dispatched by the bounded connection
  pool; sessions share the store.
- **`--jobs N` sizes both pools**: `max 1 N` connection workers, live-job
  capacity, and job-worker slots; default 4. Pending plus running jobs count
  against capacity. A submission beyond it is rejected synchronously with
  `register_error` / `job queue full`; it is not admitted to an extra job
  queue. The connection queue's separate bound is 128.

## 3. Semantics preserved by construction

| Property | Source |
| -------- | ------ |
| Async validate result ≡ sync validate reply | §6.4 theorem `outcome_congruence` (proof, not test) |
| Terminal phases absorbing; cancel-vs-finish race safe | §6.4 + cooperative-cancel doc |
| Validation bounds outside [1,100] rejected on submit (sync and async) | §6.4 theorem |
| Unknown/evicted id → `JobUnknown`, never spurious | `StoredPhase` typing |
| Session teardown cancels its jobs, then ids evict to `JobUnknown` | `runAsync`'s `endSession`: `cancelJob` followed by `evictJob` for each owned id |
| apalache child dies on cancel | `CancelToken` + `runApalacheCancellable` (t13) |

**No changes to `Core.Jobs`, the proofs, or the codec.** This is
wiring + configuration only — the theorems keep compiling unmodified.

## 4. Deliberate non-goals / parity decisions

- **stdio stays sync-only.** The Haskell stdio mode rejects async
  messages; so does ours. (The error-tag difference —
  `register_error` vs `protocol_error` — is the already-documented
  divergence family.)
- **No per-connection job isolation** — process-wide visibility, as
  upstream.
- **No spec to the TLA+ model**: async flows are already explicit
  *extensions* in `Core.Protocol`'s `TlaStep` (ext* constructors);
  unchanged.

## 5. Test plan (new live gate tier, APALACHE_MC-gated)

Over a live TCP session against the locally built binary, real apalache:

1. `register_validate_async` DeterministicCounter bound 3 →
   `job_accepted` → `await_job` → `job_result` with
   `SpecValid` — and assert the payload **equals** the sync
   `register_validate` reply for the same config (empirical
   congruence).
2. `register_trace_gen_async` Counter (`constInit CInit`,
   `inv TraceComplete`, bound 5) → `job_result` with non-empty
   generated traces; destPath copy semantics checked.
3. Cancel: submit long trace-gen (numTraces 10), `cancel_job` →
   `job_status` with phase `cancelled`; check that the Apalache child is gone.
4. `query_job` with a bogus id → `job_status` with phase `unknown`.
5. Two concurrent jobs on one connection + a second connection
   querying the first's job id (cross-connection visibility).
6. Capacity: `--jobs 1`, keep one job live; a second submission is rejected
   immediately with `register_error` containing `job queue full`.
7. mTLS variant of (1) via the existing throwaway-PKI pattern.
8. Negative: bound 0 and bound 101 rejected on the async path.

Run the complete `lake test` inventory listed in the [documentation index](README.md).
`tools/AsyncSpec.lean` has no unconditional Windows skip; the live tool and
platform prerequisites still apply. The Windows results below are dated runs.

## 6. Known issue: Windows (t31 follow-up, post-landing)

> **SUPERSEDED 2026-08-31 by t33** (`Docs/worker-pool-design.md` /
> `Docs/worker-pool-impl-status.md`): the worker-pool accept loop's
> never-completing workers eliminate the teardown race described below —
> Windows no longer branches to the t30 sync sequential sessions,
> async_spec was unskipped and validated there, and the ledger records the
> 2026-08-31 pooled service redeploy and flat handle trend. This is historical
> deployment evidence, not a current service-health check.
> The narrative below is kept as the record of the original defect.

At the original t31 incident, async server sessions were **Linux-only**. On windows-dev the
concurrent accept loop (session tasks over the shared store)
reproducibly segfaults the process whenever a session completes
quickly (e.g. rapid connect/disconnect, 6/6 runs); the crash is
inside the Lean 4.33 runtime task machinery (lthread worker applying
a task closure; crash address resolves into libleanshared static
code, not our shims or module code). Isolation experiments:

- trivial tasks (300 spawn/complete cycles) on Windows: clean;
- sync sessions on session tasks: clean (300-connection Linux stress
  also clean; Linux async sessions clean and fully gated green);
- any session task that so much as *binds* the JobStore value (its
  Std.Mutex/Std.Semaphore external objects) — even created inside
  the task, even unused — crashes on quick teardown;
- holding task references, per-connection recv buffers, task
  priorities, and top-level task bodies all make no difference;
  a Windows cdb capture (dump + linker map) pinned the fault to the
  Lean runtime, not application code.

Windows builds therefore branch to the t30 sync sequential sessions
(serveTcpOn/serveTlsOn + mirrorSession) in both server modes; the
async_spec gate self-skips on Windows; the r-windev service runs the
sync build. Revisit when the Lean Windows runtime fixes task/external
object teardown (then restore serveTcpConcurrentOn/serveTlsConcurrentOn
in Shell/Cli.lean and drop the AsyncSpec skip).

Also fixed while chasing this (real bug independent of the crash):
the TCP transport's 64 KiB receive scratch was a single shared
module-level buffer — a latent cross-connection data race once
sessions run concurrently. It is now allocated per connection.

## 7. Decisions (signed off)

- **D1 — `--jobs` semantics**: ✅ **capacity = N** — the flag becomes
  the store's concurrency bound; default stays 4 (matches the parser
  and the deployed service's `--jobs 4`).
- **D2 — Windows redeploy**: ✅ **redeploy immediately** after landing,
  same `.oldN` backup/rollback pattern, with live async validation
  against the service.
- **D3 — stdio**: ✅ **sync-only**, Haskell parity; async is a
  server-mode feature.

## 8. Original rollout plan (completed; see t33 ledger)

1. Wire `runAsync` into the `--serve`/`--server` accept loops
   (store created once in `serveOne`/TCP equivalent).
2. New gate tier per §5; full `lake test` green on Linux.
3. README + CHANGELOG; `Docs/cutover.md` no longer lists async as
   unwired.
4. (Per D2) Windows rebuild + service redeploy + live async validation
   against the service.
