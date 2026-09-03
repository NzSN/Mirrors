# Model Interface Compiler — Detailed Design

> Status: **TypeScript/Counter vertical slice implemented in Mirrors; later
> target profiles remain planned**
> Parent design: [`model-interface-generation-design.md`](model-interface-generation-design.md)
> Runtime distribution:
> [`model-interface-runtime-distribution-design.md`](model-interface-runtime-distribution-design.md)
> Cross-language generated interface:
> [`generated-model-interface-spec.md`](generated-model-interface-spec.md)
> Scope: freeze the version-1 compiler inputs, canonical intermediate
> representation, resolver, diagnostics, TypeScript emitter, CLI behavior,
> proof claims, fixtures, and Counter vertical slice.

## 0. Implementation status

Mirrors now contains the pure model-interface types, deterministic resolver,
canonical contract/descriptor/lock codecs, pure SHA-256, strict ITF evidence
normalization, trace preflight/coverage, the `mirrorecma-v1` TypeScript emitter,
safe owned-file publication, and the standalone `model_interface_gen`
executable. Counter resolve/generate/check, generated TypeScript compilation
against MirrorECMA, a mutable recording adapter, and real session replay are
covered by the implementation gates and validation harnesses.

The version-1 TypeScript slice is the implemented target. The C++ second target
and the later shared multi-emitter abstraction remain follow-up work, as
specified by M5.

## 1. Purpose

The parent design establishes the system-level seam:

```text
real implementation
        ^
LLM-written model-specific port adapter
        ^
deterministically generated binding
        ^
existing StateComputer
```

This document specifies the compiler that produces the model-specific port and
the binding. It answers the implementation questions deliberately left open by
the parent design:

- What exact artifacts does the compiler consume?
- What facts are authoritative and what facts are only evidence?
- What is the normalized type and path language?
- How does resolution calculate the state that Mirrors actually compares?
- Which failures prevent a lock, which are target-emission failures, and which
  are trace-coverage obligations?
- Which bytes are canonical and which digests appear in generated files?
- What does the first TypeScript target emit?
- Which commands write files and which commands are safe read-only CI checks?
- What can Lean prove, and what remains runtime evidence?

## 2. Version-1 decisions

The following choices are frozen for the first implementation:

1. The companion contract is strict JSON, not YAML.
2. The companion contract explicitly declares the closed action universe.
3. Apalache/ITF type metadata supplies structural type evidence; trace sample
   values never infer or widen types.
4. The existing `StateComputer` interface remains unchanged.
5. Initializer and transition wire labels are disjoint.
6. Generated implementation ports are synchronous.
7. The implementation port exposes per-action methods plus `observe()`.
8. Every observation represents exactly one complete top-level model variable.
   Leaf-by-leaf assembly of a model variable is deferred.
9. Observation variables exactly equal the keys Mirrors compares.
10. Coverage is not stored in the interface lock. It is a separate report
    keyed by the interface semantic digest.
11. The first target profile is `mirrorecma-v1`.
12. The first emitter is implemented directly. A shared emitter seam is
    extracted when C++ becomes the second target adapter.
13. Generated source is formatted internally; no external formatter is part
    of deterministic generation.
14. The compiler is a separate Lake executable named `model_interface_gen`.
15. Normal resolution consumes pinned evidence and never requires a live
    Apalache process.

## 3. Module shape

The compiler is split into a pure deep module and a thin effectful shell:

```text
files / flags / optional external tools
              |
              v
Shell.ModelInterface
  - load strict JSON
  - resolve source closure
  - normalize raw type evidence
  - hash canonical bytes
  - atomically write generated files
              |
              v
Core.ModelInterface
  resolve(contract, evidence, run profile, provenance)
       -> lock + structured diagnostics
  preflight(lock, raw traces)
       -> coverage report + structured diagnostics
              |
              v
Shell.ModelInterface.Emit.TypeScript
  emitTypeScript(lock, target profile)
       -> generated tree + structured diagnostics
```

The pure resolver knows nothing about the filesystem, current directory,
environment, Apalache processes, or target-language syntax. The TypeScript
emitter knows nothing about TLA+ sources or raw traces. Both depend only on
normalized values.

## 4. Compiler interfaces

The following Lean-like declarations describe semantic interfaces rather than
committing to exact implementation syntax.

```lean
structure ResolveInput where
  contract       : Located ContractV1
  evidence       : ModelEvidence
  runProfile     : RunProfile
  sources        : List SourceDigest
  previousLock   : Option LockedModelInterface := none

structure CompileResult (α : Type) where
  value           : Option α
  diagnostics     : List Diagnostic

def resolve : ResolveInput → CompileResult LockedModelInterface

structure PreflightInput where
  lock             : LockedModelInterface
  traces           : List RawTraceEvidence
  requireAllActions : Bool := false

def preflight : PreflightInput → CompileResult CoverageReport

structure TargetProfile where
  id                : String
  profileVersion    : Nat

def emitTypeScript :
  TargetProfile → LockedModelInterface → CompileResult GeneratedTree
```

`CompileResult.value` is present exactly when the requested artifact is safe to
use. Warnings and obligations may accompany a value. Any error diagnostic
forces `value = none`.

Resolution accumulates independent diagnostics instead of failing at the first
semantic error. Invalid intermediate nodes carry an internal invalid marker so
later stages suppress derivative noise such as five path errors caused by one
unknown root variable.

### 4.1 Generated tree

```lean
structure GeneratedFile where
  relativePath : String
  bytes        : ByteArray
  executable   : Bool := false

structure GeneratedTree where
  files        : List GeneratedFile
```

Invariants:

- paths use `/` separators;
- paths are relative and contain neither an empty segment, `.` nor `..`;
- file paths are unique;
- files are sorted by relative path;
- version 1 never emits executable files;
- filesystem writes are outside this interface.

## 5. Input artifacts

### 5.1 Companion contract

The authoritative version-1 syntax is an object with no unknown fields. The
compiler rejects duplicate JSON object keys before semantic decoding.

