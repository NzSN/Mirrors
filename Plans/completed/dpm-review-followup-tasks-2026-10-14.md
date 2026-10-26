# DPM review follow-up tasks

Date: 2026-10-14. Source: [fix plan](dpm-review-followup-2026-10-14.md).
Status: complete for the declared remote WSL scope. See
[acceptance evidence](../dpm-review-followup-evidence-20261014/README.md).
Owners are not alone in the workspace;
each preserves other owners' edits and stays within the files assigned below.

| Task | Owner and files | Depends on | Work | Acceptance | Status |
| --- | --- | --- | --- | --- | --- |
| T0 | Coordinator; this plan/tasks and baseline inventory | None | Freeze review inputs, scope and historical manifest/checkpoint hashes | Three raw failures preserved; exact four HEADs and reviewed source identities recorded | Complete: 51 files frozen; 891 + 1,460 historical hashes verified |
| T1 | Cancellation owner; `dpm_host.py`, `cli.py`, `tests/test_dpm_host.py`, canonical `tests/cancellation_control.py` | T0 | Scoped cooperative cancellation through complete cleanup; preserve first failure and accounting; add bounded process regressions | Normal/single/repeated/timeout-cleanup and cleanup-entry cases reap every owned process; repeated signals cannot bypass cleanup or erase primary reason | Complete: seven remote ownership controls and final 65-test Python suite pass |
| T2 | C++ owner; `../MirrorCPP/src/schedule_sync.cpp`, `test/unit/schedule_sync_test.cpp`, `test/unit/CMakeLists.txt`, relevant resource-guide clarification | T0 | Admit wrapped rows and separators; boundary regressions; 30-second CTest timeout | Exact limit passes and fits; one-byte-over final observation/events refuse; controlled sync and neighboring suites pass | Complete: remote WERROR suites pass, sync 27 cases/362 assertions; all 27 CTest timeouts verified |
| T3 | Coordinator; `Codec/Dpm.lean`, `tools/DpmSpec.lean`, relevant runner-guide clarification | T0 | Admit empty literals while retaining path/NUL/length/closed-object constraints | Empty literal passes pure admission; empty paths/NUL/overlong literals refuse; pure suite passes | Complete: remote pure policy 25 gates pass |
| T4a | Remote validation owner; new task-owned remote follow-up prefix and evidence workflow only | T0 | Inspect remote resources/toolchain; provision independent source/cache/output directories | Prior source/install/evidence untouched; ordinary ext4 source/install paths, bounded jobs and sufficient scratch capacity recorded | Complete: independent 12-GiB ext4 image, tools and copied caches recorded |
| T4b | Remote validation owner; generated `HostIdentity.lean`, installer/gate helper pins by sequential handoff | T1, T2, T3, T4a | Verify source transfer, refresh identities remotely, rebuild launcher/CPP, regenerate projects and install new prefix | Current implementation matches compiled inputs; selected new installation inventory verifies; old launcher refuses changed helpers | Complete: 36 implementation files match; new 5,265-file installation verifies; stale launcher refuses |
| T5 | Remote validation owner; new regression/gate outputs | T4b | Focused Python/Lean/CPP gates; public cancellation/empty-argv controls; fresh installed three-profile gate; full no-model suite | Required controls pass; exact final exits/logs retained; source hiding/network isolation and owned-process cleanup verified; live skips explicit | Complete: final installed/non-model exits 0; seven function controls, three public controls and paired C++ refusal pass |
| T6 | Independent reviewer; read-only final source/control/evidence review | T5 | Review fixes, scope and raw acceptance records independently | No remaining confirmed finding in corrected scope, or actionable findings returned for repair/revalidation | Complete: independent remote audit finds no remaining confirmed finding in corrected scope |
| T7 | Coordinator; new evidence README/manifests, current status, new checkpoint and AGENTS pointer | T6 | Verify final hashes, evidence coverage and historical preservation; close task statuses | Every evidence file/selected source verifies, documentation links resolve, old records unchanged; no commit/push | Complete: new manifests/checkpoint recorded; historical bytes preserved |

T1, T2, T3 and T4a may run independently. T4b owns generated identity files only
after source-owner handoff; do not refresh their pins concurrently with edits.
T5 starts only after verified rebuild/repackaging. Each owner returns exact
changed files, validation commands/results and open limitations to the
coordinator. Repair findings sequentially and re-run only affected gates before
the final acceptance record is frozen.
