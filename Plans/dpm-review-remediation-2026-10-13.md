# DPM review remediation plan

Date: 2026-10-13
Status: completed 2026-10-14 for the declared remote WSL scope.

[Final evidence](dpm-review-remediation-evidence-20261014/README.md) records both
remote gate exits 0, exact source/runtime/installation identities, independent
review and preserved superseded diagnostics. All final heavy qualification ran
on the owned remote WSL host; no fresh model checker, commit, push or production
change was made.

Two Astra subagents using `gpt-6-astra` with `reasoning_effort: high` developed
the design. The coordinator independently reproduced all four review findings.
The work corrects MBT artifact admission, execution evidence, output accounting
and experimental C++ deadline handling.

This plan is published separately from the uncommitted F3–F5 implementation
and evidence. Local references `Plans/dpm-f3-f5-evidence-20261013/README.md` and
`Plans/dpm-f3-f5-evidence-20261013/source-manifest.json` identify the reviewed
implementation. That dated evidence remains unchanged; it does not qualify the
corrected implementation automatically.

## Findings and required outcomes

| Finding | Current behavior | Required outcome |
| --- | --- | --- |
| P1: unlisted Python modules execute | Adjacent `hashlib.py` executes through the host's `sys.path` insertion; adjacent `json.py` executes through the packaged application runner, with selected artifact hashes unchanged | Execute only verified packaged/application Python sources, with isolated imports and an explicit trusted runtime |
| P2: incomplete evidence can report a match | An execution with no events, observations `[{}]` and outcome `cancelled` can classify as `matched` | Match credit requires complete, consistent execution and comparison evidence |
| P2: raw files bypass the output budget | A runner retains 1,048,578 bytes under a 100-byte limit because raw SDK files are not counted | Account for all retained output and refuse budget violations |
| P2: callback overruns still pass | A 100-ms execution with a 250-ms final observer and 150-ms teardown reports `passed=true`; `cleanup(1ms)` takes 150 ms | Returning callbacks that exceed their budgets cannot establish a pass |

Relevant local contracts are `Docs/dpm-runner-contract.md`,
`Docs/dpm-cli-guide.md` and `../MirrorCPP/docs/controlled-synchronization.md`.

## Scope and compatibility

Preserve existing SDK wire formats, actor scheduling semantics and failure
signature contents. Reduction remains confined to an explicit finite admitted
catalog. Exact retained October oracle captures may be reused with their
provenance checked; this work requires no new model generation.

The corrected project configuration uses `mirrors.dpm-project/v2`. Executable
v1 projects receive an explicit refusal and reprepare instruction, rather than
silent reinterpretation. Historical receipts remain available for read-only
diagnostic rendering. New project and install manifests bind the corrected
artifacts and newly built consumers.

F5 remains the C++-only `mirrorcpp.controlled-sync-experimental/v1` profile with
`modelComparison: false`. Broader M4 resource enforcement, native platform
qualification, package publication and production deployment remain separate.
No local Apalache/TLC, commit or push is included in this plan.

## Ownership and execution order

Ownership below assigns implementation responsibility. Keep one editor for
`dpm_host.py`. The evidence specialist may
develop the new pure codec and dedicated tests concurrently, but host integration
requires a sequential handoff or application by the host owner.

| Stage | Owner | Dependency | Work | Acceptance gate |
| --- | --- | --- | --- | --- |
| R0 | Coordinator | None | Freeze corrected contracts, compatibility rules and the four exact regression cases | Each regression fails against the reviewed implementation |
| R1 | Host owner | R0 | Explicit Python loading, v2 command admission, complete output accounting and process failure handling | Both adjacent-module controls write no marker; oversized retained output refuses |
| R2 | Evidence owner, with host integration by the host owner | R0; host integration after R1 | Shared execution validator and bounded typed state correspondence | Complete matches pass; malformed evidence refuses; genuine early mismatches remain valid |
| R3 | C++ owner | R0 | Execution, cleanup and exploration deadline handling | Returning callback overruns cannot pass; first failures, actual joins and cleanup retry remain correct |
| R4 | Packaging owner | R1, R2, R3 | Refresh identities, rebuild affected artifacts, regenerate projects and install into new prefixes | Selected hashes match the corrected artifacts and installation inventory |
| R5 | Coordinator and independent Astra reviewer | R4 | Fresh installed-consumer acceptance, independent review and a new dated evidence record | All regression and integration gates pass within their declared scope |

R1 and R3 can proceed independently. R2's pure codec and dedicated tests can
proceed alongside them. Preserve unrelated editor caches, ECMA `.work/`, and
all historical evidence.

## R1 Python loading and output accounting

### Explicit command and import handling

Introduce closed typed command forms:

