# Mirror Framework task assignments

Date: 2026-09-21

Source: [improvement roadmap](mirror-framework-improvements.md)

Scope: develop and assign implementation tasks; implementation is queued.

Execution started on 2026-09-22 at the user's request. See
[execution decisions and active ownership](execution-decisions.md). B1/C1/I1,
C2/E1 contract drafting, R1/F1, and G1 are assigned to `general-purpose-gpt`
agents. The historical planning checklists below describe the earlier planning
pass; they do not mark these new implementation assignments complete.

Planning-time source identities (recheck before implementation):

| Repository | Full HEAD | Observed worktree |
| --- | --- | --- |
| Mirrors | `eb5cd001b990e6ac5e9b1e9b1c5a17ffb85e25fc` | Untracked `Plans/`, `.projectile-cache.eld`, and `tools/__pycache__/`; preserved |
| MirrorGate | `173075d318e4be926570a1378fc0aa36a1294f89` | Clean |
| MirrorECMA | `a50710c7eb5e4d42631641a97749f6920e67b607` | Clean |

These read-only observations identify the planning inputs, not a newly tested
cross-repository combination.

## 2026-09-25 candidate status

This section records the uncommitted candidate. It does not qualify M5. The
exact catalog selection, install digests, retained run identifiers, and the
Q2 acceptance matrix are in
[q3-readiness-2026-09-25.md](q3-readiness-2026-09-25.md), which is excluded
evidence output. `.projectile-cache.eld` remains on disk and is classified
`pre-existing-unrelated` for every component. The pinned Node 24.15.0 runtime
used by the source R0 commands is the gitignored
`.work/toolchains/node-v24.15.0-linux-x64` tree; it is not catalog content.

The Gate worker reply for a callback failure stays `{code: APPLICATION, message}`
with the callback's own message. Typed rejections stay `VALUE`. The suite
classifies an `observation_shape_mismatch` caused by `APPLICATION` as
implementation and one caused by `VALUE` as codec. No application-code prefix
is part of the worker frame. Source R0 records
`frameworkCatalogDigest` of the parsed catalog document. Digesting the raw
`Buffer` is not the catalog selection. Q1 and Q2 are not complete. `framework.reduction`
is unavailable on this host because
`scripts/materialize-lease-reduction.mjs` assigns `APALACHE_MC` and runs that
local launcher before `startExploreSession`. A remote-only reduction would have
to submit that same explore session to the deployed service at
`192.168.150.219:8999` after the service reports Apalache 0.61.0 and Java
`25.0.4+7-LTS`. Aggregate cgroup enforcement, native Ubuntu acceptance, that
remote tier, interop, publication, and deployment were not established.

## Current execution checkpoint

The planning assignments below remain historical. Active implementation now uses
four fresh-context `general-purpose-gpt` finish owners with non-overlapping
scopes: `distribution_finish`, `evidence_finish`, `reproduction_finish`, and
`recovery_finish`. The parent coordinates and reviews their work; dispatch and
passing helper tests do not complete a task card.

Installed producer commands are frozen in `tools/evidence/commands.json`.
Their retained results, manifest digests, and the catalog selection are
recorded only in the excluded Q3 report. Q1 and Q2 remain incomplete while
origin reproduction, LeaseService reduction, the remote activated service,
interop, delegated cgroup, and native Ubuntu evidence are absent. Real
delegated-cgroup enforcement is a required unavailable tier on this host
because no writable delegated cgroup-v2 parent was supplied. Q3 must preserve
that result as incomplete unless actual retained evidence later changes it.
The rerun follows the execution-environment routes and host preflight defined
in the Q1 card below.

## Assignment and status rules

The requested `@general-purpose-gpt` role is assigned all task families below.
Four agents completed source-grounded work packages with non-overlapping
document ownership. Completing a work package means its task
specifications are ready; it does not mean the proposed product changes exist.

The coordinating agent owns this index, dependency reconciliation, and document
validation. Each implementation task must later receive one active owner with a
specific file scope. Tasks that share a file run sequentially or hand off ownership
explicitly. No task authorizes unrelated refactoring, commits, pushes, publication,
deployment, or broad host cleanup.

| Assigned agent | Task IDs | Owned planning artifact | Implementation state |
| --- | --- | --- | --- |
| `general-purpose-gpt` / `compatibility_install_tasks` | C1–C5, I1–I5 | [Compatibility and installation](tasks/compatibility-and-installation.md) | Queued |
| `general-purpose-gpt` / `reproduction_fidelity_tasks` | R1–R5, F1–F5 | [Reproduction and fidelity](tasks/reproduction-and-fidelity.md) | Queued |
| `general-purpose-gpt` / `evidence_tasks` | E1–E5 | [Durable evidence](tasks/durable-evidence.md) | Queued |
| `general-purpose-gpt` / `gate_recovery_tasks` | G1–G5 | [Gate recovery](tasks/gate-recovery.md) | Queued |
| `general-purpose-gpt` / coordination assignment | B1–B3, Q1–Q3 | This index | Queued |

