# Mixed-junction precedence correction

> Status: **implemented and validated, 2026-09-13; JP0–JP4 accepted**.
> Scope: the precedence finding from [differential triage](../../test/fixtures/tla-frontend/differential/evidence/triage.md).
> Delivery: [implementation tasks](../../Drafts/tla-junction-precedence-tasks.md).
> Authority: [frontend compatibility](tla-frontend-design.md#5-compatibility-authority)
> and [profile revision rules](tla-language-profile.md#2-profile-identity-and-revision-rules).

## 1. Decision

Give canonical conjunction `/\` and disjunction `\/` one precedence level in
the default parser profile, with `OperatorAssociation.same` for both. A chain
may repeat one canonical operator, but an unparenthesized mixture is rejected.
Parentheses and properly indented prefix-junction lists establish their own
grouping boundaries. Publish this acceptance change as profile revision 2.

This corrects the demonstrated junction conflict. It does not establish that
the rest of the integer-level operator table implements TLA+'s full precedence
relation. A general precedence-interval redesign is separate work.

## 2. Current failure and implementation cause

`accepted/AcceptPrecedence.tla` currently contains:

```tla
MixedJunction == A /\ B \/ C
```

Mirrors accepts it as `(A /\ B) \/ C`. The pinned SANY and Apalache runs both
reject it with a precedence conflict. The local shape test also asserts the
incorrectly admitted grouping, so retaining that expectation would preserve the
bug rather than protect compatibility.

Relevant implementation points:

- `Core/Tla/Parser.lean`: `levelDisjunction = 3`, `levelConjunction = 4`;
  the default table places both operators in association class `.same`.
- `associationConflict`: different canonical operators in that class conflict
  when encountered in the same precedence-level chain.
- `parseExpressionLevel`: parses tighter operands recursively and tracks the
  chain's first operator locally. The current unequal levels prevent that
  conflict check from seeing the two junction operators together.
- `tools/TlaParserSpec.lean`: `scenarioPrecedenceShapes` explicitly accepts the
  mixed expression and expects disjunction over conjunction.

The compatibility rule is supported by the recorded native rejection. TLA+
precedence generally admits incomparable operator combinations rather than
imposing a total ordering; see [Lamport's parsing explanation](https://lamport.azurewebsites.net/tla/tutorial/parsing.html).

## 3. Required behavior

The following examples assume declared operands. They describe the proposed
revision-2 parser behavior; they are not claims of tests executed by this task.

| Expression | Result |
| --- | --- |
| `A /\ B /\ C` | accept homogeneous conjunction chain |
| `A \/ B \/ C` | accept homogeneous disjunction chain |
| `A /\ B \/ C` | reject at the second, conflicting operator |
| `A \/ B /\ C` | reject at the second, conflicting operator |
| `(A /\ B) \/ C` | accept explicit left grouping |
| `A /\ (B \/ C)` | accept explicit right grouping |
| `(A \/ B) /\ C` | accept explicit left grouping |
| `A \/ (B /\ C)` | accept explicit right grouping |
| `A /\ B \land C` | accept: both spellings denote conjunction |
| `A \land B \lor C` | reject after alias normalization |

Longer chains must follow the same rule: `A /\ B /\ C \/ D` is rejected.
Whitespace and comments do not establish grouping. Parentheses inside a larger
expression reset the local chain check; the parser must not infer a conflict
merely from the operator at the root of a parenthesized AST subtree.

Existing relative behavior with arithmetic, relations, negation, implication,
and equivalence must remain covered. This package does not silently revise their
precedence or associativity rules.

## 4. Parser change

Introduce one junction-level constant, using the current disjunction level 3.
Both junction table entries use it and retain `.same`. Existing public level
names may remain as aliases to the common level to avoid unnecessary call-site
churn; update their comments and audit every use. Leave the remaining levels
unchanged, including the unused numerical gap if one remains.

Retain the existing table-driven `associationConflict` path. Do not add a source
regex, token pre-scan, or AST post-check that bans mixtures regardless of scope.
The parser must still consume supplied `ParserProfile` tables; custom-table tests
should prove that the default behavior comes from data rather than a hard-coded
junction prohibition.

The prefix-list entry test currently recognizes junctions by numerical level.
Change that recognition to the canonical junction identities `/\` and `\/`.
Numerical precedence controls binding, not whether an operator is a list marker.
Keep alias normalization in `LanguageProfile`/the lexer.

Do not change generic error recovery as part of this correction. The existing
halting conflict path can remain even though its helper is named `emitLimit`:
the public result is an error at stage `parse`, code
`TLA-PARSE-PRECEDENCE-CONFLICT`, reason `malformed`, not a resource-limit result.
Its primary range covers the conflicting operator's original spelling. There
must be no successful module or admitted partial elaboration after the error.

## 5. Prefix-junction and delimiter boundaries

Sharing a level makes prefix-list handling a required regression surface.
Preserve valid homogeneous lists and properly indented nested lists:

```tla
P == /\ A
     /\ B

Q == /\ A
     /\ \/ B
        \/ C
```

JP0 corrected the original design assumption about mixed list markers. Both
pinned parsers accept a prefix conjunction list followed by a disjunction at
the same indentation: the conjunction list ends and becomes the left operand
of the disjunction. The retained Apalache IR distinguishes these forms:

- `Value == /\ A` followed by aligned `\/ B`: `OR(AND(A), B)`;
- `Value == /\ A \/ B` on one line: `AND(OR(A, B))`;
- the nested list above: `AND(A, OR(B, C))`.

See the [JP0 matrix and native evidence](../../test/fixtures/tla-frontend/differential/evidence/junction-precedence-jp0-r5/README.md).
The parser must preserve these grouping boundaries, including continuation of
an enclosing infix chain after a completed prefix list. A list item's grammar
boundary is not equivalent to a flat unparenthesized infix chain: do not apply
a blanket mixed-token ban to an entire multiline expression. Further layout
expectations must also be qualified before being frozen.

Exercise parentheses containing lists, nested `IF`/`LET` bodies, comments,
multiline infix continuations, and the existing `junctionBoundaryColumn` behavior.
Keep lossless CST reconstruction and byte ranges unchanged for accepted sources.
Existing nesting, fuel, token, and diagnostic limits remain authoritative.

## 6. Profile and corpus migration

This changes which source strings are accepted. It therefore requires
`mirrors-tla-frontend-profile-2`; do not silently alter the meaning of the default
profile while continuing to label it revision 1.

Update the default `LanguageProfile` and `ParserProfile` identities together,
name the new default operator table consistently, and audit explicit profile-1
references in live consumers/tests. Do not infer parser selection from an
arbitrary profile-name string or add a legacy-mode dispatcher. Existing archived
revision-1 evidence remains immutable. Any existing profile-keyed cache must
distinguish the new identity; creating a cache is not part of this work.

Proposed corpus changes:

1. Keep `acc-precedence` accepted by parenthesizing its `MixedJunction`
   definition as `(A /\ B) \/ C`. Its intended AST grouping remains the same,
   but source hashes and CST positions must reflect the actual edited text.
2. Add two rejected fixtures for the original unparenthesized expression and
   its reverse ordering, each isolated so the first conflict is independently
   observable. Both expect parse/malformed and the existing diagnostic code.
3. Add one accepted grouping fixture covering homogeneous chains, all four
   parenthesized forms, and supported ASCII aliases. Use focused unit/calibration
   probes for layout permutations rather than multiplying corpus files for
   every whitespace variation.

That proposed inventory is 60 fixtures: 33 accepted and 27 rejected. Derive the
actual counts and branch links from the finished manifest; do not hard-code them
into the runner. Give new cases stable IDs and owning profile branches.

Update the live manifest and expected-summary profile identities to revision 2.
Regenerate affected structural summaries through a deterministic producer from
the real frontend; do not hand-edit hashes or expected AST renderings. Existing
model-interface artifacts still use `model_interface_gen` for regeneration and
`check` for validation. If no reusable frontend-summary producer exists, add a
small test-tool exporter or expose the existing spec's summary projection; do
not introduce another parser or derive observations from expected files.

The existing summary, inspection, lock, and protocol schemas need no version
change solely because a profile value changes. Previously accepted, unaffected
model-interface sources must retain byte-identical locks/generated output.

## 7. Differential evidence and acceptance

Keep the SANY/Apalache artifacts and Java pins unchanged. First qualify the small
behavior matrix, then run the entire revised corpus. Corrected `acc-precedence`
must be accepted by all three tools; both new negative cases must be rejected;
the grouping/alias fixture must be accepted with the expected Mirrors ASTs.

The fourteen reviewed policy entries bind the old profile and Mirrors binary.
They cannot be copied forward by replacing hashes mechanically. Re-observe the
same seven policy fixtures, review their unchanged rationale against revision 2,
and create renewed entries with exact profile/source/tool identities and evidence.
Preserve old registry content through the archived snapshots/repository history.
No reviewed exception may excuse the precedence defect itself.

Two complete runs with a stable implementation must produce identical semantic
payloads, retaining raw evidence and all fixture rows. The two original
`acc-precedence` outcome disagreements should disappear. Overall acceptance may
still fail because Unicode policy, ENABLED levels, and named-instance projection
work remain outside this package; do not promise a green aggregate or assume its
failure count without inspecting the new results.

Require focused parser tests, all six frontend gates, `lake build`, `lake test`,
and existing model-interface golden checks. Include a negative control restoring
different junction levels in a temporary test profile: the mixed-chain rejection
test must detect that regression. Verify that the original unparenthesized source
is rejected through the development CLI and compiler source-admission path, not
only through a parser helper.

## 8. Non-goals and completion

This package does not fix ENABLED, broaden Unicode support, expose qualified
instance operators, redesign all TLA+ precedence intervals, change wire/target
contracts, or rewrite existing evidence checkpoints. Treat newly exposed issues
outside junction handling as findings, not opportunistic repairs.

Completion requires the new default rule, honest profile migration, focused
positive/negative/layout evidence, unchanged unaffected generated bytes, and
recorded differential closure of the precedence finding. Design publication
alone satisfies none of those implementation gates.
