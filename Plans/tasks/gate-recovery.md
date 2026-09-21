# Gate recovery and aggregate resource accounting tasks

Date: 2026-09-21

Roadmap: [Mirror Framework improvement plan](../mirror-framework-improvements.md)

Coordination: [Mirror Framework task assignments](../mirror-framework-tasks.md)

Assigned role: `general-purpose-gpt`

Implementation state: **queued; no product implementation or host recovery is authorized**

## Scope and claim boundary

This work package develops roadmap tasks G1-G5 for MirrorGate. It does not run
recovery against host resources, create or modify host cgroups, publish a
capability, or authorize deployment. G1's design and model may be drafted in
Wave 0. All Python, TypeScript, policy, backend, and host-facing changes remain
queued behind the dependencies and file assignments below.

The first recovery capability terminates and reclaims abandoned Gate-owned work.
It does **not** adopt, resume, or transfer an abandoned session. A record that
cannot establish exclusive ownership remains ambiguous and unreclaimed. A later
recovery receipt is separate evidence; it cannot turn an incomplete evaluation
or unconfirmed cleanup into a pass.

Aggregate-limit claims are similarly conditional. The existing Bubblewrap
profile remains available with its accurately described per-process and host-UID
limits. Aggregate process, memory, or CPU enforcement may be claimed only for a
new, explicitly selected cgroup-v2 capability backed by operator delegation and
real-backend observations. If a caller requires that capability and admission
cannot establish it, Gate must reject the run before untrusted code starts.

## Initial source-grounded inventory

This inventory is an input to B1, not a permanent implementation pin. Recheck it
before coding.

- Planning baseline is Mirrors `eb5cd001b990e6ac5e9b1e9b1c5a17ffb85e25fc` and
  MirrorGate `173075d318e4be926570a1378fc0aa36a1294f89`; the inspected MirrorGate
  worktree was on `main` with no reported local changes.
- `supervisor/mirrorgate/orchestration.py` owns the connection-local
  `OrchestrationController` and `SessionState`. `_cleanup_operation()` joins one
  authoritative in-memory cleanup operation, and `close()` starts cleanup for
  all sessions when a control connection exits normally.
- `supervisor/mirrorgate/preparation.py` owns `BackendOwner`, `BackendSession`,
  `ControlBackend`, the physical resource census, worker reservation, and bounded
  cleanup. `BackendOwner` currently binds connection ID, principal UID, and
  session ID, but there is no boot identity, durable controller identity, or
  restart ledger. `ControlBackend` allocates private roots with `mkdtemp()` and
  keeps active sessions only in memory.
- `supervisor/mirrorgate/artifacts.py` owns `FrozenStore` and owner-bound
  `FrozenLease` objects. Leases and pending removals are in memory. Safe snapshot
  traversal is descriptor-relative, but restart recovery has no durable record
  proving which snapshot directory belongs to which Gate instance.
- `supervisor/mirrorgate/sandbox.py` owns `GateSession` and `SandboxProcess`.
  Normal teardown kills the process group. The trusted child sets
  `PR_SET_PDEATHSIG`, and Bubblewrap uses `--die-with-parent` and a PID namespace;
  these mechanisms do not supply restart-durable cleanup evidence. No cgroup
  membership is established.
- `supervisor/mirrorgate/control_server.py` distinguishes one owned stdio
  connection from attached Unix clients and closes a controller in `finally`.
  `supervisor/mirrorgate/cli.py` currently exposes only administrative `run` and
  `control` commands. Recovery must remain an operator interface, never an
  author/agent tool.
- `ControlBackend.capability_reports()` currently reports
  `quota.aggregate-v1` as unavailable with `enforcedScope: "none"`. The strict
  `ControlLimits` schema in `control_policy.py` contains per-command/per-session
  bounds but no cgroup memory, PID, or CPU-bandwidth fields.
- `docs/sandbox/supervisor-design.md` and
  `docs/sandbox/linux-bubblewrap.md` explicitly state that abrupt controller
  termination can retain snapshots, that no restart-durable ledger or garbage
  collector exists, and that current rlimits are not aggregate cgroup quotas.
