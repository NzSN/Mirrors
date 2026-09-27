# Checkpoints

Date-flow record of execution checkpoints, newest entry first. Each dated
entry records the frozen identity, qualified evidence, validation performed,
and open work at that date. Entries are append-only history, not current
status; later entries do not implicitly amend earlier ones.

## 2026-09-27 — Standing after the reproduction round: M5 position and open decisions

Status: **standing checkpoint, no execution.** Records the milestone positions
after the route-2 campaign and the decisions still open. Full evidence detail:
`/tmp/q1-route2-result.md` (Parts A–F); next work package spec:
`/tmp/m3-reduction-plan.md`.

### Milestone positions (selection `68a3ad58…`, diagnostic WSL2 profile)

| Milestone | Position |
| --- | --- |
| M0, M1 | Done (2026-09-22 reviews; catalog and evidence exercised together) |
| M2 | Done on the diagnostic profile: both D bindings qualified (`run-432e1b13…`, `run-2a1a8c0c…`); native Ubuntu acceptance descoped by operator decision 2026-09-27 |
| M3 | Partial: mutation controls qualified (17/17 local + Gate); reproduction qualified and credited (`run-6accf0f9…`); **safe reduction outstanding** (remote explore-session mode; spec staged) |
| M4 | Partial: recovery qualified (`run-41660b4b…`); **aggregate-limit gate open** (no delegated cgroup-v2 parent on this host) |
| M5 | In execution: Q1 diagnostic scope verified (15 credited runs, both D bindings, schema v2), Q2 offline 16/16; Q3 pending; **cannot be treated as complete** — demonstration #4's reduction half, interop, remote model check, and cgroup tiers lack evidence, and M3/M4 partials structurally forbid M5-complete. A descoped variant would need a named profile (e.g. "M5-diagnostic"), never the bare name. |

### Open decisions (owner: user)

1. **cgroup tier**: keep incomplete, or descope alongside native Ubuntu.
2. **Reduction dispatch timing**: implement the remote explore-session mode now
   (live run still gated on operator service activation) or hold until the
   service is activated.
3. **`handling` governance**: the reproduction bundle's five policy IDs are
   documented test-fixture placeholders; a governance decision owns the real
   values (preflight does not consult them today).
4. **Remote JDK pin reconciliation**: local Microsoft JDK archive bytes
   (`75894d10…`/`e7bc0bc0…`) differ from the remote-tier pins
   (`54ba13f3…`/`58df5c13…`); decide whether pins name the server's toolchain.

### Operator prerequisites (unchanged)

Activate Apalache 0.61.0 / Java 25.0.4+7-LTS on `192.168.150.219:8999` with a
same-time identity observation (unblocks remote model check AND reduction);
supply a delegated cgroup-v2 parent on a suitable host (unblocks M4's
aggregate-limit clause); provide interop companion checkouts or approve a
remote-only interop mode.

## 2026-09-27 — Reproduction gate fixed, qualified, and credited (selection 68a3ad58)

Status: **`framework.reproduction` is implemented, qualified, and credited.**
M3 advances to reproduction + mutation complete, reduction outstanding. M5
remains not qualified (reduction, interop, remote model check, cgroup open;
native Ubuntu descoped). Executed by the delegated `general-purpose-flash`
executor; full detail in `/tmp/q1-route2-result.md` Part F.

- Final selection: `68a3ad583d2889695e37bbde4af3b81d12b184a8d72e1bb9a360d6266a709c68`
  (byte-stable; Mirrors `e23ff68e…`/31, MirrorECMA `80e63904…`/9, MirrorGate
  `b0ba4350…`/3). Snapshot `22e54f1f…`; local manifest `eb57ddd4…`; gate
  manifest `103e1769…`; both installs `state=committed`.
- Decisions applied (user-confirmed): (a) MirrorECMA exports
  `inspectProjectReproductionAuthority` (+ `identitySha256`-class helpers) from
  `src/index.ts`; post-hoc signature construction via public validators;
  authoritative R0 = the installed faulty replay of the same selection.
