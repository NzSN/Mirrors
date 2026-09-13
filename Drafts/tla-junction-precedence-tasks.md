# Mixed-junction precedence implementation tasks

> Status: **JP0–JP4 completed and accepted, 2026-09-13; broader differential gate still fails**.
> Authority: [mixed-junction design](../Docs/model-interface-compiler/tla-junction-precedence-design.md).

## Final acceptance

The coordinating assistant accepts JP0–JP4. `specification_implementer`
implemented the parser/profile packages and independently approved all fourteen
policy renewals; the worker following `test-automator` instructions qualified
references, checked compiler admission, and produced the final evidence.

[Checkpoints J and K](../test/fixtures/tla-frontend/differential/evidence/README.md)
each contain 180 completed observations over 60 fixtures. Their semantic payloads
are byte-identical (SHA-256
`5dd32f9003de7c09771dac69282be01a853fcf5dfd11c4302011b6bf3da3f354`):
540 matches, 14 reviewed policy differences, 11 failures, and 285 unsupported
comparisons. No precedence exception is installed. The remaining failures are
Unicode acceptance (2), ENABLED levels (1), and named-instance projections (8).

`lake build` and `lake test` passed, including live Apalache and permitted
loopback. All four model-interface golden hashes remained unchanged. The final
offline differential suite passed 54 tests, with four opt-in live tests skipped;
the separate full reference runs provide the recorded live corpus evidence.

## 1. Scope and ownership

Correct the conjunction/disjunction precedence finding only. Preserve unrelated
frontend semantics and existing evidence. The assigned agents are
`test-automator` and `specification_implementer`. The packages below record their
responsibilities, acceptance criteria, and completed handoffs.

| Package | Assigned owner | Prerequisite | Review/handoff |
| --- | --- | --- | --- |
| JP0 — reference matrix | `test-automator` | none | `specification_implementer` checks that observations are sufficient to implement the rule |
| JP1 — parser correction | `specification_implementer` | accepted JP0 matrix | `test-automator` reviews the parser change and regression coverage |
| JP2 — profile/corpus migration | `specification_implementer` | JP1 handoff | `test-automator` verifies profile consistency, regenerated facts, and corpus coverage |
| JP3 — compiler/compatibility checks | `test-automator` | JP2 complete | `specification_implementer` investigates implementation failures within JP1/JP2 scope |
| JP4 — differential closure | `test-automator` | JP3 gates pass | `specification_implementer` cross-checks evidence and registry renewal; coordinating assistant records final acceptance |

`specification_implementer` owns shared implementation documentation, profile
identity migration, and any necessary Lake wiring through JP2. After handoff,
`test-automator` owns JP4's evidence and status updates. The coordinating assistant
accepts package handoffs and resolves ownership or scope conflicts.

One owner edits each file at a time. JP1 and JP2 both touch
`Core/Tla/Parser.lean` and must remain sequential. JP3 does not repair production
code opportunistically: it reports a failing case to `specification_implementer`
with a bounded follow-up scope, then reruns the affected gate after handoff.
Both agents preserve unrelated changes and may not weaken expectations or
rewrite historical evidence to obtain a pass.

Each handoff records changed files, exact commands and exit results, evidence
paths, and remaining findings. Review by the other agent is read-only unless
ownership is explicitly transferred. JP4 cross-checking is independent of the
evidence producer; it is not a claim that the parser author independently audited
their own implementation. The parser/corpus review belongs to `test-automator`.

## 2. JP0 — freeze the compatibility matrix

**Owner:** `test-automator`.
**Handoff:** recorded compatibility matrix and consumer/exporter inventory to
`specification_implementer` before JP1 starts.
**Files:** focused calibration tests under `tools/tla-differential/tests/` and
an execution note; no production edits.

- Qualify both mixed orders, homogeneous chains, four parenthesized forms,
  ASCII aliases, and prefix-list/layout boundaries against the existing pins.
- Show the current Mirrors default admits the original offending expression.
- Confirm how the shared-level `.same` mechanism can express the correction.
- Inventory live profile-1 consumers and the available summary-generation path.

**Acceptance:** exact observed outcomes and native logs are recorded; no guessed
layout expectations or broader precedence claims enter the next package.

