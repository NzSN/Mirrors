# Rc.11 completion checkpoint — 2026-11-06

**Exact-candidate qualification is complete. Publication, production replacement,
reboot, and the two-release compatibility lifecycle remain separate operations.**
The machine-readable [result](result.json) and [operation card](operations.md)
define the accepted scope and the concrete remaining actions.

Mirrors is frozen at `19c31bf09b58e27c2942ca123a2017c30b638216`, with local immutable
tag `v0.2.0-rc.11`. MirrorGate is `cd4914b2fa68aaa4f22955352b81cbb890ffd6f0`;
MirrorECMA is `9192171fc5f8d8457f8d13ffaafa117222914ec2`. Selected C0 is
`989061a0e10c569c3bae787a97e225a5580679e094fde313e487de17604faa40`.

| Roadmap stage | Current result |
| --- | --- |
| S0–S1 intake/source freeze | Passed; 49 source files reviewed, 240 unrelated files preserved, source stable through gates |
| S2 source delivery | Private source and companion commits ready; remote publication pending approval |
| S3 packages | Linux archive and repeatable Windows ZIP verified at the exact source |
| S5 qualification | Both D bindings; complete M5 profile; 20 sealed bundles; Q1 and independent Q2 accepted |
| S5 controls | Six actual Q negatives and four actual stale-audit negatives rejected; Q2 identical after oracle shutdown |
| S5 native/client acceptance | Full native Windows driver including seven Rust tests; 22 client rows; three installed DPM profiles; 13 finite controlled C++ executions |
| S6 handoff | Scoped prerelease ready; package/live controls pass; production baseline healthy; rollback copy prepared |
| S7 publication/deployment/reboot | Concrete operations prepared, not performed |
| S8 compatibility lifecycle | Existing behavior/goldens retained; two shipped cycles, real workload records and consumer acknowledgements remain required |

[Windows acceptance](windows-full-result.json) verifies all 10,113 Git blobs,
no source overlay, actual Rust execution and zero remaining test-job processes.
Linux-only DPM build regression and eight optional/platform-specific TLA
unit cases remain explicit Windows skips; live TLC safety/liveness/mutant tiers
ran. [Independent Q2](independent-q2-result.json) used installed verifier/schema
bytes, hidden source/scratch, isolated networking and read-only inputs.
[Offline repetition](offline-after-shutdown.json) is byte-identical after the
owned model server, its console host and tunnel stopped. Production stayed on
its prior executable hash and remains running.

The final fixes cover native Windows DPM job ownership, evidence/filesystem
transactions and ACLs, archive byte preservation, audit-to-manifest identity,
and native Rust gate admission. Bare `bash` under native Lean selected WSL;
rc.11 calls the shared Python driver directly. Gate's hosting repair processes
reply snapshots in wire order before coalesced events; deterministic red/green
regressions and the complete companion gate pass.

The Linux packaging attempt exposed a pinned Lean runtime prerequisite:
`IO.FS.createTempDir` exits 139 when `TMPDIR` names an absent directory. A minimal
probe reproduced this; the successful package gates used an existing owned
ext4 directory. Earlier failed/superseded attempts remain retained and receive
no acceptance credit. Freeze-time status text in the immutable source is
historical; this checkpoint records the completed gates.

The local Linux archive was built on Ubuntu 26.04.1 WSL2. It is not an Ubuntu
24.04 ABI claim or the future hosted Linux asset. Native M4 enforcement/recovery,
Windows/macOS Gate backends and generic scheduling guarantees remain outside
this scoped release. DPM installed acceptance has `freshModelCheck: false`;
the separate finite controlled campaign supplies its own model comparison.
