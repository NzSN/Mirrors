# Mirrors — Supported Interface Reference

For an end-to-end deployment and client walkthrough, see the [remote server guide](remote-server-guide.md).

> The complete client-facing interface of the Lean 4 mirror, with exact
> wire shapes (pinned by `test/fixtures/*.jsonl`, the golden corpus every
> message is byte-verified against). Covers both the **synchronous** flows
> and the **asynchronous** job interfaces.
> Related: `client-implementation-guide.md` (the conformance
> specification layered on these wire shapes),
> `architecture-overview.md`, `async-enablement-design.md`,
> `cutover.md` (divergences from the Haskell implementation).
> Product releases: [versioning and installation](versioning.md).

## 1. Transports and CLI modes

| Mode | Command | Transport | Session kind |
| ---- | ------- | --------- | ------------ |
| version | `mirror --version` | stdout | prints `Mirrors 0.0.2` followed by a newline and exits successfully |
| stdio (default) | `mirror` | stdin/stdout, newline-delimited | **sync only** — one register flow per process |
| TCP daemon | `mirror --serve <port> [--bind <addr>] [--jobs N]` | plain TCP, JSONL | **async** — one session per connection, concurrent |
| mTLS daemon | `mirror --server <port> --tls --cert C --key K --ca A [--registry URL] [--jobs N] [--bind B] [--model-interface-allow-client FP[,FP...]] [--model-interface-descriptor-read]` | TLS 1.3, mutual auth, JSONL | **async** — one session per connection, concurrent |
| validate client | `mirror validate --host H --port P [--tls …] [--pin FP] --spec S.tla` | outgoing TCP/mTLS | sync validation by default; `--async` submits and awaits a server job |

`--version` is a standalone mode: it needs no model, Apalache process, or
server configuration. It writes nothing to stderr and exits with status `0`.
Additional arguments (including a repeated `--version`) are rejected with
status `2`. Installing the executable as `ModelMirrors` preserves the same
behavior: `ModelMirrors --version` prints the Mirrors product identity.
The version is compiled into the executable; it does not identify a Git commit
or indicate whether the build used a modified working tree.

Protocol framing: **one JSON object per line** (valid UTF-8,
`\n`-terminated), with at most **65,535 payload bytes** before the newline.
The bound is enforced before JSON parsing and after final response encoding.
mTLS policy: TLS 1.3 only, client certificate required, CA chain + SAN
hostname/IP verification, optional SHA-256 fingerprint pin
(`--pin`, case-insensitive), client key must be `0600` (POSIX).

`--jobs N` sizes connection workers and the async job store (live-job capacity
and worker slots) in both server modes. It defaults to 4; the CLI clamps zero
to 1. Pending and running jobs both consume capacity; an additional submission
is rejected synchronously when that capacity is full.

### Validate CLI source delivery

`mirror validate --host H --port P --spec ./Main.tla [--dep FILE]...`
reads local files and sends an inline `SpecConfig`, with the root first. It
recursively discovers sibling `EXTENDS` and `INSTANCE` modules through the shared
TLA+ frontend. `--dep` selects additional files by declared module name, taking
precedence over sibling lookup; their own sibling dependencies are also captured.
Duplicate explicit names fail. Standard catalog modules without a selected local
file remain server-provided. This CLI does not search `TLA_LIBRARY` or directories
recursively. Server role and TCP/mTLS selection do not change source resolution.

Capture uses the existing frontend limits (128 modules, 4 MiB per file, 16 MiB
total, depth 64), regular-file/UTF-8 checks and LF normalization. Cycles terminate
and shared modules are sent once. Resolution failure or an encoded registration
larger than 65,535 bytes exits 2 before connection. There is no chunking or upload
endpoint. This behavior is specific to the validation CLI; suite project remote
paths retain their separately documented deployment semantics.

The executable regression `python3 tools/check-validate-closure.py` tests the
wire request against a local protocol fixture and runs in `lake test`. The
optional `tools/check-validate-remote.py` tests both a valid three-module model
and an invariant-violating leaf change against a real server:

```sh
python3 tools/check-validate-remote.py \
  --relay-argv '["/path/to/operator-configured-jsonl-relay"]'
```

The operator-supplied relay consumes a JSONL request on stdin and returns the
server reply on stdout; it owns remote access and credentials. The test checks
that all local modules travel inline and asserts CLI exit 0 for valid and 1 for
invalid. Add `--async` to this test with an interactive relay that forwards
multiple request/reply pairs on one connection. It then checks async submission,
job correlation and the same final CLI verdicts. These are explicit live tests,
separate from the ordinary local gate.

Live evidence (2026-09-18): the locally built CLI sent `Main -> Helper -> Leaf`
to the existing Windows `ModelMirrors` service on port 8999 through an SSH relay
and a certificate-verified TLS 1.3 connection. The server returned valid for
`Leaf.Step = 1` (CLI exit 0) and invalid for `Leaf.Step = -1` (CLI exit 1), with
all three sources supplied inline in both cases. The service used its existing
Apalache 0.58.2 installation. This verifies recursive delivery and real remote
validation; it does not claim a direct local-CLI mTLS transport test. Earlier
probe failures were relay/fixture setup failures, not passing acceptance results.
The `validate --async` CLI subsequently passed both verdict cases against the
upgraded Windows service, using an interactive SSH/TLS relay and retaining its
submitting connection through the matching `job_result`.

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
Materialized server-side into a per-session owned temp dir. This form is
portable across stdio, TCP, and mTLS only when the complete, compact
registration remains within the version-1 limit of 65,535 UTF-8 bytes. Clients
must validate the final encoded line before sending it. A larger closure must
use a pre-provisioned server-side `specPath`, direct Apalache generation as an
explicit application workflow, or a future versioned artifact-transfer
protocol; version 1 has no source chunking or upload fallback.

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
entries (sorted). Each disk ITF artifact is bounded at 16 MiB. Negotiated
registrations additionally require strict duplicate-free JSON and compatible
typed metadata across the complete trace bundle, and cap that bundle at 256
files, 64 MiB of source JSON, 256 traces, and 65,536 states.

