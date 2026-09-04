# Non-Lean client conformance-test coverage

Status: MirrorECMA, MirrorCPP, and MirrorRust have executable coverage for the
normative C1–C27 client rules in `Docs/client-implementation-guide.md`.
MirrorCPP now enforces the 65,535-byte inbound payload cap in its shared
stdio/TCP framing path and its TLS accumulator. This matrix is executable
conformance evidence, not a formal proof of the non-Lean implementations.

| Rules | Required behavior | MirrorECMA | MirrorCPP | MirrorRust |
| --- | --- | --- | --- | --- |
| C1–C3 | Strict JSONL framing, 65,535-byte inbound/outbound limit, `proto_step` dispatch, additive fields | `transport.test.ts`, `protocol.test.ts`, canonical corpus; strict LF termination and byte-level fatal UTF-8 framing | inbound/outbound limit over stdio/TCP/TLS, framing/transport tests, protocol additive-field test, full golden corpus | `transport.rs`, protocol additive-field test, canonical supported-message corpus |
| C4–C7 | Legal session opening/termination, clean or peer-first close, no protocol heartbeat assumption | one-shot/`Connection` tests; disconnect eviction and query-based liveness in live smoke | phase-guard, fault-close, and transport EOF tests | one-shot APIs plus protocol-error poisoning, transport close, and live disconnect eviction |
| C8–C12 | Exactly one report per driven state, full ITF state, terminal mismatch, arbitrary integers, no fixed trace length | real Counter replay plus deliberately extra-key mismatch over stdio/TCP/mTLS | real Counter replay plus deliberately extra-key mismatch over stdio/TCP/mTLS; value/diff corpus | real Counter replay plus deliberately extra-key mismatch over stdio/TCP/mTLS; arbitrary-precision codec tests |
| C13–C16 | Inline dependency closure, optional absent/null parity, `constInit`/`paramVars`, validate bounds | spec resolver, canonical corpus, authoritative Counter, no-write bound tests | spec resolver, `decode_only` corpus, authoritative Counter, bound registration error | spec resolver, normalized absent/null corpus, authoritative Counter, no-write bound tests |
| C17–C23 | Cross-connection job IDs, long-poll/idempotence, cancellation, sync/async congruence, unknown, queue pressure, unordered completion | scripted async suite and live reverse-await/cancel/evict/queue-full matrix | scripted async suite and real sync/async comparison plus reverse awaits | scripted async suite and real cross-connection/reverse-await/cancel/evict/queue-full matrix |
| C24–C27 | TLS 1.3 mTLS, SAN-only identity, fingerprint pinning, key permissions | real TLS 1.2 rejection, rogue client, CN-only, wrong pin, registry failover, mode 0644 | TLS fixture suite: TLS 1.2, wrong CA, CN-only, pins, registry, mode 0644 | real TLS 1.2 rejection, rogue client, CN-only, wrong pin, registry failover/override, mode 0644 |

The error obligations in section 10 are also covered: `register_error`, poisoned
`protocol_error`, terminal `step_mismatch`, and `infraError` distinct from a
validation verdict.

## Compiled model-interface D3 coverage

MirrorECMA additionally covers the runtime-distribution design's compiled
verification slice through `model-interface-protocol.test.ts`,
`model-interface-runner.test.ts`, and `model-interface-counter.smoke.ts`:

- strict duplicate-aware contract/request/reply decoding and exact digest
  syntax;
- exact immutable adapter lookup, factory creation only after `matched`, and
  exactly-once binding disposal;
- old-server `prefer` only through an explicit fresh fallback factory;
- zero factory/SUT calls for missing negotiation, wrong digest, malformed
  replies, unauthorized mTLS, and framing failures;
- real Counter replay over stdio and allowlisted mTLS, plus an intentionally
  incorrect observer reaching ordinary `step_mismatch`.

## Dynamic model-interface D4 coverage

MirrorECMA's development-only dynamic path is covered by
`model-interface-descriptor.test.ts`, `model-interface-dynamic.test.ts`,
`model-interface-runner.test.ts`, and `model-interface-counter.smoke.ts`:

- strict descriptor/reply/failure codecs and byte-identical Lean-compatible
  canonical descriptor hashing, including the fixed Counter digest;
- bounded content-verified LRU caching, exact request correlation for
  `ifNoneMatch`/`not_modified`, and missing/corrupt cache rejection;
- exact local handler and observer IDs, source-free conversion for supported
  native types, alias dispatch, all-inputs-before-mutation, and permanent
  lifecycle poisoning;
- zero callbacks and no `report_state` for malformed/wrong-digest descriptors,
  unsupported types, missing cache entries, registry mismatches, and denied
  descriptor access;
- real Counter `resolved -> not_modified` replay over stdio, authorized mTLS
  descriptor read, denial without descriptor-read scope, exactly-once cleanup,
  and a wrong observer reaching ordinary `step_mismatch`.

## Static model-interface D5 coverage

MirrorCPP covers its compiled-only D5 profile through
`model_interface_test.cpp`, `generated_model_interface_test.cpp`, and the real
mirror integration suite:

- strict duplicate-aware verification request/reply/failure decoding,
  canonical branded digests, and exact four-part immutable adapter lookup;
- zero factory/SUT calls for missing, malformed, wrong-digest, unregistered,
  ambiguous, and unauthorized paths, with explicit-only `prefer` fallback;
- generated C++23 typed ports and checked codecs for arbitrary integers and the
  complete portable primitive/container/map/variant baseline;
- input-before-mutation, lifecycle poison/reentrancy, classified adapter and
  observation errors, binding digest/config checks, and exactly-once cleanup
  with primary-error precedence;
- real generated Counter replay over stdio and allowlisted mTLS, denial without
  the allowlist, and a wrong observer reaching ordinary `step_mismatch`.

D5 exact-digest registries for MirrorRust and MirrorLean, and the proposed
common portable cross-language fixture suite, remain planned.

## One-command gate

From the Mirrors repository:

```sh
tools/interop/run.sh
```

The runner builds the Lean mirror, runs all three non-Lean unit/golden suites,
executes their live Counter and transport-negative gates, and then retains the
Haskell validate client as an independent compatibility oracle. Its checkout
locations can be overridden with `ECMA_REPO`, `CPP_REPO`, and `RUST_REPO`.

MirrorRust does not currently expose the optional explorer APIs. Its canonical
wire test therefore covers every message family in its advertised public API;
the C1–C27 rules do not require a client to implement every optional register
flow. MirrorECMA and MirrorCPP retain explorer coverage.
