# Framework execution decisions

Date: 2026-09-22

The user authorized execution of the framework task cards using
`general-purpose-gpt`. This record tracks B2 decisions and B3 assignments;
implementation acceptance still requires reviewed destination files and checks.

## Selected scope

- Implement the initial checked-corpus Node distribution, with a separately
  selected Linux Gate profile and optional fresh-trace tooling. No package
  publication or production deployment is part of this execution.
- Use exact source revisions and dirty-tree content identities. Preserve
  MirrorECMA's pre-existing untracked `.work/` directory.
- Use owner-only local durable evidence storage, with no automatic upload or
  pruning. Hosted retention, signing, and production access policy remain
  unqualified rather than blocking local implementation.
- Keep behavioral results, cleanup observations, and evidence persistence
  independent. Qualification is derived from all required observations.
- Recovery initially uses offline operator inspection and explicit reclamation.
  It does not adopt abandoned sessions. Ambiguous ownership never authorizes
  signaling or removal.
- Aggregate limits require an explicitly supplied delegated cgroup v2 parent.
  Do not provision host delegation. The current host exposes a read-only cgroup
  hierarchy; real aggregate acceptance therefore needs another supplied fixture.
- The candidate platform is Ubuntu 24.04 x86_64. The current Ubuntu 24.04.4
  environment runs a WSL2 kernel; its observations cannot establish native-host
  acceptance. I1 must record the precise tested profile and remaining gaps.
- R5's first candidate is LeaseService with coordinate-preserving input changes
  from client/token `2` to `1`, subject to model validation and actual mismatch
  reproduction. WorkQueue's existing input-sensitive failures already use the
  smallest supported item, so it is unsuitable for this acceptance case. Model
  validation uses evaluator-selected pinned Apalache in the optional fresh-trace
  profile; ordinary checked replay does not acquire that dependency.

## Active ownership

| Agent | Initial tasks | Exclusive files |
| --- | --- | --- |
| `baseline_catalog` | B1, C1, I1 | `Plans/implementation-baseline.md`, `Docs/framework-catalog-inventory.md`, `Docs/reference-distribution-profile.md` |
| `evidence_contract` | E1 draft | `Docs/durable-evidence-design.md`, `tools/evidence/schema/`, `tools/evidence/fixtures/`, contract validator/tests |
| `recovery_design` | G1 | MirrorGate recovery design/model/model gate and scoped documentation links |
| `reproduction_contracts` | R1, F1 | MirrorECMA reproduction/mutation contracts and inert fixtures |
| parent coordinator | B2, B3, review | this record and `Plans/mirror-framework-tasks.md` |

Following C2 review, `baseline_catalog` additionally owns C3's
`Core/FrameworkCatalog.lean`, `Codec/FrameworkCatalog.lean`,
`Shell/FrameworkCatalog.lean`, `tools/FrameworkCatalog.lean`,
`tools/FrameworkCatalogSpec.lean`, and `lakefile.lean`. Runtime work begins once
C2/E1 confirm the shared reference shapes. No other active agent owns these files.

Companion writes must use the environment's approved filesystem mechanism.
Scratch artifacts are not delivered implementation. Shared runtime modules are
not assigned until contract review; each subsequent handoff records its exact
scope here.

## Contract review

C2 and E1 confirmed their shared reference shapes on 2026-09-22. The parent
accepted that seam for local implementation, including a separate public dirty
identity projection and acyclic evidence references. Schema/validator acceptance
remains subject to the executable contract tests. Each task retains its original
acceptance criteria and reports unavailable checks explicitly.

E1 was accepted for the selected local profile after parent review and an
independent run of all 20 contract tests (passed). The private envelope hashes
payloads; the separately constructed public summary contains no envelope hash;
the final index hashes both structures and payloads. Only a verified committed
index establishes completion. E2/E3 are now active under their assigned owner.

`reproduction_contracts` now owns the sequential R1/F1 acceptance checks,
R2–R4 and F2–F3 implementation in MirrorECMA: reproduction/campaign modules,
`src/index.ts`, `src/project.ts`, `src/cli.ts`, focused tests and their docs.
Existing suite/comparator lifecycle remains authoritative. Cross-repository Gate
integration and R5 are separate subsequent handoffs. No other active assignment
may edit those shared MirrorECMA modules.

