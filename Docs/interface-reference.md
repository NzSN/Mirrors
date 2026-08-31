# Mirrors — Supported Interface Reference

> The complete client-facing interface of the Lean 4 mirror, with exact
> wire shapes (pinned by `test/fixtures/*.jsonl`, the golden corpus every
> message is byte-verified against). Covers both the **synchronous** flows
> and the **asynchronous** job interfaces.
> Related: `client-implementation-guide.md` (the conformance
> specification layered on these wire shapes),
> `architecture-overview.md`, `async-enablement-design.md`,
> `cutover.md` (divergences from the Haskell implementation).

## 1. Transports and CLI modes

| Mode | Command | Transport | Session kind |
| ---- | ------- | --------- | ------------ |
| stdio (default) | `mirror` | stdin/stdout, newline-delimited | **sync only** — one register flow per process |
| TCP daemon | `mirror --serve <port> [--bind <addr>] [--jobs N]` | plain TCP, JSONL | **async** — one session per connection, concurrent |
| mTLS daemon | `mirror --server <port> --tls --cert C --key K --ca A [--registry URL] [--jobs N] [--bind B]` | TLS 1.3, mutual auth, JSONL | **async** — one session per connection, concurrent |
| validate client | `mirror validate --host H --port P [--tls …] [--pin FP] --spec S.tla` | outgoing TCP/mTLS | client of the sync validate flow |

Framing everywhere: **one JSON object per line** (UTF-8, `\n`-terminated).
mTLS policy: TLS 1.3 only, client certificate required, CA chain + SAN
hostname/IP verification, optional SHA-256 fingerprint pin
(`--pin`, case-insensitive), client key must be `0600` (POSIX).

`--jobs N` sizes the server's async job store (live-job capacity and
worker slots; default 4).

## 2. Shared structures

### `ApalacheConfig`
```json
{"specPath": "specs/HourClock.tla", "initPredicate": null, "nextPredicate": null,
 "constInit": "CInit", "invariant": "TraceComplete", "lengthBound": 5, "paramVars": "parameters"}
```
Only `specPath` is mandatory. Defaults (Haskell-exact): `invariant`
and `paramVars` `""`, `lengthBound` `10`, the rest `null`.
Absent optional keys are accepted (`.:?` semantics: absent ≡ null).
`paramVars` names a spec variable moved out of state comparisons into
step parameters. Specs with `CONSTANTS` need `constInit`.

### `SpecConfig` (inline spec)
`{"sources": ["---- MODULE M ----\n…", …]}` — full TLA+ sources;
`EXTENDS`/`INSTANCE` closure is the client's responsibility.
Materialized server-side into a per-session owned temp dir.

### `TraceConfig`
`{"numTraces": 1, "view": null}` — `numTraces` ≥ 1; `view` is an
optional state-view operator name (`view: null` or absent = none;
any `"name"` is passed as `--view=name`).

### ITF values
Arbitrary-precision ints as `{"#bigint": "…"}` (bare integral JSON
numbers also accepted on decode), sets `{"#set": [...]}`, maps
`{"#map": [[k,v],…]}`, tuples `{"#tup": [...]}`, variants
`{"#variant": {"tag": "…", "value": …}}`, records as plain objects,
plus strings/bools/null.

## 3. Synchronous interfaces

The first message on any connection must be a `register*` message
(phase-indexed; anything else is rejected — the session machine makes
illegal orderings unrepresentable).

### 3.1 `register` — validate, generate, then replay (full MBT)
```json
{"proto_step": "register", "apalacheConfig": {…}, "spec": null|{…},
 "traceConfig": {"numTraces": 1, "view": null}}
```
Flow: `spec_validated` → per trace: `initial_state` →
(`next_step` ↔ `report_state` → `step_ok`)* → `all_steps_done`.

Client replies to `initial_state`/`next_step` with:
```json
{"proto_step": "report_state", "state": {"count": {"#bigint": "2"}, "action_taken": "tick"}}
```
`next_step` carries the action and its parameters:
`{"action": "tick", "parameters": {…}, "proto_step": "next_step"}`.
The mirror diffs each report against the expected trace state
(`filterMeta` drops `#*`, `action_taken`, `parameters` keys);
mismatch → `step_mismatch` with structured hints:
```json
{"proto_step": "step_mismatch", "expected": {…}, "actual": {…},
 "hints": [{"kind": "valueMismatch|missing|extra|missingElem|extraElem|typeMismatch|truncated",
            "path": [{"field": "count"}], "actual": …, "expected": …}]}
```
Diff hints are capped at 50 (+ one `truncated` hint), in the same
sorted-key order as the Haskell implementation.

