# Application integration contracts

Status: **AIT-00 contract accepted for implementation, 2026-09-16**.
This document specifies new interfaces; it does not claim that they are
implemented. The [design](application-integration-design.md) remains the product
authority. The coordinating parent accepted the corrected contract on 2026-09-16;
downstream tasks may implement it in ledger dependency order. Baselines inspected: Mirrors `424b68a`, MirrorECMA `008234d`,
MirrorGate `67e70b9`. No runtime change is part of AIT-00.

Every record below is closed: reject unknown keys, duplicate keys, invalid
Unicode, unsafe integers, NaN/infinity, cycles, accessors and non-plain records
in inert declarations. Optional means absent, not null, unless a union
explicitly includes null. No record below adds a field to an existing closed
control v1/v2, worker v1 or Mirrors protocol record.

## 1. Ownership and version axes

| Contract/export | Producer and implementation owner | Version/compatibility rule |
| --- | --- | --- |
| `SuiteModel<Port>`, `<Model>Model` companion, native bridge | Mirrors AIT-01/02 compiler emits; MirrorECMA AIT-04 exports the structural type | `mirrors.suite-model/v1`; async target only |
| Bundle publication: `bundle`/`check --bundle` grammar, owned files, `.mirrors-suite-bundle.json` | Mirrors AIT-03 | `mirrors.suite-bundle/v1` |
| Native adapter representation | Mirrors bridge; Gate public kit/proxy | `mirrors.node-native-port/v1` |
| `ConstructionScope`, `SuiteLocalBinding`, `LocalImplementation` | MirrorECMA AIT-08 lifetime helper | Local API under `mirrorecma.suite/v1`; no wire extension |
| `SuiteDefinition`, `defineSuite`, `ReplayPlan`, `AcceptanceRequirements` | MirrorECMA AIT-04; trusted evaluator supplies declarations | `mirrorecma.suite/v1`, `mirrorecma.replay-plan/v1`, `mirrorecma.acceptance/v1` |
| `MatchedEvidence` | MirrorECMA AIT-05 replay tracker, never adapter-authored | `mirrorecma.matched-evidence/v1` |
| `evaluateAcceptance`, `AcceptanceAssessment` | MirrorECMA AIT-06 pure evaluator | Assessment carried by the suite result |
| `runSuite`, `runSuiteWithFactory`, `SuiteResult`, `SuiteRun` | MirrorECMA AIT-07 | `mirrorecma.suite-result/v1` |
| Public adapter kit | Gate AIT-09/10 from the sanitized manifest | `mirrorgate.adapter-kit/v1`, profile `node-native-esm/v1` |
| Preparation/authoring profile | Gate AIT-11 from admitted operator policy | `node-esm/v1` |
| Hosting environment delivery | Gate AIT-12; controller produces, host consumes | Control **3**, capability `hosting.public-environment-v1`, record `mirrorgate.public-environment/v1` |
| `mirror.project.json`, `loadProject` | Evaluator authors; MirrorECMA AIT-15 validates; AIT-17 `init` seeds a template | `mirrorecma.project/v1`; exported from `mirrorecma/project` |
| `evaluateSuite`, trusted receipt persistence | Gate AIT-13/14 integration | Suite result retained alongside the existing Gate receipt; no receipt v1 mutation |

Existing independent identities stay independent: semantic digest, semantic
interface version, descriptor schema/resolver/comparison policy, source closure
and provenance digest, compiler identity, selected corpus and run configuration,
bundle bytes, implementation source/artifact, native representation, runtime,
public kit, and transport/control versions. A semantic digest identifies the
resolved observable interface, not hidden invariants, source revision, corpus,
implementation, behavior correctness, or toolchain compatibility.