```json
{
  "schema": "mirrors.model-interface/v1",
  "interfaceVersion": "1.0.0",
  "model": {
    "module": "Counter",
    "source": "specs/Counter.tla"
  },
  "wire": {
    "actionVariable": "action_taken",
    "parameterVariable": "parameters"
  },
  "initializers": [
    {
      "id": "Initialize",
      "wireAction": "init",
      "wireAliases": [],
      "inputs": []
    }
  ],
  "actions": [
    {
      "id": "Tick",
      "wireAction": "tick",
      "wireAliases": [],
      "inputs": [
        {
          "id": "Stride",
          "from": {
            "root": "stepParameters",
            "path": [
              { "field": "parameters" },
              { "field": "stride" }
            ]
          }
        }
      ]
    }
  ],
  "observations": [
    {
      "id": "Count",
      "wireName": "count",
      "provenance": "implementation"
    }
  ]
}
```

Arrays are used for actions, inputs, and observations so duplicate stable IDs
can be diagnosed with both source locations. Their source order has no
semantic meaning; canonicalization sorts them by stable ID.

#### Required fields

| Field | Rule |
| --- | --- |
| `schema` | Exactly `mirrors.model-interface/v1` |
| `interfaceVersion` | Three-component decimal semantic version string |
| `model.module` | Nonempty TLA+ module name |
| `model.source` | Normalized logical relative path; never an absolute path |
| `wire.actionVariable` | Exactly `action_taken` in version 1 |
| `wire.parameterVariable` | String or `null`; must agree with the run profile |
| `initializers` | Nonempty |
| `actions` | May be empty |
| `observations` | Must exactly classify all comparable variables |

#### Stable IDs

Stable IDs are ASCII and match:

```text
[A-Z][A-Za-z0-9]*
```

They are case-sensitive and unique within their semantic collection. They do
not contain target-language spelling. Target profiles derive native names from
stable IDs using versioned rules.

#### Wire labels and aliases

- `wireAction` is nonempty and case-sensitive.
- All primary labels and aliases form one collision-free global set.
- An alias belongs to exactly one primary label.
- Initializer labels and aliases are disjoint from transition labels and
  aliases.
- Aliases affect runtime acceptance but not the stable action identity.

#### Optional explicit type assertions

An input or observation may include `expectedType`. This is an assertion, not
a competing source of truth. When declaration evidence exists, the assertion
must normalize to the identical type. When declaration evidence is absent, an
explicit type may resolve the field but creates a `contract_asserted_type`
obligation in the result.

Trace samples alone never resolve a type.

### 5.2 Run profile

The run profile records the protocol configuration that affects trace
repartition:

```lean
structure RunProfile where
  configuredParamVar : Option String
```

For the current client interface, this is derived from
`ApalacheConfig.paramVars`: empty string becomes `none`; a nonempty string
becomes `some name`.

The contract's `wire.parameterVariable` must equal this normalized value. This
prevents a correct generated binding from being paired with a runtime config
that changes the shape of `next_step.parameters`.

Generated bindings also expose `assertCompatibleConfig` and check the same
fact at client startup.

### 5.3 Source manifest

The effectful shell resolves the root module and its `EXTENDS`/`INSTANCE`
closure. The pure resolver receives only logical identities and digests:

```lean
structure SourceDigest where
  moduleName     : String
  logicalPath    : String
  contentSha256  : String
```

Logical paths use `/`, are relative to the declared source root, and are sorted
by `(moduleName, logicalPath)`. File content is UTF-8 with CRLF normalized to
LF before hashing. The source manifest never contains local absolute paths.

### 5.4 Normalized model evidence

The pure resolver does not parse arbitrary TLA+ or invoke Apalache. An evidence
adapter normalizes supported sources into:

```lean
inductive EvidenceOrigin where
  | apalacheTypecheck
  | itfVarTypes
  | contractAssertion

structure TypeFact where
  modelPath      : ModelPath
  type           : ModelType
  origin         : EvidenceOrigin
  location       : SourceLocation

structure ModelEvidence where
  traceVars      : List String
  itfParamVars   : List String
  typeFacts      : List TypeFact
  evidenceSha256 : String
```

The initial implementation accepts raw typed ITF JSON and extracts:

- top-level `vars`;
- optional `param_vars`;
- `#meta.varTypes`;
- source locations in the evidence artifact.

Unlike [`Shell.Mirror.parseItfTrace`](../Shell/Mirror/Session.lean), the
evidence/preflight parser must preserve malformed and duplicate-key evidence.
It must not turn a missing or non-string `action_taken` into an empty string,
and it must not drop undeclared state keys before reporting them.

The Apalache type-string parser is a parser for the finite emitted type
grammar, not a general TLA+ parser.

### 5.5 Trace evidence

Full traces are intentionally excluded from `ResolveInput`. They are consumed
only by `preflight`. Consequently:

- adding traces cannot change the lock or generated source;
- coverage does not influence interface semantics;
- a lock can be generated offline from pinned structural evidence;
- real traces remain validation evidence rather than an authority for action
  completeness.

## 6. Core domain model

### 6.1 Structural type algebra

```lean
inductive ModelType where
  | int
  | bool
  | str
  | null
  | set      (element : ModelType)
  | seq      (element : ModelType)
  | tuple    (elements : List ModelType)
  | record   (fields : List ModelField)
  | map      (key value : ModelType)
  | variant  (cases : List VariantCase)
  | opaqueItf (description : String)

structure ModelField where
  wireName : String
  type     : ModelType

structure VariantCase where
  tag      : String
  payload  : ModelType
```

Type invariants:

- record field names are nonempty and unique;
- variant tags are nonempty and unique;
- record fields sort by `wireName` in canonical form;
- variant cases sort by `tag` in canonical form;
- tuple and sequence order is semantic and preserved;
- record and map remain distinct even if their concrete examples look alike;
- sets retain TLA extensional equality and do not acquire sequence ordering;
- types are finite in version 1; recursive named types are deferred;
- `#unserializable` does not inhabit a concrete resolved type;
- `opaqueItf` requires an explicit contract opt-in and is rejected by the
  `mirrorecma-v1` target unless that target profile explicitly enables it.

`null` is a value type, not field absence. Version 1 record observations are
closed and contain every declared field.

### 6.2 Paths

```lean
inductive PathRoot where
  | initialState
  | stepParameters

inductive PathSegment where
  | field        (name : String)
  | index        (index : Nat)
  | mapKey       (key : CanonicalItfLiteral)
  | variantValue (tag : String)

structure InputProjection where
  root     : PathRoot
  path     : List PathSegment
  type     : ModelType
```