R1/F1's first nine passing tests validate synthetic contract fixtures using
test-local helpers. Parent review did not accept them as runtime inertness or
drift-enforcement evidence: the runtime implementation must replace those helpers
with imports of the production validator and instrument actual effect callbacks.
Accessor side effects, duplicate JSON keys and malformed shared references are
explicit regression obligations in the R2/F2 handoff.

After E1 contract tests pass, `evidence_contract` owns E2/E3 sequentially across
`tools/evidence/` and `Docs/durable-evidence-design.md`. This includes collection,
storage, finalization, offline verification, dependency pins and focused tests.
It does not include `lakefile.lean`, currently owned by C3. E4/E5 follow E3 review.

G1 was accepted after destination hash verification and model review. TLC 2.19
exhaustively checked 30,283 distinct finite states; all three weakened guards
produced their expected counterexamples. Apalache 0.62.2 passed typechecking and
safety through length 8 under an explicit version override; the default 0.61.0
pin was not checked. Raw logs are staged at
`/tmp/mirrorgate-g1-recovery-evidence-final-20260922` pending E3 durable archival.

`recovery_design` now owns G2/G3 sequentially in MirrorGate:
`recovery_journal.py`, `recovery.py`, `preparation.py`, `artifacts.py`, `cli.py`,
their focused tests and recovery documentation. G4/G5 follow parent review.
Recovery tests use only explicitly owned disposable roots and child processes.

B1, C1 and I1 were parent-reviewed on 2026-09-22. The review corrected a stale
Gate source filename and clarified that source implementation is backed by source
locations, while test/acceptance claims need run evidence. The accepted profile
forbids compiler execution during ordinary checked replay. The full namespace
probe failed creating a network namespace socket inside the tool sandbox; the
same full probe subsequently passed with narrowly approved escalation. Required
Gate tests may therefore run outside the tool sandbox. The smaller user/PID probe
alone does not satisfy Gate admission. These documents complete inventory
and profile selection, not runtime or installation qualification.

## Acceptance mapping

| Work | Required acceptance before completion |
| --- | --- |
| B1/C1/I1 | refreshed revisions/status, source-linked owner inventory, observed platform and dependency boundaries |
| C2/E1 | compatible identity definitions, valid/rejected fixtures, independent outcome axes, no public private-data canaries |
| C3/C4 | strict Lean decoder/validator tests, deterministic generated output, `lake test`, qualified support rows |
| C5 | read-only diagnostics and rejection before local adapter import or Gate acquisition; installed-consumer negatives |
| E2/E3 | child exit preservation, bounded collection, interruption/storage negatives, offline verification after scratch removal |
| E4/E5 | exact candidate evidence links and additive historical availability audit |
| I2/I3 | dependency closure, hashes, profile separation, staged activation and rollback fixtures |
| I4/I5 | offline relocated consumer with sources/tools hidden, genuine mismatch, upgrade/interruption matrix |
| R1–R5 | inert bounded inputs, exact replay signatures, fresh reset and disposal, bounded stability/reduction evidence |
| F1–F5 | fixed protected inputs, correct baseline first, complete named mutant matrix, independent observer probes |
| G1 | executable TLA+ safety model, weakened-guard counterexamples, explicit model/OS evidence boundary |
| G2/G3 | durable journal cut points, exclusive ownership, adversarial identities, real abrupt-death recovery |
| G4 | required delegated-cgroup admission and actual descendant PID/memory/CPU enforcement observations |
| G5 | immutable original evaluation evidence, bounded recovery receipt and capability adapters |
| Q1–Q3 | exact installed candidate, all required demonstrations, separate-checkout evidence verification, honest readiness report |

Focused checks run first. Owning-repository full gates run for changed behavior;
required environment failures remain failures or unavailable tiers, never passes.
No candidate qualifies through mocked enforcement or a missing retained log.

## Reviewed progress

