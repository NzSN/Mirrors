# Compatibility and installation task cards

Date: 2026-09-21

Source: [framework improvement roadmap](../mirror-framework-improvements.md)

Coordination: [task index and shared handoffs](../mirror-framework-tasks.md)

Assigned implementation role: `@general-purpose-gpt`

Status: task definitions ready; every product task below is **queued**

## Scope and execution rules

This work package refines roadmap tasks C1-C5 and I1-I5. It does not implement
them, publish packages, deploy services, mutate a host installation, or change a
companion repository. Proposed paths and command names become binding only after
B2 selects the initial profile and B3 records one active owner for each shared
file. An implementation assignment must preserve unrelated dirty-tree work and
stop when a required schema, platform, or file-ownership decision is missing.

Use the shared handoff contract in the [task index](../mirror-framework-tasks.md):
C2 owns capabilities and supported combinations; [E1](durable-evidence.md) owns
run, artifact, outcome, and evidence-envelope semantics. Installation consumes
both without defining competing identities. [Gate recovery](gate-recovery.md)
exports capabilities through C2, and [reproduction/fidelity](reproduction-and-fidelity.md)
consumes the installed distribution without becoming a package owner.

Each card's acceptance commands are either **existing** commands observed in the
current repositories or **planned** commands the card must add. Planned commands
must have the stated semantics even if C2/B3 approves a different final spelling.
A green source test is not publication, installed-consumer, Gate-backend, or
release-candidate evidence.

## Source-grounded baseline inventory

This is a read-only planning snapshot, not completion of C1 or B1. Refresh full
SHAs and dirty-tree state immediately before implementation.

| Area | Current source of truth | Observed baseline and planning consequence |
| --- | --- | --- |
| Repository identities | Mirrors `eb5cd001b990e6ac5e9b1e9b1c5a17ffb85e25fc`; MirrorECMA `a50710c7eb5e4d42631641a97749f6920e67b607`; MirrorGate `173075d318e4be926570a1378fc0aa36a1294f89` | Mirrors had unrelated untracked `.projectile-cache.eld`, `Plans/`, and `tools/__pycache__/`; companion worktrees were clean in this inspection. B1 must refresh rather than treating these as permanent pins. |
| Framework claims | `Docs/framework-map.md`, `Docs/application-integration-guide.md`, `Docs/application-integration-progress.md`, `Docs/versioning.md` | These already distinguish source implementation, local acceptance, installation, and publication, but the tables are handwritten and can drift. |
| Compiler capabilities | `Shell/ModelInterface/Compiler.lean`, `Shell/ModelInterface/Emit/`, `tools/ModelInterfaceGen.lean`, `lakefile.lean` | The compiler dispatches `mirrorecma-v1`, `mirrorecma-async-v1`, `mirrorcpp-v1`, and `mirrorrust-v1`. `lake test` performs golden checks for all four and runs `tools/model-interface-rust/check.sh`. |
| Rust support boundary | `Shell/ModelInterface/Emit/Rust.lean`; `Docs/framework-map.md`; MirrorGate `sdk/compatibility.json` | Rust emission exists in Mirrors, while the framework map still says no generated Rust target. Gate separately records `rustGeneratedApplicationTarget: false` and a handwritten Counter fixture profile. C4 must represent these as different evidence states, not flatten them into supported/unsupported. |
| Tool and client pins | `tools/ci/versions.env`; MirrorECMA `scripts/ci/versions.env`; product identity in `Shell/Version.lean` | Pins, product versions, protocol/profile versions, semantic digests, revisions, and artifact hashes are separate identities. Current Mirrors pins include Node 24.15.0, pnpm 11.22.0, Java 25.0.4+7, Apalache 0.61.0, and Rust 1.96.0. |
| Project diagnostics | MirrorECMA `src/project-config.ts`, `src/project.ts`, `src/cli.ts`, `test/project.test.ts`, `docs/project-tools.md` | `mirrorecma doctor` is read-only and separates configured identities from unperformed executable/backend admission. Overrides fail closed against lock constraints. It is the primary local consumer for C5. |
| Installed local acceptance | MirrorECMA `scripts/check-installed-suite.mjs` and `test/fixtures/project/installed-runner.mjs` | The existing gate packs once, installs offline, relocates, hides framework checkouts/global tools, runs correct/faulty/cleanup/timeout cases twice, and records identities. Preparation still begins from sibling source checkouts and is not a reference distribution. |
| Gate compatibility | MirrorGate `sdk/compatibility.json`, `docs/compatibility.md`, `docs/sandbox/linux-bubblewrap.md` | The manifest is `mirrorgate.sdk-compatibility/v1`, experimental, Linux/Bubblewrap, Python 3.12, Bubblewrap >=0.9.0, Node/Rust workers, and `productionPublication: false`. It is an input adapter, not the framework catalog itself. |
| Installed restricted acceptance | MirrorGate `integrations/mirrorecma/scripts/installed-suite.mjs`, `scripts/installed-workflow.mjs`, and `WORKFLOW.md` | Existing tests pack once, relocate, run offline with hidden source checkouts, and exercise real worker cleanup. They remain component acceptance, not an atomic multi-component installer or retained release bundle. |
| Platform evidence | Existing Gate contract plus dated Linux x86_64/WSL2 evidence and Ubuntu 24.04 interop CI | Linux/Bubblewrap is the only current Gate backend claim. Architecture and distribution base remain to be selected by I1/B2; interface compatibility cannot supply missing platform evidence. |
| Installation procedure | `Docs/versioning.md` | Mirrors documents staged per-user binary replacement and backup, but there is no framework-wide content manifest, transactional activation, or rollback-tested reference distribution. |
| Fresh trace dependencies | `tools/ci/versions.env`, `tools/ci/install-apalache.sh`, and project tooling docs | Checked-corpus replay is designed not to require Java/Apalache. Fresh trace generation is a separate optional profile and must stay separate in I2-I5. |

