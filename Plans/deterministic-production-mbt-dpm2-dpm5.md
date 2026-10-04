# DPM-2 through DPM-5: detailed execution plan

Date: 2026-10-04

Status: **DPM-2 through DPM-5 accepted for the declared profiles**.
Final [approved acceptance](dpm2-dpm5-qualified-20261004/README.md) closes the earlier remote/native gaps.
The user requested detailed plans and step-by-step execution for all remaining
DPM stages. This document defines their dependencies, implementation seams and
acceptance gates before implementation starts. Progress and retained evidence
are appended by stage; an implementation alone does not satisfy an exit gate.

## Baseline, ownership and constraints

- Mirrors `eb096fd` and MirrorCPP `aa906a5` have the completed, uncommitted
  [DPM-0/DPM-1 implementation](deterministic-production-mbt-dpm0-dpm1.md).
  Preserve that implementation and its historical evidence while extending it.
- WriteSentry `62b62298c5c764dc63cde10968c2555a79df1d3c` also has substantial
  existing working-tree changes. Its native phase worker, source hooks and v3
  model correspondence are inspected working-tree inputs, not clean-HEAD
  qualification. Freeze hashes for the selected files and do not revert or
  repurpose unrelated production-readiness/performance work.
- MirrorCPP owns reusable coordination, binding-lifecycle integration and finite
  schedule enumeration. Mirrors owns public compiler fixtures and their emitted
  bindings, real comparison gates, plans and retained evidence. A WriteSentry
  adapter owns native command/checkpoint correspondence and its native worker.
- Generated output is produced by `model_interface_gen` and checked read-only.
  No hand-edited generated bindings, copied oracle observations, relaxed codecs
  or synthesized passing verdicts are permitted.
- No local Apalache/TLC. Fresh model checks/captures use the Mirrors CLI against
  the owned native Windows oracle, with fresh identity observations. Offline
  replay is explicitly distinguished from fresh model checking.
- Windows writes remain under
  `C:\Users\ayden\Desktop\Workspace\MirrorsRemote`. Native build inputs are
  copied to a new owned stage; diagnostic mutations affect only those copies.
- Retain exact source/model/mapping/compiler/build identities, commands, actual
  results, cleanup and negative controls. Preserve earlier evidence unchanged.
- These stages do not authorize changing the selected M5 qualification, creating
  a new OS isolation backend or publishing an unqualified general concurrency
  claim. Git commits and external registry releases are not part of this plan.

## DPM-2 — Generated-binding replay integration

### Contract and architecture

Extend the existing scheduler with a controller-owned incremental execution:
`start_schedule` performs static admission, factory construction and the initial
park barrier; `advance` releases exactly the next recorded actor/interval;
`finish` requires every recorded interval and actor completion before cleanup.
The existing `run_schedule` is implemented through the same machinery and retains
DPM-1 behavior. The plan remains fixed and fully admitted before application work.
An out-of-order generated callback cannot change the admitted schedule.

A reusable binding-session owner connects generated initialization, actions and
disposal to this execution. It retains the execution handle and receipts across
primary comparison errors and cleanup failures. Negotiated selection still
constructs bindings only after matched admission. Multiple initializations must
finish/clean up the prior execution before starting another; no live actor handle
may be silently discarded. The generated binding's existing codec, poison and
reentrancy rules remain authoritative.

The application port maps a typed action to a checked actor/checkpoint interval
and reads real observations. The integration must not accept expected oracle
state as an implementation initializer. Comparison status and scheduler/cleanup
status are retained independently; scheduling success is not conformance.

### Ordered work

1. **D2.1 — Incremental scheduler.** Refactor the run loop into admitted start,
   one-step advance and terminal finish. Retain one-permit, actor-generation,
   quiescence and cleanup invariants. Test wrong step/order, premature finish,
   calls after terminal state, cancellation and retained incomplete cleanup.
2. **D2.2 — Binding owner.** Add the small session/lifecycle bridge and classified
   errors through the existing LocalBinding/compiled selection seams. Preserve
   primary comparison failure if disposal also fails. Keep an independent
   cleanup receipt and dispose exactly once.
3. **D2.3 — Compiler-owned concurrent fixture.** Add a small split-counter TLA+
   model and reviewed interface: initialization plus read/write/completion steps
   with actor input. Generate a C++ binding through the existing compiler. Use
   actual worker-local saved values and actual shared state as observations.
