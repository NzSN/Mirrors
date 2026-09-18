# Async protocol and resource ownership

The async server model is in [`specs/MirrorProtocol.tla`](../specs/MirrorProtocol.tla),
with `AsyncInit`, `AsyncNext`, `AsyncInv`, and `AsyncFairSpec`. It covers both
`register_validate_async` and `register_trace_gen_async`, query, await (including
timeout), cancellation, cross-connection access, and owner-session teardown.

The original single-session protocol is retained as `SyncInit`, `SyncNext`, and
`SyncSpec`. `Spec` combines the two framed projections. Use `AsyncSpec` for async
resource verification; the old synchronous phase is not used to restrict the
server's multiplexed job operations. Completion of a synchronous flow on an
async connection is represented by `AsyncClose(c, "sync_done")`.

## What is modeled

| Model state | Implementation responsibility |
| --- | --- |
| `connections[c]`: open, closing, closed | `Shell.Mirror.runAsync` and its finally-owned session drain |
| `jobs[j].owner`, `stored`, kind, phase and outcome | Process-wide `Shell.Jobs.Store`; only the submitting session evicts its jobs |
| Queued/acquired/body/unwinding/settled stages | Dedicated job task, acquisition boundaries, runner finally blocks |
| Slot acquisition and release counters | Semaphore permit owned by `jobThread`, including after cancellation or eviction |
| Owned spec, run-directory and child resource tokens | Materialized source directory, temporary outputs, child process and its streams/handles |
| Cancellation flag, installed hook, stop request | Atomic token registration/cancellation; late registrations observe cancellation |
| `waiting[c]` and `AsyncLivePromises` | An awaiting connection borrows the job's promise until it answers or closes |
| `last` | Diagnostic request/reply snapshot, not a guard or ownership authority |

One request/reply is abstracted as an atomic operation, except long-polling,
owner draining and worker acquisition/cleanup, whose race boundaries are separate
steps. Large result bytes, socket framing, certificates, native allocator
internals and filesystem contents are erased. A child token is released only
when collection/reaping completes; requesting its termination does not release it.
Borrowed model files are excluded from owned cleanup. Trace files belong to the
run directory and are read before that directory is released.

Completed results remain intentionally retained while their owner connection
stays open. This is the existing result-retention policy, not a global memory
bound. Job IDs are never reused within a model run. The finite job-ID domain
bounds explored histories, not the production counter.

## Safety and eventual release

`Inv` includes `AsyncInv`, so the combined specification also checks async
resource safety. `AsyncInv` conjoins:

- `AsyncTypeOK`: valid connection/job/resource states and bounded release counters.
- `AsyncResourceAccounting`: live resources equal acquisitions minus releases;
  borrowed specs are never acquired for cleanup; every held slot is accounted for.
- `AsyncNoOrphanedResources`: live body resources have an executing/unwinding task;
  a settled task has no resources or slot, and an executing body retains its slot.
- `AsyncClosedOwnersHaveNoEntries`: a closed session has no retained table entries.
- `AsyncTerminalResultsStable`: cancellation/completion races cannot replace the
  first terminal outcome with a later worker result.
- `AsyncLateCancellationSafe`: a child hook installed after cancellation has a
  stop request; it cannot silently miss the cancellation.
- `AsyncCapacityOK`: live-job and physical worker-slot bounds hold independently.
- `AsyncWaitersOwned`: only an open connection retains an await reference.
- `AsyncNoLeaksAtQuiescence`: after every connection closes and every task settles,
  no job entry, promise reference, worker permit or owned body resource remains.

An invariant alone cannot force a hung process to exit. `AsyncFairSpec` adds
explicit progress assumptions for worker scheduling, process/body completion,
unwinding, owner draining and ready await replies. Under those assumptions:

- `AsyncResourcesReleased`: every terminal job eventually has a settled task,
  no owned body resources and no worker permit.
- `AsyncClosingEventuallyClean`: a closing owner eventually has no retained job
  entries, outstanding promise references, body resources or permits.

These are **conditional model guarantees**. Successful OS resource release,
eventual collection after child termination, and a progressing runtime are
assumptions. A failed filesystem deletion, process crash, or injected runner that
never returns is not proved leak-free. The implementation attempts all registered
cancellation callbacks even if one throws and retains a worker permit until its
body exits; a logical cancellation result does not claim physical quiescence.
A permanently open owner can retain arbitrarily many terminal results under the
current policy. Connection-pool/global resources and unrelated application memory
are outside this job-resource model.

