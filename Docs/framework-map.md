# Mirrors framework map and support

The [current architecture overview](architecture-overview.md),
[interactive diagram](architecture-overview.html), and
[module map](architecture-details.md) were synchronized against Mirrors `548ba71`
and current linked client sources on 2026-10-09. [Current status](current-status.md)
records exact frozen qualification; the generated catalog block retains its own
selection and observation vocabulary. Older source-review baselines are history.
Start application onboarding with
[the integration guide](application-integration-guide.md); use the
[remote server guide](remote-server-guide.md) for deployment and connections.
Source implementation, local acceptance, package publication and machine
installation are separate claims. Dated evidence remains tied to its recorded
revisions, even when a repository advances.

## Current acceptance and scheduling

[Current status](current-status.md) and [published readiness](../Plans/q3-published-roadmap-2026-10-07.md)
record the qualified `m5-wsl-windows-remote/v1` candidate: 18 commands/16 tiers,
19 linked nodes, 20 independently verified bundles and six rejected controls.
Broader M4, new platform backends and package-publication remain separate.
The table below is a generated declaration snapshot from catalog A, not the later
approval B's observed acceptance; its `unknown` cells do not negate scoped Q1/Q2.
Do not hand-edit that generated block or infer unsupported capability observations.

The compiler implements eight emitters: TypeScript sync, async v1/v2, C++ v1/v2,
Rust v1/v2 and Lean v1. The common portable shared vector gate retains six-profile
scope; additional v2 language/codec/native acceptance is separately bound.
[DPM](deterministic-scheduling.md) supplies declared-checkpoint coordinators and
incremental replay for C++, Node workers and Rust threads. Gate's Node/Rust worker
isolation remains a separate path; no generic generated Rust Gate evaluator or
Lean Gate facade is implied.

The newer [DPM integration kit and receipt timeline](dpm-usability-design.md)
are source accepted for six C++/async-ECMA/Rust kit modes. Their generated
mapping helpers reduce adapter setup; applications retain hooks, observations
and execution ownership. F3 schedule reduction, F4 installed CLI and F5
synchronization wrappers remain approved follow-ons. Current tool revisions
do not inherit the frozen M5 or earlier DPM installed-package qualification.

## Repository ownership

