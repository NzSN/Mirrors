# Immutable toolchain acquisition tasks

Date: 2026-10-26

Baseline: Mirrors `fe86ec03e8bcd557ac8561321fda3b5141af5dff`

Status: implementation task record; no qualification is granted by this
document.

## Objective

Restore the reviewed TLA+ differential toolchain from content-addressed bytes,
without relying on a mutable release URL, ambient tool discovery, or network
access during ordinary verification. A version label selects a release; the
SHA-256 pin identifies the exact artifact bytes.

## Scope

In scope:

- the SANY and Apalache release archives used by the differential gate;
- an explicit, operator-selected SHA-256 artifact store;
- offline restoration into the ignored local toolchain directory;
- fail-closed validation of missing, truncated, changed, or partially written
  artifacts; and
- documentation and focused regression coverage for the acquisition contract.

Out of scope:

- acquiring or replacing the operator-selected JDK;
- committing large tool archives to Git;
- changing corpus expectations, profile approvals, or the lock's SANY pin;
- running local Apalache/TLC model operations; and
- claiming a new frontend or end-to-end qualification.

## Identity inventory

The lock retains release provenance, archive identity, extracted launcher
identity, and the derived standard-library identity. The current pins are:

| Component | Identity |
| --- | --- |
| SANY archive | `tla2tools-1.8.0.jar`, SHA-256 `d15655eeaff4b3f7b3d65c46b838bc0f35d131b2ef4b1e473689b62c98d4726f` |
| SANY build | revision `2ef2af8c767b76e5db5cba2878f027ac07aad36c`, recorded build timestamp `2026-10-24T01:36:19.357Z` |
| SANY standard library | SHA-256 `fc1e01131317e322a90eb5534fc217f6a1b64df8de540d949255eaa7d8ff88ad` |
| Apalache archive | `apalache-0.61.0.tgz`, SHA-256 `68fb56dd9d053cf21d692fd7ec3fbaaeba1395661ec7434fa2b4c47e6fc432b8` |
| Apalache build | revision `831d473` |
| Apalache extracted JAR | SHA-256 `33611081942d392646af60993c599907f1f41752fce4a62304dbf9e2cdad4346` |
| Apalache launcher | `bin/apalache-mc`, SHA-256 `71e0733e2a88b185ed073c3e8dd3044a320cbcabfbaa043a196692d49ed2b03a` |
| Apalache standard library | SHA-256 `b8e3930442b5eb78940e44996c1cf577c1c1d152a49fbeec001e1f8aa927e094` |
| JDK | OpenJDK `25.0.4`, build `25.0.4+7`, operator-supplied and checked by version/build; not downloaded by this tool |

## Storage and CLI contract

The artifact store is selected only by an explicit `--artifact-store DIRECTORY`
argument. Its object path is `sha256/<lower-case-sha256>`; the digest from the
lock, not an ambient filename, is the object identity. A store is not read from
an environment variable, repository sibling, package cache, or `PATH`.

Commands:

```sh
# Verify the installed toolchain. No network and no store are used.
python3 tools/tla-differential/acquire.py

# Populate from locked release URLs only if required, optionally caching every
# verified archive in the explicitly selected store.
python3 tools/tla-differential/acquire.py --download --artifact-store /approved/store

# Restore a fresh local toolchain from the explicitly selected store only.
python3 tools/tla-differential/acquire.py --offline --artifact-store /approved/store
```

`--artifact-store` without `--download` is also offline restoration; `--offline`
makes the no-network intent explicit. `--download` and `--offline` are mutually
exclusive. A present store object with the wrong size or digest is refused
without a network fallback. Existing local artifacts are never overwritten.

Archive downloads and store publication use a temporary file on the destination
filesystem, verify the pinned size and SHA-256, then install with a no-clobber
operation. Apalache extraction is staged in a temporary directory and only
renamed into place after its JAR, launcher, and standard-library identities
verify.

## Tasks

### T1 - Lock identity inventory

- Record archive sizes alongside existing hashes.
- Add Apalache build revision, archive root, install paths, JAR and launcher
  sizes/hashes, while preserving all existing release URLs and derived
  standard-library hashes.
