# Mirrors — Architecture Details

> Source map reviewed on 2026-10-03 against base `6abd893` plus the current
> compiler/client working-tree changes.
> This describes implemented source paths and proof scope, not a new build,
> installed-service acceptance run, or release qualification.
> Read the [overview](architecture-overview.md) first; the
> [framework map](framework-map.md) covers the related repositories.
> Explanatory judgments use the [shared semantic notation](semantic-notation.md).

## 1. Repository and responsibility map

| Location | Responsibility | Assurance boundary |
| --- | --- | --- |
| [`Core/`](../Core/) | Values, traces, comparison, protocol/job/resource machines, model-interface resolution, TLA+ syntax and elaboration, framework catalog rules | Pure definitions with module-specific theorems and executable checks; location alone does not mean every property is proved |
| [`Codec/`](../Codec/) | JSON, ITF/wire, explorer, Consul, model-interface and catalog representations | Pure codecs, canonicalization and specific round-trip/tag laws |
| [`Shell/`](../Shell/) | CLI, sessions, transports, processes, source capture, compiler publication, runtime authorization/cache | Trusted orchestration; some helpers and emitters are pure, but no whole-shell refinement is claimed |
| [`Ffi/`](../Ffi/) | Native sockets, TLS, signals, timeouts and platform helpers | Trusted Lean declarations and C implementations |
| [`Main.lean`](../Main.lean) | `mirror` executable dispatch | Effectful entry point |
| [`specs/`](../specs/) | Protocol/resource models and example TLA+ models | Specifications and model-check inputs, with separately scoped correspondence claims |
| [`test/fixtures/`](../test/fixtures/) | Frozen wire, compiler, frontend and other test inputs | Fixtures are test inputs, not evidence that a current run passed |
| [`tools/`](../tools/) | Development CLIs, regression gates, interop, distribution and evidence tools | Executable validation and packaging outside the protocol proof |
| [`catalog/`](../catalog/), [`distribution/`](../distribution/) | Component capabilities, selected combinations and locked distribution inputs | Declarations and identities, kept separate from observed acceptance |
| [`Plans/`](../Plans/), [`CHECKPOINTS.md`](../CHECKPOINTS.md) | Decisions, campaign work and dated evidence references | Consult exact recorded identities and unmet obligations |

The library roots and executable targets are defined in
[`lakefile.lean`](../lakefile.lean). Read [`lean-toolchain`](../lean-toolchain),
[`lake-manifest.json`](../lake-manifest.json), and
[`tools/ci/versions.env`](../tools/ci/versions.env) for the selected tool versions
instead of treating a version copied into architecture prose as a live pin.

## 2. Runtime paths

### CLI and session entry

[`Main.lean`](../Main.lean) delegates parsing and orchestration to
[`Shell.Cli`](../Shell/Cli.lean):

| Mode | Implemented path |
| --- | --- |
| No arguments | Stdio transport → `runLocalStdioSession` → `Shell.Mirror.run` with real `syncOracles`; one synchronous registration flow |
| `--serve` | TCP connection pool → `asyncMirrorSession` → `Shell.Mirror.runAsync` using the process-shared job store |
| `--server --tls` | mTLS connection pool → verified peer fingerprint and authorization context → the same async session entry; optional Consul registration |
| `validate` | Client-side source-closure capture → direct or registry-discovered remote transport → synchronous or asynchronous validation request |
| `trace-gen` | The same remote connection/source preparation → synchronous or asynchronous trace generation → local capture artifacts |
| `--version` | Print the product version from [`Shell.Version`](../Shell/Version.lean) |

`validate` and `trace-gen` are Mirror client modes. The selected Mirror server
executes Apalache behind its oracle boundary. The separate
`model_interface_gen`, `tla_frontend`, `framework_catalog`, and
`model_interface_reduction` executables are development/contract tools, not
additional `mirror` wire modes.

The shared [`Transport`](../Shell/Transport/Stdio.lean) record supplies
`recv`, `send`, and a trace-delivery scope. Stdio, TCP and TLS frame one JSON
message per line with a 65,535-byte UTF-8 payload bound, excluding the final LF.
The main session entry points use duplicate-aware
[`Codec.StrictJson`](../Codec/StrictJson.lean), then decode registration
extensions and the wire message. Transport framing and parser invocation remain
trusted shell behavior; codec theorems do not prove those IO operations.

### Selective use of the protocol machine

