# Mirrors framework map and support

Current source inventory reviewed 2026-09-18. Start application onboarding with
[the integration guide](application-integration-guide.md); use the
[remote server guide](remote-server-guide.md) for deployment and connections.
Source implementation, local acceptance, package publication and machine
installation are separate claims. Dated evidence remains tied to its recorded
revisions, even when a repository advances.

## Repository ownership

| Repository | Responsibility | Entry point |
| --- | --- | --- |
| Mirrors | Lean checker, TLA+ frontend, model-interface compiler, wire contracts and server resource proofs | [README](../README.md), [documentation index](README.md) |
| MirrorECMA | TypeScript client, generated application suites, project CLI, negotiated replay and reports | [README](../../MirrorECMA/README.md), [suite API](../../MirrorECMA/docs/application-suites.md) |
| MirrorCPP | C++23 client and compiled generated bindings | [README](../../MirrorCPP/README.md) |
| MirrorRust | Rust client, async jobs, strict compiled verification and deferred binding registry | [README](../../MirrorRust/README.md) |
| MirrorLean | Lean client, recursive model sources, synchronous replay and typed server async jobs | [README](../../MirrorLean/README.md) |
| MirrorGate | Shared controller, policy, isolation, snapshots, worker lifecycle, native SDKs and optional evaluator integrations | [README](../../MirrorGate/README.md), [SDK/facade selection](../../MirrorGate/docs/client-language-support.md) |
| MirrorRegistry | Optional Consul-compatible discovery library/CLI; not a checker or worker supervisor | [README](../../MirrorRegistry/README.md) |
| MirrorExamples | Counter/RBT examples and retained model/trace corpora | [README](../../MirrorExamples/README.md) |
| ModelMirros | Haskell ModelMirrors reference implementation and historical protocol/deployment material | [README](../../ModelMirros/README.md) |

The executable name `ModelMirrors` can identify different implementations.
Record its implementation, source revision and binary hash rather than inferring
features from the executable name or product version alone. The local Haskell
checkout is named `ModelMirros`; its Cabal package/executable is `ModelMirrors`.

## Generated capability status

<!-- BEGIN GENERATED FRAMEWORK SUPPORT -->
Catalog `mirrors.framework.candidate-2026-09-22` visibility: **private**. Dirty source identities are explicit; this table does not publish packages or assert runtime acceptance.

| Component | Revision | Dirty |
| --- | --- | --- |
| `mirrorecma` | `87ff8ca1555e2e35dd9a4664fc94aaa46d8f3dc2` | true |
| `mirrorgate` | `173075d318e4be926570a1378fc0aa36a1294f89` | true |
| `mirrors` | `e7c8681d7db62000555675188d0125931136e002` | true |

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
| C++ | stdio, TCP, mTLS; submit/query/await/cancel | Generated `mirrorcpp-v1` bindings and exact compiled verification | Native C++ control-v1/v2 SDK and reusable source integration; acceptance fixture, not a published generic suite API |
| Rust | stdio, TCP, mTLS; correlated async jobs | Exact registry, reviewed metadata, required/preferred compiled verification and fallible replay; Mirrors now has a source-level `mirrorrust-v1` emitter, while generic installed-client acceptance remains unestablished | Native Rust control-v1/worker-v1 SDK and optional evaluator; Counter is a handwritten fixture, distinct from generic generated-application acceptance; current facade starts the model peer over local stdio |
| Lean | stdio, TCP, separate native mTLS package; typed `Connection` async jobs | Base protocol; negotiated registry and generated Lean target remain planned | No native Lean Gate facade |

Stdio does not accept server-job messages. Server async jobs, async application
operations, and Gate operations have different owners and cancellation contracts.
See the [client contract](client-implementation-guide.md) before advertising a
profile; base interoperability does not imply generated bindings or a suite API.

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
