# Mirrors — Client Implementation Guide & Conformance Specification

> How to implement a client of the Mirrors mirror server, and the
> normative rules a conforming client must obey.
> Companion docs: `interface-reference.md` (exact wire shapes — the
> message catalog is NOT repeated here),
> `model-interface-runtime-distribution-design.md` (runtime negotiation),
> `generated-model-interface-spec.md` (portable generated bindings),
> `model-interface-compiler-design.md` (build-time compiler), `cutover.md`
> (Haskell divergences), `worker-pool-design.md` (server concurrency model),
> and `tls-ffi-review.md` (TLS policy details).
> Wire truth is pinned by `test/fixtures/*.jsonl` (the golden corpus,
> frozen from the Haskell reference implementation); this document is the
> behavioral layer on top of it.
>
> Normative keywords **MUST / MUST NOT / SHOULD / MAY** are used as in
> RFC 2119. Numbered rules **C1–C27** are the base conformance checklist —
> a client that satisfies every MUST is wire-compatible with both the Lean 4
> mirror and the Haskell reference (`ModelMirros@3496251`). Rules prefixed
> **MI** are additionally mandatory for a client that advertises version-1
> runtime model-interface support. The Haskell compatibility statement applies
> to registrations without that optional extension.

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
- **C2.** Clients **MUST** enforce the uniform **65,535-byte payload** limit
  (not counting the terminating newline) on raw UTF-8 bytes before JSON
  parsing and after final encoding. They **MUST NOT** emit a larger line or
  use an unbounded receive accumulator. Keep individual messages small; ship
  TLA+ sources via the `spec.sources` array (§5) rather than inventing side
  channels.
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
  `explorer_session_done`, `step_mismatch`, `register_error`, or
  `protocol_error`), the flow is over. A
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
divergence, §10).

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

## 9. Runtime model-interface support (optional negotiated profile)

The model-interface extension verifies that a local generated binding describes
the exact interface Mirrors resolved from the registration's spec, contract,
typed trace evidence, and run profile. It distributes **data**, never an
implementation adapter or executable code.

The Mirrors server and MirrorECMA's compiled-verification and dynamic-descriptor
paths are implemented. The MirrorCPP, MirrorRust, and MirrorLean static
registries are planned. Implement only the profile your client can honestly
advertise:

| Client profile | Request | Local executable behavior | Version-1 use |
| --- | --- | --- | --- |
| Legacy stepping | no `modelInterface` field | caller supplies `StateComputer` | Existing, unchanged entry points |
| Compiled verification | `verify` | precompiled generated binding plus application adapter | Default production profile; implemented in MirrorECMA |
| Dynamic descriptor | `descriptor` | local handler/observer registry interpreted by MirrorECMA | Development-only; implemented in MirrorECMA |

The three artifacts have deliberately different owners:

```text
Mirrors compiler -> canonical ModelInterfaceDescriptor + semantic digest
target emitter   -> GeneratedBinding implementing StateComputer
application      -> local ImplementationAdapter for the real SUT
```

- **MI1.** Existing non-negotiated entry points **MUST** remain
  source-compatible, send no `modelInterface` field, and retain their existing
  replay behavior. The extension is allowed only on `register` and
  `register_traces`; version 1 does not extend validate, trace-generation,
  async-job, or explorer registrations.
- **MI2.** A client **MUST** treat a descriptor and generated metadata as inert
  interface data. It **MUST NOT** evaluate or compile received content, load a
  module/plugin/symbol named by it, retrieve an executable adapter, or expose
  expected trace state to the application adapter.

### 9.1 Build and register a compiled binding

Static clients obtain their binding before deployment. A typical build pipeline
is:

```sh
/path/to/Mirrors/.lake/build/bin/model_interface_gen resolve \
  --spec specs/Counter.tla \
  --contract specs/Counter.mirror-interface.json \
  --evidence traces/counter.itf.json \
  --param-var parameters \
  --lock generated/Counter.mirror-interface.lock.json

/path/to/Mirrors/.lake/build/bin/model_interface_gen generate \
  --lock generated/Counter.mirror-interface.lock.json \
  --target mirrorecma-v1 \
  --out generated/mirrorecma
```

The implemented target is currently `mirrorecma-v1`; new target profiles must
obey `generated-model-interface-spec.md`. Check the generated tree in CI instead
of repairing it there:

```sh
/path/to/Mirrors/.lake/build/bin/model_interface_gen check \
  --spec specs/Counter.tla \
  --contract specs/Counter.mirror-interface.json \
  --evidence traces/counter.itf.json \
  --param-var parameters \
  --lock generated/Counter.mirror-interface.lock.json \
  --target mirrorecma-v1 \
  --out generated/mirrorecma

/path/to/Mirrors/.lake/build/bin/model_interface_gen preflight \
  --lock generated/Counter.mirror-interface.lock.json \
  --trace traces/counter.itf.json \
  --require-all-actions
```

