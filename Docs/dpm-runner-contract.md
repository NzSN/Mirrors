# DPM runner, reduction and installed CLI contract

Implementation contract frozen 2026-10-13 before F3–F5 code changes. The
execution authorization is the user's instruction to execute the six stages.

## Ownership

`Core.Dpm` owns inert candidates, actor-chain admission, preemption counting and
deterministic reduction ordering. `Codec.Dpm` owns bounded strict JSON. The
Lean `mirrors-dpm` entry point and packaged host tools own artifact admission,
processes, deadlines, retained evidence and installation. Application runners
use the existing C++/Node-worker/Rust-thread SDK sessions; applications supply
their actual factories, checkpoint placement and observations.

## Project and authority

`mirrors.dpm-project/v2` is an explicitly finite admitted candidate catalog.
Each candidate binds its input rank, actor subset, complete actor-local chains,
schedule, matching oracle and independently retained oracle provenance. This
first reducer searches that catalog, not every syntactically possible schedule.
The caller supplies the trusted SHA-256 of the project. Artifact digests are
checked against that trusted project before a runner or application is started.
Paths are bounded regular nonsymlink files; relative paths stay within the
project root. Runtime executables are explicitly admitted. Executable v1 projects
refuse with a reprepare instruction; historical SDK receipts remain diagnostic inputs.

The closed command forms are `{kind: "native", executable: PATH, args: [ARG]}`
and `{kind: "python-isolated", executable: PATH, script: PATH, args: [ARG]}`.
Each argument is exactly `{artifact: PATH}` or `{literal: STRING}`. Executable,
script and artifact arguments must belong to the selected artifact closure;
literals, including empty strings, remain individual argv entries, with no shell.
Executable, script and artifact paths remain nonempty. The host inserts
`-I -S -B` before a Python script. This profile supports standalone Python
adapters using the trusted platform standard library. Packaged Python helpers
execute exact hash-verified source bytes, without directory insertion or cached
bytecode lookup. The interpreter hash does not pin the OS-owned standard library,
extension modules, dynamic loader or shared libraries; those are trusted runtime
prerequisites. Artifact stability during execution and non-detaching runners
are requirements, not hostile-process confinement guarantees.

The nullable `explorerIdentity` binds the separately selected SDK explorer's
three identity digests. SDK exploration refuses when it is absent and checks
returned schedules against it. A separate C++ explorer may have different
implementation and mapping hashes from the replay runner. The catalog and
every artifact are rechecked after execution. Expected states never initialize
the SUT or become observations.

## Runner exchange

The runner is an application-owned executable, or executable plus application
module, called with fixed arguments `--request FILE --response FILE`.
`mirrors.dpm-runner-request/v1` supports `describe`, `materialize`, `replay` and
`explore`. Each request binds a unique request ID, project digest and candidate
ID. `mirrors.dpm-runner-response/v1` echoes those bindings. Materialization
returns exact artifact identities, never a standalone `valid: true` claim.
Replay returns the actual SDK `mirrors.scheduled-comparison/v1` receipt. The
host independently checks terminal comparison, execution schedule/identity,
fresh execution IDs, complete receipt retention and confirmed cleanup.
Exit zero alone never establishes a model match. A shared profile-aware execution
validator checks complete actor declarations, alternating permit/arrival pairs,
actor-local permit origins, schedule step indices, consecutive observations and
actual cleanup attempts. Matches require all intervals and observations, completed
execution, true completion flags, and consistent successful client/terminal facts.
Early comparison prefixes preserve C++ completed/incomplete versus ECMA/Rust
cancelled disposal; a final-interval mismatch may have a passed execution.
An exact-terminal initial-observation mismatch may have zero intervals and keeps
`checkpoint: null`, with initial oracle/client/observation correspondence checked.
Counter delta normalization still requires an actual `write` interval. Client
action names follow admitted model actions, including aliases such as
`finish` mapping to checkpoint `$done`.
Checked oracle correspondence maps model states to observations, including
model-inert initialization steps. Bounded typed Lean comparison validates states,
rejects duplicate ITF map keys and checks terminal/client observations against the
selected oracle. SDK exploration uses the same execution checks without model
comparison authority.

Runner evidence has both per-request `outputBytes` and operation-wide
`totalOutputBytes` acceptance limits. Accounting includes every retained file:
request/schedule copies, raw SDK receipts, envelopes, logs, temporary helper
inputs/outputs, receipt copies and final reports. Duplicate representations count
separately. Existing project/oracle inputs outside the output tree are excluded.
Each request gets a new process group and new output directory. Logs are drained
through capped streams; nested SDKs inherit those streams. Directory accounting
runs during execution and after owned processes stop and streams drain; symlinks
and special files refuse. Host writes are charged before publication. The host
reserves 65536 bytes plus 1024 bytes per admitted attempt for final reporting,
adds the actual serialized baseline fingerprint size before further acquisition,
and reserves worst-case request capacity for each trial plus a fresh best replay.
Insufficient reserve cannot establish successful reduction.