Path order is semantic and is never sorted.

Version-1 root discipline:

- initializer inputs use only `initialState`;
- transition inputs use only `stepParameters`;
- `initialState` exposes only declared non-meta state variables after parameter
  repartition; it never exposes the action label or raw full oracle object;
- `stepParameters` is a record whose top-level fields are the effective
  parameter variables;
- an empty path selects the complete root value, but must still have a resolved
  type.

The first Counter slice requires only `field`. The IR reserves `index`,
`mapKey`, and `variantValue`; unsupported traversal returns a deterministic
resolver diagnostic rather than silently falling back to raw ITF.

### 6.3 Resolved actions

```lean
inductive ActionPhase where
  | initialize
  | transition

structure ResolvedInput where
  id         : StableId
  projection : InputProjection
  typeOrigin : List EvidenceOrigin

structure ResolvedAction where
  id          : StableId
  phase       : ActionPhase
  wireAction  : String
  wireAliases : List String
  inputs      : List ResolvedInput
```

Actions sort by stable ID. Inputs sort by stable ID. Alias arrays sort by wire
label. The primary wire label is never replaced by an alias during
canonicalization.

### 6.4 Resolved observations

```lean
structure ResolvedObservation where
  id          : StableId
  wireName    : String
  type        : ModelType
  provenance  : ObservationProvenance
  typeOrigin  : List EvidenceOrigin
```

Version 1 supports only `implementation` provenance. An LLM adapter may
compute an abstraction from real implementation state, but the generated
binding cannot copy a comparable value from the oracle or calculate it by
running model logic.

Each observation maps one-to-one to one complete top-level comparable model
variable. Overlapping paths and leaf-level composition are rejected.

## 7. Exact comparison schema

The resolver must reuse the existing Core semantics instead of maintaining a
similar-looking independent rule.

Let:

```text
effectiveParamVars =
  unique(itfParamVars ++ configuredParamVar.toList)

requiredObservationVars =
  traceVars
    - effectiveParamVars
    - every root name k for which Core.Value.isMetaKey(k) is true
```

`Core.Value.isMetaKey` is root-only. A top-level variable named `parameters`
is filtered even when it is not the configured parameter variable; a nested
record field named `parameters` remains compared.

For a concrete trace, preflight additionally checks the actual pipeline:

```lean
let processed := applyParamVars configuredParamVar.toList trace
let steps := traceSteps processed

for step in steps do
  let actualKeys := (filterMeta step.vars).map Prod.fst
  require actualKeys.toFinset = requiredObservationVars.toFinset
```

The contract is complete exactly when:

```text
set(observations.map wireName) = set(requiredObservationVars)
```

Additional constraints:

- `traceVars`, `itfParamVars`, observation wire names, record keys, and map keys
  are duplicate-free where their semantics require unique keys;
- generated observations validate to `WfValue` and `NodupKeys` before
  encoding;
- sequences and tuples remain ordered and distinct types;
- set validation uses extensional element equality and does not impose a wire
  order as semantic state.

A missing ordinary variable is `MIC-R-OBS-001`. An extra non-comparable
observation is `MIC-R-OBS-002`. The resolver never weakens comparison or
synthesizes either side.

## 8. Locked interface

### 8.1 Shape

The lock is a normalized semantic artifact, not a cache of raw source or trace
data.

```json
{
  "schema": "mirrors.model-interface-lock/v1",
  "interfaceVersion": "1.0.0",
  "semanticDigest": "lowercase-sha256",
  "provenanceDigest": "lowercase-sha256",
  "model": {
    "module": "Counter"
  },
  "contract": {
    "schema": "mirrors.model-interface/v1",
    "interfaceVersion": "1.0.0",
    "model": {
      "module": "Counter",
      "source": "specs/Counter.tla"
    },
    "wire": {
      "actionVariable": "action_taken",
      "parameterVariable": "parameters"
    },
    "initializers": [
      {
        "id": "Initialize",
        "wireAction": "init",
        "wireAliases": [],
        "inputs": []
      }
    ],
    "actions": [
      {
        "id": "Tick",
        "wireAction": "tick",
        "wireAliases": [],
        "inputs": [
          {
            "id": "Stride",
            "from": {
              "root": "stepParameters",
              "path": [
                { "field": "parameters" },
                { "field": "stride" }
              ]
            }
          }
        ]
      }
    ],
    "observations": [
      {
        "id": "Count",
        "wireName": "count",
        "provenance": "implementation"
      }
    ]
  },
  "runProfile": {
    "actionVariable": "action_taken",
    "configuredParamVar": "parameters",
    "itfParamVars": [],
    "effectiveParamVars": ["parameters"]
  },
  "initializers": [
    {
      "id": "Initialize",
      "phase": "initialize",
      "wireAction": "init",
      "wireAliases": [],
      "inputs": []
    }
  ],
  "actions": [
    {
      "id": "Tick",
      "phase": "transition",
      "wireAction": "tick",
      "wireAliases": [],
      "inputs": [
        {
          "id": "Stride",
          "from": {
            "root": "stepParameters",
            "path": [
              { "field": "parameters" },
              { "field": "stride" }
            ]
          },
          "type": { "kind": "int" }
        }
      ]
    }
  ],
  "observations": [
    {
      "id": "Count",
      "wireName": "count",
      "type": { "kind": "int" },
      "provenance": "implementation"
    }
  ],
  "provenance": {
    "compilerVersion": "1.0.0",
    "contractSha256": "lowercase-sha256",
    "evidenceSha256": "lowercase-sha256",
    "sources": [
      {
        "module": "Counter",
        "path": "specs/Counter.tla",
        "sha256": "lowercase-sha256"
      }
    ]
  }
}
```

Coverage counts and unseen-action obligations are deliberately absent.
`preflight` stores them in a separate report.

Evidence-origin annotations remain structured compiler diagnostics. They are
not serialized into the lock or runtime descriptor because they are neither
adapter semantics nor a separately authenticated provenance projection.

The lock does serialize the exact normalized companion `contract`. This is
build metadata outside `SemanticDescriptor`, so adding it does not change the
semantic digest or the runtime-distributable descriptor. Lock v1 requires the
field. `provenance.contractSha256` is recomputed from its canonical bytes when
a lock is loaded; a missing or mutated contract therefore fails before target
emission. The provenance digest in turn authenticates `contractSha256`.