The initial inventory establishes source entry points, not support claims. In
particular, emitter availability is not installed client acceptance, Gate worker
acceptance, hosted CI, or publication.

## Dependency and handoff summary

| Task | Starts after | Produces for |
| --- | --- | --- |
| C1 | None; coordinate with B1 | C2, I1, B1 |
| C2 | C1 draft plus E1 identity vocabulary; finalize with B2 | C3-C5, I2, E4, G5 |
| C3 | B2/B3 and frozen C2 fixtures | C4, C5, I2 |
| C4 | C3 and component-owned records | C5, I2, E4, Q1 |
| C5 | C3-C4 and B3 ownership | I5, G5, Q1 |
| I1 | C1 inventory; feeds B2 rather than waiting for all M0 work | B2, I2 |
| I2 | B2/B3, C2-C3, and E1 | I3 |
| I3 | I2 and E1 provenance fields | I4, E2/E3 collectors |
| I4 | I3 and the existing local/Gate suite contracts | I5, R/F installed acceptance, Q1 |
| I5 | I4, C5, E3/E4 retention/linking | Q1-Q3 |

## C1 - Inventory compatibility identities and fact owners

**Assigned owner:** `@general-purpose-gpt`

**Milestone / status:** M0 / **queued** (the baseline above is only a seed)

**Repository and file responsibility**

- Mirrors documentation only: new `Docs/framework-catalog-inventory.md`, with
  links from `Docs/framework-map.md` if B3 assigns that shared file.
- Read-only inventory of MirrorECMA project/tool/package records and MirrorGate
  `sdk/compatibility.json`; no companion changes in this task.

**Work and deliverables**

1. Refresh all selected repository SHAs and porcelain status, then inventory
   product versions, protocol versions, target profiles, semantic/interface
   digests, tool pins, package metadata, runtime profiles, artifact hashes,
   platform/backend claims, acceptance ledgers, and publication flags.
