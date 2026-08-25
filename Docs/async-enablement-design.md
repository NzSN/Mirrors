# Async Operations Enablement — Design

> Status: **approved** (D1–D3 signed off; implementation released as t31)
> Scope: expose the already-built, already-proven async job machinery —
> validate-only (`register_validate_async`) and trace-gen-only
> (`register_trace_gen_async`) — in the production server modes.
> Upstream reference: ModelMirros `docs/async-operations-design.md`
> (its job model is formalized by our §6.4 proofs).

## 1. Background

The wire protocol has five async messages: `register_validate_async`,
`register_trace_gen_async`, `job_query`, `job_await`,
`job_cancel`. In the Lean port every layer beneath the transport is
done and verified:

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
  `job_accepted`, `job_query`/`job_await` → `job_status` /
  `job_result`, `job_cancel` → `job_status(job_cancelled)`;
  a sync register mid-session still runs inline; EOF/decode-failure
  closes the store (cancel live jobs, evict ids).
- **`Shell.Apalache.Runner`** — the real runner (per-job session dir,
  owned-spec release, cancel-kill) already plugs into the store.

**The gap:** no production mode calls `runAsync`. stdio runs one sync
`run`; the `--serve`/`--server` accept loops run sync sessions;
`--jobs` is parsed but reserved. (The Haskell mirror has the same
limitation — its `Main.hs` wires only `run`.)

## 2. Target topology

```
mirror --server 8999 --tls ... --jobs N
        │
        ├─ JobStore (ONE per process; capacity = N)
        │     ├─ Task job-1 (validate)   ── apalache child
        │     └─ Task job-2 (trace-gen)  ── apalache child
        │
        └─ accept loop
              ├─ connection 1 → runAsync transport orc store
              └─ connection 2 → runAsync transport orc store
```

- **One store per server process.** Job ids are unique per store; any
  connection may `job_query`/`job_await`/`job_cancel` any id —
  matches the Haskell store's process-wide visibility.
- **One async session per connection**, sequential accept loop
  (unchanged); sessions share the store.
- **`--jobs N` gains real semantics**: store capacity = N (semaphore
  bounds *concurrently running* job bodies; submissions beyond capacity
  are queued by the store, queue-full → `register_error`, per the
  existing parity-tested semantics). Default 4 (the parser's current
  `getD 4`), `--jobs 1` serializes job execution.

## 3. Semantics preserved by construction

| Property | Source |
| -------- | ------ |
| Async validate result ≡ sync validate reply | §6.4 theorem `outcome_congruence` (proof, not test) |
| Terminal phases absorbing; cancel-vs-finish race safe | §6.4 + cooperative-cancel doc |
| Bounds outside [1,100] rejected on submit (sync and async) | §6.4 theorem |
| Unknown/evicted id → `JobUnknown`, never spurious | `StoredPhase` typing |
| Session teardown cancels its jobs, then ids evict to `JobUnknown` | `closeJobStore` (Haskell `endSession` parity) |
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
   `job_accepted` → `job_await` → `job_result` with
   `SpecValid` — and assert the payload **equals** the sync
   `register_validate` reply for the same config (empirical
   congruence).
2. `register_trace_gen_async` Counter (`constInit CInit`,
   `inv TraceComplete`, bound 5) → `job_result` with non-empty
   generated traces; destPath copy semantics checked.
3. Cancel: submit long trace-gen (numTraces 10), `job_cancel` →
   `job_cancelled`; apalache child verified gone.
4. `job_query` bogus id → `job_unknown`.
5. Two concurrent jobs on one connection + a second connection
   querying the first's job id (cross-connection visibility).
6. Capacity: `--jobs 1`, submit 2 jobs → second waits; third beyond
   queue → `register_error`.
7. mTLS variant of (1) via the existing throwaway-PKI pattern.
8. Negative: bound 0 and bound 101 rejected on the async path.

All existing 9 gates must stay green; the Windows build must keep
compiling (the t30 platform branches are untouched by this work —
`runAsync` uses only Task/Mutex/transport).

## 6. Decisions (signed off)

- **D1 — `--jobs` semantics**: ✅ **capacity = N** — the flag becomes
  the store's concurrency bound; default stays 4 (matches the parser
  and the deployed service's `--jobs 4`).
- **D2 — Windows redeploy**: ✅ **redeploy immediately** after landing,
  same `.oldN` backup/rollback pattern, with live async validation
  against the service.
- **D3 — stdio**: ✅ **sync-only**, Haskell parity; async is a
  server-mode feature.

## 7. Rollout

1. Wire `runAsync` into the `--serve`/`--server` accept loops
   (store created once in `serveOne`/TCP equivalent).
2. New gate tier per §5; full `lake test` green on Linux.
3. README + CHANGELOG; `Docs/cutover.md` no longer lists async as
   unwired.
4. (Per D2) Windows rebuild + service redeploy + live async validation
   against the service.
