# Generated Model Interface — Cross-Language Specification

> Status: **proposed normative version 1**
>
> The `mirrorecma-v1` reference target and `mirrorcpp-v1` static target are
> implemented. The `mirrorrust-v1` and `mirrorlean-v1` profiles are specified
> here for subsequent implementation.
>
> Compiler design:
> [`model-interface-compiler-design.md`](model-interface-compiler-design.md)
>
> Runtime negotiation:
> [`model-interface-runtime-distribution-design.md`](model-interface-runtime-distribution-design.md)

## 0. Implementation status

Mirrors currently implements the canonical lock, semantic digest, normalized
contract handoff, ownership manifests, and the `mirrorecma-v1` and
`mirrorcpp-v1` emitters. MirrorECMA and MirrorCPP implement exact-digest adapter
selection and exercise their generated Counter bindings over local stdio and
allowlisted mTLS server mode.

The common portable-profile check, cross-language recording vectors,
`mirrorrust-v1`, `mirrorlean-v1`, and their negotiated client registries remain
implementation work. The C++ emitter has direct executable coverage for the
portable type baseline, but that is not yet the proposed shared vector suite.
Consequently, this document remains the normative target for the remaining
work; two implemented outputs are not evidence that all four profiles conform.

## 1. Purpose

This document defines the interface that the Mirrors model-interface compiler
generates for every supported client language. It is the contract between:

1. the language-neutral semantic lock produced by Mirrors;
2. a target-language emitter;
3. the implementation adapter written by a human or LLM;
4. the generated binding that satisfies the client's existing
   `StateComputer` interface; and
5. the negotiated client runtime that selects a local binding by exact
   semantic digest.

Cross-language compatibility does **not** mean that TypeScript, C++, Rust, and
Lean expose identical source syntax or share a binary ABI. It means that, for
the same semantic lock and the same sequence of model stimuli, every
conforming generated binding:

- exposes the same stable actions, inputs, and observations;
- accepts and rejects the same model values;
- invokes the implementation adapter in the same order;
- reports semantically equal ITF state;
- implements the same lifecycle and failure rules; and
- embeds the same semantic digest and normalized companion contract.

The semantic lock is the language-neutral interface definition. Generated
source is a target-specific projection of that definition.

## 2. Normative language and conformance

The words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** are
normative.

A target profile conforms to this specification when its emitter, generated
binding, client-runtime integration, and common conformance fixtures satisfy
all MUST-level requirements. A target profile MAY reject a language-neutral
interface that it cannot represent faithfully. It MUST return a deterministic
target-emission diagnostic instead of weakening or changing the interface.

This specification defines source-level and behavioral compatibility. It does
not define an ABI between independently compiled languages.

## 3. Terms and seams

| Term | Meaning |
| --- | --- |
| Semantic lock | Verified `mirrors.model-interface-lock/v1` compiler output. |
| Semantic descriptor | Runtime-distributable projection with schema `mirrors.model-interface-descriptor/v1`. |
| Stable ID | Target-independent identity of an action, input, or observation. |
| Target profile | Versioned rules that lower one semantic lock into one client language. |
| Generated port | Model-specific interface implemented by the application adapter. |
| Implementation adapter | Human- or LLM-written mapping from the generated port to the real SUT. |
| Generated binding | Deterministic implementation that converts the generated port to the client `StateComputer` seam. |
| Local binding | Per-session client-runtime handle containing a generated computer and SUT cleanup. |

The required module shape is:

```text
semantic lock
    |
    v
target emitter --------------------------+
    |                                    |
    v                                    v
generated port                  generated binding
    ^                                    |
    |                                    v
implementation adapter               StateComputer
    ^                                    |
    |                                    v
real SUT                         Mirror client runtime
```

The generated binding is a deep module. It owns action dispatch, input
projection, ITF/native conversion, lifecycle checks, observation validation,
coverage, and error classification. The implementation adapter owns only the
irreducible mapping to real application operations and state.

## 4. Identity and version axes

Implementations MUST keep the following axes distinct:

| Axis | Example | Purpose |
| --- | --- | --- |
| Contract schema | `mirrors.model-interface/v1` | Syntax of the companion contract. |
| Descriptor schema | `mirrors.model-interface-descriptor/v1` | Canonical language-neutral semantics. |
| Interface version | `1.0.0` | Model author's compatibility declaration. |
| Semantic digest | 32-byte SHA-256 | Exact interface selection across all languages. |
| Target profile | `mirrorecma-v1` | Native source and client-runtime lowering rules. |
| Profile version | `1` | Generated-source compatibility for that target. |
| StateComputer contract | `mirrors.state-computer/v1` | Client replay seam expected by the binding. |
| Adapter ID | Application-defined string | Selects one local SUT adapter for an interface. |

The semantic digest is calculated once by Mirrors:

```text
SHA-256(
  UTF8("mirrors-model-interface-descriptor/v1")
  || 0x00
  || canonicalSemanticDescriptorBytes
)
```

It is the same for every target language. Target profile, generated source,
compiler provenance, adapter ID, and coverage MUST NOT affect it.

Runtime adapter selection MUST use the exact tuple:

```text
{
  semanticDigest,
  adapterId,
  targetProfile,
  stateComputerContractVersion
}
```

Names, model versions, compatible ranges, and structural guesses MUST NOT
replace exact digest selection.

## 5. Authoritative compiler input

Every emitter MUST consume a verified `LockedModelInterface`. It MUST NOT read
TLA+ source, inspect sample traces, invoke Apalache, or reinterpret the
companion contract.

The generated behavior is derived only from these resolved semantic fields:

```text
schema
interfaceVersion
model.module
resolverSemanticsVersion
comparisonPolicyVersion
runProfile
initializers
actions
observations
semanticDigest
```

The normalized companion `contract` is emitted as inert registration metadata.
It does not override resolved actions, types, paths, observations, or the
semantic digest. Before emission, the compiler MUST verify the lock and
recompute `provenance.contractSha256` from canonical contract bytes.

