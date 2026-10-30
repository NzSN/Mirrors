# October 29 completion campaign

This campaign executes the [approved work plan](../completion-execution-plan-2026-10-29.md).
The source prepares `v0.2.0-rc.1`; no release, package publication or production
replacement has occurred. The published starting point is Mirrors
`7e9a27d0db72ec36b49c6fc5764b2687b565edfd`. New implementation and qualification
inputs are working-tree changes, with exact bytes retained below.

## Completed acceptance

| Scope | Result and boundary |
| --- | --- |
| Finite F5 producer/consumer comparison | [Acceptance](controlled-model/acceptance.json): thirteen fresh native executions, eleven actual remote model verdicts, two matching policies, count/FIFO/early-unlock rejections, incomplete-cleanup/deadline refusals and six admission controls. The new composite schema records model comparison; raw SDK v1 receipts remain `modelComparison:false`. |
| Finite F5 reduction | Two fresh baselines, both declared policy trials and a fresh best replay reproduce the count mutation. Cost changes from `[2,0,4,14]` to `[2,0,2,14]`; minimality covers only the two declared policies. |
| Profile 6 | Independent required [T](../../test/fixtures/tla-frontend/differential/evidence/profile6-20261029-t/README.md) and [U](../../test/fixtures/tla-frontend/differential/evidence/profile6-20261029-u/README.md) each complete 61 fixtures, 76 branches and 183 observations: 564 matches, fourteen reviewed policy differences, 292 unsupported comparisons, zero unresolved findings. Semantic SHA-256 `c1938ecf662c828557fd1535cd25389368a6c27dcef445ea20405c7e41a47edb`. |
| Installed DPM | [Receipt](receipts/installed-dpm-acceptance.json): fresh C++, ECMA and Rust consumers pass after source hiding and network isolation. Retained finite oracles are used; `freshModelCheck:false` remains explicit. |
| Mirrors local gates | [RC aggregate](logs/rc-full-local-no-model.log) passes with an explicit fresh MirrorCPP prefix and ext4 temporary root. Native integer-map and new controlled-model preparation are included. Live local model tiers remain skipped. [Native rebuild](logs/rc-native-rebuild.log) passes without changing original shim sources. |
| Native Windows | [Build/gates](logs/windows-reference-finals.log): full native build and eight selected runtime suites pass, including the TLS long-poll regression and pure controlled-witness admission. This is not full `lake test` or production service qualification. |
| MirrorGate | Selected clean commit `4b379ac0c017e7621c945ebf8c106cd98a6c70d1` passes its [complete required gate](logs/gate-full-selected-5.log): 311 Python tests (five explicit skips), 227 Node tests, eleven integration tests, C++/Rust controls and actual Bubblewrap conformance/lifecycle gates. Native cgroup enforcement is not established. |

The F5 oracle was an isolated owned Windows process at loopback port 19129,
server SHA `f137abc5a51da1291e5c72323fb3069bd462b5427f6fb6e0401708b356ee3513`.
Actual backend Java and JAR identities were checked. Private keys stayed on
win10; the fixed in-place helper transported only public models and verdict
metadata. An observed four-second clock offset is covered by an explicitly
selected five-second tolerance, not a global relaxation. The
[shutdown observation](receipts/oracle-shutdown.json) confirms it stopped and
production `ModelMirrors` remained at its original SHA `8173ddea…`.

The fresh campaign exposed a TLS client bug: a five-second handshake receive
timeout remained active for application reads. Clearing it after the successful
handshake permits valid long async waits; a real six-second TLS response passes
on Linux and Windows. The handshake budget remains enforced.

The [current five-client matrix](client-matrix/receipt.json) passes all 22 rows:
C++/Haskell/Rust/Lean/ECMA valid, invalid and wrong-pin cases, plus all seven ECMA
protocol scenarios. A [fresh post-run observation](receipts/matrix-observation-after.json)
confirms the same server, runtime and fixture identities. The
[owned Job cleanup](receipts/matrix-cleanup.json) confirms the server and its
descendants are gone, with 33 actual Java executions observed at the selected
executable hash and production unchanged. The first matrix attempt is retained
separately: its Lean result was `VALID`, but the harness rejected the singular
`1 day` certificate-warning text. The narrow matcher fix and 146 evidence tests
pass before the complete fresh rerun.

## Source, package and compatibility selection