| Tasks | Current evidence and status |
| --- | --- |
| B1, C1, I1 | Inventory/profile artifacts reviewed and accepted; no runtime qualification implied |
| C2, E1 | Shared local contracts reviewed; E1's 20 executable contract tests independently passed |
| G1 | Delivered model/design accepted with destination hashes and actual checker logs; durable archival pending E3 |
| C3 | Scoped implementation accepted after review corrections; full gate failed exact Java pin check, qualification incomplete |
| E2, E3 | Local implementation accepted after review corrections and 51 independently passing tests |
| R1, F1 | Contract fixtures delivered; production validation acceptance proceeds with R2/F2 |
| R2–R4, F2–F3 | Local helper slice passed 60 independent tests; application provenance/probe integration and installed reproduction/CLI still pending |
| G2, G3 | Delivered and hash-verified; full required Gate script passed after temporary pinned dependency preparation |
| C4, I2 | Candidate migration reviewed; I2 contract accepted after identity/closure fixes, final focused recheck pending |
| E4, E5 | 68 evidence tests independently passed; historical audit accepted, linkage tooling reviewed with final hardening pending |
| C5 | Pure validator active under evidence owner; project/CLI integration remains reproduction owner |
| I3 | Authorized after I2 recheck; immutable preparation, verification and disposable activation/rollback |
| R5, F4 | Narrow LeaseService reducer and Gate campaign/reproduction integration assigned |
| G4 | Optional backend implementation assigned; delegated real-enforcement tier unavailable |
| I4–I5, F5, G5 | Waiting for their specific reviewed producer handoffs |
| Q1–Q3 | Pending all required acceptance; no release candidate is qualified |

Passing tests above are limited to their named scope. Parent review findings must
be resolved before an implementation task is accepted or its consumers advance.

C3's review corrections subsequently passed focused build/spec, adapter, CLI,
canonicalization and rendering checks. The parent independently confirmed that
the traversal regression is rejected. Scoped C3 implementation is accepted;
`lake test` failed its DV1 tool check because installed Java reports `25.0.4.1`
instead of exact `25.0.4+7`, with four differential tests skipped. The
`acc-precedence` message is an expected negative case, not another failure.
Whole-tree evidence also records concurrent unrelated evidence-tool changes and
does not qualify an immutable candidate. Logs and scoped source hashes are at
`/tmp/mirrors-c3-lake-test-final.log` and
`/tmp/mirrors-c3-scoped-files.sha256`, pending E3 archival.

`baseline_catalog` now owns C4's `catalog/` records, marked generated support
section in `Docs/framework-map.md`, compact report and freshness checks. It also
owns I2's `distribution/reference-node/` manifests and
`tools/distribution/` contract validation. I3 waits for parent manifest review.
MirrorECMA project/CLI files remain owned by `reproduction_contracts`; C5 must use
an explicit handoff to that owner rather than concurrent edits.

E2/E3's final review verified independent payload copies, descriptor-relative
no-follow access, bounded parsing/verification and payload durability before
index publication. Parent reran 51 tests successfully. G1 and C3 source packages
are now retained under the owner-only local evidence store, explicitly
historical-unqualified with no invented pre-run catalog/run reference. Parent
verified all 18 and 28 retained file hashes respectively.

`evidence_contract` now owns E4/E5 adapters and tests under `tools/evidence/`,
the additive `Docs/evidence/historical-artifact-availability.json` sidecar, and
scoped explanatory links in `Docs/application-integration-progress.md`. Original
historical evidence records remain byte-preserved. C4 owns catalog data and C2/C3
own catalog semantics; E4 integrates through those reviewed interfaces.

Parent verified E5's 43 scoped absolute locators (40 unavailable at audit,
3 external with policy) and unchanged original four JSON records. All rows stay
non-qualifying. E4 separates source validation from local/release candidate
qualification; candidate profiles require M5 demonstrations and component gates,
and cannot credit source-only evidence as runtime/installed/hosted/publication
acceptance. The combined 68-test evidence suite passed independently.

After E4's final hardening, `evidence_contract` owns C5's new MirrorECMA
`src/framework-catalog.ts`, `test/framework-catalog.test.ts` and new conformance
fixtures only. `reproduction_contracts` retains `src/index.ts`, project and CLI
integration. I2 manifest semantics come from `baseline_catalog`. These scopes
must not overlap; pure preflight performs no executable/tool or adapter invocation.

G2/G3's scoped runtime review accepted durable filesystem/process intents,
root/UID/object-token validation, retained-descendant protection, interruption
handling, a trusted launch barrier before submitted execution, safe Python path
selection, and serialized journal transitions. The required script passed Python
282/282, Node 226/226 and integration 4/4, then stopped at missing
`nlohmann_json` 3.11.3; temporary dependency preparation is authorized. Separate
Rust and real sandbox/lifecycle checks passed. This is not a full-gate pass or
aggregate-cgroup acceptance. Exact destination integration remains to verify.

