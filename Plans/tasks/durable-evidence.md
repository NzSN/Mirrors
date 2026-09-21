# Durable verification evidence tasks (E1-E5)

Date: 2026-09-21

Source: [Mirror Framework improvement plan](../mirror-framework-improvements.md)

Assignment: `general-purpose-gpt` / `evidence_tasks`

Implementation status: **Queued**. This document is planning and task decomposition only.

## Outcome and boundaries

E1-E5 create a shared, verifiable evidence envelope around existing commands. They
do not replace Mirrors comparison semantics, MirrorECMA suite results, or Gate
receipts. In particular, a behavioral result, cleanup result, and persistence
result remain separate observations. Qualification may require all three, but it
must not rewrite one result to make another look successful or failed.

The implementation owner must preserve existing work, refresh the repository
SHAs and dirty-tree state before coding, and keep publication, deployment,
credential handling, and destructive host cleanup outside these tasks. B3 assigns
non-overlapping implementation ownership before any cross-repository edit.

## Baseline inventory

The planning inspection used Mirrors
`eb5cd001b990e6ac5e9b1e9b1c5a17ffb85e25fc`, MirrorGate
`173075d318e4be926570a1378fc0aa36a1294f89`, and MirrorECMA
`a50710c7eb5e4d42631641a97749f6920e67b607`. Mirrors had untracked planning,
editor-cache, and Python-cache files; the two companion status checks were clean.
These are inventory facts, not permanent implementation pins.

| Existing mechanism | Current source and constraint | E-task use |
| --- | --- | --- |
| Application integration record | `Docs/application-integration-evidence.json` identifies source/artifacts and hashes, but several logs and local receipts point into `/tmp`. `Docs/application-integration-progress.md` says six aggregate logs were already absent during its audit and that no gates were rerun. | E5 records honest unavailability without manufacturing or refreshing evidence. |
| Retained application evidence | `Docs/application-integration-p12-evidence.json` plus `Docs/evidence/application-integration-p12/` retain hashed, inspectable artifacts. | E1/E3 use this as a retained public-summary fixture, not as evidence for a newer revision. |
| Portable frontend evidence | `tools/tla-differential/archive.py` verifies semantic/raw hashes, rejects a changing implementation, sanitizes host paths, and copies to a new destination. Checkpoints have `artifact-index.json` and `raw-evidence.tar.gz`. | E2/E3 reuse its bounded-copy, integrity, and non-overwrite patterns; they do not replace its domain report. |
| Gate private receipt publication | `../MirrorGate/integrations/mirrorecma/src/receipt-writer.ts` bounds serialization, writes mode `0600`, fsyncs, publishes through an exclusive hard link, rejects unsafe parents/overwrite, and reports persistence separately. Its default receipt limit is 4 MiB with a 16 MiB maximum. | E1 preserves these receipt semantics. E3 extends them to a multi-artifact envelope/index rather than flattening Gate results. |
| Suite result semantics | `../MirrorECMA/docs/application-suites.md` preserves primary mismatch/cancellation/timeout while reporting cleanup separately. `../MirrorGate/integrations/mirrorecma/WORKFLOW.md` returns trusted receipt, allowlisted public result, local/physical cleanup, and separate persistence evidence. | E1 defines a carrier for these fields. Collectors retain producer-native payloads and status precedence. |
| Capability identity | `../MirrorGate/sdk/compatibility.json`, `tools/ci/versions.env`, and component contracts describe capabilities and pins. `../MirrorGate/docs/compatibility.md` keeps protocol, interface, artifact, runtime, SDK, and private-spec identities distinct. | C2 owns their catalog meaning. E1 records the exact selection and observations for one run. |

Other current summary records with scratch-path references include
`Docs/client-conformance-update-evidence.json`,
`Docs/async-protocol-resource-evidence.json`, and
`Docs/async-resource-lean-evidence.json`. They are E5 inventory inputs; their
presence is not proof that the referenced logs remain available.

## Shared identity and evidence handoff

E1 and C2 must review one vocabulary before either schema is frozen. Planning
drafts may proceed in parallel; B2 reviews the joint contract and B3 assigns its
implementation files.

### Ownership seam

