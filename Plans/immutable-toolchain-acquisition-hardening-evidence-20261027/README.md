# Immutable acquisition hardening evidence — 2026-10-27

This record covers two review fixes in `tools/tla-differential/acquire.py`:

1. Downloads now stop and fail when they exceed the pinned size, before excess
   bytes are written. Exact-size input remains accepted.
2. Apalache distribution publication uses an atomic no-replace rename. A
   concurrently created invalid destination is preserved and rejected; a
   concurrently published valid distribution is verified and accepted.
   Platforms without an atomic no-replace primitive fail closed.

## Validation

| Check | Result | Evidence |
| --- | --- | --- |
| Focused acquisition suite | 18 tests passed, including oversized download and concurrent destination controls | `acquisition-tests.log` |
| Offline differential discovery | 78 tests passed, four live-reference tests skipped | `offline-differential.log` |
| Complete no-model gate outside the sandbox with ext4 `TMPDIR` | 728 build jobs; `ALL LOCAL NON-MODEL GATES GREEN` | `no-model.log` |
| Installed artifact verification before runtime admission | Archive, extraction, and standard-library identities checked; Java 25.0.4+7 refusal preserved | `runtime-verification.*` |

The coordinator remains on Java 21, so standalone SANY `-help` verification did
not run. Native integer-map coverage remained skipped because no
`MIRRORCPP_PREFIX` was selected. No local Apalache/TLC model operation, live
differential campaign, production deployment, commit, or push occurred. This
record grants no frontend profile or end-to-end qualification.
