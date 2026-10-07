# DPM integration kit and counterexample timeline

Date: 2026-10-07
Status: first approved slice implemented and source accepted. The
[approved feature plan](../Plans/dpm-usability-features-2026-10-07.md) keeps the
schedule reducer, installed CLI and controlled synchronization wrappers as
follow-on slices. Broader M4 remains separate; no new framework/package release
qualification is inferred from these source gates.

## Generated integration kit

Use a verified ordinary/reviewed model-interface lock and an explicit application
mapping. The mapping is `mirrors.dpm-kit-plan/v1`: model semantic identity,
actor/operation declarations and one checkpoint interval per transition action.
Each action selects a fixed actor or a declared string input ID. The compiler
cannot infer actual operations, hooks, observation fidelity or a safe lock point.

```bash
.lake/build/bin/model_interface_gen generate-dpm \
  --lock test/fixtures/deterministic-scheduling/ScheduledCounter.lock.json \
  --mapping test/fixtures/deterministic-scheduling/dpm-kit-plan.json \
  --target mirrorecma-async-v1 --out /tmp/counter-dpm-kit-new

.lake/build/bin/model_interface_gen check-dpm \
  --lock test/fixtures/deterministic-scheduling/ScheduledCounter.lock.json \
  --mapping test/fixtures/deterministic-scheduling/dpm-kit-plan.json \
  --target mirrorecma-async-v1 --out /tmp/counter-dpm-kit-new
```

Targets are C++v1/v2, async-ECMAv1/v2 and Rustv1/v2. Sync ECMA and Lean reject:
they have no accepted DPM execution profile. Ordinary generation bytes remain
unchanged. Each kit owns the ordinary binding, native helper, canonical plan,
metadata, application seed and integration checklist through the existing
`.model-interface-generated.json` publication/rollback machinery. Copy the seed
into application-owned files before editing; regeneration never owns those copies.

The helper resolves `step_for`/`stepFor(actionId, actor)` to an actual SDK `Step`.
It rejects unmapped actions, undeclared actors and fixed-actor disagreement.
Static generation rejects wrong model identity, incomplete/duplicate mappings,
unknown input/actor/checkpoint IDs and non-string actor inputs before publication.
The application admits the generated model/mapping constants and its actual
implementation identity, supplies the deferred factory and wires generated port
callbacks to the existing binding-session lifecycle. Expected state is never
passed to the factory. This first mapping contract does not automate the native
pilot's richer multi-phase/CallDone proxy mapping.

## Read-only terminal/JSON timeline

```bash
python3 tools/deterministic-scheduling/timeline.py \
  --receipt /path/to/actual-replay.receipt.json --format text

python3 tools/deterministic-scheduling/timeline.py \
  --receipt /path/to/actual-replay.receipt.json --format json \
  --expected-sha256 "$TRUSTED_RECEIPT_SHA256" --out /tmp/timeline-new.json
```

The viewer supports actual C++/ECMA/Rust comparison, binding and checkpoint
execution receipts. It shows admitted steps, accepted permits, actual arrivals,
retained observations, model verdict and cleanup separately. A model mismatch
followed by cancellation for disposal stays a model mismatch. Local schedule
completion does not become model-conformance credit. Repeated initialization
gets separate execution sections; missing/truncated evidence remains explicit.

Model-action attribution is retained from the client when present. An optional
`--kit-metadata FILE --kit-sha256 TRUSTED_SHA256` annotates unambiguous checkpoint
relations only after its model/mapping/profile identities match the receipt.
The expected metadata digest must come from a trusted artifact/check result,
not merely a hash guessed from arbitrary received input. Planned action labels
do not assert that a not-permitted interval actually executed. If Rust/C++ omit
explicit state indices, unique matching actual-state correlation is identified
as such; ambiguous matches leave the failure location unknown. Raw expected/
actual values and ordered hints remain in JSON, without a second model interpreter.

Input files are bounded regular nonsymlink JSON, duplicate/nonfinite keys/values
reject, events/observations must be ordered and consistent, and a contradictory
pass/terminal refuses. Outputs use exclusive creation and cannot overwrite the
input. Display control characters are escaped; source receipt bytes stay unchanged.
The timeline is diagnostic tooling, not a fresh replay or qualification producer.

## Accepted source evidence and remaining slices

[First-slice evidence](../Plans/dpm-usability-evidence-20261007/README.md) records
21 focused tests plus compiler/language/migration regressions. C++, Rust and Node
helpers/application seeds compile against actual SDKs. A fresh generated Node
consumer drives real owned workers through the emitted public binding and local
Mirrors supplied-trace comparison: normal replay matches, a real mutation causes
`step_mismatch`, and both confirm cleanup. Retained oracles are reused explicitly;
no new model check is credited. Generated binding/kit ownership checks and ordinary
v1 outputs pass without editing any frozen source/evidence record.

Next slices reuse these seams: a schedule-valid same-signature reducer, a packaged
cross-language replay/explore/report CLI, and a separate synchronization-wrapper
profile that explicitly models blocked/enabled actors. None is silently claimed
implemented or accepted by this first kit/timeline delivery. Source/tool changes
mean a future current-candidate qualification needs a new freeze and actual gates;
the earlier accepted C094271a54… remains its immutable profile record.
