# Application integration implementation plan

Status: **P00–P12 implemented and accepted locally, 2026-09-16–17.**
P12 includes three actual restricted authors and an explicitly automated
fresh-evaluator onboarding study; it does not claim a human usability study.
See the [execution record](application-integration-progress.md) for current
acceptance evidence and outstanding gates.
Prepared on 2026-09-16 against the current working checkouts. This plan implements
the [application integration design](application-integration-design.md), preserving
its ownership, lifetime, compatibility and disclosure requirements. It does not
authorize publication or claim that the proposed interfaces are available.

## 1. Establish the actual starting point

| Repository | Inspected HEAD | Reusable implementation | Missing delivery |
| --- | --- | --- | --- |
| Mirrors | `60ed1a62b654ab63c56a117492908c281aca2540` | Verified semantic locks, async target, public manifests, conservative publication/check, corpus preflight | Bundle publication, model handle, native local bridge |
| MirrorECMA | `76ccec0fa1d349fc175f425b993766558cf0bae3` | Compiled negotiated async replay, deferred factories, reports, generic provider seam | Suite definition/runner, authoritative acceptance evidence, pure acceptance evaluation, normalized results, project tools |
| MirrorGate | `67e70b92077df8751968bc242a48139f211010b4` | Recursive native codecs, restricted preparation/workers, managed workflow, public projections | Public kit, standard Node preparation/environment interface, suite convenience, reusable safe receipt persistence |

These are source-inspection findings, not fresh test results. Four discrepancies
must be resolved before accepting the implementation baseline:

- The design cites MirrorECMA `008234d`; that object is unavailable in this local
  repository. The current checkout lacks `examples/application-validation/`.
  Gate's application runner imports that directory and therefore cannot currently
  reproduce the documented three-application matrices.
- The design's earlier AIT-00/AIT-05 status is historical. No suite acceptance
  implementation was found in this MirrorECMA checkout. Reconcile the intended
  revision and inspect any recovered work before assigning new implementation.
- `Docs/application-integration-contracts.md` and
  `Docs/application-integration-tasks.md` are already deleted in the working tree.
  Preserve those user changes; this plan does not restore them or rely on their
  historical contents as an available contract.
- Existing packed-consumer checks establish useful package boundaries, but still
  read model/corpus paths or build tools from checkouts. They do not yet prove the
  design's independent, relocated, prepared-offline consumer requirement.

Baseline reconciliation means locating the intended source and evidence, selecting
compatible revisions, and recording provenance. Do not switch branches, discard
local changes, recreate historical evidence, or label unavailable matrices passed.
If the missing application work cannot be recovered, explicitly schedule its
reconstruction and establish new baseline evidence before migration acceptance.
Framework work can proceed once its contracts are settled; missing historical
applications block preservation claims and final migration acceptance.

## 2. Contract decisions to settle first

Keep the design's decisions. Resolve the following concrete interface details in
the owning repositories, backed by typechecked consumer fixtures and schema
vectors. The proposed filenames below are implementation locations, not existing
public APIs.