```text
native:
  { kind: "native", executable: PATH, args: [ARG, ...] }

Python:
  { kind: "python-isolated", executable: PATH, script: PATH, args: [ARG, ...] }

ARG:
  { artifact: PATH } or { literal: STRING }
```

Lean validates the structure and finite bounds. The host resolves and
hash-checks the executable, Python script and artifact arguments. Literal
arguments are preserved as individual argv entries; no shell is involved.
Maintain bounded counts/UTF-8 lengths and reject NULs and unknown fields.

The host supplies `-I -S -B` before the verified Python script. Application
arguments cannot replace those flags. The initial Python runner profile can
require a standalone adapter using the standard library; additional packaged
Python dependencies require explicit admission.

Remove directory insertion into `sys.path` from the CLI, installer and installed
gate helpers. Load packaged helpers by compiling and executing the exact
verified source bytes at explicit paths, without adjacent module or `.pyc`
lookup. Validate the same bytes that are executed. Extend the embedded host
identity closure when introducing a packaged helper.

The pinned interpreter executable does not pin its standard library, extension
modules, loader or shared libraries. Record these as trusted platform
prerequisites. Packaged/application artifacts must remain stable during
execution; this profile does not promise confinement against arbitrary
concurrent filesystem replacement or process-group escape.

### One output accounting interface

Keep `outputBytes` as a per-request limit and add `totalOutputBytes` for a
replay, explore or reduce operation. Count all retained bytes beneath the
operation's output root: request/schedule copies, logs, response envelopes,
raw SDK receipts, temporary files, copied receipts and host reports. Existing
project/oracle inputs outside that root are excluded. Duplicate retained
representations count separately.

Centralize accounting and process cleanup at the existing request-execution
interface. Drain stdout/stderr concurrently through bounded streams. Replace
Counter's nested `capture_output` usage, bound raw receipt reads before parsing,
audit nested output files during execution, and perform final accounting after
owned processes stop and streams drain. Reject unexpected symlinks and special
files. Charge host output writes before publishing them.

Reserve capacity for the final report and required fresh best replay. If those
cannot complete, retain an incomplete result rather than claiming successful
reduction. Planned budget exhaustion may yield `best_observed` only when its
required confirmation and evidence are available.

Output overflow, timeout, malformed evidence or uncertain cleanup stops further
acquisition. Terminate the owned process group and report cleanup separately
from the primary reason. Actual overflow yields exit 2 and no match/minimality
credit.

Polling establishes accounting and admission, not a hard disk or memory quota.
Direct file writes can overshoot between checks. Preserve raw failed evidence,
record the observed overshoot and never relabel it as within budget. Require
non-detaching runners; hard aggregate confinement remains broader M4 work.

### Files and regression gates

The host owner controls `Codec/Dpm.lean`, `Shell/Dpm/Cli.lean`, identity generation,
`dpm_host.py`, `cli.py`, `prepare_cli.py`, `install_cli.py`,
`check_cli_installed.py`, `apps/counter_runner.py` and the host/install tests.
Keep pure candidate ordering and its proofs in `Core/Dpm.lean` unchanged.

Required controls include both unchanged-pin adjacent-module reproductions,
adjacent bytecode, the exact 1 MiB raw receipt plus `{}` response at a 100-byte
limit, child exit between polls, final response growth, duplicate/nested files,
stream floods, cumulative reduction trials, exact-limit cases and descendant
writers. Assert that no unadmitted marker executes and no over-budget result
receives success credit.

## R2 Execution and comparison evidence

Introduce one shared execution validator in `dpm_host.py`, consumed by replay
classification and SDK exploration. Distinguish complete execution evidence
from a valid comparison prefix. F2 diagnostic rendering must not turn partial
evidence into conformance credit.

Validate strict types, schema/profile, embedded schedule identity, bounded
execution ID, positive generation, and actor declarations against the complete
admitted schedule. Validate event ordinals and step indices, alternating
permit/arrival pairs, declared actor/operation, actor-local permit origins and
actual destination checkpoints. Observations must cover consecutive
`afterSteps` indices and contain valid states.

A match requires all N intervals, 2N events and N+1 observations, with
`outcome=completed`, successful completion flags, confirmed cleanup, no remaining
actors, a successful client and consistent `all_steps_done` terminal evidence.
Missing events, observations `[{}]`, or cancelled execution with stale true
flags refuse.

Preserve actual SDK differences:

- Early C++ mismatches currently report `completed` with incomplete execution
  and `passed=false`; ECMA/Rust report cancellation during disposal.
- A final-interval mismatch can have a successful execution and failed comparison.
- C++ does not require unique operation names or emit `actorThreads`.
- C++ cleanup attempts use `status`; ECMA/Rust use `cleanup` with different
  optional error fields.