2. For every fact record its authoritative owner, producing repository/path,
   consumer, freshness rule, and whether it is declared or observed.
3. Record contradictions and stale prose without resolving them. Include the
   `mirrorrust-v1` emitter versus generated-Rust support-table discrepancy.
4. Classify each capability independently as source-implemented, source-tested,
   locally accepted, installed-consumer accepted, hosted-CI accepted, published,
   or unknown. Never infer a later state from an earlier one.

**Acceptance and commands**

- Review every row against a live path; no row may cite only a roadmap or design.
- Run read-only identity capture in each selected repository:
  `git rev-parse HEAD`, `git status --short`, and targeted `rg` over the files in
  the baseline table.
- Validate JSON inputs with `python3 -m json.tool`, including Gate's compatibility
  manifest. The completed inventory has one owner and freshness rule per fact and
  an explicit unresolved list.

**Handoff / stop condition:** send the owner map and discrepancy list to B1, C2,
and I1. Stop if two repositories both appear authoritative for the same fact;
C2/B2 must settle governance before migration.

## C2 - Freeze the catalog capability contract

**Assigned owner:** `@general-purpose-gpt`

**Milestone / status:** M0-M1 / **queued**

**Repository and file responsibility**

- Mirrors: new normative `Docs/framework-catalog-contract.md` and catalog fixtures
  under `test/fixtures/framework-catalog/`.
- Joint semantic handoff with [E1](durable-evidence.md); C2 does not own evidence
  run/outcome fields or retention policy.

**Prerequisites:** C1 owner map; E1 draft identity envelope; B2 decisions for
catalog governance and initial profile. Draft work may proceed before B2, but the
contract cannot freeze while field ownership or governance is unresolved.

**Work and deliverables**

1. Specify a versioned strict catalog document, component capability records,
   exact component-revision selection, tested combinations, and immutable
   evidence references. Include canonicalization and content-digest rules.
2. Define required identities for compiler targets, client features, control and
   worker protocols, evaluator/worker language pairs, OS/architecture/backend,
   runtime trees, and distribution profiles.
3. Define separate declared-capability and observed-evidence fields with
   independent, explicitly observed status dimensions for implementation,
   testing, installation, hosted CI, and publication. Unknown is explicit;
   absence never means false support, and publication never implies testing.
4. Define major-version/unknown-field behavior, duplicate-key rejection,
   extension rules, bounds, location-bearing errors, contradictory-record rules,
   and behavior when a referenced component/evidence revision is missing.
5. Define adapter ownership for Gate `sdk/compatibility.json` and existing pin
   files. Adapters preserve the source record and reject disagreement; they do
   not silently choose a winner.
6. Supply minimal/full valid fixtures and rejected fixtures for missing revision,
   invalid evidence reference, contradiction, unsupported schema version,
   duplicate identity, source-only-as-released, and incompatible platform.

**Acceptance and commands**

- A field-ownership matrix shows that C2 owns capabilities/combinations while E1
  owns run/artifact/outcome evidence. Both documents use the same identity types.
- A review walkthrough can answer: what is implemented, what was tested, against
  which exact revision/artifact/runtime, on what platform, and whether published.
- Fixture expectations are machine-readable and ready for C3; schema examples
  include exact rejected paths/messages. Documentation link checking and
  `for file in test/fixtures/framework-catalog/*.json; do python3 -m json.tool "$file" >/dev/null || exit; done` pass.

**Handoff / stop condition:** freeze schema version, fixtures, and adapter rules
for C3, and identity references for I2/E4/G5. Stop before implementation if E1
cannot reference the same component/artifact identities without translation.

## C3 - Implement strict validation and deterministic generation

**Assigned owner:** `@general-purpose-gpt`

**Milestone / status:** M1 / **queued**

