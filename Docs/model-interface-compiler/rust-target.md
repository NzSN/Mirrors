# Rust target: `mirrorrust-v1`

Profile version 1 generates a synchronous Rust module from the same verified
semantic lock as the TypeScript and C++ targets. Generation and freshness
checking require only Mirrors; compiling the output requires Rust 2021,
`mirrorrust` with the public model-interface API, and `num-bigint = "0.4"`.

```sh
.lake/build/bin/model_interface_gen generate \
  --lock test/fixtures/model-interface/counter/Counter.mirror-interface.lock.json \
  --target mirrorrust-v1 --out generated/rust

.lake/build/bin/model_interface_gen check \
  --spec specs/Counter.tla \
  --contract test/fixtures/model-interface/counter/Counter.mirror-interface.json \
  --evidence test/fixtures/model-interface/counter/counter.itf.json \
  --param-var parameters \
  --lock test/fixtures/model-interface/counter/Counter.mirror-interface.lock.json \
  --target mirrorrust-v1 --out generated/rust
```

The owned files are `CounterMirror.generated.rs` and
`.model-interface-generated.json`. Include the source as a module using
`#[path = "..."] mod counter;`. Output is deterministic UTF-8 with LF endings,
no timestamps, canonical embedded contract JSON, and the unchanged semantic
digest. Existing owned-file publication and stale-file checks apply.

## Native interface

The module exports `SEMANTIC_DIGEST`, `CONTRACT_JSON`, `model_interface()`,
`assert_compatible_config`, input structs, `<Model>Observation`, `<Model>Port`,
`<Model>Binding`, and `bind_<model>`. Port actions return
`Result<(), BindingError>`; `observe` returns the typed observation in a
`Result`. Methods and stable-ID fields use lowercase names with `_` before
each subsequent capital (`Tick` becomes `tick`, `HTTP` becomes `h_t_t_p`).
Invalid ASCII alphanumeric identifiers, Rust keywords, lowered collisions,
and the reserved `observe` method are rejected with `MIC-E-NAME-001`.

| Model type | Native type |
| --- | --- |
| Int | `num_bigint::BigInt` |
| Bool / Str | `bool` / `String` |
| Null | `MirrorNull` |
| Seq / Set | `MirrorSeq<T>(Vec<T>)` / `MirrorSet<T>(Vec<T>)` |
| Map[Str,T] | `MirrorMap<T>(BTreeMap<String,T>)` |
| Tuple / Record | Generated struct with typed `field_0`, `field_1`, … |
| Variant | Generated enum with typed `Case0(T)`, `Case1(T)`, … |

Composite names are deterministic `MiTypeA<action-index>I<input-index>` or
`MiTypeO<observation-index>`, followed by `F<index>`, `C<index>`, or `Item` for
nested nodes. Action/input/observation IDs, record keys, and variant tags sort
lexically; tuple fields retain positional order. Numeric record/variant member
names preserve arbitrary wire keys without identifier escaping or collisions.
`NativeCodec` exposes checked conversion using MirrorRust `Value`.
Null, empty tuples, and empty records remain distinct. Sets reject duplicates
using recursive semantic equality, including reordered nested sets/maps.
Closed records reject missing and extra fields. Maps reject duplicate keys.
`opaqueItf`, non-string map keys, and `mapKey` projections fail at emission;
field, index, variant-value, and empty-root projections are supported. Indices
above the 32-bit portable `usize` range are rejected at emission.

## Binding ownership and lifecycle

`bind_counter(port, &config)` owns its port and checks the effective parameter
variable before invoking it. The binding implements `FallibleStateComputer`.
It decodes every input before mutation, invokes one handler followed by one
observation, and reports only declared observations. Coverage counts successful
callbacks by stable ID; aliases dispatch to that same ID. Initializers may
reset an initialized binding. A transition before initialization, unknown action,
decoding failure, adapter error, observation error, or unwinding panic poisons
the binding permanently. Rust mutable borrowing prevents safe reentrant calls.
Panic-abort builds terminate the process instead of unwinding.

`coverage()` returns a snapshot; `assert_all_actions_covered()` checks all
declared actions. `into_local_binding()` consumes a binding whose port is
`'static` and supplies MirrorRust's negotiated runner with its computer,
semantic digest, and config checker. The port is released through Rust `Drop`
when the local binding is dropped; its runtime disposal callback is a no-op.

Construct the SUT **inside** a registered deferred factory, after the client
validates `matched`, for example:

```rust
factory: Box::new(|context| {
    let port = CounterAdapter::new();
    counter::bind_counter(port, context.effective_config())?.into_local_binding()
})
```

Use `counter::model_interface()` for inert selection metadata and
`mirrorrust-v1` for the registry target profile. Direct binding construction
alone does not establish the negotiated construction barrier.

## Validation boundary

`lake test` always checks Rust golden freshness and emitter rejection cases.
With Cargo and `RUST_REPO` (default `../MirrorRust`), it also runs
`bash tools/model-interface-rust/check.sh`. That harness compiles Counter and
a generated structural corpus against the actual Rust client, tests codecs,
coverage, all-input validation, errors and poisoning, and performs negotiated
stdio replay with both correct and deliberately incorrect observations.
Negotiation mismatch must invoke no adapter factory. The existing pinned
Counter trace is replayed; this gate does not generate fresh Apalache traces.
Missing native prerequisites produce an explicit skip. Rust mTLS acceptance
and the proposed common cross-language recording vectors remain unverified by
this harness.