- `integrations/mirrorecma/src/receipt.ts` keeps evaluation and cleanup outcomes
  distinct; `workflow.ts` prevents a model pass with unconfirmed cleanup from
  becoming an overall pass. Recovery evidence must preserve this rule rather
  than rewriting the original evaluation receipt.
- MirrorGate currently contains no `.tla` or `.cfg` recovery model. G1 therefore
  introduces the formal-model location and its executable check before lifecycle
  implementation begins.

## Assignment and sequencing summary

| ID | Assigned owner | Milestone / wave | Depends on | State |
| --- | --- | --- | --- | --- |
| G1 | `general-purpose-gpt` | M0/M4, Wave 0 | B1 inventory; draft E1/C2 identity vocabulary | Draft design allowed; implementation queued |
| G2 | `general-purpose-gpt` | M4, Wave 2 | G1 approved model/interface; B2 and B3 | Queued |
| G3 | `general-purpose-gpt` | M4, Wave 3 | G2; B3 | Queued |
| G4 | `general-purpose-gpt` | M4, Wave 3 | G1; B2 cgroup profile decision; B3 | Queued |
| G5 | `general-purpose-gpt` | M4, Wave 4 | G2-G4; C2 and E1 contracts; applicable C3/E3 producers | Queued |

Tasks sharing `preparation.py`, `cli.py`, capability reporting, tests, or docs run
sequentially under B3, with a clean handoff and one active file owner. No task
below authorizes unrelated refactoring, commits, pushes, package publication, or
production recovery.

## G1 - Specify the recovery lifecycle and formal safety model

**Stable ID:** `G1`

**Assigned owner:** `general-purpose-gpt`

**State:** design/model drafting allowed; all runtime changes queued

**Dependencies:** refreshed B1 source baseline and the draft C2/E1 identity
vocabulary. G1 owns recovery semantics; it references rather than defines the
catalog and durable-evidence schemas.

### Intended responsibility

Repository: MirrorGate. Exact intended files:

- new `docs/sandbox/recovery-design.md` for the lifecycle, operator interface,
  ownership rules, durability assumptions, failure taxonomy, and claim limits;
- `docs/sandbox/supervisor-design.md`, `docs/sandbox/linux-bubblewrap.md`, and
  `README.md` only to link the approved design and preserve current limitations;
- new `specs/recovery/Recovery.tla` and `specs/recovery/Recovery.cfg` for the
  abstract machine;
- new `scripts/check-recovery-model.sh` as the pinned, repeatable model gate.

G1 does not change the control protocol, controller, backend, journal, CLI,
receipts, or cgroup behavior.

### Deliverables

1. Define the recovery unit as one operator-selected state root containing a
   versioned journal and Gate-owned resource claims. Separate controller
   instance, connection, session, run, resource, host boot, and recovery-attempt
   identities. A PID is an observation, never ownership proof by itself.
2. Specify transitions for allocation intent, durable ownership, active use,
   cleanup intent, reclaimed, retained-by-policy, ambiguous, and failed cleanup.
   Include preparation, snapshot freeze, build, authorization, worker launch,
   replay/worker use, and cleanup interruption points.
3. Define one exclusive live owner or recoverer per state root. A restarted
   controller may terminate and reclaim abandoned work after validation; it may
   not resume/adopt it or accept operations under its old authority.
4. Define resource-specific validation. Filesystem reclamation requires a pinned
   state root plus recorded path component and object identity; process action
   requires boot identity and non-PID ownership evidence; cgroup action requires
   an operator-delegated Gate subtree and an exact recorded cgroup identity.
   Symlinks, changed objects, unknown versions, foreign UIDs/roots, and conflicting
   live owners become `ambiguous`, not cleanup targets.
5. Define monotonic evidence: later observations may move `unconfirmed` to a
   separately recorded recovered/failed/ambiguous cleanup result, but cannot
   erase earlier failures, rewrite an evaluation result, or infer success from
   absence alone. Intentional retained source views remain retained unless their
   own policy explicitly marks them recoverable.