4. **D2.4 — Real comparison.** Run serial and overlapping schedules through the
   generated port and actual Mirrors comparison. Retain both success and a
   deliberate real-SUT mutation that produces server `step_mismatch`.
5. **D2.5 — Negative integration.** Reject identity/mapping mismatch before SUT
   acquisition; exercise malformed input, unexpected checkpoint, poisoned/reentrant
   binding behavior, early server termination, cancellation and teardown failure.
   Verify factories, permits and cleanup counts rather than only exit codes.
6. **D2.6 — Regression and freeze.** Run DPM-1 regressions and affected existing
   client/compiler gates. Retain fresh receipts and source/build hashes, then
   update the stage status before proceeding to DPM-3.

### Exit gate

A generated callback advances a live worker stack by one declared interval,
actual observations pass a real Mirrors replay, an actual SUT mutation produces
`step_mismatch`, rejection precedes acquisition where required, and every
termination path has separate primary and cleanup evidence. No wire or generated
binding lifecycle rule is weakened.

## DPM-3 — Native WriteSentry adapter and reviewed correspondence

### Contract and architecture

Use WriteSentry's existing phase worker as the native hook transport. MirrorCPP
selects and records logical actor permits; the worker supplies the native
preallocated atomic handshake, actual production execution and native cleanup.
The portable condition-variable hook must never execute in VEH/suspended-target
code. A bridge must report the worker's actual phase, not the requested phase.

Select a bounded pilot from the current production model/correspondence: stable
publication followed by a write, and a write overlapping publication/retirement
where supported, with symmetric actor directions. The final selection must name
its exact commands/actions, inputs, slots, bounds and exclusions before execution.
Do not claim the whole existing v3 profile merely because selected cases pass.

Mapping records bind logical actors to native worker identities and command
sequences. If a native operation spans several model actions, its real native
stack and operation identity must persist. Multi-operation actor reuse requires
an explicit mapping/session rule rather than pretending distinct native calls
are the same operation. Existing generated native observations and model checks
are reused where applicable, with actual adapter identity validation before
spawning the SUT.

### Ordered work

1. **D3.1 — Freeze pilot inputs.** Inventory/hash current native worker, production
   sources, hooks, generated interface, selected model closure and existing
   correspondence. Document the concrete pilot cases and unsupported cases.
2. **D3.2 — Bridge and identities.** Implement the native adapter over the existing
   worker command/reply seam. Validate phase/action/actor/operation identity;
   retain real native replies and reject unsupported or unrealizable scheduling
   requests without claiming a production defect. Separate process ownership
   from scheduler ownership; reuse the existing transport close/reap contract.
3. **D3.3 — Owned native build.** Stage source/dependency inputs in a new
   MirrorsRemote directory, hash before/after copying, build the native worker
   and required bridge artifacts, and retain actual compiler/flags/binary hashes.
   Do not edit the existing WriteSentry build scripts merely to bypass their
   different output-root guard.
4. **D3.4 — Fresh oracle admission.** Observe the owned Windows service and capture
   or freshly validate selected model traces through Mirrors CLI. Bind captures
   to the exact model closure and selected scope. Old traces may aid debugging
   but do not stand in for this fresh gate.
5. **D3.5 — Native replay and controls.** Repeat the selected schedules on fresh
   native instances. Compare actual production observations with Mirrors. Build
   isolated production-behavior mutations and require genuine `step_mismatch`;
   changing only a portable protocol simulation earns no credit.
6. **D3.6 — Cleanup and refusal.** Exercise unexpected phase, bad actor/mapping,
   cancellation, worker exit and teardown failure. Retain native/process cleanup
   separately and expose any uncontrolled effect or unexercised historical trace.
7. **D3.7 — Retain and review.** Verify source/mapping/model hashes stayed stable;
   retain repeated outcomes, native transcripts and same-time service identity.
   Publish only the bounded pilot claim and explicit exclusions.

### Exit gate

Two real native actors execute the selected production slice under the reusable
coordinator/bridge, recorded schedules reproduce outcomes, and production
mutations cause real comparison failures. The bridge preserves safe native hook
behavior and records verified cleanup. Existing WriteSentry qualification is
neither relabelled nor enlarged implicitly.

## DPM-4 — Bounded exploration and coverage

### Contract and architecture

