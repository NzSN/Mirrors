# Grok downstream task and handoff preparation

Goal: prepare MW-30/MW-60/MW-65/MW-70/MW-80 from
`Plans/mainwork-stages-2026-11-03.md` as executable downstream task cards and
reviewable release/operation/compatibility templates.

Read root AGENTS.md, the stage plan, Docs/completion-qualification-release-design.md,
Plans/completion-qualification-release-plan-2026-10-30.md,
Docs/qualification-harness-design.md, tools/evidence/README.md,
tools/evidence/commands.json, Docs/versioning.md, Docs/ecosystem-versioning.md,
tools/release/release.py, .github/workflows/release.yml,
Plans/compatibility-lifecycle-decision-2026-10-29.md and relevant DPM contracts.
Current source is `75fbf962020cea8a13e009ecfdb3e912e7ce212f`.

Ownership: new files only in
`Plans/mainwork-execution-20261103/handoff/` and task-owned temporary roots.
You are not alone in the checkout. Preserve others' work; no edits to source,
existing docs/evidence, catalogs, locks, central ledger or CHECKPOINTS.md.

Produce:

1. `tasks.md`: argument-complete downstream task cards covering clean Linux
   and Windows packaging, final M5 producer membership, remote 22-row clients,
   three installed DPM profiles and full Windows acceptance. Derive exact
   command IDs/required profile membership from current registry, not counts
   copied from dated prose. Identify every required and supporting origin.
   For unresolved identities use named inputs and origin/validation rules.
2. `verification.md`: actual Q1/Q2 entry points/arguments, installed runtime
   bindings, DAG ordering, source/network isolation, six required negative
   controls and owned-backend stop prerequisites. No oracle stop is executed.
3. `release-handoff.md`: claim matrix template, immutable unused tag/version
   proposal rule, package bindings, final review checklist and release-note
   template. Never silently retag rc.5 or treat template rows as accepted.
4. `operations.md`: concrete operation cards with required host/path/hash/ref
   inputs, trigger/commands, expected receipts, abort and rollback criteria,
   distinct tag/workflow publication, Windows asset, candidate-port checks,
   production replacement and reboot boundaries. Unknown current values remain
   explicit. Prepare only; no mutations or remote contact.
5. `compatibility-retention.md`: ledger templates for public/private retention,
   two consecutive shipped-cycle matrices, real-workload hashes/counts/byte
   differences/incidents, consumer acknowledgements and fallback tests. Retain
   register_error and Haskell/golden contracts; no retirement or soak credit.
6. `result.json` and `inventory.json`: exact HEAD/tree, task completion scope,
   validations actually performed, generated paths/bytes/SHA-256 (inventory
   excludes itself), unresolved inputs and next executable action.

Validate commands against current parsers/source without starting builds or
model checkers. Templates and task cards are preparation only. No full build,
`lake test`, local Apalache/TLC, downloads, commits/tags/push/PRs, external
messages, publication, remote operation or reboot. No credential bytes.

Done when dependency ordering and current command contracts are inspectable,
all remaining stages have executable work/receipts/exit gates, and Codex can
distinguish completed preparation from unexecuted qualification and operations.