6. Model safety properties: at most one recovery owner; no resource outside the
   validated ownership set is acted upon; no cross-session reclamation; reclaimed
   is terminal for that resource identity; evidence is monotonic; and no
   incomplete/unconfirmed run becomes a pass. Model retry/interruption as
   idempotent transitions.
7. State liveness only under named assumptions: durable readable records,
   exclusive lock acquisition, stable resource identity, eventual OS operation
   response, and recurring retry. The model must not claim eventual cleanup for
   ambiguous ownership, unavailable hosts, or permanently failing kernels/filesystems.
8. Decide whether recovery is initially an offline administrative command
   (recommended) or requires a versioned control capability. It must never be an
   agent-facing operation.

### Acceptance evidence and commands

- Review maps every roadmap recovery acceptance criterion to a model invariant,
  an OS/backend test obligation, or an explicit non-guarantee.
- Counterexamples exist for intentionally weakened exclusive-owner,
  cross-session, and monotonic-evidence guards; the corrected bounded model has
  no counterexample in the documented scope.
- The model gate is executable as:

  ```bash
  bash scripts/check-recovery-model.sh
  ```

- Documentation path/link and whitespace checks pass:

  ```bash
  git diff --check
  ```

### Handoff and stop conditions

G1 hands G2 a versioned record state machine and durability contract; G3 a
resource-validation/reclamation table; G4 the cgroup ownership boundary; and G5
the recovery-result vocabulary. Stop before runtime work if record identity,
exclusive ownership, retained-resource policy, or model/OS evidence separation
is unresolved.

## G2 - Implement the durable journal and ownership identity

**Stable ID:** `G2`

**Assigned owner:** `general-purpose-gpt`

**State:** queued

**Dependencies:** approved G1 design/model, B2 durability/profile decisions, and
B3's exclusive file assignment.

### Intended responsibility

Repository: MirrorGate. Exact intended files:

- new `supervisor/mirrorgate/recovery_journal.py` for the closed record codec,
  atomic persistence, checksums/sequences, state-root lock, boot/controller
  identity, and bounded inspection;
- `supervisor/mirrorgate/preparation.py` for journal hooks at backend/session,
  snapshot, build, reservation, and cleanup ownership boundaries;
- `supervisor/mirrorgate/artifacts.py` only for durable snapshot claim/release
  hooks defined by G1, without weakening descriptor-relative traversal;
- `supervisor/mirrorgate/cli.py` only for trusted state-root configuration needed
  by `control`; G3 owns the later inspect/reclaim subcommands;
- new `tests/test_recovery_journal.py` plus focused additions to
  `tests/test_control_backend.py`.

### Deliverables

1. A closed `mirrorgate.recovery-journal/v1` codec (final name subject to G1
   review) with bounded files, records, strings, and resource counts. Reject
   duplicate IDs, unknown fields, unsupported versions, invalid transitions, and
   records outside the selected state root.
2. An operator-created, private state root validated as an absolute,
   non-symlinked directory owned by the serving UID with the documented mode.
   Acquire an exclusive nonblocking owner/recoverer lock before allocation.
3. Per-instance boot ID, random controller incarnation, principal UID, session
   ID, resource kind, immutable resource identity, lifecycle state, and monotonic
   sequence. Record process PID/start-time/cgroup observations only as the G1
   ownership contract permits; never treat PID alone as authority.
4. Crash-consistent updates using a documented same-filesystem atomic commit
   sequence and explicit file/directory sync points. On a torn, truncated,
   checksum-invalid, or future-version record, quarantine/report the record
   without guessing its last state or touching referenced resources.
5. Write ownership intent before externally visible allocation and commit the
   resulting identity before use. Cleanup records intent before action and a
   terminal observation afterward. Redact commands, environment, credentials,
   private model data, and arbitrary exception text from the journal.
6. Concurrent controllers/recoverers fail closed. Changed host boot identity
   invalidates process observations but does not by itself authorize or forbid a
   resource action; G1's resource-specific proof decides.

### Acceptance evidence and commands