[`Shell.Mirror.Session`](../Shell/Mirror/Session.lean) owns payloads, loaded
traces, cursors and actual wire sends. Its relationship to
[`Core.Protocol`](../Core/Protocol.lean) is specific to each path. The module
defines the global function `step`, called as `_root_.step` from the shell:

| Session operation | Control and effect path |
| --- | --- |
| `register` | Generate a trace bundle, resolve any eligible model-interface request, preflight when required, then call `step` with the admission result before replay |
| `register_traces` | Load supplied ITF paths, apply the effective parameter partition, resolve/preflight if eligible, then call `step` before replay |
| Replay `report_state` | Compare expected and actual states with `diffState`; pass match and final-step bits through `step`; construct payload-bearing replies in the shell |
| Synchronous validate or trace generation | Invoke the corresponding injected oracle and send its result directly |
| Explorer registrations | Transfer the wire exchange to the explorer flow in `Shell.Apalache.Runner` |
| Async register/query/await/cancel | Dispatch directly through `Shell.Jobs.Store`, whose job transitions execute `Core.Jobs.transition` |

Consequently, “one `step` per wire message” is not the implementation.
Even replay constructs its wire replies separately from the abstract output
list. The tag-level protocol theorem does not establish end-to-end refinement
of all session paths.

`run` receives one registration and completes its flow. `runAsync` loops over
registrations and job operations; synchronous requests run inline on that
connection. Async jobs return `job_accepted` promptly. Terminal query/await
operations return the retained `job_result`; pending jobs or timed-out awaits
return status. EOF, decode failure, transport exceptions, or a completed flow
that sets the session phase to `done` lead to session cleanup.

### Replay and the comparison boundary

Replay runs `traceSteps` over each loaded trace. Step zero sends `initial_state`
with full expected state variables; later steps send `next_step` with the action
and parameter bindings. The application client executes its own adapter and
returns `report_state`. Mirrors compares the reported state; it does not execute
the application itself.

`replayStep` uses `diffState` and threads the resulting match/final-step bits
through the pure session machine. Every matching report receives `step_ok`, and
the final matching step also receives `all_steps_done`. The first mismatch
receives `step_mismatch` with filtered expected/actual states and ordered hints;
remaining traces are not replayed. This is a comparison against the exercised
trace, not a proof of every possible application behavior. See the
[wire reference](interface-reference.md) and
[client implementation guide](client-implementation-guide.md).

### Connection workers, jobs and resource ownership

Both server modes construct one job store and one descriptor-resolution service
per process. `--jobs N` defaults to 4; the CLI uses `max 1 N` for connection
workers, live-job capacity, and descriptor-resolution concurrency. These are
separate mechanisms, not one shared semaphore.

[`Shell.Transport.Tcp`](../Shell/Transport/Tcp.lean) implements the common
bounded connection queue, default capacity 128, and persistent dedicated worker
tasks. A worker serves one connection, closes it, then returns to the queue.
[`Shell.Transport.Tls`](../Shell/Transport/Tls.lean) uses that pool and performs
the TLS handshake and peer-fingerprint extraction before session dispatch.
Both Windows and Linux use this implementation; the older Windows sequential
fallback is historical. See the [worker-pool design](worker-pool-design.md) and
its dated [implementation ledger](worker-pool-impl-status.md).

[`Shell.Jobs.Store`](../Shell/Jobs/Store.lean) holds a mutex-protected table,
monotonic job IDs, promises, retained wire outcomes and cancellation tokens.
Submission rejects immediately when the live, nonterminal job count reaches
capacity. Each accepted job gets a dedicated task, while a separate semaphore
bounds executing job bodies. Terminal state changes use `Core.Jobs.transition`.

The submitting session tracks its own IDs. Its `finally` attempts cancellation
and eviction for each of those IDs, including after errors. Query, await and
cancel look up IDs in the shared store; a querying connection need not have
submitted the job. Session teardown evicts the IDs recorded by that owner,
regardless of which connections queried them.
Completed outcomes remain available for repeated retrieval while the owner is
open, so live-job capacity is not a bound on all retained result memory.

Cancellation marks logical state and invokes registered cleanup hooks. The
worker keeps its semaphore permit until its body unwinds and settles, even if
its table entry has been cancelled or evicted. The Apalache runner terminates
and collects child processes, then unwinds owned run directories and inline
source resources. Borrowed source paths are not deleted. A cancellation reply
does not assert that all physical cleanup has finished; a body that never
returns can retain its permit. Resource acknowledgements and global composition
are covered separately in [async resource proofs](async-resource-lean-proofs.md)
and the [resource model](async-protocol-resource-model.md).

