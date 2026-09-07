# Semantic Notation for Mirrors Documentation

Explanations of algorithms, interfaces, and resource lifecycles use the
judgment-based method of Robert Harper's
[Practical Foundations for Programming Languages](https://www.cs.cmu.edu/~rwh/pfpl/).
The distinction between expressions and commands follows the
[Modernized Algol supplement](https://www.cs.cmu.edu/~rwh/pfpl/supplements/ma-derived.pdf).
The domain types, indexed authorities, and resource scopes in these documents
are Mirrors specification constructs. They do not name a shipped programming
language, add wire operations, or assert that a complete metatheory has been
proved.

## Metalanguage and object language

The **metalanguage** describes which programs, values, and transitions are
valid. Its metavariables range over explicitly defined syntactic categories:

| Metavariable | Ranges over |
| --- | --- |
| `τ`, `τ′`, `υ` | Types |
| `e`, `v` | Expressions and values |
| `m` | Commands that can perform effects |
| `Γ` | Typing assumptions, such as `x : τ` |
| `M`, `L` | A resolved model interface and a target profile |
| `H` | Runtime resource, authority, and implementation state |
| `q` | A local protocol or binding phase |
| `σ`, `ι` | A fresh session identity and an exact interface identity |
| `ε`, `D` | A tagged failure and a sequence of diagnostics |

A document may introduce additional metavariables, judgments, or abstract
types at the point where they are needed. An abstract type such as
`ContractV1` or `SourceLocation` denotes the semantic data described by that
document; its spelling does not import a Lean or TypeScript declaration.

The **object language** consists of the expressions, values, and commands
described by those judgments. The symbol `⊢` belongs to the metalanguage;
an expression such as `cmd(m)` belongs to the object language.

```text
⊢ τ type                       τ is a well-formed type
Γ ⊢ e : τ                      e has type τ under Γ
Γ ⊢ m ÷ τ                      m produces a τ if it returns normally
I ⊢ resolve ⇓ (ℓ, D)            input I resolves to lock ℓ and diagnostics D
I ⊢ resolve ⇑ D                 resolution rejects I with diagnostics D
⟨H; m⟩ ↦ ⟨H′; m′⟩             one execution step
⟨H; m⟩ ⇓ ⟨H′; v⟩              execution terminates with value v
⟨H; m⟩ ⇑ ⟨H′; ε⟩              execution terminates with tagged failure ε
```

`⇓` and `⇑` are different outcome judgments. A successful execution may change
`H`; a failed execution may also have performed effects before failing. An
absent terminating derivation does not by itself establish failure: execution
may still be waiting or may diverge.

An inference rule has premises above the line and a conclusion below it:

```text
J₁    ...    Jₙ
───────────────
       J
```

It permits deriving `J` from derivations of every premise. Side conditions such
as distinct labels, a valid principal, or an exact digest match are part of
the rule. Premises alone do not specify scheduling; execution order is given
by command sequencing or an explicit ordered transition relation.

## Types and data

`≜` introduces a definition. Products describe fields available together;
sums describe alternatives, each with its own payload:

```text
Prod[l₁:τ₁, ..., lₙ:τₙ]         finite labeled product
Sum[c₁:τ₁, ..., cₙ:τₙ]          finite labeled sum
1                               singleton command-result type
τ × υ                           positional binary product
Seq[τ]                          finite ordered sequence
Option[τ] ≜ Sum[none:1, some:τ]
Result[τ, υ] ≜ Sum[ok:τ, error:υ]
τ → υ                           function type
K ⇀ V                           partial map from keys to values
Singleton[s]                    type containing only s
ByteVector[n]                   sequence of exactly n bytes
SortedSeq[τ]                    sequence with the stated ordering invariant
```

Labels are distinct within a product or sum. `⟨l₁=v₁, ..., lₙ=vₙ⟩` is a
product value, and `e.l` selects its `l` component. `none` and `some(v)` are
option constructors. This notation describes semantic data; concrete JSON
field names, optional-field rules, canonical ordering, and byte encodings
remain governed by their wire or artifact specifications.

The model-value language separately defines `Int`, `Bool`, `Str`, `Null`,
sets, sequences, tuples, records, maps, and variants in the
[generated-interface specification](https://github.com/NzSN/Mirrors/blob/main/Docs/generated-model-interface-spec.md#8-model-interface-type-language).
Interface products use stable IDs; model records use wire labels. The
command-result singleton `1` is distinct from model `Null`. A mathematical
set of names is also distinct from a serialized ITF set value.

Writing `Session(σ)` or `Binding(σ,ι)` indexes a type by semantic identities.
Equal indices demand the same identity, not a similar name or version range.
Runtime-issued identities can be introduced under a fresh-name binder or
hidden in an existential package. These indices are specification devices;
they do not require a particular host-language type system. Runtime handle
ownership, liveness, authentication, and bounds still require validation.

These interface-level products, computations, and indices are separate from
the serialized MITL language. They add no variable binding, polymorphism,
dependent types, or executable commands to a version-1 model descriptor.

## Expressions, commands, and sequencing

An expression `cmd(m)` contains a suspended command. The type
`Comp[τ] ≜ τ cmd` is the computation type used throughout the interface
documents. It is not a serialized model type and does not by itself select
an asynchronous API. A synchronous target executes its command before the
native callback returns; target-specific asynchronous interfaces need their
own stated contract.

```text
Γ ⊢ e : τ                         Γ ⊢ m ÷ τ
────────────────                  ─────────────────────
Γ ⊢ ret(e) ÷ τ                    Γ ⊢ cmd(m) : Comp[τ]

Γ ⊢ e : Comp[τ]    Γ, x:τ ⊢ m ÷ υ
──────────────────────────────────
Γ ⊢ bnd(e; x.m) ÷ υ
```

The readable command `x ← m₁; m₂` abbreviates
`bnd(cmd(m₁); x.m₂)`. It runs `m₁` before entering `m₂` with the successful
result substituted for `x`. Failure propagates without entering that
continuation. A command that returns unit may use `_` for its ignored result.
Documents may write an abstract operation such as `observe(P)` as a command;
its surrounding text or typing judgment specifies its input and result types.

A command may eliminate a finite sum by cases. Each branch gets only its
constructor's payload, and all branches must have the same result type:

```text
Γ ⊢ e : Sum[c₁:τ₁, ..., cₙ:τₙ]    ∀i. Γ, xᵢ:τᵢ ⊢ mᵢ ÷ υ
───────────────────────────────────────────────────────────
Γ ⊢ case(e; c₁(x₁).m₁; ...; cₙ(xₙ).mₙ) ÷ υ
```

The readable form `case e of cᵢ(xᵢ) . mᵢ` uses the same rule. Executing a
case on constructor `cⱼ(v)` enters only `mⱼ`, with `v` substituted for `xⱼ`.

For example, the sequence below admits no action before input validation and
no observation before the action succeeds:

```text
input ← decodeAll(M, action, payload);
_ ← invoke(P, action, input);
observation ← observe(P);
report ← encodeObservation(M, observation);
ret(report)
```

`decodeAll` and `encodeObservation` denote checked conversions. `invoke` and
`observe` denote actual application operations. Their names do not authorize
generating a substitute model implementation or treating a type-correct
observation as a conformance verdict.

## Resource scopes and authority

A form such as `withSession(g, policy; σ, s.m)` binds a fresh session identity
`σ` and its handle `s` in command `m`. `withBinding(...; b.m)` binds a local
binding similarly. These are resource-scope primitives with an explicit
cleanup contract, rather than ordinary lambdas. They register cleanup during
acquisition, cover partial construction, and await cleanup on terminal paths.

Authority types such as `Matched(σ,ι)` are abstract. Only a trusted operation
that validates the required checks introduces a value of that type. Having
`Comp[Matched(σ,ι)]` gives a command that may produce authority; it does not
give authority before that command succeeds.

Ordinary product and function types allow duplication. At-most-once logical
release in these sketches therefore comes from the supervisor's atomic
resource-state transitions, not an unstated linear type discipline. Repeated
release joins existing cleanup. A cleanup deadline without confirmed physical
termination is a cleanup failure. Timers, scheduling, and backend enforcement
are operational assumptions, not consequences of a typing derivation.

Tagged outcomes preserve primary failures. If the body fails and cleanup also
fails, the body failure remains primary and cleanup diagnostics remain
secondary. Model mismatch, negotiation failure, infrastructure failure,
application failure, and cancellation retain their separate tags.

## Reading executable material

Operational shell commands, exact wire/artifact examples, concrete public API
references, and recorded debugger or reproduction evidence keep their native
syntax. They specify how to use or reproduce an implementation. Algorithm and
lifecycle explanations use the judgments and command language above. The
JavaScript and CSS that render the interactive architecture diagram are
executable documentation infrastructure.

A mathematical requirement is not automatically an implemented check or a
proved theorem. Each document retains its implementation-status statements,
source references, and acceptance evidence. A preservation, progress, or
representation-independence claim needs its own precise statement and proof;
passing finite traces establishes only the reported coverage.
