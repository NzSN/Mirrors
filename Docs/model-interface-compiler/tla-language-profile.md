# Mirrors TLA+ frontend language profile (revision 1)

> Status: **proposed revision-1 profile, frozen with the TF0 corpus on 2026-09-11**.
> Design authority: [general TLA+ frontend design](tla-frontend-design.md).
> Task package: [TLA+ frontend tasks](tla-frontend-tasks.md), package TF0.
> Conformance corpus: [`test/fixtures/tla-frontend/manifest.json`](../../test/fixtures/tla-frontend/manifest.json).
> Differential status: **not run against pinned baselines**. The pinned SANY and
> Apalache versions are owned by the coordinating agent; the corpus records
> `not_run` placeholders rather than conformance claims.

## 1. Scope and authority

This profile fixes what the Mirrors TLA+ frontend accepts, rejects, and records.
It is the profile that `Core.Tla.LanguageProfile` must instantiate and the
profile that the frozen corpus in `test/fixtures/tla-frontend/` encodes.

The frontend is a compiler input module. This profile does not change the
Mirrors wire protocol, model-interface locks, StateComputer contracts, generated
targets, MirrorECMA APIs, or MirrorGate records.

Compatibility rules inherited from the design:

- Mirrors must not define an accidental TLA+ dialect; every accepted or rejected
  construct has an owning fixture in the corpus.
- A module accepted by Mirrors but rejected by both compatibility oracles is a
  frontend finding unless a reviewed profile difference covers it.
- A module rejected by Mirrors but accepted by the baselines is either a
  documented limit or a defect, and must never be silently classified as
  malformed evidence.
- Differential comparison is about outcomes and structural facts, not external
  error wording.

## 2. Profile identity and revision rules

| Item | Revision-1 value |
| --- | --- |
| Profile id | `mirrors-tla-frontend-profile-1` |
| Corpus manifest schema | `mirrors.tla-frontend-corpus/1` |
| Structural summary schema | `mirrors.tla-frontend-summary/1` |
| Source identity | normalized UTF-8 bytes, CRLF and CR normalized to LF, SHA-256 |
| Pinned SANY baseline | placeholder; owned by the coordinating agent |
| Pinned Apalache baseline | placeholder; owned by the coordinating agent |

A profile revision is required to change any of the following, and each change
must be reviewed with the corpus diff:

- an accepted or rejected spelling, production, or declaration form;
- the standard-module catalog identity or its declaration facts;
- a resource limit that fixtures exercise;
- the list of intentional differences from the reference baselines;
- the semantics of a truncated profile area such as `INSTANCE` substitution.

Cache keys must include the profile id, the catalog revision, and the limits
revision. Cached elaboration facts from another profile revision are invalid.

## 3. Module structure

- A module begins with a header line of the form
  `---- MODULE Name ----`: at least four leading dashes, the keyword `MODULE`,
  the module name, and at least four trailing dashes.
- The declared module name must equal the logical identity requested from the
  provider, which for borrowed roots is the file base name.
- The module body ends with a terminator line of at least four `=` characters.
- A module without a terminator is rejected at the `parse` stage
  (`rej-no-terminator`).
- Text after the terminator is not part of the module body; revision 1 accepts
  trailing whitespace and rejects any further module content.
- Exactly one module is captured per logical identity; a second source for the
  same identity is a `moduleGraph` error (`rej-duplicate-module`).

## 4. Lexical profile

### 4.1 Characters, whitespace, and line endings

- Source is captured as bytes, decoded as UTF-8, and normalized so that CRLF and
  CR become LF before lexing. Source hashes are computed over those normalized
  bytes, never over an AST or a pretty-printed form.
- Space, tab, and LF separate tokens. Tab counts as one byte and one column.
- Control characters other than tab, LF, and CR are errors
  (`rej-control-character`). This is deliberately stricter than the local
  reference parser, which ignores the byte; the design requires the frontend to
  reject unknown control characters.
- A byte sequence that is not valid UTF-8 is a source-unit error; it cannot be
  represented as a tracked text fixture, so `Core.Tla.Source` owns that unit
  test.

### 4.2 Identifiers and reserved words

- An identifier starts with a letter or `_` and continues with letters, digits,
  or `_`. Revision 1 does not accept quoted or numeric-leading identifiers.
