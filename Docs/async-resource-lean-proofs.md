# Lean proofs for async resource safety

[Core/AsyncResources.lean](../Core/AsyncResources.lean) defines the executable
per-job resource and cancellation machines.
[Core/AsyncOwnership.lean](../Core/AsyncOwnership.lean) proves their global
ownership composition. Building `mirror` imports both modules through the job
store, so a failed proof prevents building the executable.

The theorems quantify over arbitrary finite job, connection and slot populations
and arbitrary finite accepted histories. They have no TLC exploration bound.
They prove safety; eventual scheduling, process termination and OS cleanup remain
separate progress obligations.

## The proved properties

| TLA+ obligation | Lean definition / theorem |
| --- | --- |
| Resource types and accounting | `Lease`, fixed-size `ResourceMap`, `lease_accounting`, `job_resource_accounting` |
| No orphaned job resources | `Job.Valid.resourcesOwned`, `Job.Valid.slotActive`, `step_preserves`, `reachable_valid` |
| No duplicate release of an incarnation | `released_rejects_release`, `released_has_no_further_release` |
| Closed owners retain no entries | `World.Valid.storedOwner`, `closed_owner_has_no_entries` |
| Stable terminal outcomes | `terminal_stable`, `world_terminal_stable` |
| Late cancellation is observed | `Job.Valid.lateCancellation`, `Cancellation.late_registration_emits_cleanup` |
| Unique cancellation tickets and once-only claims | `Cancellation.reachable_ticket_unique`, `repeated_cancellation_claims_nothing`, `retired_hook_not_claimed` |
| Admission and physical slot bounds | `admission_bounded`, `reachable_live_capacity`, `active_jobs_bounded` |
| Await references have open owners | `World.Valid.waitOwned` |
| Leak-free quiescence | `reachable_world_quiescence_leak_free`, `quiescent_accounting_balanced` |

`initial_valid` / `world_initial_valid` prove the initial states satisfy the
invariants. `step_preserves` / `world_step_preserves` prove preservation for every
allowed operation. Induction over `Reachable` then yields the invariant for every
reachable state, without a trace-length bound.

The global quiescence theorem states that when all connections are closed and
all admitted worker bodies are settled, there are no occupied permits, borrowed
await references, retained job entries or live owned body resources. The companion
accounting theorem states that cumulative acquisitions equal releases there.

Cancellation requests and terminal outcome publication are separate operations:
completion can win a cancellation race, but a published outcome never changes.
Job-table eviction does not erase the worker's resource state or release its
permit. That state survives with the original token until the worker settles.

## Sequential child processes

Validation performs type checking and then model checking in separate Apalache
processes. A child lease can therefore be reacquired after release only by
advancing `childGeneration`. Acquisitions and releases include that generation
counter; it is an unbounded `Nat`. Releasing twice without a new acquisition is
rejected. Spec-directory, run-directory and worker-slot leases cannot be reused
within one job.

The runtime ledger uses a fixed-size resource record instead of accumulating
functional-update closures. Reachability certificates are `Prop` fields and are
erased by Lean compilation; they do not retain prior jobs, resources or cleanup
closures in the running server.

The Lean machine is a resource/ownership abstraction of the
[TLA+ model](async-protocol-resource-model.md), not a verified translation of its
AST. Its worker stages combine several TLA+ acquisition/unwinding stages, and
its child generations expose sequential invocations that the TLA+ runner action
abstracts. The global model's finite ID domains are universally quantified;
fresh IDs are not reused within a history.

## Connection to the running server

The production job store executes proved code:

- Every accepted job gets a `CancelToken.newTracked` containing a `CheckedJob`.
  Its state carries a kernel proof of reachability. Updates use `CheckedJob.step`;
  there is no whole-post-state invariant validator standing in for preservation.
- The worker acknowledges its semaphore acquisition with `start` and settles only
  after its body scopes have released their resources. Missing acknowledgements
  cannot produce a settled ledger. A successful verdict with live resources is
  rejected and becomes an infrastructure failure.
- The default Apalache runner acknowledges owned spec/run-directory acquisitions
  and releases. Each child acknowledges acquisition, cancellation-hook installation,
  and collection/release. Borrowed specs receive no owned lease.
- Cancellation and child-hook installation share one mutex. The shell executes the
  proved registry's returned cleanup claims outside that lock. Late registrations
  run immediately; retirement drops references to released resources.
- The store uses `admissionAllowed`, `lookupEntry` and `dropEntry` directly.
  `lookup_dropped_absent` proves the selected ID disappears;
  `eviction_preserves_other` proves other IDs retain their prior lookup result.

Standalone cancellation tokens remain available for callers outside a job/worker
context; they use the proved registry but have no job-resource ledger. Standard
server submissions always use tracked tokens.

The **global `World` is a verified composition model**, not a shadow table kept by
the server. The runtime executes the per-job, cancellation, admission and eviction
primitives above. The correspondence of session owner lists, mutex scheduling and
actual IO effects to every `World.Step` has not been proved. The existing
`Core.Protocol.step_refines_tla` theorem concerns its original tag-level relation;
it is not that missing whole-shell refinement theorem.

## Boundary of the guarantee

Acquisition/release events acknowledge effects reported by the shell. Lean does
not prove that an OS call deleted a directory, reaped a process or closed a native
handle. The existing filesystem cleanup helpers and native/runtime APIs remain
trusted boundaries. Arbitrary injected runners and cleanup callback bodies are
not verified by storing their callbacks in a proved registry. Distinct callback
tickets do not establish that their payloads refer to distinct OS resources.

Successful cleanup and eventual process/worker progress are still assumptions
for physical leak freedom. Lean liveness proofs have not been added; the existing
TLC fairness checks remain separate. A permanently open owner may intentionally
retain terminal results under the current protocol policy.

## Validation and proof audit

```sh
lake build async_resource_spec jobstore_spec apalache_cli_spec async_spec mirror
.lake/build/bin/async_resource_spec
.lake/build/bin/jobstore_spec
APALACHE_MC=/absolute/path/to/apalache-mc .lake/build/bin/apalache_cli_spec
APALACHE_MC=/absolute/path/to/apalache-mc .lake/build/bin/async_spec
```

[AsyncResourceProofSpec](../tools/AsyncResourceProofSpec.lean) contains kernel-checked
non-vacuity examples: sequential children work, while early settlement, early
successful publication, borrowed-spec acquisition and duplicate releases fail.
It audits the principal theorem dependencies against Lean's standard `propext`,
`Classical.choice` and `Quot.sound` only. No new axioms, `sorry` or native decision
oracle are used. Proof-module warnings are errors. The proof target and runtime
guard scenarios are wired into the normal Lake build/test inventory.

## Local acceptance, 2026-09-18

[Evidence and source hashes](async-resource-lean-evidence.json) record the final
working-tree snapshot. Kernel compilation, the axiom audit and non-vacuity
examples passed. Runtime guard tests, tracked partial-acquisition cleanup, live
Apalache, TCP/mTLS async jobs, stdio replay and the CLI regressions also passed.

The guards detected missed release acknowledgements during integration: mutable
local flags captured by `finally` retained their original values. The shell now
uses explicit references across finalizer closures. The acquisition test runner
also now records unexpected scenario exceptions as failures. The final live runs
passed after both corrections. The full `lake test` aggregate and Windows
deployment were not performed; raw logs remain temporary, while this summary is
retained in the repository.

The [concurrent server E2E](async-server-resource-e2e.md) checks the effectful mTLS
validation path through repeated completion, cancellation, and disconnect batches,
including process, temporary directory, descriptor, job eviction, and RSS checks.