## 3. JP1 — parser rule and focused regressions

**Owner:** `specification_implementer`.
**Reviewer:** `test-automator`, read-only; JP1's focused acceptance precedes the
full migrated-corpus acceptance in JP2.
**Files:** `Core/Tla/Parser.lean`, `tools/TlaParserSpec.lean`.

- Put both canonical junctions at one level with `.same` association.
- Identify prefix-list markers by canonical spelling rather than numeric level.
- Replace the old accepted unparenthesized shape assertion with a grouped case.
- Add mixed-order rejection, longer chains, alias, parenthesis-scope, nested
  expression, prefix-list, and exact error-range checks.
- Preserve generic table customization, bounded recovery, and lossless CSTs.

**Acceptance:** focused tests pass; parse errors are malformed precedence
conflicts with no successful module. Temporarily restoring the old unequal
levels is detected by the negative controls. Other precedence classes retain
their existing tested behavior.

## 4. JP2 — profile and corpus revision

**Owner:** `specification_implementer`, after JP1 handoff.
**Reviewer:** `test-automator`, including generated-summary provenance and profile
identity consistency.
**Files:** default identity in `Core/Tla/Lexer.lean` and `Core/Tla/Parser.lean`,
live profile documentation, corpus manifest, accepted/rejected fixtures and
generated summaries; affected profile-identity tests. Summary-export tooling
only if the inventory shows it is necessary.

- Introduce default profile 2 consistently without a silent revision-1 fallback.
- Parenthesize the accepted precedence fixture; add two mixed-order rejections
  and one accepted grouping/alias fixture.
- Regenerate live summary metadata and affected source/AST facts from the real
  frontend. Keep historical evidence intact.
- Audit profile-keyed cache identity and record whether any persistent cache
  exists; do not introduce new caching infrastructure.

**Acceptance:** manifest/schema/link checks and the complete parser corpus pass;
proposed counts are reconciled with actual fixtures and branch coverage. The
new profile labels the new grammar everywhere in the active default pipeline.

## 5. JP3 — compiler and compatibility checks

**Owner:** `test-automator`, after JP2 handoff.
**Files:** focused frontend/compiler tests only; any additional shared wiring
belongs to `specification_implementer` under an explicit handoff.

- Exercise the bad source through CLI and compiler admission, proving that it
  cannot produce a successful lock/proposal after parser rejection.
- Check corrected source and all unaffected model-interface golden outputs.
- Run all six frontend gates, `lake build`, and `lake test`; record unavailable
  environment tiers separately from assertion failures.

**Acceptance:** source admission fails closed for the conflict; corrected
examples succeed; unaffected generated output remains byte-identical; no wire
or target version changes.

## 6. JP4 — reviewed differential closure

**Owner:** `test-automator`, for execution, registry proposals, and evidence/status
updates.
**Cross-review:** `specification_implementer` checks raw evidence, exact registry
scope, repeatability, and remaining findings without editing the evidence under
review. The coordinating assistant makes the final acceptance decision.
**Files:** renewed policy registry entries, new evidence checkpoint, frontend
task ledger, differential task status, and this plan.

- Re-observe and review the seven existing policy differences under profile 2
  and the rebuilt Mirrors artifact before renewing the fourteen exact entries.
- Run the full revised corpus twice with unchanged implementation and pins.
- Confirm closure of the original precedence disagreements and correct outcomes
  for every added fixture; investigate any unexpected new failures.
- Record remaining unrelated failures and unsupported comparison surfaces.

**Acceptance:** source/harness snapshots and raw evidence verify; repeated
semantic payloads match; the precedence finding is closed without an allowlist
entry. Do not mark the whole frontend task group complete while other findings
remain.

## 7. Checklist

- [x] JP0: reference and layout matrix qualified (48 observations plus layout supplements).
- [x] JP1: shared junction rule and regressions implemented and independently checked.
- [x] JP2: profile-2 corpus migration verified, including complete summary generation.
- [x] JP3: compiler refusal, unchanged generated bytes, build and full Lake gates verified.
- [x] JP4: reviewed, reproducible precedence closure recorded.