Start with exhaustive finite enumeration, without partial-order reduction. An
exploration declaration fixes the actor-local checkpoint chains, finite input
assignments and bounds. Enumerate every eligible interleaving in a deterministic
order, preserving each actor's local order and terminal step. Define preemption
count precisely as switching away from an unfinished operation; a completed
operation does not count as preempted.

The small two-actor, three-step fixture provides an independently enumerable
20-interleaving denominator before additional bounds. Each declared input
assignment multiplies that denominator. Any time/run-budget stop is explicitly
incomplete. Every visited schedule is classified, including invalid, unrealizable,
comparison failure, timeout, cancellation and cleanup failure. Reproducible
counterexamples and exploration completeness are different result dimensions.

Model-state and transition coverage must use semantic values, preserving map/set
equality and excluding only declared scheduler-only metadata. Never collapse
actual model variables or treat action-name counts as complete interleavings.

### Ordered work

1. **D4.1 — Declaration and enumerator.** Implement strict finite actor-chain/input
   admission, stable interleaving enumeration, explicit preemption semantics and
   hard actor/step/run/time budgets. Invalid declarations construct no SUT.
2. **D4.2 — Execution and receipts.** Execute each schedule through the same replay
   path, retain the exact inputs/schedule/outcome, and preserve primary/cleanup
   separation. Retain the first counterexample without silently pruning others.
3. **D4.3 — Coverage accounting.** Record eligible, attempted, completed and each
   non-pass category, actual semantic states/transitions and action/checkpoint
   counts. Claim exhaustive completion only for the fully enumerated declared
   scope with all omissions accounted for.
4. **D4.4 — Independent denominator.** Compare the fixture's enumeration against a
   separate combinatorial checker; verify all 20 merges and bounded subsets,
   multiple input assignments, and stable canonical state identity behavior.
5. **D4.5 — Incomplete/negative controls.** Stop by run budget, time budget and
   cancellation; inject failing/unrealizable schedules and cleanup failure.
   None may produce a false complete/pass aggregate. POR remains disabled.
6. **D4.6 — Retain and regress.** Save denominator proof/check outputs and execution
   receipts, run affected DPM-1/2/3 regressions, and document exact completeness
   limits before DPM-5.

### Exit gate

The small fixture exhausts its declared finite scheduling/input scope against
an independent denominator. Truncation and every non-pass remain visible;
semantic coverage does not count instrumentation noise. No general weak-memory,
instruction-level or unbounded concurrency claim is made.

## DPM-5 — Installed consumer and capability evidence

### Contract and architecture

Install the reusable MirrorCPP module and its public contracts into a fresh
prefix. Build a downstream consumer using only installed headers/libraries and
its declared fixture/model artifacts. Run with source checkouts hidden and
network access removed for offline tiers. Native pilot artifacts remain an
explicit application/platform dependency rather than an undeclared sibling path.

A versioned capability manifest and compatibility documentation may advertise
only the implemented and accepted profiles. Portable fixed replay, generated
comparison, finite exploration and the specific native pilot are separate claims.
The manifest must not imply a Windows Gate backend, arbitrary production control,
full WriteSentry qualification or a new M5 release candidate. External package
registry publication is not required for this installed-consumer/capability gate.

### Ordered work

1. **D5.1 — Packaging contract.** Install public scheduler/integration/exploration
   interfaces, transitive dependencies and a versioned capability manifest;
   include explicit profile/platform/limitation fields.
2. **D5.2 — Fresh downstream consumer.** Configure/build from installed artifacts
   with no sibling-checkout assumptions. Exercise fixed replay, generated model
   comparison and the declared finite exploration scope.
3. **D5.3 — Source-hidden acceptance.** Copy admitted binaries/model artifacts and
   dependencies into a bounded runtime, hide source/scratch build roots, disable
   networking for offline tiers, and verify both passing and rejection cases.
4. **D5.4 — Native artifact binding.** Verify the native pilot's manifest/mapping,
   source/model/build hashes, process cleanup and repeated receipts as separate
   platform evidence. Do not substitute portable test results for native evidence.
5. **D5.5 — Capability controls.** Reject missing/tampered artifacts, incompatible
   mapping/profile and incomplete evidence. Published capability observations
   must trace to retained acceptance records for the exact exercised inputs.
