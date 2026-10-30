# Completion, qualification, and release design

Date: 2026-10-30

Status: proposed design for the remaining completion campaign. Existing source
behavior and dated acceptance records are unchanged. This document does not
authorize a branch push, tag push, package publication, production deployment,
or machine reboot.

Scope revision, October 30: the user removed native-runner/M4 execution work
from this campaign and selected the observed Ubuntu 26.04.1 WSL2 coordinator
for S3.6 and S5. This is a distinct WSL2 qualification scope, not Ubuntu 24.04
qualification. Stage IDs S5-S8 remain stable for existing evidence references.

The executable task breakdown is in the
[October 30 execution plan](../Plans/completion-qualification-release-plan-2026-10-30.md).
The original campaign and its bounded results remain in the
[October 29 plan](../Plans/completion-execution-plan-2026-10-29.md) and
[evidence record](../Plans/completion-evidence-20261029/README.md).

## 1. Purpose and scope

This design covers every remaining stage from the current uncommitted
`v0.2.0-rc.1` candidate through source delivery, package construction,
exact-candidate framework qualification, release admission, publication,
deployment, rollback, reboot acceptance, and the longer compatibility
lifecycle.

It does not reopen completed work without cause. The following already have
scoped acceptance at their recorded identities:

- finite F5 controlled mutex/FIFO comparison and reduction over the two
  declared policies;
- independent profile-6 T/U differential campaigns with identical semantic
  payloads;
- source-hidden, network-isolated installed C++/ECMA/Rust DPM acceptance with
  `freshModelCheck:false`;
- the 22-row five-client mTLS matrix;
- local non-model and native-rebuild gates, eight selected native Windows
  suites, and the selected MirrorGate required gate;
- repeatable packaging of the selected Windows RC binaries.

These results are inputs, not blanket qualification for a later commit, a
different host, an arbitrary program, native cgroup enforcement, a published
release, or a deployed service.

### Non-goals

- arbitrary-program scheduling, arbitrary instruction preemption, weak-memory
  completeness, POR, browser or async-Rust scheduling, and generic native-trap
  instrumentation;
- a Windows or macOS Gate backend, which requires a separately reviewed
  isolation and ownership contract;
- local Apalache or TLC execution on the WSL2 coordinator;
- retirement of stdio `register_error` or the Haskell oracle in this candidate;
- treating a new Git ref, product version, service PID, or service status as
  proof of behavioral or platform acceptance.

## 2. Normative contracts

The stage implementations must follow the existing contracts rather than
creating a parallel qualification or packaging format:

| Area | Contract |
| --- | --- |
| Evidence identity, collection, and retention | [Durable evidence](durable-evidence-design.md) and [evidence tools](../tools/evidence/README.md) |
| M5 commands and linked Q1/Q2 | [Qualification harness](qualification-harness-design.md) |
| Reference platform and installation | [Reference distribution](reference-distribution-profile.md) and [activation transaction](../distribution/reference-node/activation-transaction.md) |
| Remote oracle and service operation | [Remote server guide](remote-server-guide.md) and [interop instructions](../tools/interop/INTEROP.md) |
| Release identity and Linux assets | [Versioning](versioning.md), [release workflow](../.github/workflows/release.yml), and [release tooling](../tools/release/release.py) |
| F5 comparison boundary | [Controlled model comparison](dpm-controlled-model-comparison.md) |
| Compatibility retention and retirement | [Compatibility decision](../Plans/compatibility-lifecycle-decision-2026-10-29.md) |

If a stage needs a new receipt shape, it must use a new versioned schema. An
existing producer result keeps its own semantics; wrapping it in an evidence
envelope does not broaden the result.

## 3. Claim and state model

### 3.1 Claim levels

Each stage emits exactly the strongest claim supported by its observations:

| Claim | Meaning | Explicitly not implied |
| --- | --- | --- |
| `source-validated` | Named source and non-model gates passed | Installed, live-model, native, or release acceptance |
| `scoped-accepted` | A declared finite profile passed at exact identities | Arbitrary inputs, other hosts, or a later source candidate |
| `platform-qualified` | All required tiers of the selected platform profile passed | Other platforms, hosts, or profiles |
| `release-admitted` | A concrete artifact set and its qualification limits passed review | Public availability or production deployment |
| `published` | Remote immutable tag and release assets were reobserved | Production health or service lifecycle |
| `deployed` | The selected production bytes were replaced and checked | Reboot persistence or future health |
| `lifecycle-accepted` | Stop/start and the separately approved reboot checks passed | Other service configurations or hosts |

