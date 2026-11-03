# MW-12 source implementation

Execute this bounded task now; do not return another plan. Baseline HEAD is
`75fbf962020cea8a13e009ecfdb3e912e7ce212f`. The user requested continuation of
the reviewed mainwork stages with Grok execution and Codex review.

Own **only** `Shell/Version.lean`, `tools/distribution/refresh_identity.py`,
`tools/distribution/test_refresh_identity.py`, and new evidence files under
`Plans/mainwork-mw12-20261103/source/`. You are not alone in the checkout;
preserve others' edits. Do not edit generated catalogs/locks or historical
evidence. Codex will own final catalog/registry integration and checkpointing.

Read root AGENTS.md, the relevant product/refresh contract in Docs/versioning.md
and Docs/framework-catalog-contract.md, then the three owned files. Do not
repeat the previous wide source audit. The concrete defect is that the refresh
copies stale catalog product `Mirrors 0.1.1` despite the selected source declaring
`0.2.0-rc.5`. `update_locks` should still propagate the catalog by component ID.

Implement:

1. Prepare source version `0.2.0-rc.6` in Shell/Version.lean. Existing rc.1–rc.5
   tags are immutable; create no tag and perform no Git ref mutation.
2. Make catalog refresh obtain the Mirrors product version from the selected
   local Mirrors source declaration before calculating catalog selection. Sync
   that product into the component-owned Mirrors record when that record is
   requested. Leave other components' declared products alone. Preserve the
   `--skip-component-records` / `--skip-render` semantics and existing API callers.
3. Fail before catalog writes if the source version is missing, malformed or
   ambiguous. Reuse an appropriate existing parser or keep the source parser
   narrow; avoid unrelated refactors or permissive fallback to stale metadata.
4. Add meaningful regressions covering stale catalog→source version correction,
   owned-record consistency, skip behavior and invalid declaration refusal.
   Keep the existing lock-product propagation test. Run the focused refresh
   module tests and full distribution Python suite with a task-owned ext4
   TMPDIR under `.golden-build/mw12-20261103/`. No full Lake/native build.

Write a short `report.md` (<=100 lines), `result.json` with exact commands,
exit codes/log hashes and limitations, and `inventory.json` with generated-file
bytes/SHA-256 excluding itself. Retain raw logs. Return actual changed paths
and test counts. No commit/push/tag, remote model/service operation, local
Apalache/TLC, full build or changes outside the owned scope. Stop after edits,
focused validation and evidence; Codex reviews and integrates the candidate.
