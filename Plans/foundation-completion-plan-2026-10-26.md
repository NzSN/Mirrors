# Foundation completion plan

Date: 2026-10-26

Baseline: Mirrors `fe86ec03e8bcd557ac8561321fda3b5141af5dff`

Status reconciliation (2026-10-29): this original design is retained below.
[The current execution plan](completion-execution-plan-2026-10-29.md) and
[its evidence](completion-evidence-20261029/README.md) supersede the old queue:
immutable artifact acquisition and journal-v2 recovery source work are already
implemented; finite F5 comparison and profile-6 qualification now have new scoped
acceptance. Current framework/platform qualification and release/deployment
remain separately tracked. This plan alone grants no qualification.

## Execution rules

Every implementation change creates a new candidate identity. Previous M5,
DPM, and differential evidence remains revision-specific. Freeze exact source,
tool, package, runtime, and evidence identities for each acceptance campaign.
Failed, incomplete, and skipped required tiers never become passes.

Run live model operations through the Mirrors CLI against the selected owned
remote service after reobserving its endpoint, binary, runtime, and certificate
identities. Run differential frontend tools only on a separately admitted host.
Do not start local Apalache or TLC on this coordinator.

Preserve dated evidence and historical approvals. Record new results in new
directories rather than rewriting prior receipts.

## 1. Immutable toolchain acquisition

**Goal:** reproducible inputs that cannot silently change upstream.

Contract: [TLA+ differential validation](../tools/tla-differential/README.md).

1. Inventory SANY, Apalache, JDK, launcher, and standard-library identities.
2. Add an operator-approved content-addressed artifact store keyed by SHA-256.
3. Extend acquisition to support an explicit offline/cache source without
   ambient-PATH fallback.
4. Preserve build revision, release URL, artifact hashes, and derived library
   hashes in the lock.
5. Retain old locks and evidence unchanged.
6. Add tests for missing artifacts, truncation, hash mismatch, partial
   download, cache refusal, and offline restoration.

**Exit criteria**

- A fresh empty cache restores the exact pinned toolchain from the immutable
  source.
- Subsequent verification works without network access.
- Mutated or unavailable artifacts fail closed.
- No large binaries enter Git without an explicit separate decision.

## 2. Frontend profile-6 qualification

**Goal:** establish semantic confidence in the SANY/`Bags` migration.

Contracts: [language profile](../Docs/model-interface-compiler/tla-language-profile.md)
and [differential validation design](../Docs/model-interface-compiler/tla-differential-validation-design.md).

1. Freeze the candidate source, profile, corpus, catalog, registry, and
   toolchain hashes.
2. On an admitted Java 25.0.4+7 host, run two independent required differential
   campaigns using fresh output directories.
3. Cover all 61 fixtures and all Mirrors/SANY/Apalache observations.
4. Compare semantic reports for determinism and check executable/source hashes
   before and after each run.
5. Investigate every disagreement: repair defects, retain documented resource
   limits, or add a narrowly scoped reviewed difference with exact source and
   engine pins.
6. Archive the runs and populate the profile-6 registry only from reviewed
   observations.

**Exit criteria**

- All required observations complete.
- No unresolved findings remain.
- Independent runs produce identical semantic payloads.
- Profile-5 approvals remain historical and are never automatically renewed.

## 3. Exact-candidate end-to-end qualification

**Goal:** prove the actual source, packages, and deployed binaries rather than
only the source tree.

References: [October 25 qualification](completed/current-source-qualification-2026-10-25.md),
[remote server guide](../Docs/remote-server-guide.md), and
[interop instructions](../tools/interop/INTEROP.md).

1. Freeze full SHAs for Mirrors, MirrorECMA, MirrorGate, MirrorCPP, and
   MirrorRust, including any dirty-content identities.
2. Build from a clean checkout and record binary/package hashes.
3. Run the complete no-model gate with ext4 `TMPDIR`, the full Windows
   `lake test`, repaired model-interface suites, native integer-map coverage,
   and rebuilt DPM launcher plus three-profile installed acceptance.
4. Reobserve the remote endpoint, certificate, server binary, Apalache, and
   Java identities.
5. Run the current M5 command/tier inventory: installed correct/faulty replay,
   mismatch and mutation campaigns, prefix/domain reduction, live model
   checks, the full cross-client matrix, and prepared-filesystem recovery.