Execution states are `not-started`, `awaiting-external-input`, `admitted`,
`executing`, `passed`, and `failed`. A diagnostic or partial run may be
retained, but only a complete required run reaches `passed`.

### 3.2 Candidate identities

A candidate record binds the following namespaces independently:

1. **Source:** full Mirrors commit and tree, every companion commit, and any
   explicitly admitted dirty-content digest. Public release construction uses
   a clean tagged checkout, not a HEAD-only dirty identity.
2. **Contract:** catalog/profile selection, generated-interface locks, model
   and corpus hashes, compatibility rules, and receipt schemas.
3. **Toolchain:** Lean/Lake, C compiler, Java, SANY, Apalache, Node, Python,
   Haskell toolchain, OpenSSL, and native build dependencies, using the exact
   identities required by each producer.
4. **Artifact:** executable, DLL, package, archive, manifest, cache index, and
   checksum bytes. Reproducible packaging of unchanged binaries is not a claim
   of reproducible compilation.
5. **Host:** actual OS release, architecture, kernel/virtualization class,
   filesystem, libc, runtime libraries, cgroup delegation, and permissions.
   The declared target never supplies an observed host fact.
6. **Deployment:** endpoint, owned process, server executable, Apalache/JAR,
   Java executable, certificate chain/leaf pin and validity, fixture root, and
   service configuration. Historical PIDs and certificates are not current
   observations.
7. **Evidence:** run ID, finalized envelope, public projection, artifact
   inventory, dependency edges, cleanup result, and independent verification
   result.

The release key is the tuple of source, contract, artifact, and selected
qualification profile. A product-version string is only one field.

### 3.3 Invalidation rules

| Change | Required consequence |
| --- | --- |
| Behavioral source, compiler, model, corpus, or companion change | New candidate; rerun every affected source, installed, remote, and downstream gate |
| Catalog, distribution lock, toolchain, Java, SANY, or Apalache pin change | Re-admit the affected profile and rerun all dependent producers and Q verification |
| Package recipe or binary change | Rebuild and recheck archives, installation, artifact bindings, and deployment payload |
| Packaging-only change with identical binaries | Rerun archive/install checks; source test evidence remains bound to its original identity and is not broadened |
| Host, cgroup parent, filesystem, or runtime-library change | Re-admit that host and rerun host-dependent acceptance |
| Endpoint, certificate, server, backend, or fixture change | Obtain fresh before/after observations and rerun affected remote producers |
| Evidence-only correction | Preserve original bytes, add a corrective record, and rerun the relevant verifier; do not rewrite a receipt |
| Product version or tag name change | Return to source freeze and construct a new clean tagged candidate |

A new commit after dirty-tree qualification does not inherit that
qualification automatically. The execution order below therefore establishes
the immutable source candidate before the final exact-candidate campaigns.

## 4. Stage architecture

```text
S0 baseline intake
  -> S1 final source/evidence freeze
  -> S2 audited branch publication
  -> S3 clean tagged package construction
       -> S5 exact-candidate platform/framework qualification
       -> S6 release admission and concrete handoff
       -> S7 approved publication, deployment, and reboot checks
       -> S8 retention and compatibility lifecycle
```

S6 may prepare a scoped prerelease handoff while an unrelated external tier is
pending, but it must label that tier absent. A full-scope release claim
requires every selected required stage to pass.

## 5. Detailed stage designs

### S0. Baseline and evidence intake

**Inputs.** Published Mirrors `7e9a27d`, the current completion working tree,
companion source identities, October 29 evidence, and existing release/service
records.

**Procedure.**

1. Inventory tracked, untracked, ignored, and evidence paths without resetting
   or cleaning the shared checkout.
2. Classify existing receipts as accepted, failed, incomplete, skipped, or
   historical. Preserve their bytes and original claim limits.
3. Reobserve coordinator OS/kernel/filesystem facts and bind the selected
   Ubuntu 26.04.1 WSL2 execution scope to actual observations.
