# Mirrors — Client Implementation Guide & Conformance Specification

> How to implement a client of the Mirrors mirror server, and the
> normative rules a conforming client must obey.
> Companion docs: `interface-reference.md` (exact wire shapes — the
> message catalog is NOT repeated here), `cutover.md` (Haskell
> divergences), `worker-pool-design.md` (server concurrency model),
> `tls-ffi-review.md` (TLS policy details).
> Wire truth is pinned by `test/fixtures/*.jsonl` (the golden corpus,
> frozen from the Haskell reference implementation); this document is the
> behavioral layer on top of it.
>
> Normative keywords **MUST / MUST NOT / SHOULD / MAY** are used as in
> RFC 2119. Numbered rules (**C1**, **C2**, …) are the conformance
> checklist — a client that satisfies every MUST is wire-compatible with
> both the Lean 4 mirror and the Haskell reference (`ModelMirros@3496251`).

## 1. Where a client can attach

| Endpoint | Transport | Session model | Use for |
| -------- | --------- | ------------- | ------- |
| `mirror` (default) | stdin/stdout of a spawned process | **sync only**, one register flow per process | local MBT, tests |
| `mirror --serve <port> [--bind A] [--jobs N]` | plain TCP | async-capable, one session per connection, concurrent | LAN daemons, CI |
| `mirror --server <port> --tls --cert C --key K --ca A [--jobs N]` | mTLS (TLS 1.3 only) | async-capable, one session per connection, concurrent | production |
| registry-discovered peers | mTLS + Consul-style registry | as above, with fingerprint pinning | discovery deployments |

A single physical connection carries exactly one logical session.
Multiple sessions require multiple connections (the server's worker pool
and shared job store exist precisely to make that cheap — see §7).

## 2. Framing

- **C1.** Every message, both directions, is exactly **one JSON object
  per line**, UTF-8, terminated by `\n`. No length prefixes, no
  concatenated JSON, no blank lines (the mirror never emits them; a
  read that returns an empty line is EOF).
- **C2.** Clients **MUST NOT** emit lines larger than the server's
  receive buffer can hold; the golden corpus stays under 64 KiB per
  line. Keep individual messages small; ship large TLA+ sources via the
  `spec.sources` array (§5) rather than inventing side channels.
- **C3.** All protocol messages are discriminated by the string field
  `"proto_step"`. Clients **MUST** dispatch on `proto_step` and
  **MUST** tolerate (ignore) unknown additional fields in mirror
  messages — the wire contract is field-additive.

## 3. Session lifecycle

- **C4.** The first message on a session **MUST** be a `register*`
  message (`register`, `register_traces`, `register_trace_gen`,
  `register_validate`, `register_explore*`, or the async variants).
  Anything else is rejected out-of-phase (`protocol_error`; the
  session machine — `Core/Protocol.lean` — makes illegal orderings
  unrepresentable, and the TLA+ spec proves no unsolicited output).
- **C5.** After a terminal mirror message (`all_steps_done`,
  `gen_traces_done`, `spec_validated` for validate-only,
  `explorer_session_done`, `step_mismatch`), the flow is over. A
  client **MUST NOT** send further flow messages on that session; start
  a new connection instead.
- **C6.** A client **SHOULD** close connections cleanly and **MUST**
  tolerate the server closing first. On connection end the server
  cancels and evicts exactly that session's async jobs (Haskell
  `endSession` semantics) — jobs submitted on other connections are
  unaffected, but a dropped connection loses its own in-flight work.
- **C7.** There are no pings, heartbeats, or idle timeouts at the
  protocol level (the server's 10 s `SO_RCVTIMEO` applies only to the
  TLS handshake window, not to established sessions). A client that
  needs liveness **MAY** poll with `query_job` or simply open a
  probe connection.

## 4. The synchronous replay contract (`register`, `register_traces`)

The full-MBT flows are a **call-and-response loop**; the mirror drives,
the client executes the system under test and reports:

```
client → register / register_traces
mirror → spec_validated                 (register_traces: immediate, no check run)
mirror → initial_state {state}          (per trace)
client → report_state {state}           (MUST answer)
mirror → step_ok | step_mismatch
mirror → next_step {action, parameters}
client → report_state {state}           (after executing the action)
…
mirror → all_steps_done
```

- **C8.** The client **MUST** answer every `initial_state` and
  `next_step` with exactly one `report_state`. Staying silent wedges
  the session (the mirror's read blocks; on the worker-pool server a
  silent connection parks a pool worker — this is a documented
  accepted-divergence DoS surface on plain TCP).