### 8.2 Semantic and provenance digests

Two digests prevent unnecessary generated-source churn:

- `semanticDigest` hashes only normalized interface semantics: module,
  interface version, run profile, actions, projections, observations, and
  resolved structural types.
- `provenanceDigest` hashes source digests, normalized contract bytes,
  normalized evidence, and compiler version.

Digest inputs are domain-separated:

```text
semanticDigest = SHA-256(
  UTF8("mirrors-model-interface-descriptor/v1")
  || 0x00
  || canonicalSemanticDescriptorBytes
)
```

The provenance digest uses its own `mirrors-model-interface-provenance/v1`
domain prefix.

The semantic projection has schema
`mirrors.model-interface-descriptor/v1`. Runtime distribution transmits this
projection, not the surrounding lock's provenance section.

Generated source embeds `semanticDigest`. A comment-only model change or a
compiler upgrade that preserves semantics may update provenance without
forcing the LLM-written adapter to change. `check` still notices a stale lock.

Each digest is computed over the appropriate canonical JSON projection with
its own digest field omitted. A digest never hashes itself.

### 8.3 Coverage report

```json
{
  "schema": "mirrors.model-interface-coverage/v1",
  "semanticDigest": "lowercase-sha256",
  "traces": 20,
  "states": 141,
  "actions": [
    { "id": "Initialize", "count": 20 },
    { "id": "Tick", "count": 121 }
  ],
  "unseenActions": []
}
```

Coverage arrays sort by stable ID. Coverage is evidence that declared actions
were exercised, not proof that all parameter or state combinations were
covered.

## 9. Canonical bytes

Canonical lock, report, manifest, and diagnostic JSON obey these rules:

1. UTF-8 without BOM.
2. LF line endings.
3. Exactly one final newline for files.
4. No insignificant whitespace in digest input.
5. JSON object keys sorted lexicographically by UTF-8 byte sequence.
6. Set-like semantic arrays sorted by their documented stable key.
7. Path segments, tuples, sequences, and source text preserve semantic order.
8. Integers use unsigned or signed decimal syntax; floating-point numbers are
   forbidden in compiler artifacts.
9. SHA-256 digests use 64 lowercase hexadecimal characters.
10. No locale, timezone, current directory, environment, hash-table iteration,
    timestamp, random value, or absolute path affects output.

Machine-authored JSON artifacts use the compact canonical encoding plus one
final newline. The indented JSON in this document is presentation-only.

Contract formatting is not semantic. Its digest is computed from strict parsed
and normalized contract data, not the user's whitespace.

Generated source obeys target-profile rules:

- UTF-8 without BOM;
- LF endings;
- exactly one trailing newline;
- fixed import and declaration order;
- no external formatter;
- generated header contains target profile, profile version, and semantic
  digest, but no timestamp or local path.

## 10. Resolver pipeline

Resolution is a deterministic pure pipeline:

```text
1. Validate contract structure and stable identifiers.
2. Normalize source and evidence provenance.
3. Normalize and reconcile structural type facts.
4. Resolve the effective parameter partition.
5. Validate initializer/action identity and label sets.
6. Construct typed initial-state and step-parameter roots.
7. Resolve every action input path.
8. Derive required observation variables from exact Core semantics.
9. Resolve observations and require exact completeness.
10. Optionally classify compatibility against a previous lock.
11. Canonicalize the semantic IR and compute digests.
```

### 10.1 Type fact reconciliation

For each model path:

| Evidence | Result |
| --- | --- |
| Two declaration facts normalize to different types | `MIC-R-TYPE-001` conflict; include both locations |
| Declaration fact plus equal contract assertion | Resolved with both origins |
| Declaration fact plus unequal contract assertion | `MIC-R-TYPE-001` conflict |
| No declaration fact plus contract assertion | Resolved with `contract_asserted_type` obligation |
| Trace samples only | `MIC-R-TYPE-002` unresolved type |
| No evidence | `MIC-R-TYPE-002` unresolved type |

Trace values validate a resolved type during preflight. They never infer, join,
widen, or replace it.

### 10.2 Parameter partition

```text
configuredParamVar = normalize(runProfile.configuredParamVar)

require contract.wire.parameterVariable = configuredParamVar

effectiveParamVars =
  stableUnique(evidence.itfParamVars ++ configuredParamVar.toList)
```

The resolver records original ITF parameter variables separately from the
configured extra parameter variable because they have different provenance.

### 10.3 Action validation

The resolver enforces:

- at least one initializer;
- unique nonempty stable IDs;
- nonempty wire labels;
- one owner for every primary label and alias;
- disjoint initializer and transition label sets;
- aliases are collision-free and do not form redirect chains;
- initializer inputs use `initialState` only;
- transition inputs use `stepParameters` only;
- `actionVariable` equals the hardcoded version-1 value `action_taken`.

Declared but unseen actions are not resolution failures. Coverage belongs to
preflight.

### 10.4 Typed path resolution

Given a root type and a path, each segment produces the next type:

| Segment | Required current type | Result |
| --- | --- | --- |
| `field(name)` | Record containing unique `name` | Field type |
| `index(i)` | Tuple with `i` in range | Tuple element type |
| `index(i)` | Sequence | Sequence element type |
| `mapKey(k)` | Map whose key type accepts `k` | Map value type |
| `variantValue(tag)` | Variant containing unique `tag` | Case payload type |

Invalid traversal reports the exact segment index, current normalized type,
and available fields/cases where applicable. Indexing a set or map, traversing
an opaque value, using a mistyped map key, or selecting an absent variant is an
error.

The initial root is a record of state variables remaining after parameter
repartition and root-meta removal. The step root is a record of effective
parameter variables. Therefore Counter resolves:

```text
stepParameters
  .parameters        : { stride : Int }
  .stride            : Int
```

### 10.5 Observation resolution

Version 1 restricts each observation to a complete top-level variable. The
resolver:

1. calculates `requiredObservationVars`;
2. rejects duplicate observation wire names;
3. rejects every observation absent from that set;
4. emits one error for every required variable not declared;
5. resolves the full top-level variable type;
6. requires `provenance = implementation`;
7. constructs the observation list sorted by stable ID.