- Qualified instance references use `Name!Declaration` and are lexed as a
  qualified name, not as two identifiers plus punctuation.
- Reserved words cannot be declared or used as names (`rej-keyword-identifier`).
  The reserved set covers at least: `MODULE`, `EXTENDS`, `CONSTANT`,
  `CONSTANTS`, `VARIABLE`, `VARIABLES`, `INSTANCE`, `LOCAL`, `RECURSIVE`,
  `ASSUME`, `ASSUMPTION`, `AXIOM`, `THEOREM`, `LEMMA`, `PROPOSITION`,
  `COROLLARY`, `OBVIOUS`, `OMITTED`, `PROOF`, `LET`, `IN`, `IF`, `THEN`,
  `ELSE`, `CASE`, `OTHER`, `CHOOSE`, `ENABLED`, `UNCHANGED`, `SUBSET`, `UNION`,
  `DOMAIN`, `EXCEPT`, `WITH`, `TRUE`, `FALSE`, `BOOLEAN`, `STRING`, `WF_`,
  `SF_`, and every ASCII operator spelling listed in §4.7.

### 4.3 Integer literals

Revision 1 accepts the same integer spellings as the reference lexer, and each
fixture in `acc-numeric-spellings` pins one:

| Spelling | Example | Value |
| --- | --- | --- |
| decimal | `255` | 255 |
| octal | `\o377` | 255 |
| hexadecimal | `\hFF` | 255 |
| binary | `\b11111111` | 255 |

The lexer normalizes every spelling to an integer value; the AST does not carry
the original radix. `\o` is ambiguous with the user-visible concatenation
operator spelling, so the lexer must prefer the numeric reading when `\o`,
`\h`, or `\b` is immediately followed by digits.

Decimal real literals (`1.5`, `1.5e3`) are valid TLA+ and the local reference
probe accepts them, but revision 1 keeps an integer-only numeric value domain
and stages them out: the `lex` stage reports a profile-limit diagnostic naming
the literal (`rej-real-literal`). Carrying reals in the AST value domain is a
profile revision; the staged fixture records `reason: profile_limit` and
`revisit: unscheduled`. Spellings outside the integer table and the staged real
form are malformed at `lex`.

### 4.4 Strings and escapes

- A string is terminated on the same line; a newline inside a string is a
  lexical error (`rej-newline-in-string`).
- An unclosed string is a lexical error (`rej-unterminated-string`).
- Revision 1 accepts the escapes `\"`, `\\`, `\n`, `\t`, `\f`, and `\r`
  (`acc-values`). Any other escape is rejected at `lex`.

### 4.5 Comments

- `\*` starts a line comment that ends at the next LF (`acc-trivia`).
- `(*` starts a block comment that ends at the matching `*)` and nests
  (`acc-trivia`). An unclosed block comment is a lexical error
  (`rej-open-comment`).
- Block comment depth is limited (see §8); exceeding the limit is a bounded
  limit failure, not a parse error (`rej-comment-depth`).
- Comments and strings never create module edges: dependency keywords inside
  them are inert (`acc-trivia`, `graph.lexical-false-positive`).

### 4.6 Annotations

- A line comment whose first non-space character is `@` is captured as an
  annotation trivia item with a kind and a payload
  (`acc-annotations`).
- `@type: ...;` is classified as `apalache.type`; other `@name` prefixes keep
  `annotation:<name>`.
- Revision 1 records annotation trivia in the token stream and in structural
  summaries but derives **no** semantic facts from it: annotations never create
  declarations, types, or evidence.

### 4.7 Operator spellings

