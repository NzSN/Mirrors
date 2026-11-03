# Codex review of Grok mainwork delegation

Status: **preparation accepted with corrections**. All three workstreams have
completed, and Codex verified 116 inventoried files plus command/log bindings.
This accepts stage/task development, bounded source validation and readiness
reports. It does not pass final S1–S8 release/framework qualification.

The [correction overlay](review/corrected-commands.md) is authoritative where
Grok's drafts differ. Original job outputs/inventories are preserved unchanged.

## Checks already performed

- Verified the task DAG has 25 unique task IDs, all dependencies resolve and no
  cycles exist. MW-63 explicitly requires final installed admission; remote
  reductions conditionally require MW-54's fresh observation.
- Confirmed every original byte of the HEAD version of CHECKPOINTS.md remains
  after the prepended November 3 entry. New plan/brief links resolve.
- Inspected Grok's three actual test logs and command receipts. Release tests:
  11 passed. Evidence tests: 146 passed. Distribution's first run: 61 tests,
  two failures and eight errors attributable to installation directories on
  tmpfs; that failed attempt is preserved.
- Independently reran the distribution suite with a task-owned TMPDIR on the
  repository's ext-family filesystem: 61 tests passed, exit 0. Exact command,
  environment override, raw logs and hashes are in
  [review/distribution-ext4.json](review/distribution-ext4.json).
- Independently compared source version, both catalog variants, both component
  locks and current companion HEADs. The exact comparison is retained in
  [review/identity-check.json](review/identity-check.json).

## Confirmed freeze/admission findings

1. Mirrors product metadata in both catalogs and component locks remains
   `0.1.1`; Shell/Version.lean declares `0.2.0-rc.5`. Product propagation from
   the catalog does not resolve a wrong catalog value. MW-12 must reconcile the
   maintained product authority with the selected actual candidate before freeze.
2. The catalog binds Mirrors `bd5d3b5` with a dirty-content identity; current
   HEAD is `75fbf96`. The final C0 must be refreshed against the final source,
   not credited from the older packages or a stale catalog snapshot.
3. Catalog companion pins and locally available checkouts differ: catalog ECMA
   `9192171` versus local `f943588`, and catalog Gate `4b379ac` versus local
   `4ef786b`. Selection/acquisition must precede source-dependent command
   binding. Read-only local source inspection does not qualify another pin.
4. The exact newly pinned Batteries carrier is absent from its recorded local
   retention path. Artifact acquisition must preserve the pin; do not substitute
   or silently regenerate a different Git bundle.

## Delegation and artifact acceptance

| Workstream | Job / continuation | Reviewed output | Verdict |
| --- | --- | --- | --- |
| Source | `task-mw01aed1-qwunu2` | 15 inventoried files, actual suite logs, identity/diff review and delivery preparation | Accepted with the history/environment clarifications below. |
| Admission | `task-mw01aiok-fut1xh` → `task-mw026hrs-ivmqrb` | 94 inventoried files, retained probes, report and command recipes | Accepted with scope/path/context corrections. |
| Handoff | `task-mw01an01-ykiuvm` → `task-mw024ayy-cb5udw` | Seven inventoried files, registry vectors and package/Q/operations/compatibility preparation | Accepted with command/isolation/operation corrections. |

The initial admission and handoff attempts reached the 60-turn request limit.
Their companion error mislabeled that as an authentication failure; the actual
stop reason/stderr and successful continuations establish the cause. Both
stopped attempts remain failed in the ledger. The same Grok sessions resumed
with bounded finish-only briefs; no incomplete job is credited as complete.
Sanitized job receipts are in [review/grok-jobs.json](review/grok-jobs.json).

Each inventory was checked for exact bytes/SHA-256 and complete file membership.
Source and admission command records were checked against the actual log files.
No runtime/domain source, catalog, dependency lock, branch or tag was changed.
The only tracked edit is the requested CHECKPOINTS.md prefix; the new plan and
execution directory are the new reviewable scope. Existing untracked evidence
and historical checkpoints remain preserved.

## Review corrections

1. The shared collector example omitted `--attachment-plan` and used scalar
   `$ARGV`. The corrected template uses exact arrays, retains nonzero producer
   exits and finalizes only the actual staging path reported by collection.
2. The local tag precedes packaging; later MW-71 admits release publication.
   This removes the draft's apparent tag/packaging dependency cycle.
3. Independent Q2 must hide all source/scratch/credential roots, clear ambient
   settings, use only admitted dependency imports and retain isolation proofs.
4. A missing-run control does not satisfy the required missing-payload control.
   The corrected control deletes an inventoried payload in a scratch store.
   Incomplete-profile rejection must occur after coherent collection/finalization
   and catalog linkage, not merely fail byte integrity. Complete-profile catalog
   verification is also required on the successful Q result.
5. Client controls require `validate --host ... --port ...`. A concrete guarded
   replacement/rollback script must exist before production operations. Do not
   mutate an admitted BUILD.json/archive to record publication or deployment.
6. The admission recipe's `/var/tmp` proposal is outside this session's writable
   roots. Its `wsl2/locks` layout emits invalid bootstrap paths. Use a task-owned
   repository root preserving `distribution/reference-node-wsl2-26.04/...`.
   The actual bootstrap validator rejected the draft and accepted that correction;
   see [review/lock-layout-check.json](review/lock-layout-check.json).
7. Four per-family builds/D audits and a new Ubuntu 24.04 host are outside the
   active WSL2-only campaign. The base lock remains a structural regression
   control; build/install the selected WSL2 local/Gate pair only.
8. Remote model operations through an admitted Mirrors CLI are allowed from
   this coordinator. The prohibition concerns local Apalache/TLC, not remote
   clients after admission. Reconcile obsolete registry paths before final freeze.
9. Historical no-commit-at-execution checkpoint text stays historical. Its
   presence in a later commit is not a reason to rewrite it. New entries and
   maintained status updates own current continuation.

These corrections are documented templates/exit gates, not newly executed
collector, sandbox, negative-control, service or publication acceptance.

## Capability and provenance limits

Both locks passed Codex's independent read-only structural validation with
unchanged lock bytes. Existing verifier hash `5a64a5bd…` is a bootstrap
observation; no current-source C3 build is claimed. The retained reproducible
[admission checker](review/admission-check.py) and its
[output](review/admission-check.json) also confirm ext4 repository/tmpfs default
temporary storage, missing strace and absent recorded Batteries carrier.

Grok's subprocess context permitted local socket probes; Codex's independent
AF_INET/AF_UNIX probes returned EPERM. These are context-specific observations,
not interchangeable host qualification. The original namespace probe failed.
The actual final producer context must be admitted afresh. Log 090's timestamp
was supplied by its writer and receives no freshness/chronology credit. Its
advisory content does not replace final artifact/tool observations.

Registry review checked 20 command vectors against actual prefixes and lengths,
covering every selected required command and all 16 tiers. Corrected Bash blocks
passed syntax checks only. See [review/recipe-checks.json](review/recipe-checks.json).
No final non-model aggregate/full build, package construction, D audit, live
remote/Windows run, Q campaign, public or production operation ran in this batch.

## Next execution gate

MW-12 must resolve the product/version/catalog split, choose/acquire exact
companion refs, reconcile registry bindings and maintained status, then run
approved final local gates and freeze. MW-53 additionally needs the exact
`73130433…` Batteries carrier, admitted strace/namespace capabilities and final
candidate packages. MW-54 needs fresh endpoint/TLS/backend/client/Windows inputs.
The accepted preparation leaves these obligations explicitly pending.