These limits govern retained-evidence admission, not OS disk or memory quotas.
Direct child writes can overshoot polling. On failure, raw evidence stays intact;
a bounded reserved refusal report records measured retention and overshoot,
even if direct writes have already exceeded the operation limit. Overflow exits
2, stops further acquisition, and never earns match/minimality credit. Cleanup
status remains distinct from the primary failure. Deadlines terminate only owned
descendants; timeout or missing receipts do not imply successful SDK cleanup. Incomplete cleanup stops
reduction. Raw receipts and primary failures are retained without rewriting.

## Reduction

Every candidate retains each selected actor's whole original checkpoint chain,
including exactly one final `$done`. Removing an actor changes its factory
declaration as well as its schedule. Input rank is an explicit finite-domain
complexity. A preemption is a switch away from an unfinished actor; switching
after `$done` does not count. Cost is lexicographic actor count, input rank,
preemption count, then step count; candidate ID breaks ties deterministically.

The baseline must reproduce twice with fresh execution IDs, the same declared
failure signature and confirmed cleanup. Candidates require matching admitted
model oracles and fresh actual comparison. Signature profiles are explicit:
exact model terminal payloads, or a named application-specific normalization
whose implementation is part of the trusted artifact closure. Trace indices
alone do not identify a failure. Ambiguous attribution refuses.

Reports distinguish matched, same failure, different failure, invalid candidate,
oracle unavailable, timeout, malformed/stale evidence and incomplete cleanup.
Attempt/time/evidence exhaustion yields `best_observed`. Exhaustive conclusive
coverage of the smaller admitted catalog permits `minimal_in_admitted_catalog`;
no global-minimum or all-interleavings claim follows.

## Installed commands

`doctor`, `replay`, `explore`, `reduce` and `report` consume prebuilt admitted
artifacts. `report` is read-only and reuses the packaged timeline. Replay exits
0 only for a completed match with confirmed cleanup, 1 for an actual mismatch,
and 2 for refusal/incomplete/infrastructure/cleanup failure. Reduction exits 0
when its bounded reduction operation succeeds; that is reproduction of a
failure, not conformance success. Exploration completion and model comparison
are separate fields. Output directories must be new; inputs are never replaced.

Installation stages a relocatable verified tree, checks it before atomic
activation, and refuses overwrite of an existing destination. Node is a
prerequisite only for Node runners. Python is an explicit host/timeline runtime
prerequisite. Native SDK build prerequisites and runtime prerequisites remain
distinct. Installed gates hide source trees and isolate Linux networking.

## F5 experimental scope

The first wrapper profile is C++ controlled nonrecursive mutexes and bounded
FIFO queues on real threads. It has its own session and resource receipts.
Actors submit pending operations and park without internal locks held. A
coordinator grants enabled operations, records actual ownership/results and
keeps observers quiescent. Fixed replay rejects disabled choices; exploration
branches only over enabled choices. All unfinished actors waiting on declared
resources with no enabled operation is a controlled deadlock. Uncontrolled
callback hangs are timeouts. Cancellation retains the primary finding and
requires actual joins before cleanup confirmation. A held mutex is never
silently released to repair a schedule.

Hooks belong to one worker/execution; resource IDs resolve only within that
execution. Wrong-owner release, recursive acquire, live foreign hook calls and
resource-kind mismatches refuse. Hooks cannot be copied; borrowing a hook beyond
its worker callback is outside the valid C++ object lifetime. Queue sends
and receives preserve bounded FIFO/exact-once semantics. The profile does not
extend the ordinary one-transition/one-checkpoint mapping automatically.

## Acceptance

F3: real input/actor/preemption reduction in all three declared languages,
fresh best-candidate replay, wrong failure, stale identity, oracle tamper,
timeout and cleanup refusal controls. F4: source-hidden offline installed
replay/explore/reduce/report in each language, relocation, runtime and artifact
tamper controls. F5: real mutex contention and queue backpressure, deterministic
replay, enabled-set exploration, resource misuse, deadlock, cancellation,
semantic mutations and confirmed joins. Existing generated/wire bytes and
frozen historical evidence remain stable. New results get a separate record.


## Finite F5 model-comparison extension

The raw SDK `mirrors.controlled-sync-replay/v1` and exploration schemas retain
`modelComparison:false`. The separate
`mirrors.controlled-sync-model-comparison/v1` result can record a real remote
model verdict for `mirrors.controlled-mutex-fifo-model/v1` only after complete
native receipt admission, identity binding and confirmed cleanup. See the
[finite mapping contract](dpm-controlled-model-comparison.md). This does not
extend arbitrary C++ receipts, the general SDK explorer or F5 weak-memory scope.
