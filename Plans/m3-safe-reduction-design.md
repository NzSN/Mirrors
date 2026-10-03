# M3 safe reduction: reducer design

Date: 2026-09-28. Status updated 2026-10-03.

Status: prefix and domain reduction are qualified for the selected
`m5-wsl-windows-remote/v1` profile on post-M6 working-tree C0
`879be4fd92d3c2e1abbb19b0737c620dcf7cea466f6796a4703b75aa5a533c25`.
The [current readiness record](q3-post-m6-2026-10-03.md) binds the
installed reductions, reproduction linkage and independent Q2 verification.
It does not qualify later commits or documentation changes. Broader M4
aggregate/process recovery and native Ubuntu acceptance remain unqualified.

Historical implementation and prefix acceptance: published in Mirrors `b19e090`
and MirrorECMA `da18f1a`, with follow-up fixes through MirrorECMA `4992b07` and
Mirrors `e8ba489`. The prefix
tier `qualification.reduction-prefix` qualified 2026-09-30 under selection
`fed55175b792feaec86cf71bf7fae1bae680a0313797a5c982f3a6ecc746f025`
(`framework.reduction-prefix` run-dcc51362-9084-4c2d-9eeb-9329bacb8d01,
`shortest_reproducing_prefix`, `minimalityComplete: true`; diagnostic WSL2
profile). At that September 30 checkpoint, the domain tier
`qualification.reduction-domain` still awaited remote service activation;
the later Windows oracle decision and qualification supersede that blocker.

Deferrals (operator decision 2026-09-29): every tier that requires a native
Ubuntu host is deferred — no native Ubuntu machine is available. For this
design that means the local oracle mode never qualifies here; the remote
explore-session oracle (section 5) is the only reduction qualification path.
The local mode remains implemented for hosts that permit it.

This document re-stages, in tracked form, the work-package spec previously held
at `/tmp/m3-reduction-plan.md` (lost with the 2026-09-27 `/tmp` cleanup) and
records the design against current source.