**Repository and file responsibility**

- Mirrors new modules, subject to B3: `Core/FrameworkCatalog.lean` for pure
  validation, `Codec/FrameworkCatalog.lean` for bounded strict decoding,
  `Shell/FrameworkCatalog.lean` for file orchestration, and a
  `framework_catalog` executable wired in `lakefile.lean`.
- Focused tests in `tools/FrameworkCatalogSpec.lean`; fixtures remain the frozen
  C2 contract unless explicitly handed back to C2.
- Generated outputs only in paths selected by C2; C4 owns their data migration.

**Prerequisites:** frozen C2 contract/fixtures, B2 profile decisions, and B3
exclusive ownership. E1 reference validation must be available as a contract or
an explicit typed stub; do not invent its outcome fields.

**Work and deliverables**

1. Implement bounded, duplicate-aware parsing, schema/version checks, canonical
   identity comparison, reference resolution, contradictions, and actionable
   JSON locations.
2. Add deterministic rendering of compact JSON and marked support-table sections.
   Generated regions have stable ordering/newlines and refuse manual drift.
3. Add explicit adapters for existing pin files and Gate compatibility input;
   validate adapter output against the same catalog types.
4. Provide `validate`, `render`, and `render --check` modes. All check modes are
   read-only and perform no network access, package installation, or execution of
   component binaries.

**Acceptance and commands**

- Planned focused gate: `lake build framework_catalog framework_catalog_spec`
  followed by `.lake/build/bin/framework_catalog_spec`.
- Planned CLI checks:
  `.lake/build/bin/framework_catalog validate catalog/framework-catalog.json`
  and `.lake/build/bin/framework_catalog render --catalog
  catalog/framework-catalog.json --check`.
- Run the CLI twice in fresh temporary output directories and compare bytes.
  Every C2 negative fixture fails with its expected location; missing revisions,
  bad evidence references, and contradictions are distinct errors.
- Run `lake test`; record external tiers that skip. No generated-region diff and
  `git diff --check` are required before handoff.

**Handoff / stop condition:** deliver the validated CLI/API and adapter fixtures
to C4/C5/I2. Stop if validation would require executing an untrusted component or
fetching an evidence reference; catalog validation is structural and local.

## C4 - Migrate current records and generate qualified support tables

**Assigned owner:** `@general-purpose-gpt`

**Milestone / status:** M1 / **queued**

**Repository and file responsibility**

- Mirrors central selected catalog under `catalog/` and component record at the
  path frozen by C2; generated regions in `Docs/framework-map.md` and the compact
  JSON report selected by C2.
- MirrorECMA capability record at the C2/B3-selected component-owned path.
- MirrorGate retains `sdk/compatibility.json`; change it only for a proven missing
  fact, under a separate B3 ownership handoff. The catalog normally consumes it
  through C3's adapter.
- Explanatory prose outside generated markers remains documentation-owned and is
  not overwritten by the generator.

**Prerequisites:** C3 validator/generator; exact refreshed revisions from B1;
component-owner review of records; E1-compatible immutable evidence references.

**Work and deliverables**

1. Migrate compiler targets, client capabilities, protocol/runtime versions,
   Gate constraints, pins, and existing evidence references without promoting
   historical evidence to current HEAD.
2. Model the Rust row precisely: `mirrorrust-v1` is implemented and golden-tested
   in Mirrors; generic installed MirrorRust generated-application and Gate suite
   acceptance remain unestablished; Gate's handwritten Counter fixture remains a
   distinct profile and `rustGeneratedApplicationTarget` stays false until its
   own acceptance exists.
3. Generate support tables and compact JSON. Clearly label source, local,
   installed, hosted, and published states and platform scope.
4. Add regression fixtures showing that a source-only feature cannot render as
   runtime-accepted or released and that stale prose/generated bytes fail checks.

**Acceptance and commands**

