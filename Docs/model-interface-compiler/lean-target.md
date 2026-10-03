# Lean generated model-interface target

`mirrorlean-v1` is the synchronous Lean 4 target for the portable generated
interface contract. It emits `<Model>Mirror.lean` and the compiler-owned manifest
through the same publication and freshness-check seam as the other targets.
The generated namespace is `<Model>Mirror`; the SDK dependency is
`MirrorLean.ModelInterface`.

## Native representation

| Model type | Generated Lean carrier |
| --- | --- |
| Integer, Boolean, string | `Int`, `Bool`, `String` |
| Null | `MirrorNull` |
| Sequence, set | Distinct `MirrorSeq α` and `MirrorSet α` wrappers |
| String-keyed map | `MirrorMap α`, with checked semantic key uniqueness |
| Tuple, closed record, closed variant | Generated nominal structures or inductive types |

Structural codecs validate model values before entering application callbacks and
validate observations before returning reports. Null, empty tuple, and empty
record have distinct native carriers. Sets use semantic uniqueness rather than
incidental array identity. The initial profile rejects opaque values,
integer-keyed maps and unsupported paths during generation; it does not silently
erase their semantics. See the [portable type contract](../generated-model-interface-spec.md).

## Generated binding

The generated module exposes immutable metadata, the semantic digest, one input
structure per action, an `Observation` structure, a `Port`, and `bind`. Action
methods use quoted Lean identifiers, including `«initialize»`. Input and
observation members derive from stable IDs; nested structural fields use stable
generated names such as `field0` and `case0`.

Port actions and observation return classified `IO (Except BindingError …)`
results. The binding exposes `computer`, `coverage`, `assertAllActionsCovered`,
and `toLocalBinding`. It ignores the legacy previous-state argument. Every input
is projected and decoded before the action runs, observation follows the action,
and coverage advances only after a complete report. An initializer resets a
trace; a transition before initialization, reentrant call, invalid input, failed
handler or failed observation poisons the binding. Poisoned bindings make no
further application calls.

`toLocalBinding` supplies the SDK replay and disposal seam; the compiler does not
generate a transport stack or the application implementation. Applications remain
responsible for actual state, reset, observation accuracy and resource release.

## Negotiated client integration

MirrorLean's additive `ModelInterface` API keeps the existing `StateComputer`,
`MirrorError`, and legacy wire APIs intact. `CompiledAdapterSelection` selects an
exact immutable `(semanticDigest, adapterId, targetProfile,
stateComputerContractVersion)` registration. Local metadata and registry checks
precede opening a connection or starting a process. A required `matched` reply
precedes factory/SUT construction; malformed or mismatched replies invoke no
factory. This initial static profile offers required verification, not implicit
legacy fallback.

The negotiated path adds bounded duplicate-aware JSON admission and classified
binding/registration failures, then shares the legacy replay dispatcher for
terminal, mismatch and report behavior. Acquired bindings are disposed on success
and failure. The server-mode TLS adapter validates the configured peer pin;
acceptance receipts call it `validatedServerPin`, rather than claiming the SDK
exposes a separately observed peer-fingerprint value.

## Validation entry points

- [`ModelInterfaceLeanSpec.lean`](../../tools/ModelInterfaceLeanSpec.lean) checks
  deterministic generation, owned fixture freshness and rejected profiles.
- [`tools/model-interface-lean/check.sh`](../../tools/model-interface-lean/check.sh)
  compiles generated Counter and structural types against a fresh SDK source
  copy, runs binding/lifecycle tests, and requires invalid native examples to
  fail compilation.
- [`tools/model-interface-conformance/`](../../tools/model-interface-conformance/)
  runs shared judgment, value, equivalence, projection and recording vectors
  through real generated language consumers.
- The sibling [SDK tests](../../../MirrorLean/test/ModelInterface.lean) cover
  strict negotiation, deferred factories, errors, disposal and native codecs.
- [`run-generated-lean.py`](../../tools/interop/run-generated-lean.py) builds a
  fresh native consumer and executes source-hidden stdio, TCP-denial and owned
  Windows mTLS cases. The [top-level generated-client entry](../../tools/interop/INTEROP.md)
  combines those receipts with Rust and the shared six-profile corpus.

Generated source/native checks, transport acceptance, installed-consumer evidence
and release qualification are separate claims. Record exact inputs and receipts
when running the transport matrix; an earlier generic Lean validation row does
not establish generated-binding acceptance.