`resolve` produces the reviewed semantic lock. `generate` produces an owned,
deterministic source tree whose metadata exports the semantic digest and the
complete normalized companion contract. The application implements the
generated port and registers a factory that combines that adapter with the
generated binding. The contract, lock, descriptor, generated binding, and
implementation adapter are not interchangeable.

- **MI3.** A compiled client **MUST** embed the compiler-produced semantic
  digest and normalized contract, select a precompiled binding, and perform no
  runtime descriptor interpretation, code generation, dynamic loading, or
  artifact retrieval. Generated files **MUST NOT** be hand-edited.
- **MI4.** The build and runtime configurations **MUST** agree on the effective
  `paramVars` value and `mirrors.state-computer/v1` behavior. A configuration
  mismatch is a local failure before any application handler or observer runs.

### 9.2 Encode the registration extension

The generated metadata supplies the two variable parts of a compiled request:

```text
modelInterface = {
  schema: "mirrors.model-interface-negotiation/v1",
  request: "verify",
  policy: "require",
  acceptDescriptorSchemas: ["mirrors.model-interface-descriptor/v1"],
  expectedSemanticDigest: renderWire(generated.semanticDigest),
  contract: { inline: generated.contract }
}
```

`renderWire` emits exactly `sha256:` followed by 64 lowercase hexadecimal
characters. Parse it into a branded 32-byte/native digest value and compare
that value; do not compare permissively normalized strings. The generated
target may expose the payload as 64 lowercase hex characters and let the client
codec add the `sha256:` wire prefix.

| Field | Compiled `verify` | Dynamic `descriptor` |
| --- | --- | --- |
| `schema` | Exactly `mirrors.model-interface-negotiation/v1` | Same |
| `request` | `verify` | `descriptor` |
| `policy` | `require` by default; `prefer` only by explicit caller choice | Same |
| `acceptDescriptorSchemas` | Nonempty, unique, ordered; at most 8 | Same |
| `expectedSemanticDigest` | Required | Optional; a mismatch is still fatal |
| `ifNoneMatch` | Forbidden | Optional cache validator |
| `contract` | Exactly `{ "inline": <complete ContractV1> }` | Same |

- **MI5.** The outer protocol stays field-additive, but every versioned
  negotiation, failure, companion-contract, and descriptor object **MUST** use
  strict duplicate-aware decoding: reject duplicate keys, unknown fields,
  invalid field combinations, noncanonical digests, and resource-limit
  violations. Optional fields accept absent or explicit `null`; encoders omit
  absent values.
- **MI6.** A client **MUST** send the complete generated `ContractV1` inline.
  The reserved contract-digest reference is unsupported in version 1, and the
  client **MUST NOT** infer a companion file from the server-side `specPath`.
- **MI7.** The contract and expected digest **MUST** come from the same verified
  generated metadata. The client **MUST NOT** substitute a model name,
  `interfaceVersion`, provenance digest, version range, or “compatible” digest
  for exact semantic identity.

### 9.3 Gate replay on the first reply

Negotiation adds no protocol phase. It extends the existing first reply:

```text
client -> register or register_traces + modelInterface
mirror -> spec_validated + modelInterface   -> validate, then create binding
       -> register_error + modelInterface   -> terminal, create nothing
```

The server may have already queued `initial_state` after `spec_validated`.
That does not authorize the client to read it into the replay loop, invoke the
adapter, or send `report_state` until the negotiation extension is validated.

| Reply seen by client | Required action |
| --- | --- |
| `matched` for `verify` | Require supported descriptor schema and an exact returned-digest match, then construct the selected binding |
| `resolved` for `descriptor` | Validate the complete envelope and descriptor, recompute identity, then validate local handlers |
| `not_modified` for `descriptor` | Use only an existing byte-valid, digest-valid cache entry |
| `unsupported`, `unavailable`, or `too_large` | Under `require`, expect terminal `register_error`; under `prefer`, continue only through an explicit permitted fallback |
| `mismatch` | Terminal under both policies; never fall back |
| missing extension from an old server | Fail under `require`; under `prefer`, use only an explicit fresh fallback factory |
| malformed, contradictory, or mode-inappropriate extension | Close the session as a client-side protocol/negotiation failure |

- **MI8.** Under `require`, a missing reply, required failure, malformed reply,
  unsupported schema, unexpected status, or digest mismatch **MUST** close the
  flow before any adapter factory, SUT constructor, action, observer, or other
  application callback runs. No `report_state` may be sent.