- **C2 owns declarations:** component identity, capability identity, supported
  combinations, and the distinct source/local/hosted/installable/published states.
  A catalog assertion may reference an immutable E1 evidence identity.
- **E1 owns observations:** run identity, selected catalog identity, actual
  component/dirty-tree identities, commands, platform/tools, artifacts, observed
  outcomes, completeness, and retention metadata. An envelope never promotes a
  catalog capability.
- **R1 consumes E1:** a private reproduction bundle cites the originating E1
  `runRef`, uses E1 artifact identities and failure categories, and adds its own
  captured/private inputs, redaction, access, and repeatability rules. E1 public
  projection never inherits R1 private contents.
- **G5 exports through both owners:** recovery/backend support is a C2 capability;
  a particular recovery attempt and its cleanup receipt are E1 run evidence.
  G5 keeps Gate ownership/session/boot identities in its private artifact and
  exposes only the reviewed public projection.

The link is deliberately asymmetric to avoid a digest cycle. An E1 run records
the immutable **input catalog selection** used before execution. A later catalog
revision may cite the finalized E1 bundle by content digest; the old bundle does
not claim that later catalog revision.

### Required references

The joint contract must define these logical records, with final names settled by
C2/E1 review:

- `catalogSelectionRef`: catalog schema/version plus immutable digest or exact
  revision selected before the run;
- `componentRef`: repository/component name, full revision, dirty state, and a
  patch/tree digest when dirty; a dirty checkout is never identified only by HEAD;
- `artifactRef`: media/type, byte size, SHA-256, visibility, and a bundle-relative
  path or external immutable locator; paths are not identities;
- `runRef`: evidence schema/version, opaque run ID, finalized envelope SHA-256,
  and public/private projection kind;
- `producerResultRef`: namespaced producer schema and artifact reference, so the
  envelope need not reinterpret every MirrorECMA/Gate/Mirrors result.

`runRef.envelopeSha256` is computed after finalization and stored by the evidence
store/catalog link that refers to the envelope. The hashed envelope contains its
schema and `runId`, but never its own digest; no self-referential hash is allowed.

Every handoff supplies schema versions, valid fixtures, rejected fixtures, field
ownership, and the downstream validation command. Unknown major schema versions
fail closed; additive minor-version behavior follows the C2/E1 decision rather
than being guessed by a consumer.

### Independent status axes

The envelope carries, but does not collapse, these axes:

| Axis | Minimum normalized states | Rule |
| --- | --- | --- |
| Behavioral/execution | `passed`, `failed`, `inconclusive`, `not_run` plus a namespaced producer classification such as mismatch, timeout, infrastructure error, or required skip | Preserve the producer's native result and primary failure. A cleanup or storage error cannot change the recorded behavioral observation. |
| Cleanup | Per-scope `confirmed`, `failed`, `unconfirmed`, or `not_applicable`; scopes include local cooperative, Gate physical, and later Gate recovery | Never infer physical cleanup from local disposal, cancellation acknowledgement, empty remaining-resource output after a reported cleanup failure, or process disappearance without receipt evidence. |
| Persistence | `complete`, `incomplete`, `failed`, or `not_requested`, with required/optional policy | Only an atomically finalized, verified index is `complete`. A required persistence failure blocks qualification but leaves behavioral and cleanup fields intact. |

Qualification is a derived decision with reasons, not a fourth spelling of the
behavioral result. Required skipped or blocked tiers prevent full qualification;
optional skips remain visible without being converted into passes.

### Public/private boundary and initial local store

Public evidence is generated from a fixed allowlist. It may contain reviewed
component/artifact identities, commands represented by stable command IDs and
sanitized arguments, normalized outcomes, tier status, counts, timestamps, and
public artifact hashes. It excludes credentials, tokens, raw private model or
trace data, expected states, private paths, control handles, arbitrary exception
text, unreviewed stdout/stderr, and R1/G5 ownership secrets. Public canary tests
are required; redacting a serialized private receipt is not an accepted projector.