Cross-cutting B/Q assignments are reserved for a subsequent bounded agent dispatch
after their prerequisites. They have not been launched as implementation jobs.

## Shared handoff contract

C2 and E1 jointly establish a single identity vocabulary before schemas are
implemented. Neither embeds its own competing representation of the other.

- C2 owns component capabilities, supported combinations, and exact companion
  revision selection. It references evidence by immutable identity.
- E1 owns run/artifact identity, observed outcomes, completeness, and evidence
  references. A catalog claim is not fresh execution evidence.
- R1 consumes those identities and preserves private reproduction inputs and
  failure categories without adding fields to author-visible results.
- F1 binds campaigns to unchanged model, observer, corpus, and acceptance inputs.
- G1 owns recovery lifecycle and resource ownership; G5 exports evidence through
  E1 and capabilities through C2 without redefining their schemas.
- I2 consumes the catalog and artifact identities. I3 adds runtime-tree content
  identity; host/kernel admission remains a separate observation.

All handoffs name schema versions, fixture examples, rejected examples, field
ownership, and tests a downstream consumer must pass. Proposed names remain
provisional until the relevant design contract is reviewed.

## B1 — Refresh the implementation baseline

Assigned role: `general-purpose-gpt`. Milestone: M0. Dependencies: none.

Ownership: framework baseline documentation in Mirrors `Plans/`; read-only
inspection of companion repositories and their current guidance.

Deliverables:

- Full SHAs and dirty-tree state for every repository selected for implementation.
- A map of existing catalogs, tool pins, package identities, receipts, project
  diagnostics, mutation fixtures, and Gate lifecycle owners.
- A list of implementation-versus-documentation discrepancies with source links.

Acceptance: all six workstreams have concrete source entry points; implemented,
accepted, installed, and published support remain distinct. Existing uncommitted
work is recorded and preserved. No historical result is assigned to a newer SHA.

Handoff: C1, E1, I1, R1, F1, and G1 receive the baseline. The source inventories in
the four work packages provide an initial input; refresh them before coding.

## B2 — Settle shared contracts and initial profile

Assigned role: `general-purpose-gpt`. Milestone: M0.
Dependencies: B1, C1, draft C2, E1, and I1.

Ownership: cross-repository decision record under Mirrors `Plans/`; schema and
lifecycle details remain owned by their component tasks.

Deliverables: initial OS/architecture, bundled-versus-operator dependencies,
catalog governance, evidence location/retention/access, reset support, cgroup
delegation assumptions, and explicitly unresolved deployment choices.

Acceptance: C2/E1 use compatible identities and outcome semantics; every choice is
marked as observed, proposed, or selected. Any user/operator decision that affects
publication or deployment is resolved before that dependent action. Ordinary
local schema and fixture work can continue without pretending deployment is ready.

Handoff: a concrete contract package for C3, E2, I2, R2, F2, and G2.

## B3 — Establish implementation ownership and gate mapping

Assigned role: `general-purpose-gpt`. Milestone: M0/M1.
Dependencies: B2 and the task cards in all four work packages.

Ownership: this task index and scoped implementation assignments.

Deliverables: one active owner per changed module, full companion pins, contract
links, ordered PR-sized changes, and a mapping from acceptance criteria to tests.

Acceptance: no two active assignments own the same file; blocked consumers name
their missing handoff; required runtime tiers are distinguishable from optional
checks. Agent assignments include scope, preserved work, stop conditions, and
an explicit prohibition on unsupported completion claims.

## Execution waves

| Wave | Eligible tasks | Required handoff |
| --- | --- | --- |
| 0 | B1; C1, I1, E1, R1, F1, G1 inventory/design portions | Current source baseline; proposals may remain drafts |
| 1 | C2, E1 final contracts; B2, B3 | Shared identities and initial profile reconciled |
| 2 | C3, E2–E3; R2 and F2 after their contracts; G2 after its lifecycle design | B3 scope allocation and individual card prerequisites |
| 3 | C4–C5, E4–E5, I2–I3, R3–R4, F3–F4, G3–G4 | Validated producers and fixtures; no implicit schema guessing |
| 4 | I4–I5, R5, F5, G5 | Installed artifacts and applicable runtime acceptance |
| 5 | Q1–Q3 | All required workstream acceptance complete |

Waves express coarse parallelism, not permission to ignore task-specific
dependencies. R5 is limited to explicitly supported domain reductions; native
client or platform expansion requires separately scoped work.

## Q1 — Qualify the exact installed candidate

Assigned role: `general-purpose-gpt`. Milestone: M5.
Dependencies: C5, I5, R5 or explicitly scoped reduction support, F5, E5, G5.

