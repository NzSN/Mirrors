# Deterministic Model-Interface Generation — Design

> Status: **Mirrors compiler and `mirrorecma-v1` emitter implemented; client
> negotiation libraries and static C++/Rust/Lean emitters remain planned**
> Scope: generate a model-specific implementation interface and a binding to
> the existing client-side `StateComputer` interface for MirrorECMA,
> MirrorCPP, MirrorRust, and MirrorLean.
> Related documents: `architecture-overview.md`,
> `client-implementation-guide.md`, `interface-reference.md`, and
> `client-test-coverage.md`.
> Detailed compiler contract:
> [`model-interface-compiler-design.md`](model-interface-compiler-design.md).
> Runtime descriptor distribution:
> [`model-interface-runtime-distribution-design.md`](model-interface-runtime-distribution-design.md).

## 1. Problem

Every existing client ultimately accepts the same low-level computation:

```text
(action name, parameters or initial state, previous reported state)
    -> next reported state
```

MirrorECMA calls this `StateComputer`; MirrorCPP, MirrorRust, and MirrorLean
provide equivalent interfaces. This is a useful stable seam, but it is a raw
protocol-facing interface:

- action names are strings;
- parameters and observations are untyped ITF state maps;
- nested parameter paths are known manually by each adapter;
- the full oracle state is available during initialization;
- `prevState` makes it easy to accidentally reimplement the model instead of
  driving the real system under test (SUT);
- each language repeats dispatch, decoding, observation assembly, and error
  handling.

An LLM can write this glue, but Mirrors does not currently produce a
deterministic, model-specific interface for the LLM to implement. For example,
nothing mechanically turns the Counter model into this requirement:

```text
initialize()
tick(stride : Int)
observe() -> { count : Int }
```

The missing module is a **Model Interface Compiler**. It generates that
implementation-facing interface and a deep binding from it to the existing
`StateComputer` seam.

## 2. Goals

1. Preserve `StateComputer` as the low-level client interface.
2. Generate model-specific, typed implementation interfaces deterministically.
3. Generate equivalent interfaces for TypeScript, C++, Rust, and Lean.
4. Restrict an LLM to the irreducible semantic mapping:
   model action to real implementation operation, and real implementation
   state to model observation.
5. Hide raw ITF values, parameter paths, phase handling, and encoding from the
   LLM-written adapter.
6. Prevent accidental oracle-state echoing and model reimplementation.
7. Detect model/interface/generated-source drift in CI.
8. Validate the completed adapter against real Apalache traces and report
   action coverage.

## 3. Non-goals

- Inferring implementation method names from TLA+.
- Generating the semantic mapping from a model action to an arbitrary SUT
  without implementation-specific input.
- Treating finite trace coverage as a proof of behavioral completeness.
- Replacing the existing JSONL protocol or `StateComputer` interfaces.
- Adding a general-purpose TLA+ source parser to the verified core.
- Claiming that generated non-Lean clients or LLM-written adapters are formally
  verified.
- Silently synthesizing unobservable model state from expected trace values.

## 4. Source alternatives

### 4.1 TLA+ annotations only

Existing Apalache `@type` annotations provide valuable structural type
information and keep model facts local. They are insufficient as the complete
source, however:

- arbitrary TLA+ relations do not define a canonical implementation command
  interface;
- an operator name need not equal the value assigned to `action_taken`;
- extracting action-specific parameter projections requires semantic knowledge;
- client-specific annotations in comments are not checked as part of normal
  TLA+ semantics.

TLA+/Apalache type information should therefore be evidence used by the
compiler, not the only declaration of adapter intent.

### 4.2 Trace inference only

Typed ITF traces provide:

- `vars` and `param_vars`;
- `#meta.varTypes` when produced by Apalache;
- observed `action_taken` values;
- concrete parameter and state shapes.

They cannot establish a complete interface. A finite trace can show that
`tick` exists but cannot show that another action does not exist. It may also
miss variants, collection shapes, and parameter combinations.

Trace inference is suitable for scaffolding and validation only. Inferred
actions must remain unsealed until explicitly accepted in the companion
contract.

### 4.3 Companion contract only

A separate contract is explicit and deterministic, but a fully independent
contract would repeat model variable types and drift from TLA+.

### 4.4 Decision: hybrid contract

Use each source only for facts it can establish:

| Fact | Authoritative source |
| --- | --- |
| Model variable names and structural types | Apalache typed evidence, backed by TLA+ `@type` annotations |
| Parameter variable | Companion contract, checked against `ApalacheConfig.paramVars` / ITF `param_vars` |
| Stable action identifiers and exact wire labels | Companion contract |
| Initial versus transition classification | Companion contract |
| Action input projections | Companion contract, resolved against typed model paths |
| Compared observation variables | Mirrors' actual trace repartition and `filterMeta` rules |
| Implementation methods and accessors | LLM-written adapter |
| Exercised actions and behavior | Real ITF traces |

