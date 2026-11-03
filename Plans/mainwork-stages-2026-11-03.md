# Mirrors release-completion stages — 2026-11-03

Status: active task plan, with execution delegated to Grok and acceptance owned
by Codex. This plan continues the [completion design](../Docs/completion-qualification-release-design.md)
and [October 30 task plan](completion-qualification-release-plan-2026-10-30.md).
Their stage identifiers remain stable; S4/native-runner work stays withdrawn.

## Baseline and outcome

Initial source: Mirrors `75fbf962020cea8a13e009ecfdb3e912e7ce212f` on `main`.
The cached `origin/main` matches; a fresh remote observation is a delivery task,
not an inference from the tracking ref. Tracked files were clean before this
planning work. Existing untracked completion evidence and editor caches stay
on disk and outside this task's delivery scope.

The source now includes Batteries carrier re-pin `72d83b0`, product-identity
propagation `f0daef9`, and diagnostic parsing `75fbf96`. October 31 maintained
status text predates the latter commits. The earlier rc.5 packages bind
`3ee3d92`; they remain historical package evidence and cannot qualify this
later source. Neither a product version nor a matching cached branch ref
supplies an immutable final candidate or a successful deployment.

The intended outcome is an audited immutable artifact set, exact-candidate
qualification, a reviewed release handoff, and separately selected publication,
deployment and lifecycle results. Compatibility retirement requires later
measured release cycles and cannot finish during this candidate's preparation.

## Stages and exit gates

| Stage | Required output and exit gate | Dependencies / initial state |
| --- | --- | --- |
| S0 Intake | Inventory current source, companions, hosts and historical evidence; map every remaining obligation to a task and owner. | Execute now; historical receipts are inputs only. |
| S1 Review and freeze | Review post-rc.5 source, run focused regressions and required final local gates, resolve findings, and freeze exact source/contract/tool/companion identities. | Focused review/validation now; final freeze waits for findings and any required build approval. |
| S2 Audited delivery | Review explicit payload/exclusions, compare staged bytes, publish only the selected branch scope when authorized, and reobserve remote full SHA. | Prepare now; mutation depends on concrete delivery authorization. Do not republish an unchanged source just to advance the stage. |
| S3 Clean packages | Select an unused immutable candidate tag matching source version; construct clean Linux/Windows packages and verify manifests, archives, dependencies, source bindings and actual host smoke. | Requires final S1/S2 source and approved tag/version selection; old rc.5 bytes remain unchanged. |
| S5-A Admission | Admit observed hosts and exact C0/locks/cache inputs; materialize source-hidden installations and pass both D audits; freshly observe the owned remote endpoint/runtime/TLS and client pins. | Preflight now; final construction and admission require S1–S3 identities. |
| S5-B Producers | Execute the selected registry's complete M5 commands/tiers, remote five-client matrix, three installed DPM profiles and full declared Windows tests; retain failures, cleanup and before/after identities. | Requires exact D bindings and respective remote/Windows admission. |
| S5-C Independent Q | Build the finalized C0→D→R0→R1→Q graph; pass linked Q1, independent installed/offline Q2, complete-profile catalog linkage and all required negative controls. | Requires complete same-candidate producers. No source checkout or live backend fallback. |
| S6 Release admission | Review the artifact/qualification claim matrix, notes, retention, rollback plan and concrete publication/deployment payload. | Draft templates now; final admission requires verified evidence for the selected release scope. |
| S7 Operations | Independently verify selected public refs/assets, guarded deployment/rollback, live controls and separately approved reboot persistence. | Concrete operations remain separate boundaries; preparation is authorized now. |
| S8 Retention and compatibility | Verify retained artifacts/evidence and record real compatibility matrices, soak, incidents, acknowledgements and fallback exercises across two consecutive shipped cycles. | Prepare ledger now; no fabricated release-cycle, soak or retirement credit. |

Critical path: S0 → S1 → S2 → S3 → S5-A → S5-B → S5-C → S6 → S7.
S8 retention preparation runs alongside these; retirement admission spans a
later release. S5-B may run independent producers in parallel only after their
own dependencies pass. A failed required tier stays failed or awaiting input;
an explicitly scoped prerelease must name every absent tier.