No expected trace value is copied into the lock or generated binding.

### 10.6 Compatibility classification

When `previousLock` is supplied, resolution also returns structured changes.
Version 1 classifies these changes as breaking:

- adding or removing a required action method;
- changing action phase;
- changing a primary wire label without retaining it as an alias;
- adding a required input;
- removing an observation;
- changing an input or observation type incompatibly;
- changing the configured parameter variable.

Documentation, source provenance, and alias additions are nonbreaking when
semantic dispatch remains unambiguous. Compatibility classification does not
change whether the new lock itself is valid.

## 11. Diagnostics

Diagnostics are structured data. Human strings are rendered after sorting.

```lean
inductive Severity where
  | error
  | warning
  | obligation

structure DiagnosticSubject where
  kind      : String
  stableId  : Option String

structure SourceLocation where
  source    : String
  pointer   : Option String
  line      : Option Nat
  column    : Option Nat

structure Diagnostic where
  code       : String
  severity   : Severity
  stage      : String
  subject    : DiagnosticSubject
  primary    : SourceLocation
  related    : List SourceLocation
  arguments  : List (String × String)
```

Logical source names use normalized workspace-relative paths. Absolute paths
never appear in diagnostics, locks, or generated files.

Diagnostics have a total order:

```text
stage ordinal
-> canonical source ID
-> pointer / line / column
-> code
-> subject kind and stable ID
-> canonical arguments
```

Related locations and arguments are independently sorted and deduplicated.

### 11.1 Code families

| Prefix | Meaning |
| --- | --- |
| `MIC-R-*` | Contract/evidence resolution prevents a valid lock |
| `MIC-E-*` | Selected target cannot lower or render a valid lock |
| `MIC-P-*` | Trace preflight or coverage finding |
| `MIC-B-*` | Generated runtime binding failure |
| `MIC-C-*` | CLI/compiler-shell input, stale-output, or infrastructure finding |

Representative codes:

| Code | Meaning |
| --- | --- |
| `MIC-R-SCHEMA-001` | Unsupported schema or unknown contract field |
| `MIC-R-ID-001` | Duplicate or invalid stable ID |
| `MIC-R-ACTION-001` | Duplicate/colliding wire label or alias |
| `MIC-R-ACTION-002` | Initializer/transition label overlap |
| `MIC-R-PARAM-001` | Contract and run-profile parameter variable differ |
| `MIC-R-TYPE-001` | Conflicting type declarations |
| `MIC-R-TYPE-002` | Type cannot be resolved from declaration evidence |
| `MIC-R-PATH-001` | Typed path segment is invalid |
| `MIC-R-OBS-001` | Required comparable variable has no observation |
| `MIC-R-OBS-002` | Observation is not a comparable variable |
| `MIC-E-TYPE-001` | Target profile does not support a resolved type |
| `MIC-E-NAME-001` | Target identifier escape produces a collision |
| `MIC-P-TRACE-001` | Trace structure or `action_taken` is malformed |
| `MIC-P-ACTION-001` | Trace contains an undeclared action |
| `MIC-P-COVERAGE-001` | Declared action was not exercised |
| `MIC-P-VALUE-001` | Trace value does not inhabit its resolved type |
| `MIC-B-LIFECYCLE-001` | Transition before initialization or poisoned use |
| `MIC-B-INPUT-001` | Runtime input is missing or has the wrong type |
| `MIC-B-ADAPTER-001` | SUT adapter method failed |
| `MIC-B-OBS-001` | Observation is incomplete, extra, or mistyped |

`MIC-P-COVERAGE-001` is an obligation by default and an error under
`--require-all-actions`. It is not a runtime binding failure.

A well-shaped actual observation that differs from the expected state remains
Mirrors' ordinary `step_mismatch`; it is not assigned a compiler diagnostic.

## 12. Trace preflight

Preflight parses raw ITF JSON with stricter evidence rules than the normal
runtime loader. It must diagnose duplicate keys, undeclared state keys, missing
or non-string `action_taken`, malformed metadata, and inconsistent schemas
before any lossy projection.

For each trace, preflight:

1. validates structural metadata and unique key requirements;
2. checks trace `vars` and `param_vars` against the lock's run profile;
3. applies the configured parameter repartition;
4. requires state zero to carry a declared initializer label;
5. requires every later state to carry a declared transition label;
6. rejects an initializer inside the transition tail;
7. validates every projected input against its resolved type;
8. validates every comparable state value against its observation type;
9. confirms actual `filterMeta(step.vars)` keys equal the lock observation
   keys at every step;
10. counts canonical action IDs and produces a coverage report.

Unknown actions are errors. Missing declared actions are obligations unless
`requireAllActions` is true.

Preflight never modifies the lock, contract, trace, or generated files.

## 13. Target lowering and emission

### 13.1 Emitter seam

The conceptual long-term seam is:

```text
semantic lock
    -> target lowering
target-specific model
    -> deterministic rendering
generated tree
```

Only one emitter exists in Phase 1, so introducing a generic emitter structure
then would be hypothetical indirection. Implement `emitTypeScript` directly.
Extract a common emitter interface when the C++ emitter becomes the second
adapter in Phase 2.

Target-specific identifier validation and unsupported-type failures belong to
target lowering, not `resolve`. A language-neutral lock may be valid even when
one target cannot represent it.

### 13.2 `mirrorecma-v1` profile

The first profile emits one source file and one ownership manifest:

```text
CounterMirror.generated.ts
.model-interface-generated.json
```

The TypeScript file declaration order is fixed:

1. generated header;
2. imports;
3. named input and observation types;
4. implementation port;
5. binding error types;
6. generated decoders and encoders;
7. lifecycle state and coverage storage;
8. binding implementation;
9. public binding factory.

The module also exports inert registration metadata without adding executable
behavior or changing the existing port/binding APIs:

```ts
export const CounterSemanticDigest = "..." as const;
export const CounterModelInterface = {
  semanticDigest: CounterSemanticDigest,
  contract: { /* canonical companion contract */ },
} as const;
```

Clients pass this contract in registration and select the local adapter by the
semantic digest. The implementation adapter itself is never generated into or
stored in this metadata.

The header contains:

```text
@generated by Mirrors model_interface_gen
target-profile: mirrorecma-v1
profile-version: 1
semantic-sha256: ...
DO NOT EDIT
```