- **C9.** `report_state.state` **MUST** contain the full observable
  state as ITF values. The mirror diffs it against the expected trace
  state with `filterMeta` semantics: keys starting with `#` plus
  `action_taken` and `parameters` are excluded from comparison.
  Everything else is compared deeply — extra keys are reported as
  `extra` hints, missing ones as `missing`.
- **C10.** On `step_mismatch` the session ends **without** a trailing
  `all_steps_done` (spec-faithful; the Haskell server sends one —
  documented divergence). Clients **MUST** treat `step_mismatch` as
  terminal. Hints are capped at 50 plus one `truncated` hint, in
  sorted-key order; see `interface-reference.md` §3.1 for the hint
  schema.
- **C11.** Integers in state **MUST** be encodable as
  `{"#bigint": "<decimal>"}`. The mirror also *accepts* bare integral
  JSON numbers on decode (Haskell parity), but a conforming client
  **SHOULD** always emit `#bigint` — that is what every encoder in
  the ecosystem produces.
- **C12.** Trace length and stride choices are nondeterministic
  (apalache search order). Clients **MUST NOT** hardcode expected step
  counts; drive the loop until a terminal message.

## 5. Specs: path vs. inline

- `apalacheConfig.specPath` is interpreted **server-side** — it names
  a file on the server's filesystem (or, when `spec` is given, the
  module's basename within the materialized temp dir).
- **C13.** To keep a client server-filesystem-independent, ship specs
  inline: `"spec": {"sources": ["---- MODULE M ----\n…", …]}`. The
  client **MUST** include the full `EXTENDS`/`INSTANCE` closure in
  `sources`; the server materializes them into a per-session owned
  temp dir (never the server's cwd — run-dir isolation is gated by
  `counter_spec`).
- **C14.** `ApalacheConfig` optional fields follow Haskell `.:?`
  semantics: absent ≡ explicit `null`. Defaults on decode:
  `invariant` and `paramVars` `""`, `lengthBound` 10, the rest
  `null`. A client **MAY** omit optional keys (JS clients do) or send
  explicit nulls (Haskell clients do); both are conforming.
- **C15.** Specs declaring `CONSTANTS` **MUST** set `constInit`.
  `paramVars` names a spec variable lifted out of state comparison
  into step parameters (see `tools/CounterSpec.lean` for the
  resulting `{"parameters":{"parameters":{"stride":N}}}` shape after
  resplit).
- **C16.** `register_validate`/`register_validate_async` take
  `bound` ∈ [1, 100]; out-of-range bounds are rejected synchronously
  at registration before any state change.

## 6. Asynchronous job interface (server modes only)

Available on `--serve`/`--server` connections. Submitting an async
message on a stdio session is rejected (`register_error` — tag
divergence, §9).

```
client → register_validate_async | register_trace_gen_async
mirror → job_accepted {jobId, kind}      (synchronous; full queue → register_error)
client → query_job {jobId}               → job_status {phase}
client → await_job {jobId[, timeoutSecs]} → job_result {outcome} | job_status
client → cancel_job {jobId}              → job_result | job_status
```

- **C17.** `jobId`s are process-unique and **cross-connection
  visible**: any connection may query/await/cancel any live job.
  Clients **MAY** submit on one connection and await on another, but
  note C6: the submitter's disconnect cancels and evicts its jobs
  regardless of who is awaiting.
- **C18.** `await_job` **MUST** be treated as long-polling: without
  `timeoutSecs` it blocks until the job terminates; with it, a
  timeout returns `job_status` (non-terminal), never an error.
  Terminal results are idempotent — re-awaiting a finished job returns
  the same `job_result` until eviction.
- **C19.** Cancellation is cooperative but lethal to the apalache
  child: `cancel_job` on a running job terminates the spawned
  `apalache-mc` process. A client **SHOULD** cancel jobs it no longer
  needs rather than dropping the connection (which cancels anyway, per
  C6).
- **C20.** A completed validate job's `outcome.validate` payload is
  **identical** to what the synchronous `register_validate` flow
  would have answered for the same config (machine-proven congruence,
  `async-enablement-design.md` §6.4) — clients **MAY** share result
  handling between sync and async paths.
- **C21.** `job_status.phase` `"unknown"` is answered exactly for
  never-submitted or evicted ids. Clients **MUST NOT** retry-loop on
  `unknown` expecting the job to appear.

## 7. Concurrency expectations