Private bundles use an owner-only directory and mode-`0600` files. The proposed
developer default is `${XDG_STATE_HOME:-$HOME/.local/state}/mirrors/evidence/v1/`,
overridable with `MIRRORS_EVIDENCE_ROOT`. It is outside `/tmp` and the checkout,
performs no automatic upload, and retains finalized bundles until an explicit
operator action. Tests always supply a disposable `mktemp -d` root. This is a
concrete local default only: deployment storage, retention duration, access
control, signatures, and pruning policy remain B2/operator decisions and must be
resolved before release qualification or hosted claims.

Initial proposed bounds for B2 review are: 4 MiB envelope/index, 16 MiB hard cap
for an inline Gate-compatible receipt, 64 MiB per collected artifact, 512 MiB and
2,048 files per bundle. Exceeding a required limit records persistence
`incomplete`/`failed`; it never truncates an artifact and calls the bundle
complete. Credentials are excluded by construction at every size.

## E1 — Specify the evidence envelope and release profile

Assigned owner: `general-purpose-gpt`. Milestone: M0/M1. Status: **Queued**.

Repo/file scope (proposed; B3 confirms ownership):

- Mirrors: `Docs/durable-evidence-design.md`,
  `tools/evidence/schema/evidence-envelope-v1.schema.json`,
  `tools/evidence/schema/public-summary-v1.schema.json`, and contract fixtures
  under `tools/evidence/fixtures/`.
- Read-only inputs: the baseline files above, C2's schema draft, and Gate/MirrorECMA
  receipt/result contracts. E1 does not edit C2, R1, or G5-owned schemas.

Prerequisites: B1 baseline inventory and draft C2 identity vocabulary. E1 design
may start before B2; schema freeze and implementation wait for B2 review and B3
file allocation.

Deliverables:

1. Specify the records and three status axes above, UTC/monotonic timestamp roles,
   command and environment capture, required/optional tiers, dirty-tree identity,
   unknown-version behavior, and integrity versus provenance/trust claims.
2. Define allowlisted public projection and private envelope schemas with valid,
   rejected, dirty-tree, required-skip, cleanup-failure, persistence-failure, and
   private-canary fixtures.
3. Define release-required artifacts by profile. The initial release profile
   requires exact component/catalog identities, command records, behavioral
   results, all applicable cleanup scopes, public summary, private index, and
   hashes for every required log/receipt; optional raw diagnostics remain labeled.
4. Record the local storage/bounds proposal and leave deployment retention,
   access, and signing explicitly unresolved for B2.

Acceptance tests/commands to exist with the task:

```bash
python3 -m unittest discover -s tools/evidence/tests -p 'test_contract.py'
python3 tools/evidence/validate.py tools/evidence/fixtures/envelope-private.valid.json
python3 tools/evidence/validate.py tools/evidence/fixtures/public-summary.valid.json
```

The contract test must reject a HEAD-only dirty identity, an unknown major
version, a claimed complete bundle with a missing required artifact, a public
private-canary, and any envelope that merges cleanup/persistence into behavior.

Downstream handoff: C2 receives `runRef`/evidence-state semantics; E2/E3 receive
the envelope and bounds; R1 receives the private reproduction seam; G5 receives
cleanup/recovery fields; B2 receives unresolved operator decisions. Completion
means the reviewed contract and fixtures exist, not that any runtime was rerun.

## E2 — Collect existing command evidence without changing command semantics

Assigned owner: `general-purpose-gpt`. Milestone: M1. Status: **Queued**.

Repo/file scope (proposed; split by B3 if companion adapters are needed):

- Mirrors generic collector: `tools/evidence/collect.py`,
  `tools/evidence/commands.json`, and `tools/evidence/tests/test_collect.py`.
- Component-owned adapter manifests only: existing Mirrors `lake test` and interop
  commands; MirrorECMA project/check/test commands; MirrorGate `scripts/test.sh`
  and affected evaluator integration commands. Existing runners and product exit
  handling remain unchanged.

Prerequisites: frozen E1 schema, B2 initial profile, B3 ownership, and each
component owner's exact current gate commands.

Deliverables:

1. Wrap a named existing command, stream stdout/stderr normally, capture bounded
   raw output and exact argv/cwd/timing/exit/signal facts, and record unavailable,
   skipped, blocked, and infrastructure outcomes without treating them as product
   assertions.
