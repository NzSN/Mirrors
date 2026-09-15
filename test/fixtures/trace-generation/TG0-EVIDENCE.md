# TG0 trace-generation transport repro evidence

Captured 2026-09-15 for
`Drafts/trace-generation-transport-hardening-tasks.md` section 5.

## Frozen inputs and compatibility measurements

- MirrorECMA's synthetic inline source produces a 70,209-byte
  `register_trace_gen` line and a 70,128-byte `register_explore` line.
- The Lean synthetic value builder produces exact 65,535- and 65,536-byte
  compact `gen_traces_done` messages and exact 65,535- and 65,536-byte compact
  `job_result` messages. The path-overflow forms are 70,073 and 70,110 bytes,
  respectively.
- The small generic Counter controls are 101 bytes (`gen_traces_done`) and 144
  bytes (`job_result`). They remain below the unchanged 65,535-byte cap.
- The failure fixture exits 42 after emitting separate stdout and stderr,
  includes the multibyte scalar sequence `测试`, exposes its owned working
  directory, and emits more than the proposed diagnostic budget.

These are reproduced synthetic measurements. The historical 65,286- and
109,036-byte application-response measurements are not claimed as reproduced;
their original artifacts no longer survive in the selected fixture set.

## Pre-change defect evidence

Before the premature TG1 production edits appeared in the shared MirrorECMA
worktree, a bounded run of `owned-registration-lifecycle.test.ts` was killed by
`timeout` (exit 124). The public registration paths rejected the oversized
line but left their spawned fixture alive, and scripted registration-send
failures observed `closeCount = 0` instead of 1. The real-child tests use a
PID file as the child identity and kill that exact PID in `finally`, so the
leak symptom cannot leave the test process unbounded.

The current Mirrors implementation remains red under:

```text
APALACHE_MC=$PWD/test/fixtures/trace-generation/apalache-failure.sh \
  lake env lean --run tools/TraceGenerationTransportReproSpec.lean
```

The command exits 1 with twelve focused failures:

- synchronous 65,536-byte durable, ephemeral, and path-overflow replies reach
  the transport and are rejected;
- asynchronous 65,536-byte and path-overflow `job_result` replies reach the
  transport and are rejected instead of becoming stable terminal results;
- the synchronous oracle returns the literal `trace generation failed`, losing
  the stable category, exit 42, stdout, stderr, Unicode, truncation marker, and
  sanitized `<run>` identity.

The same command typechecks successfully before running, and its 65,535-byte
and Counter controls pass. Every observed hang path is bounded externally or
by exact-PID cleanup.

## Handoff contracts

- TG1 must make both public string-target APIs validate before child
  allocation, while post-acquisition send failures close once and preserve the
  send error if cleanup also fails. Successful in-limit registration bytes may
  not change. The currently present TG1 production edits are not accepted by
  this TG0 note; they require the package's full acceptance commands and an
  independent handoff.
- TG2 must return decoded inline values before owned-directory cleanup, mark
  path durability explicitly, and carry categorized bounded Apalache failure
  evidence through cleanup. A generation failure remains primary over cleanup;
  a success followed by cleanup failure becomes an operation failure.
- TG3 must plan from exact final compact bytes. Synchronous shared-filesystem
  results may use paths only when durable and fitting; ephemeral, remote, and
  path-overflow cases return bounded errors. Async oversized results retain the
  same job id and return the same terminal error on repeated query and await.
- Once `DeliveryScope` and `GeneratedTraceDelivery` land, the black-box TG0
  transport/oracle constructors must be assigned explicit shared/remote scope
  and durability rather than relying on pre-TG2/TG3 shapes.

No DumpLedger or generated application artifact was read into a fixture or
modified by TG0.