- Mirrors change set: `tools/evidence/reproduction-capture.mjs` (R0→bundle via
  the public authority, refusal on R0 inconsistency before any suite run),
  `mirrorecma.reproduction-capture/v1` adapter in `collect.py`, attachment-plan
  schema enum, registry fixes (R-a/R-b/R-c), and a scope-verifier extension
  letting a reproduction node credit its R0 as origin-or-replay. Suites:
  distribution 31 OK, evidence 112 OK; MirrorECMA focused jest 1/1 +
  `pnpm run check` clean.
- Reproduction evidence: bundle sha256 `bb657526d52f0f20…` built from R0
  `run-63e28740…`; installed CLI `status: reproduced`, exit 0,
  expected == observed (trace 0, state 1, action `enqueue`); `handling` policy
  IDs are documented test-fixture placeholders pending the governance decision.
- Scope verdict: `{"status": "verified", "verifiedRunCount": 15}` — both D
  bindings credited, reproduction node credited. Offline verifier: 16/16.
- Key runs: reproduction `run-6accf0f9-8323-41ca-b385-29fcd66b425d`; D-local
  `run-432e1b13-…`; D-gate `run-2a1a8c0c-…`; R0 `run-63e28740-…`; Q
  `run-c8969f9c-…`; 15 tiers total.
- Confirmations: no commits/pushes (HEADs unchanged); store append-only
  (116 runs); no local model checker; no remote-service contact; WSL2
  diagnostic profile.

## 2026-09-27 — Q1 route-2 rerun: verified two-binding scope (diagnostic WSL2 profile)

Status: **Q1 diagnostic scope complete; Q2 verified over the full required scope.
M5 remains not qualified** (reproduction, reduction, interop, remote model check,
and cgroup tiers open; native Ubuntu acceptance descoped by operator decision
2026-09-27). Executed by the delegated `general-purpose-flash` executor per
`/tmp/q1-route2-plan.md` and the Part-C brief; full detail in
`/tmp/q1-route2-result.md` (Parts A–E).

### Final candidate identity

- Catalog selection: `9ae8fb472a183183f91fb3128e6b6c2a7fda71d9f6a0b43e7066a5958abb451e`
  (byte-stable; Mirrors `b11c502c…`/30 paths, MirrorECMA `a306a2cd…`/7,
  MirrorGate `b0ba4350…`/3 — `IDENTITY_OK`).
- Snapshot index SHA-256 `2135f090…`; local manifest `c867b01a…`; gate manifest
  `e1c572e1…`; both installs `state=committed`, pristine pre-audit.
- Lineage this round: `9b187ba7…` (2026-09-25, superseded by doc drift) →
  `52e9a083…` (doc-drift adoption) → `32135a3b…` (P1–P3 batch) → `af71db25…`
  (MirrorECMA vocabulary) → `9ae8fb47…` (reference-project generator fix).

### Qualified runs (14 credited + Q scope run; all cite the final selection)

| Command | Run ID |
| --- | --- |
| `framework.install-diagnostics` (D-local) | `run-ae0b01c9-f874-4c1f-894f-9d867a20a4cb` |
| `framework.install-diagnostics-gate` (D-gate) | `run-2b6e15c6-6c81-44b2-a807-cb1949878d51` |
| `framework.replay-correct` | `run-fef0497e-…` |
| `framework.replay-faulty` (intended mismatch) | `run-1b91446a-…` |
| `framework.mutation-local` | `run-45a009d0-…` |
| `framework.mutation-gate` | `run-23fdc30d-…` |
| `mirrorgate.application-campaign.work-queue` | `run-d45164e2-…` |
| `mirrorgate.application-campaign.persistent-transfer` | `run-3463e63d-…` |
| `mirrorgate.application-campaign.lease-service` | `run-755e0221-…` |
| `mirrorgate.recovery` (bound to fresh work-queue run) | `run-efeb64cc-…` |
| `mirrorecma.project-check` | `run-9fd1355e-…` |
| `mirrorecma.test` | `run-b2d0d731-…` |
| `mirrorgate.required` | `run-b936c96a-…` |
| `mirrors.local-no-model` (40/40 steps, Microsoft JDK 25.0.4+7 on PATH) | `run-762e0694-…` |
| Q scope run | `run-413a466b-dc30-491b-9956-ce718c60aef0` |