## Executable tasks

The [task ledger](mainwork-execution-20261103/tasks.json) records owners,
dependencies, outputs and review state. `complete` means Codex reviewed the
task output, not that the enclosing release stage passed. Stage state uses the
design's `not-started`, `awaiting-external-input`, `admitted`, `executing`,
`passed` and `failed` vocabulary. A report must distinguish readiness work
from a real producer run.

| Task | Owner | Work and acceptance | Dependency |
| --- | --- | --- | --- |
| MW-00 | Grok/source | Capture HEAD/tree/status/cached refs and full companion identities/dirty scope; identify maintained-status drift. | Now. |
| MW-10 | Grok/source | Review changes since `3ee3d92`; run distribution, release and evidence Python suites with raw logs and exit codes; report concrete findings. | MW-00. No full build or local model checker. |
| MW-11 | Codex | Review Grok's findings, inspect relevant source, independently reproduce material failures and verify receipt/log hashes. | MW-10. |
| MW-12 | Grok, then Codex review | Fix confirmed findings in separately assigned files; rerun focused regressions, then required final non-model/native gates; emit immutable candidate freeze. | MW-11 and any required full-build approval; assign actual files after diagnosis. |
| MW-20 | Grok/source, then Codex | Prepare exact delivery list/exclusions and fresh remote-ref check command; perform authorized commit/push only after reviewed scope exists; verify remote full SHA. | Preparation now; final action after MW-12. |
| MW-30 | Grok/handoff | Prepare next-candidate version/tag decision and exact clean Linux/Windows construction/check commands using maintained release tools. | Preparation now; do not move or reuse rc.5 tags. |
| MW-31 | Grok, then Codex review | Build exact tagged Linux archive, verify checksums/build manifests/imports/content and isolated archive smoke on observed selected host. | MW-20, selected version/tag authorization, required build approval. |
| MW-32 | Grok, then Codex review | Transfer exact source to admitted Windows staging, verify before/after source bytes, build, run package suites, verify repeat packaging/DLL closure and cleanup. | Same final source as MW-31; owned Windows access and build approval. |
| MW-50 | Grok/admission | Observe actual coordinator/runtime/tool/permission facts and read-only companion state; validate both lock roots and retained Batteries carrier; identify blockers precisely. | Now; no new C0 acceptance. |
| MW-51 | Grok/admission | Produce argument-complete C0/cache/install/two-D command recipes tied to current tool parsers and actual missing inputs; distinguish base and WSL2 profiles. | MW-50. Execute final forms after MW-12/MW-31/MW-32. |
| MW-52 | Grok/admission | Enumerate fresh remote observation, TLS validity/pin, client and Windows prerequisites; supply safe observation recipes and prerequisite owners. | Now; no historical endpoint/current-health inference. |
| MW-53 | Grok, then Codex review | Materialize final C0, both installed profiles and both D bindings; retain exact manifests/cache/source-hidden/trace-audit receipts. | MW-51 plus final source, packages and admitted permissions/tools. |
| MW-54 | Grok, then Codex review | Reobserve selected owned remote and Windows hosts; admit certificate/runtime/backend/client identities without exporting credential bytes. | MW-52 plus selected endpoint/credentials/host access. |
| MW-60 | Grok/handoff | Extract the selected 18-command/16-tier obligations from `tools/evidence/commands.json`; map source gates, replay/R1, reductions, mutations, recovery, remote/client, DPM and Windows rows to real command/artifact contracts. | Now for task preparation; reconcile exact profile membership, do not assume counts. |
| MW-61 | Grok, then Codex review | Execute source/installed correct and faulty replay, both origin/R1 branches, prefix/domain reductions, full mutation aggregates and prepared-filesystem recovery with finalization and cleanup. | MW-53; remote-dependent reductions also require MW-54. |
| MW-62 | Grok, then Codex review | Execute remote model and all 22 selected five-client rows using Mirrors CLI and same-time identity observations. | MW-53/MW-54. |
| MW-63 | Grok, then Codex review | Renew source-hidden/network-isolated installed C++/ECMA/Rust DPM acceptance with `freshModelCheck:false`. | Final exact packages and required admission. |
| MW-64 | Grok, then Codex review | Execute full declared Windows `lake test`, native integer-map, compiler/runtime/TLS gates on a separately admitted live-check host. | MW-32/MW-54 and explicit long/full build approval. |
| MW-65 | Grok/handoff | Prepare finalization graph, Q1/Q2 and negative-control recipes; independently resolve actual installed verifier/schema/registry paths. | Preparation now; execution after MW-61–MW-64. |
| MW-66 | Grok, independently checked by Codex | Execute complete linked Q1 and installed offline Q2, validate complete-profile catalog linkage, reject required missing-payload/tamper/wrong-link/incomplete-profile controls, verify backend independence and emit qualification result. | All selected required producers passed; owned backend lifecycle authority before stopping any backend. |
| MW-70 | Grok/handoff | Draft claim matrix, release-note/handoff templates and operation/rollback prerequisites; unknown identities remain explicit. | Now; final bytes/claims after MW-66. |
| MW-71 | Codex | Review evidence scope and final handoff; present concrete immutable publication/deployment/reboot operations when ready. | MW-31/MW-32/MW-66/MW-70. |
| MW-72 | Grok, then Codex review | Execute approved tag/release publication, download/hash checks, guarded candidate-port/deployment/rollback and separately approved reboot controls. | MW-71 plus operation-specific authorization; no inferred public/production action. |
| MW-80 | Grok/handoff | Create retention and compatibility ledger templates naming two shipped-cycle matrices, real workloads, incidents, acknowledgements, rollback and retirement gates. | Now. |
| MW-81 | Grok, then Codex review | Verify final retained public/private artifacts and record each actual compatibility/soak observation; keep retirement pending until policy is met. | Retention after completed runs; retirement spans two shipped cycles and separate decision. |

