# Deterministic scheduling under MBT

Status: DPM-0–DPM-5 accepted for declared C++, Node-worker and Rust-thread
profiles. [Current framework status](current-status.md) separates implementation,
installed/native acceptance and the frozen M5 profile. This guide describes
checkpoint control, not arbitrary OS instruction preemption.

[Generated integration kit and timeline](dpm-usability-design.md) implement the
first approved usability slice; their source acceptance and remaining feature
contracts are separate from the earlier frozen DPM/runtime qualification.

## Ownership and execution path

```text
Model trace action
       |
Generated binding -> handwritten application port
       |
DPM binding session: initialize / advance / observe / dispose
       |
Coordinator: admit schedule -> permit one actor -> verify actual arrival
       |
Actual worker runs -> checkpoint parks it -> observer reads real SUT state
       |
Actual observation -> Mirrors comparison -> next interval or failure/cleanup
```

The SDK owns permits, parking, cancellation and worker handles. The application
owns operations, actual observations, safe checkpoint placement and external
resources. The compiler generates types, codecs, identity and dispatch; generated
files are not edited to add application behavior. Normal MBT ports need not use
DPM. A DPM port maps each model action to an admitted actor/checkpoint interval.

A checkpoint names the interval's destination. An application worker calls
`arrive("read")` after its read and waits inside that call until its next permit.
C++/Rust condition-variable waits release the scheduler mutex while retaining
thread stack/locals; Node workers await a private permit promise. Application
locks remain held, so parking while another selected actor needs such a lock can
block progress. The initial barrier parks actors before application execution;
`$done` means actual completion/exit, including relevant teardown effects.

Only declared participating actors are controlled. Background threads, external
I/O, clocks, randomness, non-returning callbacks and effects inside a checkpoint
interval require their own application contract. Scheduling changes timing and
synchronization; finite checkpoint coverage is not all weak-memory behavior.

## Profiles and references

| Client | Execution profile | SDK guide |
| --- | --- | --- |
| MirrorCPP | mirrorcpp.cooperative-checkpoints/v1 | [C++ scheduling](../../MirrorCPP/docs/deterministic-scheduling.md) |
| MirrorECMA | mirrorecma.worker-checkpoints/v1 | [Node-worker scheduling](../../MirrorECMA/docs/deterministic-scheduling.md) |
| MirrorRust | mirrorrust.cooperative-checkpoints/v1 | [Rust-thread scheduling](../../MirrorRust/docs/deterministic-scheduling.md) |

Schedules use `mirrors.checkpoint-schedule/v1` and bind the model semantic digest,
application mapping and implementation identities. Full admission precedes factory
acquisition. Receipts keep permits/actual arrivals, observations, fresh execution
identity, comparison outcome, primary failure and cleanup separately. Incomplete
cleanup retains owned handles for explicit retry; no silent thread detach or
successful conformance credit. Hard termination needs a separate process owner.

Finite exploration enumerates actor-order-preserving merges over declared finite
inputs, with explicit enumeration/run/time/evidence bounds. Unknown totals,
truncation, absent required comparison and unconfirmed cleanup never become a
complete pass. The accepted counter fixture covers 20 interleavings × two inputs;
this is bounded local coverage, not universal model conformance or POR.

The native pilot uses frozen WriteSentry phase workers: logical proxies send
Begin/Advance/Quit and report actual native phases/state. Portable coordinator
locks do not enter trap/suspended-target regions. The Linux controller namespace
hides sources and networking; the external Windows worker is not thereby sandboxed.
Gate's independent Node/Rust isolation does not imply generic DPM Gate acceptance.

## Accepted stages and exact evidence

DPM-0 contracts, DPM-1 coordinator, DPM-2 generated replay, DPM-3 bounded native
bridge, DPM-4 finite exploration and DPM-5 installed consumers are accepted for
the linked profiles. [C++ record](../Plans/dpm2-dpm5-qualified-20261004/README.md)
and [ECMA/Rust record](../Plans/dpm-languages-evidence-20261005/README.md) retain
frozen source/package/model/runtime identities. Each ECMA/Rust installed consumer
passes 60 replay cases, 11 exploration checks, 14 native runs and three mapping-refusal
controls. Broader WriteSentry qualification and current external source revisions
are not inferred from that frozen four-case pilot.

Explicit async-ECMA/Rust v2 emitters support its integer-key maps. Ordinary v1
output remains stable; the Node suite/project bundle path stays async v1. See
[generated profile contract](generated-model-interface-spec.md) and
[lock migration comparison](model-interface-compiler/lock-migration.md).

Application integration examples are in
[the executable consumer kit](../tools/deterministic-scheduling/languages/) and
[the C++ fixture](../tools/deterministic-scheduling/counter_support.hpp).