2. Preserve the child's exit code/signal. Collection or persistence problems are
   recorded independently; the later qualification command enforces required
   persistence.
3. Capture full component revisions and dirty identities before and after the
   command. A checkout that changes during collection makes the evidence
   incomplete rather than silently selecting either state.
4. Add adapters around existing commands; do not add a competing suite runner or
   change Gate/MirrorECMA outcome precedence.

Acceptance tests/commands:

```bash
python3 -m unittest discover -s tools/evidence/tests -p 'test_collect.py'
python3 tools/evidence/collect.py --store "$MIRRORS_EVIDENCE_ROOT" --command-id mirrors.lake-test -- lake test
```

Focused tests exercise child exits `0` and `7`, signal termination, timeout,
unavailable executable, oversized output, dirty-tree change, collector
interruption, and write failure. The wrapper's observed exit must equal the child
exit in every completed case. Full component gates run only when their owning PR
requires them and their results are retained by E3.

Downstream handoff: E3 receives a staging envelope plus bounded artifacts; E4
receives stable command IDs; R2/F4/G5 may register producer adapters without
changing E2 core. Collector completion is not evidence persistence or release
qualification.

## E3 — Finalize, store, and verify bundles offline

Assigned owner: `general-purpose-gpt`. Milestone: M1. Status: **Queued**.

Repo/file scope (proposed): Mirrors `tools/evidence/store.py`,
`tools/evidence/finalize.py`, `tools/evidence/verify.py`, storage/index schemas,
and `tools/evidence/tests/test_store.py` plus `test_verify.py`. Gate's existing
`receipt-writer.ts` remains Gate-owned and is consumed as a producer.

Prerequisites: E1 and E2; B2 must accept the local profile. Deployment storage is
not a prerequisite for local implementation.

Deliverables:

1. Stage artifacts beneath the selected owner-only evidence root, reject symlink
   traversal/non-regular files/duplicates/limit overflow, hash bytes while copying,
   and create a canonical index containing every artifact and projection.
2. Finalize in the same filesystem with fsync and exclusive, no-overwrite commit
   semantics. A verifier recognizes completion only through the committed index;
   interrupted staging remains explicitly incomplete and is never a pass.
3. Verify schema, canonical index digest, artifact size/hash, required membership,
   catalog-selection syntax, projection kind, and status-axis consistency without
   network access or producer scratch paths.
4. Generate the public summary from its allowlist and verify private canaries are
   absent. State clearly that hashes prove byte integrity, not truthful execution,
   trustworthy signing, or independent provenance.

Acceptance tests/commands:

```bash
python3 -m unittest discover -s tools/evidence/tests -p 'test_*.py'
python3 tools/evidence/verify.py --offline /path/to/finalized-bundle
```

Tests remove the producer scratch directory before offline verification and
cover missing/truncated/changed artifacts, index tampering, symlink and traversal
attempts, destination collision, interruption before/after index publication,
oversize/file-count limits, unknown schema, public canaries, and owner permissions.

Downstream handoff: E4 receives immutable `runRef` and verified public summary;
R2 stores private reproduction artifacts through this API; G5 stores recovery
receipts without exposing ownership secrets; Q2 consumes the installed offline
verifier. E3 does not choose deployment retention or delete stored bundles.

## E4 — Bind catalog claims and release candidates to retained evidence

Assigned owner: `general-purpose-gpt`. Milestone: M1/M5 integration. Status: **Queued**.

Repo/file scope (proposed; C3/B3 must assign shared files): Mirrors catalog
evidence-link adapter and qualification profile under `tools/evidence/`, catalog
link fixtures, and generated public evidence references. C2/C3 retain ownership
of the catalog schema and generator; release-candidate manifests remain their own
artifacts rather than being embedded into E1.

Prerequisites: C2 identity contract, C3 catalog validation entry point, E3
finalization/verifier, exact candidate component pins, and B3 ownership.

Deliverables:

1. Validate catalog evidence links by E1 schema/version and finalized envelope
   digest. A missing, private-only, incomplete, stale, or wrong-combination bundle
   cannot support a public capability state.
2. Create a release-evidence profile that lists required command IDs/artifact
   kinds and evaluates required skips, cleanup scopes, persistence, and exact
   companion identities without rewriting their underlying results.