6. **D5.6 — Final review and retention.** Verify current source/build identities,
   preserve historical records, write the final stage-by-stage acceptance report
   and update proposal/roadmap status. Report every unqualified exclusion.

### Exit gate

A fresh installed consumer works without source checkout access, negative
controls reject invalid bindings/artifacts, and capability/compatibility claims
match the retained portable and native evidence. Any unmet required stage gate
keeps the dependent claim incomplete; source tests alone never qualify it.

## Execution ledger

| Stage | Current status | Next acceptance step |
| --- | --- | --- |
| DPM-2 | Accepted: four fresh oracle cases, 60 replay controls; generated outputs clean | Declared cooperative binding scope only |
| DPM-3 | Accepted: four native schedules repeated, two production mutants detected, native failure/refusal controls pass; four bounded MBTSafety checks VALID | Four-case pilot only; historical full v3 scope excluded |
| DPM-4 | Accepted: 20 schedules x 2 inputs; 11 finite execution/coverage cases | No all-schedules model-comparison or universal claim |
| DPM-5 | Accepted: fresh installed portable and native consumer gates with source hidden/network isolated; capability observation retained | No general Windows SDK/Gate or new M5 release claim |

## DPM-4 implementation contract — 2026-10-04

The first exploration profile is `mirrorcpp.finite-checkpoint-exploration/v1`.
A declaration contains fixed actor-local chains ending in `$done`, an explicit
finite list of JSON input assignments, the model/mapping/implementation identity,
and reviewed base-observation/instrumentation variable lists. Actor order and
schedule traversal are canonical. Switching away from an actor whose chain is
not complete counts as one preemption; switching after `$done` does not.

Enumeration has its own candidate/time bounds before or alongside execution.
A complete small denominator is retained when it can be established; hitting an
enumeration bound reports a lower bound and unknown total. Run-count, time and
cancellation limits cannot produce a complete result. Per-run evidence must bind
to the exact candidate schedule and carry confirmed cleanup before another run
is started. Runner exceptions or unknown cleanup stop exploration explicitly.

The default runner uses the existing scheduler. A reviewed runner can instead
supply DPM-2 comparison evidence; scheduling completion, model comparison and
exploration completion remain separate dimensions. No arbitrary callback result
is accepted as a pass without its exact schedule/identity and execution evidence.
An actual model mismatch is a retained counterexample; it does not count as
completion of the unexecuted suffix of that schedule.

Canonical coverage uses type-tagged value encodings: map entries are ordered by
canonical key, set members are recursively normalized, sorted and deduplicated,
and sequence/tuple order is preserved. Integer and string keys remain distinct;
duplicate map keys and unsupported mixed/compound map keys reject coverage.
Ordinary record keys remain ordinary data. The projection lists every actual
observation variable; excluded instrumentation variables are explicit and retained.
There is no implicit dropping of a semantic field.

Acceptance uses all 20 order-preserving merges of two three-interval actors,
two declared initial inputs (40 executions), independent combinatorial checking,
preemption-limited subsets, and explicit incomplete/failure controls. This local
result supplies no native acceptance credit. The separate approved native result
below closes the dependent native capability claim in DPM-5.

## Historical local-only acceptance — 2026-10-04

[Evidence and precise scope](dpm2-dpm5-evidence-20261004/README.md), including
source/binary identities, 220/220 SDK units, clean generated output, 15 actual
installed replay cases and 11 finite-exploration cases. At that checkpoint, all locally independent
steps had been executed. Overall DPM-2–DPM-5 acceptance was **Partial**:
fresh remote capture and real native Windows pilot acceptance still required
explicit transfer authorization. No commit, push, server reconfiguration or
external package publication was performed.

## Approved remote/native completion — 2026-10-04

The user explicitly approved the previously gated transfers/staging. All remaining
steps were executed: four fresh counter captures with 60 replay controls; four
fresh native captures and four fixed-schedule MBTSafety validations; eight native
positive replays, two production mutation mismatches and four native failure
controls; three mapping refusals before acquisition; and source-hidden installed
consumer build/runtime acceptance. Final host observation found no remaining
owned worker. The server retained its original PID/binary identity.

[Final acceptance and capability observation](dpm2-dpm5-qualified-20261004/README.md)
bind the corrected counter model, freshly generated raw-ITF native binding,
source/build/compiler identities and receipts. The previous Partial entry above
is historical. No commit, push, server reconfiguration or external package
publication was performed.