- Unit tests cover every persistence cut point, partial write, missing sync,
  truncation, checksum failure, unknown version, duplicate record, stale boot ID,
  reused PID fixture, foreign state-root owner/mode, and two concurrent
  recoverers. No rejected case calls a reclaimer.
- Backend tests show that every owned allocation either has a durable prior
  intent or is rolled back before it can be returned to a caller.
- Focused and full gates:

  ```bash
  python -m unittest discover -s tests -p 'test_recovery_journal.py'
  python -m unittest discover -s tests -p 'test_control_backend.py'
  bash scripts/test.sh
  ```

### Handoff and stop conditions

G2 hands G3 a tested journal reader, exclusive recovery lease, typed resource
claims, and terminal append API. It hands G5 the versioned record identity only;
G5 does not reinterpret journal internals as evidence. Stop if the selected
filesystem cannot meet the documented atomicity/durability assumptions, if two
installations can share a state root without distinct identities, or if any
allocation can escape the write-ahead ownership boundary.

## G3 - Add ownership-validated inspection and reclamation

**Stable ID:** `G3`

**Assigned owner:** `general-purpose-gpt`

**State:** queued

**Dependencies:** G2 journal API and B3's sequential handoff for shared backend
and CLI files.

### Intended responsibility

Repository: MirrorGate. Exact intended files:

- new `supervisor/mirrorgate/recovery.py` for read-only inspection, validation,
  reclamation planning, execution, retry, and bounded results;
- `supervisor/mirrorgate/cli.py` for trusted `recovery inspect` and explicit
  `recovery reclaim` commands using a selected state root;
- `supervisor/mirrorgate/preparation.py` only where live backend startup must
  refuse or invoke the approved recovery policy before new admission;
- new `tests/test_recovery.py` and `tests/test_recovery_acceptance.py` for
  adversarial and abrupt-termination cases;
- the G1 recovery design and Linux backend guide for the implemented scope and
  manual-intervention rules.

### Deliverables

1. `inspect` is read-only and emits a bounded, stable report of live, abandoned,
   retained, reclaimed, failed, and ambiguous claims without exposing private
   paths or credentials in public output. `reclaim` requires the exclusive
   recovery lease and operates only on a validated plan.
2. Filesystem actions walk beneath a pinned operator state root using
   descriptor-relative, no-follow checks and compare the recorded object
   identity immediately before action. Never accept absolute journal paths,
   `..`, symlinks, mount aliases, replacement directories, or merely matching
   names as proof.
3. Process actions require the complete G1 identity proof. A same-number PID with
   a different boot/start/cgroup identity is unrelated. If the existing
   non-cgroup backend cannot prove descendant ownership after restart, recovery
   reports the process ambiguous/unconfirmed instead of sending a signal.
4. Reclamation seals the abandoned session, terminates validated active resources
   within an independent budget, removes validated ephemeral endpoints,
   snapshots, and session directories, preserves policy-retained source views,
   and persists each observation. Re-running after interruption is safe and does
   not duplicate or broaden authority.
5. Startup behavior is explicit: fail closed, inspect-only, or recover-before-
   admit according to the operator policy selected in B2. No mode silently
   adopts old sessions or infers successful cleanup from an empty process list.
6. Fault-injection harnesses terminate the controller at preparation, freezing,
   build, authorization, worker launch, replay/worker use, and cleanup boundaries
   under a disposable state root. They verify actual resource census before and
   after recovery and retain ambiguous resources for manual intervention.

### Acceptance evidence and commands

- Adversarial tests cover foreign directories, symlink swaps, inode replacement,
  stale journals, changed boot ID, PID reuse, concurrent sessions, concurrent
  recoverers, interrupted recovery, and intentionally retained output. No test
  permits a foreign process signal or foreign path removal.
- Abrupt-termination tests run only in newly created disposable roots and use
  test-owned child processes. They never scan or clean broad `/tmp`, the
  repository, a home directory, or a production cgroup.
