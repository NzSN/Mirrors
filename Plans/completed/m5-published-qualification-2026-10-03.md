# Published-revision M5 qualification — 2026-10-03

Status: complete for `m5-wsl-windows-remote/v1`.

Apply the documentation correction and qualify the published component revisions
under the unchanged `m5-wsl-windows-remote/v1` profile. The earlier working-tree
qualification remains historical. No source implementation changes are planned.

1. Correct the stale M6 status wording; verify published component revisions and
   pin-matched compatibility checkouts.
2. Refresh identities to byte stability with zero included implementation edits;
   snapshot, build both caches, and transactionally install both distributions.
3. Run both D audits first, then all 18 required commands across 16 tiers.
4. Verify the linked Q1 scope, archive fresh evidence, run independent isolated
   Q2 and six rejection controls, then recheck final identities.
5. Write Q3, update current milestone/status records and preserve checkpoint history.

Native Ubuntu, aggregate cgroups, active-process recovery, Windows service-manager
acceptance and the legacy all-transport matrix remain outside this profile.
Use only the owned Windows oracle; Windows writes remain inside MirrorsRemote.
Publication of resulting evidence records is separate from the frozen source refs.

## Execution record

- M6 footer corrected. Separate compatibility checkouts match the existing pins.
- Published Mirrors `291961577b408cc135afe201f272ca684dc622e3`, MirrorECMA
  `a03cf10a8787ff7691a4fd8b8f1013667501dfb7` and MirrorGate
  `455e196c73332a1b0d85b1d822dfc4aa3542bbd9` selected.
- C0 `f01fb7717ca9bab18a68443707f478d49c15a15d420273db1e881c9683b16384`
  reached byte stability after three refreshes. All included implementation-path
  sets are empty; the candidate uses the published revisions.
- Native oracle PID 2572 remains unchanged, Apalache 0.62.2 / Java 25.0.4+7-LTS.
- Snapshot and build artifacts: `/tmp/m5-published-20261003*`.

- Both caches built and installations committed; both D audits ran first.
- All 18 commands/16 tiers passed; independent Q2 verified 20 bundles and the
  19-node/two-D scope, with all six negative controls rejected.
- Source-hidden LeaseService acceptance and final identity checks passed.
- Evidence retained at `~/.local/state/mirrors/m5-published-20261003`.
- [Published-revision Q3](q3-published-2026-10-03.md), checkpoint and current status
  records updated. No new source commit was introduced by this campaign.
