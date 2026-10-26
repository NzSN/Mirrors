# DPM review remediation qualification

Date: 2026-10-14. Status: accepted for the declared remote WSL scope.

The [approved remediation plan](../completed/dpm-review-remediation-2026-10-13.md) is
complete. [Acceptance](acceptance.json) records the actual final gates;
[independent review](independent-review.json) found no remaining confirmed
findings in its reviewed scope. The original
[October 13 F3–F5 evidence](../dpm-f3-f5-evidence-20261013/README.md) remains
historical and unchanged. These working changes remain uncommitted.

The selected installation manifest is
`829f09ddef80a5db433f3580160092b80e0134e55032c8263ad14f087f341285`.
Its 5,265 installed files were independently checked. The gate rebuilt consumers
in isolated copies of that immutable installation and recorded their rebound
project identities separately.

## Corrected behavior

| Area | Accepted correction |
| --- | --- |
| Python admission | v2 typed commands, mandatory isolated Python flags, launcher-selected policy, exact verified helper bytes, inert adjacent source and bytecode |
| Replay evidence | Shared profile-aware intervals, observations, identity, completion and cleanup checks; typed oracle/client/observation correspondence |
| Output accounting | Per-request and total-operation retention includes raw SDK files, envelopes, logs, generated inputs, typed checks and reports; overflow refuses with measured failed evidence |
| C++ deadlines | Returning callbacks and actual joins are checked before completion acceptance; cleanup overruns remain sticky, with first-failure and retry ownership preserved |
| Exploration | Nonempty complete rows and consistent shape/input/category/denominator/stop facts |
| Compatibility | Model actions follow admitted aliases, including `finish` to `$done`; exact-terminal initial mismatches retain `checkpoint: null`; actual v1 projects receive a reprepare diagnostic |

## Final execution results

All final heavy builds and gates ran on `windows-dev` Ubuntu 22.04 WSL2.
[Environment](environment.json) records Lean 4.33.0, GCC 12.3.0, CMake 3.28.4,
Node 24.19.0, Python 3.10.12 and Rust 1.96.0. The launcher pins the actual
remote Python interpreter. Its OS standard library, extensions and loader are
trusted prerequisites.

| Gate | Result |
| --- | --- |
| Lean build | 727 targets passed |
| Pure policy / typed supplied-state evidence | 16 / 11 gates passed |
| DPM Python | 58 tests passed |
| C++ scheduling / binding / exploration | 35 cases, 752 assertions passed |
| C++ controlled synchronization | 25 cases, 331 assertions passed |
| ECMA scheduling / binding / exploration | 23 tests passed |
| Rust | Offline consumer build passed; seven generated-binding tests passed in the full suite |
| Full non-model gate | Exit 0; includes 39 distribution and 142 durable-evidence tests |
| TLA differential offline | 63 tests passed with four live-reference tests explicitly skipped |
| Installed three-profile gate | Exit 0; source paths hidden, networking isolated and original installation inventory unchanged |

The final phase records are `acceptance-phase.exit = 0` and
`local-gates-qualified-phase.exit = 0`; see [phase results](phase-results.json).
The [full non-model log](logs/local-no-model-check-qualified.log) retains the
explicit live Apalache/Counter/async skips. Offline acquisition tests use the
[locked archive fixtures](remote-records/offline-fixture-artifacts.json) with
Java/tool calls mocked; acquiring those bytes did not run a model checker.

Each [fresh installed profile](installed/acceptance.json) passed an actual full
match, an actual early mismatch, eight supplied-trace catalog comparisons,
40 local SDK schedules, 11 control families and eight malformed-receipt
controls. Each reduction retained two baseline executions, seven smaller
candidate trials and a fresh best replay: ten distinct executions per profile,
30 total. All three reduced `[3,1,4,7]` to `[2,0,0,6]` with the same write/count
delta-1 failure and confirmed cleanup. Minimality is limited to the admitted
catalog. The separate installed C++ sample passed; its
[returning-callback overrun](installed/controlled-sync-overrun.receipt.json)
reported `timed_out`, `passed: false`, both budget flags true and physical cleanup
confirmed. Both controlled-resource receipts retain `modelComparison: false`.

## Identities and retained artifacts

- [Source manifest](source-manifest.json): 51 selected working files across
  Mirrors, MirrorCPP, MirrorECMA and MirrorRust; all 35 implementation files
  match the qualified remote sources. Documentation is recorded separately from
  implementation qualification, including final updates after the remote snapshot.
- [Qualified source verification](qualified-source-verification.json) and
  [original transfer manifest](source-transfer.json): 5,270 transferred files
  checked. The two recorded post-transfer changes are the generated remote
  interpreter identity and the host regression's partial-write assertion.
- [Installation manifest](installation-manifest.json): exact activated tree.
  [Input projects](input-projects) distinguish prepared, installed and freshly
  rebuilt consumer identities.
- [Binary identities](binary-identities.json): 200 executable/native archive
  hashes and durable remote paths. Binaries and development-kit trees stay on
  the remote host; this dossier retains receipts, inputs and logs.
- [Workflow](workflow), [raw installed evidence](installed) and [logs](logs)
  retain exact commands, request/response bindings, SDK receipts, reductions,
  controls and diagnostics. [Curation](remote-curation.json) binds the transferred
  receipt/log archive. [Evidence manifest](evidence-manifest.json) inventories the
  completed dossier except itself.

Sources remain under `/home/jlc/Tools/mirrors-dpm-remediation-20261013/source`.
Large outputs remain under
`D:/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build`.
The pre-existing `/home/jlc/Repos/Mirrors` checkout was not changed.

## Superseded diagnostics and storage

Earlier failures receive no pass credit: the initial Lean phase found a missing
relocated host-driver path and an overly strict assertion that an interrupted
raw write must finish all 1 MiB; the focused phase corrected the layout/test and
passed. The initial Rust offline build lacked `rustls-pemfile`; the locked fetch,
offline rebuild and vendoring retry passed.

The full-suite retries separately exposed a symlink build-root restriction,
insufficient Linux space for a copied launcher, missing pinned `jsonschema`,
and missing offline archive fixtures. Each failed exit and raw log remains
retained. The final full retry used the exact evidence dependencies and an owned
4 GiB ext4 scratch image on D:. Atomic installation stayed on Linux ext4 because
D: does not support the required no-overwrite `renameat2` mode. Completed generated
Rust outputs were copied to D:, verified across 897 files, and then replaced by
an owned symlink to restore Linux free space. These layout changes preserved
private source files, the installation and unrelated data.

## Boundaries

Retained October oracle captures were reused with checked provenance; there was
no fresh model check. SDK finite exploration and F5 controlled resources remain
separate from model-comparison credit. This record does not extend frozen M5 C0
`94271a54…`, qualify a new framework release or native platform, establish broader
M4 confinement/restart recovery, or authorize deployment/publication.

Output polling provides acceptance accounting, not a hard disk/memory quota.
An owned writer can be stopped before completing its requested write; failed
bytes are retained and counted. Uninterruptible C++ callbacks or joins may
return late, but cannot establish a pass; a hard limit needs an external owner.
Non-detaching runners and stable admitted artifacts remain profile assumptions.
No commit, push or production service change was made.