- **MI9.** A `verify` client **MUST** accept normal negotiated replay only from
  a strictly valid `matched` reply whose descriptor schema is accepted and
  whose parsed semantic digest exactly equals the embedded digest. It **MUST**
  reject descriptor bytes on `matched` and any status/field combination not
  allowed by `model-interface-runtime-distribution-design.md` §9.
- **MI10.** `prefer` **MUST NOT** weaken a digest pin. It may continue after an
  old-server omission or a permitted non-pin failure only when the caller
  explicitly supplied a separate legacy fallback factory. Libraries
  **MUST NOT** silently change `require` to `prefer` or reuse the negotiated
  factory as an implicit fallback.

### 9.4 Select and own the local binding

A semantic digest identifies an interface, not a unique application adapter.
Compiled clients therefore use an immutable local registry keyed by:

```text
{
  semanticDigest,
  adapterId,
  targetProfile,
  stateComputerContractVersion
}
```

Registry lookup may occur before opening the connection, but it is pure: it
returns a factory without constructing the SUT. After `matched`, the runner
invokes exactly that factory to create one fresh session-local binding:

```text
LocalBinding = {
  semanticDigest,
  computer: StateComputer,
  assertCompatibleConfig(effectiveConfig),
  coverage?(),
  dispose()
}
```

- **MI11.** Registry lookup **MUST** use the exact four-part key and return
  exactly one factory. It **MUST NOT** guess “latest”, search version ranges,
  choose the closest digest, or try several adapters until one works.
- **MI12.** The selected factory **MUST** run only after successful negotiation
  (or an explicit permitted legacy fallback), return a fresh binding for that
  session, and perform no remote artifact retrieval. The runner **MUST** recheck
  the binding digest and effective configuration before entering replay.
- **MI13.** Negotiated and legacy entry points **SHOULD** converge on the same
  replay loop after binding selection. After construction, the runner **MUST**
  attempt `dispose` exactly once on success, `step_mismatch`, decode or
  transport failure, a thrown `StateComputer`, and binding-validation failure.
  A cleanup failure is secondary to an earlier primary failure.

Implementation skeleton:

```text
key, factory = registry.lookupExact(generated metadata, local adapter config) // pure
send(extendRegistration(base registration, verify request))
first = readOneBoundedUtf8Line()
authorization = decodeStrictlyAndAuthorize(first, policy, key.semanticDigest)
binding = authorization == matched ? factory(config) : explicitFallback(config)
try:
  require binding.semanticDigest == key.semanticDigest
  binding.assertCompatibleConfig(config)
  replayLoop(binding.computer)
finally:
  binding.disposeExactlyOnce()
  connection.close()
```

Keep failure families distinct: structured server negotiation failures,
client-local selection/configuration failures, generated-binding conversion or
lifecycle failures, transport failures, and ordinary Mirrors `step_mismatch`
are not interchangeable verdicts.

- **MI14.** Client-local negotiation failures **SHOULD** expose stable codes
  such as `negotiation_missing`, `descriptor_digest_invalid`,
  `adapter_not_registered`, `adapter_ambiguous`, `binding_digest_mismatch`,
  `binding_config_mismatch`, `adapter_factory_failed`, and
  `legacy_fallback_unavailable`. A structured `register_error.modelInterface`
  code remains a server failure and **MUST NOT** be collapsed into those local
  codes or into a conformance mismatch.

### 9.5 Implement descriptor mode only for a local interpreter

`descriptor` mode is implemented by MirrorECMA's development handler registry.
It is not the runtime path for C++, Rust, Lean, or normal production TypeScript
clients.

- **MI15.** Before caching or using `resolved`, a descriptor client **MUST**
  validate its strict schema, exact `descriptorBytes`, structural limits, and
  canonical semantic digest. It **MUST** enforce the 32,768-byte inline
  descriptor limit and the 65,535-byte final line limit; it must never accept a
  truncated, chunked, compressed, or partially decoded descriptor.
- **MI16.** `not_modified` succeeds only when a local cache entry exists and
  its bytes recompute to the advertised digest under the same byte, depth, and
  node limits. A missing or corrupt entry aborts the session; retry on a new
  connection without `ifNoneMatch`.
- **MI17.** A dynamic handler registry **MUST** match every stable initializer,
  action, and observation ID exactly, contain no extras, accept input records
  keyed by the declared stable input IDs, and declare the same semantic digest
  as the verified descriptor. It **MUST** support every descriptor type and map
  aliases only to their primary action. It validates all inputs before mutation,
  performs exactly one observation pass after an action, and permanently
  poisons the binding after an invalid observer value. It never constructs
  handler bodies from descriptor content.