| Class | Revision-1 decision | Fixture |
| --- | --- | --- |
| Symbolic ASCII (`/\`, `\/`, `~`, `=>`, `<=>`, `#`, `<=`, `>=`, `\in`, `\notin`, `\union`, `\intersect`, `\subseteq`, `..`, `<<`, `>>`, `[`, `]`, `\|->`, `!`, `@`, `'`) | accepted | `acc-ascii-symbolic`, `acc-module-minimal` |
| Word ASCII (`\land`, `\lor`, `\lnot`, `\neg`, `\equiv`, `\cup`, `\cap`, `\leq`, `\geq`, `\X`, `\times`, `\div`, `\circ`, `\o`, `\oplus`, `\prec`, `\succ`, `\subset`, `\supset`, `\subseteq`, `\supseteq`, `\notin`, `\sim`, `\approx`, `\bullet`, `\star`, …) | accepted; each spelling normalizes to one operator identity | `acc-ascii-word`, `acc-operators` |
| Unicode glyphs (`∧`, `∨`, `¬`, `⇒`, `⇔`, `∈`, `⊆`, `∪`, `∩`, `≠`, `≤`, `⟨`, `⟩`, `↦`, `‥`, `□`, `◇`, `≡`) | **staged out**: rejected at `lex` with a profile-limit diagnostic naming the spelling | `rej-unicode-spelling` |

The word-ASCII list above is the token table published by the reference parser
used for local probing. Unicode remains a staged limit rather than an
accidental extension: the same reference parser rejects those glyphs, so
accepting them would create a Mirrors-only dialect before any pinned
differential allowlist entry exists.

Pairs of spellings that must produce the same normalized AST are declared as an
equivalence group in the corpus manifest; `acc-ascii-symbolic` and
`acc-ascii-word` are the first such pair (`ascii-alias-pair`). The comparison is
per shared declaration name, ignoring the module name.

### 4.8 Punctuation

Revision 1 recognizes `(`, `)`, `[`, `]`, `{`, `}`, `,`, `:`, `.`, `!`, `@`,
`|`, `->`, `<-`, `|->`, `<<`, `>>`, `..`, `'`, `=` and the `==` definition
symbol. `≜` is **not** part of revision 1: the reference parser treats it as an
unknown character, so a module using it is rejected at `lex` until a pinned
baseline accepts it.

## 5. Syntax profile

### 5.1 Declarations

| Declaration | Revision-1 treatment | Fixture |
| --- | --- | --- |
| `CONSTANT` / `CONSTANTS` | accepted, comma lists may continue on following lines | `acc-constants` |
| `VARIABLE` / `VARIABLES` | accepted, declaration order preserved | `acc-module-minimal`, `acc-generic-transfer` |
| `RECURSIVE` | accepted with explicit arity | `acc-recursive` |
| operator definition (`==`) | accepted for prefix, infix, user-defined symbolic, and higher-order operands | `acc-operators` |
| `LOCAL` declaration | accepted; the wrapped declaration is retained and visible only inside its own module | `acc-local` |
| `INSTANCE` (named and unnamed) | syntax recognized; semantics staged out in revision 1 (§7.4) | `rej-instance-*` |
| `ASSUME` / `ASSUMPTION` | accepted; must be constant level | `acc-assumptions` |
| `AXIOM` | accepted; carried as an assumption-like statement with no proof obligation | `acc-assumptions` |
| `THEOREM` / `LEMMA` / `PROPOSITION` / `COROLLARY` | accepted with an opaque proof body | `acc-theorem-proof` |

### 5.2 Proof bodies

- A proof body (`PROOF` … and `PROOF OMITTED`) is retained with its source span
  and is not elaborated (`syntax.proof.opaque`).
- Proof bodies never contribute model-interface facts, and the parser must still
  find the following top-level declaration reliably.

### 5.3 PlusCal

- A module containing a `--algorithm` or `--fair algorithm` marker inside a
  comment block is treated as a PlusCal module.
- Revision 1 **rejects** such modules at `parse` with a profile-limit diagnostic
  (`rej-pluscal`). Treating the algorithm as an inert comment would silently
  produce a module with no model facts, so the frontend fails closed and requires
  pre-translated TLA+.
- PlusCal translation is not part of the frontend.

### 5.4 Expressions

Revision 1 covers the executable expression surface used by Mirrors and sibling
application models: literals, tuples, records, sets, functions, function sets,
`DOMAIN`, selection by index and field, `EXCEPT` updates with `!` and `@`,
`IF/THEN/ELSE`, `CASE` with `OTHER`, `LET/IN`, `CHOOSE`, bounded `\A` and `\E`
quantifiers, set and set-of comprehensions, priming, `ENABLED`, `UNCHANGED`,
action subscripts `[A]_v` and `<<A>>_v`, action disjunction, `[]`, `<>`, `~>`,
`[]<>`, `<>[]`, and `WF_`/`SF_` fairness. Each construct has an owning accepted
fixture (`acc-values`, `acc-functions`, `acc-control`, `acc-quantifiers`,
`acc-comprehensions`, `acc-actions`, `acc-temporal`, `acc-precedence`).

### 5.5 Precedence and associativity

Verified against the local reference parser and frozen as rules:

- `*` binds tighter than `+`; arithmetic binds tighter than relational
  operators; relational operators bind tighter than `/\`.
- `~` binds tighter than `/\`.
- `/\` and `\/` share one precedence level: mixing them at the same nesting
  level without parentheses is a precedence conflict and must be rejected
  (`rej-precedence-mix`).
- `=>` and `<=>` are non-associative: chaining them without parentheses is a
  precedence conflict (`rej-precedence-chain`). The same applies to chained
  `=`.
- The frontend must not invent an association for a conflict. Parentheses are
  required whenever the profile does not define a unique reading.

### 5.6 Error recovery

- Recovery may resume at declaration and delimiter synchronization points so a
  module can report more than one useful error
  (`rej-multiple-errors`, minimum two diagnostics).
- Any error-severity diagnostic makes the module unusable: a result containing
  an error diagnostic cannot cross the successful elaboration or compilation
  path.

## 6. Module graph profile

### 6.1 Providers

| Provider | Revision-1 contract | Fixture |
| --- | --- | --- |
| Borrowed directory | resolves sibling modules beneath one pinned root, bounded reads, rejects symlinks, special files, path escapes, and identity changes, and rechecks identity before use | `acc-generic-extends` |
| Inline source map | resolves only the caller-supplied closed map of logical names to captured bytes and performs no filesystem access | `acc-inline-equivalent` |
| Standard-module catalog | resolves catalog identities without filesystem access | `acc-standard-modules` |

Logical paths in persisted artifacts are provider-relative
(`<Module>.tla`). Physical paths never enter locks, generated output, public
diagnostics, or corpus expectations.

### 6.2 Graph rules

1. The requested root's declared module name must equal its logical identity
   (`rej-header-mismatch`).
2. Dependencies resolve through the selected provider only.
3. Known standard modules resolve through the catalog; other missing modules
   fail (`rej-extends-missing`).
4. Two sources for one module identity fail (`rej-duplicate-module`).
5. Dependency cycles fail with a bounded complete cycle path
   (`rej-extends-cycle`).
6. A diamond parses and elaborates each shared module once
   (`acc-diamond`).
7. Edges retain owner, dependency, kind, `LOCAL`, substitutions, and source
   order; canonical output is sorted, edges keep declaration order.
8. Resource limits apply before an unbounded graph or diagnostic is allocated.

### 6.3 Standard-module catalog

Revision 1 reuses the production identity list as the catalog's name set:
`Naturals`, `Integers`, `Reals`, `Sequences`, `FiniteSets`, `Bags`, `TLC`,
`TLCExt`, `Toolbox`, `Randomization`, `RealTime`, `Json`, `CSV`, `IOUtils`,
`Option`, `Variants`, and `Apalache`.

The catalog separates three kinds of entry, exactly as the design requires:

- language-defined modules with frontend-owned declaration facts;
- Apalache-profile modules pinned to an Apalache compatibility profile;
- filesystem-supplied modules captured like application sources.

Declaration facts exist only where a reviewed catalog revision provides them.
Revision 1 must provide facts for at least the operators used by the accepted
corpus (`Nat`, `Int`, `Append`, `Cardinality`). A name in the list is **not**
enough to invent an arity: using an operator from a module whose declarations
are still pending is a profile-limit error, and the catalog must grow with
evidence before callers depending on those modules are migrated.

## 7. Elaboration profile

### 7.1 Names and scopes

- Module constants, variables, operators, and `RECURSIVE` declarations resolve
  with stable analysis-local symbol ids that are never persisted.
- `EXTENDS` makes the eligible declarations of the extended module available
  unqualified; visibility is computed from the elaborated graph.
- `LOCAL` declarations stay visible inside their own module while remaining
  representable in provenance (`acc-local`).
- `LET` definitions and quantifier or comprehension binders introduce scopes.
- Duplicate declarations, unknown names, arity mismatches, and ambiguous imports
  are errors carrying primary and related declaration locations
  (`rej-duplicate-declaration`, `rej-unknown-name`, `rej-arity-mismatch`,
  `rej-extends-ambiguity`).

### 7.2 Effective variables

Effective state variables are computed from resolved declarations:

```text
effectiveVariables(M) =
  stableUnique(
    effectiveVariables(each directly extended module in source order)
    ++ variables declared directly by M
  )
```

- `stableUnique` deduplicates the same resolved declaration reached through a
  diamond; two different declarations with one visible name are an ambiguity.
- Each result keeps `visibleName`, `declaredName`, `declaredIn`,
  `declarationRange`, and an import path. Corpus summaries express the import
  path as the module-name chain from the root to the declaring module.
- Variables introduced by `INSTANCE` are never concatenated into the root
  variable list; revision 1 elaborates none of them and reports the staged limit
  instead.
- The motivating fixture is `acc-generic-transfer`: twelve variables inherited
  from `GenericBase` plus seven declared locally resolve to exactly nineteen
  effective variables in declaration order, and the transitive
  `acc-generic-transfer-audit` resolves the same nineteen variables.

### 7.3 Expression levels

Levels are ordered `constant < state < action < temporal`.

- `acc-levels` freezes the classification of one operator per level.
- `ASSUME`, `ASSUMPTION`, and `AXIOM` statements must be constant level;
  a state variable inside an assumption is an error
  (`rej-level-assume`), matching the reference message that assumptions must be
  level 0.
- Level checking runs before a result is handed to the compiler, and it is the
  stage that owns level diagnostics.

### 7.4 `INSTANCE` and substitutions (staged)

Revision 1 recognizes instance syntax but stages instance semantics out. Every
instance fixture is rejected at the `substitution` stage with a specific
profile-limit diagnostic; the frontend must never guess, silently union
variables, or approximate substitution.

| Fixture | Reference tool | Eventual classification owned by TF5 |
| --- | --- | --- |
| `rej-instance-definition-only` | accepted | accepted: definition-only instance reachable through a qualified name |
| `rej-instance-variable-substituted` | accepted | accepted: child variable replaced by a parent symbol |
| `rej-instance-unnamed` | accepted | accepted: unqualified visibility after substitution |
| `rej-instance-implicit-substitution` | accepted | accepted: implicit same-name substitution |
| `rej-instance-unsubstituted` | rejected | rejected: substitution missing for a child variable |
| `rej-instance-invalid-substitution` | rejected | rejected: substitution target is not declared by the child |
| `rej-substitution-constant-by-state` | accepted | accepted: constant substituted by a state expression, shifting the instantiated operator to state level |

Each staged fixture carries `reason: profile_limit`, `revisit: TF5`, and an
`eventual` object in the manifest. TF5 must implement substitution, reclassify
these fixtures, and remove the staged limit in a reviewed profile revision; it
must not edit the fixture files, only the manifest expectations and the profile.

## 8. Resource limits

Limits are part of the profile because fixtures exercise them. Values marked
*frozen* already exist in production scanners; values marked *provisional* are
seed values that must be measured against the conformance corpus and production
models before Phase 2 exit.

| Limit | Value | Status | Exercised by |
| --- | --- | --- | --- |
| `maxSourceBytes` | 4 MiB | frozen | `RejectIdentifierSize`-class inputs; production scanner default |
| `maxIdentifierBytes` | 256 | frozen | `rej-identifier-size` |
| `maxCommentDepth` | 64 | frozen | `rej-comment-depth` |
| `maxDeclarations` | 4096 | frozen | production scanner default |
| `maxModules` | 128 | provisional | graph construction |
| `maxDependencyDepth` | 64 | provisional | graph construction |
| `maxDependencyEdges` | 4096 | provisional | graph construction |
| `maxDiagnostics` | 64 | provisional | recovery and diagnostic rendering |
| `maxNestingDepth` | 256 | provisional | parser termination |

Limit failures are deterministic, bounded, and reported as their own reason
(`limit`), never as malformed input.

Implementation packages may add local defensive bounds that no corpus fixture
exercises (for example a token-count, token-byte, integer-digit, or diagnostic
byte budget). Those bounds are implementation detail, not profile decisions:
they must stay above every corpus-observed input, and promoting one into the
table above requires a reviewed profile revision with an owning fixture.

## 9. Intentional differences from the reference baselines

| Difference | Direction | Reason | Fixture |
| --- | --- | --- | --- |
| Control bytes outside tab/LF/CR are rejected | Mirrors stricter | design requires rejecting unknown control characters | `rej-control-character` |
| Identifier length, comment depth, and byte size are bounded | Mirrors stricter | untrusted compiler input; bounded resources | `rej-identifier-size`, `rej-comment-depth` |
| PlusCal modules are rejected instead of read as comments | Mirrors stricter | translation is out of frontend scope; failing closed avoids empty model facts | `rej-pluscal` |
| Unicode operator glyphs are rejected | both reject | local reference parser has no Unicode tokens; acceptance would need a reviewed allowlist entry | `rej-unicode-spelling` |
| `≜` is rejected | both reject | not accepted by the local reference parser | profile §4.8 |
| Decimal real literals are staged out | Mirrors stricter | integer-only numeric value domain in revision 1 while both baselines accept real literals | `rej-real-literal` |
| Instance semantics are staged out | Mirrors stricter | substitution rules must be implemented before use | `rej-instance-*` |
| Duplicate declarations are errors | Mirrors stricter | reference reports a warning and continues; the design requires an error with related declaration locations | `rej-duplicate-declaration` |
| Ambiguous imported declarations are errors | Mirrors stricter | reference reports a warning and continues; elaboration must not guess which declaration is meant | `rej-extends-ambiguity` |

The corpus records `referenceExpectation` on exactly the fixtures where the
local reference probe accepted a module that revision 1 rejects by design:
`accepted-by-reference-tool` for a clean acceptance and
`accepted-with-warning-by-reference-tool` when the reference completed with
warnings only (duplicate declarations and conflicting imported declarations).
Differential status remains `not_run`: the entries are construction evidence
from an exploratory local probe (tla2tools 2.0 of 2024-08-08, SANY2 2.1
reporting `SANY2 Version 2.1 created 24 February 2014`), not a pinned
differential gate, and TF8 owns turning them into a recorded gate with the
pinned versions.

## 10. Corpus contract

### 10.1 Layout

```text
test/fixtures/tla-frontend/
  manifest.json          fixture index, expectations, branches, differential slots
  accepted/              fixtures the current profile must accept end to end
  rejected/              fixtures the current profile must reject at the named stage
  expected/              structural summaries for accepted fixtures
```

Single-module fixtures are one file. Multi-module fixtures are a directory
bundle with sibling modules; the manifest names the root and the pinned
provider root.

The manifest `status` is `provisional` while the SANY and Apalache pins are
unset: fixture ids, outcomes, stages, reasons, and structural summaries are
frozen for revision 1 at handoff, and only the differential slots and pinned
tool versions remain for the coordinating agent.

### 10.2 Fixture semantics

- `accepted` means lexing, parsing, graph resolution, elaboration, and level
  checking succeed with no error diagnostics, and the structural summary in
  `expected/` is produced.
- `rejected` means every stage before `stage` succeeds and the named stage
  produces at least one error diagnostic; no later stage runs.
- `reason` distinguishes `malformed` (no profile revision should accept it),
  `limit` (resource bound), and `profile_limit` (valid TLA+ deliberately staged
  out of this profile revision).
- A `profile_limit` fixture is valid TLA+ for the reference baselines. When the
  named stage is later than `lex`, lexer and parser suites must still accept its
  tokens and structure; only the named stage rejects the module.
- `minDiagnostics` requires bounded recovery to report at least that many
  diagnostics.
- `revisit` names the task package that must reclassify a staged fixture.
- `referenceExpectation` records the exploratory local-probe outcome where it
  differs from revision 1: `accepted-by-reference-tool` or
  `accepted-with-warning-by-reference-tool`.

### 10.3 Structural summaries

Summaries compare outcomes and structural facts, never unstable prose:

- `modules`, `standardModules`, `dependencies` (owner, module, kind,
  resolution, `local`, substitutions, line);
- `declarations` in source order with kind, names, arity or proof treatment, and
  declaration line;
- `effectiveVariables` in effective order with `declaredIn` and `importPath`;
- `sources` with logical path and normalized SHA-256;
- optional `levels`, `renderings`, and `annotations` for the fixtures that pin
  them.

Rendering strings use normalized ASCII spellings with explicit parentheses.
They are only present where the profile defines a unique reading.

### 10.4 Ownership and change rules

- The corpus is the property of the frontend packages, not of an implementation
  detail: fixtures are referenced by id, never by path, from suites.
- Fixtures are added or reclassified only with a reviewed profile or tool
  version change.
- Implementations must not weaken or edit a fixture to make a gate pass; the
  coordinating agent arbitrates conflicts between an implementation and a
  frozen expectation.
- No fixture may contain private application model material. The generic
  `GenericBase`/`GenericTransfer` bundle exists so the DumpLedgerTransfer
  acceptance case can be exercised without copying the private model.

### 10.5 Handoff validation

At handoff the corpus was validated with a strict JSON parse that rejects
duplicate keys, unique fixture ids, provider-relative paths, file existence,
branch coverage in both directions, summary presence and schema, source
SHA-256 agreement, declaration and dependency line agreement, and a scan for
private model material. The recorded results are with the TF0 handoff report.
An exploratory local SANY pass over all 57 fixtures is recorded in the
manifest `differential.localProbe` section; it is construction evidence, not a
pinned differential gate.

## 11. Branch coverage

Every profile branch below is owned by at least one accepted or rejected
fixture. The table mirrors the manifest branch list; the handoff check verifies
both directions, so a manifest edit that drops a branch or names an undeclared
branch fails validation.

| Branch | Deciding stage | Fixtures |
| --- | --- | --- |
| `lex.annotations.apalache` | lex | `acc-annotations` |
| `lex.comments.line` | lex | `acc-trivia` |
| `lex.comments.malformed` | lex | `rej-open-comment` |
| `lex.comments.nested-block` | lex | `acc-trivia` |
| `lex.identifiers` | lex | `acc-module-minimal` |
| `lex.integers.alternate-spelling` | lex | `acc-numeric-spellings` |
| `lex.integers.decimal` | lex | `acc-module-minimal` |
| `lex.keywords` | lex | `acc-module-minimal`, `acc-constants`, `rej-keyword-identifier` |
| `lex.limits.comment-depth` | lex | `rej-comment-depth` |
| `lex.limits.identifier-size` | lex | `rej-identifier-size` |
| `lex.malformed.control-character` | lex | `rej-control-character` |
| `lex.module.delimiters` | lex | `acc-module-minimal`, `rej-no-terminator` |
| `lex.numbers.real-literal-staged` | lex | `rej-real-literal` |
| `lex.operators.alias-equivalence` | lex | `acc-ascii-symbolic`, `acc-ascii-word` |
| `lex.operators.ascii` | lex | `acc-module-minimal`, `acc-operators`, `acc-ascii-symbolic` |
| `lex.operators.ascii-word` | lex | `acc-ascii-word` |
| `lex.operators.unicode-staged` | lex | `rej-unicode-spelling` |
| `lex.punctuation` | lex | `acc-module-minimal` |
| `lex.strings.escapes` | lex | `acc-values` |
| `lex.strings.malformed` | lex | `rej-unterminated-string`, `rej-newline-in-string` |
| `lex.trivia.lossless` | lex | `acc-trivia` |
| `syntax.decl.assume-axiom` | parse | `acc-assumptions` |
| `syntax.decl.constants` | parse | `acc-constants` |
| `syntax.decl.instance` | parse | `rej-instance-definition-only` |
| `syntax.decl.local` | parse | `acc-local` |
| `syntax.decl.operator` | parse | `acc-module-minimal`, `acc-operators` |
| `syntax.decl.recursive` | parse | `acc-recursive` |
| `syntax.decl.theorem-proof` | parse | `acc-theorem-proof` |
| `syntax.decl.variables` | parse | `acc-module-minimal`, `rej-keyword-identifier` |
| `syntax.expr.action-subscript` | parse | `acc-module-minimal`, `acc-actions` |
| `syntax.expr.comprehensions` | parse | `acc-comprehensions` |
| `syntax.expr.control-flow` | parse | `acc-control` |
| `syntax.expr.enabled-unchanged` | parse | `acc-actions` |
| `syntax.expr.fairness` | parse | `acc-temporal` |
| `syntax.expr.functions-records` | parse | `acc-constants`, `acc-functions` |
| `syntax.expr.literals-collections` | parse | `acc-values` |
| `syntax.expr.priming` | parse | `acc-module-minimal` |
| `syntax.expr.quantifiers` | parse | `acc-quantifiers` |
| `syntax.expr.selection-except` | parse | `acc-functions` |
| `syntax.expr.temporal` | parse | `acc-module-minimal`, `acc-temporal` |
| `syntax.pluscal.staged` | parse | `rej-pluscal` |
| `syntax.precedence.binding` | parse | `acc-precedence` |
| `syntax.precedence.conflict` | parse | `rej-precedence-mix`, `rej-precedence-chain` |
| `syntax.proof.opaque` | parse | `acc-theorem-proof` |
| `syntax.recovery.bounded` | parse | `rej-multiple-errors` |
| `graph.extends.cycle` | moduleGraph | `rej-extends-cycle` |
| `graph.extends.diamond` | moduleGraph | `acc-diamond` |
| `graph.extends.direct` | moduleGraph | `acc-module-minimal`, `acc-generic-extends`, `acc-generic-transfer` |
| `graph.extends.missing` | moduleGraph | `rej-extends-missing` |
| `graph.extends.transitive` | moduleGraph | `acc-generic-transfer-audit` |
| `graph.identity.duplicate-module` | moduleGraph | `rej-duplicate-module` |
| `graph.identity.filename-header` | moduleGraph | `rej-header-mismatch` |
| `graph.lexical-false-positive` | moduleGraph | `acc-trivia` |
| `graph.provider.borrowed-directory` | moduleGraph | `acc-generic-extends` |
| `graph.provider.inline-equivalence` | moduleGraph | `acc-inline-equivalent` |
| `graph.standard-modules` | moduleGraph | `acc-module-minimal`, `acc-standard-modules` |
| `elab.extends.ambiguity` | nameResolution | `rej-extends-ambiguity` |
| `elab.names.arity` | nameResolution | `acc-recursive`, `acc-operators`, `rej-arity-mismatch` |
| `elab.names.duplicate` | nameResolution | `rej-duplicate-declaration` |
| `elab.names.local` | nameResolution | `acc-local` |
| `elab.names.unknown` | nameResolution | `rej-unknown-name` |
| `elab.variables.effective-origins` | nameResolution | `acc-generic-extends`, `acc-generic-transfer`, `acc-generic-transfer-audit`, `acc-diamond` |
| `elab.variables.nineteen` | nameResolution | `acc-generic-transfer`, `acc-generic-transfer-audit` |
| `elab.variables.order` | nameResolution | `acc-module-minimal`, `acc-generic-transfer` |
| `elab.instance.staged` | substitution | `rej-instance-definition-only`, `rej-instance-variable-substituted`, `rej-instance-unnamed`, `rej-instance-implicit-substitution` |
| `elab.substitution.implicit` | substitution | `rej-instance-implicit-substitution` |
| `elab.substitution.invalid` | substitution | `rej-instance-invalid-substitution` |
| `elab.substitution.level-shift` | substitution | `rej-substitution-constant-by-state` |
| `elab.substitution.missing` | substitution | `rej-instance-unsubstituted` |
| `elab.levels.assumption` | level | `acc-assumptions` |
| `elab.levels.classification` | level | `acc-levels` |
| `elab.levels.violation` | level | `rej-level-assume` |

## 12. Disposition of the design's open decisions

| Design open decision | Revision-1 disposition | Owner of the remainder |
| --- | --- | --- |
| 1. Grammar and baseline versions | structure frozen here; exact SANY/Apalache pins pending | coordinating agent |
| 2. Structural proofs or opaque regions | proof bodies retained as opaque regions (§5.2) | TF2 |
| 3. Apalache annotations as facts or trivia | trivia only, no semantic facts (§4.6) | TF6 if facts become necessary |
| 4. Measured default limits | frozen scanner limits plus provisional seeds (§8) | TF1/TF3 with production models |
| 5. Standard-module catalog sourcing | three-kind policy and name set (§6.3); declaration facts grow with evidence | TF4/TF6 |
| 6. Parser generation | implementation-neutral; `Parser` technique stays free while tables stay explicit | TF2 |
| 7. Stable inspection JSON schema | corpus manifest and summary schemas are stable for fixtures; CLI schema is separate | TF8 |
| 8. `INSTANCE` before scanner removal | no: instance semantics stay staged until TF5 lands | TF5 |
| 9. Scaffold proposal v2 contents | deferred; revision 1 keeps today's evidence admission | TF6 |
| 10. Publishable corpus scope | these fixtures are generic; no private model material | coordinating agent |

## 13. Non-goals

This profile does not define TLA+ type inference, model checking, Apalache
execution, dynamic value typing, action-universe closure, StateComputer
contracts, generated target profiles, or formatter behaviour.