SDKs: MirrorCPP `8c542a6b1339cc0b6176465ff7f17a32e614553d`,
MirrorECMA `f94358834dce2e527c8bc8feec0423a54cf4176c`,
MirrorRust `6b9480ab81717b76ca7f74b41fc554578b70c890`,
MirrorLean `a8634ebe2455f97d15b55bec3c810d945cb6e3d3`.
Their external worktrees were preserved; task-owned builds/clones live under
`.golden-build/completion-20261029/`.

The staged [Windows archive](receipts/windows-candidate-archive.json) has SHA
`bed5c045102b80441a006a36e789164cf8dd50ad737008d3dda53a02d496a172`.
[Its build receipt](receipts/windows-candidate-build.json) binds the validated
base-plus-overlay source and executable/DLL hashes. Repeated packaging of those
same binaries is byte-identical; this is not a reproducible-compilation claim.
The ZIP is retained in the ignored release-artifacts directory, not in Git.

The [compatibility decision](../compatibility-lifecycle-decision-2026-10-29.md)
retains the supported stdio `register_error` behavior and pinned Haskell oracle.
A [five-request native probe](receipts/stdio-compatibility.json) passes. Actual
consumer migration and two shipped-release soak cycles remain prerequisites
for retirement; this decision grants no elapsed-time or deprecation credit.

## Remaining execution

The current matrix uses explicit endpoint/fixture selection, fresh identities
generated independently on each host, and a source-built pinned Haskell client.
No existing remote private key was exported. The initial Hackage download failed;
a verified public cache and signed incremental update restored the requested
September 1 index-state. Actual tool download identities, the compiled dependency
plan and the matrix's executable identities are retained.

A newly fetched Apalache TGZ was [refused](receipts/apalache-carrier-refusal.json):
its archive SHA is `765f6105…`, not the selected `7cfadf6e…`. Inspection after
refusal confirmed a valid archive with the exact observed JAR `079b6c23…`.
No artifact was executed or pin changed. The matrix observation distinguishes the
selected archive pin from reobserved executable bytes; it does not falsely claim
that the missing selected archive carrier was verified. The mismatch alone does
not identify its cause or establish a changed executable runtime.

The existing reference distribution declares Ubuntu 24.04, while this coordinator
is Ubuntu 26.04.1. Its full eighteen-command/sixteen-tier M5 refresh, both D audits
and linked independent Q1/Q2 verification therefore remain separate outstanding
work on a matching selected environment. These new scoped passes do not renew
that older platform/candidate record. The old retained October 25 private store
and driver paths are absent on this coordinator; their historical receipts remain.

[M4 preflight](receipts/m4-selected-preflight.json) observes WSL2 and no supplied
cgroup parent. Actual native quota/descendant/controller-death acceptance still
needs the selected native runner and operator-owned cgroup-v2 delegation. The
journal-v2 source extension is already implemented and its local controls pass.

Release packaging and its concrete publication/deployment/rollback handoff are
downstream of this source snapshot; the separate handoff records artifact hashes.
The final [non-model aggregate](logs/final-local-no-model.log) passes with the
installer's actual host/package observation repair. A real archive materialization
regression proves that package `0.1.0` and host `ubuntu-26.04` cannot be relabeled
as the catalog's historical `2.0.0`/`ubuntu-24.04` expectations. All 42 distribution
tests pass. The original interrupted aggregate is retained without pass credit. Production service
replacement, service-manager/reboot acceptance and public publication have not
been performed.

## Integrity and retained failures

Run `python3 Plans/completion-evidence-20261029/verify.py` after regenerating the
final inventory. It independently checks inventory bytes, frontend archive
membership/raw hashes and semantic equality, actual controlled-model verdict
logs and artifact bindings, installed-profile limits and missing/tampered controls.
It explicitly grants neither full framework qualification nor native M4 acceptance.

Original failed setup attempts remain separate: sandbox socket refusal, tmpfs
rejection for a required ext4 gate, missing/overlong Gate test prerequisites,
stale SANY calibration path, non-UTF-8 diagnostic archiving, and the optional
MirrorCPP example build's GCC-15 warning. The repaired library and owned consumers
pass with warnings-as-errors; the optional SDK example failure receives no pass.
No private keys, certificates, compiler binaries or tool archives belong in this
evidence inventory. Public certificate fingerprints and credential path selectors
in bounded remote receipts are metadata, not credential contents.
