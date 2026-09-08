# Repository Guidelines

## Architecture and source map

Mirrors is a Lean 4 conformance checker connecting client state machines to
Apalache through JSONL. Keep domain logic and proofs in `Core/`, pure codecs in
`Codec/`, effects and orchestration in `Shell/`, and native socket/TLS operations
in `Ffi/`. The shell and C shims are outside the proof boundary.

`Main.lean` starts the CLI; `Shell/Mirror/Session.lean` drives
`Core/Protocol.lean`. TLA+ models live in `specs/`, executable regression suites
in `tools/`, and golden data in `test/fixtures/`.

Read the relevant contract before changing behavior:

- Architecture: `Docs/architecture-overview.md`.
- Protocol or client compatibility: `Docs/interface-reference.md` and
  `Docs/client-implementation-guide.md`.
- Model-interface compilation or emission: `Docs/model-interface-compiler-design.md`
  and `Docs/generated-model-interface-spec.md`.
- Negotiation, authorization, or caching:
  `Docs/model-interface-runtime-distribution-design.md`.
- Native boundary: `Ffi/README.md` and `Docs/tls-ffi-review.md`.
- Native rebuild dependencies: `Docs/native-build-design.md`; verify with
  `bash tools/check-native-rebuild.sh`.
- MirrorECMA reports, async adapters, or dynamic lifecycle:
  `../MirrorECMA/docs/replay-and-async.md`.

Distinguish proposed target profiles from implemented behavior; consult each
design document's implementation-status section and current code.

## Build and validation

Run commands from the repository root. Use elan with `lean-toolchain`; Linux
builds need a C compiler, OpenSSL 3 development files, and `pkg-config`.

- `lake build` builds libraries, the mirror, and default test executables.
- `.lake/build/bin/mirror` runs synchronous stdio mode.
- `lake test` rebuilds before running the gates defined in `lakefile.lean`,
  including model-interface golden checks and preflight.
- After building, run focused suites such as
  `.lake/build/bin/fixtures_replay` or `.lake/build/bin/model_interface_spec`.
- `APALACHE_MC=/path/to/apalache-mc lake test` enables live model-checking tiers.
  The driver also probes a local fallback installation. Report skipped tiers;
  Python, OpenSSL, and loopback access are needed for integration coverage.
- For cross-client changes, follow `tools/interop/INTEROP.md` before running
  `bash tools/interop/run.sh`; it requires external client checkouts and tools.

Rebuild normally after C or included-header edits; Lake tracks shim objects and
linked executables, compiler identity, and OpenSSL settings. Run the native
rebuild gate after changing that dependency graph.

CI tool/client pins live in `tools/ci/versions.env`. MirrorECMA
`scripts/ci/versions.env` owns its published compiler baseline; coordinated client
checks use an explicit full `MIRRORS_REF` SHA. Keep synchronous generated output
stable when changing the separate `mirrorecma-async-v1` target.

## Editing and testing conventions

Follow neighboring Lean code: two-space indentation, `UpperCamelCase` types,
`lowerCamelCase` functions, and descriptive theorem names. Preserve proved
invariants without introducing `sorry` or axioms. Keep FFI signatures and C
ownership behavior aligned.

Preserve exact wire bytes, optional-field semantics, ordered diff hints, and
ordinary record keys. Local async computer contracts and report schemas do not
change the wire protocol. Support codec fixes with focused regression and golden
corpus evidence.
Regenerate frozen Haskell fixtures with `tools/fixtures/run.sh` per
`test/fixtures/README.md`; do not hand-edit them. Regenerate model-interface
outputs through `model_interface_gen` and validate with its `check` command.

Extend the relevant `tools/*Spec.lean` suite for behavioral changes; wire new
gates into `lakefile.lean`. Keep build and scratch artifacts untracked.

## Change descriptions

Follow history's concise, scoped subjects, such as `tls: ...` or
`model-interface: ...`. Describe the behavior change, affected contracts,
validation results, and any skipped or blocked checks in pull requests.