| Decision | Proposed implementation direction | Required contract evidence |
| --- | --- | --- |
| Compiler/runtime seam | MirrorECMA exports `SuiteModel`, `defineSuite`, `runSuite`, `runSuiteWithFactory`, and `evaluateAcceptance`; compiler companion imports only the required public runtime surface | Minimal generated Counter consumer compiles; imports are inert; exact registry identity is derived |
| Bundle CLI and ownership | Add `bundle` as publication mode over `mirrorecma-async-v1`, with explicit generation and read-only freshness grammar; use a separate `mirrors.suite-bundle/v1` owned-file manifest | Specify required lock/source/contract/evidence inputs, hash coverage, stale-file deletion and collision handling; preserve existing manifest parsing |
| Native representations | Version the public Node representation independently; retain existing array-shaped generated ports | Shared positive/negative vectors for the complete supported subset, consumed by both local bridge and Gate |
| Execution evidence | Use a suite-specific strict collector in existing replay; commit a pending observation only on its corresponding `step_ok` | Initialization/final-state acknowledgements, trace completion, alias mapping and missing/duplicate acknowledgement fixtures |
| Acceptance bounds | Specify maximum required actions/pairs and exact counter representation/overflow behavior | Limits never truncate required evidence; diagnostic truncation cannot affect an acceptance decision |
| Lifetime | Define one transferred disposer, a scoped construction helper, an independent bounded cleanup default and explicit connection ownership | Late factory/action/disposal state table; local quiescence and Gate physical cleanup remain distinct |
| Results | Freeze additive result/evidence schemas and outcome precedence, preserving old report schemas | Table-driven mismatch, coverage-unmet, evidence-loss, cancellation, timeout and cleanup combinations |
| Gate environment | Prefer a new hosting capability plus a versioned `public_contract` response envelope; derive it from admitted policy | Old clients reject/decline unsupported capability; existing public-task/v1 closed records and worker frames remain unchanged |
| Project/CLI discovery | Freeze the complete project schema listed in P10, including trusted generated-model and deferred local adapter module/export references | One round-trip fixture serves init/loadProject/generate/check/replay; loader/doctor never import adapters and replay imports only after match |
| Toolchain identity | Separate compiler, server, client, Gate and optional generation tools; define explicit override → lock → installed registry selection | Incompatible override fails; offline and remote-server configurations have honest identities and path semantics |

Do not insert bundle hash fields into the current closed compiler ownership
manifest. Avoid self-referential content hashing: define hashes of owned payload
files and canonical metadata separately. Existing target identity and semantic
digest remain unchanged.

One compatibility correction is necessary: current TypeScript lowering rejects
ordinary `__proto__` record keys before async emission. Supporting the design's
required vector needs safe record handling in that existing path as well as in
the companion. Preserve established generated golden bytes; extend support only
with focused cases demonstrating safe construction and lookup.

## 3. Work packages and dependencies

Each package should be a reviewable change with its own evidence. Use the IDs
below for coordination, without carrying forward the unavailable AIT ledger's
completion claims. A dependency means accepted interfaces or behavior are needed;
test design and isolated implementation may begin against agreed fixtures earlier.

| ID | Owner and deliverable | Depends on | Design slices |
| --- | --- | --- | --- |
| P00 | Coordinator: reconcile revisions, prior work and application baseline | None | All |
| P01 | All owners: contracts, compatibility fixtures, shared native vectors | P00 inventory | I0 |
| P02 | Mirrors: bundle, native bridge, publication and check | P01 | I1 |
| P03 | MirrorECMA: immutable suite definition and pure acceptance | P01 | I3 |
| P04 | MirrorECMA: authoritative replay evidence and lifetime support | P01 | I3 |
| P05 | MirrorECMA: suite runner and normalized result | P02–P04 | I3 |
| P06 | Gate SDK: public Node adapter kit | P01; existing public manifest | I2 |
| P07 | Gate supervisor/SDKs: Node profile and negotiated environment | P01 | I4 |
| P08 | Gate integration: safe receipt writer | P01 result contract | I5 |
| P09 | Gate integration: `evaluateSuite` and original-owner cleanup | P05–P08 | I5 |
| P10 | MirrorECMA tools: project loader, commands and doctor; Gate probe | P02–P09 for full acceptance | I6 |
| P11 | All owners: independent installed/offline acceptance | P02–P10 | I1–I6 |
| P12 | Application owners: migration, retained matrices and onboarding study | P00 recovered baseline, P11 | I7 |

The main local path is P01 → P02/P03/P04 → P05. Gate kit/profile work and the
receipt writer can proceed alongside it. Gate acceptance joins those paths at
P09. Project schema/resolver work can start after P01; its full command acceptance
waits for the real components. Run an initial Gate-free packed suite at P05 rather
than postponing packaging problems until P11.

### P00 — Reconcile source and evidence

Record the three revisions, dirty paths, supported toolchain and baseline gate
commands. Locate the missing application suite and any earlier integration work
without overwriting the current checkouts. Recover the nine WorkQueue, four
transfer and four lease behavioral cases plus the 23 Gate source/control cases
and their expected first mismatch coordinates. Keep the evaluator/model/corpus
fixed while establishing baseline behavior.