Provenance, source paths, evidence locations, diagnostics, and trace coverage
MUST NOT be exposed through the generated implementation port.

## 6. Language-neutral generated interface

The resolved, portable definitions used by every emitter are:

```text
ResolvedInput = {
  id   : StableInputId,
  from : { root: initialState | stepParameters, path: PathSegment[] },
  type : ModelType
}

ResolvedAction = {
  id          : StableActionId,
  phase       : initialize | transition,
  wireAction  : String,
  wireAliases : String[],
  inputs      : ResolvedInput[]
}

ResolvedObservation = {
  id         : StableObservationId,
  wireName   : String,
  type       : ModelType,
  provenance : implementation
}
```

Actions, inputs, aliases, and observations are already normalized by the
resolver. Emitters MUST preserve their identities and MUST NOT merge, infer,
or omit entries.

For specification purposes, every generated module exports the following
semantic interface. Native spelling is defined by the target profile.

```text
GeneratedMetadata = {
  semanticDigest : SemanticDigest,
  contract       : ContractV1
}

Port = {
  one synchronous handler for each declared initializer,
  one synchronous handler for each declared transition action,
  observe() -> complete Observation
}

Binding = {
  computer                  : StateComputer,
  coverage()                : Map<StableActionId, Nat>,
  assertAllActionsCovered() : Unit
}

bind(port, effectiveConfig) -> Binding
```

`GeneratedMetadata`, `Port`, `Binding`, and `bind` are conceptual names. A
profile MUST produce model-specific native names as described in section 12.

The generated metadata MUST be constructible without filesystem access,
network access, dynamic loading, source evaluation, or SUT construction.

## 7. Generated implementation port

### 7.1 Actions

The port MUST contain exactly one handler for every resolved initializer and
transition action. It MUST contain no handler for wire aliases; an alias is
dispatched to its primary stable action handler.

For an action with no inputs, its handler takes no input argument. For an
action with one or more inputs, its handler takes exactly one generated,
closed input record. Fields are identified semantically by input stable ID.

Handlers are synchronous in version 1. A target profile MUST reject an adapter
that returns a deferred computation through this interface. An asynchronous
generated interface requires a new additive StateComputer contract version.

A handler semantically returns `Unit`. It MAY signal an implementation failure
through the target profile's prescribed synchronous error mechanism.

### 7.2 Observation

The port MUST expose exactly one `observe()` operation. It returns one closed
observation record containing every resolved observation exactly once and no
additional fields.

`observe()` MUST describe actual post-operation SUT state and MUST NOT mutate
the SUT. The implementation adapter, not the generated binding, is responsible
for any abstraction from concrete implementation state to the declared model
type.

Version 1 accepts only observations whose provenance is `implementation`.
Oracle and derived provenance MUST be rejected during resolution.

### 7.3 Prohibited port data

The generated port MUST NOT expose:

- expected next model state;
- `StateComputer.prevState`;
- raw ITF `State` or `Value` objects;
- raw action strings;
- undeclared oracle fields;
- protocol messages or transports;
- descriptor or contract parsers; or
- filesystem, package, plugin, or network loading instructions.

This restriction prevents the implementation adapter from becoming a second
model interpreter or echoing the oracle's expected answer.

## 8. Model Interface Type Language

### 8.1 Method