The exact adapter key remains `(semanticDigest, adapterId, targetProfile,
stateComputerContractVersion)` as in
[adapter-registry.ts](../../MirrorECMA/src/adapter-registry.ts#L49). The handle
fixes `targetProfile = "mirrorecma-async-v1"` and
`stateComputerContractVersion = "mirrors.async-state-computer/v1"`; a suite
cannot override either. Default adapter ID is `suite-local/v1`; an evaluator
may select another stable ID once in the suite declaration. Bundle/profile
versions are not new registry target identities. MirrorECMA core has no Gate
import, session type, public-output policy, or physical-cleanup controller.

## 2. Common validation and identity rules

All new JSON records below are closed, recursively; reject unknown keys,
duplicate JSON keys, invalid Unicode, unsafe integers, NaN/infinity, cycles,
accessors and non-plain records in inert library declarations. Optional means
absent, not null, unless a union explicitly includes null. Reject unsupported
schema/profile before acquiring a connection or implementation. Existing imported
protocol/descriptor records keep their own validators and semantics.

All new arrays are ordered. Snapshot inert data deeply; caller mutation after
`defineSuite` cannot change a run. Generated function references are trusted and
retained, never serialized or invoked by definition validation. JSON records
with ordinary keys such as `__proto__` use own-property-safe construction.

| Primitive/collection | Bound and encoding |
| --- | --- |
| `Id` | Nonempty Unicode string, no NUL, at most 256 UTF-8 bytes; stable action IDs additionally must exist in descriptor |
| `Sha256` | Exactly 64 lowercase hexadecimal characters; no `sha256:` prefix |
| `Count` | Integer 0 through `Number.MAX_SAFE_INTEGER`; overflow is evidence failure, never saturation |
| Path/reference | Nonempty, no NUL, at most 4096 UTF-8 bytes; project-relative local paths resolve at project file |
| Suite/project/config input | At most 1 MiB decoded JSON, depth 64, 65,536 nodes; lower wire/backend limits still apply |
| Corpus occurrences | 1 through 4096; every trace nonempty; repeated references permitted |
| Required actions/pairs | At most 1024 actions and 4096 ordered pairs; duplicates rejected, initializer IDs rejected |
| Optional diagnostic text | At most 4096 UTF-8 bytes per error, 64 errors; truncation marked explicitly |
| Timeouts | Positive safe integer milliseconds, maximum 3,600,000 per field |

These are new suite limits, not permission to exceed the current registration
frame or backend limits. Oversized encoded registration fails before connection
acquisition; no automatic batching that changes replay/reset semantics.

`FileIdentity = {logicalPath: string, sha256: Sha256}`; logical paths are
canonical relative slash paths without `.`/`..`, NUL, backslash or prefix
collisions. `ModelIdentity = {sources: readonly FileIdentity[], contractSha256:
Sha256, evidenceSha256: Sha256, provenanceDigest: Sha256}`. Sources are sorted
by logical path; provenance fields retain compiler meanings.

`CorpusIdentity = {sha256: Sha256, occurrences: readonly Sha256[]}`. Hash each
trace's exact checked bytes, then hash canonical JSON of the ordered occurrence
hash array; repeated occurrences remain repeated. This is byte identity, not
semantic ITF equivalence. `configSha256` hashes canonical JSON of the normalized
run configuration plus explicit spec-reference identity, preserving absent versus
null predicate semantics. Canonical JSON here sorts object keys by Unicode code
point, preserves array order, uses compact JSON escaping and finite integer
decimal tokens, UTF-8 without BOM or trailing newline. Strings are not Unicode
normalized. Use the existing canonical descriptor algorithm for semantic digest,
not this artifact algorithm. Hashes authenticate no untrusted producer by themselves.

## 3. Exact suite and replay shapes

The following notation defines closed records; `readonly` applies recursively.
Imported types are current public MirrorECMA `GeneratedModelInterface`,
`SemanticDescriptor`, `ApalacheConfig`, `AsyncLocalBinding`,
`AsyncAdapterFactory`, `AsyncNegotiationAuthority`, and `AsyncActionContext`.
`Port` is the compiler's generated Node-native operation object: the same
structural shape as the current worker author adapter `{actions, observe,
dispose?}` ([node-worker.md](../../MirrorGate/docs/node-worker.md#L14)), not the
existing array-shaped async port. Gate providers already produce a compiled binding and
bypass this bridge.

```ts
interface SuiteModel<Port> {
  schema: "mirrors.suite-model/v1";
  metadata: GeneratedModelInterface;
  descriptor: SemanticDescriptor;
  modelIdentity: ModelIdentity;
  bundleSha256: Sha256;
  targetProfile: "mirrorecma-async-v1";
  stateComputerContractVersion: "mirrors.async-state-computer/v1";
  representation: "mirrors.node-native-port/v1";
  bindNative(port: Port, config: ApalacheConfig): AsyncLocalBinding;
}
interface AcceptanceRequirements {
  schema: "mirrorecma.acceptance/v1";
  requiredActions: readonly Id[];
  requiredPairs: readonly (readonly [Id, Id])[];
}
type SpecReference =
  | {kind: "local"; path: string; sources: readonly FileIdentity[]}
  | {kind: "server"; path: string; sources: readonly FileIdentity[]};
type TraceReference =
  | {kind: "local"; path: string; sha256: Sha256}
  | {kind: "server"; path: string; sha256: Sha256};
interface ReplayPlan {
  schema: "mirrorecma.replay-plan/v1";
  kind: "corpus";
  spec: SpecReference;
  config: ApalacheConfig;
  configSha256: Sha256;
  traces: readonly TraceReference[];
  corpus: CorpusIdentity;
}
interface SuiteDefinition<Port> {
  schema: "mirrorecma.suite/v1";
  id: Id;
  adapterId: Id;
  model: SuiteModel<Port>;
  replay: ReplayPlan;
  acceptance: AcceptanceRequirements;
}
```

`defineSuite({id, model, replay, acceptance?, adapterId?})` is the only public
constructor; omission of acceptance normalizes to the versioned empty arrays.
Explicit input acceptance may omit either array, normalizing it to empty; it
has no schema key. Returned AcceptanceRequirements always contains schema and
both arrays. The input itself has no `schema`
field; the returned definition does. There is no mutable registry/transport in
it. Definition validation checks handle metadata/descriptor/digest/profile
agreement, config identity, reference/occurrence hash alignment, stable ID
membership and supported type shapes. File reads, corpus preflight and hash
verification occur in `loadProject`/run preparation, before the factory.

`ApalacheConfig` retains the existing exact fields
([protocol.ts](../../MirrorECMA/src/protocol.ts#L97)): required `specPath`,
`invariant`, `lengthBound`; optional `initPredicate`, `nextPredicate`,
`constInit` (string or null), and `paramVars` (string). `lengthBound` is a
nonnegative safe integer, not a timeout or a trace truncation request. Normalize
only path resolution; do not guess predicate/parameter names. `config.specPath`
must equal the resolved `spec.path`. Local model source closure must agree with
handle provenance; corpus generation provenance remains separately recorded in
the project lock and cannot be inferred from the selected config.

Local references mean files accessible to the selected owned local Mirrors
process; pass verified absolute paths. Server references mean paths in an
explicit remote service namespace; never resolve them against the local project
or upload local content implicitly. Mixing local and server reference kinds is
invalid. Existing `register_traces` carries only `itfTracePaths`, not inline trace
bytes ([protocol.ts](../../MirrorECMA/src/protocol.ts#L119)).

**Remote v1 admission constraint:** current path registration supplies no remote
byte-identity/preflight attestation. The new strict suite profile therefore
rejects server references with `remote_corpus_verification_unavailable` before
connecting unless a separately approved remote verification contract is added.
The declaration preserves remote intent and produces an actionable diagnostic;
it does not pretend local preflight proves remote bytes. AIT-15 must implement
this rejection; remote suite execution is a named follow-up blocker requiring
Mirrors transport/identity design beyond this backlog. Existing low-level remote
and inline-spec APIs keep their semantics. No implicit download/upload, no
fabricated remote binary identity, and no model-generation fallback is allowed.

The runner entry points fixed by this contract are:

```ts
defineSuite(input: {
  id: Id; model: SuiteModel<Port>; replay: ReplayPlan; adapterId?: Id;
  acceptance?: {requiredActions?: readonly Id[]; requiredPairs?: readonly (readonly [Id, Id])[]};
}): SuiteDefinition<Port>;

runSuite(suite: SuiteDefinition<Port>, options: {
  mirror: SuiteMirrorTarget;                      // existing owned per-run target
  implementation: LocalImplementation<Port>;      // section 6
  timeouts?: Partial<SuiteTimeouts>;              // section 6
  signal?: AbortSignal;
}): Promise<SuiteResult>;

runSuiteWithFactory(suite: SuiteDefinition<Port>, context: {
  mirror: SuiteMirrorTarget; timeouts?: Partial<SuiteTimeouts>; signal?: AbortSignal;
}, factory: AsyncAdapterFactory): Promise<SuiteRun>;
```

`SuiteMirrorTarget = string | Transport`, using the existing public Transport
interface. A string selects the binary; a supplied transport transfers exclusive
per-run ownership and is closed by that run, as in the compiled runner. This
adds no parallel transport or shared-transport inference. `runSuiteWithFactory` accepts the existing generic
`AsyncAdapterFactory = (config, authority) => AsyncLocalBinding | Promise<...>`
([adapter-registry.ts](../../MirrorECMA/src/adapter-registry.ts#L84)); the
privileged matched authority is passed only to that trusted factory, after
negotiation.

## 4. Matched evidence and acceptance

```ts
interface MatchedEvidence {
  schema: "mirrorecma.matched-evidence/v1";
  replayEntered: boolean;
  corpusCompleted: boolean;
  exact: boolean;
  tracesSelected: Count;
  tracesStarted: Count;
  tracesCompleted: Count;
  initialStatesMatched: Count;
  transitionsMatched: Count;
  statesReported: Count;
  requiredActionCounts: readonly {id: Id; count: Count}[];
  requiredPairCounts: readonly {from: Id; to: Id; count: Count}[];
  uncertainty: readonly ("mapping" | "protocol" | "counter_overflow" |
    "missing_ack" | "missing_tracker")[];
}
interface AcceptanceAssessment {
  assessment: "met" | "unmet" | "incomplete" | "not_evaluated";
  missingActions: readonly Id[];
  missingPairs: readonly (readonly [Id, Id])[];
  reason: "requirements_met" | "coverage_unmet" | "replay_incomplete" |
    "evidence_unavailable" | "replay_not_entered";
}
```

Evidence arrays contain exactly one entry for each declared requirement, in
requirement order; zero is meaningful only when `exact` is true. Uncertainty
codes are unique in the order above, at most five. `exact` means the completed
prefix's required counters are authoritative, not that the corpus completed.
On evidence loss retain established prefix counts with `exact:false`; never
convert unknown coverage into absence. These counters are separate from optional
bounded general diagnostic maps. Their memory is bounded by declaration limits,
not a rolling event window.

Pure `evaluateAcceptance(requirements, evidence)` validates nonnegative counts,
requirement alignment and logical consistency: completed <= started <= selected,
matched initializers <= started, and full completion requires all selected
initializers matched. Impossible evidence is rejected as an evidence-validation
error, not assessed as unmet. The runner turns that rejection into an evidence
failure. Empty requirements still require full matching replay.

| Condition (in order) | Assessment | Missing arrays |
| --- | --- | --- |
| Replay never entered | `not_evaluated` / `replay_not_entered` | Empty |
| Replay interrupted, including mismatch | `incomplete` / `replay_incomplete` | Empty |
| Full replay but uncertain essential evidence | `incomplete` / `evidence_unavailable` | Empty |
| Full replay, exact counters, any required count zero | `unmet` / `coverage_unmet` | Exactly proven zeros, declaration order |
| Full replay, exact counters, all requirements positive | `met` / `requirements_met` | Empty |

A pending observation is established only after a successfully sent report. A
committed initializer increments `initialStatesMatched`, resets adjacency, and
never enters transition coverage. A committed transition increments its stable
action counter; a pair counts only between consecutive committed transitions
within the same trace. Map wire labels/aliases through the immutable negotiated
descriptor; ambiguous/unknown mapping fails evidence. Never expose that mapping
to the implementation.

The first `initial_state` invokes the declared initializer exactly once through
the generated computer, with its initial payload and empty previous state. The
factory does not initialize, observe, or count coverage itself. Each subsequent
`initial_state` resets through the same generated initializer dispatch, reusing
the binding; do not call the factory per trace. Evidence:

- [replay-core.ts:110](../../MirrorECMA/src/replay-core.ts#L110) calls
  `recorder.begin(true)` for each `initial_state`;
  [replay-core.ts:115](../../MirrorECMA/src/replay-core.ts#L115) dispatches
  `execution.start(action, state, {})` once, then
  [replay-core.ts:126](../../MirrorECMA/src/replay-core.ts#L126) records
  `reported` after sending the observation. `reported` is not acceptance.
- [Counter generated binding:383](../test/fixtures/model-interface/counter/generated-async/CounterMirror.generated.ts#L383)
  maps wire `init` to
  [port.initialize at line 387](../test/fixtures/model-interface/counter/generated-async/CounterMirror.generated.ts#L387);
  generated coverage is local invocation evidence, not server acknowledgement.
- [Session.lean:582](../Shell/Mirror/Session.lean#L582) sends initial state for
  index zero, [Session.lean:608](../Shell/Mirror/Session.lean#L608) compares the
  report, and [Session.lean:623](../Shell/Mirror/Session.lean#L623) emits
  `step_ok` on every match, including before the final
  [all_steps_done at line 625](../Shell/Mirror/Session.lean#L625).
- [Core/Protocol.lean:150](../Core/Protocol.lean#L150) models the terminal match
  as `all_steps_done` ([line 152](../Core/Protocol.lean#L152)); the shell also
  emits the compatibility `step_ok`. Both layers must be respected; they are not
  contradictory acknowledgement counts.
- [replay-report.ts:178](../../MirrorECMA/src/replay-report.ts#L178)
  acknowledges only on a subsequent begin and records action/pair counts at
  `reported` time ([line 191](../../MirrorECMA/src/replay-report.ts#L191)).
  Those maps must not be relabeled matched. The existing completed report
  acknowledges pending state at
  [line 218](../../MirrorECMA/src/replay-report.ts#L218); the new tracker is
  independent.

`all_steps_done` is authoritative terminal acceptance: commit any still-pending
observation once, then require preflight state/trace counts to agree before
marking the full corpus complete. With preceding `step_ok`, it commits nothing
again. `next_step`/`initial_state` can acknowledge a pending predecessor only
where the existing protocol's serial progression establishes acceptance; record
that rule explicitly in AIT-05 tests. Unexpected ordering, duplicate terminals,
extra states, missing selected occurrences, mismatch, EOF, timeout or cancellation
never manufacture completion. A report sent followed by EOF contributes only
reported count; a final ack followed by EOF preserves that matched prefix but
not full completion. An initialization-only nonempty trace is valid and creates
zero transition/pair coverage.

## 5. Suite result and cleanup evidence

The additive `SuiteResult` view keeps existing wire messages, `ReplayReport`,
`CompiledReplayReport` and Gate receipt schemas unchanged. Coordinates in this
view are zero-based trace index and zero-based state index with initialization at
state 0; one-based progress-report indices are normalized on the way in, and the
original report bytes/coordinates remain in trusted raw evidence.

```ts
type SuiteOutcome = "passed" | "mismatch" | "failed" | "cancelled" | "timedOut";
type ConformanceAssessment = "matched" | "mismatch" | "incomplete" | "not_evaluated";
type SuiteFailureStage =
  | "configuration" | "negotiation" | "model_generation" | "transport"
  | "implementation_execution" | "value_validation" | "acceptance"
  | "evidence" | "cleanup";
interface BoundedErrorSummary {
  name: string;              // <= 256 UTF-8 bytes; "Error" when unavailable
  code?: string;             // stable machine code from the failure source, <= 256 bytes
  summary: string;           // <= 4096 UTF-8 bytes; truncation marked explicitly
}
interface LocalCleanupEvidence {
  status: "not_started" | "completed" | "failed" | "unconfirmed";
  failures: readonly BoundedErrorSummary[];          // <= 64
}
interface PhysicalCleanupEvidence {                  // Gate owner only
  status: "confirmed" | "failed" | "unconfirmed";
  remainingResources: readonly string[];             // <= 64 entries, <= 4096 bytes each
  failures: readonly BoundedErrorSummary[];          // <= 64
}
interface SuiteCounts {
  tracesSelected: Count;
  tracesStarted: Count;
  tracesCompleted: Count;
  initialStatesMatched: Count;
  transitionsMatched: Count;
  statesReported: Count;                             // reported, not matched
}
interface SuiteFailure {
  stage: SuiteFailureStage;
  kind: string;              // stable per-stage code, never derived from message text
  code?: string;             // raw protocol/program code when one exists
  summary: string;           // BoundedErrorSummary bounds
}
interface SuiteResult {
  schema: "mirrorecma.suite-result/v1";
  outcome: SuiteOutcome;
  conformance: ConformanceAssessment;
  acceptance: AcceptanceAssessment;
  failure?: SuiteFailure;
  suiteId: Id;
  identity: {
    semanticDigest: Sha256;
    bundleSha256: Sha256;
    model: ModelIdentity;
    corpus: CorpusIdentity;
    configSha256: Sha256;
    adapterId: Id;
    targetProfile: "mirrorecma-async-v1";
    stateComputerContractVersion: "mirrors.async-state-computer/v1";
  };
  counts: SuiteCounts;
  coverage: MatchedEvidence;                          // exact matched requirement counters
  cleanup: {local: LocalCleanupEvidence; physical?: PhysicalCleanupEvidence};
}
interface SuiteRun {                                  // trusted generic seam only
  result: SuiteResult;
  report?: CompiledReplayReport | ReplayReport;        // unmodified low-level report
}
```

Conformance is `matched`, `mismatch`, `incomplete` or `not_evaluated` and is
kept separate from acceptance. `runSuite` resolves to a structured `SuiteResult`
after cleanup for ordinary operational failures; invalid inert programmer or
configuration input may reject before any run is acquired. Low-level runners keep
their current exception behavior. `SuiteRun.report` is absent when failure precedes report creation; never fabricate
a low-level report. It is trusted-side data and is
never part of the Gate public projection.

| Condition (in precedence order) | `outcome` | Notes |
| --- | --- | --- |
| Model comparison mismatch established | `mismatch` | Conformance `mismatch`; acceptance `incomplete`/`replay_incomplete`; only this kills a behavioral mutant |
| Cancellation before completion | `cancelled` | Conformance/acceptance reflect the interrupted prefix |
| Deadline exceeded before completion | `timedOut` | Same; `failure.stage` names the deadline stage |
| Any other structured non-success | `failed` | `failure.stage`/`kind` classify it |
| Conformance matched, coverage unmet | `failed` | `failure.stage: "acceptance"`, `kind: "coverage_unmet"`; matched evidence retained |
| Conformance matched, coverage met, all applicable cleanup satisfied | `passed` | Local `completed`; physical `confirmed` when present |
| Conformance matched, coverage met, cleanup failed/unconfirmed | `failed` | Primary outcome stays successful replay; cleanup evidence remains separate, never relabeled `passed` |

Failure kinds preserve these frozen minimums; AIT-07 may add kinds but never
reclassify by message text: `invalid_declaration`, `unsupported_profile`,
`operator_budget_limit` (configuration); `digest_mismatch`, `negotiation_denied`,
`negotiation_unavailable` (negotiation); `generation_failed` (model_generation);
`transport_error`, `connection_closed`, `protocol_error` (transport);
`factory_failed`, `action_failed`, `observer_failed` (implementation_execution);
`input_shape_mismatch`, `observation_shape_mismatch` (value_validation);
`coverage_unmet` (acceptance); `evidence_unavailable`, `evidence_invalid`,
`remote_corpus_verification_unavailable` (evidence); `local_cleanup_failed`,
`local_cleanup_unconfirmed`, `physical_cleanup_failed`,
`physical_cleanup_unconfirmed` (cleanup). An exception thrown by an adapter is
not automatically an infrastructure error; unknown or untrusted rejection values
keep a bounded unknown classification.

Counts keep matched and reported semantics separate. `statesReported` mirrors
attempted/reported states; `initialStatesMatched`/`transitionsMatched` are
definitive matched counters. A blocked or unacknowledged action contributes to
reported diagnostics only. `coverage` is the exact `MatchedEvidence`, including
`exact:false` uncertainty when evidence loss prevented a proven zero.

## 6. Lifetime interface: construction scope, implementation and budgets

The invariant is unchanged: exact match precedes SUT construction and evaluation
worker acquisition. The local seam is a deferred implementation factory plus a
scoped construction helper; it is not a mutable registry.

```ts
interface ConstructionScope {
  /** Register one disposer per acquired resource, immediately after acquisition. */
  register(dispose: () => void | Promise<void>): void;
}
interface SuiteLocalBinding<Port> {
  readonly port: Port;                               // Node-native operation object
  dispose?(): void | Promise<void>;                  // the one transferred cleanup obligation
}
type LocalImplementation<Port> =
  (scope: ConstructionScope) => SuiteLocalBinding<Port> | Promise<SuiteLocalBinding<Port>>;
```

1. `register` may be called only before the factory settles. A later call is a
   programming error (`late_registration`), is not admitted, and leaves that
   resource outside the helper's guarantee.
2. On factory rejection or cancellation before return, the helper disposes
   registered disposers in reverse registration order, exactly once each, under
   the independent cleanup budget; a rejecting disposer does not stop the
   remaining ones.
3. On successful return the scope seals and its obligations transfer to the run.
   The runner joins, in order, the returned `dispose` (when present) and then the
   registered disposers in reverse registration order, once each, after replay
   is sealed (or after any subsequent failure).
4. Exactly one releaser per obligation. The runner never calls `port.dispose` by
   duck typing and never calls both the returned `dispose` and a `port.dispose`
   that release the same resource; an implementation that exposes SUT cleanup on
   the port must surface it once through `dispose` or `scope.register`. Gate's
   provider handle retains its own at-most-once rule and is not a transferable
   session token.
5. Factory returns after cancellation/deadline: never admit replay; join its
   disposal under the cleanup budget; if that budget expires, local cleanup is
   `unconfirmed`, not `completed`.
6. A cooperative disposer that ignores cancellation stays `unconfirmed` when the
   budget expires; a timer cannot terminate arbitrary local JavaScript, so no
   false quiescence or physical-cleanup claim is allowed.
7. Disposer rejection is retained as bounded cleanup evidence alongside the
   primary failure and can never make a mismatching run pass. Unregistered
   arbitrary resources are explicitly outside the helper's recovery guarantee.

Current-code fact: the generated async binding's declared interface does not
include `dispose` ([CounterMirror.generated.ts:346](../test/fixtures/model-interface/counter/generated-async/CounterMirror.generated.ts#L346)),
while the runner's `AsyncLocalBinding` requires it
([adapter-registry.ts:68](../../MirrorECMA/src/adapter-registry.ts#L68));
today's consumers wrap the generated binding and supply `dispose` manually
([async-generated-counter.smoke.ts:98](../../MirrorECMA/test/async-generated-counter.smoke.ts#L98)).
The AIT-01/02 companion bridge must therefore supply the binding's `dispose` by
forwarding the `LocalBinding` obligation, and AIT-07 must not assume the
generated binding alone is an `AsyncLocalBinding`.

Budgets are execution-only; they are never stored in the suite definition.

```ts
interface SuiteTimeouts {                            // normalized record; all fields present
  registrationMs: number; actionMs: number; receiveMs: number; cleanupMs: number;
}
```

| Field | Default | Meaning | Tightening rule |
| --- | --- | --- | --- |
| `registrationMs` | 60_000 | Registration/negotiation wait | Existing compiled default |
| `actionMs` | 10_000 | Per action + complete observation + comparison | Maps to existing `deadlines.stepMs` |
| `receiveMs` | 60_000 | Receive/close waits | Existing compiled default |
| `cleanupMs` | 10_000 | Independent local cleanup budget | New; never derived from an aborted replay budget |

Defaults reuse the existing compiled runner defaults
([async-replay.ts:40](../../MirrorECMA/src/async-replay.ts#L40)). An evaluator may
set any positive safe integer within the section 2 timeout bound. Gate operator
limits are upper bounds: they may lower defaults, and the effective values are
recorded in run evidence; an explicit evaluator request above an operator limit
fails configuration validation with `operator_budget_limit`. No suite, provider
or adapter path may widen a budget above the operator limit or below the
section 2 bound.

## 7. Bundle publication: command grammar and owned artifacts

The Mirrors compiler publishes the trusted suite bundle as an additive operation
of the existing `model_interface_gen` CLI (grammar fixed; existing commands,
outputs and exit codes unchanged):

```text
model_interface_gen bundle --spec FILE --contract FILE --evidence FILE
    [--param-var NAME] --lock FILE --target mirrorecma-async-v1 --out DIR
    [--diagnostics json]
model_interface_gen check --spec FILE --contract FILE --evidence FILE
    [--param-var NAME] --lock FILE --target TARGET --out DIR
    [--bundle] [--diagnostics json]
```

- `bundle` requires `--target mirrorecma-async-v1`; other targets are rejected as
  `unsupported_bundle_target`. It requires a valid sealed lock validated exactly
  as `check` validates today; a scaffold proposal is never silently sealed and
  no corpus is generated.
- `bundle` writes only the bundle-owned paths named below inside `--out`; it
  never overwrites a non-owned file and never writes outside `--out`. Publication
  uses the existing generate discipline (sorted, deterministic, LF, exactly one
  trailing newline, no timestamps, no absolute paths, no environment data).
- `check --bundle` extends the current read-only comparison: it verifies every
  bundle-owned file byte-for-byte, the recorded hashes and the manifest schema.
  Without `--bundle`, target outputs, diagnostics and behavior are byte-identical
  to today.
- Exit codes keep the existing convention: `0` clean/success, `1` stale or
  invalid output, `2` usage or exception. No new codes.

Owned artifacts, relative to `--out` (one model per bundle; `<Model>` is the
compiler's model name exactly as used by `<Model>Mirror.generated.ts`):

| Path | Content | Owner |
| --- | --- | --- |
| `<Model>Mirror.generated.ts` | Unchanged `mirrorecma-async-v1` output | Existing async emitter |
| `.model-interface-generated.json` | Unchanged target ownership manifest (`mirrors.model-interface-generated/v1`) | Existing emitter |
| `<Model>.suite.ts` | Companion handle: imports the generated binding, exports `<Model>Model` (`SuiteModel<Port>`) and embeds canonical descriptor, public-port manifest, model identity and bundle identity | AIT-01 |
| `<Model>.descriptor.json` | Canonical descriptor data used for negotiation and bundle identity | AIT-01 |
| `<Model>.public-port.json` | Sanitized public manifest, schema `mirrorgate.port/v1`, byte-identical to the generated `export const <Model>PublicManifest` | AIT-01 |
| `.mirrors-suite-bundle.json` | Ownership manifest, schema `mirrors.suite-bundle/v1` | AIT-03 |

`.mirrors-suite-bundle.json` is closed JSON
`{schema, profileVersion, targetProfile, semanticDigest, files: [{path, sha256}]}`
with `files` sorted by path and covering every other bundle-owned file with
its actual byte hash. Bundle identity must not require a cryptographic fixed
point. The companion contains exactly one identity declaration
`const bundleSha256 = "<64 lowercase hex>" as const;` and references this
constant in its handle. Generate the companion first with 64 ASCII zeroes in
that declaration. Build an identity manifest with the exact closed shape above
and SHA-256 of each payload, including that zero-slot companion. Hash its
canonical JSON bytes plus one LF to obtain bundleSha256. Substitute the digest
into that one slot, then publish the actual ownership manifest with the final
companion hash. Verification reconstructs the zero-slot companion and identity
manifest and checks both the identity and every actual published payload hash.
The ownership manifest itself is excluded from both file lists. Its exact byte
hash is a distinct publication artifact hash, never bundleSha256. Reject a
missing, duplicated, or malformed identity slot. Canonical manifest JSON uses
the existing compiler canonical-file encoder; paths are sorted lexically.
The `<Model>.suite.ts` companion must not import Gate, must not start a process
or read files at module load, and must reject unsupported target/schema/profile
combinations before any run.

Regeneration may replace only compiler-owned files. Identical inputs must
produce byte-identical bundle bytes; existing synchronous and async target
outputs stay byte-stable, and `<Model>.public-port.json` must remain sanitized
(no model source/name/path, wire aliases, invariant selection, trace
coordinates, expected values, provenance paths or credentials beyond the
approved public stable IDs and type fields).

## 8. Public adapter kit contract

Gate generates one public kit per bundle manifest. Kit identity is
`mirrorgate.adapter-kit/v1` with profile `node-native-esm/v1`; the kit is the
only implementation-facing artifact and never contains model descriptors, raw
locks, generated evaluator source or private material.

| Path | Ownership and rules |
| --- | --- |
| `port.json` | Copy of `<Model>.public-port.json`, byte-identical; schema `mirrorgate.port/v1` |
| `PUBLIC-CONTRACT.md` | Evaluator-approved behavior prose; seeded only when absent, never overwritten by regeneration |
| `adapter.d.ts` | Generated worker-native declarations: exact stable IDs and current Node worker value representations, safely quoted object keys |
| `adapter.mjs` | Editable stub, seeded only when absent; unimplemented operations throw an explicit unimplemented-operation error; no shadow expected state |
| `check-adapter.mjs` | Public structural/codec checks: import shape, handler/observer shape, codecs, reset invocation contract, exercised disposal; never business semantics |
| `adapter-kit.json` | Closed `{schema: "mirrorgate.adapter-kit/v1", profile: "node-native-esm/v1", interfaceDigest, publicManifestSha256, files: [{path, sha256, owned}]}` sorted by path |

Generation consumes only the validated sanitized manifest plus separately
approved behavior prose, rejects unknown manifest fields and unsupported public
shapes, preserves stable IDs as string keys, and produces deterministic bytes
with an owned-file freshness check that never overwrites authored adapter or prose
files. Disclosure checks reject model/wire/provenance/trace/credential canaries
from every kit file. Kit self-tests execute submitted imports only in the
approved development sandbox for restricted work; a trusted local developer may
run their own adapter locally. The kit's checker uses exit codes `0` clean,
`1` structural failure, `2` usage or exception.

## 9. Project configuration contract

The example trace hash below is a syntactically valid placeholder and must be
replaced by the real checked trace byte hash before replay.

`mirror.project.json` is evaluator-authored, inert declaration data; it is never
exported to a restricted author and never executes code. `mirrorecma init` seeds
a template only when the destination is absent. Generation and scaffolding must
not select model predicates, bounds, corpora, acceptance requirements or
toolchain versions on the evaluator's behalf.

```json
{
  "schema": "mirrorecma.project/v1",
  "suiteId": "transfer/checked-corpus-v1",
  "model": {
    "spec": "model/Transfer.tla",
    "contract": "model/Transfer.contract.json",
    "evidence": "model/Transfer.evidence.json",
    "paramVar": "parameters",
    "target": "mirrorecma-async-v1",
    "generatedDir": ".mirrors/evaluator/transfer",
    "lock": "model/Transfer.mirror-interface.lock.json"
  },
  "replay": {
    "config": {"invariant": "Safety", "initPredicate": "Init",
      "nextPredicate": "Next", "constInit": null, "lengthBound": 20,
      "paramVars": "parameters"},
    "traces": [
      {"kind": "local", "path": "traces/resume-after-restart.itf.json",
       "sha256": "0000000000000000000000000000000000000000000000000000000000000000"}
    ]
  },
  "acceptance": {"requiredActions": ["Begin", "Commit"],
    "requiredPairs": [["Pause", "Restart"]]},
  "execution": {"mirror": "mirror",
    "timeouts": {"registrationMs": 60000, "actionMs": 10000,
      "receiveMs": 60000, "cleanupMs": 10000}},
  "toolchain": {"lock": "mirrors.toolchain.lock.json"}
}
```

| Field | Rule |
| --- | --- |
| `schema` | Exactly `mirrorecma.project/v1` |
| `suiteId` | `Id`; human-facing label, not an identity substitute |
| `model.*` | Canonical project-relative paths to the reviewed spec, contract and evidence inputs, plus the sealed lock and the supported async target and generated directory |
| `model.paramVar` | Optional; when present must equal `replay.config.paramVars` |
| `replay.config` | `ApalacheConfig` minus `specPath`; `specPath` is derived from `model.spec` (single source of truth) and must not appear here |
| `replay.traces` | Ordered 1–4096 local/server references with per-trace `Sha256`; mixing kinds is invalid |
| `acceptance` | Optional; omitting it normalizes to the versioned empty arrays. Never inferred from the interface |
| `execution.mirror` | Optional explicit tool reference resolved by AIT-16 precedence; absent means project lock then installed registry |
| `execution.timeouts` | Optional `SuiteTimeouts` (section 6); validated and passed to the runner, never stored in the suite |
| `toolchain.lock` | Optional project-relative reference; the toolchain-lock schema itself is frozen by AIT-16 |

`loadProject(url)` returns exactly
`{suiteId, replay, acceptance, execution}`. It resolves every relative path
against the project file, not the process working directory, may read files and
hash traces for preflight, and must not import application code, load the
adapter, execute a build, generate traces, download, connect, launch an agent or
rewrite user configuration. It fails honestly on malformed/unknown fields,
duplicate keys, illegal paths, bad bounds, missing corpus files, hash mismatch,
incompatible declared target and invalid requirement IDs. `server` references
parse but are rejected with `remote_corpus_verification_unavailable` before any
connection. The returned `replay` is a complete `ReplayPlan`: `spec` is derived
from `model.spec`, `config.specPath` is the resolved local spec path,
`configSha256` hashes the normalized config plus explicit spec-reference
identity, and `corpus` derives from the ordered occurrence hashes. The loader
performs preflight; `runSuite` re-verifies before invoking any factory.

The project's public surface is the `mirrorecma/project` export plus the
AIT-17 commands `init`, `doctor`, `generate`, `check` and `replay`; those commands
reuse this validation and introduce no separate coverage semantics.

## 10. Hosting environment delivery contract

Environment delivery is an explicit negotiated hosting capability on a new
closed control protocol version **3**, with the unchanged v1 bootstrap:

- New capability `hosting.public-environment-v1`; new closed record
  `mirrorgate.public-environment/v1` delivered as a versioned response extension
  in the v3 `agent.start` success result (field `environment`), and included by
  the host whenever it supplies `public_contract` to a hosted agent.
- Clients select v3 by offering `controlVersions: [3]` and requiring
  `hosting.public-environment-v1` plus their selected runtime/backend
  capabilities. No common version returns `VERSION_UNSUPPORTED` before session
  allocation; there is no silent downgrade and a v1/v2 host keeps the legacy
  brief without ever claiming the capability.
- v2 and v1 records stay closed and byte-stable. The new record is not a field
  added to any existing v1/v2 envelope, policy or task record.

```ts
interface PublicEnvironment {
  schema: "mirrorgate.public-environment/v1";
  profileId: "node-esm/v1";
  entryPoint: string;
  paths: {
    authoring: "/workspace";
    buildSource: "/source";
    buildOutput: "/output";
    runtimeWritable: readonly string[];
  };
  writablePaths: {
    authoring: readonly string[];
    build: readonly string[];
    runtime: readonly string[];
  };
  tools: readonly string[];
  limits: {
    wallMs: number;
    stdoutBytes: number;
    stderrBytes: number;
    progressRecords: number;
    progressBytes: number;
    progressRecordBytes: number;
  };
}
```

All fields are required and records closed. entryPoint is a canonical relative
path (1–4096 UTF-8 bytes, no dot segments, backslash, NUL or absolute prefix).
Stage paths are sandbox-visible absolute canonical paths only; arrays are
sorted, duplicate-free, at most 128 entries of at most 4096 UTF-8 bytes.
runtimeWritable equals writablePaths.runtime. Empty means no writable paths;
no invented profile-defined path is allowed. tools is the sorted list of admitted
broker tool IDs (at most 128, each matching the existing control PublicId).
limits is exactly the admitted managed-agent limit record from agent_policy.py:
positive integers bounded respectively by 300000, 1048576, 1048576, 256, 262144,
and 16384, further tightened by operator policy. It describes agent output/time
limits, not aggregate CPU/memory or evaluation-worker guarantees. The complete
record is limited to 64 KiB encoded UTF-8. The v3 agent.start success result
adds exactly environment to the corresponding v2 success shape; all other
operation shapes retain v2 fields with control version 3. Bootstrap stays v1.
The hosted public_contract response carries the same environment value alongside
its existing approved task and tool fields. Delivery must use actual admitted
stage facts; never disclose a host path in lieu of a sandbox path.

The record is generated by Gate from admitted operator policy, derives from the
same facts that enforce the sandbox, and contains no host paths, credentials,
private mounts or model configuration. Declared writable paths, tools or limits
never grant access; backend enforcement remains authoritative, and a declaration
that contradicts admitted policy is a defect, not an upgrade. Unknown fields are
rejected by the closed v3 schema.

Affected consumers, updated together by AIT-12:

| Consumer | Path |
| --- | --- |
| Normative doc + closed schemas | `MirrorGate/docs/agent-hosting-control-v3.md`, `MirrorGate/protocol/control-v3/{schema.json,contract.json,policy-schema.json,audit-receipt-schema.json}` |
| Python codec | `MirrorGate/supervisor/mirrorgate/control_protocol_v3.py` |
| Python policy/derivation | `MirrorGate/supervisor/mirrorgate/control_policy.py`, `agent_policy.py`, `preparation.py` |
| Python delivery | `MirrorGate/supervisor/mirrorgate/authoring_broker.py`, `authoring_mcp.py`, `agent_runtime.py` |
| Node SDK | `MirrorGate/sdk/node/control-v3.mjs`, `control-v3.d.mts`, `index.mjs` re-export |
| C++ SDK | `MirrorGate/sdk/cpp/include/mirrorgate/control.hpp`, `sdk/cpp/src/control_v3.cpp`, `CMakeLists.txt` |
| Shared vectors | `MirrorGate/conformance/control-v3/{vectors.jsonl,lifecycle.json,run}` |

## 11. Resolved questions and dependent tasks

Every AIT-00 question is resolved here; nothing below remains ambiguous for an
implementing task.

| Question | Resolution | Implemented by |
| --- | --- | --- |
| Bundle/check command grammar and owned artifact names | Section 7; additive `bundle` and `check --bundle`, fixed file set, existing exit codes | AIT-01, AIT-03 |
| Companion export and identity | `<Model>Model` export; normalized zero-slot identity manifest hash, separate from actual publication hashes (section 7) | AIT-01 |
| Public manifest handling | Stay embedded in the generated source and additionally emitted as `<Model>.public-port.json`; kit input | AIT-01, AIT-09 |
| Public kit profile and layout | Section 8; `mirrorgate.adapter-kit/v1`, `node-native-esm/v1` | AIT-09, AIT-10 |
| Construction-scope interface | Section 6; `ConstructionScope`/`SuiteLocalBinding`/`LocalImplementation` | AIT-08 |
| Project schema and `loadProject` result | Section 9; `mirrorecma.project/v1`, `mirrorecma/project` export | AIT-15, AIT-17 |
| Local/remote trace references | Local verified paths; server references rejected `remote_corpus_verification_unavailable` until an approved remote verification contract exists | AIT-15 |
| Hosting capability/schema extension | Section 10; control 3 + `hosting.public-environment-v1` | AIT-12 |
| Default replay and cleanup budgets; who may tighten | Section 6; 60/10/60 s replay defaults, 10 s independent cleanup; Gate operator limits tighten, evaluator requests above a limit fail | AIT-07, AIT-08, AIT-12 |
| Suite result shape and outcome derivation | Section 5 | AIT-07 |
| First-initializer and terminal-ack evidence | Section 4, resolved against current code with line evidence | AIT-05, AIT-07 |
| Independent identities and ownership | Section 1, sections 5–10 | All |

Named follow-ups that remain out of this backlog: remote suite execution needs
a Mirrors transport/identity contract for server-visible byte identity (AIT-15
ships the rejection); TypeScript build/package installation profiles stay
explicit future work (AIT-11 ships JS ESM only); G3 generic repair lineage, G4
terminal cleanup retrieval/durable restart and G6 extended public mismatch
disclosure keep their own designs.

## 12. Prohibited constructs

| Prohibited | Rule and enforcement | Owner |
| --- | --- | --- |
| Undefined `trusted-project.js` glue | Project input is inert JSON; the loader never imports or executes user code and never merges plan with policy | AIT-15 |
| Duplicate cleanup owner | Exactly one releaser per obligation; the runner joins local cleanup once, Gate owns physical cleanup, a provider handle is never adopted or reconnected, and local completion is never relabeled physical confirmation | AIT-07, AIT-08, AIT-14 |
| Semantic-digest overclaim | The digest identifies the resolved observable interface only; corpus, config, implementation, runtime and bundle identities stay separate fields and no acceptance claim is derived from the digest | AIT-01, AIT-07 |
| Silent source upload/download | No implicit transfer, generation fallback, sibling search or PATH substitution; server references are rejected until approved | AIT-15, AIT-16 |
| Gate import in MirrorECMA core | Ordinary MirrorECMA entry points stay Gate-free; suite convenience and receipt persistence live in the Gate integration package | AIT-07, AIT-14 |
| Fields added to closed v1/v2 records | New behavior uses new versions/capabilities (`mirrors.suite-*`, `mirrorecma.*`, control 3) rather than reopening frozen schemas | AIT-12, AIT-14 |
| Second model comparator or acceptance-as-conformance | Mirrors establishes comparison; MirrorECMA drives operations and reports matched evidence; `coverage_unmet` is a failed acceptance, never a behavioral mismatch | AIT-05, AIT-06, AIT-07 |

## 13. Reusable fixture inventory

Existing artifacts downstream tasks must reuse rather than duplicate:

| Fixture | Polarity | Purpose | Primary tasks |
| --- | --- | --- | --- |
| `Mirrors/test/fixtures/model-interface/counter/generated-async/CounterMirror.generated.ts` | positive | Async port shape, `init` dispatch, embedded public manifest, identity exports | AIT-01/02/04/07 |
| `Mirrors/test/fixtures/model-interface/counter/generated/CounterMirror.generated.ts` | positive control | Synchronous byte-stability control | AIT-01/03 |
| `Mirrors/tools/check-async-emitter.py`, `Mirrors/tools/ModelInterfaceSpec.lean` | positive/negative | Existing emitter freshness and sanitized-manifest checks | AIT-01/03 |
| `MirrorECMA/test/async-generated-counter.smoke.ts` | positive | Zero SUT construction before match, exactly-once disposal and transport close | AIT-05/07/08 |
| `MirrorECMA/test/replay-report.test.ts`, `async-replay-report.test.ts` | negative | Reported-versus-matched counters, ack timing | AIT-05/06 |
| `MirrorECMA/test/registry.test.ts`, `owned-registration-lifecycle.test.ts` | positive/negative | Exact adapter key and existing lifecycle rules | AIT-04/08 |
| `MirrorGate/protocol/manifest.schema.json` | positive | Sanitized public manifest schema `mirrorgate.port/v1` | AIT-09 |
| `MirrorGate/conformance/control-v2/vectors.jsonl` + `protocol/control-v2/schema.json` | positive control | Closed-schema/version discipline to mirror for v3 without modification | AIT-11/12 |
| `MirrorExamples/specs/Counter`, `MirrorExamples/specs/RBT` and traces | positive corpora | Real checked corpora for suite replay | AIT-07/19/20 |

New fixtures each owner must add and keep reusable (names frozen for reuse):

| Fixture | Kind | Owner |
| --- | --- | --- |
| `Mirrors/test/fixtures/model-interface/<model>/bundle/` golden + mutated inputs (stale byte, unsupported target, non-owned file) | positive/negative | AIT-01/03 |
| MirrorECMA project positives/negatives (`mirror.project.json`: unknown field, mixed refs, missing trace, hash mismatch, bad bounds, server ref) | positive/negative | AIT-15 |
| MirrorECMA suite-runner cases: coverage unmet vs mismatch vs evidence loss vs denial | negative | AIT-05/06/07 |
| MirrorECMA construction-scope cases: first/second allocation failure, cancellation before return, late binding, stalled disposer, disposer rejection | negative | AIT-08 |
| Gate kit golden, malformed manifest negatives and disclosure canaries | positive/negative | AIT-09/10 |
| Gate control-v3 vectors: capability denial, unknown-field rejection, no downgrade, environment non-widening | positive/negative | AIT-12 |
| Gate receipt negatives: existing destination, symlink, unwritable parent, cyclic/throwing values, interrupted publication | negative | AIT-13 |

## 14. Handoff

AIT-00 acceptance evidence: this document defines every exported type/example
with an owner and producer (section 1 table, sections 3–10), enumerates the
prohibited constructs and their enforcement owners (section 12), resolves the
first-initializer and terminal-acknowledgement ambiguity against current code
with file/line evidence (section 4), freezes budgets, grammar and artifact names
(sections 6–8), and lists reusable positive/negative fixtures (section 13). No
runtime source changes are part of AIT-00.

Downstream consumption:

- AIT-01/02/03 consume sections 3, 5, 7, 12.
- AIT-04/05/06/07/08 consume sections 2–6 and 11–13.
- AIT-09/10/11/12/13/14 consume sections 5–8, 10, 12–13.
- AIT-15/16/17 consume sections 3, 6, 9, 11–12.
- AIT-18–23 consume this whole contract plus the ledger's validation profiles.

Parent review accepted the corrected contract on 2026-09-16. Corrections remove
the bundle hash cycle, define the hosting environment record, avoid the existing
LocalBinding export collision, specify the transport target, and allow absent
raw reports before replay. AIT-01, AIT-04, AIT-05, AIT-09, AIT-11 and AIT-13
are ready; other tasks retain their listed dependencies. Remote v1 execution is
explicitly unsupported because the current protocol cannot attest remote corpus
bytes; local execution remains the first supported design path. This is contract
acceptance only, not executable feature completion.