- The server is a bounded worker pool (`--jobs N`, default 4, both
  server modes): N connection workers plus a job store of capacity N
  with N apalache worker slots.
- **C22.** A client **SHOULD** size its own connection pool ≤ the
  server's `--jobs` when driving sustained load (the 300-cycle stress
  harness uses exactly 4 against `--jobs 4`). Oversubscribing
  connections is legal — excess connections queue at the accept
  backlog — but oversubmitted *jobs* are rejected at submit with
  `register_error` ("job queue full"), and clients **MUST** handle
  that reply.
- **C23.** Clients **MUST NOT** assume any ordering between jobs
  submitted on different connections.

## 8. mTLS conformance

When the endpoint is `--server --tls`:

- **C24.** TLS 1.3 only; the client **MUST** present a certificate
  chaining to the server's CA (`--ca`). No client certificate →
  handshake failure (server logs `tls: handshake rejected` 1:1).
- **C25.** Server identity is verified by **SAN only** (hostname or
  IP-literal SAN; CN is ignored). Clients **MUST** connect using a name
  present in the server cert's SAN — e.g. the production cert carries
  `IP:192.168.150.219` only, so a loopback `127.0.0.1` connect fails
  verification even though it is the same machine.
- **C26.** Fingerprint pinning: when the deployment pins (registry
  discovery, `--pin`), the client **MUST** verify the server's
  SHA-256 certificate fingerprint (case-insensitive compare). A wrong
  pin **MUST** fail the connection before any protocol bytes flow.
- **C27.** Client key files **MUST** be `0600` on POSIX (enforced;
  Windows ACLs govern there). Wildcard server certificates match the
  leftmost label only (OpenSSL semantics — stricter than the Haskell
  `tls` package; accepted divergence, fail-closed).

## 9. Errors and divergences a client must absorb

| Reply | Meaning | Client obligation |
| ----- | ------- | ----------------- |
| `register_error` | registration/submit failures: bad spec, apalache infra failure, queue full, bad bound, async-in-stdio | **MUST** treat as terminal for that register attempt; message is human-readable, not machine-enumerated |
| `protocol_error` | decode failures, out-of-phase messages | **MUST** treat as a client bug; the connection is unusable for that flow |
| `step_mismatch` | implementation diverged from the spec trace | terminal; consume `expected`/`actual`/`hints` for diagnosis |
| `infraError` inside a job outcome | apalache died without output (e.g. loader failure) | **MUST NOT** confuse with a spec verdict; retryable |

Known Haskell divergences (full list: `cutover.md` §3): no trailing
`all_steps_done` after `step_mismatch` (C10); out-of-phase job
messages answered `register_error` vs Haskell's `protocol_error`;
stricter wildcard SAN scope; case-insensitive `--pin`.

## 10. Testing a client implementation

1. **Wire corpus**: `test/fixtures/*.jsonl` — 63 golden transcripts
   frozen from the Haskell implementation, plus `decode_only.jsonl`
   pinning JS-client shapes (absent optional keys). Replay your
   client's encoders against them.
2. **Reference session driver**: `tools/CounterSpec.lean` is the
   canonical conforming MBT client (Counter echo loop, corrupt-count
   and extra-key negative scenarios) — copy its message discipline.
3. **Live harness**: `tools/interop/run.sh` shows an unmodified real
   client (MirrorECMA, TypeScript) exercising stdio + TCP + mTLS +
   registry + negatives end-to-end; `tools/interop/INTEROP.md` lists
   the matrix.
4. **Load shape**: `stress300v2.py` (on r-windev,
   `D:\ModelMirrors\tmp\`) is the reference concurrent driver: a
   4-connection pool, mixed submit/await/cancel, 300 cycles — the
   exact workload the server is stress-gated against.
5. **Self-check against the mirror's own client**: `mirror validate
   --host … --spec …` is a minimal conforming client of the sync
   validate flow; diff your client's exchange against it.

## 11. Reference clients

| Client | Language | Exercises |
| ------ | -------- | --------- |
| `mirror validate` (this repo) | Lean 4 | sync validate over TCP/mTLS, registry discovery, pinning |
| MirrorECMA (`test/smoke.test.ts`) | TypeScript | stdio/TCP/mTLS, registry, TLS negatives |
| Haskell `ModelMirrors validate` | Haskell | the reference wire consumer |
| `tools/CounterSpec.lean` | Lean 4 | full MBT replay incl. mismatch negatives |
| `stress300v2.py` | Python | async jobs, connection pooling, cancel |