Conflicting sources are errors. The compiler must not silently choose one.

## 5. Architecture

```text
TLA+ sources and @type annotations ───────┐
                                          │
model.mirror-interface.json ──────────────┼─> Model Interface Compiler
                                          │          │
typed Apalache / ITF evidence ────────────┘          v
                                            locked canonical IR
                                                     │
                                ┌────────────────────┼────────────────────┐
                                v                    v                    v
                          TypeScript emitter      C++ emitter       Rust/Lean emitters
                                │                    │                    │
                                └────────────────────┼────────────────────┘
                                                     v
                                      generated model-specific module
                                      - implementation port
                                      - typed values
                                      - StateComputer binding
                                      - validators and diagnostics
                                      - coverage instrumentation
                                                     ^
                                                     │
                                          LLM-written SUT adapter
                                                     ^
                                                     │
                                               real implementation
```

The generated module is deep: a small implementation-facing interface hides
raw ITF values, dispatch, typed path resolution, lifecycle rules, complete
state assembly, encoding, and coverage accounting. Deleting it would spread
that knowledge back across every model and language client.

The generated port is a real seam. At minimum, it has two adapters:

- the production adapter written by a human or LLM against the real SUT;
- a generated or hand-written recording adapter used to test the binding.

## 6. Companion contract

Use JSON in version 1. Mirrors already has a JSON codec stack, so this avoids
introducing YAML parsing solely for design metadata.

Example `Counter.mirror-interface.json`:

```json
{
  "schema": "mirrors.model-interface/v1",
  "interfaceVersion": "1.0.0",
  "model": {
    "module": "Counter",
    "source": "Counter.tla"
  },
  "wire": {
    "actionVariable": "action_taken",
    "parameterVariable": "parameters"
  },
  "initializers": [
    {
      "id": "Initialize",
      "wireAction": "init",
      "inputs": {}
    }
  ],
  "actions": [
    {
      "id": "Tick",
      "wireAction": "tick",
      "inputs": {
        "stride": {
          "from": {
            "root": "stepParameters",
            "path": [
              { "field": "parameters" },
              { "field": "stride" }
            ]
          }
        }
      }
    }
  ],
  "observations": {
    "count": {
      "modelPath": [{ "field": "count" }],
      "provenance": "implementation"
    }
  }
}
```

### 6.1 Stable identifiers versus wire labels

`id` is the stable language-neutral identity used for compatibility checks and
target identifier generation. `wireAction` is the exact, case-sensitive string
received from Mirrors. Keeping them separate permits deliberate target naming
and explicit wire-label aliases during migrations.

### 6.2 Typed paths

Paths use structured segments rather than dotted strings or JSON Pointer.
Supported normalized segments should include:

- `field` for records and state maps;
- `index` for sequences and tuples;
- `mapKey` for ITF maps with non-string keys;
- `variantValue` for variant payloads.

The `root` identifies which payload is legal:

- `initialState`: the state from `initial_state`;
- `stepParameters`: the state carried by `next_step.parameters`.

Only explicitly declared initialization paths may be exposed to the
implementation adapter. The rest of the expected initial state remains hidden.

### 6.3 Type resolution

The companion contract normally omits types that can be resolved from the
model. For Counter:

```tla
\* @type: Int;
count,
\* @type: { stride: Int };
parameters,
```

resolves the generated `count` and `stride` types to arbitrary-precision
integers. If typed evidence is absent or ambiguous, resolution fails unless an
explicit contract type is supplied and independently checked.

The normalized type grammar must cover the existing ITF value domain:

- integer, Boolean, string, and null;
- record, sequence, tuple, and set;
- map/function entries;
- tagged variants;
- an explicit opaque ITF escape hatch for types a target cannot model
  idiomatically.

## 7. Locked canonical IR

Resolution produces a checked-in lock artifact, for example
`Counter.mirror-interface.lock.json`. Emitters consume only this normalized IR.

The lock contains:

- contract schema version and model-interface version;
- source-closure digest for the root TLA+ module and its dependencies;
- companion-contract digest;
- generator version;
- exact initial and transition action sets;
- resolved parameter paths and structural types;
- complete observation schema;
- stable target-independent identifiers;
- compatibility aliases;
- no sampled coverage state; coverage is a separate report keyed by the
  semantic lock digest.