- Real Bubblewrap evidence distinguishes confirmed process exit, confirmed path
  removal, retained-by-policy output, and unconfirmed/ambiguous cleanup:

  ```bash
  python -m unittest discover -s tests -p 'test_recovery.py'
  MIRRORGATE_REQUIRE_SANDBOX=1 python -m unittest discover -s tests -p 'test_recovery_acceptance.py'
  bash scripts/test.sh
  ```

### Handoff and stop conditions

G3 hands G5 versioned recovery results and real-backend fixtures; Q1 receives the
abrupt-controller scenario. Stop and require manual intervention whenever exact
ownership cannot be revalidated, a live owner holds the state root, a record is
unsupported/corrupt, or bounded termination/removal cannot be observed.

## G4 - Add optional cgroup-v2 aggregate admission and accounting

**Stable ID:** `G4`

**Assigned owner:** `general-purpose-gpt`

**State:** queued

**Dependencies:** G1 ownership contract, B2's selected Linux/delegation profile,
and B3's exclusive file assignment. G4 can proceed alongside G3 after those
contracts settle.

### Intended responsibility

Repository: MirrorGate. Exact intended files:

- new `supervisor/mirrorgate/cgroup.py` for operator-delegation validation,
  Gate-owned child creation, controller files, membership, counters, kill, and
  removal;
- `supervisor/mirrorgate/control_policy.py` and policy fixtures for a new
  versioned aggregate-limit schema; do not add fields silently to the closed v1
  schema;
- `supervisor/mirrorgate/sandbox.py` for a trusted pre-exec membership barrier so
  no submitted instruction runs before the process is inside its admitted
  cgroup;
- `supervisor/mirrorgate/preparation.py` for per-session cgroup ownership,
  admission, census, journal binding, and teardown;
- new `tests/test_cgroup_backend.py` and `tests/test_cgroup_acceptance.py`, plus
  focused policy/isolation test updates;
- `docs/sandbox/linux-bubblewrap.md` for exact semantics and limitations.

### Deliverables

1. Accept only an operator-supplied cgroup-v2 subtree already delegated to the
   serving UID. Validate its ownership, filesystem type, enabled controllers,
   path identity, and absence of symlink traversal. Gate never runs `sudo`, edits
   system service configuration, or searches for a writable host cgroup.
2. Create one recorded Gate-owned descendant subtree per admitted session (and
   narrower children only if the design requires them). Set `pids.max`,
   `memory.max`, and `cpu.max` before joining the trusted launcher. Define CPU as
   aggregate bandwidth/period plus observed `cpu.stat`, not as a false cumulative
   CPU-time guarantee. Preserve existing rlimits as separate controls.
3. Ensure the trusted launch helper joins the cgroup before executing Bubblewrap
   or submitted code. Descendants inherit membership, the sandbox cannot mount or
   write cgroupfs, and attempted session/process-group escape cannot leave the
   Gate subtree.
4. Record admission settings and post-run observations from `pids.current`,
   `pids.events`, `memory.current`/supported peak and event files, `cpu.stat`, and
   `cgroup.events`. Distinguish configured limits, observed throttling/OOM/PID
   denial, and confirmed emptiness; missing counter support is explicit.
5. Teardown uses the validated cgroup identity, bounded termination (`cgroup.kill`
   only when supported and owned, otherwise a documented safe fallback), observes
   an empty population, then removes the subtree. Journal integration makes
   interrupted teardown retryable without widening ownership.
6. Capability discovery reports aggregate quotas available only after a live
   delegation probe. A policy/session requiring aggregate limits fails admission
   before the SUT starts when the controller, delegation, or required kernel file
   is unavailable. The existing non-cgroup profile continues to report
   `quota.aggregate-v1` unavailable.

### Acceptance evidence and commands

- Unit tests use a fake hierarchy only for parser/state/error coverage; they are
  never cited as enforcement evidence.
- Real tests create a uniquely named child below an explicitly supplied
  disposable delegated parent, then clean only that child. They exercise nested
  process/thread workloads, collective PID denial, collective memory enforcement,
  CPU throttling with observed counter deltas, descendant escape attempts,
  abrupt controller death, and idempotent cleanup.
