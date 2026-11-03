# Grok source and validation task

Goal: execute MW-00/MW-10 and prepare MW-20 in
`Plans/mainwork-stages-2026-11-03.md`, then deliver reproducible source-readiness
evidence for Codex review.

Read root AGENTS.md, CHECKPOINTS.md's newest entry, the stage plan,
Docs/current-status.md, Plans/execution-decisions.md, Docs/architecture-overview.md,
Docs/model-interface-runtime-distribution-design.md and the relevant distribution,
evidence and release contracts. Baseline HEAD is
`75fbf962020cea8a13e009ecfdb3e912e7ce212f`; preserve later/other edits.

Ownership: write only new files under
`Plans/mainwork-execution-20261103/source/` and task-owned temporary roots.
You are not alone in the codebase. Do not revert others' changes or edit source,
catalogs, locks, CHECKPOINTS.md, central ledger or other job output directories.
Report proposed fixes with exact file/line evidence for a later assignment.

Execute, rather than merely acknowledge:

1. Record HEAD/tree/status/cached tracking refs and read-only companion
   commit/tree/dirty state. Preserve pre-existing untracked work. Cached refs
   are not freshly observed remote publication.
2. Review `3ee3d92..HEAD` behavior/input changes and stale maintained-status
   claims. Assess new candidate/package invalidation precisely.
3. Run these focused suites from the repository root; retain raw stdout/stderr,
   exact argv, UTC timing and exit status for each:

   ```sh
   python3 -m unittest discover -s tools/distribution -p 'test_*.py' -v
   python3 -m unittest discover -s tools/release -p 'test_*.py' -v
   python3 -m unittest discover -s tools/evidence/tests -p 'test_*.py' -v
   ```

4. Reproduce any material finding with a minimal command or existing test;
   distinguish source bugs from environmental failures. Do not fix source yet.
5. Prepare the S1/S2 review list, explicit exclusions, final required gate
   commands and current-source remote observation recipe. No git mutation.
6. Write `report.md` and `result.json` including tasks, exact identities,
   command records, failures/skips, evidence limitations and next executable
   action. Include `inventory.json` of generated files with bytes/SHA-256
   (exclude the inventory itself). Use relative local output paths.

Constraints: no full Lean/native builds, no `lake test`, no local
Apalache/TLC, no network-dependent model runs, no external messages,
commit/push/tag/ref mutation, remote service operation or reboot. No credentials
or private-key bytes in any output. A failed command is retained, not hidden.

Done when all three commands actually ran, findings/receipts are inspectable,
and the report separates focused validation from final freeze/package/framework
qualification. Return a concise summary with paths and concrete blockers.