Acceptance: a compatible source inventory identifies available, missing and
historical evidence separately. The three application commands resolve real
source before anyone claims the old matrices were retained. Update stale design
status references as part of reconciliation, preserving the deleted files.

### P01 — Establish executable contracts

Produce public type declarations/schema fixtures for section 2, an explicit
lifetime/result table, and shared representation vectors. Keep private descriptor
and provenance fixtures separate from public manifest/vector material. Choose
one versioned vector source with pinned/hash-checked copies where needed; do not
make local MirrorECMA depend on Gate to obtain runtime codecs.

Acceptance: a minimal trusted model handle and fake generic provider typecheck
through the intended public APIs; schema negatives fail closed; every unresolved
field/command spelling has an owning task. Contract tests do not count as runtime
acceptance.

### P02 — Generate and publish the trusted bundle

Touchpoints: [compiler](../Shell/ModelInterface/Compiler.lean),
[async emitter](../Shell/ModelInterface/Emit/TypeScriptAsync.lean),
[shared TypeScript lowering](../Shell/ModelInterface/Emit/TypeScript.lean),
[CLI](../tools/ModelInterfaceGen.lean), and a new companion emitter under
`Shell/ModelInterface/Emit/`.

1. Reuse `loadVerifiedLock`, target emission and sanitized manifest rendering.
   Emit unchanged async files, `<Model>.suite.ts`, canonical descriptor/public
   manifest data and versioned bundle metadata. Derive target/digest/contract
   identity; do not expose independent caller overrides.
2. Emit the native bridge from resolved type shapes. Validate all operation
   inputs before invoking the handler and the complete observation before
   returning state. Cover nested collections, semantic duplicates, exact tuples,
   declared variants, bigints, closed records and ordinary special keys. Reject
   unsupported maps/opaque shapes before adapter construction or import.
3. Extend conservative publication with separate bundle ownership, deterministic
   hashing, manifest-last publication, rollback, locking and read-only checking.
   Never overwrite unowned files or accept a scaffold as a sealed contract.
4. Transfer disposal at the companion/factory seam; retain old binding types and
   generated coverage semantics. The generic Gate binding path bypasses the local
   native bridge, so values are converted exactly once.

Acceptance: deterministic generation/regeneration; freshness failure without
repair; safe handling of collisions, symlinks, stale manifests and interrupted
publication; existing sync/async/C++ goldens unchanged; generated code typechecks
against the public API and executes shared vectors. Add the focused compiler
suite and freshness gate to `lakefile.lean`.

### P03 — Define suites and pure acceptance

Add separate MirrorECMA modules, such as `src/suite-definition.ts` and
`src/acceptance.ts`, exported through `src/index.ts`. A suite snapshots inert
inputs and trusted generated functions without connections, timers, factories
running, mutable registries or accumulated evidence.

Reject empty corpus declarations, unknown/initializer requirement IDs, malformed
requirements and identity mismatches. Preserve ordered trace occurrences and
intentional repetition. File existence/hash/preflight checks belong in the
explicit I/O phase before factory construction, not inside the pure definition.
Validate requirement IDs against stable transition IDs, never guessed wire names.

Acceptance: pure tests distinguish met, proven unmet, incomplete and not evaluated;
empty requirements still require full matched replay; original-input mutation
cannot change a defined suite; multiple runs share no counters; required counters
survive diagnostic truncation. No Gate import or second model comparator appears.

### P04 — Collect matched evidence and join lifetimes

Touchpoints: MirrorECMA `src/replay-core.ts`, `src/negotiated.ts`,
`src/async-replay.ts`, `src/adapter-registry.ts` and focused replay/lifecycle tests.
Keep the existing recorder/report behavior compatible.

Add an internal opt-in evidence collector to the existing compiled replay path.
Retain one pending initialization/transition when reporting state; record its
acceptance only on the associated `step_ok`. Current Mirrors emits this reply
for every matched state, including the final state
([server source](../Shell/Mirror/Session.lean)). `all_steps_done` completes the
selected corpus only after all expected occurrences and acknowledgements.
Validate ordering and occurrence counts. Reset pair adjacency at each trace;
map labels/aliases through the validated immutable descriptor. Missing,
duplicate or uncorrelated acknowledgements produce an evidence failure.

