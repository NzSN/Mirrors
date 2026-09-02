# Mirrors

Mirrors is the Lean 4 port of the
[ModelMirrors](https://github.com/NzSN/ModelMirros) mirror: a conformance
checker that connects client state machines to the
[Apalache](https://apalache-mc.org/) model checker over a frozen,
newline-delimited JSON protocol.

The implementation is split deliberately:

- a pure, machine-checked core for protocol transitions, trace handling,
  state diffs, async jobs, resources, and wire codecs;
- a thin effectful shell for transports, process management, concurrency,
  service discovery, and the command-line interface; and
- small C shims for sockets and OpenSSL 3.

The proved Lean functions are the functions executed by the shipping binary;
there is no separate code-extraction step. The wire format remains compatible
with the Haskell reference implementation, as checked by golden fixtures,
differential tests, and client interop tests.

## Features

- Synchronous mirror sessions over standard input/output.
- Concurrent JSONL sessions over plain TCP or TLS 1.3 mutual TLS.
- Bounded async validation and trace-generation jobs in both server modes.
- TLA+ validation, ITF trace generation/replay, and symbolic exploration via
  `apalache-mc`.
- Optional Consul registration, heartbeats, discovery, and certificate
  fingerprint pinning.
- A built-in client for validating a TLA+ specification against a running
  mirror.
- A phase-indexed protocol machine that refines the TLA+ protocol model, plus
  round-trip and behavioral proofs across the pure core and codecs.

For exact client messages and behavior, see the
[interface reference](Docs/interface-reference.md) and
[client implementation guide](Docs/client-implementation-guide.md).

## Requirements

- [elan](https://github.com/leanprover/elan). The repository pins Lean
  `v4.33.0` in [`lean-toolchain`](lean-toolchain).
- A C compiler, OpenSSL 3 development files, and `pkg-config` on Linux.
- `apalache-mc` for actual model-checking operations and the live integration
  tests. Put it on `PATH` or set `APALACHE_MC` to its executable.
- Python 3 and the `openssl` CLI for all test tiers.

Windows builds use the MSYS2 UCRT64 toolchain. The default OpenSSL include and
library directories are `/d/Programs/msys2/ucrt64/include` and
`/d/Programs/msys2/ucrt64/lib`; override them with `OSSL_INC` and `OSSL_LIB`
when needed.

## Build and test

The first build fetches the pinned `batteries` dependency from GitHub.

```bash
lake build
lake test
```

The main executable is written to `.lake/build/bin/mirror` (or
`mirror.exe` on Windows). `lake test` rebuilds the project and runs ten gates:
fixture replay, differential state diffs, stdio smoke, async job-store tests,
Apalache CLI and explorer tests, TCP/mTLS transport tests, registry tests, the
Counter end-to-end flow, and live async server flows.

Tests that require a real Apalache installation self-skip unless
`APALACHE_MC` is set. For example:

```bash
APALACHE_MC=/path/to/apalache-mc lake test
```

The mirror sets `LC_ALL=C.UTF-8` for Apalache child processes. The transport
and registry suites also self-skip individual external-tool tiers when their
requirements are unavailable.

To run the full cross-language matrix against MirrorECMA and the Haskell
reference client, follow [`tools/interop/INTEROP.md`](tools/interop/INTEROP.md)
and run `tools/interop/run.sh` after providing its external client checkouts.

## Usage

### Standard input/output

With no arguments, the mirror reads and writes one JSON object per line on
standard input/output. This mode intentionally supports synchronous protocol
flows only.

```bash
APALACHE_MC=/path/to/apalache-mc .lake/build/bin/mirror
```

### Plain TCP server

```bash
APALACHE_MC=/path/to/apalache-mc \
  .lake/build/bin/mirror --serve 9000 --bind 127.0.0.1 --jobs 4
```

`--jobs N` controls both the connection-worker pool and the process-wide async
job capacity; it defaults to `4`. Without `--bind`, the server listens on all
interfaces. Plain TCP has no transport authentication, so bind it explicitly
when it should not be network-accessible.

### Mutual-TLS server

```bash
chmod 600 pki/server.key

APALACHE_MC=/path/to/apalache-mc \
  .lake/build/bin/mirror --server 9443 --tls \
    --cert pki/server.crt \
    --key pki/server.key \
    --ca pki/ca.crt \
    --bind 0.0.0.0 \
    --jobs 4
```

The TLS transport requires TLS 1.3, a client certificate that chains to the
configured CA, and SAN-based peer identity verification. Private key files
must have mode `0600` on POSIX. Add `--registry http://consul:8500`, or set
`MODELMIRRORS_REGISTRY`, to register the server and publish its certificate
fingerprint.

Transport authentication alone does not authorize model-interface negotiation.
To permit digest verification for selected clients, pass their certificate
SHA-256 fingerprints as one comma-separated allowlist:

```bash
--model-interface-allow-client <64-hex-fingerprint>[,<64-hex-fingerprint>...]
```

Add `--model-interface-descriptor-read` to grant those same clients full
descriptor-read scope. Without the allowlist, negotiated model-interface access
is disabled while legacy mTLS registrations remain available.

### Validate from the CLI

Validate a local specification through a plain TCP server:

```bash
.lake/build/bin/mirror validate \
  --host 127.0.0.1 \
  --port 9000 \
  --spec test/specs/Counter.tla \
  --bound 10
```

Dependencies imported by the specification can be included with repeated
`--dep` options. Predicate overrides are available through `--inv`, `--init`,
`--next`, and `--cinit`.

For mutual TLS, add the client credentials and optionally pin the server
certificate:

```bash
.lake/build/bin/mirror validate \
  --host mirror.example.com \
  --port 9443 \
  --tls \
  --cert pki/client.crt \
  --key pki/client.key \
  --ca pki/ca.crt \
  --pin SHA256_FINGERPRINT \
  --spec Spec.tla
```

Registry discovery replaces `--host` and `--port` with
`--registry http://consul:8500`; TLS client credentials remain required.
The validate command exits `0` for a valid specification, `1` for an invalid
specification, and `2` for an infrastructure or usage error.

## Architecture

```text
client
  │ JSONL
  ▼
stdio / TCP / mTLS transport ───────► C socket and OpenSSL shims
  │ framed messages
  ▼
session driver ──► decode ──► Core.Protocol.step ──► encode
  │                              │
  │                              ├─ Core.Trace / Core.Diff
  │                              └─ Core.Jobs / Core.Resource
  ▼
Apalache adapter ──► apalache-mc
  │
  └─ async job store / explorer JSON-RPC / Consul registry
```

| Zone | Location | Responsibility |
| --- | --- | --- |
| Verified pure core | `Core/`, `Codec/` | Protocol state machine, values, traces, state diffs, job/resource models, JSON and RPC codecs, proofs |
| Trusted Lean shell | `Shell/` | Session loops, bounded worker pool, job execution, Apalache adapters, transports, registry, CLI |
| Trusted native boundary | `Ffi/` | Socket/signal primitives and the OpenSSL 3 TLS shim |
| External oracles | Apalache, Consul, OS | Model checking, discovery, and runtime services |

Every successful pure protocol transition is related to the model in
[`specs/MirrorProtocol.tla`](specs/MirrorProtocol.tla) by the refinement
theorem in [`Core/Protocol.lean`](Core/Protocol.lean). The shell and native
boundary are deliberately outside that proof claim and are covered by runtime,
negative, and interop tests instead. See the
[architecture overview](Docs/architecture-overview.md) for the complete trust
boundary and data flow.

## Repository layout

- `Core/` — pure domain models and proofs: values, traces, diffs, protocol,
  jobs, and resource lifecycles.
- `Codec/` — total JSON, protocol bridge, explorer RPC, and Consul codecs with
  round-trip and fidelity proofs.
- `Shell/` — session drivers, transports, Apalache integration, worker pool,
  registry, client, and CLI.
- `Ffi/` — Lean declarations and C shims for sockets, signals, and TLS.
- `specs/` — TLA+ protocol models and model-checking witnesses.
- `test/fixtures/` — the frozen Haskell wire corpus and differential cases.
- `tools/` — test executables, fixture tooling, mock services, and interop
  harnesses.
- `Docs/` — architecture, protocol, design, review, and migration records.

## Clients

- [MirrorCPP](https://github.com/NzSN/MirrorCPP)
- [MirrorLean](https://github.com/NzSN/MirrorLean)
- [MirrorRust](https://github.com/NzSN/MirrorRust)
- [MirrorECMA](https://github.com/NzSN/MirrorECMA)

All four clients have live Counter replay coverage against this Lean mirror,
including real mTLS server mode. The top-level `tools/interop/run.sh` runs the
three non-Lean client suites (MirrorECMA, MirrorCPP, and MirrorRust) together;
MirrorLean also retains its live gates in its own repository.

## Project status

The Lean port is feature-complete through the transport, registry, CLI, and
cross-platform worker-pool phases. Both TCP server modes run bounded async
sessions on Linux and Windows; the older Windows synchronous fallback has been
retired. Standard input/output remains synchronous by design for Haskell
compatibility.

Known compatibility differences, the remaining top-level interop-runner
integration, and the Haskell deprecation criteria are tracked in
[`Docs/cutover.md`](Docs/cutover.md).
Notable implementation changes are recorded in [`CHANGELOG.md`](CHANGELOG.md).

One Lake build-system caveat remains: changing only a C shim may not relink an
existing executable. Remove the affected `.lake/build/bin/*` binary and shim
object before rebuilding after C-only edits.

## Documentation

- [Architecture overview](Docs/architecture-overview.md) — five-minute system
  map and trust boundaries.
- [Architecture details](Docs/architecture-details.md) — module-level data and
  control flow.
- [Supported interface reference](Docs/interface-reference.md) — complete
  protocol messages and CLI transport modes.
- [Client implementation guide](Docs/client-implementation-guide.md) — client
  conformance rules and error handling.
- [Non-Lean client test coverage](Docs/client-test-coverage.md) — executable
  C1–C27 evidence mapped across MirrorECMA, MirrorCPP, and MirrorRust.
- [Lean 4 refactor design](Docs/lean4-refactor-design.md) — original goals,
  proof obligations, and phase plan.
- [Worker-pool design](Docs/worker-pool-design.md) and
  [implementation status](Docs/worker-pool-impl-status.md) — concurrency model
  and cross-platform validation.
- [TLS FFI review](Docs/tls-ffi-review.md) — TLS policy and native-boundary
  security review.
- [Final review](Docs/final-review.md) — acceptance audit and proof review.
- [Cutover plan](Docs/cutover.md) — compatibility differences and remaining
  migration work.
