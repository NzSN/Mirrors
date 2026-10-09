# Framework documentation synchronization — October 9

Date: 2026-10-09
Status: completed for maintained framework/client documentation.

The user requested “Sync all outdated docs”. This review updates maintained
framework and linked client guides against inspected source and the latest
checkpoint. Dated qualification records, frozen acceptance and source manifests,
proof receipts, generated outputs and earlier checkpoint entries retain their
original bytes and claims. This is documentation maintenance, not a new build,
installed-package acceptance, live service check or release qualification.

## Inspected source and accepted boundaries

| Repository | Inspected HEAD |
| --- | --- |
| Mirrors | 548ba71 |
| MirrorECMA | 1e87f3e |
| MirrorCPP | 25a44b5 |
| MirrorRust | 0f77fdf |
| MirrorGate | 8afae26 |
| MirrorLean | b8b9491 |

At review start Mirrors, ECMA and Gate had unrelated editor caches; Rust also
had a local `tests/protocol.rs` edit. The review preserves those bytes. The heads
above describe inspected checkouts, not a clean immutable campaign snapshot.
MirrorLean's maintained guide was inspected and required no change.

The [latest frozen M5 record](q3-published-roadmap-2026-10-07.md) qualifies
`m5-wsl-windows-remote/v1`, class `local-candidate`, under C0 `94271a54…` at
Mirrors f0894d2, ECMA eef6f71 and Gate 455e196. It retains 18 required commands,
16 tiers, 19 linked nodes/two installed D bindings, 20 independently verified
bundles and six rejected controls. Later source/docs publication never transfers
that qualification to current HEAD automatically.

The [DPM first-slice record](dpm-usability-evidence-20261007/README.md) accepts
F1 kit generation/checking and F2 actual-receipt timelines in source only: six
C++/async-ECMA/Rust kit modes, 21 focused tests, actual helper/seed compilation
in three languages and real Node-worker match/mismatch replay with cleanup.
The common portable corpus retains six profiles; the compiler implements eight
emitters. [F3/F4/F5](dpm-usability-features-2026-10-07.md) remain approved,
unimplemented follow-ons. Broader [M4](m4-native-host-and-platform-plan-2026-10-07.md)
requires both native host delegation and durable process-to-cgroup linkage.

## Corrections

- Refresh source-navigation heads and architecture data; add DPM kit/timeline
  source ownership, SDK entry points and changelog coverage.
- Correct incomplete target lists to include async-ECMA v2 and Rust v2 while
  keeping common corpus, runtime/package and framework qualification scopes distinct.
- Replace obsolete domain-reduction activation and frontend differential-failure
  summaries with links to their later accepted records. Earlier results remain
  historical and unsupported frontend comparisons remain explicit coverage gaps.
- Mark original queued task cards as historical; direct continuation through
  the latest checkpoint and approved F3/F4/F5 plan. Move the original AGENTS
  September checkpoint sections verbatim into an [archived reference](framework-checkpoint-reference-2026-09-22.md).
- Describe traced native builds as implemented rather than an unfixed timestamp
  probe. Correct the current five-client cutover runner inventory.
- Make the recorded October 8 certificate expiry explicit in remote guides.
  No live service or replacement credentials were inspected or changed.

## Validation and limits

Validation completed without running implementation or qualification suites:

- All 1,687 local targets/anchors and code fences pass across 234 maintained
  Markdown documents, including this final inventory.
- Companion architecture JSON matches both embedded HTML payloads. All 24 component
  IDs, seven guided views, 29 connections, boundary references, source paths and
  component bounds validate; all three embedded JavaScript scripts pass `node --check`.
- All 4,857 protected tracked source, fixture, generated and historical evidence
  files match the before-review SHA-256 inventory, including the unrelated Rust
  protocol-test edit. The generated catalog declaration block remains unchanged.
- Earlier checkpoint bytes are identical after removing the new dated entry;
  archived September AGENTS sections match the original 3,550 bytes verbatim.
  Editor caches stay in place. All six repositories pass `git diff --check`.

These checks validate documentation integrity and navigation; they do not refresh
source/runtime qualification. The pre-review inventories and scratch validation
reports are in `/tmp/mirrors-doc-sync-20261009-*`; durable scope, outcomes and
changed paths are recorded here.
No implementation test suite, local/remote model checker, service action, package
publication or commit/push is included. Any future rebuilt package that includes
these docs needs refreshed artifact identities before installed-package acceptance.

## Exact changed-document inventory

48 documents changed across Mirrors and four linked client repositories. MirrorLean
was inspected and required no edit. Only documentation files changed during this task.

