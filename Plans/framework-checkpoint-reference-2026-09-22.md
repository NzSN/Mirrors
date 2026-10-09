# Archived framework checkpoint reference

Archived during the 2026-10-09 documentation synchronization from `AGENTS.md`
at Mirrors `548ba71`. The original September checkpoint sections below are
retained verbatim, including v5 hashes and historical tool/service observations.
Their stop/resume instructions are superseded. For current work, read
[current status](../Docs/current-status.md), the newest
[checkpoint](../CHECKPOINTS.md), and [execution decisions](execution-decisions.md).

## 2026-09-25 candidate

Untracked `.projectile-cache.eld` files stay on disk and are excluded from the
selected component refs as pre-existing-unrelated editor caches. The exact
catalog selection, install digests, and remaining Q1–Q3 gaps are in
`Plans/q3-readiness-2026-09-25.md`. That report is evidence output and is not
part of the selection digest. The v5 hashes below remain historical.

## Stopped framework-completion checkpoint (2026-09-22)

Superseded (2026-09-30): framework work resumed 2026-09-25; the current
position lives in `CHECKPOINTS.md` (latest entries 2026-09-30). The v5 hashes
and counts below remain historical, and the resume instructions in this section
no longer apply.

Work is intentionally stopped at the user's request. Resume from
`Plans/execution-decisions.md` and `Docs/qualification-harness-design.md`; do
not restart the framework work from its historical queued task-card labels.

- Mirrors, MirrorECMA, and MirrorGate contain the coordinated uncommitted
  implementation. No background worker or qualification command remains live.
- The byte-stable v5 catalog selection is
  `e3b691a60a87708b50c24085303fd313359cef33c50b11f7cc89fbd2358c3b7d`.
  Its snapshot is `/tmp/mirrors-reference-final-snapshot-v5`. The local cache
  build passed with canonical manifest digest
  `6579da18768b3efa5f6e6a61e7d7aa190e25f81bb520b9823f2b7e1a2e7fa8c2`;
  cache-index and manifest file hashes are respectively
  `2d3590e70e61537d97536e3d67af0f563a045d0a32b3d95d297c6993d8cb857a`
  and `942c794d66ef236f279e9b7a10a066da120cd7886d1cf4d307e205093c956321`.
  Installation committed at `/tmp/mirrors-reference-final-local-install-v5`.
- The v5 selection records the pre-commit dirty working trees. The checkpoint
  commits requested after this stop create new clean repository revisions, so
  v5 remains diagnostic and cannot qualify those pushed revisions. Refresh the
  catalog and snapshot from the pushed SHAs before resuming qualification.
- Stop occurred before v5 installed-consumer qualification. The Gate cache was
  not built. Q1, Q2, and Q3 therefore remain incomplete. Earlier v3/v4 failed
  audits are diagnostic only; their findings were fixed in source and covered
  by the current 22-test distribution suite.
- Focused source validation at stop: Mirrors evidence 94/94 and distribution
  22/22; MirrorECMA TypeScript plus installed wrapper/project 19/19 and catalog
  regression 3/3; MirrorGate recovery 40 tests with 34 passes and six
  environment skips, plus installed campaign wrappers 7/7. Model checking was
  excluded from these local results.
- Run every model check through the Mirrors CLI against the deployed service at
  `192.168.150.219:8999`. Do not start local Apalache or TLC. The direct mTLS
  CLI smoke returned `VALID` for bound-3 HourClock. The service still runs
  Apalache 0.58.2 and Java 21.0.11, so that observation is smoke evidence, not
  the selected 0.61.0/25.0.4+7 qualification. Newer toolchains are staged on
  the server but inactive; the service was not restarted or reconfigured.
- The current WSL2 host has no writable delegated cgroup-v2 parent. Real
  aggregate enforcement remains required but unavailable, and WSL2 does not
  establish native Ubuntu host acceptance.

Resume in this order: refresh identities and the immutable snapshot from the
pushed SHAs, rebuild and verify the local cache, run installed-consumer
qualification, build and install the Gate cache from that same snapshot, freeze
the installed evidence commands, run Q1, verify Q2 offline, then update Q3.

End of archived September checkpoint sections.
