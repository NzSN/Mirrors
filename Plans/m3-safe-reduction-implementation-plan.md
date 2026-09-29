# M3 safe reduction: implementation plan

Date: 2026-09-28

Status: proposed; execution is not authorized by this document. No task below
claims qualification by passing source tests; a tier is credited only by
retained installed-run evidence against a frozen selection.

Design: [m3-safe-reduction-design.md](m3-safe-reduction-design.md) (architecture,
safety contract S1–S6, remote oracle mode). Roadmap:
[mirror-framework-improvements.md](mirror-framework-improvements.md) §3. Task
cards: [R4/R5](tasks/reproduction-and-fidelity.md#r4---add-safe-deterministic-prefix-reduction).
Position record: [CHECKPOINTS.md](../CHECKPOINTS.md) (2026-09-27 standing).

## 0. Execution rules (apply to every phase)

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