6. Test Windows service stop/start and reboot behavior.
7. Verify retained evidence independently offline, including malformed and
   missing-link controls.

**Exit criteria**

- Every required tier passes against one frozen candidate.
- No required tier is hidden as an optional skip.
- Independent Q1/Q2-style verification succeeds.
- Results are explicitly labeled local-candidate, not production acceptance.

## 4. M4 ownership and recovery

**Goal:** safe aggregate resource enforcement and descendant recovery.

Contract: [M4 acceptance and platform progression](m4-native-host-and-platform-plan-2026-10-07.md).

1. Design a versioned journal extension binding each process to its exact
   delegated cgroup resource identity.
2. Keep v1 process records ambiguity-only; never infer ownership from PID or
   path text.
3. Implement revalidation of boot, principal, session, cgroup inode, and
   delegation before recovery actions.
4. Record cleanup only after the owned subtree is confirmed empty.
5. Add unit and fault-injection tests for stale identities, PID reuse, torn
   writes, concurrent recovery, and retries.
6. On a native Linux host with an operator-owned cgroup-v2 delegation, run
   CPU/memory/PID quota readbacks, descendant enforcement and escape refusal,
   abrupt controller termination, administrative recovery and filesystem
   cleanup, and wrong-principal/session/boot plus unrelated-sentinel controls.

**Exit criteria**

- Owned descendants and resources are reclaimed safely.
- Ambiguous or unrelated processes/files survive untouched.
- Aggregate limits apply to the whole descendant tree.
- Exact native-host evidence supports only the tested profile.

## 5. F5 C++ model comparison

**Goal:** turn the controlled mutex/FIFO prototype into a verified scheduling
profile.

Contracts: [approved DPM usability features](dpm-usability-features-2026-10-07.md)
and [runner contract](../Docs/dpm-runner-contract.md).

1. Define the finite model: actors, mutex ownership, FIFO state, callbacks,
   joins, cleanup, and terminal states.
2. Specify the mapping from native receipts to model actions and observations.
3. Validate the model independently through the selected remote model-checking
   path.
4. Execute matching and deliberately mismatching schedules under explicit
   finite bounds.
5. Test callback/join deadlines, cancellation, late cleanup, and output-budget
   accounting.
6. Reduce counterexamples and replay the reduced result freshly.

**Exit criteria**

- Real executions match the model across the declared finite profile.
- Deliberate deviations are detected.
- Cleanup and deadline failures remain non-passing.
- Only then change `modelComparison` to `true`.

## 6. Compatibility lifecycle

**Goal:** retire legacy behavior without breaking supported clients.

Contract: [Haskell cutover](../Docs/cutover.md).

1. Inventory remaining Haskell/stdio async error-tag consumers.
2. Publish the compatibility contract, migration path, and deprecation
   measurements.
3. Run the documented soak while preserving exact wire bytes and supported
   fallbacks.
4. Add consumer evidence that supported clients no longer depend on legacy
   behavior.
5. Remove or disable the legacy path only after the stated criteria are met.
6. Run codec goldens and the cross-client compatibility matrix again.

**Exit criteria**

- Deprecation criteria are demonstrated, not merely elapsed.
- Supported clients have a verified migration path.
- Removal introduces no unreviewed wire or schema change.

## 7. Release and controlled deployment

After items 1–3, prepare the release. M4 and F5 may remain separately scoped
roadmap capabilities and must not be advertised as accepted.

Contract: [ecosystem versioning](../Docs/ecosystem-versioning.md).

1. Select the version under the ecosystem compatibility policy.
2. Run focused release tooling and build reproducible archives.
3. Create an immutable tag and verify hosted assets and hashes.
4. Stage the exact release on Windows and repeat live positive/negative
   checks.
5. Preserve the previous binary and configuration for rollback.
6. Perform controlled service replacement and reboot verification.
7. Record deployment evidence separately from framework qualification.

## Recommended order and boundaries

Execute **immutable toolchain → profile-6 qualification → exact-candidate
qualification → release**.

M4 and F5 are independent architectural tracks. They need not block a
compatible release whose documented scope excludes them, but each remains
unaccepted until its own gates pass. Windows/macOS Gate backends, arbitrary
instruction preemption, browser or async-Rust scheduling, weak-memory
completeness, POR, and generic native-trap instrumentation are not implicitly
added by this plan.