### Apalache and explorer adapters

[`Shell.Apalache.Runner`](../Shell/Apalache/Runner.lean) provides the two real
injection points: `syncOracles` for inline flows and `jobRunner` for asynchronous
jobs. [`SpecSource`](../Shell/Apalache/SpecSource.lean) captures source closures
and distinguishes owned materializations from borrowed files. Each invocation
uses a temporary run directory rather than the mirror's working directory.
Negotiated borrowed registrations attempt an owned source snapshot so the
descriptor provenance identifies the bytes supplied to Apalache.

[`Shell.Apalache.Cli`](../Shell/Apalache/Cli.lean) selects `APALACHE_MC`, falling
back to `apalache-mc`. Validation runs `typecheck` followed by bounded `check`;
trace generation runs `check --output-traces`. Exit classification distinguishes
model verdicts from infrastructure failures. The async variant registers child
termination hooks and reaps the process before acknowledging its release.

[`Shell.Apalache.Explorer`](../Shell/Apalache/Explorer.lean) starts a local
Apalache explorer process on the Mirror host and communicates using HTTP/JSON-RPC.
`register_explore` drives interactive replay and comparison;
`register_explore_session` exposes transition assumptions, state queries,
invariant checks, stepping, rollback and disposal. These effectful flows do not
inherit the pure protocol theorem merely because they reuse `diffState`.

### Trace delivery and retained capture

[`Shell.Transport.TraceDelivery`](../Shell/Transport/TraceDelivery.lean) measures
the exact final compact JSON bytes. Synchronous generation selects full inline
delivery when it fits. Otherwise, paths-only success requires a shared-filesystem
scope, durable paths that survive cleanup, and a fitting path-only message.
If those conditions fail, the result is a bounded `TRACE_RESULT_TOO_LARGE` error.
Async trace results support full inline delivery or a bounded terminal
infrastructure error; repeated retrieval does not regenerate the traces.

Stdio declares shared-filesystem scope. Network transports default to remote
scope. Explicit `--shared-trace-root` configuration plus an allowlisted mTLS
client enables the synchronous shared-filesystem path, implemented by
[`Shell.SharedTrace`](../Shell/SharedTrace.lean) and the CLI session wrapper.
That configured shared-delivery path rejects async destinations. Generation
reads/copies outputs before owned-directory cleanup through
[`Shell.Apalache.TraceGeneration`](../Shell/Apalache/TraceGeneration.lean).

[`Shell.TraceCapture`](../Shell/TraceCapture.lean) implements the remote
`trace-gen` client. It retains raw ITF JSON, the request, reply lines, captured
source text and a receipt containing file hashes in a new local output directory.
Returned server paths are not ordinary local filenames; reading shared results
requires an explicit server-root/local-root mapping. Capture records the inputs
and replies of that operation; release qualification additionally requires the
identity and evidence links described below.

## 3. Pure domains and theorems

### Values, traces and differences

[`Core.Value`](../Core/Value.lean) represents arbitrary-precision integers,
booleans, strings, sets, sequences, tuples, records, string/integer function maps,
variants, unserializable values and null. Sets retain a list representation but
use extensional equality: duplicates and order do not change set membership.
`ValueMap` is an association list. Entry-wise mutual containment is an equivalence
on arbitrary lists and agrees with lookup equality under distinct-key premises.
Callers use `valEq`; structural list equality is not the value-domain relation.

`filterMeta` removes top-level comparison metadata: keys beginning with `#`,
`action_taken`, and `parameters`. Ordinary nested record keys retain their
meaning. Integer-key maps are distinct from string-key maps; the existing path
vocabulary represents an integer-map difference as an atomic map-level mismatch.
The [WriteSentry extension contract](model-interface-compiler/writesentry-extensions.md)
records these additive value and target capabilities.

[`Core.Trace`](../Core/Trace.lean) defines ITF traces and `traceSteps`.
`applyParamVars` combines recorded and configured parameter names in stable,
deduplicated order and uses that same effective list for metadata and state
partitioning. Its lookup-losslessness theorem requires `ResplitKeyInv`; keys
outside the declared partition can be dropped. Other theorems cover
idempotence, disjointness, step length/order and the injected action name.

