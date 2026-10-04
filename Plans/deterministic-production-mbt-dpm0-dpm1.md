# DPM-0 / DPM-1: cooperative scheduling for MirrorCPP

Date: 2026-10-03

Status (2026-10-04): **DPM-0 specified and DPM-1 implemented; local acceptance passed**. This plan covers the
reviewed interface and a portable concurrent fixture. DPM-2 generated binding
integration, DPM-3 WriteSentry integration, DPM-4 exploration and DPM-5 capability
publication remain separate delivery slices.

## Refreshed baseline

The September 30 [proposal](../Proposals/deterministic-production-mbt.md) is
historical. MirrorCPP now includes the earlier codec changes at `aa906a5`.
WriteSentry `62b62298c5c764dc63cde10968c2555a79df1d3c` already has a native phase
worker, `WRITESENTRY_MBT_PHASES` hooks and a recorded `native-runtime-phase/v3`
qualification. Its portable `ProtocolPort` is only one of its adapters. This
work does not rerun or extend that native qualification. The reusable interface
is still missing from MirrorCPP; it must accommodate a later adapter rather
than replace the private worker opportunistically.

## Ownership and initial profile

MirrorCPP owns a `mirrorcpp.cooperative-checkpoints/v1` scheduler module.
One controller permits at most one declared actor to execute between
checkpoints. Actor functions execute once on real `std::thread` workers and
retain their stacks across permits. An actor has one declared operation instance
per execution. A random execution identifier and process-local generation distinguish reused
logical actor names. The adapter declares actors, operations and checkpoint names, supplies a
factory receiving the recorded inputs, provides a quiescent observer, and owns
its application resources through captured owning values.

The compiler, wire protocol and StateComputer contract do not change. DPM-1
records implementation observations without claiming an oracle comparison.
No model checker or native Windows workload is needed for this portable slice.

## Execution state machine

- Admission validates the complete schedule, exact profile and expected model,
  mapping and implementation identity labels, identifiers, actor membership,
  completion placement, bounds and input size **before** invoking the factory.
- The factory builds the SUT and supplies exactly one worker per declared actor.
  Workers first park at an internal start barrier, before application code.
- A step selects one parked actor and names its expected next checkpoint or
  terminal completion. The coordinator records a permit and releases that actor.
- A hook records the actual checkpoint and parks its actor. The coordinator
  compares that arrival with the selected step before taking an observation.
  Unexpected arrival, premature return, worker failure and an unregistered hook
  caller are distinct failures. There is no automatic schedule repair.
- Only the controller invokes the observer, while all declared actors are parked
  or finished. The scheduler mutex keeps cancellation unwinding from racing an
  observation. The observer must not call scheduler hooks or wait for an actor.
- Completion requires every scheduled checkpoint and every actor's terminal
  step. All started actors must be joined and teardown must succeed for a pass.

Invariants: at most one actor has a permit; actor identities are unique; hooks
are bound to the actual owned worker thread; no actor runs before admission;
observations do not borrow expected model state; the first primary failure is
preserved independently of cleanup. Event order is controller acceptance order,
not nondeterministic initial registration order.

## Replay and evidence contract

A strict, versioned schedule artifact contains the profile, model semantic digest,
mapping SHA-256 and instrumented implementation SHA-256 labels, JSON inputs and
ordered `(actor, checkpoint)` steps. Identity labels are supplied by the trusted
adapter and must match the replay artifact exactly. DPM-1 does not attest that a
running executable has those bytes; build/artifact attestation belongs to its
acceptance harness and DPM-5. Actual inputs are delivered directly from the
recorded schedule to the factory.

The mapping declares actor/operation identities and checkpoint vocabulary. The
initial profile accepts only deterministic inputs and cooperative actors; it
has no clock/random/OS-fault choice interception. Adapters must reject workloads
that need those controls until an explicit extension supplies them.

Receipts retain the full schedule and declarations, fresh generation, accepted
permits, actual arrivals, quiescent observations, primary outcome, cleanup
attempts and any remaining actors. Replay equivalence compares schedule,
accepted events and observations, excluding the fresh execution identifier and process-local generation.
It establishes reproducibility at declared checkpoints, not instruction-level
or weak-memory coverage. No schedule coverage percentage is reported.

## Cancellation and cleanup ownership

Execution and cleanup waits have separate steady-clock budgets. Cancellation
wakes coordinator-owned waits; parked actors unwind without receiving another
permit. Arbitrary application code cannot be preempted safely in-process.

The returned execution handle retains ownership of every thread, including after
cleanup times out. It reports remaining actors and permits an explicit cleanup
retry. It never detaches a thread or reports an unjoined thread as reclaimed.
Destroying a handle cancels and joins its remaining threads and can block if an
adapter violates cooperative termination. Factory, observer, teardown and thread
TLS destructors are trusted prompt-returning callbacks. The budgets bound
coordinator waits, not arbitrary callback execution or OS thread destruction.
A hard termination guarantee requires an isolated-process owner; that extension
is not part of DPM-1. Tests of incomplete cleanup retain an owning release gate,
then unblock and join the actor before leaving the test.