Generated binding counters and `ReplayRecorder.reported()` are not acceptance
evidence. Existing recorder inference at a subsequent state or terminal message
remains legacy behavior, not a source of manufactured strict matched counts.
Retain completed-prefix evidence on failure as well as success.

Add suite-capable lifecycle support to join a late factory result and its
disposal within an independent cleanup budget. Existing fire-and-forget late
disposal is insufficient. Track unfinished operations/quiescence, use a scoped
construction helper for registered partial resources, seal further operations
on failure, and prevent retries or late reports. Preserve low-level public
exception behavior/defaults through internal opt-in support or an additive seam.

Acceptance: tests cover explicit final acknowledgement, malformed sequences,
unknown aliases, multi-trace resets, diagnostic truncation, late factory
resolve/reject/hang, partial allocation, operation/observer cancellation, failed
or stalled disposal, and primary-plus-cleanup failures. A never-settling local
operation cannot receive confirmed quiescence merely because disposal returned.
Local deadlines remain cooperative: a blocked JavaScript event loop cannot be
preempted by its own timer. Test hard termination of CPU-bound work through Gate.
Exercise acknowledgement collection against real Mirrors, not only mock streams.

### P05 — Compose the suite runner and results

Add `src/suite-runner.ts` and `src/suite-result.ts`. Compose P03/P04 with the
generated handle through existing exact negotiated compiled replay. Validate
bundle/corpus provenance and preflight before application acquisition; perform
required match before importing/constructing a local implementation or acquiring
an evaluation worker. Invoke the factory at most once per run and initialize
the returned SUT for every selected trace.

Expose `runSuite` for the local bridge and `runSuiteWithFactory` for existing
generic providers. The local factory receives public lifetime controls; matched
authority remains at the trusted provider seam. Invoke the transferred disposer
once, without separately duck-typing and invoking `port.dispose` or provider
`close`. Close owned per-run evaluation connections; never terminate an existing
server merely because its evaluation connection ends.

Return ordinary operational failures after bounded cleanup. Keep conformance,
acceptance, local disposal, raw trusted evidence and overall outcome separate.
Use zero-based trace/state coordinates with initialization at state zero, retain
raw coordinates, and classify by structured stage/source. A matched but
under-covered replay is `failed` / `acceptance.coverage_unmet`; a mismatch remains
a mismatch with incomplete acceptance. Cleanup failure prevents overall success.

Acceptance: public-interface tests verify zero factory/observer/worker calls on
denial, deferred module import, independent repeated runs, exact disposal count,
one factory across repeated traces, result precedence and coordinate conversion.
Normalize primitive, cyclic and throwing rejection values without invoking
arbitrary getters; retain a bounded unknown classification when their source is
untrusted or unrecognized. Test this directly on suite results, before receipt
serialization, and retain private diagnostics only in trusted evidence.
Run a generated Counter and an initial Gate-free installed consumer before P09.

### P06 — Generate the public Node adapter kit

Build on Gate's validated public manifest and existing
[`sdk/node/public-model.mjs`](../../MirrorGate/sdk/node/public-model.mjs).
Add kit generation/check entry points and declarations without importing a
descriptor, raw semantic lock or evaluator module.
Reuse `sdk/node/protocol.mjs` validation and extend
`tests/integration/native-values.test.mjs` with the shared executable corpus.

Generate `adapter.d.ts`, public `port.json`, structural `check-adapter.mjs` and
versioned ownership hashes. Seed `adapter.mjs` and separately approved behavior
prose only when absent. Use exact stable IDs as safe string keys, explicit
unimplemented stubs and native representations. Check staleness without changing
authored files. Structural checks exercise import/handler/observer/reset/codec
contracts and explicitly selected disposal, without claiming business correctness.

Acceptance: typechecked skeleton; all recursive vectors and malformed-manifest
negatives; regeneration preserves author edits; disclosure snapshots exclude
private model paths/names, aliases, projections, traces, expected values and
credentials. Actual submitted imports/self-tests run only in the approved
development sandbox; local execution is an explicit trusted-developer choice.