Ownership: qualification harness/evidence in Mirrors; component gates remain
owned by their repositories. Use an isolated consumer and disposable test roots.

Deliverables: an exact candidate manifest and evidence for installation, read-only
diagnostics, correct/faulty replay, reproduction and bounded reduction, fixed
observer mutation acceptance, interruption recovery, and confirmed cleanup.

Acceptance: execute all seven end-to-end demonstrations in the roadmap. Run
applicable Mirrors, MirrorECMA, Gate, and interop gates with full companion SHAs.
Record commands, exit results, required/optional skips, and environmental failures.
A required unavailable backend leaves qualification incomplete.

All model-check execution for this qualification must run through the deployed
Mirrors service at `192.168.150.219:8999`; this coordinator has insufficient
memory and must not run Apalache, TLC, or another model checker. `lake test` is
not safe here because it runs TLC and probes a developer-local Apalache fallback.
Run the local aggregate as `bash tools/run-local-no-model-check.sh`; its explicit
model-check exclusions remain remote obligations covered separately by the
private `mirrors.remote-model-check` evidence. Retain the endpoint/server pin and
a same-time `ModelMirrors` service,
installed-binary, source-revision, Apalache and Java identity observation as
defined by the qualification harness. The current interop runner has no remote
service mode, so its required tier remains unavailable here rather than being
silently run locally or credited from the standalone remote probe.

Execute the installed gates only where their primitives are permitted; two
routes are sanctioned. (a) Escalate from the current host through a working
approval reviewer: attended `approvals_reviewer = "user"`, or a repaired
`auto_review` guardian via a catalog `auto_review_model_override` naming a
provider-served model (the 2026-09-25 pass failed closed here: the provider
rejected `codex-auto-review`, so every escalation was refused before
execution). (b) Run on a native Ubuntu 24.04 x86_64 fixture with a declared
bypass profile (`sandbox_mode = "danger-full-access"`, `approval_policy =
"never"`); the fixture itself is the boundary. Do not nest the qualification
inside an agent sandbox that denies `ptrace`, sockets, or required writes:
the framework's bubbles are the intended isolation, and such nesting turns
environment limits into false product-tier incompletes. Preflight the host
(`strace` probe, `ptrace_scope` <= 1, bubblewrap >= 0.9.0 non-setuid,
Ubuntu 24.04 AppArmor user-namespace policy, loopback) and record the tested
profile identity with the evidence. WSL2 results remain diagnostic and leave
native acceptance incomplete.

The 2026-09-22 remote boot/smoke check found `ModelMirrors` running with automatic
startup and returned `VALID` for bound-3 HourClock over verified TLS 1.3 mTLS.
It remains supporting evidence because the active backend was Apalache 0.58.2 /
Java 21.0.11. The selected Apalache 0.61.0 and Java 25.0.4+7-LTS artifacts were
staged but not activated; Q1 needs a fresh identity observation and validation
after activation.

## Q2 — Independently verify retained evidence

Assigned role: `general-purpose-gpt`. Milestone: M5. Dependencies: Q1, E3–E5.

Ownership: evidence verification and qualification report; no producer changes
unless delegated separately after a finding.

Deliverables: verification from a separate checkout or installed verifier without
depending on temporary producer directories. Include public-disclosure checks,
artifact completeness, hashes, catalog references, and cleanup outcomes.

Acceptance: required evidence survives scratch removal; tampering/missing artifacts
is detected; private data is absent from public projections. Report integrity and
execution provenance separately. Failed verification blocks qualification.

## Q3 — Publish a readiness report and handoff

Assigned role: `general-purpose-gpt`. Milestone: M5. Dependencies: Q1, Q2.

Ownership: final roadmap/task status and release-readiness documentation in Mirrors.

Deliverables: completed/partial task matrix, exact accepted profiles, retained
evidence links, limitations, migration/rollback guidance, and remaining operator
decisions. Document preparation does not publish packages or deploy services.

Acceptance: every completion claim has retained evidence; source-level, local
installed, hosted CI, and published states remain separate. The report identifies
what can be released and what still requires a distinct operational action.

## Planning completion checklist

- [x] All 30 roadmap task IDs have concrete cards and assigned roles.
- [x] B1–B3 and Q1–Q3 cover baseline, coordination, and final qualification.
- [x] Cross-workstream dependencies and shared file ownership are reconciled.
- [x] Relative links and document formatting pass validation.
- [x] Implementation remains explicitly queued; no runtime acceptance is implied.

Planning validation on 2026-09-21 checked every relative link, all 30 roadmap IDs
exactly once across the four packages, whitespace, and worktree scope. All four
assigned agents completed their document tasks. B1–B3/Q1–Q3 remain assigned
follow-on work, not executed implementation or qualification. No product source,
runtime tests, publication, commits, or pushes were part of this planning pass.
