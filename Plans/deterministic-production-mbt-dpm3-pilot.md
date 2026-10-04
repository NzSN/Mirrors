# DPM-3 bounded native pilot

Date: 2026-10-04

Status: **accepted for this four-case pilot** after explicit transfer/staging
approval. The [master plan](deterministic-production-mbt-dpm2-dpm5.md) remains the
stage authority. [Final retained acceptance](dpm2-dpm5-qualified-20261004/README.md)
contains eight matched native replays, two production mutation mismatches, four
native failure controls, three pre-acquisition mapping refusals and four bounded
`MBTSafety` validations. The installed controller repeated these checks with
source checkouts hidden and networking isolated.

## Selected cases

The bridge has two coordinator operation actors, `arm` and `write`, each executing
exactly one real native operation. A mapping binds each role to native t1 or t2.
For stable owner-only hits both roles use the owner thread sequentially; overlap
cases use different native threads. Physical thread reuse is allowed only after
the prior operation's observed CallDone, and each operation keeps a distinct
identity. This preserves the initial coordinator's one-operation-per-actor rule
without conflating its IPC proxy actors with physical native thread identities.

| Case | Native operations and order | Required observed behavior |
| --- | --- | --- |
| stable-t1 | t1 Arm(A1), then t1 Write(A1,bad,allowed,span=1) | publication, hardware target observations, a stable accepted snapshot, hit/release and operation completion |
| stable-t2 | t2 Arm(A1), then t2 Write(A1,bad,allowed,span=1) | symmetric stable snapshot/write behavior |
| overlap-t1 | t1 Arm(A1) pauses at PublishOdd; t2 Write(A1,bad,allowed,span=1) completes; t1 finishes | write overlaps publication; a silent pre-hardware write is retained as its actual outcome |
| overlap-t2 | symmetric t2 Arm / t1 Write overlap | symmetric declared publication/write window |

Each starts from the native worker's actual reset state. There are two controlled
native actors, one watch address and one-word stores. Stable cases obey the
existing owner-only filter; overlap cases exercise the other writer before
hardware publication. The filter is never disabled to force a hit. The canonical model still
uses its four-slot/two-actor/three-address domain and Budget=10, but this pilot
claims only the four named schedules and reached actions. Other patterns,
partial hardware coverage, additional/unbounded operation reuse, new-thread lifecycle,
terminal actions, reentrant sinks, arbitrary OS failures and full v3 coverage
are excluded from this pilot.

The existing WriteSentry production/performance release position is not changed.
In particular, a functional scheduling adapter does not close unrelated native
performance or hosted-CI gates.

## Hook transport and operation lifetime

The application adapter launches a freshly staged native worker. Its production
`self_watch.cpp`, `veh.cpp`, assembly writer and phase hook mechanism remain the
selected existing code. A small wrapper supplies process creation identity,
actual t1/t2 thread identifiers and an explicit Quit acknowledgement after the
existing native runtime destructor has joined its owned actors. The wrapper
changes controller metadata only, not trap-path synchronization.

MirrorCPP's portable worker functions act as command proxies for the two native
operations. A permit causes a recorded Begin/Advance command. The actual native
reply supplies the reached phase and SUT state; the proxy parks at that actual
phase. Expected oracle state is never passed to the worker. The native operation
retains its real Windows stack while its atomic phase gate is parked.

At CallDone, the generated application callback performs the CallDone interval
and a declared `$done` proxy-completion interval. The latter sends no native
command and leaves the model observation unchanged: it is explicit stuttering,
not an additional model action. The callback returns one observation for the
one model transition. Every other model callback maps to one interval.

Both the native command and model input must match the sealed mapping before
advancing. Physical actor IDs may differ between fresh processes but must remain
stable within a process and distinct for t1/t2. Process identity, creation time,
logical actor, operation instance and source/build hashes remain linked.

## Independent oracle

Native probing is used only to discover/record the requested phase schedule and
concrete command inputs. Its SUT states are diagnostic, never expected states.
A generated `WriteSentryPhaseRun` wrapper fixes that schedule as `Plan` over the
unchanged canonical `WriteSentry` / `WriteSentryMBT` actions. Fresh Apalache traces
must be obtained through the Mirrors CLI and owned Windows oracle. Capture the
full source closure, wrapper, backend identity and original returned artifacts.

The replay then starts a new native process and compares independently observed
states through the compiler-generated C++ port and actual Mirrors comparison.
Repeated replay checks the same schedule/inputs and normalized native states;
it does not require OS thread IDs to repeat across processes.

## Required controls and cleanup

- Build `duplicate-sink-call` and `skip-hit-release` only in new staged copies of
  production source. On the stable watched-write case, both must produce real
  server `step_mismatch` from changed callback/lease state, not merely a fake
  adapter exception or portable-model mutation.
- Reject unknown mappings, unsupported extra-operation traces, unknown actors and
  identity changes before native acquisition where possible. An unexpected real
  phase is a scheduling failure and is not relabelled as a production mismatch.
- Cancel a paused run, terminate the native peer as a test-owned failure, and
  retain primary failure plus separate proxy-thread/native-process cleanup.
- Teardown releases/cancels native waits using the existing runtime path, requires
  the Quit acknowledgement and zero process exit, and reaps the owned transport.
  Nonzero exit or missing acknowledgement remains explicit cleanup failure.
- Retain every native request/reply, actual process/thread identities, model
  comparison result, repeated-run projection and ownership/cleanup result.

A successful four-case pilot plus these controls qualifies only this bridge
profile. Historical WriteSentry traces outside the profile are listed as
unsupported; they are not silently counted as exercised coverage.