[`Core.Diff`](../Core/Diff.lean) compares filtered state with fuel-bounded
recursion and ordered hints. The depth budget is 8; the hint cap preserves the
first 50 hints and adds a truncation marker when needed. Soundness/completeness
have duplicate-key and well-formed-value premises stated in the theorems.
Cap and path-validity laws are separate. Historical Haskell differential counts
are recorded in the [initial review](final-review.md); they are not a current
test result for the extended value domain.

### Protocol, jobs and resources

[`Core.Protocol`](../Core/Protocol.lean) has a phase-indexed `Session p` and a
pure transition returning either an ordering error or the next phase, session
and abstract output tags. Invalid messages remain representable: for example,
`reportState` in `idle` is rejected by `step`. Payloads are reduced to the
admission, comparison-match and final-step facts the control machine needs.

`step_refines_tla` relates successful calls to the Lean-encoded `TlaStep` relation,
including explicit extension steps. Output and phase theorems constrain that
pure machine. They do not mechanically prove that arbitrary shell IO follows
the relation or that every later edit to the TLA+ file matches the Lean encoding.
The async resource model is a separate projection, not the old synchronous
phase machine imposed on the multiplexed server.

[`Core.Jobs`](../Core/Jobs.lean) proves terminal-state absorption, stored/unknown
ID behavior, validation outcome congruence and the allowed validation bound.
[`Core.AsyncResources`](../Core/AsyncResources.lean) supplies executable checked
resource/cancellation machines and admission/lookup/eviction primitives used
by the shell. Successful checked states carry erased reachability proofs.
[`Core.AsyncOwnership`](../Core/AsyncOwnership.lean) proves global composition
for arbitrary finite populations and histories; it is not a production shadow
table. Successful OS cleanup and eventual task progress remain assumptions of
the correspondence, and no whole-shell liveness proof is claimed.

[`Core.Resource`](../Core/Resource.lean) separately models lifecycle state and
owned/borrowed provenance. Its pure `use` operation requires evidence that the
resource is live, and its threaded operations have cleanup laws. Those laws do
not impose linear ownership on copied host handles; the effectful owner must
maintain real liveness.

### Codecs and model-interface rules

[`Codec.Json`](../Codec/Json.lean) implements the concrete wire/value codec and
its round-trip theorem families. Frozen field defaults, constructor shapes and
absent-versus-null distinctions remain part of the wire contract.
[`Codec.Bridge`](../Codec/Bridge.lean) proves mappings between payload-bearing
wire constructors and abstract protocol tags; it does not prove shell dispatch.
Explorer, Consul, strict JSON and model-interface codecs have their own stated
domains, bounds and laws.

[`Core.ModelInterface`](../Core/ModelInterface.lean) and its submodules own the
structural IR, deterministic resolution, comparison coverage, trace preflight,
semantic/provenance identity and negotiation policy. Their theorems concern
these functions and premises. They do not establish that arbitrary evidence is
true of a TLA+ model or that an application's observer reports honest state.

## 4. TLA+ frontend, compiler and descriptor service

[`Core.Tla`](../Core/Tla/) owns source normalization, tokens, lossless concrete
syntax, AST parsing, names, levels, graph representations and elaboration.
[`Shell.Tla`](../Shell/Tla/) owns bounded source providers and module graph
capture. Borrowed sibling-file and closed inline-map providers identify source
units by normalized source bytes, rather than a reprinted syntax tree.
`Frontend.analyze` resolves one captured graph, then elaborates
declarations, `EXTENDS` visibility, `INSTANCE` substitutions, arities and
expression levels. The active language/parser identity is
`mirrors-tla-frontend-profile-5`; use the
[language profile](model-interface-compiler/tla-language-profile.md) for its
accepted subset. This is not an evaluator, model checker, arbitrary type
inference engine, PlusCal translator, or TLAPS proof checker.

[`Shell.ModelInterface.Compiler`](../Shell/ModelInterface/Compiler.lean) consumes
a TLA+ root, companion contract, typed ITF evidence and optional parameter
configuration. It checks module identity and requires evidence variables to
match the frontend's effective variables before partitioning. Pure resolution
produces the semantic descriptor and provenance; the shell canonicalizes them
separately and computes distinct semantic and provenance digests before writing
the lock. Provenance tracks compiler, contract, evidence and source identities;
those locations do not enter the distributable descriptor. `generate` verifies
a lock before invoking an
emitter; `check` re-resolves and compares generated bytes without publishing.

