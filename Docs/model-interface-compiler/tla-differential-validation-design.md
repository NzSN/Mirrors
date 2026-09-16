# TLA+ frontend differential validation

> Status: **profile-4 differential acceptance passed on 2026-09-15. The initial
> 2026-09-13 failure was superseded by the compatibility/catalog repairs.
> Unsupported comparisons remain uncertified. See the
> [current acceptance record](tla-frontend-tasks.md#1811-profile-4-standard-catalog-closure-2026-09-15).**
> Authority: [frontend compatibility contract](tla-frontend-design.md#5-compatibility-authority)
> and [language profile](tla-language-profile.md).
> Delivery: [differential validation tasks](../../Drafts/tla-differential-validation-tasks.md).

## 1. Objective and current evidence

Run the same public source bundles through Mirrors, pinned SANY, and pinned
Apalache. Preserve observations, compare supported facts, and make every
disagreement or unavailable comparison explicit. External tools are compatibility
oracles, not production dependencies and not infallible authorities.

The profile-4 acceptance manifest contains 61 fixtures: 34 accepted and 27
rejected, covering 76 branches and 107 fixture-branch links. Required runs T/U
each completed 183 observations, with 564 exact matches, 14 reviewed differences,
292 explicitly unsupported comparisons, and no unresolved/incomplete findings.
Runners derive counts from their captured manifest rather than hard-code them.
The [evidence index](../../test/fixtures/tla-frontend/differential/evidence/README.md)
retains the historical failed runs and subsequent repairs. The earlier
exploratory reference probe remains historical construction evidence.

The initial delivery targets corpus outcome and required structural comparisons;
the implemented harness exposes remaining observation and compatibility gaps.
It also publishes a capability matrix for all five compatibility levels in the
parent design. Unsupported lexical/CST/expression comparisons remain explicit
follow-up coverage, not evidence of complete TLA+ conformance. DumpLedgerTransfer
application harness acceptance, MirrorGate certification, and state exploration
remain separate gates.

## 2. Architecture and ownership

Use an offline Python orchestration package under `tools/tla-differential/` with
one entry point and adapters for Mirrors, SANY, and Apalache. It owns fixture
capture, bounded subprocess execution, normalization, comparison, and reporting.
Each adapter exposes `probe`, `observe`, and `capabilities`; callers do not parse
tool-specific diagnostics or know invocation details.

Use `tla_frontend parse/resolve --format json` for borrowed Mirrors fixtures.
Add a test-only Lean driver for inline fixtures through `SourceProvider.inline`
and the same frontend API. Do not silently turn the inline case into a borrowed
Mirrors invocation. The driver can expose additional pure frontend observations
needed for comparison, but must not implement a second parser or elaborator.
Any new output is a separate development schema; the closed inspection v1
schema and operational mirror commands remain unchanged.

Reference adapters derive facts from reference output or a small bridge to the
pinned tool's semantic API. They must never load Mirrors' expected summaries to
manufacture reference observations. The comparator alone reads expectations.
Reference bridges belong in this tooling directory, outside the proof boundary.
No production protocol, model-interface lock, generated binding, or client API
changes are part of this delivery.

## 3. Tool pins and capability qualification

Create a dedicated `toolchain.lock.json` containing exact distribution versions,
artifact URLs and SHA-256 hashes, Java runtime identity, bridge source/build
identity, and bundled standard-library identities. Record the relationship
between SANY and Apalache's bundled parser: agreement between tools sharing
parser code is correlated evidence, not two independent parser implementations.

`tools/ci/versions.env` currently pins Apalache `0.61.0` and its artifact hash.
Use that as the first candidate, verifying the actual artifact and invocation
before locking it. Select and verify the SANY artifact during DV1; the historical
probe's version string alone is insufficient. No new exact pin is invented here.
An existing executable's version banner is not a substitute for artifact hashes.
Acquisition is an explicit setup operation, never an implicit download in a test.

DV1 must inspect each selected tool's own help/API/source and qualify the exact
commands against tiny accepted, syntax-invalid, unknown-name, level-invalid,
EXTENDS, and substituted-INSTANCE bundles. Do not assume an exit code alone
means semantic acceptance. Do not invoke model checking or require Init/Next,
type annotations, or invariants just to test frontend acceptance. If an Apalache
command includes later typechecking/transformation phases, preserve their results
separately from parsing and semantic loading. Publish exactly which phase ran.

The capability matrix records each fact as `supported`, `unsupported`, or
`unqualified`, with extraction method and calibration evidence. Required outcome
observations from both tools and required SANY structural facts must be qualified
before a complete initial-tier result is possible. If an API cannot expose them,
DV1 reports that blocker; later tasks cannot silently weaken acceptance.

## 4. Identical input and isolated execution

Capture the manifest, profile, expected summaries, difference registry, and all
listed source files once. Validate unique IDs, relative paths, sourceRoot and
inline mappings, missing files, and path escape before invoking tools. Copy only
each fixture's listed files into its isolated directory, preserving file names
and logical identities, including intentionally malformed filename/header pairs.
Never repair a negative fixture or copy unrelated siblings from `rejected/`.

Decode and normalize sources with the profile's UTF-8/line-ending rules. Hash
the normalized bytes actually staged. Mirrors' successful source manifest must
agree with the reachable staged closure; unused listed files need not appear in
that closure. Reference inputs use those same normalized bytes. For the inline
case only the external adapters receive a materialized equivalent source map;
the report distinguishes provider equivalence from filesystem equivalence.

Restrict each tool's module search path to that fixture and its pinned standard
library. Do not inherit ambient TLA library paths or a user's working directory.
Record standard modules separately from local source units, including library
hashes and shadowing policy. Qualification must detect ambient-module leakage.
Check staged hashes after execution; changed inputs invalidate the observation.

Initial runner defaults: one fixture per process, at most two concurrent tool
processes, 60-second timeout per invocation, 1 GiB JVM heap where applicable,
8 MiB captured output per stream, and 64 MiB retained artifacts per invocation.
The implementation must enforce bounds, terminate the process group, and clean
temporary directories on success, error, timeout, and interruption. Overrides
are explicit and recorded; startup calibration may motivate reviewed changes.
Limit exhaustion is an execution failure, never a language rejection. Network
access is unnecessary during execution.

## 5. Observation and comparison contract

Version observations as `mirrors.tla-differential-observation/v1`. Each carries
fixture ID, engine identity, input digest, invocation, adapter version, and:

- execution status: `completed`, `unavailable`, `timeout`, `crash`,
  `invalid_output`, or `resource_exhausted`;
- language outcome: `accepted`, `rejected`, or `unknown`;
- native phase and optional normalized stage, with mapping evidence;
- diagnostics, available structural facts, and per-fact capability status;
- paths and hashes for bounded raw stdout/stderr and tool artifacts.

Only a qualified successful execution may have a known language outcome.
Unknown phase mappings remain unknown. Mirrors must match its precise manifest
stage/reason; external stages are compared only where the qualified mapping
supports it. Do not force SANY or Apalache onto Mirrors' internal pipeline.
Do not compare diagnostic wording. Keep native phase and exit status even when
a normalized interpretation exists.

Compare each oracle against Mirrors separately, then report oracle-to-oracle
disagreement. Two rejecting tools do not excuse disagreement with one tool;
two agreeing tools do not automatically prove Mirrors defective. Every
unexplained mismatch blocks acceptance and is triaged with the raw evidence.

| Surface | Initial required comparison | Boundary |
| --- | --- | --- |
| Outcomes | Every fixture on all three engines | Reviewed differences may explain outcomes; execution errors may not |
| Stages | Exact Mirrors stage/reason; qualified reference stage mapping | Unknown mappings are explicit coverage gaps |
| Variables | Effective names and declaration origins on mutually accepted fixtures, Mirrors versus SANY | Ordering is a Mirrors golden requirement unless reference ordering semantics are qualified |
| Resolution | Local dependency identities, EXTENDS/INSTANCE kind, visible operator names and arities, LOCAL visibility | Compare facts before lossy transformation; identify unsupported reference fields |
| Substitution and levels | Corpus-exercised named/unnamed/chained substitutions, surviving root variables, operator levels | SANY extraction and fixtures must establish semantic identity; no guessed provenance |
| Apalache structure | Every qualified fact exposed by its frontend output | An unavailable fact is not equality and not a passed check |
| Lexical/syntactic detail | Outcome comparison plus existing Mirrors lossless/shape tests | Token spans, trivia, full CST and expression shape are not externally certified by this initial tier |
| Execution handoff | Staged source hashes, root identity, observed source closure where exposed | This does not execute the model; existing capture integration remains necessary |

Required SANY structural facts are the variables, resolution, substitution, and
level rows above for applicable mutually accepted fixtures. A missing required
fact makes the initial structural tier incomplete. Explicitly report nonapplicable
facts for rejected inputs; never compare a recovered partial semantic graph as
a successful result. Retain all remaining parent-design coverage gaps separately.

Normalize declaration identities to logical module/name and qualified instance
path, with substitution relationships where exposed. Sort set-like collections;
preserve semantic order where required. Preserve raw spellings/locations in
observations even when alias canonicalization or span normalization is used for
comparison. Validate canonicalization using distinct declarations, diamonds,
LOCAL re-exports, and named instances so it cannot hide an ambiguity.

## 6. Reviewed differences

Create `differences.json`, a separate versioned registry. Each entry identifies
fixture IDs, engine/artifact pins, profile and source digests, comparison fields,
exact expected outcomes/facts, rationale, owning profile section, evidence, and
review provenance (review artifact or commit). Include a revisit condition.
No wildcard fixture exclusions, generic ignore flag, or outcome-only blanket
allowlist is permitted. An unused, obsolete, or overbroad entry fails validation.

Seed candidates from the manifest's resource/profile limits and historical
reference expectations, but require fresh observations and review before marking
them accepted. A `malformed` fixture can also expose a policy difference; for
example the profile explicitly discusses stricter control-character handling.
Do not equate the manifest's reason label with universal external rejection.
Never update expectations automatically from observed results. A change to
language acceptance follows the profile's revision rules in a separate change.

## 7. Reports and aggregate status

Emit closed-schema `report.json` and a concise `summary.md`. Include repository
commit and dirty-tree/diff digest, corpus/profile/summary/registry hashes, tool
and standard-library identities, limits, commands, timestamps, per-fixture
observations, comparisons, reviewed differences, and coverage by branch/engine/
fact. Include even fixtures that could not execute. Do not reduce the denominator
to successful invocations. Reports refer to raw artifacts by relative paths and
hashes; portable summaries contain logical paths rather than host paths. Private
raw tool paths may remain in local logs and must be sanitized for publication.

Aggregate verdicts are `pass`, `fail`, and `incomplete`. Known mismatches yield
`fail` even if other work is unavailable; otherwise any missing required run or
fact yields `incomplete`. Pass requires all required comparisons satisfied,
including explicitly reviewed differences. Report exact matches and reviewed
differences as separate totals. Overall exit codes: 0 pass, 1 fail, 2 incomplete,
3 invalid invocation/configuration. An optional developer mode may collect
partial evidence, but it cannot convert incomplete to pass.

The semantic comparison payload must reproduce byte-for-byte on a second run
with identical inputs and pins; timestamps, elapsed times, and raw log order are
outside that deterministic payload. No result cache is needed in the first
delivery. Later caches must include every input/tool/adapter/limit identity.

Local outputs go to an ignored build/scratch directory. CI archives complete
bounded evidence. The accepted checkpoint records a durable report and summary
under a dedicated evidence directory, with retrievable raw artifact references.
After execution, the ledger/profile/manifest replace `not_run` with the observed
scoped status (`pass`, `fail`, or `incomplete`) linked to evidence. Only a
successful required run authorizes a passing acceptance claim.

## 8. Delivery gates and limits of the claim

Keep offline orchestration/normalization tests in the default local validation
path; external tools belong to an explicit required differential command and
dedicated CI job. Missing pins/artifacts fail that required job as incomplete.
Pin acquisition occurs in CI setup. CI triggers include frontend, fixture,
profile, adapter, standard-library, and lock changes. Tool upgrades require
reviewed lock changes and a full rerun; no silent baseline fallback is allowed.

Before accepting the runner, demonstrate that it detects a changed variable
origin, dropped dependency, wrong level/arity, inverted acceptance, missing
fixture row, stale difference entry, crashed tool, and malformed successful
output. Use adapter test doubles and temporary report mutations; preserve the
real corpus and production code. Then execute every fixture on both references
and Mirrors, run required structural comparisons, and reproduce the normalized
report. Existing `lake build` and `lake test` must remain green after integration.

The resulting claim is agreement on the captured corpus, pins, profile, and
listed comparison surfaces, with enumerated differences and omissions. It is
not complete TLA+ conformance, proof checking, typechecking conformance, model
execution equivalence, or completion of the other TF8 ecosystem gates.


## 9. Implementation status (2026-09-13)

This section preserves the initial delivery snapshot; the current acceptance
status is above and in frontend tasks sections 18.8–18.11.

The runner, isolated capture, bounded process layer, provider-correct development
observations, standalone SANY bridge, Apalache parse adapter, closed schemas,
comparator, reviewed registry, portable evidence export, offline tests, and CI
workflow are implemented. Source and executable hashes are recorded before
execution and verified afterward. Raw evidence can be restored from the indexed
archives; captured input/harness snapshots accompany the reports.

Actual corpus outcomes and qualified projections expose unresolved compatibility
findings; implementation does not imply a passing conformance gate. Named-instance
operator facts are missing from Mirrors' existing public elaboration projection.
The bridge's substitution comparison covers atomic actual values/spellings and
instance sites; richer resolved expression identity remains uncertified.

See the [execution/task record](../../Drafts/tla-differential-validation-tasks.md#10-executed-evidence-and-acceptance-boundary)
and [evidence index](../../test/fixtures/tla-frontend/differential/evidence/README.md).
