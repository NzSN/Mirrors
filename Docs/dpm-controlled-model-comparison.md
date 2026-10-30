# Finite controlled mutex/FIFO model comparison

The initial profile `mirrors.controlled-mutex-fifo-model/v1` compares one
reviewed real-thread C++ producer/consumer mapping. It adds the
[installed CLI command](dpm-cli-guide.md#finite-controlled-mutexfifo-comparison)
and a composite receipt. Raw SDK receipt schemas and their
`modelComparison:false` claims remain unchanged.

## Mapping and authority

The producer starts, acquires `mutex`, increments the observed count, checkpoints,
unlocks, sends 10 and 20 through capacity-one FIFO `queue`, then finishes.
The consumer starts, receives both values, acquires the mutex, increments count,
checkpoints, unlocks and finishes. Two actors each have seven decisions.
The observer reads actual native count and received values after every decision;
the initial frame and all fourteen subsequent frames are required.

[The model](../specs/ControlledMutexFifo.tla) owns expected PCs, ownership,
enabled operations, FIFO contents and observations. The native grant/result
witness fixes the chosen actor order and supplies actual operation/resource/value
and enabled-set claims. The model checks every transition and observation,
including the terminal count 2 and received sequence `<<10,20>>`. Expected states
never seed the native application or its observer.

Pure admission in `Core/DpmSyncComparison.lean` and the strict codec checks
closed fields, selected model/mapping/implementation hashes, int64 values,
indexed complete observation frames, ordinal-paired grants/results, complete
actor chains and terminal actor/resource declarations. Only a completed,
non-budget-exceeded native execution with confirmed cleanup is admitted.
Admission emits a witness with `modelComparison:false`; it is not conformance.

The host pins the policy, native binary, mapping, model and validator, generates
a constant-bound query from actual evidence, then invokes the selected remote
Mirrors CLI over mTLS. An actual valid verdict establishes `matched`; an actual
invalid verdict establishes `rejected`. Both mean a model comparison took place;
only the match passes. Missing, stale, timed-out, malformed or incomplete evidence
has no model-comparison success. Source/artifact changes during the operation
refuse. All retained artifact roles are hash-bound in the composite result.

## Bounds and limits

Admission permits at most 32 decisions and exactly N+1 observation frames; the
initial mapping executes fourteen. The witness is bounded to 1 MiB at strict
JSON admission, with depth 32. The remote query bound is N+1, at most 33.
Host process/output/aggregate evidence limits and owned descendant cleanup apply.
The Windows relay has a 90-second validator deadline and 256 KiB combined verdict
output limit. Credential paths select files on their existing host; credential
bytes are not evidence artifacts.

The acceptance campaign exercises first-enabled and last-enabled selection,
count/FIFO/early-unlock semantic mutations, cleanup/deadline refusal and malformed
receipt/identity controls. Reduction tests exactly those two policies for a count
mutation: two fresh baselines, every catalog trial and a fresh best replay.
`minimal_in_admitted_catalog` means only that explicit two-policy space.

This profile does not prove all controlled-resource programs, all interleavings,
weak-memory behaviors, arbitrary native instruction scheduling or OS resource
quotas. Installed offline C++/ECMA/Rust DPM acceptance is a separate claim from
this remote model comparison. Exact acceptance identities and failures are in
[the campaign record](../Plans/completion-evidence-20261029/README.md).