- C3 `validate` and `render --check` pass from a clean generated output.
- Existing `lake test` passes, including the `mirrorrust-v1` golden and
  `bash tools/model-interface-rust/check.sh`; these establish emitter scope only.
- Gate `python3 -m json.tool sdk/compatibility.json` passes and its adapter agrees
  with the migrated record. Manual changes inside generated markers are detected.
- Review each rendered claim back to an exact record and evidence identity; no
  row says published unless a publication artifact is actually referenced.

**Handoff / stop condition:** provide the selected catalog and generated report
to C5, I2, E4, and Q1. A missing component record renders unknown/unsupported as
specified; it never licenses an inferred support claim.

## C5 - Enforce freshness and diagnose installed combinations

**Assigned owner:** `@general-purpose-gpt`

**Milestone / status:** M1 / **queued**

**Implementation slices and file responsibility**

- **C5.a local diagnostics:** MirrorECMA `src/project-config.ts`, `src/project.ts`,
  `src/cli.ts`, `test/project.test.ts`, installed project fixtures, and
  `docs/project-tools.md`.
- **C5.b restricted admission:** MirrorGate integration preflight in
  `integrations/mirrorecma/src/suite.ts` (or the B3-selected pre-acquisition
  seam), focused tests, and compatibility documentation.
- Mirrors CI/generation wiring in `lakefile.lean` and catalog checks. Shared files
  are sequentially owned; C5.a and C5.b may run in parallel only after B3 proves
  their scopes do not overlap.

**Prerequisites:** C3 consumer API, C4 selected catalog, B3 file allocation, and
the I2 distribution-manifest shape for installed identity lookup. G5 may add new
Gate capabilities later through C2, not by changing C5's comparison semantics.

**Work and deliverables**

1. Extend read-only `doctor` to select a catalog explicitly and report catalog,
   component, package, executable, runtime-tree, and platform identities
   separately from live protocol/backend observations.
2. Add freshness checks to Mirrors/MirrorECMA/Gate CI for catalog validation,
   generated bytes, exact component revisions, and immutable evidence links.
3. Fail an incompatible installed combination before adapter import/factory
   construction locally and before provider/worker acquisition through Gate.
   Report which identity/capability/evidence predicate failed.
4. Allow a supported combination to proceed to ordinary exact interface
   negotiation and Gate policy admission. Catalog approval is never an override
   for semantic-digest matching, runtime negotiation, or policy.

**Acceptance and commands**

- MirrorECMA existing checks: `pnpm run check` and the focused project Jest suite;
  extend `pnpm run check:installed-suite` with compatible, incompatible, stale,
  missing-catalog, and unknown-version fixtures. Assert zero adapter imports and
  zero factory calls for rejected local combinations.
- Gate focused integration tests assert zero session/provider/worker acquisition
  for catalog rejection, then run `bash scripts/test.sh` for the required backend
  matrix. Backend unavailability is a required-tier failure or explicit skip,
  never a compatibility pass.
- Mirrors `lake test` includes `render --check`. CI deliberately editing a
  generated byte or component revision must go red with an actionable location.

**Handoff / stop condition:** deliver diagnostics/freshness behavior to I5 and
Q1. Stop if the implementation would make `doctor` execute tools or perform live
Gate admission; those remain separately requested operations with cleanup.

## I1 - Select and document the first reference platform

**Assigned owner:** `@general-purpose-gpt`

**Milestone / status:** M0-M2 / **queued**

**Repository and file responsibility**

- Mirrors new `Docs/reference-distribution-profile.md`; read-only evidence review
  in MirrorECMA and MirrorGate.
- B2 owns the final cross-repository decision. I1 supplies a reviewed proposal,
  not a unilateral support declaration.

**Work and deliverables**