| Repository | Responsibility | Entry point |
| --- | --- | --- |
| Mirrors | Lean checker, bounded TLA+ frontend, model-interface compiler, selected pure proofs, catalog/distribution and qualification tooling | [README](../README.md), [documentation index](README.md) |
| MirrorECMA | TypeScript client, generated application suites, project CLI, negotiated replay and reports | [README](../../MirrorECMA/README.md), [suite API](../../MirrorECMA/docs/application-suites.md) |
| MirrorCPP | C++23 client and compiled generated bindings | [README](../../MirrorCPP/README.md) |
| MirrorRust | Rust client, async jobs, strict compiled verification and deferred binding registry | [README](../../MirrorRust/README.md) |
| MirrorLean | Lean client, recursive model sources, synchronous replay, required compiled verification and typed server async jobs | [README](../../MirrorLean/README.md), [generated target](model-interface-compiler/lean-target.md) |
| MirrorGate | Shared controller, policy, isolation, snapshots, worker lifecycle, native SDKs and optional evaluator integrations | [README](../../MirrorGate/README.md), [SDK/facade selection](../../MirrorGate/docs/client-language-support.md) |
| MirrorRegistry | Optional Consul-compatible discovery library/CLI; not a checker or worker supervisor | Optional checkout; see [discovery](#sources-traces-and-discovery) |
| MirrorExamples | Counter/RBT examples and retained model/trace corpora | Optional checkout; this repository also retains [fixtures](../test/fixtures/) |
| ModelMirrors | Haskell reference implementation and historical protocol/deployment material | [README](../../ModelMirrors/README.md) |

The executable name `ModelMirrors` can identify different implementations.
Record its implementation, source revision and binary hash rather than inferring
features from the executable name or product version alone. The current local
Haskell checkout, Cabal package and executable are named `ModelMirrors`;
older records use the checkout name `ModelMirros`.

## Generated capability status

<!-- BEGIN GENERATED FRAMEWORK SUPPORT -->
Catalog `mirrors.framework.candidate-2026-09-22` visibility: **private**. Dirty source identities are explicit; this table does not publish packages or assert runtime acceptance.

| Component | Revision | Dirty |
| --- | --- | --- |
| `mirrorecma` | `eef6f71f2ff2d22c6e3a83274d150638a010b663` | true |
| `mirrorgate` | `455e196c73332a1b0d85b1d822dfc4aa3542bbd9` | true |
| `mirrors` | `f0894d2c89426278900ba79f2b7a1b9b9c5d6620` | true |

| Capability | Owner | Declared | Source | Tested | Local | Installed | Hosted CI | Published |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `mirrorecma.project.doctor-read-only` | `mirrorecma` | available | present | unknown | unknown | unknown | unknown | unknown |
| `mirrorecma.suite.checked-corpus` | `mirrorecma` | available | present | unknown | unknown | unknown | unknown | unknown |
| `mirrorgate.backend.linux-bubblewrap-v1` | `mirrorgate` | experimental | present | unknown | unknown | unknown | unknown | unknown |
| `mirrorgate.control.v1` | `mirrorgate` | experimental | present | unknown | unknown | unknown | unknown | unknown |
| `mirrorgate.control.v2` | `mirrorgate` | experimental | present | unknown | unknown | unknown | unknown | unknown |
| `mirrorgate.generated-application.mirrorrust-v1` | `mirrorgate` | unavailable | absent | unknown | unknown | unknown | unknown | unknown |
| `mirrorgate.pair.node-evaluator.node-worker-v1` | `mirrorgate` | experimental | present | unknown | unknown | unknown | unknown | unknown |
| `mirrorgate.pair.rust-evaluator.rust-worker-v1` | `mirrorgate` | experimental | present | unknown | unknown | unknown | unknown | unknown |
| `mirrorgate.quota.aggregate-v1` | `mirrorgate` | experimental | present | unknown | unknown | unknown | unknown | unknown |
| `mirrorgate.recovery.offline-reclaim-v1` | `mirrorgate` | experimental | present | unknown | unknown | unknown | unknown | unknown |
| `mirrorgate.recovery.session-adoption` | `mirrorgate` | unavailable | absent | unknown | unknown | unknown | unknown | unknown |
| `mirrorgate.runtime.node-v1` | `mirrorgate` | experimental | present | unknown | unknown | unknown | unknown | unknown |
| `mirrorgate.runtime.rust-v1` | `mirrorgate` | experimental | present | unknown | unknown | unknown | unknown | unknown |
| `mirrorgate.rust-evaluator.counter-fixture-v1` | `mirrorgate` | experimental | present | unknown | unknown | unknown | unknown | unknown |
| `mirrorgate.worker.v1` | `mirrorgate` | experimental | present | unknown | unknown | unknown | unknown | unknown |
| `mirrors.compiler.target.mirrorcpp-v1` | `mirrors` | available | present | unknown | unknown | unknown | unknown | unknown |
| `mirrors.compiler.target.mirrorecma-async-v1` | `mirrors` | available | present | unknown | unknown | unknown | unknown | unknown |
| `mirrors.compiler.target.mirrorecma-v1` | `mirrors` | available | present | unknown | unknown | unknown | unknown | unknown |
| `mirrors.compiler.target.mirrorrust-v1` | `mirrors` | experimental | present | unknown | unknown | unknown | unknown | unknown |
<!-- END GENERATED FRAMEWORK SUPPORT -->

## Client capabilities

| Client | Base transport / server jobs | Model-interface path | Gate evaluator path |
| --- | --- | --- | --- |
| TypeScript | stdio, TCP, mTLS; network async jobs through `Connection` | Generated synchronous/async bindings; compiled verification and dynamic descriptors; default `defineSuite` / `runSuite` and project CLI | Gate-owned `evaluateSuite`; native Node control-v1/v2 SDK |
| C++ | stdio, TCP, mTLS; submit/query/await/cancel | Generated `mirrorcpp-v1/v2` bindings and exact compiled verification | Native C++ control-v1/v2 SDK and reusable source integration; acceptance fixture, not a published generic suite API |
| Rust | stdio, TCP, mTLS; correlated async jobs | Generated `mirrorrust-v1/v2` bindings, exact registry, required/preferred compiled verification and fallible replay; shared vectors and bounded source-hidden generated-Counter offline/mTLS acceptance | Native Rust control-v1/worker-v1 SDK and optional evaluator; Counter is a handwritten fixture, distinct from generic generated-application acceptance; current facade starts the model peer over local stdio |
| Lean | stdio, TCP, separate native mTLS package; typed `Connection` async jobs | Generated `mirrorlean-v1` bindings and additive required-only compiled registry sharing legacy replay; shared vectors and bounded source-hidden generated-Counter offline/mTLS acceptance | No native Lean Gate facade |

Stdio does not accept server-job messages. Server async jobs, async application
operations, and Gate operations have different owners and cancellation contracts.
See the [client contract](client-implementation-guide.md) before advertising a
profile; base interoperability does not imply generated bindings or a suite API.

The [shared conformance gate](../tools/model-interface-conformance/check.py)
executes six generated profiles. The [interop guide](../tools/interop/INTEROP.md)
defines the bounded Rust/Lean generated-Counter matrix separately from the legacy
all-transport matrix and recorded framework M5 qualification. Source, native and
transport acceptance do not update catalog release claims automatically; the
generated catalog table above retains its own selected identity.

Gate currently isolates **Node and Rust workers** on **Linux/Bubblewrap**.
Evaluator language and worker language are independent: C++ and Rust evaluators
can each drive either worker. C++/Lean workers and Windows/macOS Gate backends
remain separate work. A Windows Mirrors service supplies model checking, not
Windows Gate isolation. Node is unnecessary for a Rust evaluator using a Rust
worker; Node-worker cases still require the approved Node runtime.

## Sources, traces and discovery

The Lean `ModelMirrors validate --async` CLI sends the recursively resolved local
TLA+ source closure and awaits on its owner connection. Client libraries expose
separate source resolvers and explicit inline-source options; they do not all have
the CLI's `--dep` API. Project suite replay retains explicit server-visible model
and corpus paths and does not automatically upload private inputs. A trace result
must obey the [delivery contract](client-implementation-guide.md#51-trace-generation-result-delivery);
a remote `destPath` is never a local client directory.

Registry discovery locates model servers. mTLS, operator trust/pins and
model-interface authorization remain separate. Gate's local control endpoint is
not a Mirrors JSONL endpoint and is not discovered through MirrorRegistry.

## Validation and evidence

- [Client coverage](client-test-coverage.md) and [interop commands](../tools/interop/INTEROP.md): actual scopes, required live dependencies and client SHA overrides.
- [Server resource E2E](async-server-resource-e2e.md): concurrent mTLS validation and bounded resource/RSS recovery on Linux; not a universal heap-leak proof.
- [Lean resource proofs](async-resource-lean-proofs.md): precise pure-model and effectful-runtime boundary.
- [Rust Gate acceptance](../../MirrorGate/docs/rust-evaluator-sdk-status.md): 20 Rust rows and comparison with C++/TypeScript reference outcomes, plus packaging and failure tests.
- [Application acceptance](application-integration-progress.md): dated Node suite/application studies, not evidence of equivalent suite tools in every language.
- [Windows deployment record](windows-deployment-20260918.md): dated installed-server identity; source updates do not automatically redeploy it.