#### Optional model-interface negotiation

`register` and `register_traces` may carry a strict `modelInterface` field.
Its schema is `mirrors.model-interface-negotiation/v1`; it requests either an
exact digest check (`verify`) or the language-neutral descriptor
(`descriptor`). The inline companion contract is resolver input. Mirrors never
sends executable adapter code.

Shape excerpt (the inline value must be a complete strict `ContractV1`):

```json
{
  "modelInterface": {
    "schema": "mirrors.model-interface-negotiation/v1",
    "request": "verify",
    "policy": "require",
    "acceptDescriptorSchemas": ["mirrors.model-interface-descriptor/v1"],
    "expectedSemanticDigest": "sha256:<64 lowercase hex>",
    "contract": { "inline": { "schema": "mirrors.model-interface/v1" } }
  }
}
```

On a match, the existing `spec_validated` message carries an optional
`modelInterface` reply with status `matched`. Descriptor requests return
`resolved` plus the canonical descriptor, or `not_modified` when
`ifNoneMatch` equals the resolved digest. Required failures keep the existing
`register_error` tag and add a structured status/code; they emit no
`initial_state`.

When this field is absent, registration and reply bytes remain identical to
the legacy protocol. Local stdio permits verification and descriptor reads;
plain TCP has no model-interface scope. mTLS transport authentication alone
also grants no model-interface scope. `--model-interface-allow-client` accepts
a comma-separated list of exact client certificate SHA-256 fingerprints and
grants those principals verify scope; `--model-interface-descriptor-read`
additionally grants the listed principals descriptor-read scope. The latter
flag is rejected without a nonempty allowlist. Cache/accounting identity
includes the verified peer principal as well as its CA realm. Full schemas,
policy precedence, limits, and client invariants are specified in
[`model-interface-runtime-distribution-design.md`](https://github.com/NzSN/Mirrors/blob/main/Docs/model-interface-runtime-distribution-design.md).

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
The path is interpreted by the server, not by the client. For local stdio the
peer shares the server filesystem: if the full compact reply would exceed
65,535 UTF-8 bytes and `destPath` produced durable copies outside the owned
session directory, Mirrors returns the existing `gen_traces_done` shape with
those paths and `"itfTraces": []`. Without such durable copies it returns a
bounded `register_error` beginning with `TRACE_RESULT_TOO_LARGE`.

TCP and mTLS peers are remote even when a pathname happens to look meaningful
on both hosts. They never receive path-only success in place of an oversized
inline result; version 1 fails explicitly with `TRACE_RESULT_TOO_LARGE`.
Replies whose full encoding fits retain their existing bytes and include both
paths and inline traces.

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

The [async protocol/resource model](async-protocol-resource-model.md) specifies
job ownership, cancellation, retention and eventual cleanup. Its resource
guarantees are conditional on the documented progress and cleanup assumptions.

### 4.1 Submit: `register_validate_async` / `register_trace_gen_async`
```json
{"proto_step": "register_validate_async", "apalacheConfig": {…}, "bound": 5, "spec": null}
{"proto_step": "register_trace_gen_async", "apalacheConfig": {…}, "spec": null,
 "destPath": null, "traceConfig": {"numTraces": 1, "view": null}}
```
Immediate reply: `{"proto_step": "job_accepted", "jobId": "job-0",
"kind": "validate" | "gen_traces"}`. Validation bounds outside [1,100] or a full
queue → `register_error` synchronously at submit.

The validation CLI selects this path with `validate --async`. It resolves and
sends the same inline source closure, requires `job_accepted` of kind `validate`,
then sends `await_job` with `timeoutSecs: 30` on the submitting connection until
a matching terminal result arrives. Pending/running statuses cause another
long poll; wrong job IDs, wrong result kinds, cancelled/unknown jobs, disconnects
and protocol failures exit 2. Valid and invalid verdicts retain exits 0 and 1.
The flag does not detach or print a job handle for later use, and it does not
fall back to synchronous validation on an older server. The 30 seconds is a
per-poll server wait, not a total execution deadline. Ending the CLI closes its
owner connection, so the server cancels/evicts that connection's jobs.

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
`register_validate` reply for the same config. Trace-generation job results
are network results and therefore require inline delivery. If their compact
`job_result` would exceed 65,535 UTF-8 bytes, the same job ID instead has the
terminal `{"error":"TRACE_RESULT_TOO_LARGE: …"}` outcome. Repeated
`query_job` or `await_job` operations return that same deterministic terminal
outcome and do not rerun Apalache.

## 5. Error replies

| Message | When |
| ------- | ---- |
| `{"proto_step": "register_error", "error": "…"}` | registration/submit failures: bad spec source, categorized and bounded Apalache failure, `TRACE_RESULT_TOO_LARGE`, queue full, out-of-range bound, async message in stdio mode |
| `{"proto_step": "protocol_error", "error": "…"}` | decode failures and out-of-phase messages |

Documented divergences from the Haskell implementation (details in
`cutover.md`): mismatch tail is spec-faithful (no trailing
`all_steps_done` after `step_mismatch`); error-tag choice on
async job messages in stdio mode; stricter (fail-closed) wildcard SAN scope;
case-insensitive `--pin` (Lean robustness improvement).
