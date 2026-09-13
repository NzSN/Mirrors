# TLA+ differential validation implementation tasks

> Status: **harness implemented and exercised, 2026-09-13; full differential
> acceptance failed. See §10 for executed evidence and remaining work.**.
> Authority: [differential validation design](../Docs/model-interface-compiler/tla-differential-validation-design.md).
> Parent acceptance gap: [frontend task ledger §17.6](../Docs/model-interface-compiler/tla-frontend-tasks.md#176-tf8-validation-and-remaining-tiers-2026-09-12).

## 1. Scope and sequencing

Implement a reproducible differential gate for the public frontend corpus.
Do not change TLA+ semantics, source fixtures, existing summaries, wire contracts,
or client interfaces opportunistically. Report discovered frontend defects as
separate work; a failing differential gate remains failing until resolved.

Delivery order: DV0 → DV1 → DV2 → DV3 → DV4 → DV5 → DV6. Ownership below
describes file responsibility, not a requirement to launch multiple agents.
The integrator owns shared build/CI wiring, the lock, aggregate documentation,
and final acceptance. Later packages may extend earlier files after handoff.
Each handoff includes actual files changed, commands/results, unresolved
capabilities, and evidence paths; no acceptance is inferred from code presence.

## 2. DV0 — freeze inputs and report contracts

**Owner:** corpus/report implementer.
**Files:** proposed `tools/tla-differential/{schema/,corpus.py,tests/}` and
`test/fixtures/tla-frontend/differential/differences.json`.

- Define observation/report/registry/lock schemas from design §§3–7.
- Validate fixture identities, paths, source maps, stage/reason expectations,
  branch coverage, and exact source hashes without changing the corpus schema.
- Capture all listed sources and distinguish supplied files from reachable closure.
- Define required fact IDs and comparison applicability for each fixture.
- Seed difference candidates as unreviewed; they cannot authorize a pass.

**Acceptance:** current corpus validates as 57 fixtures, 32 accepted/25 rejected,
75 branches, with all files accounted for; invalid paths, duplicate IDs, missing
sources and unknown required facts are refused. JSON round trips preserve closed
schemas; unsupported fact is distinguishable from an observed empty collection.

## 3. DV1 — qualify and pin reference capabilities

**Owner:** reference-tool implementer; integrator owns final lock review.
**Files:** proposed `tools/tla-differential/{toolchain.lock.json,qualification.md,
adapters/sany.*,adapters/apalache.*,bridges/}`.

- Verify candidate artifacts against exact hashes and record Java/library identity.
- Inspect pinned tool help/API/source; document exact frontend-only invocations.
- Determine whether a bridge is necessary and record shared parser lineage.
- Calibrate accepted and independently invalid syntax/name/level cases, plus
  EXTENDS and INSTANCE cases. Include a zero-exit diagnostic failure if supported
  by the tool, otherwise simulate it in adapter tests.
- Publish the full capability matrix and stage mappings with raw evidence.
- Resolve how required SANY variables/origins/dependencies/visibility/arity/
  substitutions/levels are extracted independently of Mirrors expectations.

**Acceptance:** both tools have verified pins and reliable outcome classification;
all required SANY structural facts are demonstrated. Missing facts or tools are
explicit blockers, not waived by reducing the contract. No model exploration or
type-annotation requirement has been introduced into parser acceptance.

## 4. DV2 — capture and bounded execution

**Owner:** runner implementer.
**Files:** proposed `tools/tla-differential/{capture.py,process.py,run.py,tests/}`.

- Materialize one fixture bundle per tool invocation from the captured bytes.
- Preserve negative-case filenames and closed dependency sets; pin module paths.
- Implement timeout/output/artifact bounds, process-group cancellation, cleanup,
  deterministic environment, and pre/post input hashing.
- Record unavailable/crash/timeout/resource/invalid-output separately from rejection.
- Run without automatic acquisition or ambient-library fallback.

**Acceptance:** adapter doubles demonstrate all execution outcomes, child cleanup,
output flooding, input mutation and missing-artifact handling. Ambient sibling
modules cannot satisfy missing dependencies. Same bundles have identical input
digests across engines. No failed invocation produces semantic success.

## 5. DV3 — Mirrors observations and structural normalization

**Owner:** frontend tooling implementer.
**Files:** proposed `tools/tla-differential/{adapters/mirrors.py,normalize.py,
tests/}`, `tools/TlaDifferentialDriver.lean`, and focused driver specification.
**Shared wiring:** integrator only, `lakefile.lean`.

- Consume existing parse/resolve JSON for borrowed cases.
- Drive the one inline case through the actual inline provider in the test driver.
- Normalize independent reference facts into logical semantic identities.
- Preserve qualified-instance provenance, LOCAL visibility, declaration identity,
  stage mapping confidence, and unsupported fields.
- Keep ordering assertions local where external ordering is not qualified.

**Acceptance:** generic transfer yields 12 inherited plus seven local variables;
inline and borrowed equivalent cases agree while recording distinct providers.
Named/chained/substituted instances and ambiguous/LOCAL declarations cannot
collapse to identical keys. Expected summaries cannot influence external adapter
outputs. Operational CLI and inspection v1 remain byte-compatible.

## 6. DV4 — comparison and reviewed differences

**Owner:** comparator implementer.
**Files:** proposed `tools/tla-differential/{compare.py,report.py,tests/}`;
extend registry/schema files only after DV0 handoff.

- Compare Mirrors against manifest outcomes, stages and existing summaries.
- Compare each reference outcome and every required/qualified structural fact.
- Aggregate pass/fail/incomplete with unchanged fixture and branch denominators.
- Enforce exact, source/tool/profile-bound difference entries with review evidence.
- Emit canonical comparison JSON, human summary, and bounded raw evidence links.

**Acceptance:** injected inverted outcome, wrong origin/arity/level, dropped edge,
missing fixture, missing required fact, unknown phase, stale/unused difference,
crash and malformed JSON all receive the designed verdict. Known mismatch plus
unavailable tool remains fail with both facts visible. Intentional limits become
reviewed differences only after real reference observations and review.

## 7. DV5 — local and CI integration

**Owner:** integrator.
**Files:** proposed tool README and acquisition helper, appropriate `.github/
workflows/` job, `lakefile.lean`, ignore rules, and documentation links.

- Publish one external command: `python3 tools/tla-differential/run.py --required`.
  This is a proposed interface, not an available command at design time.
- Wire offline harness tests into local gates; keep external acquisition and runs
  in explicit setup and a required differential CI job.
- Archive reports/logs even on failure; enforce required exit status and coverage.
- Scope job triggers to every semantic/tooling/corpus/pin input described in design.

**Acceptance:** offline tests pass without Java/reference tools; required mode
with missing artifacts returns incomplete/nonzero. A simulated mismatch fails
CI and retains evidence. Existing `lake build`, `lake test`, and inspection CLI
goldens remain green; report any environment-blocked gate exactly.

## 8. DV6 — execute, review and record acceptance

**Owner:** integrator/reviewer.
**Files:** dedicated `test/fixtures/tla-frontend/differential/evidence/` checkpoint,
frontend task ledger, language profile, corpus differential metadata, and this plan.

- Run the full captured corpus against Mirrors and both pinned tools.
- Review every discrepancy: frontend defect, reference behavior, intentional
  profile difference, adapter defect, or unresolved finding. Do not auto-bless.
- Run required structural comparisons and repeat the run to verify deterministic
  semantic output. Preserve raw artifacts and their retrieval references.
- Record exact scope/counts/pins/commit and all unsupported comparison surfaces.
- Replace `not_run` with the observed scoped pass/fail/incomplete status and
  evidence link. Claim passing acceptance only after a successful required run;
  preserve failed/incomplete findings.

**Acceptance:** all manifest fixtures have three valid observations; all required
comparisons pass or match narrowly reviewed differences; no unknown required
facts, execution failures, or unreviewed mismatches remain. The accepted evidence
is durable and reproducible. Lexical/CST and any other unimplemented external
surfaces remain explicitly uncertified. This does not mark the whole frontend
task group complete or claim the separate application/MirrorGate gates passed.

## 9. Implementation checklist

- [x] DV0: input, schema and capability contracts implemented and validated.
- [x] DV1: artifacts pinned; corpus-relevant atomic reference projections calibrated.
- [x] DV2: bounded capture/execution and adversarial cleanup verified.
- [ ] DV3: provider-correct driver implemented; full named-instance operator/level
  observation acceptance remains open because the frontend projection omits
  qualified operators. Rich substitution expression identity remains uncertified.
- [x] DV4: comparator, narrowly reviewed differences, evidence identities, and
  negative controls implemented and exercised.
- [x] DV5: offline Lake gate and dedicated external CI workflow integrated.
  Hosted CI was not executed in this local session.
- [ ] DV6: complete positive acceptance remains open. Full-corpus execution and
  discrepancy review are complete; remaining failures require separate
  frontend/profile/projection work.

## 10. Executed evidence and acceptance boundary

The implementation was carried out with the test-automator, tooling-engineer,
docs-researcher/build-engineer, and QA/reviewer instructions. This running session
could not register newly copied role names, so workers followed those files in
explicitly scoped default-agent threads; later related responsibilities reused
those threads. No production frontend semantics or frozen source fixtures were
changed to obtain agreement.

The corpus remains 57 fixtures (32 expected accepted, 25 rejected), with 75
branches and 103 fixture-branch links. The harness captures each source bundle
and invokes Mirrors, standalone SANY, and Apalache, retaining all 171 observations.
It checks implementation/binary stability and preserves the source/harness
snapshot. Two same-input runs produce identical semantic payloads; see the
[evidence index](../test/fixtures/tla-frontend/differential/evidence/README.md)
for current checksums, exact commands, and raw archive verification.

Checkpoint A established 27 differences. The reviewer and integrator approved
14 outcome comparisons covering exactly seven documented revision-1 policies
on the two reference engines. Each entry is pinned to exact source hashes,
profile, tools, review artifact, and checkpoint evidence. The remaining
comparisons concern mixed-junction precedence, Unicode baseline rationale,
ENABLED levels, and missing named-instance qualified operator projections.
See [triage](../test/fixtures/tla-frontend/differential/evidence/triage.md).

Validation includes offline normal/error/mutation tests, opt-in live reference
calibration (including chained and LOCAL instances), the native Lean build,
parser corpus, and the aggregate Lake suite with pinned live Apalache and
loopback access. The required runner was also executed with Java deliberately
absent from PATH and returned `incomplete` / exit 2, with all observation rows
retained. The discovered source-addition and malformed-arity harness defects
were fixed and their exact regressions added before the final evidence reruns.

The initial comparisons do not certify full lexical/CST equivalence, external
native-to-Mirrors stage mapping, Apalache structural normalization, or complete
substitution-expression/declaration identity. These remain explicit unsupported
surfaces. SANY and Apalache share parser lineage, so agreement is correlated.
This work does not complete the separate MirrorGate or real application harness
acceptance tiers from the parent ledger.
