# Shared generated-interface conformance

These reviewed JSONL examples are shared by the Core judgment gate and native
consumers. `tools/model-interface-conformance/make-fixtures.py` is the explicit
authoring utility. Tests read the checked-in files; they never regenerate their
expected results.

`model_interface_language_spec` checks structural well-formedness, the portable
v1 baseline, value typing, type-indexed equivalence, and static/dynamic paths.
It also calls each real target emitter for supported and excluded types/paths.
The generated `Portable`, `Recording`, and `Path*` modules are synthetic test
interfaces. They share their semantic lock across targets but are not sealed
application models or qualification evidence.
The Core gate also pins the versioned type-depth, normalized-node, and wire-name
byte boundaries. The empty closed variant is represented as a native empty type;
an empty sequence of that type is valid, and any element is rejected.

| Fixture | Meaning |
| --- | --- |
| `mitl-types.jsonl` | Structural type, expected well-formedness, portable membership, and default values for supported types. |
| `mitl-values.jsonl` | Raw ITF value and expected strict type acceptance, including closed records/variants and semantic container uniqueness. |
| `mitl-equivalence.jsonl` | Both operands' type acceptance and expected type-indexed equality. |
| `mitl-paths.jsonl` | Static result type, dynamic result/error, and explicit target path exclusions. `stateRoot` exercises an empty projection on the complete input state. |
| `counter-binding-events.jsonl` | Raw binding stimuli, injected callback failures, exact stable-ID event order, errors, reports, and coverage. |
| `native-encoding.jsonl` | Invalid native containers constructed by the observation port, with encode-stage failure and permanent poisoning. |

The portable codec port receives every supported native type through generated
initializer decoding, then returns observations through generated encoding.
The reported state is decoded and encoded again through the same generated
binding. This exercises both codec directions, including arbitrary integers,
empty products, nested sets, maps, variants, and ordinary records containing
marker-looking wire keys. No adapter implements a substitute MITL validator.

The recording interface adds a boolean `Enabled` input projected through a
sequence and variant to Counter's `Stride` input. `init/reset` and
`tick/increment` dispatch by the same stable IDs. Its report remains count-only.
The fixtures cover initialization order, resets, every alias, all-input
validation before callbacks, unprojected fields, callback/observer failure,
permanent poisoning, coverage, and configuration mismatch. Separate live
acceptance uses the authoritative Counter model and lock.

Every successful recording step also passes its actual generated state to the
SDK's `report_state` encoder. The adapters retain those returned payload strings.
The verifier rejects duplicate JSON keys, wrong envelopes, altered states,
missing frames, and noncanonical bytes, even when the separate event/state log
is correct. This count-only corpus has fully specified canonical payload bytes.
The receipt includes hashes of the common raw-frame mapping and a JSONL artifact
formed by appending one LF to each verified SDK payload. Transport behavior is
still established by the separate interop gates.

Three malformed **native** observation-record cases run in TypeScript and its
async target. Lean and Rust reject those shapes during native construction;
the Rust and Lean gates each retain three compile-rejection diagnostics. C++ observation
objects always have the declared integer member, including default-constructed
aggregates; the consumer statically verifies its exact type. Those languages
do not claim runtime execution of unrepresentable missing/extra/mistyped native
records. Raw ITF missing/extra/mistyped **closed-record values** run through the
generated codecs in all five targets. Representable observer failures and
invalid native sets also run in every target.

Run from the Mirrors root after building the executable and preparing the SDKs:

```sh
lake build model_interface_language_spec
python3 tools/model-interface-conformance/check.py \
  --cpp-prefix /absolute/path/to/prepared/mirrorcpp
```

The runner requires the sibling MirrorECMA, MirrorRust, and MirrorLean checkouts
by default; `--ecma`, `--rust`, and `--lean` override them. TypeScript uses the
SDK's real compiler and public wire codec. C++ consumes its prepared package;
Rust builds offline with the SDK's existing lock as its dependency seed; Lean
builds an isolated source copy. Both that build and the generated consumer select
the SDK's exact `lean-toolchain` through `elan run`; the consumer root also
contains the pin, so a relocated `/tmp` run cannot select the global default.
All generated sources and outputs stay under
`.golden-build/model-interface-conformance/` unless `--work` is supplied.

The receipt names the exact target set, fixture/generated/adapter hashes, and
tested scope. `--targets` permits focused development; a subset never claims
the full target set. `--reuse-generated` is explicitly marked in the receipt
and does not establish freshness. This gate executes no model checker and
does not establish transport or release qualification.
