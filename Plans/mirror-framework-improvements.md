# Mirror Framework improvement plan

Date: 2026-09-21

Status (2026-10-03): the selected `m5-wsl-windows-remote/v1` profile is qualified
for post-M6 working-tree C0
`879be4fd92d3c2e1abbb19b0737c620dcf7cea466f6796a4703b75aa5a533c25`.
Broader M4 acceptance remains partial. This roadmap does not itself authorize
new implementation or release actions. [Current readiness](q3-post-m6-2026-10-03.md)
records the exact accepted candidate and limits; later commits and documentation
changes do not automatically inherit its qualification.

Planning baseline: Mirrors `eb5cd00`, MirrorGate `173075d`

Task decomposition and agent assignments: [task index](mirror-framework-tasks.md).

Current topology decision, 2026-10-01: the WSL2 coordinator uses the current
machine's native Windows host as its designated remote oracle, with Apalache
0.62.2 / Microsoft Java 25.0.4+7-LTS. The observed endpoint is
`172.20.208.1:8999`, and Windows artifacts are confined to
`C:\Users\ayden\Desktop\Workspace\MirrorsRemote`. This replaces the earlier
server as the intended execution target. Pin migration is complete; domain materialization, remote checking and
the declared 22-case mTLS interop matrix passed for the frozen candidate;
historical milestone/evidence records below are not relabelled. Gate's separate
Linux delegated-cgroup/native-host capabilities remain unqualified. See
[the execution decision](execution-decisions.md#2026-10-01--current-windows-host-is-the-designated-remote-oracle).

M5 scope revision, 2026-10-01: at the user's request the selected profile is
`m5-wsl-windows-remote/v1`. Native Ubuntu acceptance and aggregate-cgroup
enforcement are removed from M5 requirements. M4's ownership-safe recovery
remains a dependency; its aggregate-limit clause belongs to the separate Linux
scope. WSL-supported installation, isolation/recovery and retained-evidence
checks keep their stated requirements. No excluded capability is counted as
qualified. [Execution plan](m5-wsl-windows-remote.md).

## Objective and scope

Make the framework easier to install, diagnose, and operate while strengthening
the evidence behind its conformance claims. This plan covers six workstreams:

1. Machine-readable compatibility and support information.
2. Reproducible installation and runtime preparation.
3. Failure capture, replay, and minimization.
4. Adapter fidelity and mutation acceptance.
5. Durable verification evidence.
6. Gate recovery and aggregate resource accounting.

The workstream deliverables below retain the original cross-repository roadmap.
The milestone table and linked readiness report distinguish implemented and
qualified scope from remaining capabilities; historical proposed names are
resolved by their owning contracts. Further implementation requires scoped
changes and the specified acceptance evidence. Package publication, production
deployment, and destructive host recovery remain separate operational actions.

## Existing foundations and constraints

The framework already has generated suites, project commands including `doctor`,
local and restricted replay, matched coverage requirements, deliberate application
mutants, installed-consumer tests, and private cleanup-aware receipts. Extend
these mechanisms rather than introducing a competing runner or lifecycle.

Sources for the baseline:

- [Framework ownership and support](../Docs/framework-map.md).
- [Application integration](../Docs/application-integration-guide.md).
- [Application acceptance and onboarding evidence](../Docs/application-integration-progress.md).
- [Versioning and installation](../Docs/versioning.md).
- [MirrorECMA project commands](../../MirrorECMA/docs/project-tools.md).
- [MirrorECMA suite results](../../MirrorECMA/docs/application-suites.md).
- [Gate compatibility and limitations](../../MirrorGate/docs/compatibility.md).
- [Gate evaluation workflow](../../MirrorGate/integrations/mirrorecma/WORKFLOW.md).
- [Gate backend](../../MirrorGate/docs/sandbox/linux-bubblewrap.md).

Preserve these boundaries throughout:

- Mirrors owns model resolution, generation, execution, and comparison.
- Client libraries own negotiated replay and application-facing results.
- Gate owns policy, snapshots, worker admission, physical cleanup, and isolation.
- Evaluators own private models, expected states, acceptance, and disclosure.
- Applications own actual behavior, observations, reset, and external resources.
- Lean proofs cover their stated pure models; shell, native, kernel, and external
  tool behavior require separate evidence.
- Product versions, protocol versions, interface digests, artifact hashes,
  runtime profiles, and private model revisions remain distinct identities.

## Delivery order and ownership

| Milestone | Work | Primary owner | Depends on | Exit condition | Status |
| --- | --- | --- | --- | --- | --- |
| M0 | Baseline inventory and contracts | Mirrors, with each component owner | None | Scope, schemas, failure rules, and supported initial path reviewed | Done: scope, contracts, and baseline reviewed and accepted 2026-09-22 |
| M1 | Compatibility catalog and evidence format | Mirrors catalog; evidence producers in each repo | M0 | Generated support tables and durable evidence exercised together | Done: catalog selection and durable evidence exercised together in the 2026-09-25 pass |
| M2 | Installable reference distribution | Component packaging owners; framework integration in Mirrors | M1 | Fresh isolated consumer completes local and Gate flows | Done for selected WSL2 profile: committed local/Gate installs and source-hidden D audits (`run-3bafa0a2…`, `run-050b159c…`) qualify recorded C0 `879be4fd92d3…`; native Ubuntu acceptance excluded |
| M3 | Failure reproduction and fidelity acceptance | MirrorECMA, Mirrors compiler, Gate integration | M1; use M2 distribution for final acceptance | Reproduction, safe reduction, and mutation controls pass | Done for selected profile: both installed R1 branches reproduced; prefix best 2/16 with complete minimality; LeaseService R5 model-valid and actual reduced-corpus baseline/fault preserves the same signature; local/Gate mutation aggregates 17/17; exact R0/R1/R5 linkage independently verified |
| M4 | Gate interruption recovery | MirrorGate | M1 evidence format | Ownership-safe recovery and aggregate-limit gates pass | Partial overall: recorded-candidate recovery reclaims four owned prepared filesystem resources with confirmed cleanup and exact fresh-origin linkage; this required M5 clause qualifies. Aggregate cgroups and active-process post-restart recovery remain separately unqualified |
| M5 | Release-candidate qualification: `m5-wsl-windows-remote/v1` | All affected owners | M2, M3, M4 ownership-safe recovery | Exact candidate passes this profile's installed/runtime/evidence gates; native Ubuntu and aggregate-cgroup acceptance excluded | Done for `m5-wsl-windows-remote/v1`: post-M6 working-tree C0 `879be4fd92d3…`; all 18 commands/16 tiers, 19-node/two-D scope and 20 bundles independently verified; six controls rejected; [Q3 post-M6](q3-post-m6-2026-10-03.md) |

### Historical milestone updates

These dated notes preserve each earlier candidate's position. Their pending
work and evidence apply to that date and selection; the table above and current
readiness record supersede them as current status.

Updated 2026-09-29: safe-reduction implementation landed on both mains
(MirrorECMA `da18f1a`; Mirrors `abbf70b`, `b19e090`) and every tier requiring a
native Ubuntu host was deferred by operator decision. Qualification statuses
otherwise reflect the 2026-09-27 route-2 rerun on selection
`68a3ad583d2889695e37bbde4af3b81d12b184a8d72e1bb9a360d6266a709c68`; per-tier
evidence and blockers are in [q3-readiness-2026-09-25.md](q3-readiness-2026-09-25.md),
`../CHECKPOINTS.md` (date-flow record), and `/tmp/q1-route2-result.md`. Partial means at least one exit-condition
capability lacks qualified evidence; it is not a pass, and no partial status
qualifies a dependent milestone.

Updated 2026-09-30: the closing sweep finished the locally executable work.
The SR-5a prefix tier is qualified with the strong claim
(`framework.reduction-prefix` `run-dcc51362-9084-4c2d-9eeb-9329bacb8d01`,
`shortest_reproducing_prefix`, `minimalityComplete: true`) under selection
`fed55175b792feaec86cf71bf7fae1bae680a0313797a5c982f3a6ecc746f025`, and Q2
verifies a 16-run scope including the reduction tier. Only SR-5b (domain
reduction) remains on M3, operator-gated on the remote service activation;
remote model check and interop remain unavailable and the native-Ubuntu/cgroup
tiers stay deferred. Per-tier evidence is in
[q3-readiness-2026-09-30.md](q3-readiness-2026-09-30.md) and the
`CHECKPOINTS.md` 2026-09-30 records.

Updated 2026-10-01: separate native-Linux requirements are removed from the
selected M5 profile. The current Windows oracle is admitted and the requested
remote checks passed. The domain result is individually qualified and reproduced
by installed replay, while full linked-scope credit requires the same LeaseService
bundle in a finalized R1. Current results, exact boundaries and remaining
candidate-wide work are in [Windows remote readiness](q3-windows-remote-2026-10-01.md).
Historical Q1/Q2 scopes above do not qualify this new selection.

Updated 2026-10-01 after complete rerun: all five completion items qualify
the exact named WSL2/Windows profile on C0 `f2080fd722ed097eb1d5e4b4fd8cd4e8d7a1d1092b91530d48a51ca3bf141670`.
Both reproduction/reduction branches, fixed mutation aggregates, prepared-snapshot
recovery, source/remote gates and the full independently verified Q1/Q2 graph
pass. Current acceptance is in [completion readiness](q3-m5-complete-2026-10-01.md).
M4's separate aggregate/process claims remain unqualified; only its exercised
ownership-safe filesystem clause is required and credited by this M5 profile.

### Ongoing implementation discipline

Within M1, catalog and evidence work can progress independently after agreeing
on identity fields. M3 and M4 can progress independently. Native-client expansion
follows acceptance of the initial Node suite path; it must not be advertised as
complete merely because a shared schema exists.

Each implementation PR must state its owned files, affected contracts, required
checks, skipped or blocked tiers, and compatibility impact. Read the current
repository guidance before implementation; recheck branch state and companion
SHAs instead of treating the planning baseline as a permanent pin.

## 1. Machine-readable compatibility

### Problem

Support descriptions are duplicated across repositories and can lag code. At the
planning baseline, Mirrors dispatches `mirrorrust-v1` to its Rust emitter, while
the framework map and onboarding guide still describe Rust generation as absent.
Emitter availability alone does not establish installed client or Gate acceptance.

### Deliverables

1. Define a versioned framework catalog schema in Mirrors. Component repositories
   retain ownership of their capability records; a framework catalog references
   exact component revisions and a tested combination.
2. Record compiler targets, client capabilities, control/worker protocols,
   evaluator/worker language combinations, OS/backend constraints, and evidence
   references. Distinguish source implementation, local acceptance, hosted CI,
   installability, and publication as separate fields.
3. Reuse Gate's existing `sdk/compatibility.json` and existing tool/client pins as
   inputs through explicit adapters. Specify which record owns each fact; reject
   contradictory records instead of choosing one implicitly.
4. Generate support tables and a compact JSON report from the catalog. Separate
   generated sections from explanatory prose and historical evidence.
5. Extend project diagnostics to consume the selected catalog and explain an
   incompatible combination. Keep `doctor` read-only; live backend admission
   remains a separately requested operation with cleanup.

### Implementation sequence

- C1: Inventory current identity/capability files and document their owners.
- C2: Specify schema, unknown-field/version behavior, evidence states, and the
  distinction between declared and observed capabilities.
- C3: Implement validation and deterministic documentation generation.
- C4: Migrate current tables, including an explicitly qualified Rust target row.
- C5: Add freshness checks and consumer compatibility diagnostics to CI.

### Acceptance

- Missing revisions, invalid evidence references, and contradictory capabilities
  fail catalog validation with actionable locations.
- Generated tables are deterministic and CI detects manual edits or stale output.
- A source-only feature cannot appear as released or runtime-accepted.
- An incompatible installed combination fails before adapter construction or
  worker acquisition; a supported combination reaches ordinary negotiation.
- Wire negotiation remains authoritative at runtime; catalog approval cannot
  bypass exact interface matching or Gate policy.

## 2. Reproducible installation

### Problem

The source and installed-consumer workflows have substantial acceptance evidence,
but users still need to assemble compatible tools and approved runtimes. Package
versions alone do not identify the actual filesystem trees used by a Gate worker.

### Deliverables

1. A reference distribution recipe for local Node suite replay, plus an optional
   Linux Gate component. Record exact packages, compiler/server artifacts,
   dependencies, hashes, supported host assumptions, and catalog revision.
2. A separate optional fresh-trace generation profile containing its pinned
   Apalache/Java requirements. Checked-corpus replay must not acquire those
   dependencies merely to replay existing traces.
3. A content manifest for admitted runtime trees, including provenance and a
   documented hashing rule. Keep runtime contents separate from kernel and host
   policy evidence; reproducible packaging does not prove backend availability.
4. Staged installation, integrity verification, atomic activation where supported,
   and rollback to the previous installation. Keep private credentials and
   operator policies outside distributed artifacts.
5. A single installation guide that leads to a correct replay, an intentional
   mismatch, and optional restricted replay of the same suite.

### Implementation sequence

- I1: Select one supported OS/architecture for the first reference distribution;
  derive it from existing Linux acceptance and record the exact platform.
- I2: Reconcile package metadata and companion requirements; create locked build
  and installation manifests consuming the M1 catalog.
- I3: Package tools and runtime roots; produce checksums and provenance evidence.
- I4: Exercise offline installation from a prepared cache and relocation with
  source checkouts and global build tools unavailable.
- I5: Add upgrade interruption, hash mismatch, missing dependency, and rollback
  cases; archive installed-consumer evidence.

### Acceptance

- A clean consumer runs the documented workflow without sibling checkouts,
  hidden global tools, or per-run framework compilation.
- Correct behavior passes; a deliberate application fault produces a genuine
  model mismatch; Gate execution records confirmed physical cleanup.
- Corrupted packages and incompatible overrides fail before executing the SUT.
- Moving the installation does not silently change selected tools or identities.
- Failed installation preserves the previous usable installation.
- Local package acceptance is reported separately from publication. Expanding to
  another platform requires that platform's own installed-consumer evidence.

## 3. Failure capture, replay, and minimization

### Problem

A structured failure identifies an outcome, but diagnosing a cross-component run
still requires collecting compatible inputs and reconstructing execution context.
The framework should provide a reproducible trusted-side case with explicit limits
on repeatability, especially for asynchronous or external-state applications.

### Deliverables

1. A versioned private reproduction bundle containing model/corpus identities,
   permitted captured inputs or explicit external references, generated interface
   identity, implementation identity, tool/catalog identity, failure coordinates,
   normalized outcome, and cleanup evidence.
2. MirrorECMA capture/replay entry points integrated with existing project and
   suite APIs. Loading a bundle validates data but does not automatically execute
   embedded scripts or fetch dependencies; replay explicitly selects admitted code.
3. A failure-signature contract distinguishing mismatch, timeout, observer/codec
   error, unmet coverage, cancellation, and cleanup failure.
4. An opt-in reducer for deterministic, resettable cases. Start with isolating the
   failing trace and shortest reproducing prefix. More general deletion or input
   reduction requires model-valid candidates and explicit domain support.
5. A trusted diagnostic report plus the existing allowlisted public projection.
   Private traces, expected states, paths, and exception text never become public
   solely because a reproduction bundle exists.

### Implementation sequence

- R1: Specify capture bounds, redaction, external references, failure signatures,
  identity validation, and retention/access rules using the evidence format.
- R2: Implement capture and exact replay against installed tools.
- R3: Repeat replay to classify stable versus non-reproducible failures; record
  attempt counts and outcomes rather than claiming universal determinism.
- R4: Implement prefix reduction with fresh reset and disposal on each attempt,
  independent cleanup budgets, total attempt/time limits, and cancellation.
- R5: Add model-validated reduction for selected domain inputs only after the
  basic path is accepted. Label results as bounded reductions, not global minima.

### Acceptance

- A deterministic application fault reproduces the recorded mismatch from its
  bundle in both supported local and restricted paths.
- Missing private dependencies or incompatible identities cause explicit refusal.
- Reduction cannot count timeout, invalid model sequence, or cleanup failure as
  reproduction of the original behavioral mismatch.
- Every trial starts from a declared reset state; failed cleanup stops further
  trials when independence can no longer be established.
- Non-resettable or unstable cases retain the original bundle and report why
  reduction was unavailable or inconclusive.
- Oversized and malformed bundles fail bounded validation; public-output canary
  checks establish that captured private data is not disclosed.

## 4. Adapter fidelity and mutation acceptance

### Problem

A passing replay concerns reported observations. Isolation and matching interface
digests do not establish that an observer reads the actual application. Existing
application mutants provide a foundation for explicit, repeatable fidelity checks.

### Deliverables

1. A suite-level mutation acceptance contract: fixed model, corpus, observer, and
   acceptance requirements; named application mutations; expected detectable
   behavior; and identity records for unchanged protected inputs.
2. A reusable runner using ordinary suite execution and Gate providers. It runs
   the correct baseline and declared faulty implementations without modifying
   framework lifecycle or comparator semantics.
3. A result taxonomy: killed by behavioral mismatch, survived, invalid mutant,
   infrastructure failure, or inconclusive. Cleanup status remains independent;
   incomplete cleanup cannot qualify a successful mutation run.
4. A per-mutant matrix with mismatch evidence, tested scenarios, and explicit
   coverage limits. Avoid a single percentage without its denominator and scope.
5. Application-specific independent probes where useful, such as checking durable
   storage after a reported successful transfer. These belong to trusted
   evaluator/application fixtures, not to a universal inferred-observer mechanism.

### Implementation sequence

- F1: Codify existing WorkQueue, transfer, and lease mutants and their protected
  observer/model identities using a shared contract.
- F2: Extract orchestration into a public testing helper with bounded resource use.
- F3: Add negative controls for a broken observer or fabricated shadow state; show
  which independent probes detect them and which remain outside the claim.
- F4: Run the same matrix locally and through Gate; connect failures to R bundles.
- F5: Add guidance for domain-specific faults, resets, observations, and limitations.

### Acceptance

- The correct implementation passes before mutant results are interpreted.
- All required known-detectable mutants reach a real mismatch with acceptable
  cleanup; survivors are visible failures of the configured mutation requirement.
- Changing the observer, model, or corpus invalidates the fixed-baseline campaign
  instead of silently preserving its earlier acceptance.
- A worker crash or unavailable backend is never reported as killing a mutant.
- Reports explicitly state that mutation evidence strengthens confidence and does
  not prove observer honesty or exhaustive conformance.

## 5. Durable verification evidence

### Problem

Some historical aggregate logs referenced in the application progress record no
longer exist under `/tmp`. Hashes preserve identity claims but cannot replace the
missing artifacts needed to inspect a run.

### Deliverables

1. A shared evidence envelope with schema version, run identity, component and
   dirty-tree identities, platform/tools, commands, timestamps, outcomes, skipped
   or blocked tiers, artifact hashes, and cleanup records where applicable.
2. A clear distinction between historical evidence and fresh verification.
   Evidence is bound to its exact tested combination, not reassigned to HEAD.
3. Bounded artifact collection and durable storage outside scratch directories.
   Small sanitized summaries may be committed; full logs/private receipts belong
   in access-controlled artifact storage with a stated retention policy.
4. Atomic finalization with an index and integrity checks. Interrupted collection
   produces an incomplete record, never a completed pass.
5. A verifier for completeness, hashes, schema compatibility, and catalog links.
   Integrity verification must not be described as independent proof of truthful
   execution; provenance and signer trust are separate decisions.

### Implementation sequence

- E1: Define public/private fields, size limits, retention, and release-required
  artifacts. Reuse Gate receipt semantics rather than flattening outcome fields.
- E2: Add collectors around existing gate commands without changing exit behavior.
- E3: Implement storage/finalization and offline verification.
- E4: Link catalog entries and release candidates to retained bundles.
- E5: Mark unavailable historical artifacts explicitly; never manufacture logs
  or reinterpret old passes as fresh validation.

### Acceptance

- Removing scratch directories after publication does not break retained evidence.
- Missing/truncated artifacts, changed hashes, and incomplete collection are
  detected; required skipped tiers prevent full qualification.
- Required evidence-persistence failure blocks qualification while preserving the
  underlying behavioral result and failure reason.
- Public summaries pass private-data canary checks; private bundles retain strict
  access controls and exclude credentials by construction.
- An independent checkout can verify the bundle and identify precisely what ran.

## 6. Gate interruption recovery and aggregate limits

### Problem

Normal cancellation and cleanup already have explicit ownership rules. Abrupt
controller death requires a separate recovery design. The documented backend also
does not provide aggregate cgroup guarantees, so per-process limits cannot be
advertised as limits over an entire descendant tree.

### Deliverables

1. A Gate-owned recovery contract specifying resource ownership, persistent
   records, crash states, restart behavior, safe reclamation, and failure reporting.
   Default to terminating/reclaiming abandoned work; adopting or resuming sessions
   is a separate capability and remains out of the first implementation.
2. An operator-owned journal for snapshots, workers, and backend resources, with
   versioned records and exclusive recovery ownership. Never use PID alone as
   proof of ownership; account for PID reuse, boot identity, and stale records.
3. Scoped recovery inspection and reclamation that validates ownership before
   touching resources. Ambiguous resources remain unreclaimed and are reported.
4. An optional Linux cgroup v2 backend capability for aggregate process/memory/CPU
   limits where supported by operator delegation. Preserve the existing profile
   with its accurately documented limits when aggregate guarantees are not asked
   for; reject admission when requested guarantees cannot be enforced.
5. Fault-injection evidence for interruption at preparation, freezing, build,
   authorization, worker launch, replay, and cleanup boundaries.

### Implementation sequence

- G1: Write the lifecycle/interface design and a TLA+ recovery model. Specify
  single-owner recovery, no cross-session reclamation, monotonic cleanup evidence,
  and eventual cleanup assumptions. Separate model properties from OS evidence.
- G2: Implement journal durability and ownership identity; test torn/truncated
  records, concurrent recoverers, changed boot identity, and version mismatch.
- G3: Implement inspect/reclaim operations restricted to validated Gate resources;
  exercise recovery after abrupt process termination in disposable test roots.
- G4: Add aggregate-limit admission and accounting under operator-delegated cgroups,
  including descendant escape attempts and nested process workloads.
- G5: Integrate recovery receipts and backend capabilities into catalog, diagnostics,
  and evidence; document manual intervention for ambiguous ownership.

### Acceptance

- Abrupt controller termination cannot convert an incomplete run into a pass.
- Recovery never kills an unrelated process or removes an unrelated path, including
  adversarial stale journals, symlinks, PID reuse, and concurrent sessions.
- Resource reclamation is idempotent; interrupted recovery can retry safely.
- Available backend evidence confirms actual process/snapshot reclamation. Lack of
  evidence is reported as unconfirmed cleanup, not inferred success.
- Aggregate limits constrain a descendant workload collectively, and unsupported
  delegation causes explicit admission failure when those limits are required.
- Existing worker/control contracts and owned-versus-attached controller behavior
  remain compatible, or any new behavior uses a documented capability/version.

## Verification and qualification

Use focused tests while implementing, then run the existing owning-repository
gates for changed behavior. For Mirrors this includes `lake test` and applicable
compiler golden/preflight checks; native dependency-graph changes also require
`bash tools/check-native-rebuild.sh`. For Gate, use its required real-backend
`bash scripts/test.sh` plus affected evaluator integration gates. Follow the
current MirrorECMA and native-client instructions for their respective changes.

Cross-repository qualification must use explicit full companion SHAs and retained
artifacts. Run the applicable interop matrix and installed-consumer tests against
the exact candidate packages. Record environmental failures, optional skips,
required failures, and behavioral assertions separately. Passing source tests
does not establish installation, publication, or production readiness.

M5 requires these end-to-end demonstrations:

1. Install the candidate from prepared artifacts into a clean supported consumer.
2. Validate identities and capabilities without executing the application.
3. Replay a correct implementation and detect a deliberate application fault.
4. Capture and reproduce that fault; perform bounded reduction where supported.
5. Run the fixed-observer mutation campaign locally and through Gate.
6. Interrupt Gate, recover only owned resources, and retain accurate cleanup evidence.
7. Verify the archived evidence after temporary working directories are removed.

## Qualification execution environment

Required tiers must run where their primitives are permitted: `ptrace` (the
installation audit traces its relocated replay), AF_INET/AF_UNIX loopback (Gate
supervisor control, transport, registry), writable component checkouts and
evidence store. Delegated cgroup-v2 enforcement and native Ubuntu acceptance
are separate Linux-scope capabilities excluded from the selected M5 profile.
The 2026-09-25 pass inside an agent sandbox that denies these primitives
produced environment-limited incompletes, not product failures; such tiers
remain incomplete and are never downgraded to optional or passed.

The reference topology places only the framework's own bubbles (Gate
`linux-bubblewrap-v1`, the audit's bubblewrap isolation) between the host and
the evaluated work; no outer agent sandbox wraps the qualification run. When
an agent drives the run, use a dedicated fixture and declare the posture
explicitly: a qualification profile with `sandbox_mode =
"danger-full-access"` and `approval_policy = "never"` (the fixture is the
boundary), or a working approval reviewer (attended `user`, or a repaired
`auto_review` whose catalog `auto_review_model_override` names a model the
provider serves). The default attended posture stays `workspace-write` with
a reviewer; bypass profiles are per-run selections and do not weaken it.

Preflight the host before burning a pass: `strace` probe, `ptrace_scope` <= 1,
bubblewrap >= 0.9.0 non-setuid, AppArmor user-namespace policy on Ubuntu
24.04, loopback and UNIX sockets. Record the tested profile identity
(kernel, ptrace/AppArmor state, bubblewrap version) with the evidence.
WSL2-kernel observations are diagnostic and do not establish native Ubuntu
acceptance.

## Decisions to settle during M0

- First distribution OS/architecture and the boundary between bundled and
  operator-provided tools; later platforms require separate acceptance.
- Artifact storage, retention duration, private access controls, and whether
  release provenance needs signatures beyond checksums.
- Catalog governance across independently versioned repositories and how long
  older tested combinations remain supported.
- Which applications provide deterministic reset for reduction, and which require
  an explicitly inconclusive result or application-specific replay support.
- Available cgroup delegation and the supported recovery durability assumptions.

These decisions do not block schema inventory or local design work. They must be
resolved before advertising a distribution, recovery guarantee, or supported
deployment profile that depends on them.

## Completion criteria and non-goals

The selected M5 profile is complete when its scoped contracts, implementation,
acceptance evidence, and user guidance qualify an exact candidate combination.
Native Ubuntu and aggregate-cgroup claims remain separately unqualified;
M4 ownership-safe recovery stays required. The broader six-workstream roadmap
retains those separate capability records. Track partial milestones explicitly; avoid a single
framework-wide green status that hides incomplete capabilities.

This roadmap does not require a new wire protocol, replacing MirrorECMA's suite
runner, putting Gate inside client core, adding Windows/macOS isolation, achieving
full native-client feature parity, exposing private diagnostics to implementers,
or claiming exhaustive verification from finite traces or mutation campaigns.