4. Confirm the selected F5/profile-6/DPM/matrix evidence verifier and inventory
   cover the intended candidate. Do not treat absent files as skips.
5. Assign each outstanding obligation to S1-S8 and record its dependency.

**Exit gate.** Every remaining obligation has an owner role, input identity,
evidence destination, and exit criterion. No new acceptance is granted by S0.

### S1. Final source and evidence freeze

**Procedure.**

1. Review the complete diff, including new controlled-model code, TLS changes,
   installer observation changes, compatibility documents, and all evidence
   inventory members.
2. Run `git diff --check`, the current campaign
   `Plans/completion-evidence-20261029/verify.py`, relevant focused tests, and
   the final local non-model/native gates required for the changed source.
3. Regenerate the campaign inventory after the last intended evidence change;
   run the verifier again. Check that every intended evidence file is actually
   tracked or explicitly selected for delivery despite an ignore rule.
4. Scan the delivery payload for private keys, certificates with private
   material, credentials, tool archives, compiled binaries, and unbounded logs.
5. Record exact source/companion/tool identities, test outcomes, required
   skips, and externally blocked stages in a new freeze receipt.
6. Stop source edits. Any later behavioral edit returns to S1 and invalidates
   affected results.

**Exit gate.** The complete working-tree selection is reviewable and internally
consistent; all local required checks pass; every external gap is explicit.

### S2. Audited branch publication

Branch publication creates an immutable source input for final qualification.
It is not a release tag or deployment.

1. Present the exact file list, source diff, validation snapshot, exclusions,
   and proposed commit to the user.
2. After explicit branch-publication approval, stage only that list. Compare
   staged blob hashes with the reviewed bytes and repeat the credential scan
   on the staged payload.
3. Commit and push `main`; verify the remote full SHA and local/remote
   divergence. Preserve unrelated working-tree files.
4. Write a delivery audit containing the commit, tree, remote ref, payload
   hashes, and excluded paths. Publication does not alter earlier evidence.

**Exit gate.** The remote branch names the audited commit and a clean checkout
can reproduce its source identity. Any subsequent source commit starts a new
candidate for final qualification.

### S3. Clean tagged package construction

The standard Linux release builder requires a clean checkout at an existing
tag whose version matches `Shell/Version.lean`. Candidate preparation therefore
uses a local-only tag after the exact tag name and commit are approved. Do not
push that tag during package preparation: the current tag-push workflow can
publish the GitHub release automatically after its gates.

**Linux.**

1. Create a clean checkout of the S2 commit and a local `v0.2.0-rc.1` tag, or
   return to S1 if a different version is selected.
2. Run the release tooling unit tests and
   `tools/release/release.py build` into an empty artifact directory.
3. Verify `SHA256SUMS`, external and embedded build manifests, source/tag
   identity, executable versions, dynamic dependencies, and archive membership.
4. Run `check-archive` in the selected Ubuntu 26.04.1 WSL2 environment without
   Lean or source lookup in the packaged runtime path. Record this WSL2 scope
   explicitly. Keep the DPM CLI outside this archive, as the existing release
   contract specifies.
5. Record that these are focused non-model package gates, not live-model or
   framework qualification.

**Windows.**

1. Compare the staged archive's base-plus-overlay executable inputs with the
   S2 tree. Reuse the archive only for a reviewed non-behavioral difference
   with identical build inputs; otherwise rebuild and rerun affected gates.
2. Recheck the ZIP hash, executable/DLL hashes, expected version, packaging
   repeatability, and absence of credentials.
3. Do not convert identical packaging into a reproducible-compilation or full
   Windows `lake test` claim.

**Exit gate.** A versioned package-set manifest binds every artifact to the S2
commit, its build inputs, runtime prerequisites, test scope, and checksum.

### S5. Exact-candidate platform and framework qualification

S5 binds the S2 source and S3 artifacts to fresh installed and remote evidence.
Earlier October 29 results support review but do not replace a required fresh
producer when the exact selected identity differs.

#### S5-A. Admission and distribution bindings

1. Select the observed Ubuntu 26.04.1 WSL2 coordinator, including its actual
   kernel, filesystem, libc, runtimes, and permissions. Name this WSL2 profile
   in every receipt; do not claim Ubuntu 24.04 or native-Linux acceptance.
