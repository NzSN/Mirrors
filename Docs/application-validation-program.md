# Three-application validation program

Status: the three local application milestones, fresh-witness matrices,
real Gate worker matrices and fresh restricted-author runs passed on 2026-09-16.
Results and limits are recorded below. This is local checkout evidence, not
package publication, hosted CI, exhaustive conformance or an independent
third-party onboarding study.

## Objective and scope

Make application conformance testing reproducible and assess the effort required
to connect real implementations to their models. Deliver three progressively
harder integrations: asynchronous WorkQueue, persistent transfer, and competing
lease ownership. Search existing examples, specifications and Git history before
introducing a model. Preserve the existing Linux/Bubblewrap support boundary.

Mirrors owns model resolution, generated bindings and model-state comparison.
MirrorECMA owns implementation-independent replay and reports. Application suites
own models, observations, scenarios and fault expectations. MirrorGate owns
restricted authoring/build/execution and physical cleanup. Gate-specific helpers
remain in the Gate integration package.

## Common acceptance contract

Each application supplies:

1. A behavioral model, its provenance, finite bounds and explicit abstraction
   assumptions; a public contract sufficient to implement its operations.
2. A real SUT and small adapter that observes the SUT rather than reconstructing
   expected state from a shadow model.
3. A deterministic trace corpus and a separately selected fresh-trace tier.
   Record corpus/model identity; generated artifacts remain compiler-owned.
4. A reusable suite called by the command-line acceptance entry point, with
   correct and intentionally faulty implementations evaluated against the same
   model and corpus. Faults change the implementation, not the observer.
5. Reproduction instructions and a trusted machine-readable receipt recording
   implementation, model, trace and tool identities, outcomes and cleanup.
6. Separate model-mismatch, infrastructure-error, cancellation and timeout
   classifications. A failed startup or codec error does not kill a behavioral
   mutant. A conformance pass with failed cleanup is not overall acceptance.

Receipts must distinguish locally confirmed application-resource cleanup from
Gate-confirmed physical cleanup. Do not infer either from an abort signal or
from successful execution of a `finally` block alone.

## Application order and decisions

| Application | Behaviors | Required deliberate defects | Decision informed |
| --- | --- | --- | --- |
| WorkQueue | enqueue, claim, failure, retry, completion, reset | lost work, duplicate completion, wrong retry accounting, state leaking across reset | Simplest useful asynchronous integration path |
| Persistent transfer | partial writes, interruption, retry, cancellation, explicit restart | premature success, duplicate retry effect, stale session reuse, corrupt persisted content | Practicality with filesystem state and resource ownership |
| Competing ownership | acquire, renew, release, expiry, conflicting clients | overlapping ownership, expired-token acceptance, stale release, invalid renewal | Whether additional scheduling support is justified |

Each milestone first establishes a correct implementation and designated
behavioral fault detections. Review the measurements before proceeding to the
next application. Record model changes and any adjusted fault selection with
their rationale. Reuse an existing valid model rather than expanding semantics
solely to satisfy names in this table.

Restart is an explicit model operation; it does not establish arbitrary
power-loss or filesystem crash consistency. A controlled clock and selected
competing-client schedules do not establish exhaustive concurrent correctness.
An awaited asynchronous operation alone does not exercise interleavings.

## Restricted implementation acceptance

After the evaluator passes its known-good/faulty checks, fix its model and
held-out corpus for a fresh Gate-hosted implementation attempt. Supply only the
approved public behavioral contract, implementation-side port and build context.
Exclude private oracle files from authoring, build and execution mounts and
from prompts/tool responses. Submit an immutable artifact and evaluate it using
the same trusted suite through the public-port proxy.

A development subagent with access to private models is not a blind implementer.
Synthetic hosts validate plumbing only. Record actual restricted agent execution
separately, including admitted runtime identity and cleanup evidence. Repair
attempts require fresh immutable submissions and reviewed public feedback.

## Measurements and workflow changes

Report, without invented historical baselines:

- elapsed setup time to the first valid replay, with the start/end definition;
- handwritten adapter/harness lines, excluding generated artifacts and fixtures;
- designated faults detected as model mismatches, and any surviving mutants;
- evaluation duration and trace/action/sequence coverage;
- diagnosis time for observed failures, or `not measured` if unrecorded.

Fresh-workspace reproduction should use only the documented prerequisites and
commands. A developer's successful run is not independent onboarding evidence.

Prioritize shared environment discovery, implementation-side types/codec checks,
receipt persistence and cleanup retrieval only when application runs demonstrate
the need. Preserve the core package boundary; avoid adding a new framework layer
to hide application-specific logic.

## Execution evidence

### Execution ownership

The requested `general-purpose-flash` subagent delivered WorkQueue's initial
eight-mutant suite, CLI, tests and acceptance contract. Parent review checked
actual mutation behavior, exact mismatch codes/coordinates, and cleanup, then
added a retry-state mutant, failure controls and persisted receipts.
Additional named-agent attempts repeatedly reported missing task payloads and
returned reconnaissance instead of implementation; this limitation was reported
to the user. The parent completed transfer, lease, Gate integration, public
contracts, evidence and validation directly. No commits or publication were made.

Initial source revisions: Mirrors `da521d0`, MirrorECMA `257ead0`, MirrorGate
`40f3f5e`. All three working trees were clean at program start.

Available local prerequisites include the pinned Node 24.15.0 runtime under
MirrorGate's ignored `.build/toolchains/`, built Mirrors executables, and an
Apalache installation. Availability alone does not count as a passing gate.

### Delivered applications