### P07 — Add the Node profile and public environment

Implement operator-approved `node-esm/v1` preparation using Gate's existing
policy, source-view, preparation and worker lifecycle machinery. Copy approved
source selection into an immutable artifact; use a declared entry point and
pinned runtime/dependency roots. No package installation, lifecycle scripts,
adapter imports or model operations occur in trusted preparation.
Primary touchpoints are `supervisor/mirrorgate/control_policy.py`,
`preparation.py`, `artifacts.py`, `source_view.py`, `policy.py` and `sandbox.py`.

Reject dependency/root escapes, external symlinks and missing capabilities;
record source/dependency/runtime/artifact identities. Keep custom builds
separately selected. Admit the public environment from policy and deliver it
automatically through the negotiated hosting interface. Include only logical
paths, writable areas, entry expectations, public tools and advertised limits.
Use `authoring_broker.py`/`agent_runtime.py` for delivery, with capability/schema
changes in `control_protocol_v2.py` and `sdk/node/control-v2.*` as required.
Update affected codecs, declarations and fixtures together. Revise C++ codecs
only if their wire records change; otherwise regression-test their unchanged
strict parsing. Do not silently widen control v1, worker v1 or public-task records.

Acceptance: real Bubblewrap tests enforce allowed writes and deny oracle reads,
root/dependency escape and malicious environment requests. A fresh author can
build the Node skeleton without application-specific mount prose. Older hosts
cannot advertise the new capability; backend admission failure cannot fall back
to unrestricted execution.

### P08 — Persist receipts safely

Add a Gate-integration-owned receipt module, separate from model/replay code.
Use a validated destination parent, owner-only temporary file, bounded cycle-safe
serialization, and exclusive atomic publication that does not overwrite or
follow symlinks. Both temporary and published receipt files must retain POSIX
mode `0600`. Clean temporary files on every failure. Do not use a
check-then-overwriting-rename sequence as exclusive creation.

Acceptance: existing destination/symlink/invalid parent, unwritable destination,
concurrent writers, interrupted writes, cyclic/primitive/throwing rejection
values, size bounds, final-file permissions and temporary-file cleanup.
Readers see a complete record
or no published record. Receipt failure preserves model/acceptance/cleanup
outcomes and is a separate persistence failure. Existing receipt schemas remain
unchanged; combined evidence uses its own versioned envelope.

### P09 — Run a suite through the Gate-owned workflow

Extend `mirrorgate-mirrorecma` around existing `evaluateImplementation` and
prepared provider interfaces. `evaluateSuite` derives the descriptor/binding
adapter from the trusted bundle, selects approved environment/submission
references and passes the provider to `runSuiteWithFactory`.
Touchpoints are `src/workflow.ts`, `src/provider.ts`, `src/sandbox-model.ts`,
`src/receipt.ts` and the corresponding workflow/provider/receipt tests.

Preserve the normalized suite assessment across the existing compiled-report
seam: `coverage_unmet` must not become a pass because replay completed. Retain
that assessment through an additive internal workflow outcome path, preserving
legacy callers/receipt schemas rather than returning only `SuiteResult.rawReport`.
Thread the independent cleanup budget through provider and owner cleanup;
their existing `receiveMs` budget is not the new suite contract, and operator
limits must never be widened. Retain the original control owner through
managed-host handoff and final session/process
cleanup, even when negotiation prevented worker/factory creation. Support the
in-process owned context without session adoption or a second owner. Gate joins
physical cleanup and then persists P08 receipts. Public output uses the existing
allowlist, never arbitrary normalized result or exception serialization.

Acceptance: same suite and requirements through local and Gate providers;
matched-but-unmet coverage stays failed; denial has zero worker launches but
still cleans the prepared session; worker crash, CPU-bound hang, cancellation,
binding disposal failure, physical cleanup failure and receipt-write failure
retain independent evidence. Real worker vectors agree with the local bridge.
Inject cancellation during authoring, preparation, negotiation, construction,
replay and disposal, with cleanup using a fresh budget after replay is aborted.
Public projection tests exclude hostile rejection text and private coordinates,
names and expected states even when the trusted suite result retains them.

