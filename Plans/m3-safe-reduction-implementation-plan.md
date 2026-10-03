# M3 safe reduction: implementation plan

Date: 2026-09-28

Status (2026-10-03): SR-5a and SR-5b are qualified for the selected
`m5-wsl-windows-remote/v1` profile on post-M6 working-tree C0
`879be4fd92d3c2e1abbb19b0737c620dcf7cea466f6796a4703b75aa5a533c25`.
The [current readiness record](q3-post-m6-2026-10-03.md) includes both
reduction tiers, their linked reproduction runs, affected-tier reruns and
independent Q2 verification. This does not qualify later commits or edits;
broader M4 aggregate/process recovery and native Ubuntu acceptance remain
unqualified. Source tests alone never qualify a tier.

The phase cards and September 30 execution record below preserve the original
plan and its historical checkpoint. The October 1 [Windows oracle decision](execution-decisions.md#2026-10-01--current-windows-host-is-the-designated-remote-oracle)
replaced their former endpoint/toolchain activation prerequisite; use the current
readiness record for the exercised oracle identity and profile scope.

Design: [m3-safe-reduction-design.md](m3-safe-reduction-design.md) (architecture,
safety contract S1–S6, remote oracle mode). Roadmap:
[mirror-framework-improvements.md](mirror-framework-improvements.md) §3. Task
cards: [R4/R5](tasks/reproduction-and-fidelity.md#r4---add-safe-deterministic-prefix-reduction).
Position record: [CHECKPOINTS.md](../CHECKPOINTS.md) (dated execution history).

## 0. Original execution rules (2026-09-28)

1. Any source or producer change invalidates the frozen selection: re-run
   identity refresh → snapshot → cache → install → affected tiers (Phase 4)
   before any new evidence is credited.
2. Move `.projectile-cache.eld` out of all three checkouts before every
   identity refresh; run refresh twice and require `BYTE_STABLE`; keep it out
   of snapshot inputs while leaving it on disk.
3. No local Apalache or TLC on this coordinator. All model checking goes
   through the deployed service at `192.168.150.219:8999` (remote oracle mode)
   or is not run.
4. Planning documents (`Plans/**`, `CHECKPOINTS.md`) are class
   `planning-documentation` and do not move the selection digest; verify this
   still holds at re-freeze time.
5. Environment-limited tiers are recorded blocked, never skipped or optional.
   Agent-sandbox denials (sockets, `ptrace`) mean qualification runs use the
   host posture from the roadmap's qualification-execution-environment section.
6. Ownership: MirrorECMA owns reducer modules, drivers, and their tests;
   Mirrors owns the validator contract, evidence registry, and freeze chain;
   the operator owns service activation and the identity observation.
7. Deferred tiers (operator decision 2026-09-29, no native Ubuntu machine):
   M4 aggregate cgroup-v2 enforcement and the native Ubuntu acceptance
   profile. SR-5a runs on WSL2 in the escalated posture (ptrace/sockets).
   SR-5b depends only on the operator service activation (SR-0.3), not on
   native Ubuntu; no SR item below is blocked by the deferral.

## 1. Phase SR-0 — decisions and operator requests (no code)

| ID | Action | Owner | Done when |
| --- | --- | --- | --- |
| SR-0.1 | Settle reduction dispatch timing. Recommendation (design §9.2): implement remote mode now; qualify after activation. | user | decision recorded in `CHECKPOINTS.md` |
| SR-0.2 | Settle the tier split (design §6): `qualification.reduction-prefix` + `qualification.reduction-domain` replacing the single `qualification.reduction`. | user | decision recorded |
| SR-0.3 | Request activation of Apalache 0.61.0 / Java 25.0.4+7-LTS on `192.168.150.219:8999`, with same-time identity observation (versions, peer leaf SHA-256, timestamp, qualification ref). | operator | observation record in hand |
| SR-0.4 | Settle receipt schema versioning: extend `mirrorecma.lease-reduction-oracle/v1` additively or mint `/v2`. | MirrorECMA owner | decision recorded |

SR-0.3 is on the critical path only for SR-5b. Phases SR-1…SR-4 do not wait
for it.

## 2. Phase SR-1 — MirrorECMA: remote oracle mode

Goal: the materializer can run its model oracle against the deployed service
instead of a local Apalache, with identical safety behavior (design §5).

| ID | Files | Work | Validation |
| --- | --- | --- | --- |
| SR-1.1 | `src/lease-reduction.ts` (types), new test fixtures | Define the service identity record: endpoint, `peerLeafSha256`, observed Apalache/Java versions, `observedAt`, `qualificationRef`; strict key/shape validation; expected-identity constants 0.61.0 / 25.0.4+7-LTS. | `pnpm exec jest --runInBand test/reproduction-domain-reducer.test.ts` |
| SR-1.2 | `scripts/materialize-lease-reduction.mjs` | Add `--oracle-mode local|remote` (default `local`) and `--service-identity FILE`. Remote mode: no `APALACHE_MC`, no local Apalache/Java byte-pins, no `spawnMirror`; oracle opens via `connectTlsMirror`; peer leaf asserted against the record; mirror/validator/model/lock/trace/bundle local pins and pre/post drift checks unchanged; budgets, forced-close cleanup accounting, and failure receipts unchanged. | new `test/reproduction-remote-oracle.test.ts` |
| SR-1.3 | same | Refusal fixtures: wrong version / wrong fingerprint / missing record → refusal before any session open; `APALACHE_MC` provably unset on the remote path; transport-close failure → `cleanup unconfirmed` → failure receipt, exit 1. | same test file |
| SR-1.4 | receipt schema per SR-0.4 | Receipt carries `oracleMode` and the service identity record; versioned per the SR-0.4 decision. | schema round-trip tests |

Exit: `pnpm run check` clean; focused reducer tests pass; no live service
contact has occurred or been required.

## 3. Phase SR-2 — MirrorECMA: prefix-reduction driver (tier split)

Goal: an installed-entry driver for R4 so the prefix tier can qualify locally
without any model checker. Skipped entirely if SR-0.2 declines the split.

| ID | Files | Work | Validation |
| --- | --- | --- | --- |
| SR-2.1 | new `scripts/reduce-reproduction-prefix.mjs` | Driver: load bundle + stability record; refuse unless deterministic/resettable/stable; inject `validateCandidate`/`evaluateCandidate` over the installed replay path with fresh SUT, independent cleanup budget, policy bounds; emit `mirrorecma.reproduction-prefix-reduction/v1`. | new focused test |
| SR-2.2 | same | Fixtures: shortest-prefix with all shorter tested; budget-expired → `smallest_observed_reproducing_prefix` + `minimalityComplete: false`; signature drift rejected; cleanup uncertainty → hard stop (`cleanup_independence_lost`); unstable case → `not_eligible`. | same test file |

Exit: focused tests pass; claim vocabulary matches design §4 (S4) exactly.

## 4. Phase SR-3 — Mirrors: registry and evidence wiring

| ID | Files | Work | Validation |
| --- | --- | --- | --- |
| SR-3.1 | `tools/evidence/commands.json` | Update `framework.reduction` argv for oracle-mode/service-identity args; if split, register prefix and domain commands with tiers `qualification.reduction-prefix` / `qualification.reduction-domain`, both `required`. | evidence unit tests |
| SR-3.2 | `tools/evidence/collect.py`, `tools/evidence/schema/attachment-plan-v1.schema.json` | Adapter handling for the receipt version from SR-0.4; prefix-reduction attachment adapter if split. | `tools/evidence/tests/test_collect.py` incl. negative cases (receipt/manifest identity mismatch) |
| SR-3.3 | `tools/evidence/qualification-profiles.json`, scope schemas | Register new tier IDs in scope requirements; blocked-not-skipped semantics unchanged. | scope-verifier unit tests |

Exit: Mirrors evidence/distribution unit suites pass (`distribution`,
`evidence` suites as in the route-2 checkpoint); no re-freeze yet.

## 5. Phase SR-4 — re-freeze chain

Single ordered run after SR-1…SR-3 land in their repos with pinned companion
SHAs:

1. `.projectile-cache.eld` out of all three checkouts; identity refresh ×2 →
   `BYTE_STABLE`; record new selection digest.
2. Snapshot from the pushed SHAs; verify index; build local and Gate caches
   from the same snapshot; `tools/distribution/verify.py` both.
3. Transactional install of both prefixes; confirm `state=committed`.
4. Smoke the installed CLI (`replay-correct`, `replay-faulty`) before burning
   qualification runs.

Exit: new selection recorded in a parent-written `CHECKPOINTS.md` entry; prior
selection demoted to diagnostic.

## 6. Phase SR-5 — qualification runs

| ID | Run | Gate | Done when |
| --- | --- | --- | --- |
| SR-5a | `qualification.reduction-prefix` | none (local, no model checker) | retained run, receipt verified, scope verifier credits it |
| SR-5b | `qualification.reduction-domain` | SR-0.3 (activated service + identity observation) | retained run against the remote oracle; receipt carries the service identity record; known lease mismatch reproduced from the reduced candidate |
| SR-5c | affected-tier reruns (replay, reproduction, mutation, scope) per rule 0.1 | SR-4 | scope verifier `verified`; offline bundle verifier all-green |

## 7. Phase SR-6 — close-out

1. Parent-written `CHECKPOINTS.md` entry: new selection, credited runs, M3 row
   position.
2. Update the M3 row in `mirror-framework-improvements.md` (Partial → Done only
   when SR-5a/5b are both credited; if the split was declined, the single tier
   covers both) and refresh Q3 readiness.
3. Record M5 impact: demonstration 4's reduction half credited; M5 remains not
   qualified until interop, remote model check, and the cgroup tier close.

## 8. Dependency summary

```text
SR-0.1/0.2/0.4 ──► SR-1 ──► SR-3 ──► SR-4 ──► SR-5a ──► SR-6
            ──► SR-2 ──►  ┘            └─► SR-5c ──► ┘
SR-0.3 (operator) ────────────────────────► SR-5b ──► SR-6
```

## 9. Risks and fallbacks

- Service does not yet serve explore sessions under the selected versions:
  preflight with a bound-3 smoke before the SR-5b pass; on failure, SR-5b stays
  blocked and M3 stays Partial — no downgrade.
- Receipt schema decision (SR-0.4) invalidates adapter fixtures: absorb in
  SR-3.2 before re-freeze, never after.
- Remote-mode timing variance: budgets are wall-clock; stop reasons and
  `minimalityComplete: false` absorb partial search honestly.
- If the tier split is declined, SR-2 is dropped and SR-5a merges into SR-5b;
  the M3 exit condition is unchanged either way.

## 10. Historical execution record (2026-09-30)

Rounds m3r1–m3r5 executed the SR-4/SR-5 chain (identity refresh → snapshot →
dual caches → dual installs → affected-tier reruns + Q2) under the standing
constraints (no commits by the executor, no local model checker, blocked steps
recorded, never skipped). Closing qualified selection:
`fed55175b792feaec86cf71bf7fae1bae680a0313797a5c982f3a6ecc746f025`
(Mirrors `e6772d5`, MirrorECMA `4992b07`, MirrorGate `0fa8a31`).

Defects found by execution and fixed in sequence:

- Mirrors `e8ba489` — the installed `mirrorecma` package shipped only the
  materializer; `PACKAGE_SCRIPTS` / `copy_package_scripts` now materialize both
  reduction drivers (fixed the `framework.reduction-prefix` `MODULE_NOT_FOUND`).
- MirrorECMA `ad3c0cb` — the prefix driver wrote `corpusTraceFile` but never
  passed it to the reproduce seam (`traces: [undefined]` →
  `suite_configuration_invalid`).
- MirrorECMA `b753695` — the evidence reader rejects fractional JSON numbers;
  every `durationMs` emission is now integer milliseconds.
- MirrorECMA `4992b07` — probe-path `coverage_unmet` normalization (a prefix too
  short to reach the failure normalizes to "no signature" instead of
  `normalization_context_missing`) and the extracted, unit-tested
  `settleOracleCleanup` transport-close helper.

SR-5a result: `framework.reduction-prefix`
`run-dcc51362-9084-4c2d-9eeb-9329bacb8d01` — `shortest_reproducing_prefix`,
`minimalityComplete: true`, `stopReason: complete`, best 2/16, cleanup
confirmed. Q2 scope `verified` 16/16 (reduction tier credited); the offline
verifier is green over every finalized bundle. SR-5c reruns covered D-local and
D-gate, both replays, reproduction, both mutations, all three origin campaigns,
recovery, the source gates, and the local non-model gate.

SR-6: executed — the parent wrote the `CHECKPOINTS.md` records ("SR-5a credited"
and "Closing sweep complete") and the M3/M5 status rows, and
[q3-readiness-2026-09-30.md](q3-readiness-2026-09-30.md) is the Q3 readiness
report for this selection.

Remaining gate at that checkpoint: SR-5b (`qualification.reduction-domain`) — operator activation
of Apalache 0.61.0 / Java 25.0.4+7-LTS at `192.168.150.219:8999` plus the
same-time identity observation.