| Repository | Maintained document |
| --- | --- |
| Mirrors | [AGENTS.md](../AGENTS.md) |
| Mirrors | [CHANGELOG.md](../CHANGELOG.md) |
| Mirrors | [CHECKPOINTS.md](../CHECKPOINTS.md) |
| Mirrors | [Docs/README.md](../Docs/README.md) |
| Mirrors | [Docs/architecture-details.md](../Docs/architecture-details.md) |
| Mirrors | [Docs/architecture-overview.html](../Docs/architecture-overview.html) |
| Mirrors | [Docs/architecture-overview.json](../Docs/architecture-overview.json) |
| Mirrors | [Docs/architecture-overview.md](../Docs/architecture-overview.md) |
| Mirrors | [Docs/architecture-overview.txt](../Docs/architecture-overview.txt) |
| Mirrors | [Docs/client-implementation-guide.md](../Docs/client-implementation-guide.md) |
| Mirrors | [Docs/current-status.md](../Docs/current-status.md) |
| Mirrors | [Docs/cutover.md](../Docs/cutover.md) |
| Mirrors | [Docs/deterministic-scheduling.md](../Docs/deterministic-scheduling.md) |
| Mirrors | [Docs/framework-map.md](../Docs/framework-map.md) |
| Mirrors | [Docs/generated-model-interface-spec.md](../Docs/generated-model-interface-spec.md) |
| Mirrors | [Docs/model-interface-compiler/design.md](../Docs/model-interface-compiler/design.md) |
| Mirrors | [Docs/model-interface-compiler/tla-differential-validation-design.md](../Docs/model-interface-compiler/tla-differential-validation-design.md) |
| Mirrors | [Docs/model-interface-compiler/tla-frontend-design.md](../Docs/model-interface-compiler/tla-frontend-design.md) |
| Mirrors | [Docs/model-interface-compiler/tla-frontend-tasks.md](../Docs/model-interface-compiler/tla-frontend-tasks.md) |
| Mirrors | [Docs/model-interface-compiler/tla-language-profile.md](../Docs/model-interface-compiler/tla-language-profile.md) |
| Mirrors | [Docs/model-interface-generation-design.md](../Docs/model-interface-generation-design.md) |
| Mirrors | [Docs/model-interface-reduction.md](../Docs/model-interface-reduction.md) |
| Mirrors | [Docs/model-interface-runtime-distribution-design.md](../Docs/model-interface-runtime-distribution-design.md) |
| Mirrors | [Docs/native-build-design.md](../Docs/native-build-design.md) |
| Mirrors | [Docs/remote-server-guide.md](../Docs/remote-server-guide.md) |
| Mirrors | [Plans/documentation-sync-2026-10-09.md](documentation-sync-2026-10-09.md) |
| Mirrors | [Plans/execution-decisions.md](execution-decisions.md) |
| Mirrors | [Plans/framework-checkpoint-reference-2026-09-22.md](framework-checkpoint-reference-2026-09-22.md) |
| Mirrors | [Plans/m3-safe-reduction-design.md](m3-safe-reduction-design.md) |
| Mirrors | [Plans/m3-safe-reduction-implementation-plan.md](m3-safe-reduction-implementation-plan.md) |
| Mirrors | [Plans/m5-wsl-windows-remote.md](m5-wsl-windows-remote.md) |
| Mirrors | [Plans/mirror-framework-improvements.md](mirror-framework-improvements.md) |
| Mirrors | [Plans/mirror-framework-tasks.md](mirror-framework-tasks.md) |
| Mirrors | [Plans/roadmap-next-execution-2026-10-07.md](roadmap-next-execution-2026-10-07.md) |
| Mirrors | [Plans/tasks/compatibility-and-installation.md](tasks/compatibility-and-installation.md) |
| Mirrors | [Plans/tasks/durable-evidence.md](tasks/durable-evidence.md) |
| Mirrors | [Plans/tasks/gate-recovery.md](tasks/gate-recovery.md) |
| Mirrors | [Plans/tasks/reproduction-and-fidelity.md](tasks/reproduction-and-fidelity.md) |
| Mirrors | [README.md](../README.md) |
| Mirrors | [tools/deterministic-scheduling/README.md](../tools/deterministic-scheduling/README.md) |
| MirrorECMA | [README.md](../../MirrorECMA/README.md) |
| MirrorECMA | [docs/deterministic-scheduling.md](../../MirrorECMA/docs/deterministic-scheduling.md) |
| MirrorECMA | [docs/remote-server.md](../../MirrorECMA/docs/remote-server.md) |
| MirrorCPP | [README.md](../../MirrorCPP/README.md) |
| MirrorCPP | [docs/deterministic-scheduling.md](../../MirrorCPP/docs/deterministic-scheduling.md) |
| MirrorRust | [README.md](../../MirrorRust/README.md) |
| MirrorRust | [docs/deterministic-scheduling.md](../../MirrorRust/docs/deterministic-scheduling.md) |
| MirrorGate | [docs/remote-mirrors.md](../../MirrorGate/docs/remote-mirrors.md) |