After integration, `recovery_design` owns G4's optional cgroup backend,
versioned operator policy, trusted launch membership barrier, focused tests and
backend docs. Real enforcement requires a supplied delegated parent, still
unavailable. G5 supervisor capability/receipt work may follow; MirrorECMA
integration receipt/workflow files need a separate ownership handoff.

Parent independently reran seven production reproduction/mutation suites:
60 tests passed. The accepted local slice includes exact signature checking,
fresh real suite factories/disposers, independent cleanup grace, bounded callback
preflight, path-required cleanup, protected-input drift checks and separate
campaign execution/acceptance outcomes. The owner also ran the full Jest suite
(544 tests passed, 13 skipped), installed baseline replay and local 9/4/4 mutant
matrices. Installed reproduction CLI is not yet claimed.

`reproduction_contracts` now owns R5's selected LeaseService input-only reducer
and F4's new Gate integration helpers/tests/scripts, including `suite.ts` if
needed. It must reuse public suite/lifecycle APIs. `receipt.ts` and `workflow.ts`
are not concurrently assigned; changes require an explicit handoff. Fresh-trace
qualification still requires the missing exact Java artifact.

G2/G3 subsequently integrated into MirrorGate. Parent verified all 14 destination
hashes against the checked staging files and `git diff --check` passed. Preparing
the official pinned nlohmann/json 3.11.3 header in a temporary prefix allowed
`bash scripts/test.sh` to finish with exit 0, including Python 282/282, Node
226/226, integration 4/4, C++ CTest 3/3, Rust, cross-language and real lifecycle
gates. Raw aggregate-log retention is being completed before G4 edits; this pass
does not establish delegated cgroup enforcement.

F4 integration review found additional application-fixture obligations despite
passing helper tests: campaign catalog references must identify actual catalog
bytes, protected observer/probe/generated-module closures must include their
executable code, and successful fact capture alone is not a fidelity assertion.
The reproduction owner is correcting those integration points. Generic Gate
probe absence remains `not_run`; a fixed-fixture instrumentation approach is
being assessed without adding an oracle channel or claiming observer honesty.

The exact Java prerequisite was subsequently prepared in an isolated cache from
Microsoft's official OpenJDK archive and published checksum. It reports build
`25.0.4+7-LTS`; archive SHA-256 is
`75894d107e474ffb6c947ab050e3893e0a1d3d40d36f107d42936ac6088769c1`.
Mirrors' exact tool check passes with that runtime and pinned Apalache 0.61.0.
This resolves the missing-Java prerequisite without a global installation or pin
relaxation. Existing immutable catalog/cache selections retain their original
input records; a new build records the newly prepared dependency separately.

## Current integration checkpoint

This checkpoint supersedes earlier prerequisite and test-count observations;
those paragraphs remain as execution history. Implementation is still active.

- E2's predeclared private attachments passed the 73-test evidence suite. Command
  registration waits for the reproduction owner's exact argv and output contract.
  An original observation run is finalized before a reproduction bundle refers
  to it; a separate replay/capture run retains that bundle. No artifact contains
  a reference to its own enclosing envelope digest.
- C5's pure catalog/distribution admission module passes its focused tests and
  TypeScript checks. Installed CLI admission and installed reproduction remain
  integration obligations.
- Development local and Gate distribution caches have been built and installed.
  I3 remains under review for descriptor-relative filesystem operations, bounded
  materialization parsing/traversal, and exact build provenance. These caches
  are development results, not a final Q1 candidate.
- R/F helper and local application tests pass. Actual Gate application coverage
  must include WorkQueue, PersistentTransfer, and LeaseService. A LeaseService
  Gate result alone does not complete F4. The evaluator-owned R5 materializer
  must be shipped and validated independently of temporary experiments.
- G2/G3's complete Gate suite and source package are retained under the private
  evidence store. G4/G5 still require corrections to failure/retry behavior,
  production receipt wiring, and public projection validation. Gated real cgroup
  tests must exist even where their execution prerequisite is unavailable.
- The current host has no supplied writable delegated cgroup-v2 parent. Real
  aggregate enforcement is unavailable; mocked controller tests do not qualify
  it. WSL2 results also do not establish native Ubuntu host qualification.

I4/I5 and Q1/Q2 follow the reviewed integration, a new immutable source snapshot,
and exact final manifests. A readiness report must retain unavailable required
tiers as incomplete rather than converting them into optional passes.