Normal code generation is pure and offline once the lock exists. Generated
files embed the lock digest and generator version. Output must contain neither
timestamps nor machine-specific absolute paths.

## 8. Generated implementation interface

For MirrorECMA, Counter output should resemble:

```ts
export interface TickInput {
  readonly stride: bigint;
}

export interface CounterObservation {
  readonly count: bigint;
}

export interface CounterPort {
  /** Completely reset the real implementation for a new trace. */
  initialize(): void;

  /** Execute exactly one real implementation operation. */
  tick(input: TickInput): void;

  /** Read the real implementation without mutating it. */
  observe(): CounterObservation;
}

export interface CounterBinding {
  readonly computer: StateComputer;

  coverage(): Readonly<{
    initialize: number;
    tick: number;
  }>;

  assertAllActionsCovered(): void;
}

export function bindCounter(port: CounterPort): CounterBinding;
```

Target equivalents:

| Model type/interface | TypeScript | C++ | Rust | Lean |
| --- | --- | --- | --- | --- |
| `Int` | `bigint` | `boost::multiprecision::cpp_int` | `num_bigint::BigInt` | `Int` |
| Record | generated `interface` | generated `struct` | generated `struct` | generated `structure` |
| Action | generated method and/or discriminated type | generated method / `std::variant` | trait method / `enum` | structure field / `inductive` |
| Port | `interface` | abstract class or constrained type | trait | structure of functions |

Per-action methods are the version-1 default. They make the required mapping
obvious to both an LLM and the target compiler. Internally, the locked IR may
still represent actions as a closed sum.

## 9. LLM-written adapter

The LLM receives the generated port, its invariants, and the relevant SUT
source. It does not receive raw protocol responsibilities.

```ts
class CounterAdapter implements CounterPort {
  constructor(private readonly sut: RealCounter) {}

  initialize(): void {
    this.sut.reset();
  }

  tick({ stride }: TickInput): void {
    this.sut.incrementBy(stride);
  }

  observe(): CounterObservation {
    return { count: this.sut.currentCount() };
  }
}
```

The adapter owns only irreducible application semantics:

- which real operation implements initialization;
- which real operation implements each action;
- how actual implementation state is observed or abstracted into the model
  observation.

The adapter must not:

- parse ITF values;
- inspect raw `StateComputer.prevState`;
- receive the expected next model state;
- construct `#bigint` or other wire encodings;
- implement action-string dispatch;
- calculate the next state by replaying the TLA+ transition relation.

## 10. Generated `StateComputer` binding

Conceptually, `bindCounter` produces this behavior:

```ts
const computer: StateComputer = (action, payload, _previousState) => {
  switch (action) {
    case "init":
      port.initialize();
      break;

    case "tick":
      port.tick({
        stride: decodeRequiredBigInt(
          payload,
          ["parameters", "stride"],
        ),
      });
      break;

    default:
      throw new UnknownActionError(action);
  }

  return encodeObservation(port.observe());
};
```

The actual generated implementation additionally handles lifecycle state,
typed path diagnostics, poisoning, observation validation, deterministic key
ordering, and coverage.

## 11. Runtime invariants

1. One generated binding belongs to one Mirrors session.
2. Calls are serial and non-reentrant.
3. The first successful callback of a trace is a declared initializer.
4. A later initializer starts a new trace and fully resets the SUT.
5. Initializer and transition wire labels are disjoint in version 1. The
   existing `StateComputer` callback does not explicitly identify whether it
   came from `initial_state` or `next_step`.
6. Every input is decoded and validated before mutating the SUT.
7. Exactly one initializer/action method is invoked per accepted step.
8. `observe()` is invoked exactly once after a successful operation.
9. `observe()` is read-only and returns a complete post-operation snapshot.
10. A failed action does not call `observe()` and does not emit
    `report_state`.
11. Missing or mistyped inputs never acquire implicit defaults.
12. Unknown action labels are errors, never no-ops.
13. Expected transition state is never passed through the generated port.
14. `prevState` is not passed through the generated port or used to calculate
    new state.
15. After an adapter or validation failure, the binding is poisoned; later
    calls fail rather than continuing from possibly partial SUT mutation.

The current `StateComputer` interfaces are synchronous. Version 1 therefore
generates synchronous ports. A future asynchronous form must be additive—for
example `AsyncStateComputer` and `bindCounterAsync`—because a JavaScript
`Promise` cannot honestly pass through the current synchronous interface.

## 12. Observation completeness

Mirrors does not compare an arbitrary user-selected projection today.
`Core.Trace.applyParamVars` moves the configured parameter variable out of the
state side. `Core.Diff.diffState` then compares `filterMeta` projections, where
`filterMeta` removes only:

- keys beginning with `#`;
- `action_taken`;
- `parameters`.

Define the required observation keys from the actual comparison input:

```text
ComparableVars = keys(filterMeta(step.vars))
```

At the model level this is approximately:

```text
trace variables
  - configured paramVars
  - action_taken
  - parameters
  - #* metadata
```

The compiler requires exact observation coverage:

```text
generated observation variables = ComparableVars
```

If a normal compared variable such as `step_count` cannot be observed from the
real implementation, compilation fails:

```text
E_UNOBSERVABLE_COMPARED_VARIABLE:
  step_count is compared by Mirrors but has no implementation observation.
```

The generator must not copy such a variable from the oracle, derive it from
`prevState`, or run the model transition to synthesize it. Legitimate remedies
are:

1. instrument or expose the value from the SUT;
2. change the model so the value is not part of conformance state;
3. add a future explicit comparison-projection feature to Mirrors, with a
   documented weaker conformance relation.

## 13. Errors

### 13.1 Contract-resolution errors

- duplicate or overlapping action labels;
- initializer/transition label ambiguity;
- unresolved or conflicting model type;
- path does not exist in its declared root;
- path kind does not match the resolved type;
- incomplete or extra observation classification;
- stale source, contract, lock, or generated-file digest.

### 13.2 Target-emission errors

- unsupported target type;
- target identifier lowering collision;
- invalid generated relative path or duplicate generated file;
- target-profile version mismatch.

### 13.3 Runtime binding errors

- `unknown_action`;
- `transition_before_initialization`;
- `input_shape_mismatch`, including action and typed path;
- `adapter_failure`, including operation and original cause;
- `observation_shape_mismatch`;
- `binding_poisoned`;
- `schema_drift`;
- `insufficient_trace_coverage`.

A correctly shaped actual observation that differs from the model is not a
binding error. It is sent normally and becomes Mirrors' `step_mismatch`, with
the existing structured diff hints.

## 14. Compiler interface

The compiler should expose a small interface:

```text
resolve(specSources, companionContract, typeEvidence)
  -> LockedModelInterface | Diagnostics

emit(lockedInterface, targetProfile)
  -> GeneratedFiles
```

`resolve` hides:

- source-closure hashing;
- contract parsing and schema migration;
- structural type normalization;
- typed path resolution;
- action and observation completeness checks;
- language-neutral stable-identifier validation;
- compatibility classification;
- canonical lock serialization.

`emit` hides target syntax, imports, native type mapping, generated runtime
validation, target identifier lowering/collision checks, and stable formatting.

Four language emitters provide a real internal seam. Their common input is the
locked IR; no emitter independently interprets TLA+ or traces.

## 15. Validation pipeline

```text
1. Resolve model + companion contract into the locked IR.
2. Generate the model-specific port and StateComputer binding.
3. Require a clean regeneration diff in CI.
4. Let the LLM implement the generated port against the real SUT.
5. Compile the adapter against the generated interface.
6. Exercise the binding with a recording fake adapter.
7. Preflight real traces against the locked schema.
8. Replay real traces through Mirrors and the real SUT.
9. Require declared-action coverage or report explicit gaps.
```

### 15.1 Generated binding tests

The recording adapter verifies:

- exact action dispatch;
- input decoding and missing/type error paths;
- initialization before transition;
- reset on each new trace;
- exactly one operation followed by exactly one observation;
- no observation after operation failure;
- observation encoding and key completeness;
- unknown-action and poisoned-binding behavior.

### 15.2 Trace preflight

For every supplied trace:

- state zero uses a declared initializer;
- later states use declared transition actions;
- every seen parameter and state value satisfies the resolved schema;
- every seen action is declared;
- declared but unseen actions are recorded as coverage gaps.

### 15.3 Real SUT replay

The generated binding is passed as the ordinary client `StateComputer`.
For each model step it decodes the stimulus, calls the LLM-written adapter,
observes the real SUT, encodes the observation, and lets Mirrors compare it
with the trace.

A passing real trace validates that execution. It does not prove that all
actions, parameter combinations, or reachable states are covered. CI should
use multiple generated traces or symbolic exploration in addition to the
per-action coverage gate.

## 16. Versioning and compatibility

- Version the companion-contract schema separately from each model interface.
- Preserve stable action and observation IDs independently from target names.
- Permit wire-label aliases only when explicitly declared.
- Treat adding a required action as a breaking interface change: exhaustive
  adapters must implement it.
- Treat removing an action, removing a required observation, or changing a
  type incompatibly as breaking.
- Conservatively classify parameter narrowing and required-field additions as
  breaking.