1. Evaluate the initial candidate **Ubuntu 24.04 Linux x86_64** because current
   interop CI names Ubuntu 24.04 and dated acceptance is Linux x86_64; verify the
   exact libc, kernel/namespace, OpenSSL, filesystem, Node, Python, and Bubblewrap
   assumptions before selection. WSL2 evidence alone does not qualify Ubuntu or
   another host class.
2. Define two profiles: required checked-corpus local Node replay and optional
   Linux/Bubblewrap Gate replay. Define a separate optional fresh-trace profile.
3. Classify every dependency as bundled artifact, content-addressed runtime tree,
   or operator-provided host prerequisite. Keep credentials, private models,
   operator policy, kernel, namespace support, and cgroup delegation outside the
   distributed payload.
4. Record exclusions and expansion rules: other architectures/platforms require
   their own installed-consumer and backend evidence.

**Acceptance and commands**

- The profile matrix links every assumption to current acceptance or marks it
  unverified. It names OS release, architecture, runtime ABI, filesystem/atomic
  rename expectations, and Gate backend prerequisites.
- Run only read-only probes needed to characterize the candidate (`uname`,
  `/etc/os-release`, runtime `--version`, `bwrap --version`, and linked-library
  inspection); record results as observations, not portable guarantees.
- B2 explicitly accepts or replaces the candidate and the bundled/operator
  boundary before I2 freezes manifests.

**Handoff / stop condition:** hand the selected profile identifier and dependency
boundary to B2/I2. If no exact architecture has current install evidence, record
the gap and schedule qualification; do not publish a generic `linux` profile.

## I2 - Freeze distribution and installation manifests

**Assigned owner:** `@general-purpose-gpt`

**Milestone / status:** M2 / **queued**

**Repository and file responsibility**

- Mirrors reference distribution definitions under new
  `distribution/reference-node/`: profile manifest, component lock, dependency
  lock, cache index schema, activation/rollback transaction contract, and guide.
- Component package metadata remains owned in MirrorECMA `package.json`/lockfile,
  Mirrors version/pins, and MirrorGate root plus integration package manifests;
  touch each only under sequential B3 assignments.

**Prerequisites:** B2 profile and packaging decisions, B3 ownership, C2 schema,
C3 validator, C4 selected catalog, and E1 artifact/provenance identity fields.

**Work and deliverables**

1. Reconcile declared product/package versions with exact component revisions,
   package archives, compiler/server artifacts, catalog revision, runtime trees,
   transitive dependencies, licenses, and supported host assumptions.
2. Define locked `checked-replay-local`, optional `checked-replay-gate`, and
   optional `fresh-trace` manifests. Only the last includes pinned Java/Apalache;
   selecting checked replay must not fetch or require them.
3. Specify prepared-cache contents, offline resolution, compatible overrides,
   install-root layout, relocation rules, reserved/private paths, file modes,
   size/count bounds, and deterministic manifest canonicalization.
4. Specify staged verify-then-activate behavior, atomicity assumptions, retained
   previous version, rollback state machine, and failure recovery. Private keys,
   credentials, models, traces not intentionally distributed, and operator policy
   are forbidden manifest payloads.

**Acceptance and commands**

- C3 catalog validation accepts every referenced component/profile and rejects a
  wrong companion SHA, product-only match, or source-only capability.
- Planned `tools/distribution/manifest-check` validates schema, bounds, complete
  hashes, dependency closure, profile separation, relative relocatable paths, and
  absence of private/operator material.
- Resolve both checked profiles from a prepared cache with networking disabled;
  assert that the base profile contains no Java/Apalache dependency. Package
  publication remains `false`/unclaimed.

**Handoff / stop condition:** freeze manifest and transaction fixtures for I3.
Stop if a component archive cannot be tied to an exact revision and hash, or if
installation depends on a sibling checkout or implicit `PATH` lookup.

## I3 - Build, verify, stage, activate, and roll back artifacts

**Assigned owner:** `@general-purpose-gpt`

**Milestone / status:** M2 / **queued**