An observer failure, actor exception, timeout or schedule divergence is the
primary outcome. Teardown failure is a separate cleanup outcome and never erases
that primary failure. No timeout is called a deadlock without dependency evidence.

## WriteSentry compatibility decision

The portable hook uses a mutex/condition variable and is **not** suitable for
VEH handlers or a suspended-target region. The existing WriteSentry hook contract
requires preallocated POD/atomic publication and forbids heap, locks, logging and
kernel calls on the trap path. A later adapter needs an explicit atomic-handshake
transport into the same controller semantics, plus its own native acceptance.
The private phase worker provides a real second adapter to evaluate for DPM-3;
it is not silently counted as acceptance of this new library interface.

The first integration investigation should map the actual registry publication
and protected snapshot/lease events against the current production model, using
its existing multi-slot correspondence. It must preserve admission/lease/sequence
ordering, safe observation points, partial hardware outcomes and ownership.
No new hooks or production mutations are introduced in this slice.

## DPM-1 acceptance

1. A two-worker split read/write counter runs real operations with stacks retained
   across checkpoints. Serial and overlapping schedules produce different actual
   results; replay each schedule in repeated fresh executions.
2. The serialized schedule round-trips through a strict reader; bad profile,
   identity, duplicate/unknown actors, malformed fields and invalid completion
   order reject before the factory runs.
3. Negative cases exercise unexpected checkpoints, premature completion,
   uncontrolled hook callers, actor/observer exceptions, cancellation before and
   during execution, execution timeout, cleanup timeout and teardown failure.
4. Receipts preserve actual arrivals, primary failure, remaining actors and cleanup
   retries. All tests join their actors. CTest gives the suite an outer timeout.
5. Link the new implementation into the existing library, export its thread
   dependency and exercise it through the installed public header/package smoke.
   This is a packaging regression check, not DPM-5 capability publication.
6. Run focused scheduler tests, existing local unit tests, repeated fixture replay
   and suitable sanitizer checks. Report unavailable checks explicitly.

## Execution record

- Proposal and current MirrorCPP/WriteSentry contracts inspected.
- DPM-0 decisions above resolve permit, replay identity, observation and cleanup
  semantics for the first profile. The implementation and acceptance below complete
  this authorized slice.

## Accepted implementation and evidence — 2026-10-04

MirrorCPP adds `include/mirrorcpp/schedule.hpp` and `src/schedule.cpp`, the
`scheduled_counter` fixture, strict schedule serialization, receipts and public
regression tests. CMake exports the thread dependency; the installed consumer
smoke runs the public scheduler. [Usage and lifecycle contract](../../MirrorCPP/docs/deterministic-scheduling.md).

- Warning-as-error full MirrorCPP build passed with the cached dependencies.
- **615 assertions / 18 focused scheduler cases** passed. These include 80 fresh
  in-process schedule runs, malformed admission, actual fixture mutation
  observations, cancellation phases, a real lock-contention timeout, retained
  incomplete cleanup/retry, observer reentry, teardown failure and lossy-JSON rejection.
- **202/202 local unit tests** passed, including the existing transport/TLS,
  registry, protocol, model-interface and golden-corpus tests.
- The strict standalone gate passed under `PYTHONOPTIMIZE=1`: **17 fresh-process
  executions**, two schedule shapes, and two input assignments. Recorded actual
  observations and accepted event sequences match across repeated executions.
  Its registered CTest entry also passed.
- The installed CMake package consumer compiled, linked and ran the scheduler.
  This is the DPM-1 packaging regression, not DPM-5 capability publication.
- Address/Leak/UndefinedBehavior sanitizers passed the same 17-process fixture
  gate. ThreadSanitizer passed all **615 assertions / 18 scheduler cases**.
  The sandbox prevented LeakSanitizer inspection; normal test-process execution
  succeeded. ThreadSanitizer initially failed before test execution with an
  address-map collision; its final suite passed using per-process
  `setarch x86_64 -R`, with no global host configuration change.
- The observer-hook reentry regression was observed timing out before the guard,
  then passed with an explicit observation failure and confirmed actor cleanup.

[Retained local acceptance](dpm1-evidence-20261004/acceptance.json) records exact
source and executable hashes, replay receipts, test logs and the exercised scope.
No model checker ran, no production WriteSentry source changed, and no commit,
package publication or new M5 qualification is claimed for this work.

## Remaining delivery slices

DPM-2 must connect serialized generated callbacks to scheduler intervals and
retain real comparison failures. DPM-3 must adapt the existing native WriteSentry
phase machinery through its safe atomic seam and revalidate model correspondence.
DPM-4 adds bounded exploration only after replay integration is accepted. DPM-5
covers installed capability publication with accurate platform/profile claims.