Roadmap: [failure capture, replay, and minimization](mirror-framework-improvements.md#3-failure-capture-replay-and-minimization).
Task cards: [R4/R5](tasks/reproduction-and-fidelity.md#r4---add-safe-deterministic-prefix-reduction).
Existing contracts: [model-interface reduction](../Docs/model-interface-reduction.md),
[MirrorECMA reproduction bundles](../../MirrorECMA/docs/reproduction-bundles.md),
[reproduction adapter handoff](../tmp/m5-reproduction-adapter.md).
Position record: [CHECKPOINTS.md](../CHECKPOINTS.md) (dated execution history).
Implementation plan: [m3-safe-reduction-implementation-plan.md](m3-safe-reduction-implementation-plan.md)
(sequencing, owners, validation commands, re-freeze rules).

## 1. Purpose and scope

The original scope was to close M3's **safe reduction** requirement and unblock
the reduction half of M5 demonstration 4. That scope is now qualified for the
exact named-profile candidate above.

In scope:

- R4: deterministic prefix reduction over a recorded reproduction trace.
- R5: one model-validated domain profile (`lease-service-input-shrink/v1`) with
  a model oracle.
- A **remote explore-session oracle** against the deployed model-check service,
  resolving the original local-Apalache execution blocker.

Out of scope (unchanged from the parent plan): a general trace solver, new wire
protocols, additional domain profiles, native-client reduction, publication,
deployment.

## 2. Current state, separated by evidence tier

| Component | Location | Tier |
| --- | --- | --- |
| Prefix reducer (R4) | MirrorECMA `src/reproduction-prefix-reducer.ts` (`reduceReproductionPrefix`, schema `mirrorecma.reproduction-prefix-reduction/v1`) | source-implemented; focused test `test/reproduction-prefix-reducer.test.ts` |
| Stability classification (R3) | MirrorECMA `src/reproduction-stability.ts` + test | source-implemented |
| Domain profile (R5) | MirrorECMA `src/lease-reduction.ts` (`lease-service-input-shrink/v1`, domain `LeaseService.Next/v1`) | source-implemented; `test/reproduction-domain-reducer.test.ts` |
| Candidate validator | Mirrors `Core/ModelInterface/Reduction.lean` + `Codec/ModelInterfaceReductionJson.lean`, gate `model_interface_spec` | source-implemented |
| Installed oracle driver | MirrorECMA `scripts/materialize-lease-reduction.mjs` (tool manifest `mirrorecma.lease-reduction-tools/v1` local, `/v2` remote), shipped in the installed `mirrorecma` package | source-implemented; remote mode implemented (MirrorECMA `da18f1a`) |
| Installed prefix driver | MirrorECMA `scripts/reduce-reproduction-prefix.mjs`, shipped in the installed `mirrorecma` package (packaging fix Mirrors `e8ba489`) | qualified for the recorded C0 (`run-338af102-707b-4d52-8370-5b4e0aaf15f3`); shortest prefix 2/16 with complete minimality |
| Evidence commands | Mirrors `tools/evidence/commands.json`: `framework.reduction-prefix`, tier `qualification.reduction-prefix` (required), adapter `mirrorecma.reproduction-prefix-reduction/v1`; `framework.reduction`, tier `qualification.reduction-domain` (required), adapter `mirrorecma.lease-reduction-oracle/v2` | both registered and qualified for the recorded C0; domain run `run-f9a88eae-87be-4cdb-9d2c-9e57b9b70d89` |
| Development-oracle evidence | recorded in `Docs/model-interface-reduction.md` (cached Apalache 0.61.0 + JDK 25.0.4+7, 2026-09-22) | development-tier only; not installed-distribution qualification |
| Remote oracle mode | MirrorECMA `src/lease-reduction.ts` (`openReductionOracleTransport`) and the materializer's `--oracle-mode remote` | qualified against the recorded Windows Apalache 0.62.2 / Java 25.0.4+7-LTS oracle; same reduced-corpus mismatch and confirmed cleanup, with no global-minimum claim |

`reduceReproductionPrefix` and the lease profile are exported from MirrorECMA's
public API (`src/index.ts`). Both reduction tiers are credited for the frozen C0
above, including actual reduced-corpus baseline/fault replay and exact R0/R1/R5
linkage. Receipts emit integer-millisecond durations and the prefix probe
normalizes a truncated `coverage_unmet` prefix to "no signature"
(MirrorECMA `b753695`, `4992b07`).

## 3. Architecture

Pipeline, each stage gated by the previous:

1. **Eligibility (R3 output).** Reduction starts only from a case classified
   deterministic, resettable, and stable, carrying its reproduction bundle. The
   bundle stays authoritative and is never mutated; reductions are derivatives
   that cite `originalBundleSha256`.
2. **Prefix reduction (R4).** `reduceReproductionPrefix` searches prefixes of
   the selected trace only — no interior deletion, no input changes. The caller
   injects `validateCandidate` and `evaluateCandidate`; each evaluation runs
   against a fresh reset SUT with its own disposer and an independent cleanup
   budget.
3. **Domain reduction (R5).** For the lease profile only:
   `validateLeaseReductionCandidate` (strict shape) → Mirrors validator
   `mirrors.model-interface-reduction/v1` (contract check) →
   `materializeLeaseReductionTrace` → **model oracle** (explore session
   re-derives the candidate from `Init`/`Next` and confirms `TraceComplete`) →
   only then a fresh SUT execution with exact signature equality.
4. **Evidence.** Every trial and the final receipt flow through the E1 envelope
   as `mirrorecma.lease-reduction-oracle/v1` (R5) or the prefix-reduction
   schema (R4), attached under the registered command.

Ownership (unchanged): MirrorECMA owns reducer modules, the materializer, and
application-facing results. Mirrors owns the candidate-validation contract and
the evidence registry. Gate owns restricted execution and the public
projection; reduction receipts stay private-side. The evaluator owns private
models, expected states, and the service identity record (section 5).

## 4. Safety contract

Six invariants define "safe". They are stated as introduction discipline: a
reduction claim that violates any invariant is not a weaker claim, it is no
claim at all.

- **S1 — reproduction gate.** A candidate counts only on exact equality with
  the bundle's declared signature (definitional, not approximate). Timeout,
  invalid model sequence, cancellation, infrastructure error, and cleanup
  failure inhabit their own outcome types and have no path into `reproduced`.
- **S2 — trial independence.** Every trial starts from the declared reset
  state with a fresh implementation, replay scope, and disposer; no state is
  shared across trials. Unconfirmed cleanup or reset revokes the premise for
  further trials (`stopReason: cleanup_independence_lost`).
- **S3 — bounded search.** `candidateLimit` (1..4096), `totalBudgetMs`,
  `perCandidateBudgetMs`, `cleanupBudgetMs`, and caller cancellation are
  enforced structurally; every candidate and outcome is reported.
- **S4 — honest claim typing.** `shortest_reproducing_prefix` requires the
  universal side condition that every shorter prefix was validly tested
  (`minimalityComplete: true`). Otherwise the result is
  `smallest_observed_reproducing_prefix` over the attempted set, or
  `not_reduced`. No result is ever a global minimum; strategy and budget
  dependence is recorded, not hidden.
- **S5 — provenance.** The original bundle is immutable; every result carries
  `originalBundleSha256` and the trial transcript.
- **S6 — model-validity before execution (R5).** A candidate must validate
  against the model/interface contract before any SUT construction.
  Application output is never the validity oracle; unsupported domains return
  `reduction_profile_unsupported` without mutation.

## 5. Remote explore-session oracle mode

### 5.1 Historical local-only execution blocker

This subsection records the pre-implementation blocker. The endpoint and
versions below are historical; the October 1 [Windows oracle decision](execution-decisions.md#2026-10-01--current-windows-host-is-the-designated-remote-oracle)
and current readiness record supersede them.

The local-only `materialize-lease-reduction.mjs` set `process.env.APALACHE_MC`
to a local launcher, prepended a local JDK to `PATH`, byte-pinned local
mirror/validator/Apalache/JDK tools, and opened the oracle with
`spawnMirror(local mirror)`. Local model checking was prohibited on this
coordinator; the then-designated service at `192.168.150.219:8999` reported
Apalache 0.58.2 / Java 21.0.11 instead of the selected 0.61.0 / 25.0.4+7-LTS.
A local-pin rerun was therefore both prohibited and identity-incompatible.

### 5.2 Original design: transport-selected oracle

The mechanism below is implemented. Original version pins and schema options
record the design baseline; current remote acceptance uses the v2 receipt and
the oracle identity in the current readiness record.

The explore session is already transport-agnostic:
`startExploreSession(target: string | Transport, …)` and the transport layer
provides `spawnMirror`, `connectMirror(host, port)`, and `connectTlsMirror(…)`
with peer-leaf SHA-256 pinning. The remote mode is therefore an orchestration
change in the materializer, not a protocol change:

1. Add `--oracle-mode local|remote` (default unchanged: `local`).
2. In `remote` mode, open the oracle with `connectTlsMirror` to the configured
   service endpoint; **do not** set `APALACHE_MC`, spawn a local mirror, or
   read local Apalache/Java bytes.
3. Replace the local tool byte-pins for Apalache/Java with a **remote service
   identity record** (new manifest section): endpoint, peer leaf certificate
   SHA-256, observed `apalache version`, observed `java -version`, observation
   timestamp, and the qualification reference for the operator activation.
   Expected identities remain Apalache 0.61.0 and Java 25.0.4+7-LTS; any
   mismatch refuses before registration. The mirror, validator, model, lock,
   original trace, bundle, and candidate inputs keep their existing local byte
   pins and pre/post drift checks — they are still local files.
4. The operator obtains the identity record by a same-time observation of the
   activated service (the same observation the remote-model-check tier needs);
   it is evaluator-owned evidence, cited by the receipt, not generated by the
   reducer.
5. Receipt schema gains `oracleMode` and the service identity record;
   `mirrorecma.lease-reduction-oracle/v1` becomes `/v2` if the change is not
   backward-compatible — schema owner decision at implementation time.

### 5.3 What remote mode does not change

All six safety invariants hold identically: the oracle's role (model-validity
witness) is unchanged; cleanup now additionally means closing the remote
transport with the same independent budget and `unconfirmed` semantics the
driver already implements for forced close. Public projections are untouched.

## 6. Evidence and registry integration

- `framework.reduction` keeps tier `qualification.reduction-domain`,
  `required`. An unavailable required tier is blocked, never skipped or optional;
  both reduction tiers now have credit for the recorded C0.
- The command's argv gained the oracle-mode flag and the service-identity
  argument. That change required a new freeze, snapshot, cache rebuilds,
  installation and affected-tier reruns before credit.
- The adopted tier split separates
  `qualification.reduction-prefix` (R4; needs no model checker — replay only,
  qualifiable locally) and `qualification.reduction-domain` (R5; gated on the
  activated remote service). This allowed prefix acceptance before remote
  activation without diluting the M3 exit condition.

## 7. Implementation and qualification record

This list is executed by the [implementation plan](m3-safe-reduction-implementation-plan.md);
the plan owns sequencing, per-task owners and files, validation commands, and
the re-freeze rules. The items below are the design-level summary.

1. MirrorECMA: add `--oracle-mode remote` + service-identity validation to the
   materializer; focused tests (remote-mode refusal on identity mismatch, no
   `APALACHE_MC` on the remote path, transport-close cleanup accounting).
   **Executed** — MirrorECMA `da18f1a`; settlement helper extracted and tested
   in `4992b07` (see `CHECKPOINTS.md` 2026-09-30).
2. Mirrors: registry argv update, adapter/receipt schema revision, evidence
   tests; optionally the tier split from section 6. **Executed** — Mirrors
   `b19e090`; packaging fix for the installed prefix driver in `e8ba489`.
3. Operator: activate Apalache 0.61.0 / Java 25.0.4+7-LTS on
   `192.168.150.219:8999` and supply the same-time identity observation.
   **Superseded** by the October 1 Windows oracle decision. SR-5b is now
   credited under the current named-profile C0; the original server activation
   is no longer its prerequisite.
4. Re-freeze the selection; rerun the reduction tier(s) and every tier the
   change touches; update Q3. **Executed** — rounds m3r1–m3r5; Q3 readiness
   updated in [q3-readiness-2026-09-30.md](q3-readiness-2026-09-30.md). Later
   full reruns qualified both tiers; [current readiness](q3-post-m6-2026-10-03.md)
   records the latest exact candidate.

## 8. Acceptance (mapped to plan §3 and R4/R5 cards)

- A deterministic fault reduces to its shortest reproducing prefix with all
  shorter prefixes tested, or returns a bounded result with
  `minimalityComplete: false`.
- Fixtures prove fresh reset/disposal per candidate, independent cleanup
  timeout, cancellation, invalid-sequence rejection, signature-drift rejection,
  and hard stop after cleanup uncertainty.
- The lease profile's known mismatch survives at least one smaller model-valid
  candidate; a model-invalid candidate is rejected before SUT construction; a
  valid candidate with a different signature is not accepted; an unsupported
  application returns `reduction_profile_unsupported` without mutation.
- In remote mode: identity mismatch on the service refuses before any session;
  the receipt carries the service identity record; no local Apalache or Java is
  executed or read.
- Non-resettable or unstable cases retain the original bundle and report why
  reduction was unavailable or inconclusive.

## 9. Decision record and separate open scope

1. Operator service activation + identity observation was the R5/remote-model
   qualification prerequisite. The selected Windows oracle and same-campaign
   identity observations satisfy it for the recorded C0.
2. Reduction dispatch timing — settled 2026-09-29: the remote mode was
   implemented first and the prefix tier qualified 2026-09-30; the domain
   tier subsequently qualified under the Windows oracle decision.
3. Remote JDK pin reconciliation — settled 2026-09-30 as a recorded rule
   (tools/evidence/README.md, Docs/qualification-harness-design.md): remote
   pins name the observed service-host toolchain; local tiers pin the verified
   Linux carrier. Current remote observations are retained with the Q3 record.
4. `handling` governance for reproduction policy IDs remains a separate open
   decision; reduction receipts reference but do not define them.
5. Deferred with the native-Ubuntu decision: M4 aggregate cgroup-v2 enforcement
   and the native Ubuntu acceptance profile. Reduction qualification is
   unaffected — the remote oracle needs only the activated service plus
   outbound mTLS, which this WSL2 host provides outside the agent sandbox.

## 10. Non-goals and risks

Non-goals: general deletion/search strategies, additional domain profiles,
native-client reduction, public disclosure of private traces, any relaxation of
Gate policy, and any claim of global minimality.

Risks: (a) the remote service may not yet serve explore sessions under the
selected versions — preflight with a bound-3 smoke before burning a
qualification pass; (b) network variability makes per-candidate timing
noisier in remote mode — budgets remain wall-clock and stop reasons absorb
this; (c) schema versioning of the oracle receipt touches the frozen registry —
absorbed by the mandatory re-freeze in section 7.
