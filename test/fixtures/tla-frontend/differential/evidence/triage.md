# Differential discrepancy review — 2026-09-13

Reviewed by the reviewer-role agent and integrating agent against the captured
[checkpoint A](checkpoint-a/report.json), its native logs, and the revision-1
language profile. Checkpoint A executed all 171 invocations with a stable
implementation. Its 27 failing comparisons reduce to the categories below.
This review does not authorize production frontend or frozen fixture changes.

| Comparisons | Classification | Disposition |
| ---: | --- | --- |
| 14 outcomes, seven fixtures on both references | Intentional revision-1 resource/policy differences | Approved narrowly for the exact source and tool fingerprints in `differences.json`, outcome field only |
| 2 Unicode outcomes | Baseline rationale drift | Unresolved: both pinned tools accept the staged spellings; the profile's historical reference-rejection statement is stale |
| 2 precedence outcomes | Profile/fixture compatibility defect | Unresolved: both references reject the unparenthesized mixed junction on line 15 of `AcceptPrecedence.tla` |
| 1 operator level | Frontend level-classification defect | Unresolved: `Enabled == ENABLED Increment` is state-level in SANY, temporal in Mirrors |
| 8 operator/level projections | Missing qualified named-instance observations | Unresolved: Mirrors omits `I!ChildOp` in four accepted instance fixtures while SANY exposes it |

## Narrowly approved differences

The approved fixtures are `rej-comment-depth`, `rej-identifier-size`,
`rej-control-character`, `rej-pluscal`, `rej-duplicate-declaration`,
`rej-real-literal`, and `rej-extends-ambiguity`. The language profile documents
these stricter limits/policies. Both pinned references accept them; duplicate
and ambiguous declarations produce SANY warnings, retained in the raw stderr
artifacts. Each registry entry binds one fixture, one external engine, the
outcome field, exact normalized source hashes, both tool fingerprints, this
review, and the checkpoint report. A changed source/tool/profile or additional
comparison requires renewed review. This does not excuse execution failures,
missing structural facts, or any other field.

## Follow-up work outside this implementation

- Reconcile the mixed `/\` and `\/` precedence profile with the pinned references;
  preserve a negative unparenthesized case if the accepted fixture is corrected.
- Correct `ENABLED` level classification in the frontend with a focused regression.
- Expose qualified named-instance operators/levels from the existing elaboration
  facts; do not implement a second elaborator in the differential adapter.
- Decide whether to retain the ASCII-only profile or support the pinned Unicode
  aliases, and update the stale compatibility rationale through profile review.

The richer substitution expression/declaration-identity surface remains
uncertified: this checkpoint compares atomic actual values/spellings and
explicit/implicit site records. Apalache structural normalization, external
native-to-Mirrors stage mapping, and lexical/CST equivalence remain unsupported
coverage surfaces. Outcome agreement between SANY and Apalache is correlated
because the latter also uses SANY.