## Grok execution and review contract

Three independent jobs execute the ready tasks now. Authoritative briefs:

- [Source and validation](mainwork-execution-20261103/source-task.md):
  MW-00/MW-10/MW-20 preparation.
- [Admission and distribution](mainwork-execution-20261103/admission-task.md):
  MW-50/MW-51/MW-52.
- [Downstream tasks and handoff](mainwork-execution-20261103/handoff-task.md):
  MW-30/MW-60/MW-65/MW-70/MW-80 preparation.

The [Codex command corrections](mainwork-execution-20261103/review/corrected-commands.md)
override corresponding Grok handoff and admission draft examples. They preserve
attachment/argv boundaries, independent Q isolation, required payload/profile
controls, local-tag ordering, valid lock-root layout and the selected WSL2-only
scope. Original job artifacts remain inventoried unchanged. The
[reviewed outcome](mainwork-execution-20261103/review.md) and
[execution index](mainwork-execution-20261103/README.md) record what passed and
what remains pending.

Grok jobs own only their assigned new output directories. They are not alone
in the checkout; preserve others' edits and never reset/clean or revert work.
Codex owns this plan, CHECKPOINTS.md, the central ledger and review. Source
fixes receive a separate file-specific assignment after review. No job may
claim dependent stages completed by generating plans or templates.

Every result includes exact HEAD/tree, task disposition, concrete blockers,
commands/exits/log paths and SHA-256s, and a generated-file inventory. Codex
checks actual files, compares claims to outputs, reruns meaningful focused
checks, and records accepted findings/corrections in `review.md`. Grok process
success is not evidence acceptance. Missing artifacts or permission failures
remain explicit and must not be replaced by guessed observations.

The present request authorizes stage/task development, repository checkpoint
updates, Grok delegation and review. It does not by itself authorize tag/ref
mutation, release publication, production replacement or reboot. Prepare
concrete reviewable operations first. Respect existing long/full-build approval
requirements; focused Python validation is part of the current delegation.