## Runtime corrections motivated by the model

The negative actions are deliberately excluded from `Next` and must violate the
corresponding invariants when enabled by the checker:

| Negative control | Counterexample | Runtime correction |
| --- | --- | --- |
| `AsyncLeakOnExit` | Session closes while its entries remain stored | Run the owned-job drain in `runAsync`'s `finally`, including transport exceptions and terminal synchronous flows |
| `AsyncEarlySlotRelease` | Cancelled but executing worker loses its slot | Release permits in the job task's `finally`, never in the logical terminal transition |
| `AsyncMissLateHook` | A late child hook misses prior cancellation | Serialize cancellation and hook registration; run late hooks immediately, compose registrations and retire released-resource hooks |
| `AsyncLeakPartialAcquisition` | Directory creation fails after acquiring an owned spec | Establish the spec finalizer before acquiring the run directory; unwind scopes independently |

The worker also captures its original cancellation token in the same atomic
operation that starts the job; eviction cannot substitute a new uncancelled
token. Task-launch failure removes the inserted entry. Cancellation/owner cleanup
attempts all jobs/callbacks before reporting an error. The child runner retires
its cancellation hook after collection and kills/waits on collection failure.

The corresponding safety obligations are now proved in Lean for arbitrary finite
populations and histories. See [Lean resource proofs](async-resource-lean-proofs.md)
for the theorem map and the proved primitives executed by the runtime. Global
composition is proved for the Lean model; whole-shell IO refinement and eventual
cleanup are not newly proved. The existing `Core.Protocol.step_refines_tla`
theorem remains a tag-level theorem, distinct from resource ownership.

## Reproduce the checks

```sh
python3 tools/check-async-protocol.py --require-tools --output /tmp/async-model-results
lake build jobstore_spec apalache_cli_spec async_spec
.lake/build/bin/jobstore_spec
APALACHE_MC=/absolute/path/to/apalache-mc .lake/build/bin/apalache_cli_spec
APALACHE_MC=/absolute/path/to/apalache-mc .lake/build/bin/async_spec
```

The model checker uses installed `tlc`, or `TLA2TOOLS_JAR` with Java. Its documented
local fallback is `~/.local/lib/tla2tools.jar`. It extracts the unchanged standard
`Apalache.tla` from `APALACHE_JAR`, or the installed `apalache-mc` distribution.
It downloads nothing. Without tools, normal checks explicitly skip;
`--require-tools` fails instead. `lake test` runs the `--quick` model profile and
the runtime suites; the command above additionally runs full two-job safety and
one-owner/two-job liveness. Standalone TLC configurations are
[full safety](../specs/MirrorProtocolAsync.cfg) and
[cross-connection liveness](../specs/MirrorProtocolAsyncLiveness.cfg).

The default safety model has two connections, two lifetime job IDs, live capacity
one and one physical slot. Connection dispatch is modeled independently of the
production `--jobs` coupling: allowing extra peers conservatively adds competitors
for job operations. Global connection-worker allocation is outside this model. Temporal checks separately cover two connections/one
job and one connection/two jobs. Each leak negative uses one connection/one job.
A separate negative removes fairness and must produce a temporal counterexample.
`AsyncView` excludes only `last`: neither guards nor properties depend on that
diagnostic snapshot. Every resource, cancellation, wait and ownership field stays
in the checked state.

## Local verification, 2026-09-18

[Machine-readable evidence](async-protocol-resource-evidence.json) records the
source identities and checked profiles. Full async safety explored 1,581,785
distinct states. Liveness passed for 5,305 states with two connections/one job
and 78,627 states with one connection/two jobs. All four resource mutants and
the no-fairness variant produced their expected counterexamples. The original
synchronous projection passed (57 states), and existing fault/witness wrappers
passed SANY semantic checks. Apalache type checking also passed.

The corrected runtime passed job-store regressions, injected partial-acquisition
failures, real Apalache and TCP/mTLS async scenarios, stdio smoke and CLI tests.
The regression suite reproduced six failures before the runtime corrections.
These are focused checks; the full `lake test` aggregate and deployment of these
fixes to Windows were not performed in this task. Raw logs are temporary; the
JSON summary is retained here.