- Required real-backend command (exact parent supplied by the operator/test
  harness):

  ```bash
  python -m unittest discover -s tests -p 'test_cgroup_backend.py'
  MIRRORGATE_REQUIRE_SANDBOX=1 MIRRORGATE_REQUIRE_CGROUP=1 MIRRORGATE_CGROUP_PARENT=/operator/delegated/disposable-parent python -m unittest discover -s tests -p 'test_cgroup_acceptance.py'
  bash scripts/test.sh
  ```

  A missing/invalid delegated parent fails the required acceptance command; it is
  not a pass or aggregate-limit evidence. Ordinary `scripts/test.sh` may report
  the optional tier unavailable until the qualification environment supplies it.

### Handoff and stop conditions

G4 hands G5 observed capability/admission/accounting records and Q1 a disposable
aggregate-workload scenario. Stop before advertising support if pre-exec
membership is racy, the delegated subtree can be escaped or shared ambiguously,
the required controllers/counters are unavailable, or only mocked evidence ran.
Disk/filesystem quotas, host-wide denial-of-service containment, and platforms
other than the selected Linux cgroup-v2 profile remain outside the claim.

## G5 - Export recovery evidence and backend capabilities

**Stable ID:** `G5`

**Assigned owner:** `general-purpose-gpt`

**State:** queued

**Dependencies:** accepted G2-G4 producers, C2 capability contract, E1 evidence
contract, and their applicable validated schema implementations. G5 runs only
after the shared-file handoffs in B3.

### Intended responsibility

Repository: MirrorGate, with adapter handoffs to the owning C2/E1 tasks. Exact
intended MirrorGate files:

- `supervisor/mirrorgate/preparation.py` capability reporting and recovery/cgroup
  evidence adapters after G4 releases the file;
- `supervisor/mirrorgate/cli.py` stable machine-readable inspection output after
  G3 releases the file;
- new `supervisor/mirrorgate/recovery_receipt.py` for a closed, bounded trusted
  recovery receipt and allowlisted public/operator summary;
- `integrations/mirrorecma/src/receipt.ts` and `workflow.ts` only if E1 requires
  an additive reference; the v1 evaluation receipt and public projection remain
  unchanged unless separately versioned;
- `sdk/compatibility.json`, `docs/compatibility.md`, `docs/tasks.md`, and focused
  Python/TypeScript tests for observed capability/evidence status.

C2 continues to own catalog capability semantics and tested combinations. E1
continues to own evidence bundle identity, retention, completeness, and offline
verification. G5 supplies versioned Gate records/adapters and does not duplicate
either schema.

### Deliverables

1. A closed recovery receipt links journal/controller/session/resource identities,
   recovery attempt, triggering condition, validated ownership observations,
   per-resource action/result, remaining/ambiguous resources, cgroup settings and
   observed counters when applicable, and final cleanup classification. Bound and
   redact every field.
2. Preserve chronology and outcome separation. The original evaluation receipt
   remains failed/incomplete/unconfirmed as recorded. The recovery receipt may
   establish later physical reclamation, but cannot synthesize a model result,
   hide a prior cleanup failure, or upgrade the original run to passed.
3. Export actual backend capability observations through the C2 adapter: platform,
   backend ID, cgroup-v2 delegation/controller availability, enforced scope,
   supported limit semantics, recovery durability profile, and evidence reference.
   Source implementation, configured policy, probed availability, exercised local
   acceptance, installed support, CI, and publication remain distinct states.
4. Export recovery/cgroup run artifacts through E1, including required/optional
   tier status, command/exit result, exact component revisions, journal/receipt
   schema versions, hashes, and cleanup evidence. Private paths, PIDs, model data,
   exception text, and operator topology do not enter public projections.
5. Diagnostics explain: no durable state root; active owner; clean; abandoned and
   recoverable; ambiguous/manual intervention; unsupported journal version;
   missing cgroup delegation/controller; aggregate limits not requested; and
   required aggregate admission refused. Read-only diagnostics never reclaim.
6. Compatibility documentation states the exact accepted profile and limitations,
   including no session adoption/resumption and no aggregate guarantee on the
   legacy Bubblewrap-only profile.

