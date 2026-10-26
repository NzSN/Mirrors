# SANY re-pin and frontend profile-6 evidence — 2026-10-26

## Scope and artifact identity

The user explicitly authorized re-pinning the standalone SANY artifact to the
newly served jar. `artifact-identity.json` binds the exact old/new hashes,
manifest build revision, derived standard-library identity, catalog change and
validation boundaries.

The new jar reports SANY 2.2 and was built from revision `2ef2af8` on
2026-10-24. Its SHA-256 is
`d15655eeaff4b3f7b3d65c46b838bc0f35d131b2ef4b1e473689b62c98d4726f`.
The separate Apalache 0.61.0 archive and pin are unchanged.

The new standard sources changed `Bags.tla`: its bytes differ and it no longer
publicly extends `TLC`. Following the language-profile revision contract, this
change uses frontend `mirrors-tla-frontend-profile-6` and catalog
`mirrors-standard-modules/v3`; it is not treated as a hash-only refresh.

## Corpus migration

- All 34 accepted summary documents carry the profile-6 identity. The
  junction summaries and standard-module summary were regenerated through the
  real frontend. Fixture sources are unchanged: 61 fixtures, 34 accepted, 27
  rejected and 76 branches.
- The catalog binds the new `Bags` content hash and removes only the public
  `Bags -> TLC` edge. A module-resolver regression checks that `Bags` no longer
  re-exports `TLC`, while the `Integers -> Naturals` public control remains.
- The previous active difference registry is preserved byte-identically as
  `test/fixtures/tla-frontend/differential/archive/profile5-differences.json`,
  SHA-256 `79f940ccff8c34c5cc01c7ade47e91faeda07fa13bb491b75d6da7ef78219e22`.
- The active profile-6 registry starts with no reviewed differences. Historical
  approvals are not renewed without fresh observations and review.

## Validation

| Gate | Result | Evidence |
| --- | --- | --- |
| Focused profile-6 Lake build | Passed | `profile6-build.log` |
| Module resolver, lexer, parser, frontend and elaboration | Passed; all 61 corpus fixtures matched | `no-model.log` |
| Offline TLA differential tests | 63 run, 59 passed, four documented skips | `offline-differential.log` |
| Complete `tools/run-local-no-model-check.sh` with ext4 `TMPDIR` | Passed; 728 build jobs and `ALL LOCAL NON-MODEL GATES GREEN` | `no-model.log` |
| Rebased complete no-model gate on upstream `658b9ef` | Passed again with upstream temporary-root regressions retained | `no-model-rebased.log` |
| Standalone toolchain runtime verification | Refused: coordinator has Java 21, while Java 25.0.4+7 remains required | `runtime-verification.*` |

Native integer-map coverage remained skipped because no `MIRRORCPP_PREFIX` was
selected. Live Apalache/Counter/async tiers remained skipped. No local
Apalache/TLC model operation, live differential run, production deployment,
commit, push, tag or hosted release is claimed.

Profile 6 is therefore source/offline validated but **not live-differential
qualified**. Fresh required runs on the selected Java 25 runtime and actual
review of any differences remain necessary before qualification.