### Verifier verdicts (verbatim)

- Scope verifier (schema v2, both D bindings): `{"status": "verified",
  "verifiedRunCount": 14}`; local binding `c867b01a…` → `[mirrorecma, mirrors]`,
  gate binding `e1c572e1…` → `[mirrorecma, mirrorgate, mirrors]`.
- Offline bundle verifier: **15/15 exit 0**, `integrity: sha256-membership-verified`.

### Defects surfaced and fixed during this campaign (all with focused tests)

1. MirrorECMA exclusion-vocabulary seam: `planning-documentation` added on both
   sides (Mirrors P3 + MirrorECMA `framework-catalog.ts`); doctor refusal cleared.
2. Distribution generator: `write_reference_project` now selects every installed
   package for the gate profile (was: only `mirrorecma`; the D audit's doctor
   caught the mismatch at `catalog.filesystem-binding`).
3. Scope verifier: `command_cwd_matches` now honors `requiredCwdSubdirectory`
   and is stricter than before (nested commands exactly one level below owner).
4. Two envelope declaration bugs (`mirrorgate.required`, `mirrors.local-no-model`
   declared wrong component sets) — re-collected, not edited.

### Route-2 notes

Headless guardian repaired via `auto_review_model_override` in the operator
model catalog; escalations approved per action. Scope schema v2
(`distributionBindingRunIds`, 1–8) credits each installed node against its own
D binding by exact component-set equality. Planning docs (`Plans/**`, `tmp/**`,
root `CHECKPOINTS.md`) are now class `planning-documentation` and no longer move
the selection digest. Evidence is diagnostic WSL2 evidence; it does not
establish native Ubuntu acceptance.

### Remaining blockers

`framework.reproduction` (registry defects + identity-authority decision, see
`tmp/m5-reproduction-adapter.md`), `framework.reduction` (pins local Apalache),
`mirrors.interop` (missing companion checkouts), `mirrors.remote-model-check`
(operator credentials; Microsoft-JDK bytes differ from the remote-tier pin),
delegated cgroup-v2 enforcement (no writable parent on this host; descope
decision open), publication/deployment (separate operational actions).

### Confirmations

No commits/pushes (HEADs Mirrors `ce75058b…`, MirrorECMA `59b722a…`, MirrorGate
`72880aa…`); canonical store strictly append-only (76 → 93 runs); no local
model checker; no contact with `192.168.150.219:8999`; no Plans/ or
CHECKPOINTS.md edits by the executor (this entry is parent-written after round
close).

## 2026-09-25 — M5 execution checkpoint

Status: **M5 not qualified; Q1 and Q2 incomplete.** This records the delegated
`general-purpose-flash` execution of [the M5 plan](tmp/m5-qualification-plan.md).
The full run table and blockers are in
[the Q3 readiness report](Plans/q3-readiness-2026-09-25.md); the reproduction
contract analysis is in [the adapter handoff](tmp/m5-reproduction-adapter.md).

### Frozen candidate and retained evidence

- Catalog selection: `9b187ba71af41cfff8ad681f174f3f88bcadd7b5aee99cac082b589e257e8877`.
- Source snapshot: `/tmp/mirrors-candidate-snapshot-e14`, index SHA-256 `22fdde17f6b0c568798c3e0fcaff28b71c3a6b1d49f322f901b4f56c251be2a9`.
- Local and Gate canonical manifest digests: `6d9464fbc77b09e6c5758a911848e69409f6aba6734eb9cfeecb3cc13d3fc55b` and `df07907cd6b7208f2234d477c8b1eb927b9d17b7e98df11a584d240755b8f87f`. Both caches verified and both installs reported `state=committed`; `/tmp/m5/m5-freeze-verify.py` reported `PROBLEMS: none` after execution.
- Evidence from this pass is in `/tmp/m5-store`. The canonical evidence store was read-only to the sandbox and was not modified. Two earlier origin runs under the same selection were copied into `/tmp/m5-store` for offline scope checks. Retained identifiers and envelope hashes are in `/tmp/m5/m5-summary.json` and the Q3 report.