### 13.3 TypeScript native mapping

| Model type | Generated TypeScript port type |
| --- | --- |
| `int` | `bigint` |
| `bool` | `boolean` |
| `str` | `string` |
| `null` | `null` |
| `seq(T)` | `readonly T[]` |
| `tuple(T...)` | `readonly [T, ...]` |
| `record` | Generated closed readonly interface |
| `set(T)` | Generated `MirrorSet<T>` represented by a readonly array with extensional validation |
| `map(K,V)` | Generated `MirrorMap<K,V>` represented by readonly entry pairs |
| `variant` | Closed discriminated union |
| `opaqueItf` | Rejected by default with `MIC-E-TYPE-001` |

The generated binding converts these native port values to MirrorECMA's
existing `Value` representation. Record/map keys are validated for uniqueness.
Set validation uses Mirror value equality rather than JavaScript object
identity.

### 13.4 Identifier lowering

- `UpperCamelCase` stable IDs name generated types.
- A deterministic lower-camel transform names action methods and fields.
- Exact wire names remain data and are never case-converted.
- The profile owns a fixed reserved-word table.
- Reserved native identifiers receive a documented `_` suffix.
- If escaping or case conversion makes two identifiers equal, emission fails
  with `MIC-E-NAME-001`; it never appends an unstable numeric suffix.

### 13.5 Generated implementation port

Counter emits:

```ts
export interface TickInput {
  readonly stride: bigint;
}

export interface CounterObservation {
  readonly count: bigint;
}

export interface CounterPort {
  initialize(): void;
  tick(input: TickInput): void;
  observe(): CounterObservation;
}
```

The LLM-written adapter sees no raw ITF values, expected transition state, or
`StateComputer.prevState`.

### 13.6 Generated binding interface

```ts
export interface CounterBinding {
  readonly computer: StateComputer;
  coverage(): Readonly<Record<"Initialize" | "Tick", number>>;
  assertAllActionsCovered(): void;
}

export function bindCounter(
  port: CounterPort,
  config: Pick<ApalacheConfig, "paramVars">,
): CounterBinding;
```

`bindCounter` immediately validates `config.paramVars` against the lock. This
is the runtime defense against a correct generated binding being paired with a
different parameter partition.

The binding state machine is:

```text
fresh -> initialized -> initialized -> ...
  |           |              |
  +-----------+--------------+-> poisoned
```

An initializer is accepted in `fresh` or `initialized` and resets the SUT for
a new trace. A transition is accepted only in `initialized`. Any decode,
adapter, observation, or encoding failure moves permanently to `poisoned`.

For one successful callback the order is exact:

```text
classify action
-> decode and validate every input
-> call exactly one initializer/action method
-> call observe exactly once
-> validate exact observation shape and types
-> encode the report State
-> increment coverage
-> return State
```

`prevState` is ignored and never captured by the generated port. Only declared
initializer inputs are projected from `initial_state`; other oracle fields are
not passed to the adapter.

### 13.7 Ownership manifest

The generated manifest contains the target profile, semantic digest, and
sorted relative paths owned by this generation. A later `generate` invocation
may replace or remove only files listed in the previous valid manifest. It
must never clean an output directory broadly or delete unowned files.

## 14. CLI design

The compiler is a separate executable:

```text
.lake/build/bin/model_interface_gen
```

It does not add development-only commands to the operational `mirror` binary.

### 14.1 Resolve

```text
model_interface_gen resolve
  --spec specs/Counter.tla
  --contract specs/Counter.mirror-interface.json
  --evidence test/fixtures/model-interface/counter/type-evidence.json
  --param-var parameters
  --lock generated/Counter.mirror-interface.lock.json
```

Behavior:

- reads and validates inputs;
- resolves and canonically encodes the lock;
- writes the lock atomically only on success;
- never invokes live Apalache in version 1;
- refuses to replace a non-generated incompatible artifact unless explicitly
  authorized.

### 14.2 Generate

```text
model_interface_gen generate
  --lock generated/Counter.mirror-interface.lock.json
  --target mirrorecma-v1
  --out generated/mirrorecma
```

Behavior:

- decodes and verifies lock digests;
- lowers and renders deterministically;
- writes a temporary tree and validates it before replacement;
- atomically replaces owned generated files;
- never deletes unowned output.

### 14.3 Check

```text
model_interface_gen check
  --spec specs/Counter.tla
  --contract specs/Counter.mirror-interface.json
  --evidence test/fixtures/model-interface/counter/type-evidence.json
  --param-var parameters
  --lock generated/Counter.mirror-interface.lock.json
  --target mirrorecma-v1
  --out generated/mirrorecma
```

`check` is the single read-only CI command. It resolves and emits in memory,
then byte-compares the expected lock, manifest, and generated tree. It performs
no repairs and writes no files.

### 14.4 Preflight

```text
model_interface_gen preflight
  --lock generated/Counter.mirror-interface.lock.json
  --trace test/fixtures/model-interface/counter/traces/counter.itf.json
  --require-all-actions
```

Preflight is read-only. The coverage report goes to stdout or an explicitly
requested report path; writing such a report is never implicit.

### 14.5 Scaffold

```text
model_interface_gen scaffold
  --spec specs/Counter.tla
  --evidence counter.itf.json
  --contract specs/Counter.mirror-interface.json
```

`scaffold` is deferred until after the Counter vertical slice. It may propose
types and observed actions, but inferred actions are marked unsealed. It never
overwrites an existing contract without an explicit replace flag.

### 14.6 Exit codes and output

| Exit | Meaning |
| --- | --- |
| `0` | Success, clean check, or compatible preflight |
| `1` | Deterministic model-interface finding: invalid input, stale output, incompatible trace, or required coverage gap |
| `2` | Usage or infrastructure failure: bad flags, unreadable input, write failure, or unavailable requested external tool |

Diagnostics go to stderr in canonical order. A concise summary or requested
machine artifact goes to stdout. `--diagnostics json` emits canonical
structured diagnostics. `check` and `preflight` do not write unless an output
artifact is explicitly named for preflight.

## 15. Safe file behavior

- Writes use a temporary sibling followed by atomic rename where supported.
- Cooperative generators serialize through an atomic output-root lock; a
  crash-retained lock fails closed and requires operator verification before
  removal.