### Acceptance evidence and commands

- Schema fixtures include success, partial failure, ambiguous ownership, corrupt
  journal refusal, unsupported cgroup admission, and confirmed cgroup cleanup.
  Malformed/oversized/private-canary fixtures fail or redact as specified.
- Capability tests cannot report aggregate/recovery support from configuration or
  source presence alone. Removing delegation or real evidence downgrades the
  observed state and makes a required capability fail admission.
- Receipt tests prove that later recovery does not mutate the original evaluation
  status and that a public summary contains only its allowlist.
- Focused and full gates:

  ```bash
  python -m unittest discover -s tests -p 'test_recovery_receipt.py'
  python -m unittest discover -s tests -p 'test_control_acceptance.py'
  npm test
  bash scripts/test.sh
  ```

- The C2 catalog validator and E1 offline evidence verifier accept the exported
  fixtures at their exact revisions. Q1 reruns the real abrupt-recovery and
  delegated-cgroup tiers; historical or mocked fixtures do not qualify them.

### Handoff and stop conditions

G5 hands C2 immutable capability/evidence references, E1 complete private and
allowlisted public records, and Q1 the exact supported profile and commands. Stop
if C2/E1 identities are unresolved, if a public projection leaks a canary or host
topology, if recovery evidence can overwrite evaluation evidence, or if required
real-backend observations are unavailable.

## Cross-task acceptance matrix

| Roadmap requirement | Owning task | Required evidence |
| --- | --- | --- |
| Single-owner, no cross-session recovery | G1/G2 | TLA+ invariant; exclusive-lock and concurrent-recoverer tests |
| Torn/truncated/versioned durable records | G2 | persistence fault matrix with zero reclamation on invalid input |
| Safe, idempotent reclamation | G3 | adversarial identity tests and abrupt-death runs in disposable roots |
| No unrelated process/path touched | G1/G3 | formal ownership invariant plus PID reuse, symlink, inode, and concurrent-session tests |
| Monotonic cleanup evidence; no false pass | G1/G5 | model invariant and original-plus-recovery receipt fixtures |
| Aggregate descendant enforcement | G4 | real delegated cgroup nested-workload observations |
| Required unsupported guarantee rejects admission | G4/G5 | capability and policy negative tests before SUT launch |
| Durable catalog/diagnostic evidence | G5 through C2/E1 | catalog adapter validation and offline bundle verification |
| Existing owned/attached compatibility | G3-G5 | full `scripts/test.sh` and unchanged v1/v2 lifecycle fixtures unless explicitly versioned |

## Open decisions for B2/G1 review

1. Select the initial durable state-root filesystem and minimum sync/locking
   assumptions. Network filesystems and weak/unknown rename durability should be
   unsupported until separately evidenced.
2. Select the initial operator delegation mechanism and supported cgroup-v2
   controller set. The recommended boundary is an already delegated subtree;
   automatic privileged systemd/host provisioning is outside G4.
3. Decide whether non-cgroup process observations can ever satisfy the G1
   post-crash kill proof. The safe default is inspection plus ambiguity unless an
   exact non-PID ownership witness is implemented and tested.
4. Confirm offline administrative `recovery inspect/reclaim` as the first
   interface. Adding recovery to control v1/v2 would require a separate protocol
   version/capability and cross-SDK conformance work.
5. Define retention and access for terminal journals and recovery receipts through
   E1, including when compaction is allowed without destroying chronology.
6. Fix aggregate CPU semantics and names: cgroup CPU bandwidth/throttling is not
   cumulative CPU-time enforcement. Do not expose one as the other.
7. Decide how committed/prepared authoring source views are classified. Current
   code intentionally retains them as operator output; recovery should preserve
   that default unless a reviewed policy adds explicit ephemeral ownership.
8. Bind multiple installed Gate versions to distinct controller/state-root
   identities or define a reviewed migration. Unknown journal versions must not
   be reclaimed by best effort.

Until these decisions and the required real-backend evidence exist, the honest
status remains: crash recovery and aggregate cgroup guarantees are proposed and
implementation is queued.