**Repository and file responsibility**

- Mirrors orchestration under new `tools/distribution/` and focused tests; output
  recipes under `distribution/reference-node/`.
- Component pack/build changes, if required, stay in their owning repositories
  and are performed as separate B3-scoped changes. Gate runtime-root construction
  must reuse Gate's admitted runtime contract, not create a second policy format.

**Prerequisites:** frozen I2 manifests/fixtures, E1 provenance contract, component
build commands, and an isolated disposable output root. Publication credentials
are neither required nor permitted.

**Work and deliverables**

1. Build package archives, Mirrors compiler/server artifacts, and optional Gate
   integration/runtime roots once; emit byte hashes, source revisions, build
   inputs, profile/catalog identity, and E1-compatible provenance.
2. Define and implement the admitted runtime-tree content hash: normalized
   relative path, entry type, executable bit/mode policy, size, and content bytes;
   reject links, special files, traversal, duplicate names, and mutation while
   hashing. Keep this identity separate from kernel/host policy observations.
3. Implement bounded cache verification, staging in the destination filesystem,
   complete integrity verification before SUT execution, atomic activation where
   the I1 platform supports it, and explicit rollback to the previous manifest.
4. Make activation idempotent and interruption-aware. Never overwrite an unknown
   installation, follow destination symlinks, import credentials, or delete a
   previous usable version before the new version is committed.

**Acceptance and commands**

- Planned commands: `bash tools/distribution/build.sh --profile PROFILE --out DIR`,
  `bash tools/distribution/verify.sh DIR`, and
  `bash tools/distribution/install.sh --cache DIR --prefix PREFIX` against only
  explicit disposable paths.
- Two builds from the same locked inputs produce matching manifests/content
  hashes, or every documented nondeterministic artifact is separately identified
  and excluded from identity comparison. Tampering before activation is rejected.
- Installer tests prove stage/verify/activate ordering, destination confinement,
  no network, no SUT execution during verification, and retention of the previous
  version. Evidence is emitted through E1 without claiming truthful host support.

**Handoff / stop condition:** hand a prepared, verified cache and disposable
installer to I4 plus provenance inputs to E2/E3. Stop before writing a real user
prefix or publishing an archive; acceptance uses isolated temporary roots only.

## I4 - Prove offline, relocated, source-free consumption

**Assigned owner:** `@general-purpose-gpt`

**Milestone / status:** M2 / **queued**

**Repository and file responsibility**

- Mirrors distribution consumer driver/fixtures under `tools/distribution/`.
- Extend MirrorECMA `scripts/check-installed-suite.mjs` and MirrorGate
  `integrations/mirrorecma/scripts/installed-suite.mjs` only through separate B3
  handoffs; retain their existing ordinary suite and lifecycle semantics.

**Prerequisites:** I3 prepared cache/installer, C4 catalog, existing correct and
faulty Counter suite, and an available Gate backend for the optional Gate profile.

**Work and deliverables**

1. Install into a clean disposable consumer from the prepared cache with network,
   sibling checkouts, source build trees, global package/build tools, and original
   install path unavailable. Move the entire installation before first replay.
2. Run read-only compatibility/identity checks, then correct local replay and the
   existing deliberate Counter fault. The negative must be a genuine model
   mismatch, not missing infrastructure, codec failure, or cleanup failure.
3. For the optional Gate profile, replay the same suite through the installed
   integration and admitted runtime tree; retain confirmed physical cleanup.
4. Run twice after relocation and prove no package pack/install, client build,
   framework compilation, Java, or Apalache occurs per replay. Exercise fresh
   trace generation only when the separate profile is explicitly selected.

**Acceptance and commands**

- Existing component gates remain green: MirrorECMA
  `pnpm run check:installed-suite` and the Gate integration's installed-suite
  command. The new planned top-level gate is
  `bash tools/distribution/test-installed.sh --profile PROFILE --cache DIR`.