- Existing owned files are hard-link backed up before publication, and caught
  failures restore the prior tree and remove only byte-identical new files.
- No command recursively deletes a directory.
- Output roots are explicit and validated before use.
- Ownership comes only from a valid generated manifest.
- A stale or malformed ownership manifest prevents deletion.
- `check` performs byte comparisons without mutation.
- Generated files are committed so consumers do not require the generator at
  package build time.

## 16. Repository implementation map

```text
Core/ModelInterface/Types.lean
    Stable IDs, ModelType, paths, resolved actions/observations, lock

Core/ModelInterface/Resolve.lean
    Pure resolution, exact observation completeness, diagnostics

Core/ModelInterface/Preflight.lean
    Pure trace-schema/value validation and coverage

Core/ModelInterface/Canonical.lean
    Semantic/provenance projections and ordering

Codec/ModelInterfaceJson.lean
    Strict contract, evidence, lock, coverage, and diagnostic codecs

Shell/ModelInterface/Evidence.lean
    Raw ITF metadata normalization and optional external evidence adapters

Shell/ModelInterface/Emit/TypeScript.lean
    mirrorecma-v1 lowering and rendering

Shell/ModelInterface/Files.lean
    Source closure, hashes, atomic writes, ownership manifest, checks

Shell/ModelInterface/Command.lean
    CLI parsing and subcommand orchestration

tools/ModelInterfaceGen.lean
    Executable entry point

tools/ModelInterfaceSpec.lean
    Always-on pure and golden test executable

test/fixtures/model-interface/
    Contracts, evidence, locks, diagnostics, traces, generated output
```

The emitter is pure but remains outside the proof boundary because emitted
foreign-language behavior is checked by compilation and runtime tests rather
than Lean theorems. `Core/` contains only language-neutral semantics.

## 17. Proof claims

Reasonable Lean theorems are conditional on the supplied normalized evidence:

1. successful resolution yields unique stable IDs;
2. successful resolution yields globally unique wire labels and aliases;
3. initializer and transition labels are disjoint;
4. every resolved path is structurally well-typed;
5. resolved observation wire names equal `requiredObservationVars`;
6. encoded observations have duplicate-free top-level keys;
7. successfully validated observation values satisfy `WfValue`;
8. canonical ordering is idempotent;
9. canonical lock encode/decode round-trips;
10. semantic projection excludes provenance-only fields.

The proof claim does not include:

- that evidence accurately represents arbitrary TLA+ semantics;
- that Apalache itself is correct;
- that generated TypeScript or C++ implements the lock correctly;
- that the LLM adapter calls the intended SUT methods;
- that a passing finite trace proves full conformance.

Foreign-language emitters are checked through golden output, target compiler
checks, recording adapters, and real replay.

## 18. Fixture matrix

Each resolver fixture contains the smallest relevant combination of contract,
normalized evidence, optional raw trace, expected canonical diagnostics, and
expected lock or coverage report.

| Fixture | Expected result |
| --- | --- |
| `counter-valid` | Resolves `parameters.stride`; only `count` is comparable |
| `combined-param-vars` | ITF `param_vars` plus configured `parameters` are excluded |
| `filter-meta-root-only` | Root `parameters` is filtered; nested `user.parameters` remains compared |
| `missing-observation` | `step_count` produces `MIC-R-OBS-001` |
| `extra-observation` | Non-comparable `debug` produces `MIC-R-OBS-002` |
| `duplicate-record-key` | Duplicate evidence keys are rejected |
| `duplicate-map-key` | Value cannot establish `NodupKeys` |
| `set-permutation` | Different set order validates extensionally |
| `record-vs-map` | Similar concrete shapes retain distinct types |
| `init-action-overlap` | Same label in both phases is rejected |
| `alias-collision` | Alias owned by two actions is rejected |
| `transition-at-zero` | Preflight rejects transition label at state zero |
| `initializer-after-zero` | Preflight rejects initializer in transition tail |
| `missing-action-taken` | Malformed trace, never empty action dispatch |
| `wrong-path-kind` | Diagnostic identifies exact failing segment |
| `type-conflict` | Contract `Int` versus evidence `Bool`, with both locations |
| `trace-only-type` | Samples alone do not resolve a type |
| `contract-asserted-type` | Resolves with a provenance obligation |
| `trace-value-type-error` | Sample is rejected without changing resolved type |
| `param-config-drift` | Contract/run-profile mismatch fails |
| `coverage-gap` | Valid lock plus `MIC-P-COVERAGE-001` obligation |
| `deterministic-diagnostics` | Shuffled evidence order yields identical diagnostic JSON |
| `deterministic-lock` | Repeated resolution produces identical bytes |
| `lock-contract-authentication` | Missing or mutated embedded contract is rejected |
| `contract-whitespace` | Insignificant input whitespace produces identical canonical contract bytes |
| `target-name-collision` | TypeScript lowering fails with `MIC-E-NAME-001` |
| `target-opaque-type` | TypeScript lowering rejects opaque ITF |

## 19. Counter vertical slice

Phase 1 is TypeScript-only and always-on. It proves the compiler's first real
path before introducing a premature multi-emitter abstraction.

### 19.1 Inputs

- [`specs/Counter.tla`](../specs/Counter.tla);
- `test/fixtures/model-interface/counter/Counter.mirror-interface.json`;
- pinned normalized type evidence containing:
  - `count : Int`;
  - `parameters : { stride : Int }`;
  - `action_taken : Str`;
- one checked-in real ITF trace containing `init` and `tick`;
- run profile `configuredParamVar = parameters`.

### 19.2 Expected semantic lock

```text
initializer Initialize
  wire label: init
  inputs: none

transition Tick
  wire label: tick
  input Stride: stepParameters.parameters.stride : Int

observation Count
  wire name: count
  type: Int

effective parameter variables: [parameters]
comparable variables: [count]
```

### 19.3 Expected TypeScript behavior

- `initialize()` calls the real mutable Counter reset method;
- `tick({stride})` mutates the real Counter by `stride`;
- `observe()` reads the real Counter accessor;
- the generated binding reports only `count` as `#bigint` on the wire;
- the binding never passes expected `count` or `prevState` to the adapter;
- malformed or missing stride fails before Counter mutation;
- an adapter failure poisons the binding;
- both actions are counted by coverage.