- Keep the existing SANY pin and historical lock schema unchanged.

Acceptance: the lock contains every identity needed to verify acquisition and
the extracted distribution.

### T2 - Content-addressed store

- Add explicit `--artifact-store DIRECTORY` selection.
- Use `sha256/<digest>` object paths with validated lower-case digests.
- Publish only verified bytes, atomically and without clobbering a different
  object.

Acceptance: a store can be populated from verified local or downloaded
artifacts and is addressed solely by SHA-256.

### T3 - Offline restoration

- Restore missing archives from the selected store without network access.
- Extract Apalache only after archive verification and stage the distribution
  atomically.
- Keep ordinary verification network-free and independent of ambient SANY or
  Apalache installations.

Acceptance: a fresh empty local toolchain restores and verifies from a populated
store while a download call is forbidden.

### T4 - Fail-closed behavior

- Refuse missing store objects in offline mode.
- Refuse truncation, size mismatch, digest mismatch, corrupt extracted JAR or
  launcher, and partial downloads.
- Never fall back to a release URL after a selected store object is invalid.
- Never overwrite an existing local artifact or store object with different
  bytes.

Acceptance: all negative cases exit nonzero and leave no partial destination.

### T5 - Documentation

- Document store layout, cache/offline commands, no-ambient-fallback boundary,
  no-overwrite behavior, and the prohibition on committing large binaries.
- Distinguish byte reproducibility from security or behavioral qualification.

Acceptance: an operator can populate, restore, and verify without reading the
implementation.

### T6 - Validation

- Add focused regression tests for missing artifacts, truncation, hash mismatch,
  partial download, cache refusal, no-overwrite behavior, and offline
  restoration.
- Run the focused acquisition tests, the complete offline differential suite,
  and the repository no-model gate where available.

Acceptance: results are reported separately, including skipped or unavailable
checks; no result is promoted to profile qualification.

## Validation (2026-10-26)

This section records implementation validation only. No profile, differential,
or end-to-end qualification is claimed.
[Raw logs and their inventory](immutable-toolchain-acquisition-evidence-20261026/README.md)
are retained separately.

Passed:

- `python3 -m unittest tools/tla-differential/tests/test_acquire.py -v`:
  15 tests passed, covering offline restore, missing/truncated/mismatched
  store objects, corrupt cached artifacts, partial downloads including
  `IncompleteRead`, no-overwrite behavior, corrupt extracted JAR/launcher,
  JDK identity, and digest-only store paths.
- `python3 -m unittest discover -s tools/tla-differential/tests`:
  75 tests passed, 4 live-reference tests skipped because
  `DV_LIVE_REFERENCES` was unset.
- Real-artifact offline restore smoke: a temporary store was populated from
  the existing pinned SANY and Apalache archives, then restored into a fresh
  temporary toolchain with `download` patched to fail. Archive sizes and
  digests, extracted JAR/launcher identities, and both standard-library
  digests verified. The run stopped at the expected Java admission failure.
- `python3 tools/tla-differential/acquire.py`: exit 1 with
  `Java 25.0.4+7 is required for DV1 qualification`; the ambient runtime is
  OpenJDK `21.0.12.1+1`. The installed archives and extraction identities were
  checked before that refusal.
- `python3 -m py_compile tools/tla-differential/acquire.py
  tools/tla-differential/tests/test_acquire.py` and `git diff --check`: pass.
- `lake build` within the local no-model gate: success, with pre-existing
  warnings.
- Parent review reran `TMPDIR=.lake/tmp-no-model bash
  tools/run-local-no-model-check.sh` outside the sandbox: the complete gate
  passed with 728 build jobs and `ALL LOCAL NON-MODEL GATES GREEN`.

Blocked or not run:

- Native integer maps were skipped because `MIRRORCPP_PREFIX` was unset.
- The required JDK `25.0.4+7` is not installed on this coordinator, so the
  standalone SANY `-help` probe inside full verification did not run.
- No live differential campaign, profile-6 qualification, or local
  Apalache/TLC model operation was run.