- Embed source, contract, lock, and generator digests in generated files.
- Make the standalone read-only `check` command fail when committed output is
  stale.

## 17. Dependency strategy

| Dependency | Category | Design |
| --- | --- | --- |
| Contract validation, type normalization, path resolution, canonical IR | In-process | Pure module tested directly through `resolve` |
| Target emitters | In-process | One emitter adapter per target, tested from locked fixtures |
| Source/contract/lock filesystem access | Local-substitutable | Thin shell; tests use in-memory files |
| Apalache type evidence | True external | Injected type-evidence port; production process adapter and pinned fixtures in tests |
| Local SUT | In-process or local-substitutable | LLM-written production adapter plus recording fake adapter |
| Owned remote SUT | Remote but owned | Generated port at the seam; HTTP/process adapter in production, in-memory adapter in tests |
| Third-party SUT | True external | Production adapter plus mock adapter |
| Mirrors transport | Remote but owned | Reuse existing client transport interfaces; do not absorb transport into generated bindings |

## 18. Repository placement

An implementation should preserve the current proof/effect split:

```text
Core/ModelInterface.lean
    Pure locked-IR model, validation rules, and completeness predicates

Codec/ModelInterfaceJson.lean
    Companion-contract and lock codecs

Shell/ModelInterface/
    Source loading, filesystem output, and Apalache evidence resolution

tools/ModelInterfaceGen.lean
    resolve / scaffold / generate / check / preflight commands

test/fixtures/model-interface/
    contracts, locks, typed evidence, and expected generated output

Docs/model-interface-generation-design.md
    This design
```

Pure contract behavior belongs in `Core/` and wire encoding in `Codec/`.
Filesystem, process, and generator CLI effects remain in `Shell/` and `tools/`,
outside the proof boundary.

The formal claim should remain precise:

- Lean can prove pure lock and observation-completeness properties;
- generated language code is checked through deterministic fixtures,
  compilation, and interop tests;
- the LLM adapter and real SUT remain external oracles exercised by real
  traces.

## 19. Rollout

### Phase 1: Counter vertical slice

1. Define the JSON contract and locked IR for Counter.
2. Resolve types from existing Counter type evidence.
3. Implement a TypeScript emitter and generated `CounterPort` binding.
4. Replace one test-only MirrorECMA Counter computer with an adapter around a
   real Counter implementation.
5. Gate with recording-adapter tests and real Counter traces.

### Phase 2: second language proves the seam

1. Add the C++ emitter from the same lock.
2. Implement `CounterPort` in MirrorCPP.
3. Require byte-equivalent stimulus/observation fixture behavior between
   TypeScript and C++.

Two independent target adapters make the emitter seam concrete and expose
language-neutral IR mistakes early.

### Phase 3: Rust and Lean

Add the remaining emitters without changing contract semantics. Run each
client's canonical corpus plus the top-level interop matrix.

### Phase 4: scaffolding and coverage

Add trace-assisted contract scaffolding, action-coverage reports, compatibility
classification, and optional action-witness generation. Scaffolding must never
seal inferred actions without explicit confirmation.

### Phase 5: optional async profile

If real remote SUTs require it, introduce an additive asynchronous computer and
generated async ports. Do not overload the synchronous `StateComputer` with
target-specific blocking semantics.

## 20. Acceptance criteria

1. Given identical sources, contract, lock, generator version, and target
   profile, generated output is byte-identical.
2. Counter generates type-correct interfaces for TypeScript and C++ from one
   lock.
3. The generated adapter never exposes expected transition state or
   `prevState` through the implementation port.
4. Missing, mistyped, extra, and unobservable comparison fields fail before a
   misleading conformance success.
5. Unknown actions and transition-before-initialization fail deterministically.
6. A recording adapter tests exact dispatch and observation ordering.
7. A correct real Counter adapter passes real generated traces.
8. A deliberately incorrect observation produces Mirrors'
   `step_mismatch`, not a binding error.
9. Coverage reports distinguish passing traces from complete declared-action
   exercise.
10. Existing handwritten `StateComputer` callers remain source-compatible.
11. The existing full client interop matrix remains green.

## 21. Resulting seam

```text
real implementation
        ^
        |
LLM-written model-specific port adapter
        ^
        |  initialize / actions / observe
deterministically generated deep binding
        ^
        |  existing StateComputer
MirrorECMA / MirrorCPP / MirrorRust / MirrorLean
```

The deterministic generator owns everything mechanical. The LLM owns only the
mapping that genuinely requires implementation knowledge. Real trace replay
then validates the generated binding, the LLM adapter, and the SUT together.