### 19.4 Always-on gates

1. Exact golden bytes for the contract, lock, ownership manifest, diagnostics,
   coverage report, and generated TypeScript.
2. Re-emission under different current directories and locale settings yields
   identical semantic hashes and output bytes.
3. `check` returns `0` for clean output.
4. Mutating a copied generated file makes `check` return `1` without repairing
   it.
5. Generated TypeScript compiles against the pinned MirrorECMA interface.
6. A recording adapter tests initialization, stride decoding,
   operation-before-observation ordering, failure poisoning, and exact
   `report_state` bytes.
7. A real mutable Counter object is driven through the generated port.
8. A checked-in ITF trace passes through the actual Mirrors
   `register_traces` flow.
9. A deliberately incorrect Counter accessor produces `step_mismatch`.
10. Missing or mistyped stride produces `MIC-B-INPUT-001` before any SUT
    mutation.
11. Preflight with `--require-all-actions` covers `Initialize` and `Tick`.

Live Apalache trace generation remains a supplemental `APALACHE_MC`-gated
tier. The always-on gate never relies on `.golden-build/` artifacts.

## 20. Implementation sequence

### M0: type-evidence spike

- Pin Counter and HourClock typed ITF metadata.
- Define and test the emitted Apalache type-string subset.
- Confirm nested record paths and all required top-level variables resolve.
- Record unsupported type forms as explicit diagnostics.

Exit: Counter and HourClock evidence normalize deterministically without a
general TLA+ parser.

### M1: pure syntax, IR, and resolver

- Implement stable IDs, strict contract model, normalized types and paths.
- Implement parameter partition, action validation, typed paths, and exact
  observation completeness.
- Implement structured diagnostics and Counter negative fixtures.
- Implement canonical semantic/provenance projections.

Exit: Counter resolves to exact golden lock bytes; all resolver-negative
fixtures pass.

### M2: TypeScript lowering and generated binding

- Implement `mirrorecma-v1` target lowering.
- Render deterministic TypeScript and ownership manifest.
- Implement generated lifecycle, codecs, observation validation, and coverage.
- Compile generated output against MirrorECMA.

Exit: recording adapter and mutable Counter tests pass.

### M3: CLI and read-only check

- Implement `resolve`, `generate`, `check`, and `preflight`.
- Implement atomic owned-file replacement and non-mutating stale checks.
- Add canonical text and JSON diagnostics.

Exit: clean/stale/error exit-code tests pass and `check` performs no writes.

### M4: real Counter replay

- Check in the Counter contract, evidence, lock, trace, and generated output.
- Drive the mutable Counter through the generated port and Mirrors.
- Verify success and deliberate `step_mismatch` failure.

Exit: the full Counter vertical slice is always-on.

### M5: C++ second target

- Define `mirrorcpp-v1` target shape exactly.
- Add C++ lowering and rendering from the same lock.
- Extract a shared emitter interface now that two adapters exist.
- Compare both targets using common raw `StateComputer` stimuli, normalized
  recording logs, and canonical `report_state` bytes.

Exit: TypeScript and C++ have equivalent behavior from one semantic lock.

Rust, Lean, scaffolding, compatibility migration helpers, and async profiles
follow only after the two-target seam is stable.

## 21. Rejected version-1 choices

- **Trace-derived action universe:** finite traces under-approximate behavior.
- **An emitter that reads TLA+ directly:** every target would reinterpret model
  semantics independently.
- **Coverage stored in the lock:** sampled evidence would churn generated
  interfaces.
- **One generic raw `perform(action, State)` port:** it leaves dispatch and ITF
  parsing in the LLM adapter.
- **Oracle state available to the port:** it invites echoing expected values.
- **`prevState` available to the port:** it invites model reimplementation.
- **Silent defaults for missing inputs:** they turn contract errors into false
  conformance results.
- **Automatic synthesis of model-only variables:** it weakens what is actually
  being checked.
- **External source formatter:** formatter versions and configuration would
  become hidden generation inputs.
- **A generic emitter interface with one implementation:** the seam would be
  hypothetical until C++ exists.
- **Compiler commands on the operational `mirror` binary:** development
  tooling should not enlarge the production CLI.
- **Recursive output-directory cleanup:** only manifest-owned generated files
  may be replaced or removed.
- **Implicit asynchronous blocking:** async SUT support requires an explicit
  future interface rather than hidden blocking inside synchronous
  `StateComputer`.

## 22. Acceptance criteria

The compiler design is implemented when:

1. The strict Counter contract and normalized evidence resolve to canonical,
   byte-stable lock JSON.
2. Independent input ordering and formatting produce identical semantic
   digests and generated TypeScript.
3. Contract/evidence conflicts produce stable structured diagnostics with no
   absolute paths.
4. Exact observation completeness is derived from the same parameter and meta
   semantics used by `Core.Trace` and `Core.Value`.
5. Coverage changes do not change the lock or generated source.
6. `mirrorecma-v1` lowers the lock to deterministic, compiling TypeScript.
7. The generated implementation port exposes only typed initializer/action
   methods and complete observations.
8. The generated binding never exposes expected transition state or
   `prevState` to the implementation adapter.
9. Missing/mistyped inputs fail before SUT mutation; adapter/observation
   failures poison the binding.
10. A recording adapter tests exact dispatch and observation ordering.
11. A mutable Counter passes a checked-in real trace through Mirrors.
12. A deliberately wrong observation reaches Mirrors as `step_mismatch`.
13. `check` detects stale lock/generated bytes and performs no writes.
14. `preflight --require-all-actions` distinguishes valid behavior from action
    coverage gaps.
15. Existing handwritten `StateComputer` callers remain source-compatible.
16. Lean proof claims remain conditional on normalized evidence and do not
    extend to external tools, generated foreign code, the LLM adapter, or the
    SUT.

## 23. Result

The compiler has two high-leverage interfaces:

```text
resolve(normalized model facts) -> semantic lock
emitTypeScript(semantic lock)   -> generated tree
```

Everything else—source loading, evidence collection, filesystem writes,
foreign compilation, LLM mapping, and real trace replay—sits outside those
pure interfaces at explicit seams. This gives the compiler locality without
expanding its claim beyond what Mirrors can actually verify.