### P10 — Supply installed project tooling

Add optional MirrorECMA project/development modules, the `mirrorecma/project`
entry point, CLI `bin`, and package/declaration/build coverage. Preserve existing
root and supported subpath consumers when introducing an exports map; cover
alternate packaging such as Bazel if affected.

Freeze `mirror.project.json` fields for schema/version, suite ID, model
source/contract/evidence references, target, generated directories, generated-model
module/export, deferred local adapter module/export, replay configuration and
corpus/provenance references, acceptance requirements, execution timeouts and
toolchain-lock reference. Gate environment references remain Gate-tooling input.
Use one complete round-trip project fixture across init, loadProject, generate,
check and replay so commands cannot acquire incompatible implicit configuration.

Implement strict project parsing and project-relative resolution first, then
`loadProject`, `doctor`, `check`, `generate`, `init` and `replay`, all using the
same suite/acceptance validators. `init` does not overwrite authored input;
`generate` explicitly calls the compiler for reviewed inputs; `check` never
repairs; replay never generates a missing corpus. Specify an explicit separate
fresh-witness operation and provenance before exposing it, preserving existing
generation workflows until that interface is ready.

Enforce approved tool selection and identity/capabilities. Ordinary checked
local replay requires neither Java nor Apalache. Remote mode records server
capabilities and preserves existing inline/server-visible path semantics without
implicit private uploads. Installation/download is a separate preparation step.
Gate tooling owns environment references and the optional bounded backend probe.
Doctor separates configuration, executable compatibility, namespace admission
and hosted-agent audit freshness; it neither imports adapters nor starts agents.

Acceptance: cwd independence, relocated config, malformed/unknown fields, stale
hashes, incompatible explicit override, missing offline tools, remote references,
no hidden sibling/PATH/network fallback, and no loader/doctor side effects. New
CLI statuses are 0 for full success, 1 for mismatch with satisfied cleanup and
2 for other non-success, including requested receipt persistence failure.

### P11 — Prove installed and offline execution

Extend the existing package-boundary and Gate packed/workflow harnesses. Prepare
packages, declared dependencies and tools once. Put the model, checked corpus,
compiled bundle, adapter and project into a consumer directory outside all
framework checkouts. Deny source-checkout access and clear incidental resolution
paths. Compile application/generated TypeScript during explicit preparation;
the first Gate profile consumes JavaScript.

Run local and Gate consumers, relocate the consumer, then repeat from a prepared
offline installation. Capture subprocess/network activity sufficiently to reject
per-run packing, library compilation, installation, hidden checkout reads or
downloads. No Gate package may be required by the local consumer. Include missing
and incompatible tool failures and malicious package/dependency escape cases.

Acceptance: public package imports, declarations, commands and runtime files all
work from the delivered installation. Existing repository-local test convenience
is not accepted as proof of this gate. Package publication itself stays outside
this plan.

### P12 — Migrate applications and measure onboarding

Migrate WorkQueue first, then persistent transfer, then lease ownership. Keep
domain operations/observers and private evaluator choices in applications. Remove
manual tuple/descriptor construction, shallow collection conversion, report
normalization and control/cleanup loops only after the installed paths pass.
The same suite declaration must serve local and Gate execution.

Re-run all 17 local behavioral mutants and 23 Gate source/control cases, retaining
expected first mismatches and independent cleanup checks. Retain separately
selected fresh-witness generation and run new actual restricted authors against
fixed private evaluators for all three applications. A startup, codec, evidence
or cleanup error is not a behavioral mutant kill. Synthetic hosts and development
agents with private access are not fresh restricted-author evidence.

Publish role-oriented onboarding for model author/evaluator, implementation
author, integrator and operator. Have an evaluator unfamiliar with internals
follow only that guide. Record prerequisites separately, elapsed setup/first
replay, manual configuration steps, handwritten integration code, and diagnosis
time for a seeded defect. Record unavailable measurements as not measured;
do not infer usability improvement from line counts or old local runs.