The Q integration review identified that E2 emits one command per finalized run,
whereas E4 originally required every qualification command in one envelope.
`evidence_contract` now owns a typed linked qualification aggregate: it verifies
already-finalized run references, preserves each result's origin, rejects mixed
candidate identities and duplicate credit, and supplies the verified scope to
E4. This is an acyclic evidence index, not a newly invented command execution.
The original observation still finalizes before any reproduction bundle cites it.

Parent independently reran the attachment-enabled evidence suite: 73 tests
passed. Review then required the native Gate receipt adapter to check the frozen
case denominator and campaign/fidelity acceptance, rather than accepting an
arbitrary nonempty list of passed cases. Cleanup failure must also retain
precedence over a later unconfirmed case. Those integration corrections remain
with the evidence owner.

The subsequent parent `lake test` reached the catalog gate and failed on the
new Gate `aggregateQuota` field plus stale generated output. Earlier gates in
that run passed, including the async protocol model, fixture round trips, all
500 differential cases, model-interface specification, and model-interface
distribution specification. The catalog owner is reconciling the G5 handoff
and regenerated records before another aggregate run. The retained development
log is `/tmp/mirrors-framework-parent-lake-test-2.log`; it is not a qualification
pass.

The next parent aggregate run confirmed the catalog correction: framework
catalog specification, 16 distribution tests, and reference-manifest validation
passed. It then exercised 75 evidence tests and stopped at three failures and
one error in the in-progress qualification-scope migration. The old catalog-link
fixtures still modeled all commands in one envelope and must be replaced with
the linked finalized-run graph. The new admission rule is retained. Log:
`/tmp/mirrors-framework-parent-lake-test-3.log`. A further full run waits for the
evidence owner's focused-green handoff.

After resumed recovery/reproduction turns stalled, the coordinator interrupted
them and transferred their unchanged file scopes to fresh `general-purpose-gpt`
agents `recovery_finish` and `reproduction_finish`. The old owners must not edit
concurrently. Catalog/distribution and evidence owners remain unchanged. The new
recovery audit confirmed outstanding retryable cgroup cleanup, complete receipt
validation, actual original-result immutability tests, real-workload test-source
coverage, and stale documentation; these remain acceptance requirements.

### Fresh-context finish assignments

Four fresh-context `general-purpose-gpt` agents now own the remaining bounded
implementation scopes. `distribution_finish` owns catalog/distribution and the
final development cache; `evidence_finish` owns `tools/evidence/`, its durable
evidence documentation and historical sidecar; `reproduction_finish` owns the
MirrorECMA project, CLI, reproduction, reduction and Gate campaign integration;
and `recovery_finish` owns the staged MirrorGate recovery correction. The parent
coordinates and reviews these scopes. Superseded owners must not resume them.

The evidence owner independently passed 90 focused evidence tests after adding
raw command-registry retention and verification, exact single-D credit, explicit
source-R0 phase ownership, and the linked-scope negative cases. This is a focused
source validation result. The eight installed qualification command wrappers and
actual Q runs still wait for the final immutable development cache and installed
producer paths.

The shipped R5 artifacts and the pinned September Haskell interop build are now
retained as owner-only historical-unqualified source packages. The R5 package
index is `624099f5bc38c4ffec511e8e3223c61bd1094dfb5476de467b06a4d1ff32adb2`;
the Haskell package index is
`6cc303d8b79157822be38461e3805b1330eb62f000a3eec88235713fb33ba96e`.
Neither package has a preselected finalized E1 run. The interop registry pins the
new Haskell executable hash
`6b8b46ce98b59c4bbb6a922ead08b1d576a77b8889454d106c10d1227584a087`;
the older pre-September binary is not admissible.

The distribution owner is rebuilding that cache after the latest component and
framework-input cross-binding changes. Earlier `/tmp/mirrors-i4-dev-*` layouts
remain provisional and are not registered as final command identities. The
reproduction owner is closing preloaded-project admission, stale filesystem
remeasurement, and immutable package/runtime cross-binding findings before the
evidence owner freezes installed argv and output contracts.

The recovery owner has an 18-file correction staged at
`/tmp/mirrorgate-recovery-finish.patch` with its manifest. Applying that patch to
MirrorGate still needs the user's explicit write approval after automatic review
rejected the overwrite action; staged checks do not mean the destination changed.
The current host still lacks a supplied writable delegated cgroup-v2 parent, so
the real aggregate-enforcement tier is required but unavailable. No helper,
mocked-controller, or staged-patch test converts that tier into a pass.
