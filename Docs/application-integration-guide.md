# Integrating an application

The supported first path is Node ESM, generated asynchronous bindings and a
checked trace corpus. Local execution uses MirrorECMA alone. Restricted execution
adds MirrorGate's Linux/Bubblewrap environment and its optional MirrorECMA
integration. Prepare compatible packages and tools once; package publication is
separate from the implementation and installed-consumer tests described here.

## Evaluator: declare the experiment

Start with `mirrorecma init DIRECTORY`. In the resulting `mirror.project.json`,
select the reviewed model, sealed interface contract, structural evidence,
checked traces, acceptance requirements and generated output locations. Pin the
approved installed compiler and server in the toolchain lock. The
[project-tools guide](../../MirrorECMA/docs/project-tools.md) documents every
field, package/tool identity and the local versus remote path rules.

Run `mirrorecma generate --project FILE`, then compile the generated TypeScript
as part of normal application preparation. Point `model.module` to the compiled
companion and `implementation.module` to the real adapter. Generation does not
create traces, approve a scaffold proposal, implement behavior or install tools.
An optional `model.moduleSha256` pins the evaluator-approved compiled module;
generated executable code remains trusted input.

For an ESM application (`"type": "module"` in its package manifest) with
TypeScript already installed, a minimal explicit compilation is:

```sh
./node_modules/.bin/tsc .mirrors/evaluator/Example.suite.ts \
  --target ES2022 --module NodeNext --moduleResolution NodeNext \
  --strict --skipLibCheck --noEmitOnError
```

Use the generated model's actual filename. This emits the companion and imported
generated binding as `.js` files beside their `.ts` sources; configure
`model.module` accordingly. An existing application build may own this same step.

Run `mirrorecma check --project FILE` for read-only freshness and corpus preflight,
then `mirrorecma replay --project FILE`. The declaration uses ordered, nonempty
trace occurrences; repeated traces test reset but do not establish additional
distinct behavior. Coverage requirements name stable transition IDs, and pairs
are counted only within one trace after Mirrors accepts both observations.

For a library integration, import the generated `<Model>Model`, call `defineSuite`
with the same replay/acceptance data, then call `runSuite`. Put the adapter import
inside its implementation factory. See the complete
[suite API example](../../MirrorECMA/docs/application-suites.md). There is no
handwritten registry tuple, descriptor reconstruction or collection-conversion
loop on this path.

## Implementation author: map the actual application

The optional Gate development export `mirrorgate/adapter-kit` generates native
declarations, an editable stub and public structural checks from the sanitized
manifest. Read the [kit/profile guide](../../MirrorGate/docs/application-integration-runtime.md)
for its generation/check API. Generated declarations are owned; regeneration
preserves the editable adapter and approved behavioral prose.

Implement the declared `actions`, `observe` and optional domain `dispose`.
Actions complete with `undefined`. Await actual side effects before returning;
observe actual SUT state, using native `Set`, string-key `Map`, `bigint` and the
declared records/tuples/variants. Every trace's initializer resets the SUT. A
structural checker proves only public shape/codec/lifecycle obligations; it does
not prove business semantics or that an observer is honest.

Use the public contract to implement behavior. Do not reconstruct expected model
state in the observer. Validate the integration using deliberate mutations of
the real SUT with the same observer. For restricted authoring, perform imports,
builds and structural checks through admitted Gate tools; private evaluator
modules, traces, expected values and credentials are excluded.

## Integrator: choose the execution path

Local callers use `runSuite` and transfer one disposal handle. Register staged
resources through `context.deferCleanup`; use the returned once-only wrapper
when the final disposer adopts that resource. The runner owns registered
obligations on both success and failure. Arbitrary unregistered allocation
remains the application's responsibility.

Restricted callers use `evaluateSuite` from `mirrorgate-mirrorecma` with the same
suite, an operator-approved environment and submission reference. The
[workflow guide](../../MirrorGate/integrations/mirrorecma/WORKFLOW.md) specifies
direct and already-hosted ownership, receipts and result disclosure. The default
`node-esm/v1` build profile copies approved JavaScript sources and needs an entry
point, source selection and pinned runtime/dependency roots. TypeScript requires
separate explicit preparation; the profile does not install dependencies or run
submitted code in the evaluator.

Keep domain test-service setup and intentional faults in application code.
Binding/worker acquisition waits for required model match, and the original Gate
owner remains responsible for physical cleanup even if negotiation rejects.

## Operator: prepare compatible tools and isolation

Prepare packages and tool/runtime roots before running the suite. Tool overrides
must satisfy the same pinned identity and capability requirements as the lock;
an incompatible override fails without fallback. Local checked replay needs no
Java or Apalache. Fresh witness generation is a separately chosen workflow with
its own tool identities, bounds and provenance.

`mirrorecma doctor` is read-only. It reports file/package identities separately
from live executable/protocol capabilities, namespace admission and agent audit
freshness. Gate's existing control hello capability report performs its bounded
backend admission probe; use an explicitly opened and closed Gate control client
for that operator check. It creates temporary probe resources under the existing
supervisor and removes them before reporting admission. A successful configuration
check alone is not proof that Bubblewrap or a managed author is available.

Select the negotiated `hosting.public-environment-v1` capability for current
hosts. Gate delivers admitted logical paths/tools/limits through the public
contract response, so application briefs need not reproduce mount instructions.
Keep credentials in private operator configuration. Audited host support changes
invalidate old receipts; renew the approved agent-runtime audit before a new
actual restricted-author acceptance run.

## Interpret the result and reproduce the evidence

`passed` requires matched conformance, met acceptance and successful applicable
cleanup. A matched replay with missing required coverage is a failed evaluation,
not a model mismatch. Cancellation, timeouts, implementation/codec failures and
unconfirmed cleanup cannot count as killing behavioral mutants. Local cooperative
completion is distinct from Gate-confirmed physical cleanup. Local JavaScript
cannot preempt its own CPU-bound loop with a timer.

Gate persists requested trusted receipts exclusively with mode `0600`, after
cleanup. Receipt failure remains separate from model/cleanup outcomes and prevents
overall success. Author-facing output remains the approved public projection.
The project CLI exits 0 for full success, 1 for a genuine model mismatch with
satisfied cleanup, and 2 for other failures.

The migrated [three application suites](../../MirrorECMA/examples/application-validation/README.md)
provide correct and faulty WorkQueue, persistent-transfer and lease examples.
Their [migration evidence](../../MirrorECMA/examples/application-validation/results/2026-09-16-suite-migration.json)
records pinned first mismatches, local versus physical cleanup and separately
generated witnesses. For current gate results and their scope,
read the [execution record](application-integration-progress.md).

Independent onboarding measurement starts with prerequisites installed and a
checkout available. Record prerequisite installation separately, then setup and
first-replay time, manual configuration steps, handwritten integration code and
time to diagnose a seeded defect. The implementation team and automated test
driver are not substitutes for an evaluator unfamiliar with these internals.