This section follows the presentation method used in Robert Harper's
[*Practical Foundations for Programming Languages*](https://www.cs.cmu.edu/~rwh/pfpl/):
first give abstract syntax, then statics, dynamics, and safety obligations.
PFPL does not define the Mirrors model types; it supplies the method used to
state them independently of TypeScript, C++, Rust, or Lean.

The Model Interface Type Language, abbreviated **MITL**, is a small, closed,
first-order typed language. It is an interface description language, not a
general-purpose programming language. It has no variables, type abstraction,
subtyping, recursion, or evaluation of user expressions in version 1.

### 8.2 Abstract syntax of types

Let `l` range over record wire labels, `c` over variant tags, `a` over stable
action IDs, `x` over stable input IDs, and `o` over stable observation IDs.
MITL types are:

```text
τ ::= Int                         arbitrary-precision integers
    | Bool                        booleans
    | Str                         strings
    | Null                        distinguished singleton
    | Set[τ]                      finite extensional sets
    | Seq[τ]                      finite ordered sequences
    | Tup[τ₁, ..., τₙ]            finite positional products
    | Rec[l₁:τ₁, ..., lₙ:τₙ]      finite labeled products
    | Map[τk, τv]                 finite maps
    | Var[c₁:τ₁, ..., cₙ:τₙ]      finite labeled sums
```

`Tup[]` and `Rec[]` are empty product types. `Null` is kept as a distinct
syntactic type even though it is isomorphic to an empty product. The retained
constructor determines ITF encoding and prevents absence, null, and an empty
record or tuple from being conflated.

`opaqueItf(description)` may occur in the broader compiler lock algebra, but
it is not an MITL v1 type. A portable emitter rejects it with
`MIC-E-TYPE-001`.

The lock-to-MITL elaboration is syntax directed:

| Lock `ModelType.kind` | MITL type |
| --- | --- |
| `int`, `bool`, `str`, `null` | `Int`, `Bool`, `Str`, `Null` |
| `set`, `seq` | `Set[τ]`, `Seq[τ]` |
| `tuple` | `Tup[τ₁, ..., τₙ]` |
| `record` | `Rec[l₁:τ₁, ..., lₙ:τₙ]` |
| `map` | `Map[τk, τv]` |
| `variant` | `Var[c₁:τ₁, ..., cₙ:τₙ]` |
| `opaqueItf` | no portable elaboration |

Types are identified by their canonical syntax, not by a target representation
or target-language name. Record labels and variant tags are exact wire data.
The resolver canonicalizes record labels and variant tags, while tuple order
remains significant.

### 8.3 Abstract syntax of values

Canonical model values are:

```text
v ::= z                                      where z is an integer
    | true | false
    | "..."                                  a string
    | null
    | set[v₁, ..., vₙ]
    | seq[v₁, ..., vₙ]
    | tup[v₁, ..., vₙ]
    | rec[l₁=v₁, ..., lₙ=vₙ]
    | map[vk₁=>vv₁, ..., vkn=>vvn]
    | var[c=v]
```

These forms describe semantic values. They are not a second JSON syntax. The
existing client `Value` codecs remain the concrete ITF representation.

### 8.4 Statics

Because MITL v1 is closed and first-order, its judgments need no variable
context. Type well-formedness is written:

```text
⊢ τ type
```

All primitive types are well formed. Composite formation is structural:

```text
⊢ τ type
──────────────
⊢ Set[τ] type

⊢ τ₁ type  ...  ⊢ τₙ type
──────────────────────────
⊢ Tup[τ₁, ..., τₙ] type

⊢ τ₁ type  ...  ⊢ τₙ type    l₁, ..., lₙ pairwise distinct
──────────────────────────────────────────────────────────
⊢ Rec[l₁:τ₁, ..., lₙ:τₙ] type

⊢ τ₁ type  ...  ⊢ τₙ type    c₁, ..., cₙ pairwise distinct
──────────────────────────────────────────────────────────
⊢ Var[c₁:τ₁, ..., cₙ:τₙ] type
```

`Seq` and `Map` have the analogous structural rules. Types are finite; a
formation derivation that exceeds the versioned depth or node bound is
rejected.

Value typing is written:

```text
⊢ v : τ
```

The canonical-form rules are:

```text
⊢ z : Int             ⊢ true : Bool        ⊢ false : Bool
⊢ "s" : Str           ⊢ null : Null

∀i. ⊢ vᵢ : τ    values are duplicate-free under ≃τ
────────────────────────────────────────────────────
⊢ set[v₁, ..., vₙ] : Set[τ]

∀i. ⊢ vᵢ : τ
────────────────────────────
⊢ seq[v₁, ..., vₙ] : Seq[τ]

∀i. ⊢ vᵢ : τᵢ
────────────────────────────────────
⊢ tup[v₁, ..., vₙ] : Tup[τ₁, ..., τₙ]

∀i. ⊢ vᵢ : τᵢ    actual labels are exactly {l₁, ..., lₙ}
──────────────────────────────────────────────────────────
⊢ rec[l₁=v₁, ..., lₙ=vₙ] : Rec[l₁:τ₁, ..., lₙ:τₙ]

∀i. ⊢ vkᵢ : τk    ∀i. ⊢ vvᵢ : τv
keys are duplicate-free under ≃τk
──────────────────────────────────────────────────────
⊢ map[vk₁=>vv₁, ..., vkn=>vvn] : Map[τk, τv]

⊢ v : τj    cj is one declared tag
──────────────────────────────────────────
⊢ var[cj=v] : Var[c₁:τ₁, ..., cj:τj, ..., cₙ:τₙ]
```

There is no width subtyping for records and no open variant rule. Extra or
missing fields and unknown tags are ill typed.

These judgments live at the compiler/specification level. A target does not
ship a general MITL type checker: the emitter specializes each derivation into
small generated decoders and encoders. Runtime checks remain necessary only
because protocol values and implementation observations enter from outside
the typed generated port.

### 8.5 Interface types

For a resolved model interface `M`, define the input type of action `a` as:

```text
InM(a) = Prod[x₁:τ₁, ..., xₙ:τₙ]
```

`Prod` is a finite labeled interface product; its labels are stable input IDs,
not model record wire labels. When `n = 0`, the target profile may erase the
empty product to a no-argument method.

Define the complete observation type as:

```text
ObsM = Prod[o₁:τ₁, ..., oₙ:τₙ]
```

Stable observation IDs label the abstract record. Their associated wire names
remain separate data used by observation encoding.

The generated port type is the labeled product:

```text
Port(M) = Prod[
  a₁ : InM(a₁) -> Comp[1],
  ...,
  aₙ : InM(aₙ) -> Comp[1],
  observe : 1 -> Comp[ObsM]
]
```

Here `1` is the command-result singleton, not the model `Null` encoding.
`Comp[τ]` is an interface computation type: it performs the local SUT effect,
terminates with a value of type `τ`, or signals an adapter failure. It is not a
serializable MITL model type. Its target interpretation is synchronous at the
StateComputer seam and is prescribed by the target profile.

The closed action command type is the labeled sum:

```text
Cmd(M) = Sum[a₁:InM(a₁), ..., aₙ:InM(aₙ)]
```

`Sum` is a finite labeled interface sum whose labels are stable action IDs,
not model variant tags. Wire action classification and input projection
elaborate an untyped protocol pair `(wireAction, payload)` into one typed
`Cmd(M)`. The implementation adapter receives only the corresponding
summand's native input.

Interface well-formedness is written:

```text
⊢ M interface
```

The judgment holds exactly when all referenced MITL types are well formed,
stable IDs are unique, primary labels and aliases are collision-free, action
phases are disjoint, paths are valid for their roots, and observations exactly
cover the comparison schema. This is the judgment established by the Mirrors
resolver before any target emitter runs.

### 8.6 Type-indexed semantic equivalence

Model equivalence is a family of relations indexed by type:

```text
v ≃τ w
```

It is defined structurally:

- integers, booleans, strings, and `null` compare by their canonical values;
- sequences and tuples compare pointwise in order;
- records compare fieldwise by exact label, independent of field order;
- sets compare extensionally under `≃τ`, independent of presentation order;
- maps compare by unique key association under `≃τk` and `≃τv`, independent
  of entry order; and
- variants compare only when their tags are equal and their payloads are
  equivalent at the type declared for that tag.

All well-typed sets and maps satisfy their uniqueness premises. An invalid
container does not become valid merely because extensional comparison would
hide a duplicate.

`≃τ` is the cross-language value oracle. Host-language equality is not.

### 8.7 Interpretation into a target language

For every target profile `L`, type generation is an interpretation:

```text
⟦τ⟧L          native representation type
⟦Port(M)⟧L    native generated port interface
⟦Binding(M)⟧L native generated binding interface
```

The interpretation need not preserve surface syntax or representation
identity. It must preserve the introduction and elimination behavior of every
MITL constructor.

Define a logical relation between a native value and a model value:

```text
x RLτ v
```

This means native `x : ⟦τ⟧L` represents model value `v : τ`. Generated codecs
must satisfy:

```text
decodeLτ(v) = ok(x)  implies  x RLτ v
encodeLτ(x) = ok(v)  implies  x RLτ v

decodeLτ(v) = ok(x) and encodeLτ(x) = ok(v') imply v' ≃τ v
encodeLτ(x) = ok(v) and decodeLτ(v) = ok(x') imply x' ≈Lτ x
```

`≈Lτ` is target equality induced by `RLτ`, not arbitrary host equality. These
laws are required for all values within the portable profile's resource
bounds.

The interpretation also obeys:

1. **Constructor separation.** A target may reuse one carrier type for two
   MITL types, but the generated type shape must retain the constructor needed
   for exact ITF encoding.
2. **No narrowing.** `Int` has no fixed-width or floating-point intermediate.
3. **Closed elimination.** Record decoding rejects extra and missing labels;
   variant decoding rejects unknown tags.
4. **Semantic collections.** Set and map validation uses `≃τ`, not pointer,
   object-identity, or a mismatched host hash relation.
5. **Total checked conversion.** Decoders and encoders return a value or a
   classified failure; they never use undefined behavior, unchecked casts, or
   implicit defaults.

### 8.8 Target realization obligations

This specification deliberately does not assign concrete target types or
declaration syntax to MITL constructors. A target profile chooses those
representations in a separate profile specification and proves their
suitability through `RLτ`.

Every target realization must provide:

- an unbounded representation of `Int`;
- distinct interpretations of the primitive MITL types;
- finite ordered interpretations of `Seq` and `Tup`;
- finite labeled-product and labeled-sum interpretations for `Rec` and `Var`;
- checked representations of `Set` and `Map` that preserve `≃τ`;
- a representation of `Comp[τ]` that sequences one synchronous computation
  and preserves classified failure; and
- total checked conversions between supported native values and model values.

Two MITL types may share a target carrier only when the generated shape still
determines their distinct introduction, elimination, and ITF encoding rules.
Reference identity, pointer identity, object identity, or another incidental
representation relation is never model equality.

A target MAY support types beyond the common baseline. Unsupported types MUST
fail emission with `MIC-E-TYPE-001` and MUST NOT be represented by an untyped
escape hatch.

### 8.9 Portable version-1 baseline

An interface is cross-language portable in version 1 only when it stays within
this common capability set:

| Feature | Required portable support |
| --- | --- |
| Primitive types | `Int`, `Bool`, `Str`, `Null` |
| Containers | `Set`, `Seq`, fixed `Tup`, closed `Rec` |
| Maps | `Map[Str, τ]` only |
| Variants | Closed `Var` types with declared payload types |
| Paths | `field`, `index`, `variantValue` |
| Opaque values | Not supported |
| Map-key paths | Not supported |

Every version-1 target profile MUST implement this baseline before claiming
cross-language conformance. A lock using a valid language-neutral feature
outside the baseline may still be emitted by a profile that explicitly
supports it, but it is not portable across all version-1 clients.

The common resource limits are also part of the portable baseline:

| Resource | Maximum |
| --- | ---: |
| Initializers | 32 |
| Transition actions | 256 |
| Aliases per action | 16 |
| Inputs per action | 128 |
| Observations | 1,024 |
| Path segments | 32 |
| Structural type depth | 32 |
| Normalized type nodes | 8,192 |
| Stable name length | 256 UTF-8 bytes |

Target profiles MAY impose a smaller limit only when they fail deterministically
during emission and document the restriction. They MUST NOT accept an
interface and then truncate it.

## 9. Input projection and native decoding

The binding projects each action input from exactly one declared root:

- initializer inputs use `initialState`;
- transition inputs use `stepParameters`.

`initialState` means the `initial_state.state` payload after the root-only
`Core.Value.filterMeta` rule removes keys beginning with `#`, plus
`action_taken` and `parameters`. Parameter repartition has already excluded
effective parameter variables from this state. `stepParameters` means the
complete `next_step.parameters` payload produced by the same resolved run
profile. An emitter MUST NOT invent a different root normalization rule.

Paths are evaluated in declared order and support:

```text
field(name)
index(zeroBasedIndex)
mapKey(canonicalItfLiteral)
variantValue(tag)
```

Path typing is the judgment:

```text
τ ⊢ π : τ'
```

It states that path `π`, when started at a value of type `τ`, selects a value
of type `τ'`. Representative rules are:

```text
l:τ ∈ Rec[..., l:τ, ...]
────────────────────────
Rec[..., l:τ, ...] ⊢ field(l) : τ

0 <= i < n
──────────────────────────────────────
Tup[τ₀, ..., τₙ₋₁] ⊢ index(i) : τi

c:τ ∈ Var[..., c:τ, ...]
─────────────────────────────
Var[..., c:τ, ...] ⊢ variantValue(c) : τ

τ₀ ⊢ π₁ : τ₁    τ₁ ⊢ π₂ : τ₂
────────────────────────────────
τ₀ ⊢ π₁ / π₂ : τ₂
```

Sequence indices and map-key paths have analogous rules when supported by the
target profile. The resolver establishes path typing; emitters preserve the
derivation rather than attempting target-specific path inference.

Path evaluation is written:

```text
v ⊢ π ⇓ w
```

It is a partial, deterministic elimination of a well-typed model value.
Missing fields, out-of-range indices, absent map keys, and mismatched variant
tags produce `input_shape_mismatch`.

Native decoding is the target-indexed judgment:

```text
L; τ ⊢ v ⇓decode x
```

It holds only when `⊢ v : τ` and `x RLτ v`. The generated decoder implements
this judgment and carries the stable action/input IDs in its diagnostic path.

A target profile MAY reject a path segment it has not implemented. It MUST NOT
replace an unsupported path with a partial lookup or default value.

For one callback, the binding MUST decode and validate **all** inputs before
calling the implementation handler. Missing fields, extra fields in a closed
record, type mismatches, duplicate set values, duplicate map keys, invalid
variant tags, and out-of-range indices are input failures. No implementation
handler may have run when such a failure is reported.

Input record field order is not semantic. Path, sequence, and tuple order is
semantic and MUST be preserved.

## 10. Observation encoding

After a successful handler, the binding MUST:

1. invoke `observe()` exactly once;
2. verify the observation record has exactly the declared fields;
3. validate every native value against its resolved model type;
4. encode every observation under its exact `wireName`; and
5. return the complete state expected by the existing client replay loop.

Native encoding is the dual judgment:

```text
L; τ ⊢ x ⇓encode v
```

It holds only when `x RLτ v` and `⊢ v : τ`. If
`ObsM = Prod[o₁:τ₁, ..., oₙ:τₙ]`, and observation `oi` maps to wire name `li`,
complete observation encoding is:

```text
L; τ₁ ⊢ x₁ ⇓encode v₁    ...    L; τₙ ⊢ xₙ ⇓encode vₙ
────────────────────────────────────────────────────────
L; M ⊢ obs[o₁=x₁, ..., oₙ=xₙ]
       ⇓report rec[l₁=v₁, ..., lₙ=vₙ]
```

The premise requires the actual stable-ID fields to be exactly those of
`ObsM`. There is no rule for an extra, missing, or ill-typed observation.
Those cases produce `observation_shape_mismatch`.

No observation value may be copied from the oracle, expected state, input
payload, or previous reported state by generated code.

Record output key order SHOULD be deterministic. Set and map container order
is not semantically significant, but target conformance tests MUST use a fixed
order when asserting exact JSON bytes. General cross-language comparisons use
decoded Mirrors value equality.

## 11. Binding lifecycle and invocation order

Every binding starts in `fresh` and implements this state machine:

```text
fresh --initializer success--> initialized
initialized --initializer success--> initialized
initialized --transition success--> initialized
fresh --transition-----------> poisoned
fresh/initialized --failure--> poisoned
poisoned --any callback------> poisoned
```

For each successful callback, the exact order is:

```text
classify wire action or alias
-> verify initializer/transition lifecycle
-> project and validate all inputs
-> invoke exactly one port handler
-> invoke observe exactly once
-> validate and encode the complete observation
-> increment coverage for the primary stable action ID
-> return report state
```

The binding dynamics are summarized by two judgments:

```text
M; P ⊢ <q, wireAction, payload> ⇓ <q', report, stableActionId>
M; P ⊢ <q, wireAction, payload> ⇑ <poisoned, bindingError>
```

Here `M` is a well-formed interface, `P : Port(M)`, and `q` is `fresh` or
`initialized`. A successful initializer rule has the shape:

```text
classifyM(wireAction) = a       phaseM(a) = initialize
project/decodeM,L(a, payload) = ok(input)
P.a(input) ⇓ ok(())             P.observe() ⇓ ok(obs)
encodeM,L(obs) = ok(report)
─────────────────────────────────────────────────────────
M; P ⊢ <q, wireAction, payload>
       ⇓ <initialized, report, a>
```

The transition rule has the additional premise `q = initialized`. Each failed
premise selects the stable error code for its stage and produces the failure
judgment. An adapter or observation premise is effectful; all classification,
lifecycle, projection, and decoding premises precede it.

Additional invariants:

1. A later initializer begins a new trace and the adapter MUST fully reset the
   SUT.
2. Calls are serial and non-reentrant.
3. Unknown actions are never ignored.
4. Coverage is incremented only after a complete report state is constructed.
5. Aliases increment coverage for their primary stable action ID.
6. A failed handler is assumed to have possibly mutated the SUT; the binding
   is therefore poisoned.
7. A failed observation occurs after mutation and also poisons the binding.
8. A poisoned binding never calls the port again.
9. `prevState` MAY be accepted by the client `StateComputer` shim but MUST be
   ignored and MUST NOT be retained.

### 11.1 Safety obligations

Generated target implementations must satisfy the following metatheoretic
properties for every `⊢ M interface` within the profile's supported subset:

1. **Mechanical progress.** For every bounded action/payload pair, the
   generated mechanics either reach one port call, return a classified binding
   error, or wait in the application adapter. They never become stuck in
   dispatch, projection, or conversion. Progress does not claim that an
   arbitrary external SUT terminates.
2. **Preservation.** If the success judgment returns `report`, then every
   report value is well typed at its declared observation type, and the report
   contains exactly the comparison wire names.
3. **Deterministic mechanics.** Given the same descriptor, payload, lifecycle
   state, and port outcomes, classification, projection, conversion, coverage,
   and error priority produce the same result in every target.
4. **Effect isolation.** No port handler is invoked until all input typing and
   decoding premises hold. No `observe()` is invoked unless exactly one action
   handler succeeds.
5. **Poison safety.** A failure judgment makes every later callback yield
   `binding_poisoned` without another port effect.

Mirrors may prove these properties for the language-neutral resolver and
abstract dynamics. Foreign generated code demonstrates that it is a faithful
interpretation through compilation, common vectors, and real trace replay;
the proof claim does not automatically extend through a foreign compiler or
the SUT.

## 12. Symbol identity

Stable IDs are ASCII and match `[A-Z][A-Za-z0-9]*`. They are the only
cross-language identifiers. Target names are deterministic interpretations and
do not participate in semantic identity.

Each profile defines a naming interpretation:

```text
nameL : SymbolNamespace × StableId -> TargetName + NameError
```

`SymbolNamespace` distinguishes model, action, input, observation, port,
binding, error, metadata, and factory symbols. Within each namespace, `nameL`
must be injective for the symbols of one generated interface. It must also be
stable across machines and invocations.

Target lexical rules, keywords, escaping, capitalization, and declaration
syntax belong only to the target-profile specification. If the interpretation
cannot produce distinct valid target names, emission fails with
`MIC-E-NAME-001`; it MUST NOT guess an unstable suffix.

Wire action labels, aliases, observation wire names, record field wire names,
and variant tags are data. They MUST never be case-converted into different
wire values.

## 13. Binding errors

Every profile MUST preserve these stable generated-binding error codes:

| Code | Meaning |
| --- | --- |
| `configuration_mismatch` | Effective runtime parameter partition differs from the lock. |
| `unknown_action` | No primary action or alias accepts the wire label. |
| `transition_before_initialization` | A transition was requested while `fresh`. |
| `input_shape_mismatch` | Projection or native decoding failed before handler invocation. |
| `adapter_failure` | The implementation handler failed. |
| `observation_shape_mismatch` | Observation or native-to-ITF encoding failed. |
| `binding_poisoned` | A callback was attempted after a prior binding failure. |

The error carrier is profile-specific, but the code and failure priority are
not. Its interpretation MUST preserve a stable code, bounded diagnostic
context, and the distinction between success and failure. A client with an
existing infallible `StateComputer` interface MUST add a source-compatible
fallible internal hook for negotiated generated bindings; it MUST NOT encode a
local binding failure as a fake model state.

Existing handwritten `StateComputer` callers MUST remain source-compatible.
Generated-binding failures stay distinct from server `register_error`, Mirrors
`step_mismatch`, transport failure, and local registry-selection errors.

## 14. Runtime configuration

`bind` MUST validate every replay-shaping configuration field committed by the
semantic lock before the first SUT action. Version 1 requires exact agreement
for the effective parameter variable:

```text
normalize(runtime.paramVars) == lock.runProfile.configuredParamVar
```

The empty client value normalizes to `none`. A mismatch returns
`configuration_mismatch` and invokes no port or SUT operation.

A local binding factory MUST create one fresh binding and one fresh SUT handle
per Mirrors session. Mutable bindings MUST NOT be stored as process-global
singletons.

The client runtime exposes this language-neutral local shape:

```text
LocalBinding = {
  semanticDigest          : SemanticDigest,
  computer                : StateComputer,
  assertCompatibleConfig  : EffectiveConfig -> Unit,
  coverage?               : Unit -> Map<StableActionId, Nat>,
  dispose                 : Unit -> Effect<Unit>
}

AdapterFactory = EffectiveConfig -> Effect<LocalBinding>
```

The factory composes the deterministic generated binding with the
application-owned implementation adapter and cleanup. The runner rechecks the
returned digest and configuration even when they were checked before lookup.

SUT cleanup is application-specific and therefore belongs to the local binding
factory, not the generated model port. The negotiated runner MUST dispose its
local binding exactly once on success and on every failure after construction.

## 15. Target profiles

Every target profile specifies:

```text
targetProfile
profileVersion
stateComputerContractVersion
supported model types and path segments
native type mapping
native naming and reserved words
error carrier
client imports/dependencies
deterministic file layout and rendering
```

Version-1 profile identifiers are:

| Client | Profile | Status |
| --- | --- | --- |
| MirrorECMA | `mirrorecma-v1` | Implemented reference profile. |
| MirrorCPP | `mirrorcpp-v1` | Implemented static C++23 profile. |
| MirrorRust | `mirrorrust-v1` | Planned static profile. |
| MirrorLean | `mirrorlean-v1` | Planned static profile. |

All four profiles target `mirrors.state-computer/v1` semantics. A profile MUST
use the client's public `Value`, `State`, and replay interfaces rather than
generating an independent JSON or protocol stack.

### 15.1 Separation from target grammar

This shared specification contains no target declaration grammar, target type
names, imports, ownership syntax, error syntax, or source templates. Each
target profile defines those choices separately as an interpretation of MITL.

A target-profile specification is conforming only when it states `⟦τ⟧L`,
`nameL`, `CompL`, ownership, and rendering rules and demonstrates the common
judgments and dynamics. Adding a new target profile does not modify MITL.

### 15.2 `mirrorcpp-v1`

`mirrorcpp-v1` emits one `<Model>Mirror.generated.hpp` header plus
`.model-interface-generated.json`. It requires C++23 and the public
`mirrorcpp/mirrorcpp.hpp` API and targets
`mirrors.state-computer/v1`.

Its native interpretation is:

| MITL type | Generated C++ type |
| --- | --- |
| `Int` | `mirrorcpp::Value::Int` |
| `Bool`, `Str`, `Null` | `bool`, `std::string`, `MirrorNull` |
| `Set[T]`, `Seq[T]` | `MirrorSet<T>`, `MirrorSeq<T>` |
| `Tup[T...]` | `MirrorTuple<T...>` |
| `Rec[l:T...]` | `MirrorRecord<RecordField<"l", T>...>` |
| `Map[Str,T]` | `MirrorMap<T>` |
| `Var[c:T...]` | `MirrorVariant<VariantCase<"c", T>...>` |

The profile supports `field`, `index`, and `variantValue` paths. It rejects
non-string map keys and opaque types with `MIC-E-TYPE-001`, and rejects
`mapKey` paths with `MIC-E-PATH-001`. Stable model/action/input/observation IDs
must be portable ASCII C++ identifiers; keywords, leading underscores, and
collisions after lowercasing the first letter fail with `MIC-E-NAME-001`.

Generated `BindingError` derives from
`mirrorcpp::ModelInterfaceBindingError`. The generated binding classifies
input, dispatch, adapter, observation, configuration, lifecycle, and
reentrancy failures and permanently poisons itself after a failed callback.
MirrorCPP's negotiated runner converts that internal carrier into
`ErrorKind::model_interface`, preserves the stable code, disposes the binding,
and keeps ordinary server `step_mismatch` separate.

## 16. Generated metadata and owned files

Every generated target module MUST expose the semantic digest and normalized
contract in client-native inert data:

```text
GeneratedMetadata = {
  semanticDigest : SemanticDigest,
  contract       : ContractV1
}
```

The metadata MUST NOT include executable handler bodies, SUT locations,
credentials, package names to load, or network URLs.

Every generated tree includes an ownership manifest with this abstract shape:

```text
GeneratedOwnershipManifest = {
  schema          : "mirrors.model-interface-generated/v1",
  targetProfile   : TargetProfileId,
  profileVersion  : Nat,
  semanticDigest  : SemanticDigest,
  files           : SortedList[RelativePath]
}
```

The file list is target-specific and sorted. Generation may replace or remove
only paths owned by the preceding valid manifest. It MUST NOT recursively
clean the output directory or modify the implementation adapter.

Generated source MUST contain a header with generator identity, target
profile, profile version, semantic digest, and `DO NOT EDIT`. It MUST contain
no timestamp or absolute path.

## 17. Determinism

Given the same verified lock, target profile, and profile version, an emitter
MUST produce byte-identical generated files.

Required file rules:

1. UTF-8 without BOM;
2. LF line endings;
3. exactly one final newline;
4. stable file and declaration order;
5. fixed native identifier lowering;
6. fixed imports/includes and formatting;
7. canonical embedded contract data;
8. no locale, timezone, current directory, environment, random value, or hash
   table iteration in output; and
9. no external formatter as an implicit generation input.

Actions, inputs, observations, record fields, variant cases, aliases, and
owned paths use their documented canonical sort rules. Paths, sequences, and
tuples preserve semantic order.

Different target profiles are not expected to produce identical source bytes.
They are expected to embed the same semantic digest and pass the same
behavioral vectors.

## 18. Negotiated runtime integration

The generated interface is local to the client. Server messages never contain
or authorize executable adapter code.

The required runtime sequence is:

```text
load inert generated metadata
-> resolve exact local adapter registry key without constructing the SUT
-> send normalized contract and expected semantic digest
-> receive and validate `matched`
-> recheck exact digest
-> create one fresh local binding
-> recheck binding digest and effective configuration
-> enter the existing replay loop through StateComputer
-> dispose the local binding exactly once
```

Under required negotiation, no implementation handler, observer, SUT
constructor, or adapter factory may run before `matched` is validated.

This sequence is transport-independent after authorization. Local stdio is
trusted. Plain TCP has no model-interface authority in version 1. An mTLS
server grants verification only when the operator allowlists the exact client
leaf certificate fingerprint.

## 19. Compatibility

Any change to the canonical semantic descriptor changes the semantic digest.
This includes action, phase, input projection, type, observation, run-profile,
resolver-semantics, or comparison-policy changes.

Compatibility rules:

- adding a required action is breaking for exhaustive adapters;
- removing an action is breaking;
- changing an action phase is breaking;
- adding, removing, or changing a required input is breaking;
- changing a projection path is breaking;
- changing a model type is breaking unless the normalized type is identical;
- adding, removing, renaming, or changing an observation is breaking;
- adding a wire alias changes semantic identity even though the primary
  handler remains the same;
- target formatting changes may increment profile version without changing
  semantic digest; and
- provenance-only changes may change provenance digest without changing
  semantic digest.

Clients MUST continue selecting exact digests. `interfaceVersion` is useful to
humans and tooling but never authorizes a structurally different adapter.

## 20. Security requirements

Generated interfaces and runtime descriptors are data, never code-loading
instructions.

A conforming implementation MUST NOT:

- compile or evaluate source received from Mirrors;
- load a package, plugin, library, or symbol named by remote data;
- retrieve an executable adapter over the network;
- construct the SUT before required digest verification;
- expose expected state to the implementation adapter;
- continue after a poisoned binding; or
- treat the semantic digest as transport authentication.

The digest proves content identity. TLS identity, CA verification, SAN
verification, certificate pinning, and model-interface allowlists establish
transport trust and authorization.

## 21. Cross-language conformance suite

Every profile MUST run the same language-neutral fixture families.

### 21.1 MITL judgment fixtures

All targets consume shared fixtures that exercise the abstract language rather
than target source text:

```text
test/fixtures/model-interface/language/mitl-types.jsonl
test/fixtures/model-interface/language/mitl-values.jsonl
test/fixtures/model-interface/language/mitl-equivalence.jsonl
test/fixtures/model-interface/language/counter-binding-events.jsonl
```

The fixtures cover:

- positive and negative `⊢ τ type` derivations;
- positive and negative `⊢ v : τ` derivations;
- closed-record, closed-variant, set-uniqueness, and map-key-uniqueness rules;
- type-indexed equivalence `≃τ`, including presentation-order differences;
- both directions of the `RLτ` codec laws;
- arbitrary-precision integers outside every fixed-width machine range;
- constructor separation for `Null`, empty tuple, and empty record; and
- path-typing and path-evaluation judgments.

Each target may use a different native test value, but expected well-formedness,
equivalence, canonical ITF result, and stable error code are shared.

### 21.2 Compile-time fixtures

- canonical Counter lock compiles;
- emitted metadata contains the expected semantic digest and contract;
- independent source ordering and formatting do not change output;
- reserved-name and native-name collisions fail deterministically;
- every supported structural type compiles;
- unsupported type and path cases fail without partial output; and
- the generated ownership manifest lists exactly the owned files.

### 21.3 Recording-port fixtures

For common raw `StateComputer` stimuli, normalize an event log using stable
IDs, not native method names:

```json
{"event":"action","id":"Initialize","inputs":{}}
{"event":"observe","values":{"Count":{"#bigint":"0"}}}
{"event":"report","state":{"count":{"#bigint":"0"}}}
{"event":"action","id":"Tick","inputs":{"Stride":{"#bigint":"2"}}}
{"event":"observe","values":{"Count":{"#bigint":"2"}}}
{"event":"report","state":{"count":{"#bigint":"2"}}}
```

All targets MUST produce equivalent event logs. Exact JSON bytes are required
where order is fully canonical; otherwise decoded ITF semantic equality is the
oracle.

The recording suite also covers:

- primary labels and every alias;
- initializer after an initialized trace;
- transition before initialization;
- unknown action;
- missing, extra, and mistyped input values;
- all-input validation before mutation;
- missing, extra, and mistyped observations;
- adapter and observer failures;
- permanent poisoning after failure;
- exact observation count and action/observation order;
- coverage by primary stable ID; and
- runtime configuration mismatch before any port call.

### 21.4 Real Counter acceptance

Each target MUST implement an adapter around a mutable Counter SUT and pass:

1. the authoritative `specs/Counter.tla` source digest;
2. compiler lock and generated-source freshness checks;
3. a real Apalache-generated trace;
4. `Initialize`, `Tick(2)`, and `Tick(3)` dispatch;
5. count-only reports `0`, `2`, and `5`;
6. exact declared-action coverage;
7. a deliberately incorrect observer reaching Mirrors `step_mismatch`; and
8. required-negotiation failure making zero adapter/SUT calls.

At least one server-mode acceptance leg MUST use allowlisted TLS 1.3 mTLS.

## 22. Compiler module interface

The compiler implementation exposes pure decision procedures corresponding to
the specification judgments:

```text
wellFormedType       : Type -> Bool
modelValueHasType    : Type × ModelValue -> Bool
modelValueEquivalent : Type × ModelValue × ModelValue -> Bool
pathResultType       : Type × Path -> Option[Type]
```

Statics and equivalence are defined once in the pure compiler module; target
emitters do not redefine them. Generated target codecs are interpretations of
those judgments and are checked by the common vectors.

Once the second target exists, Mirrors should expose one target dispatch
interface while retaining target-specific implementations:

```text
emitGeneratedInterface :
  TargetProfile × LockedModelInterface
  -> GeneratedTree + List[EmitDiagnostic]
```

The public compiler interface remains small:

```text
resolve(normalized facts) -> semantic lock
emitGeneratedInterface(profile, semantic lock) -> generated tree
```

Each target emitter is an adapter behind that seam. Shared code SHOULD cover
semantic ordering, collision discovery, portable type/path traversal, owned
tree validation, and common conformance-vector construction. Native syntax,
imports, type spelling, error carrier, and rendering remain local to the
target emitter.

Do not introduce a universal target-language AST. It would expose the union of
four language grammars and make the module shallow. The semantic descriptor is
the shared interface; target source models remain private implementation.

## 23. Implementation sequence

1. Freeze the MITL syntax, statics, dynamics, and common judgment vectors.
2. Make the existing `Core.ModelInterface.ModelType` validation and path
   checking explicitly correspond to `⊢ τ type` and `τ ⊢ π : τ'`.
3. Add executable value-typing, `≃τ`, and codec-law fixtures without replacing
   the existing proved Mirrors `Value` equality.
4. Extract language-neutral emitter validation only where the current
   TypeScript implementation and the C++ implementation demonstrate actual
   duplication.
5. Implement `mirrorcpp-v1` from the existing Counter lock. **Done.**
6. Add a fallible negotiated-runner hook without breaking existing
   `StateComputer` callers. **Done in MirrorCPP.**
7. Require C++ and TypeScript to pass identical judgment, recording, and real
   Counter acceptance tests. **Real Counter acceptance is implemented; common
   judgment/recording vectors remain.**
8. Implement `mirrorrust-v1` and `mirrorlean-v1` from the same lock and vectors.
9. Add all generated targets to `model_interface_gen check` and the top-level
   interop matrix. **Done for TypeScript and C++; pending for Rust and Lean.**

## 24. Acceptance criteria

This specification is implemented across languages when:

1. MITL type/value/path judgments and `≃τ` have one executable Core definition
   and common cross-language vectors;
2. every target interpretation satisfies the checked `RLτ` encode/decode laws
   for the portable baseline;
3. the generated mechanical dynamics satisfy progress, preservation, effect
   isolation, and poison safety within the stated proof/test scope;
4. one semantic lock generates compiling ports and bindings for TypeScript,
   C++, Rust, and Lean;
5. every target embeds the same semantic digest and normalized contract;
6. every implementation adapter sees only typed per-action inputs and complete
   observations;
7. common stimuli produce equivalent stable-ID event logs and semantically
   equal reported state;
8. lifecycle, poisoning, error codes, and coverage match across targets;
9. arbitrary-precision integers and all supported composite types round-trip
   without narrowing or host-identity leaks;
10. unsupported interfaces fail during target emission rather than at replay;
11. negotiated selection constructs no SUT before exact digest verification;
12. existing handwritten `StateComputer` callers remain source-compatible;
13. every target passes the real Counter trace and deliberate mismatch test;
14. at least one mTLS server-mode test passes for every client; and
15. the unified interop matrix remains green.

## 25. Result

The portable interface is the combination of:

```text
canonical semantic descriptor
+ exact semantic digest
+ generated-port behavior
+ generated-binding lifecycle
+ versioned target profile
+ common conformance vectors
```

That combination gives all client languages one semantic interface while
allowing each language to retain idiomatic types, ownership, and errors. The
LLM maps the real implementation only to the small generated port. Mirrors and
the deterministic binding continue to own every mechanical protocol concern.