| Implemented target | Generated seam |
| --- | --- |
| `mirrorecma-v1` | Synchronous TypeScript port, native codecs and `StateComputer` binding |
| `mirrorecma-async-v1` | Promise-returning TypeScript port, replay context and async binding |
| `mirrorcpp-v1` | C++23 port, codecs and binding under the version-1 capability profile |
| `mirrorcpp-v2` | Additive C++ typed string/integer maps and supported literal map-key paths |
| `mirrorrust-v1` | Rust port trait, native codecs and fallible binding |
| `mirrorlean-v1` | Lean nominal structural types, typed fallible IO port, checked binding and required-verification SDK registry |

The emitters under [`Shell/ModelInterface/Emit/`](../Shell/ModelInterface/Emit/)
return in-memory file trees; filesystem publication is separate and uses
ownership manifests, locks, staged replacement and rollback. Optional CMake
consumer generation is another publication path. Async `bundle` is a
publication mode over `mirrorecma-async-v1`, adding a trusted suite and native
adapter bridge. `scaffold` creates proposals and `project-trace` emits a
projected trace with a receipt. The additive
[reviewed workflow](model-interface-compiler/reviewed-corpora.md) binds multiple
evidence inputs, explicit review, immutable seal/corpus publication and v2 lock
provenance. Semantic descriptors and ordinary v1 locks keep their existing
meaning. Shared portable type/value/equivalence/path
judgments and recording vectors now execute through generated synchronous and
asynchronous TypeScript, C++, Rust and Lean consumers. The
[Lean target](model-interface-compiler/lean-target.md) and
[shared corpus](../test/fixtures/model-interface/language/README.md) describe
their exact native and test boundaries. See the
[compiler design](model-interface-compiler/design.md),
[suite bundles](model-interface-compiler/suite-bundles.md), and
[generated-interface specification](generated-model-interface-spec.md).

Runtime negotiation distributes an inert semantic descriptor, not generated
executable code or source provenance. It supports verification/descriptor modes,
exact semantic-digest matching, `ifNoneMatch`, and `require`/`prefer` policies.
An exact digest mismatch rejects replay; eligible unavailable, unsupported or
oversized results can fall back only under the documented `prefer` policy. Current
resolution needs an inline contract and evidence; a digest-only contract
reference is not a resolver backend.

[`Shell.ModelInterface.Auth`](../Shell/ModelInterface/Auth.lean) gives local
stdio an explicit principal/scope, plain TCP no model-interface authority, and
allowlisted verified mTLS principals verification authority with descriptor-read
as a separate grant. [`Runtime`](../Shell/ModelInterface/Runtime.lean) and
[`Cache`](../Shell/ModelInterface/Cache.lean) scope cached content by
realm/principal/tenant and resolution inputs. The service independently bounds
descriptor bytes, negative results, single-flight work, per-scope queue admission
and concurrent resolution. The cache re-verifies canonical descriptor content.
See the [runtime distribution contract](model-interface-runtime-distribution-design.md).

## 5. Framework catalog, distribution and evidence

These tools describe, package and qualify framework combinations. They are
separate from per-connection wire negotiation and from application execution.

| Concern | Implemented owners and data flow |
| --- | --- |
| Capability catalog | [`Core.FrameworkCatalog`](../Core/FrameworkCatalog.lean) + [`Codec.FrameworkCatalog`](../Codec/FrameworkCatalog.lean) validate/canonicalize records; [`Shell.FrameworkCatalog`](../Shell/FrameworkCatalog.lean) and [`framework_catalog`](../tools/FrameworkCatalog.lean) load, validate, render and check catalog outputs |
| Selected source identity | [`refresh_identity.py`](../tools/distribution/refresh_identity.py) and [`snapshot_sources.py`](../tools/distribution/snapshot_sources.py) bind selected components and captured source trees |
| Build and installation | [`tools/distribution/`](../tools/distribution/) implements locked cache builds, manifest verification, staged installation/activation, installed-consumer qualification and upgrade checks |
| Durable run evidence | [`tools/evidence/`](../tools/evidence/) collects registered commands, finalizes retained artifacts/envelopes, validates links and verifies stored bytes offline |
| Qualification decisions | The [harness contract](qualification-harness-design.md), command registry and scope records combine required producer results, artifact identity, cleanup and completeness |