### 3.2 `register_traces` — replay client-supplied ITF traces
```json
{"proto_step": "register_traces", "apalacheConfig": {…},
 "itfTracePaths": ["out/itf/trace1.itf.json", …]}
```
No validation phase (fast path): `spec_validated` immediately, then
the replay loop above. Directory paths expand to their `*.itf.json`
entries (sorted).

### 3.3 `register_trace_gen` — generate traces, then done
```json
{"proto_step": "register_trace_gen", "apalacheConfig": {…}, "spec": null|{…},
 "destPath": "out/itf" | null, "traceConfig": {…}}
```
Replies `gen_traces_done`:
```json
{"proto_step": "gen_traces_done",
 "itfTracePaths": ["…/violation.itf.json"], "itfTraces": [ …inline ITF… ]}
```
`destPath` copies the traces to a client-chosen directory.

### 3.4 `register_validate` — validate only, then done
```json
{"proto_step": "register_validate", "apalacheConfig": {…}, "bound": 5, "spec": null|{…}}
```
`bound` ∈ [1, 100] (enforced synchronously before any state change).
Single terminal reply:
`{"proto_step": "spec_validated", "result": "valid"}` or
`{"result": {"invalid": "Invariant violated"}}`.

### 3.5 `register_explore` / `register_explore_session` — symbolic exploration
```json
{"proto_step": "register_explore_session",
 "spec": {"sources": […]}, "invariants": ["InvA"], "exports": []}
```
`register_explore` additionally takes `maxSteps`. After
`explorer_ready` (`{"initTransitions": 2, "nextTransitions": 3,
"stateInvariants": 1}`), the client drives the explorer:
`explore_assume_transition {transitionId}` → `explore_transition_status`;
`explore_next_step` → `explore_step_done {stepNo}`;
`explore_query_state` → `explore_state {state}`;
`explore_check_invariant {invariantId}` → `explore_invariant_status {status}`;
`explore_assume_state {state}` → `explore_assume_status`;
`explore_rollback {snapshotId}` → `explore_rollback_done`;
`explore_done` → `explore_session_done`.

## 4. Asynchronous interfaces (server modes only)

Available on `--serve` / `--server` connections (not stdio). Jobs run
on a process-wide store shared by all connections; any connection may
operate on any job id. A connection ending cancels and evicts exactly
its own jobs.

### 4.1 Submit: `register_validate_async` / `register_trace_gen_async`
```json
{"proto_step": "register_validate_async", "apalacheConfig": {…}, "bound": 5, "spec": null}
{"proto_step": "register_trace_gen_async", "apalacheConfig": {…}, "spec": null,
 "destPath": null, "traceConfig": {"numTraces": 1, "view": null}}
```
Immediate reply: `{"proto_step": "job_accepted", "jobId": "job-0",
"kind": "validate" | "gen_traces"}`. Bounds outside [1,100] or a full
queue → `register_error` synchronously at submit.

### 4.2 Operate: `query_job` / `await_job` / `cancel_job`
```json
{"proto_step": "query_job", "jobId": "job-0"}
{"proto_step": "await_job", "jobId": "job-0", "timeoutSecs": 30}   // timeoutSecs optional
{"proto_step": "cancel_job", "jobId": "job-0"}
```
Replies — `job_status` (non-terminal / unknown):
`{"proto_step": "job_status", "jobId": "job-0",
"phase": "pending"|"running"|"done"|"failed"|"cancelled"|"unknown"}`
and `job_result` (terminal outcome, idempotent):
```json
{"proto_step": "job_result", "jobId": "job-0", "outcome": {"validate": "valid"}}
{"proto_step": "job_result", "jobId": "job-1",
 "outcome": {"genTraces": {"itfTracePaths": […], "itfTraces": […]}}}
{"proto_step": "job_result", "jobId": "job-2", "outcome": {"error": "worker died"}}
```
Semantics (machine-proven, §6.4): terminal phases are absorbing;
`unknown` is answered exactly for never-submitted or evicted ids;
cancellation is cooperative and kills the apalache child; a completed
validate job's outcome payload **equals** the synchronous
`register_validate` reply for the same config.

## 5. Error replies

| Message | When |
| ------- | ---- |
| `{"proto_step": "register_error", "error": "…"}` | registration/submit failures: bad spec source, apalache infra failure, queue full, out-of-range bound, async message in stdio mode |
| `{"proto_step": "protocol_error", "error": "…"}` | decode failures and out-of-phase messages |

Documented divergences from the Haskell implementation (details in
`cutover.md`): mismatch tail is spec-faithful (no trailing
`all_steps_done` after `step_mismatch`); error-tag choice on
out-of-phase job messages; stricter (fail-closed) wildcard SAN scope;
case-insensitive `--pin` (Lean robustness improvement).