### 9.6 Transport authorization is separate from identity

| Transport | Version-1 model-interface authority |
| --- | --- |
| Local stdio | Explicit local principal; verification and descriptor read allowed |
| Plain TCP | None by default; requires an operator-configured trusted-deployment policy |
| mTLS | Legacy registration alone after CA validation; negotiation additionally requires the client leaf fingerprint in `--model-interface-allow-client` |
| mTLS descriptor read | Also requires server option `--model-interface-descriptor-read` for that allowlist |

- **MI18.** A semantic digest **MUST NOT** be treated as authentication or
  authorization. Clients retain C24–C27 server authentication, SAN validation,
  and pinning. An authorization failure is terminal and must cause zero SUT
  calls; clients **MUST NOT** retry it by silently dropping negotiation.

Full request/reply/failure schemas, status precedence, descriptor identity,
limits, and security rationale are normative in
`model-interface-runtime-distribution-design.md`. Generated port, binding,
adapter, value-conversion, and lifecycle semantics are normative in
`generated-model-interface-spec.md`.

## 10. Errors and divergences a client must absorb

| Reply | Meaning | Client obligation |
| ----- | ------- | ----------------- |
| `register_error` | registration/submit failures: bad spec, apalache infra failure, queue full, bad bound, async-in-stdio, or required model-interface failure | **MUST** treat as terminal for that register attempt; the base `error` is human-readable, while negotiated failures may also carry stable structured `modelInterface` data |
| `protocol_error` | decode failures, out-of-phase messages | **MUST** treat as a client bug; the connection is unusable for that flow |
| `step_mismatch` | implementation diverged from the spec trace | terminal; consume `expected`/`actual`/`hints` for diagnosis |
| `infraError` inside a job outcome | apalache died without output (e.g. loader failure) | **MUST NOT** confuse with a spec verdict; retryable |

Known Haskell divergences (full list: `cutover.md` §3): no trailing
`all_steps_done` after `step_mismatch` (C10); out-of-phase job
messages answered `register_error` vs Haskell's `protocol_error`;
stricter wildcard SAN scope; case-insensitive `--pin`.

## 11. Testing a client implementation

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
6. **Negotiation codec and gate**: `tools/ModelInterfaceSpec.lean` and
   `tools/ModelInterfaceDistributionSpec.lean` cover strict objects, all policy
   statuses, legacy byte identity, authorization, caching, resource limits,
   required-failure gating, and in-memory replay. Both are always-on parts of
   `lake test`.
7. **Generated-binding safety**: consume the language-neutral fixtures named by
   `generated-model-interface-spec.md` and prove zero SUT/factory calls for
   missing, malformed, unauthorized, and wrong-digest replies. Also test one
   behaviorally wrong observer after a successful match so ordinary
   `step_mismatch` remains reachable.
8. **Implemented client reference**: MirrorECMA's
   `model-interface-protocol.test.ts`, `model-interface-descriptor.test.ts`,
   `model-interface-dynamic.test.ts`, `model-interface-runner.test.ts`, and
   `model-interface-counter.smoke.ts` demonstrate MI5–MI18 over scripted
   transports plus real stdio and allowlisted mTLS. They cover exact canonical
   descriptor identity, verified cache reuse, zero-callback failures, dynamic
   lifecycle poisoning, descriptor-read denial, and ordinary
   `step_mismatch`. The top-level `tools/interop/run.sh` gate includes both D3
   compiled verification and D4 dynamic descriptor replay.

For a client claiming the compiled-verification profile, the minimum negative
matrix is: duplicate/unknown nested fields, noncanonical and wrong digests,
missing extension from an old server, every unexpected status, structured
`register_error`, unauthorized mTLS, unregistered/ambiguous adapter, binding
digest/config mismatch, factory failure, replay failure, and dispose failure.
Every pre-match case must assert zero SUT and zero adapter-factory calls.

## 12. Reference clients

| Client | Language | Exercises |
| ------ | -------- | --------- |
| `mirror validate` (this repo) | Lean 4 | sync validate over TCP/mTLS, registry discovery, pinning |
| MirrorECMA (`test/smoke.test.ts`, `test/model-interface-*.ts`) | TypeScript | stdio/TCP/mTLS, registry, TLS negatives, D3 compiled verification, D4 dynamic descriptor/cache replay |
| Haskell `ModelMirrors validate` | Haskell | the reference wire consumer |
| `tools/CounterSpec.lean` | Lean 4 | full MBT replay incl. mismatch negatives |
| `stress300v2.py` | Python | async jobs, connection pooling, cancel |
