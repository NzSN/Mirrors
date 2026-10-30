# Generic-executor completion handoff

Date: 2026-10-30

## Authority and scope

The user requested: "perform these plan via generic-executor".

This handoff authorizes execution of S0.1-S0.4 and S1.1-S1.6 in
[the completion execution plan](completion-qualification-release-plan-2026-10-30.md).
The normative rules are in
[the completion design](../Docs/completion-qualification-release-design.md).
S1.7 is a review handoff only. S2 branch publication and S3 local tag creation
are not authorized. No tag push, package publication, production deployment,
service replacement, or reboot is authorized.

## Shared-tree rules

- The checkout is dirty and shared. Preserve all existing changes and unrelated
  files. Do not reset, clean, checkout over, stage, commit, or push.
- Other agents may work in the repository. Do not revert their edits.
- Do not alter dated evidence receipts. Create new execution records under
  `Plans/completion-release-evidence-20261030/`.
- Do not run local Apalache or TLC. Use the repository-owned no-model gate.
- Do not contact or replace a production service for S0/S1.

## Required work

1. S0: inventory and classify every changed path; index the October 29 accepted
   results, failures, skips, and limits; record actual host facts; create the
   S0-S8 stage ledger with explicit external blockers.
2. S1.1-S1.2: review the candidate diff and run formatting, document-link, and
   focused checks needed for files changed after their last validation.
3. S1.3: run `python3 Plans/completion-evidence-20261029/verify.py`. Regenerate
   its inventory only if a payload file legitimately changed, and record why.
4. S1.4: audit intended evidence tracking despite ignore rules and scan the
   proposed delivery payload for private material, credentials, binaries, tool
   archives, and unreviewed generated files. Do not print secret contents.
5. S1.5: preflight loopback and an ext4 task-owned temporary root, then run
   `bash tools/run-local-no-model-check.sh` and
   `bash tools/check-native-rebuild.sh`. Retain exact commands, exits, and
   skipped live tiers. Sandbox/tmpfs failures are environmental diagnostics,
   not source failures or passing evidence.
6. S1.6: freeze the reviewed source/companion/tool identities and validation
   snapshot in the new evidence directory. Produce a human-readable summary
   and the exact proposed S2 delivery file list with exclusions.

If a check exposes a concrete source defect, retain the failure, make only a
focused repair with regression coverage, and restart the affected S1 checks.
Do not broaden the task into external qualification.

## Completion report

Report each S0/S1 task as passed, failed, or blocked; exact gate results;
files created or modified; remaining approval/external gates; and the proposed
S2 payload. Do not claim release, native M4, full framework, or deployment
acceptance from these local checks.