| Application | Local correct replay | Behavioral mutants | Gate source cases | Actual restricted author |
| --- | --- | --- | --- | --- |
| WorkQueue | 2 traces / 30 transitions | 9 rejected | 7 passed | 2 traces / 30 transitions passed |
| Persistent transfer | 2 traces / 30 transitions | 4 rejected | 8 passed | 2 traces / 30 transitions passed |
| Lease service | 2 traces / 20 transitions | 4 rejected | 8 passed | 2 traces / 20 transitions passed |

Each local matrix also distinguishes application failure, timeout and
cancellation, checking store cleanup. Gate source matrices include correct
implementations, selected behavioral mutants, actual worker process exit,
non-cooperative hang and cancellation; all 23 cases confirmed physical cleanup
with no remaining resources. WorkQueue's Gate subset is duplicate admission,
dropped enqueue and stuck retry; all nine faults run locally. The WorkQueue
model has a failed flag, not a retry counter, so retry acceptance checks clearing
that flag rather than inventing a new model field.

WorkQueue reuses its existing model and witness; the synchronous artifacts stay
unchanged and its async binding was emitted by the compiler. The reuse search
covered MirrorExamples specs/history and DumpLedgerTransfer at
`c6e1176159d55ff51ec706d72b64cfaea0f04aa0`. The latter models bundle import/export,
not resumable byte upload, so the new transfer model is explicitly standalone.
No matching lease model was found. Both new models keep `Next` distinct from
`WitnessNext`; `Safety` passed over their full `Next` relations through length 5.

All three fresh tiers regenerate genuine Apalache deterministic witnesses and
reject the same local mutant matrices. Repeating deterministic traces verifies
initialization and the generation pipeline; it does not imply additional state
space or schedule coverage. Actual adapters observe persisted queue state,
payload/journal files or live lease fields; the observers are shared by variants.

### Reproduction and measurements

The [application runner guide](../../MirrorECMA/examples/application-validation/README.md)
contains build/local/fresh commands and the
[Gate guide](../../MirrorGate/integrations/mirrorecma/scripts/application-program-gate.md)
contains worker and actual-author commands. The
[machine-readable summary](../../MirrorECMA/examples/application-validation/results/2026-09-16.json)
records source/model identities, exact first mismatches, action/pair coverage,
durations, physical source-line counts, author submission/artifact identities,
and raw-receipt hashes. Raw receipts/logs are under `/tmp/mirrors-program-*`;
private host profiles/audit/logs are under `/tmp/mirrors-program-host-private/`
and are not repository artifacts. The CLI can persist new owner-only receipts.

All three local matrices also passed from a fresh relocated source directory at
`/tmp/mirrors-program-fresh-consumer`, with explicit compiler/server paths. This
reproduction reused the installed dependency tree and tools. No independent
engineer onboarding, clean network install, setup-time baseline or diagnosis-time
study was performed; those measurements remain explicitly `not measured`.

### Restricted-author evidence

The existing supported `codex-cli 0.153.4` profile with model `gpt-5.6-sol` passed
a freshly renewed `mirrorgate.codex-dispatch/v1` audit. Each application then
started a fresh actual implementer through Gate's existing managed hosting API,
in an empty source directory, with only its public behavioral contract, sanitized
compiler-emitted public manifest and tool/build brief. These runs are distinct
from the development subagent and the synthetic dispatcher audit.

Each implementer submitted its own source. Gate verified the committed source
hash matched preparation, and the unchanged private suite accepted it. All
three runs confirmed cleanup. The fixed evaluator received no repair based on
those submissions, and no private mismatch feedback was sent to an author.
The summary retains identities and receipts, not author credentials or a promise
that a later nondeterministic author run will produce identical source.

### Validation and observed friction

- Core, example and newly generated TypeScript builds passed.
- MirrorECMA Jest: **444 passed, 4 skipped**. The four skipped tests require
  explicit `TG4_MIRROR_BIN` / `TG4_FAKE_APALACHE` inputs and are unrelated opt-in
  transport-hardening checks. WorkQueue's live smoke and all new acceptance
  matrices passed separately.
- Gate `scripts/test.sh` passed with Node 24.15.0 and Rust 1.96.0: 244 Python,
  221 Node, 3 integration and 3 CTest tests, Rust checks, and actual Node/Rust
  Bubblewrap conformance/lifecycle gates.
- Compiler freshness checks and all-action preflight passed for all application
  bindings. Mirrors `lake test` and the cross-language interop matrix were not
  rerun: this delivery changes no Mirrors compiler, runtime, proofs or wire
  protocol. Mirrors changes are documentation only.
- Early nested-process probes under the enclosing development sandbox either
  lost captured output or failed subprocess/namespace admission. Authorized
  unsandboxed reruns of the actual gates passed; the initial failures were not
  counted as behavioral defects or successful acceptance.

Two concrete workflow issues were addressed locally: native Node `Set` versus
generated array-shaped set conversion is explicit at the application proxy
boundary, and public author instructions describe writable `/workspace`, frozen
`/source` and writable `/output`. Common suites, generation/check commands and
exclusive receipt writers reduce repeated application glue without changing
MirrorECMA's core ownership. Stale frontend differential-status summaries now
point to the existing profile-4 acceptance evidence.

The larger G1–G7 platform follow-ups are not claimed implemented. Durable
supervisor recovery, a generated implementation kit, generic repair lineage and
independent onboarding measurements remain follow-up investments. This program
supplies three bounded integrations and evidence to prioritize those changes;
it does not establish arbitrary concurrent correctness, power-loss durability,
complete TLA+ compatibility or universal observation fidelity.