| Individually qualified command | Run ID |
| --- | --- |
| `framework.replay-correct` | `run-a120cdd5-e296-4ae3-bcd0-c9d2ce2e9351` |
| `framework.replay-faulty` (intended mismatch) | `run-2b9bfa73-2c80-428d-96c6-60750c8f76f7` |
| `framework.mutation-local` | `run-ba548a80-6f32-43a1-bc87-a6f1deb8e62f` |
| `mirrorgate.recovery` (filesystem resource; no cgroup claim) | `run-e0cbd2b9-365a-416b-9eb4-2613ce386c39` |
| WorkQueue origin campaign | `run-dce8b40e-4e5d-4d62-a1b8-e3bde4fe02ee` |
| PersistentTransfer origin campaign | `run-2686572d-a84d-42fc-8103-cf47deaf29ef` |

These are individual run results, **not** a verified Q2 scope. The installation
audit failed under sandbox `ptrace` restrictions, so there is no qualified
distribution binding for the scope verifier.

### Validation performed

- The authoritative `/tmp/m5/logs-v3/` local non-model run executed the 40 steps from `tools/run-local-no-model-check.sh`: 35 exited zero and five were blocked by sockets or the required Java 25.0.4+7 toolchain. `explorer_spec` exited zero while printing three socket failures, so it was not credited as green. The `/tmp/m5/LOG-PROVENANCE.md` note distinguishes this run from earlier temporary-harness path failures.
- The installed offline bundle verifier accepted an untouched bundle and rejected a deleted artifact and a changed byte. The scope verifier correctly rejected an attempted scope containing the unqualified installation audit. Q2 remains incomplete.
- An installed CLI probe reproduced the recorded faulty replay with `status: reproduced`, exit zero, and wrote its result and cleanup files. This proves the replay mechanism, not the registered `framework.reproduction` command.
- `git diff --check` passed. No source files were changed during this execution pass; the Q3 readiness report and these `tmp/` documents were updated. Nothing was committed, pushed, published, or deployed. No local model checker ran, and the remote service was not contacted or changed.

### Required work still open

| Area | Blocking fact | Next action |
| --- | --- | --- |
| Installation and Gate checks | The sandbox denies `ptrace`, AF_INET/AF_UNIX sockets, and writes in MirrorECMA, MirrorGate, and the canonical store. The installation audit, Gate aggregate, LeaseService origin, and some source gates cannot qualify here. | Rerun on a permitted native Ubuntu runner with loopback, UNIX sockets, `ptrace`, and a writable evidence store. Provide a delegated cgroup-v2 parent for real aggregate-limit evidence. |
| Automatic approval | Escalated commands were rejected *before execution*: `supported API model names are deepseek-flash, deepseek-v4-pro, but you passed codex-auto-review`. | Repair the automatic reviewer configuration or provide an approved execution environment. The rejected action was unsandboxed access needed for sockets, `ptrace`, and the canonical store; no such run was performed. |
| Reproduction | The frozen registry omits required CLI arguments, passes an incompatible tool registry, and names a correct project for a mismatch bundle. The bundle's project identity authority is not in MirrorECMA's public package exports. | Prefer a MirrorECMA-owned public identity/capture API, then implement the Mirrors R0-to-bundle adapter and fix the registry. See [the adapter handoff](tmp/m5-reproduction-adapter.md) for the proved mechanism, secondary policy choices, and file list. |
| Reduction and interop | Reduction starts a pinned local Apalache launcher; interop requires a local Apalache and missing companion checkouts. Local model checking is prohibited on this coordinator. | Provide a reviewed remote explore-session/interop path or run these tiers on an authorized suitable host with the required companions. |
| Remote model check | Operator credentials and network access are absent. The selected deployed Apalache 0.61.0 and Java 25.0.4+7 identities were not observed. | Activate and inspect the selected remote service under operator control, then retain a same-time identity observation and Mirrors CLI result. |
| Q2 and Q3 | No qualified distribution binding or full verified scope exists. | After producer changes, re-freeze the selection and rerun affected Q1 commands; then verify the full retained scope and update Q3. |

Publication and production deployment are separate operational actions; their
absence is not treated as a substitute for any required M5 tier. Any producer
change alters the candidate identity, so the six individual runs above cannot
automatically qualify a later selection.
