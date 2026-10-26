# Immutable toolchain acquisition evidence — 2026-10-26

This directory retains validation for the
[immutable acquisition implementation tasks](../immutable-toolchain-acquisition-tasks-2026-10-26.md).
It establishes the scoped acquisition and regression behavior only; it grants
no frontend profile, live differential, or end-to-end qualification.

| Check | Result | Evidence |
| --- | --- | --- |
| Focused acquisition suite | 15 tests passed | `acquisition-tests.log` |
| Offline differential discovery | 75 tests passed, four live-reference tests skipped | `offline-differential.log` |
| Complete no-model gate outside the sandbox with ext4 `TMPDIR` | 728 build jobs; `ALL LOCAL NON-MODEL GATES GREEN` | `no-model.log` |
| Installed artifact verification before runtime admission | Archives, extraction, and standard-library identities checked; Java 25.0.4+7 refusal preserved | `runtime-verification.*` |

The coordinator remains on Java 21, so standalone SANY `-help` verification did
not run. Native integer-map coverage remained skipped because no
`MIRRORCPP_PREFIX` was selected. No local Apalache/TLC model operation, live
differential campaign, production deployment, commit, or push occurred.