- Audit executed processes and filesystem reads. Correct replay passes; faulty
  replay reports expected mismatch coordinates; incompatible identity fails
  before adapter construction; Gate result includes confirmed cleanup.
- Remove/hide preparation and source directories before execution, relocate to a
  second path, disable networking, and compare both run identities/outcomes.

**Handoff / stop condition:** retain I4 evidence through E3 and give the installed
root to I5/R/F/Q work. If Bubblewrap/namespace admission is unavailable, local
acceptance may pass but the Gate profile remains incomplete, never skipped green.

## I5 - Qualify failure handling, upgrade, rollback, and retained evidence

**Assigned owner:** `@general-purpose-gpt`

**Milestone / status:** M2 / **queued**

**Repository and file responsibility**

- Mirrors negative/upgrade fixtures and distribution acceptance driver under
  `tools/distribution/`; installation guide under `Docs/`.
- C5 retains compatibility-diagnostic behavior; E3/E4 retain evidence storage and
  catalog linking. I5 consumes those interfaces rather than editing their schemas.

**Prerequisites:** I4 positive installed-consumer pass, C5 pre-construction
diagnostics, E3 offline verifier/storage, E4 catalog linkage, and disposable
same-filesystem/cross-filesystem test roots reflecting I1 assumptions.

**Work and deliverables**

1. Add bounded cases for corrupted/truncated archive, content-hash mismatch,
   wrong component/catalog revision, incompatible override, missing dependency,
   unsupported host/profile, relocated stale absolute path, and excessive input.
   Assert failure before SUT/adapter/worker execution.
2. Inject interruption after download/cache, staging, verification, activation
   preparation, activation, and cleanup. Record whether the old or new manifest
   is authoritative after each point and remove only owned incomplete staging.
3. Exercise explicit rollback after successful upgrade and after post-activation
   health-check failure. The previous installation remains byte-identical and
   usable; ambiguous state produces a recovery instruction, not destructive
   guessing.
4. Publish one installation guide covering verified install, correct replay,
   intentional mismatch, optional Gate replay, upgrade, diagnostics, rollback,
   and evidence verification. Archive evidence with exact identities and separate
   local/package/publication states.

**Acceptance and commands**

- Planned gate:
  `bash tools/distribution/test-upgrade.sh --cache OLD --candidate NEW --root DIR`
  runs the full interruption/hash/dependency/rollback matrix in a disposable root.
- Instrumented sentinels prove zero adapter construction and zero worker/SUT
  launch for integrity/compatibility rejection. A failed install leaves the prior
  `doctor`, correct replay, and version/hash checks passing.
- Verify retained evidence after deleting all scratch/preparation directories;
  use E3's verifier and C3's catalog validator. Run component full gates required
  by touched files, including `lake test`, MirrorECMA checks, and Gate
  `bash scripts/test.sh`; record required skips/failures separately.
- The final report says locally packaged/installed, not published, unless a
  separately authorized publication action and artifact evidence exists.

**Handoff / stop condition:** hand the exact install manifest, rollback evidence,
catalog diagnostics, and retained bundle to Q1-Q3. Publication, production
deployment, real user-prefix replacement, and another platform are new tasks and
require separate authorization/evidence.

## Work-package completion checklist

- [x] C1-C5 and I1-I5 retain their stable roadmap IDs.
- [x] Every card is assigned to `@general-purpose-gpt` and explicitly queued.
- [x] Repository/file responsibility, prerequisites, deliverables, commands,
  acceptance, stop conditions, and downstream handoffs are stated.
- [x] C2/E1 identity ownership and B1-B3/Q1-Q3 index handoffs are preserved.
- [x] The initial baseline distinguishes implementation, acceptance,
  installation, backend evidence, and publication.
- [ ] Product implementation, runtime acceptance, package publication, deployment,
  and host mutation remain unstarted.