- Execution IDs remain fresh across both baselines, trials and best replay;
  generation 1 may legitimately recur across independent subprocesses.

Return checked oracle/correspondence context from oracle admission. Map model
states to observations through that context; the spectator means model
`stateIndex` and execution `afterSteps` cannot be equated directly. Check terminal
expected state against the admitted oracle and terminal/client actual state
against the corresponding observation.

Add a bounded pure helper in proposed `Codec/DpmEvidence.lean`, using existing
`Codec.decodeValue`/`Codec.decRecordF`, `valEq` and `diffState`. Require recursive
duplicate-key rejection, including ITF maps. Use typed equality rather than
Python's Boolean/integer or raw-container equality. This compares supplied
states only; it evaluates no model transitions or TLA expressions. Preserve
existing failure-signature contents during this remediation.

The evidence owner controls the new codec and dedicated regression tests; the
host owner integrates the validator and bounded launcher helper. Exit 0 requires
a full match, exit 1 an actual cleaned mismatch, and exit 2 refusal/incomplete
execution. Malformed reducer trials remain unresolved and cannot establish
minimality.

Test all three profiles with real full matches and early mismatches, then mutate
events, permits, steps, declarations, identities, observations, terminal/client
fields and cleanup. Cover reused IDs, spectator offsets, final-interval mismatch,
typed ITF equivalence and invalid duplicate map keys. Fixture mutations must be
paired with fresh SDK integration runs.

## R3 C++ execution and cleanup deadlines

Use one monotonic execution deadline starting before factory acquisition.
Check it before and after factory/observer callbacks, after waits even when
their predicates become true, and before final completion acceptance. A late
factory return retains the acquired program for teardown but starts no workers.
A late final observation cannot establish a pass or be recorded as timely.

Preserve the first primary failure and original failure graph. Record subsequent
budget excess separately; do not replace resource misuse, controlled deadlock
or cancellation with a later timeout.

`cleanup(timeout)` uses one absolute deadline across worker waiting, actual
joins and teardown. If it expires before the next cleanup step, retain incomplete
cleanup for retry. If an uninterruptible join or teardown returns late, physical
cleanup may be confirmed, but a sticky overrun result prevents a pass. Set the
teardown-attempted flag before invocation; thrown or late teardown never repeats.
Retries cannot erase the first failure or budget overrun.

Execution timing ends after the final observation; cleanup has its own budget.
No detached callback thread or claim of in-process hard interruption is added.
The destructor can still wait for uncooperative application code; hard process
termination belongs to an external owner.

Exploration checks its total deadline after factory, start, advance/observation
and final cleanup. Use the earlier of the run and exploration deadlines for
execution, followed by separately bounded cleanup. Retain failed receipt rows
and executions needing cleanup retry. Reserve bounded failure metadata when
receipt capacity is exhausted. An empty frontier after an overrun does not
establish complete coverage.

The C++ owner controls `src/schedule_sync.cpp`, additive report/receipt fields in
`include/mirrorcpp/schedule_sync.hpp` if needed, `test/unit/schedule_sync_test.cpp`
and the controlled-resource guide. Keep rendering consistent with any new
non-passing budget facts.

Tests cover late factory, initial/intermediate/final observer, teardown-only
overrun, slow join/TLS destruction, the exact combined reproduction, prior
failure followed by late cleanup, cleanup retry with one teardown, callback
exception/lateness precedence and the last exploration prefix exceeding its
total budget. Use controlled synchronization or generous timing margins; assert
outcomes and ownership rather than tight wall-clock upper bounds.

## R4 and R5 Repackaging and acceptance

Refresh host identities, rebuild the Lean launcher and affected C++ SDK/consumers,
regenerate v2 project and installation manifests, and install into new prefixes.
Verify installation inventory, relocation and no-overwrite behavior. Preserve
older installed trees and evidence as historical artifacts.

Fresh source-hidden, network-isolated C++, ECMA and Rust consumers must run:

- Actual full match and early mismatch, plus malformed-evidence refusal controls.
- Reduction with two fresh stable baselines, seven smaller admitted candidates
  and fresh best replay, with independently checked execution IDs and cleanup.
- All eight model-backed supplied-trace catalog cases and 40 local SDK schedules
  per profile, keeping model comparison separate from local exploration.
- Report/timeline, runtime/artifact tamper, output budgets and cleanup controls.
- The installed C++ controlled-resource sample and callback-overrun controls,
  retaining `modelComparison: false`.

Run focused Lean/Python/C++/ECMA regressions and the local no-model-check gates.
An independent Astra review must check the final implementation and actual
negative controls before remediation is accepted. Record source hashes, commands,
raw evidence, limits and skipped checks in a new dated evidence directory.
Existing F3–F5 and frozen M5 evidence does not transfer qualification to the
corrected implementation.