The [catalog contract](framework-catalog-contract.md) separates source presence,
source testing, local acceptance, installed-consumer acceptance, hosted CI and
publication. A capability declaration is not an observation; a referenced run
must identify finalized evidence. [`distribution/reference-node/`](../distribution/reference-node/)
separates checked local replay, optional Gate replay and fresh-trace profiles.
The checked profiles do not acquire Java/Apalache as ordinary replay dependencies.
MirrorGate owns sandbox policy, backend admission and physical cleanup; Mirrors
owns model-side execution and comparison. The application owns its adapter and SUT.

Evidence collection preserves the producer's result and tracks cleanup,
completeness and persistence independently. Finalization binds retained bytes;
verification checks those identities rather than accepting a success label or
version string alone. Source tests, an installed run, retained evidence and
release qualification are different claims. Use the
[durable evidence contract](durable-evidence-design.md),
[tool guide](../tools/evidence/README.md), and current
[execution decisions](../Plans/execution-decisions.md) for an actual campaign.
Historical status headers in design handoffs do not override current source
or establish acceptance for another component selection.

## 6. Trusted native and external boundaries

[`Ffi/Tls.lean`](../Ffi/Tls.lean) and [`tls_shim.c`](../Ffi/tls_shim.c) wrap
OpenSSL TLS operations, peer/certificate fingerprints and expiry inspection.
The native boundary fixes TLS to version 1.3 and requires client certificates
on the server; clients verify the server certificate and support an additional
fingerprint pin through the Lean transport.
[`Ffi/Socket.lean`](../Ffi/Socket.lean) and
[`socket_shim.c`](../Ffi/socket_shim.c) wrap sockets, address resolution, signals,
polling, timeouts and platform helpers. Native object finalizers backstop
explicit lifecycle handling; these operations are not proved by the Lean
resource model. Consult [`Ffi/README.md`](../Ffi/README.md) for the boundary and
the [native build design](native-build-design.md) for source/header/compiler and
OpenSSL dependency tracking.

Apalache/JVM, the OS, native libraries and the Lean runtime/compiler remain
outside the domain proof. [`Shell.Registry`](../Shell/Registry.lean) provides
optional Consul registration, heartbeat, deregistration and discovery;
[`Shell.Net.Http`](../Shell/Net/Http.lean) handles its HTTP transport.
The Haskell reference supplies historical compatibility fixtures and
differential oracles, not a proof of current binary interoperability.

## 7. Validation entry points and historical evidence

The executable inventory is defined by [`lakefile.lean`](../lakefile.lean),
not a fixed count in this document. Useful navigation points are:

- `lake build` for the current default libraries and executables;
  [`tools/run-local-no-model-check.sh`](../tools/run-local-no-model-check.sh)
  for the coordinator's explicit build/unit/codec/compiler/distribution/evidence
  gates and printed live-tier exclusions.
- `lake test` for the repository aggregate definition. It rebuilds, invokes
  model-checking tiers and can discover a developer-local Apalache fallback.
  An unset `APALACHE_MC` alone does not make it a non-model-checking run. On the
  remote-only coordinator, use the preceding local runner instead.
- The [evidence tool guide](../tools/evidence/README.md) and
  [`run_remote_model_check.py`](../tools/evidence/run_remote_model_check.py)
  for the deployed-service tier. Pair verdicts with the exact service/toolchain
  observation required by the qualification harness; do not substitute local
  Apalache/TLC execution.
- [`tools/interop/INTEROP.md`](../tools/interop/INTEROP.md) for cross-client
  commands and prerequisites, and the [client coverage map](client-test-coverage.md)
  for companion async/application gates. Base wire interop does not establish
  Gate backend acceptance.
- [`tools/tla-differential/qualification.md`](../tools/tla-differential/qualification.md)
  for frontend oracle comparisons, and
  [`tools/check-native-rebuild.sh`](../tools/check-native-rebuild.sh) for changes
  to the native build dependency graph.

The [initial final review](final-review.md) is explicitly tied to commit
`5734c12`; the [TLS review](tls-ffi-review.md) preserves the historical t25/t26
findings and re-review. Worker-pool, frontend and application ledgers record
their own dates and exercised tiers. Their fixture counts, pass counts, proof
audits, installed binaries and platform observations are not fresh certification
of this source map. Report required skips, failed gates and unexercised tiers
when presenting any new result.
