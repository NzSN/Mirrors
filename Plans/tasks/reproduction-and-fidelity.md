# Reproduction and fidelity task package

Date: 2026-09-21

Status: assigned to `general-purpose-gpt`; implementation queued

Roadmap: [failure reproduction and adapter fidelity](../mirror-framework-improvements.md#3-failure-capture-replay-and-minimization)

Coordination: [framework task assignments](../mirror-framework-tasks.md)

## Scope and execution rules

This package turns R1-R5 and F1-F5 into implementation-ready cards. Completing
this document does not implement, validate, install, publish, or deploy any of
the proposed behavior. Every card is assigned to `general-purpose-gpt`; B3 must
give each implementation card one active file owner before work starts.

The initial planning baseline is Mirrors `eb5cd001b990e6ac5e9b1e9b1c5a17ffb85e25fc`,
MirrorECMA `a50710c7eb5e4d42631641a97749f6920e67b607`, and MirrorGate
`173075d318e4be926570a1378fc0aa36a1294f89`. B1 must refresh the full SHAs and
dirty-tree state; historical results remain attached to their recorded revisions.

All changes preserve the existing ownership boundaries:

- MirrorECMA owns capture, replay, reduction orchestration, suite execution, and
  application-facing mutation results.
- Mirrors owns model/interface compilation and any model-valid candidate check.
- MirrorGate owns restricted execution, physical cleanup, trusted receipts, and
  the public disclosure projection.
- E1 owns the shared evidence envelope; C2 owns catalog/component identities.
  R and F records reference those contracts instead of copying their fields.
- Evaluators retain private models, expected states, traces, diagnostic text,
  external-reference resolvers, and disclosure policy. A bundle is inert data:
  loading it never executes embedded code, imports an implementation, fetches a
  dependency, or relaxes Gate policy.

Implementation uses existing `defineSuite`/`runSuite`/`runSuiteWithFactory` and
Gate `evaluateSuite` paths. It must not add a competing comparator or lifecycle.
Each PR states exact owned files, companion SHAs, compatibility impact, executed
checks, and blocked/skipped tiers. Publication, deployment, and destructive host
recovery remain out of scope.

## Source-grounded planning baseline

- MirrorECMA's [suite contract](../../../MirrorECMA/docs/application-suites.md)
  already provides immutable suite definitions, preflighted model/corpus hashes,
  strict matched evidence, zero-based mismatch coordinates, independent cleanup,
  and bounded timeout/cancellation behavior. `SuiteResult` separates mismatch,
  timeout, cancellation, implementation/observer, codec, coverage, and cleanup
  failures; no private reproduction-bundle or reducer API exists at this baseline.
- The [project commands](../../../MirrorECMA/docs/project-tools.md) already select
  pinned compiler/server/package identities. `doctor` is read-only, and replay
  imports the evaluator-approved generated model and implementation only after
  checks. Reproduction must preserve that order and refusal behavior.
- The application program currently declares 17 local behavioral mutants:
  WorkQueue 9, Persistent transfer 4, and Lease service 4. The Gate campaign uses
  the narrower `faults` field: WorkQueue 3 plus the same 4+4, for 11. Current
  orchestration in
  [`suite.mjs`](../../../MirrorECMA/examples/application-validation/suite.mjs)
  asserts exact first mismatches and cleanup, but is example-private rather than
  a reusable campaign contract.
- The same observer is used by correct and faulty application variants. The three
  applications observe persisted queue JSON; payload bytes plus session journal;
  and live ownership, fencing token, controlled clock, and accepted-write count.
  This is useful evidence, but it does not by itself prove observer honesty.
- Gate's [`evaluateSuite`](../../../MirrorGate/integrations/mirrorecma/src/suite.ts)
  already runs the same suite through the retained physical owner. Its trusted
  receipt keeps model and cleanup detail, receipt persistence failure independently
  prevents success, and
  [`projectEvaluationReceipt`](../../../MirrorGate/integrations/mirrorecma/src/receipt.ts)
  exposes only a fixed allowlist. R/F work must not widen that public projection
  by serializing a private bundle or raw exception.
- Existing executable gates include MirrorECMA `pnpm run check`, `pnpm run test`,
  `pnpm run build:application-validation`, and `pnpm run check:installed-suite`;
  Gate integration `npm run check`, `npm test`, and `npm run test:suite`; and the
  three local application commands documented in
  [application validation](../../../MirrorECMA/examples/application-validation/README.md).
  Required real-Gate acceptance remains separate from unit tests.

## Dependency and handoff map

| Card | Starts after | Produces for |
| --- | --- | --- |
| R1 | B1; draft C2 and E1 vocabularies available | B2, R2-R5, F4 |
| R2 | R1, B2, B3; C2/E1 contracts settled | R3, R4, F4, Q1 |
| R3 | R2 | R4, Q1 |
| R4 | R2, R3 | R5, Q1 |
| R5 | R4; one domain and validator selected by B2/B3 | Q1, F5 guidance |
| F1 | B1; draft C2/E1 identities available | B2, F2-F5 |
| F2 | F1, B2, B3 | F3, F4 |
| F3 | F2 | F4, F5 |
| F4 | F2, F3, R2; Gate profile prepared | F5, Q1 |
| F5 | F4, R5 limitation vocabulary | Q1, Q3 |

R1 and F1 can proceed in wave 0 as design/inventory work. R2/F2 wait for B2's
shared-contract reconciliation and B3's non-overlapping file assignments. Final
local and Gate claims use the M2 installed distribution; checkout-based tests may
run earlier but are labelled as such.

## R1 - Specify the private reproduction contract

**Assignment and state:** `general-purpose-gpt`; M3; queued.

**Repository/file responsibility:** MirrorECMA contract documentation and inert
accepted/rejected fixtures, provisionally `docs/reproduction-bundles.md` and
`test/fixtures/reproduction/`. Coordinate schema identity with E1 and C2; do not
edit their schemas.

### Deliverables

1. Define a versioned private-bundle schema and limits for bytes, nesting, nodes,
   trace count, inline captured inputs, diagnostic text, and external references.
   An external reference includes type, immutable digest, and evaluator-owned
   resolver name; it is never an ambient URL fetch.
2. Reference C2 component/catalog identities and E1 run/artifact identities.
   Add reproduction-specific identities for suite, model, ordered corpus,
   generated interface, admitted implementation, execution profile, and failure
   coordinates without treating product version as interface identity.
3. Define normalized signatures for behavioral mismatch, timeout with stage and
   budget, observer/implementation error, codec error, unmet coverage,
   cancellation, and cleanup failure. Primary behavior and cleanup are independent:
   a timeout, invalid model sequence, crash, or cleanup failure never equals the
   original behavioral mismatch.
4. Specify capture consent, redaction, access, retention, deletion, and credential
   exclusion. Define an allowlisted public summary that contains only opaque run
   reference, normalized status, cleanup status, and explicitly approved counts
   or implementation hashes; raw paths, expected/actual states, trace values,
   exception text, and private revisions stay trusted-side.
5. Define identity-validation and compatibility refusal before implementation
   construction or Gate worker acquisition. Unknown schema versions fail closed;
   unknown additive fields follow the settled E1/C2 version policy.

### Acceptance cases and commands

- Accepted fixtures cover inline bounded data and an evaluator-resolved immutable
  external reference for every failure family.
- Rejected fixtures cover over-limit/cyclic/deep data, duplicate or missing
  identities, digest mismatch, unknown reference type, embedded executable field,
  credentials, malformed coordinates, and contradictory primary/cleanup outcomes.
- A private-data canary placed in every sensitive field is absent from the public
  projection. Loading any fixture records zero implementation imports, network
  requests, subprocesses, and Gate acquisitions.
- Planned focused checks from the MirrorECMA root:

  ```bash
  pnpm run check
  pnpm exec jest --runInBand test/reproduction-bundle.test.ts
  ```

**Handoff:** reviewed schema/version, bounds, signature equality rules, public
projection, and accepted/rejected fixtures to R2-R5. B2 records any unresolved
retention or installed-profile choice before R2 begins.

## R2 - Implement capture and exact replay

**Assignment and state:** `general-purpose-gpt`; M3; queued.

**Repository/file responsibility:** MirrorECMA public implementation and tests,
provisionally `src/reproduction-bundle.ts`, `src/project.ts`, `src/cli.ts`,
`src/index.ts`, and focused tests; MirrorGate integration adapter/receipt tests in
`integrations/mirrorecma/` only after an explicit cross-repository handoff. F2 may
not concurrently own the shared suite runner or public barrel.

### Deliverables

1. Add bounded decode/validate/capture APIs around `SuiteResult` and project/suite
   identities. Capture retains the original primary result and cleanup evidence;
   persistence failure is separate and cannot rewrite a mismatch as a pass.
2. Add explicit local replay and Gate replay entry points. Replay selects a pinned,
   evaluator-approved implementation and installed tools supplied by the caller;
   bundle contents cannot select executable code, lifecycle hooks, a resolver, or
   a relaxed runtime profile.
3. Preflight schema, hashes, C2 compatibility, E1 links, model/interface/corpus,
   and external references before factory construction or worker acquisition.
   Missing private dependencies and incompatible identities return structured
   refusal, without falling back to `PATH`, sibling checkouts, or downloads.
4. Integrate project commands without changing existing `replay` exit semantics.
   Any new command/API name is finalized in R1 and documented with its exit/result
   contract. Keep trusted bundle diagnostics out of ordinary public JSON.

### Acceptance cases and commands

- A known deterministic WorkQueue or Counter fault is captured once and replays
  to the same mismatch signature using the supported installed local path and the
  supported Gate path; correct behavior does not reproduce that signature.
- Model, corpus, interface, implementation, tool, catalog, and external-reference
  mismatches each refuse before application/worker creation, verified by spies or
  resource census. An embedded script/dependency locator remains inert.
- Malformed/oversized bundles fail within their bounds. Persistence denial retains
  the behavioral result while failing the requested evidence operation.
- Planned checks:

  ```bash
  # MirrorECMA
  pnpm run check
  pnpm exec jest --runInBand test/reproduction-replay.test.ts test/project.test.ts
  pnpm run check:installed-suite

  # MirrorGate/integrations/mirrorecma
  npm run check
  npm test -- --runTestsByPath test/reproduction-suite.test.ts
  npm run test:suite
  ```

The installed and real-Gate commands are required for the supported profile; an
unavailable backend is reported as incomplete rather than converted to a pass.

**Handoff:** replay API, exact refusal codes, bundle-to-`SuiteResult` mapping, and
local/Gate fixtures to R3/R4 and the F4 campaign adapter.

## R3 - Classify replay stability with bounded repetition

**Assignment and state:** `general-purpose-gpt`; M3; queued.

**Repository/file responsibility:** MirrorECMA reproduction module and tests only;
sequential ownership after R2.

### Deliverables

1. Add a bounded repetition policy with explicit attempt limit, total deadline,
   per-attempt budgets, cancellation, and recorded attempt order. The policy must
   be present in evidence rather than hidden as a runner default.
2. Construct a fresh implementation/reset scope for every attempt and independently
   dispose it. Stop when failed cleanup means trial independence is no longer
   established.
3. Classify `stable` only when the configured attempts reproduce the R1 signature.
   Record `not_reproduced`, `unstable`, `inconclusive`, or `cancelled` with every
   observed normalized outcome; never claim universal determinism.

### Acceptance cases and commands

- Stable deterministic mismatch, alternating outcome, one-off failure, timeout,
  cancellation, and cleanup-loss fixtures produce distinct classifications and
  exact attempt counts.
- A timeout/cleanup failure cannot satisfy a mismatch signature. No later attempt
  starts after independence is lost. Non-resettable cases preserve the original
  bundle and state why stability was not evaluated.
- Planned focused check:

  ```bash
  pnpm exec jest --runInBand test/reproduction-stability.test.ts
  ```

**Handoff:** stability record and independence proof fields to R4 and E1 collectors;
Q1 uses the exact configured attempts, not an undocumented rerun count.

## R4 - Add safe deterministic prefix reduction

**Assignment and state:** `general-purpose-gpt`; M3; queued.

**Repository/file responsibility:** MirrorECMA reducer module/tests and reproduction
documentation; sequential ownership after R3.

### Deliverables

1. Reduce only a fixed selected trace for a case declared deterministic, resettable,
   and stable by R3. The first algorithm considers prefixes only; it does not
   delete interior steps or change inputs.
2. Start each candidate from the declared reset state with a fresh implementation,
   replay scope, and disposer. Give cleanup an independent budget; stop further
   trials if cleanup or reset independence is unconfirmed.
3. Require exact R1 signature equality. Invalid model sequences, timeouts,
   cancellation, infrastructure errors, and cleanup failures are rejected
   candidates, not successful reductions.
4. Enforce candidate/attempt/time limits and caller cancellation. Report every
   candidate and outcome through E1-compatible evidence.
5. Use `shortest reproducing prefix` only when all shorter prefixes needed to
   establish that fact were validly tested within the fixed deterministic trace.
   If limits intervene, report `smallest observed reproducing prefix within the
   attempted set`. Unstable or nondeterministic failures receive no shortest-prefix
   claim, and no result is called a generally minimal trace.

### Acceptance cases and commands

- A deterministic fault reduces to its exact first failing prefix; all shorter
  tested prefixes do not reproduce. A case whose limit expires returns the best
  observed bounded result and an incomplete-minimality flag.
- Fixtures prove fresh reset/disposal per candidate, independent cleanup timeout,
  cancellation, invalid-sequence rejection, signature drift rejection, and a hard
  stop after cleanup uncertainty.
- Planned focused check:

  ```bash
  pnpm exec jest --runInBand test/reproduction-prefix-reducer.test.ts
  ```

**Handoff:** bounded prefix result and trial transcript to R5 and Q1. The original
bundle remains authoritative and is never overwritten by a reduced derivative.

## R5 - Add one model-validated domain reduction profile

**Assignment and state:** `general-purpose-gpt`; M3/M4; queued.

**Repository/file responsibility:** B2/B3 select one domain. Mirrors owns any new
candidate-validation contract under `Core/ModelInterface/`,
`Shell/ModelInterface/`, and its `tools/ModelInterface*Spec.lean` gate; MirrorECMA
owns the reducer adapter/tests. These are separate sequential assignments with an
explicit schema handoff.

### Deliverables

1. Specify one named, versioned domain reducer and its supported input fields and
   transforms. Unsupported types/actions are preserved, not guessed. The profile
   records the validator/compiler identity and domain version.
2. Validate every proposed candidate against the selected model/interface before
   executing the SUT. A reducer cannot use application output as its model-validity
   oracle or bypass ordinary suite preflight/negotiation.
3. Reuse R4 reset, cleanup, signature, total-budget, cancellation, and evidence
   rules. Return a bounded reduction transcript and the original bundle reference.
4. Document that deletion/input search is strategy- and budget-dependent. The
   result is never labelled a global minimum, and unsupported domains retain R4's
   prefix-only result.

### Acceptance cases and commands

- The selected application's known deterministic mismatch survives at least one
  smaller model-valid input candidate. A deliberately model-invalid candidate is
  rejected before application construction; a valid candidate with a different
  failure signature is not accepted.
- Candidate cap, deadline, cancellation, reset failure, and cleanup failure all
  terminate with honest partial evidence. An unsupported second application
  reports `reduction_profile_unsupported` without mutation.
- Planned checks after B3 assigns concrete files:

  ```bash
  # Mirrors
  lake build
  .lake/build/bin/model_interface_spec

  # MirrorECMA
  pnpm run check
  pnpm exec jest --runInBand test/reproduction-domain-reducer.test.ts
  ```

**Handoff:** named supported domain, validator identity, and bounded result semantics
to F5 guidance and Q1. Native-client or general reducer expansion is new scope.

## F1 - Define fixed-baseline mutation campaigns

**Assignment and state:** `general-purpose-gpt`; M3; queued.

**Repository/file responsibility:** MirrorECMA mutation contract documentation,
schema/fixtures, and the three `examples/*/application.json` declarations. Preserve
compiler-owned bundles and generated outputs; regenerate through their owner only
if the reviewed model contract changes.

### Deliverables

1. Define a versioned campaign containing suite/model/interface, ordered corpus,
   acceptance requirements, observer/source closure, correct implementation, each
   mutant, expected detectable behavior, supported execution paths, reset plan,
   independent probes, and C2/E1 identity references.
2. Migrate the known baseline without losing names or expected first mismatch:
   WorkQueue's 9 local mutants, Persistent transfer's 4, and Lease service's 4.
   Resolve the current local/Gate 17-versus-11 difference explicitly: each mutant
   is `required`, `optional`, or `unsupported` per path with a reason; absence from
   the Gate matrix is not silently treated as success.
3. Protect the model, observer, corpus, acceptance requirements, and probe
   definitions by immutable identity. Any drift invalidates the earlier campaign
   result and requires a new campaign revision.
4. Define per-mutant results: `killed_by_behavioral_mismatch`, `survived`,
   `invalid_mutant`, `infrastructure_failure`, or `inconclusive`, with cleanup as
   an independent field. A crash, timeout, unavailable backend, codec/observer
   error, or failed cleanup is not a killed mutant.

### Acceptance cases and commands

- Schema fixtures account for all 17 unique names and reject duplicate mutants,
  unknown expected actions, missing denominator/scope, mutable protected inputs,
  and contradictory expected results.
- Changing one byte of model, observer, corpus, acceptance, or independent probe
  makes baseline validation fail before running the campaign.
- Planned focused check:

  ```bash
  pnpm exec jest --runInBand test/mutation-campaign-definition.test.ts
  ```

**Handoff:** reviewed campaign contract, complete denominator, protected identities,
and per-path support matrix to F2-F4 and B2.

## F2 - Extract bounded mutation orchestration

**Assignment and state:** `general-purpose-gpt`; M3; queued.

**Repository/file responsibility:** MirrorECMA public helper, exports, tests, and
application-validation runner migration, provisionally `src/mutation-campaign.ts`,
`src/index.ts`, and `examples/application-validation/`. Sequential ownership is
required where R2 also touches `src/index.ts`.

### Deliverables

1. Expose a public testing helper that runs the correct baseline first, then each
   declared mutant through ordinary suite execution. MirrorECMA remains Gate-free;
   the helper accepts a bounded evaluator callback so Gate can supply the same
   campaign without framework-private imports.
2. Enforce maximum mutants, sequential-by-default execution, per-run and total
   deadlines, cancellation, fresh reset/factory scope, and independent cleanup.
   Stop interpretation when the correct baseline fails or protected identities
   drift.
3. Produce the F1 taxonomy and per-mutant matrix with exact scenario, signature,
   cleanup, evidence reference, and tested path. Preserve the raw trusted result
   out of public serialization.
4. Migrate existing example orchestration without changing suite comparator,
   fault implementations, first-mismatch expectations, or legacy receipt meaning.

### Acceptance cases and commands

- Unit fixtures cover passing baseline; killed, survived, invalid, infrastructure,
  inconclusive, cancellation, total-budget, and cleanup-failure cases. Crash and
  timeout controls are never counted as kills.
- The current local campaigns still give 9/9, 4/4, and 4/4 genuine mismatches with
  confirmed cleanup, and the report states denominator and path.
- Planned checks:

  ```bash
  pnpm run check
  pnpm exec jest --runInBand test/mutation-campaign.test.ts
  pnpm run build:application-validation
  node examples/application-validation/run.mjs work-queue
  node examples/application-validation/run.mjs persistent-transfer
  node examples/application-validation/run.mjs lease-service
  ```

**Handoff:** public helper and generic evaluator seam to F3 and MirrorGate F4 work.

## F3 - Add observer-fidelity negative controls

**Assignment and state:** `general-purpose-gpt`; M3; queued.

**Repository/file responsibility:** trusted application fixtures and campaign tests
under MirrorECMA `examples/application-validation/`; no universal observer inference
and no Gate policy changes.

### Deliverables

1. Add named negative controls for an observer that fails/returns an invalid value
   and for a fabricated shadow-state observer that can report model-consistent
   values while the actual SUT is faulty.
2. Add trusted application-specific probes outside the observer path: persisted
   queue contents, transfer payload/journal consistency, and lease ownership/token/
   accepted-write facts. Each probe has a fixed identity and bounded cleanup.
3. Record separately what replay detects, what the independent probe detects, and
   what remains outside the claim. A fabricated observer that fools replay is an
   expected demonstration of the boundary, not a framework pass.

### Acceptance cases and commands

- Observer exception is an implementation failure; invalid observation is a codec
  failure; neither is a mutation kill. At least one shadow-state control passes
  reported-state replay while its independent probe fails on real SUT state.
- Correct implementations pass both replay and their probes. Probe failure/error/
  timeout and cleanup uncertainty remain distinct and fail campaign acceptance.
- Planned check:

  ```bash
  pnpm exec jest --runInBand test/mutation-observer-fidelity.test.ts
  pnpm run build:application-validation
  ```

**Handoff:** negative-control fixtures and explicit confidence boundary to F4/F5.

## F4 - Run one matrix locally and through Gate with R bundles

**Assignment and state:** `general-purpose-gpt`; M3; queued.

**Repository/file responsibility:** MirrorGate `integrations/mirrorecma/` campaign
adapter, scripts, tests, and trusted receipts; reuse F2's public callback seam and
existing `evaluateSuite`. MirrorECMA core remains Gate-free.

### Deliverables

1. Adapt the F1 campaign to Gate without copying comparator/result semantics.
   Use the same protected model, observer, corpus, acceptance, mutant definitions,
   and independent probes as local execution.
2. Run the correct baseline before interpreting Gate mutants. Record worker
   admission, implementation/artifact identity, per-mutant result, and confirmed
   physical cleanup. Backend unavailability remains infrastructure failure.
3. Capture an R2 private reproduction bundle for behavioral mismatch results in
   both paths and prove exact replay of at least one known mutant locally and in
   Gate. Store only the E1 allowlisted reference in public campaign output.
4. Reconcile all 17 mutants: execute every path marked required by F1 and retain
   explicit unsupported/optional entries. A single percentage without names,
   denominator, path, and cleanup is prohibited.

### Acceptance cases and commands

- Local and Gate matrices agree on required known-detectable mutants as genuine
  behavioral mismatches with acceptable cleanup. Correct baseline passes first.
- Crash, hang, cancellation, unavailable backend, fabricated observer, independent
  probe failure, and disposal failure retain their categories and never inflate
  killed counts. Public-output canaries contain no bundle/private receipt data.
- Planned checks:

  ```bash
  # MirrorECMA local preparation
  pnpm run build:application-validation

  # MirrorGate/integrations/mirrorecma
  npm run check
  npm test
  npm run test:suite
  node scripts/application-program-gate.mjs work-queue --receipt /absolute/new-private-receipt.json
  ```

Run all three application campaigns with fresh exclusive private receipt paths in
the accepted profile. The one WorkQueue command is illustrative, not full matrix
acceptance. Required sandbox failure leaves F4 incomplete.

**Handoff:** retained local/Gate matrix, private R-bundle references, public
projection checks, and cleanup receipts to F5, E4, and Q1.

## F5 - Publish fidelity guidance and limitation templates

**Assignment and state:** `general-purpose-gpt`; M4; queued.

**Repository/file responsibility:** MirrorECMA application-suite and mutation
guidance plus cross-links from Mirrors application integration docs; no generated
fixture edits and no support-table claim without C2 evidence.

### Deliverables

1. Give application authors a checklist for domain faults, fixed baselines,
   deterministic reset, actual observations, independent probes, cleanup,
   R-bundle capture, and optional domain reduction.
2. Provide a campaign template that requires named denominator, execution paths,
   protected identities, expected detectable behavior, probe limits, unsupported
   cases, and exact retained evidence.
3. Explain claims precisely: killed mutants strengthen confidence in the fixed
   campaign; survivors expose gaps; isolation does not prove observation fidelity;
   finite traces do not prove exhaustive conformance; bounded reduction is not a
   global minimum; local results do not establish Gate/hosted/publication support.
4. Document how a model, observer, corpus, acceptance, probe, runtime profile, or
   catalog change invalidates or versions prior evidence.

### Acceptance cases and commands

- Apply the template to WorkQueue, transfer, and lease evidence from F4; every
  mutant and negative control is accounted for and every claim links to retained
  E1 evidence. A reviewer can distinguish local, Gate, installed, hosted-CI, and
  published states without consulting source code.
- All referenced paths exist, generated sections are unchanged, and Markdown has
  no whitespace errors:

  ```bash
  git diff --check
  rg -n "global minimum|observer honesty|exhaustive conformance|physical cleanup" \
    ../MirrorECMA/docs ../../Docs
  ```

**Handoff:** reviewed guidance and limitation language to Q1 qualification and Q3
readiness reporting. Broader domains, native clients, or platforms require new
cards and their own acceptance evidence.

## Package completion criteria

This planning package is complete when R1-R5 and F1-F5 retain the assignment and
queued status above, B3 maps them to non-overlapping active implementation scopes,
and each dependency handoff names reviewed schema versions, fixtures, and tests.
No task may be marked implemented from this document alone. Runtime acceptance
requires the card's commands against refreshed companion SHAs and retained E1
evidence; environmental or unavailable required tiers remain explicit blockers.