3. Bind each release candidate to immutable retained bundle references. A later
   HEAD, rerun, or regenerated catalog receives new references; it never inherits
   a historical pass by path or label.
4. Produce deterministic public links/summaries while access-controlled private
   locators remain outside the public catalog.

Acceptance tests/commands:

```bash
python3 -m unittest discover -s tools/evidence/tests -p 'test_catalog_links.py'
python3 tools/evidence/verify.py --offline --catalog /path/to/catalog.json --profile release-candidate /path/to/finalized-bundle
```

Fixtures must reject a digest mismatch, different component SHA, dirty-state
mismatch, required skipped tier, unconfirmed required cleanup, persistence
failure, missing public projection, and evidence assigned to a newer catalog
selection. Deterministic generation is checked twice from identical inputs.

Downstream handoff: C4/C5 receive validated evidence states; I2/I3 receive exact
artifact references; Q1 selects the release profile; Q2 verifies it independently.
E4 links evidence but does not publish a package, claim hosted CI, or deploy it.

## E5 — Record unavailable historical artifacts without rewriting history

Assigned owner: `general-purpose-gpt`. Milestone: M1. Status: **Queued**.

Repo/file scope (proposed):

- `Docs/evidence/historical-artifact-availability.json` as an additive sidecar
  keyed by source record, JSON pointer, original locator, and recorded hash;
- explanatory links/wording in `Docs/application-integration-progress.md`;
- verifier fixtures/tests under `tools/evidence/`;
- read-only inventory of the four current scratch-referencing evidence JSON files
  listed in the baseline. Editing an original historical record requires a
  separately reviewed compatibility decision; the default is a sidecar so its
  original bytes and claims remain intact.

Prerequisites: E1 availability vocabulary and E3 verifier. E5 does not require a
runtime rerun. E4 consumes only finalized retained bundles, never these markers.

Deliverables:

1. Inventory every scratch/external reference in the scoped records and classify
   it as retained-and-verified, unavailable-at-audit, external-with-policy, or
   unverified. Record audit time/method without asserting when an absent file was
   lost.
2. Mark the known missing application aggregate logs and local receipts as
   unavailable historical provenance while preserving their original paths,
   hashes, source revisions, and recorded behavioral claims.
3. Teach verification/reporting that a hash-only unavailable marker is not a
   retained artifact, fresh verification, or release-qualifying evidence. A
   historical summary remains historical even if its source currently passes.
4. Document the remediation path: a new run creates a new E1 bundle and run ID;
   it never fabricates an old log, copies unrelated output under the old hash, or
   changes an old date/identity to `fresh`.

Acceptance tests/commands:

```bash
python3 -m unittest discover -s tools/evidence/tests -p 'test_historical.py'
python3 tools/evidence/verify.py --historical-index Docs/evidence/historical-artifact-availability.json
```

The test enumerates all scoped `/tmp` references, requires an explicit availability
row, verifies retained artifacts when present, and reports unavailable rows as
non-qualifying without failing merely because history is honestly incomplete. It
also rejects duplicate pointers, changed recorded hashes, a `fresh` label, or a
claimed retained artifact with no bytes. Documentation link and JSON syntax checks
must pass; no runtime gate is rerun for this migration.

Downstream handoff: E4/C5 receive explicit non-qualifying historical states; Q3
can report evidence gaps accurately; future reruns create new E1/E3 bundles. E5
completion closes the inventory gap, not the missing historical artifacts.

## Implementation order and card completion

1. Draft E1 and C2 in parallel, review the seam in B2, and let B3 allocate shared
   files.
2. Implement E2 collection and E3 storage/verifier as separate changes; exercise
   them first with fixture commands, then existing component gates.
3. Implement E4 only after both catalog and bundle validators are stable.
4. Implement E5 without waiting for a rerun; new verification is always a new
   bundle and identity.

Each implementation PR reports owned files, exact companion SHAs/dirty state,
commands run, required/optional skips, persisted bundle identity, and blocked
tiers. All five cards remain queued until separately assigned for implementation;
the planning artifact itself establishes no runtime, cleanup, persistence, CI,
installation, publication, or release claim.
