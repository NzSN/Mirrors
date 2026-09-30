# WriteSentry compiler extensions

Implementation decisions, 2026-10-01. These are source capabilities; publication,
fresh remote-oracle qualification, and installed-service support are separate.
The acceptance ledger is in
[the implementation plan](../../Plans/model-interface-compiler/writesentry-integration-improvements.md).

## Replay parameters

Configured names augment recorded `param_vars`. The effective list is recorded
names followed by configured additions, deduplicated in stable order. Both
metadata and state repartitioning use that same list; descriptor serialization
retains canonical ordering. Repeated application preserves the partition.
Constants and `action_taken` keep their separate treatment.

`mirrors-applyParamVars-filterMeta/v1` remains the comparison policy identity:
the descriptor already specified the combined effective parameter set. This
repairs the execution of that policy. There is no second meaning for `/v1`.
Old binaries that split only configured names do not implement this contract
for recorded additions. Regenerate/check locks against the repaired compiler;
do not use an old replay result to qualify the corrected runtime.

This intentional runtime difference from the pinned Haskell reference is
covered by the WriteSentry-shaped partition regression. Ordinary registration,
CLI replay, and negotiated preflight share `applyParamVars`; a target binding
still checks the configured name separately from the full effective set.

## Integer function maps and C++ profile 2

Root state names and record fields remain strings. Nonempty integer function
maps use `Value.vintmap`, distinct from string function maps, records, and root
`ValueMap`. Keys are arbitrary-precision integers. ITF uses homogeneous
`#bigint` keys inside `#map`; duplicate, mixed, malformed, boolean, and other
unsupported keys fail decoding. Existing string-map encodings remain stable.
The canonical empty `#map` decodes as an empty string-map value and receives its
key type from the resolved schema. Equality is independent of entry order;
integer `1` differs from string `"1"`. Integer-map diff hints report one atomic
map-level value mismatch, preserving the existing path and cap contracts.

`mirrorcpp-v1` retains its string-map baseline and rejects all `mapKey` paths.
The additive `mirrorcpp-v2` lowers string and integer maps as
`MirrorMap<T, K>` (default `K = std::string`, integer `K = mirrorcpp::Value::Int`).
String literals use length-delimited UTF-8 bytes, including embedded NUL.
Supported literal `mapKey` segments use the corresponding typed key, with
absence, wrong key sorts, and duplicates rejected before application callbacks.
Opaque values and other map key sorts remain unsupported. Runtime template
specialization checks that every replaced section occurs exactly once.
Selected children are copied before their owning boxed parent is replaced.

The tested native carrier is MirrorCPP
`d8ed4455e8f73a9144215f62f1dc6963d6d792e7` plus the retained v2 negotiation
patch, with C++23, Boost.Multiprecision,
nlohmann JSON 3.11.3, and OpenSSL 3. The prepared package is consumed through
`find_package(mirrorcpp CONFIG REQUIRED)`. The server must include the new map
codec and parameter-policy repair. Earlier installed/released servers do not
gain this capability through generator output. TypeScript and Rust version-1
emitters retain their own strict capability boundaries. Native ordinary and negotiated stdio fixture replay pass; selecting the wrong
registry profile invokes zero application factories/callbacks. The unmodified
pinned client accepts only v1 for negotiated replay. The patch permits exactly
v1/v2 and preserves the four-part registry key and existing v1 default. These
checks do not certify every transport or cross-client combination.

## Standard imports: frontend profile 5

The active language profile is `mirrors-tla-frontend-profile-5`, with catalog
`mirrors-standard-modules/v2`. Public edges re-export reviewed declarations:
`Integers -> Naturals`, `Reals -> Integers`, `RealTime -> Reals`, and
`Bags -> TLC`. Local `INSTANCE` edges stay private. Named instances retain
the original declaration module, arity, and level. Captured local sources take
precedence over catalog fallback and do not receive invented catalog facts.