2. Freeze Mirrors and companion full SHAs/dirty policy, C0 catalog selection,
   distribution locks, package/cache bytes, and toolchain/runtime identities.
3. Build or install from the clean candidate in owner-only staging. Hide source
   checkouts and disallow ambient `PATH` or network dependency restoration.
4. Complete both required D audits before producers that consume those exact
   installations. Retain actual host and package observations, not catalog
   target literals.
5. Reobserve the selected remote endpoint, certificate validity/pin, owned
   server process, server binary, Apalache archive/JAR, Java executable, and
   fixture root before contact. Never export an existing remote private key.

#### S5-B. Required producer campaigns

1. Execute the complete selected 18-command/16-tier M5 inventory from
   `tools/evidence/commands.json`; no required row may become an optional
   skip.
2. Include source and companion gates, installed correct/faulty replay, both
   reproduction branches, domain and prefix reduction with original-input
   linkage, local/Gate mutation campaigns, prepared-filesystem recovery,
   remote model validation, and the complete selected five-client matrix.
3. Preserve the explicit installed DPM `freshModelCheck:false` limit. Where
   fresh model comparison is claimed, require actual remote model-valid and
   model-invalid semantic controls.
4. On Windows, run full `lake test` and the required native integer-map and
   model-interface tiers against the exact candidate. The previous eight-suite
   result remains only a focused input.
5. Run all model operations through the Mirrors CLI against the reobserved
   selected remote service. Do not start a local model checker on the WSL2
   coordinator.
6. Confirm server/backend/job cleanup after each owned campaign and recheck
   production source/runtime bytes where an isolated fixture was used.

#### S5-C. Linked and independent verification

1. Finalize each producer independently and construct the acyclic C0 -> D ->
   R0 -> R1 -> Q graph with exact run and artifact references.
2. Run linked Q1 over the complete required scope. Reject duplicate command
   credit, missing/tampered artifacts, wrong D bindings, wrong R0/R1 origin,
   wrong R1/R5 reduction input, mixed catalogs, and incomplete profiles.
3. Run independent installed Q2 with source/producer scratch hidden, network
   unshared, and archive inputs read-only. Verify all selected finalized
   bundles and both exact D bindings.
4. Execute actual missing, changed-byte, wrong-binding, wrong-origin,
   wrong-linkage, and incomplete-profile controls. A validator that accepts a
   negative control fails the campaign.
5. Repeat offline verification from the retained verifier/runtime after the
   oracle is stopped; require a byte-identical acceptance result.

**Exit gate.** One frozen candidate passes all required selected tiers, Q1 and
independent Q2, with complete retention and no required skip. Platform scope
and all exclusions are named explicitly.

### S6. Release admission and concrete handoff

1. Assemble the package-set, source-delivery, S5, compatibility, and negative
   control receipts into one release-claim matrix.
2. Choose the release scope. If a tier is excluded, the release notes and
   handoff must state that exclusion; a scoped prerelease must not claim
   unexecuted qualification.
3. Confirm tag/version/source equality, immutable artifact hashes, runtime
   prerequisites, known limitations, upgrade path, and retained previous
   production bytes.
4. Prepare release notes distinguishing new F5 capability, runtime fixes,
   compatibility retention, qualification evidence, skipped/out-of-scope
   work, and installation requirements.
5. Prepare separate operational requests for branch/tag publication, GitHub
   release publication, Windows asset publication if selected, production
   replacement, and reboot. Each request names the exact payload and host.
6. Have the independent verifier check the handoff inventory and ensure no
   private material or unreviewed artifact is included.

**Exit gate.** The user can approve or reject a concrete, immutable operation
with known effects. No public or production mutation occurs at S6.

### S7. Approved publication, deployment, and lifecycle checks

#### Publication

1. Reobserve the remote source commit and confirm no existing tag, release, or
   draft will be overwritten.
2. After explicit approval that includes its publication effect, push the
   selected immutable tag. The release workflow tests tooling, rebuilds the
   clean tag, checks the Ubuntu 24.04 archive in isolation, verifies remote
   identity, creates a draft with all Linux assets, and publishes it.
3. Reobserve the peeled tag commit, release assets, checksums, prerelease/
   Latest flags, and generated notes. Investigate any partial draft rather
   than overwriting it.