Acceptance: application/configuration code contains none of the five prohibited
mechanical responsibilities in design section 13; all retained matrices and
fresh-author cases have new evidence; independent onboarding measurements and
remaining limits are published.

## 4. Validation and acceptance record

Run focused gates while implementing each package, then aggregate gates at
integration milestones. Add meaningful new behavioral coverage to the owning
repository's normal gate, using public interfaces wherever practical.

| Repository/tier | Existing entry points to extend or run | Evidence required |
| --- | --- | --- |
| Mirrors focused | `lake build`; `.lake/build/bin/model_interface_spec`; `python3 tools/check-async-emitter.py`; compiler `check`/preflight | Bundle/new-key cases, executable emitted bridge, stable established generated bytes |
| Mirrors aggregate | `lake test` with explicit tool selection | Existing proofs/build/specs and new bundle freshness/gates; list external skips |
| MirrorECMA focused | `pnpm run check`; `pnpm run check:model-interface`; `pnpm run check:examples`; `pnpm run test --runInBand --no-watchman` | New suite/acceptance/evidence/lifetime/project tests plus existing replay behavior |
| MirrorECMA integrated | `MIRRORS_ROOT=<checkout> MIRRORS_REF=<full SHA> bash scripts/ci/check.sh`; separately `--live` with `APALACHE_MC` | Coordinated revision and pinned tools, generated Counter/WorkQueue, package boundary; fresh traces separately recorded |
| Gate aggregate | `bash scripts/test.sh` under its supported pinned toolchain | Python/Node/C++/Rust plus actual required Bubblewrap conformance/lifecycle gates |
| Gate integration | From `integrations/mirrorecma`: `npm run build`, `npm run check`, `npm test`, `npm run test:packed`, `npm run test:sandbox`, `npm run test:workflow`; service workflow separately | New kit/profile/suite/receipt/owner cases and existing installed workflow behavior |
| Applications | Recovered local matrices; Gate `integrations/mirrorecma/scripts/application-program-gate.mjs` and its documented author mode | 17 local mutants, 23 Gate cases, fresh witnesses and real restricted authors |
| Cross-client | Follow [interop prerequisites](../tools/interop/INTEROP.md), then `bash tools/interop/run.sh` | Relevant wire/emitter/client compatibility; explicit live Apalache and external-client prerequisites |

Do not run native rebuild validation unless the native dependency graph changes.
Do not regenerate frozen Haskell fixtures by hand. Use the compiler for generated
artifacts and verify them with check. Full interop and actual sandbox/hosted-agent
acceptance have distinct prerequisites; an unavailable tier is not a pass.

For each accepted package, record implementation revisions, commands, tool
identities, exit status, fixture/corpus identities, evidence location, and any
skipped or blocked checks. Trusted receipts may contain private data; public
evidence uses approved projections. Update cross-repository pins only to actual
compatible commits, following each repository's pin policy.

## 5. Delivery gates and staffing

Use four bounded implementation streams after P01:

- Compiler owner: P02, compiler fixtures and Lake wiring.
- MirrorECMA owner: P03–P05, then P10; owns shared replay files and public exports.
- Gate runtime owner: P06–P07, including affected language SDK/schema fixtures.
- Gate integration owner: P08–P09 and installed Gate consumers, coordinated with
  the runtime owner rather than independently changing the same SDK files.

The coordinator owns P00/P01 consistency, P11 cross-repository evidence and P12
migration order. Split pure acceptance work from replay work only with explicit
file ownership. Review the model-handle contract before compiler/runtime changes
diverge. Each owner reports concrete acceptance evidence and preserves others'
edits; no implementation task includes publication.

The first usable milestone is **a generated Counter bundle running through the
public Gate-free suite API with authoritative acceptance and joined cleanup**.
The second is **that same suite through the approved Node Gate profile with
physical cleanup and safe receipt persistence**. The final gate is **relocated
offline consumers plus migrated application matrices and measured onboarding**.
Documentation, mocks or local example success alone do not close those gates.

The original planning task inspected current sources and dependency seams.
Subsequent implementation results, recovered baseline revisions and remaining
external gates are recorded in the execution record linked above.