The eleven language-module content hashes identify exact module bytes from the
standalone TLA+ Tools 1.8.0 jar pinned in the differential lock. Apalache
extension modules without reviewed source facts have no content identity.
The active 61-fixture corpus has profile-5 summaries; the standard-module
fixture now uses `Nat` through `Integers` without explicitly extending
`Naturals`. Syntax tables remain unchanged.

Profile-4 differential approvals are preserved in
`test/fixtures/tla-frontend/differential/archive/profile4-differences.json`.
The active registry carries no renewed approvals. A new required differential
run and review against the selected JDK/SANY/Apalache identities must qualify
profile 5. Historical profile-4 results cannot do so.

## Optional generated CMake consumers

`generate-cmake` and `check-cmake` take the existing `--spec`, `--contract`,
`--evidence`, `--param-var`, and `--lock` inputs plus a C++ `--target` and `--out`.
Paths are portable relative paths within the consumer root. Generation requires
a current lock; run `resolve` first. The same emitter and owned-file transaction
publish the binding and three optional artifacts:

- `MirrorInterface.cmake`: configure verification, a build verification target,
  an interface library, and optional explicit regeneration.
- `MirrorVerify.cmake`: offline verification, also callable immediately before
  replay with `cmake -DMIRRORS_INPUT_ROOT=... -DMIRRORS_GENERATED_ROOT=... -P ...`.
- `MirrorInterface.inputs.json`: `mirrors.model-interface-consumer/v1`, recording
  captured source closure, contract/evidence/lock and output hashes, semantic
  digest, target profile, compiler version and executable hash, and regeneration
  argument arrays. The manifest excludes its own recursive output hash.

Consumers include the helper and call
`mirrors_add_model_interface(binding "${source_root}" [COMPILER "${compiler}"])`.
Link the generated interface library and `mirrorcpp::mirrorcpp` into the native
target. Verification runs at configure and every dependent build; a replay
runner must also call the verifier immediately before replay. Supplying
`COMPILER` adds `binding_regenerate`; replay-only consumers need no compiler or
model checker. Regeneration explicitly replaces owned bytes, preserves unrelated
files, and refuses unsafe replacement. A failed input compile or owned-output
publication leaves generated outputs intact. `resolve` is a separate lock write;
there is no claimed atomic transaction spanning lock resolution and publication.

Offline checks establish byte freshness and digest agreement with the recorded
manifest, not authenticity. `check-cmake` additionally recomputes semantic compiler
outputs and compiler identity. Corpus/oracle provenance remains a separate
manifest; it is not renewed by generating these helpers.

## Diagnostics

Target errors accumulate independent findings with model/action/input/observation
IDs, typed-lock JSON pointers, nested type paths, and target context. These are
lock locations, not invented TLA+ source positions. Existing diagnostic codes,
structured JSON schema, and finding exit code remain stable. Human diagnostic
data containing quotes, backslashes, or line controls is JSON-quoted; ordinary ASCII
identifier rendering remains stable. A rejected invalid-ID case verifies that
JSON and human outputs preserve escaped data without splitting lines. Unsupported map
key guidance is relative to the selected target profile.

## Executable gates

`python3 tools/check-cmake-consumer.py` exercises offline/configure/build checks,
captured dependencies, mutations, paths with spaces, unsafe/duplicate paths,
regeneration failure, and unrelated-file preservation. It is wired into both
owning runners.

`python3 tools/check-cpp-integer-maps.py --prefix <prepared-MirrorCPP-prefix>`
generates a native v2 fixture and exercises large signed keys, both key sorts,
nested/empty maps, codec/copy behavior, original integer-map stdio replay, and
zero application callbacks after missing/duplicate/mistyped input failures.
This fixture uses manually specified recorded states for a boundary regression;
it is not a model-checked oracle. Set `MIRRORCPP_PREFIX` to include it in the
owning aggregate runners; an absent prefix is an explicit native-tier skip.