4. Publish the Windows ZIP only if separately selected and approved; the
   existing Linux workflow does not automatically include it.

#### Staged deployment and rollback

1. Reobserve current production service, configuration, executable/dependency
   hashes, runtime, credentials metadata, and listener. Historical deployment
   receipts do not establish current health.
2. Start the candidate on an isolated candidate port with owned fixtures.
   Require synchronous/asynchronous valid and invalid mTLS controls and the
   selected client/protocol checks; confirm candidate cleanup.
3. Retain a hash-verified rollback executable and dependencies. Stage the new
   files beside the active paths and verify their hashes before stopping the
   service.
4. After explicit production approval, use a hash-guarded stop/replace/start
   transaction that preserves service configuration and automatically restores
   the previous bytes on failure.
5. On the production endpoint, require the four sync/async valid/invalid
   controls, expected TLS chain/pin, backend identity, installed hash, automatic
   start configuration, and no unexpected test processes.
6. Roll back on hash mismatch, service failure, positive-check failure,
   acceptance of a negative control, backend/configuration drift, or incomplete
   ownership/cleanup. Verify rollback with the same live controls; a rollback
   does not convert the failed deployment into a pass.

#### Reboot acceptance

Reboot is a separate explicitly approved operation. After reboot, observe
automatic service start, installed and dependency hashes, endpoint and
certificate identity, backend availability, and the same four live controls.
Stop/start success without reboot does not earn reboot acceptance.

### S8. Retention and compatibility lifecycle

1. Finalize public and private evidence inventories, access controls, artifact
   retention, rollback retention, and post-deployment observations.
2. Keep stdio `register_error`, golden bytes, the pinned Haskell oracle, and
   all supported clients unchanged in this candidate.
3. For each shipped release cycle, retain independent green matrices for every
   declared consumer/transport row, including Rust and async error-tag
   controls. Required skips reset admission.
4. Maintain a dated real-workload soak ledger for Lean and Haskell with
   workload hashes, run counts, byte comparisons, accepted differences,
   failures, incidents, and resolutions. Calendar time alone earns no credit.
5. After two consecutive qualifying shipped cycles, require zero unresolved
   wire-divergence reports, named consumer migration acknowledgements, and
   verified fallback/rollback before proposing deprecation.
6. Any removal still needs a reviewed notice, migration guide, separate
   compatibility release, fresh goldens/matrix, and historical oracle
   retention.

## 6. Evidence and security invariants

- Retain initial failures and successful retries as different attempts. A retry
  never rewrites the original receipt.
- Use fresh run IDs and output directories. Finalization is index-last and
  never overwrites an existing run.
- Keep private evidence owner-only; public projections contain allowlisted
  metadata, not credential contents or private dependency graphs.
- Credentials stay in operator-selected paths outside Git. Public CSRs,
  certificates, fingerprints, and hashes may cross hosts; existing remote
  private keys do not.
- Bound subprocess arguments, output, deadlines, retained files, and descendant
  cleanup. Preserve child exit/signal and cleanup outcomes independently.
- Execute no artifact whose required hash or source identity failed admission.
  Inspecting a refused carrier does not make it selected or executable.
- Source-hidden and network-isolated installed checks must not fall back to a
  checkout, global package, ambient tool, or catalog-target fiction.
- Preserve unrelated user files and all dated evidence. Never reset or clean a
  shared dirty worktree to obtain a candidate.

## 7. Release handoff contents

The concrete handoff must contain:

1. proposed operation and exact approval boundaries;
2. Mirrors and companion commits, tree/dirty identities, catalog/profile and
   toolchain selections;
3. tag/version and every archive, executable, DLL, manifest, and checksum hash;
4. a stage-by-stage claim matrix with required skips and external exclusions;
5. Q1/Q2 and negative-control references, plus the exact WSL2 platform scope;
6. installation/runtime prerequisites and known compatibility limits;
7. current production inventory, staged candidate checks, and service
   configuration to preserve;
8. stop/replace/start, automatic rollback, post-deployment verification, and
   optional reboot steps;
9. retention locations, public/private classification, and cleanup status.

An approval for one operation does not authorize the others. In particular,
approving a branch push is not approval for a tag push, and approving a tag
push under the current workflow includes its automated GitHub release
publication effect.

