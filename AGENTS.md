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
- Model-interface compilation or emission: `Docs/model-interface-compiler/design.md`
  and `Docs/generated-model-interface-spec.md`; general TLA+ frontend work:
  `Docs/model-interface-compiler/tla-frontend-design.md`.
- DPM kits, timelines, or checkpoint scheduling: `Docs/dpm-usability-design.md`
  and `Docs/deterministic-scheduling.md`; remaining approved features:
  `Plans/dpm-usability-features-2026-10-07.md`.
- Negotiation, authorization, or caching:
  `Docs/model-interface-runtime-distribution-design.md`.
- Native boundary: `Ffi/README.md` and `Docs/tls-ffi-review.md`.
- Native rebuild dependencies: `Docs/native-build-design.md`; verify with
  `bash tools/check-native-rebuild.sh`.
- MirrorECMA reports, async adapters, or dynamic lifecycle:
  `../MirrorECMA/docs/replay-and-async.md`.

Distinguish proposed target profiles from implemented behavior; consult each
design document's implementation-status section and current code.

## Current framework checkpoint

Documentation reviewed 2026-10-09 against Mirrors `548ba71`. For status or
continuation work, read `Docs/current-status.md`, the newest `CHECKPOINTS.md`
entry, and `Plans/execution-decisions.md` before selecting work. September stop
instructions and original queued task cards are historical; their frozen
identities remain in dated readiness reports and the archived
`Plans/framework-checkpoint-reference-2026-09-22.md`.

The October 7 C0 `94271a54…` qualifies `m5-wsl-windows-remote/v1` at Mirrors
`f0894d2`, MirrorECMA `eef6f71`, and MirrorGate `455e196`; the exact record is
`Plans/q3-published-roadmap-2026-10-07.md`. Later source changes require a new
identity freeze and corresponding gates before qualification credit.

DPM-0–DPM-5 are accepted for declared C++/Node-worker/Rust-thread profiles.
F1 generated integration kits and F2 receipt timelines have source acceptance
only; approved F3 schedule reduction, F4 installed CLI, and F5 synchronization
wrappers remain unimplemented. Broader M4 aggregate enforcement and active-
process post-restart recovery stay separate; follow
`Plans/m4-native-host-and-platform-plan-2026-10-07.md` for their prerequisites.

Run live model operations through the Mirrors CLI against the selected owned
remote service. Reobserve endpoint, binary, runtime and certificate identities
before use; October 7 observed `172.20.208.1:8999`, Apalache 0.62.2 and Java
25.0.4+7-LTS. The recorded certificate validity ended 2026-10-08T02:47:53Z;
that old identity cannot establish a current connection. See
`Docs/remote-server-guide.md`. Do not start local Apalache or TLC here.

Untracked `.projectile-cache.eld` files stay on disk as unrelated editor caches.
Preserve dated evidence and checkpoint entries; record new results separately.

## Build and validation

Run commands from the repository root. Use elan with `lean-toolchain`; Linux
builds need a C compiler, OpenSSL 3 development files, and `pkg-config`.

- `lake build` builds libraries, the mirror, and default test executables.
- `.lake/build/bin/mirror` runs synchronous stdio mode.
- `lake test` rebuilds before running the gates defined in `lakefile.lean`,
  including model-interface golden checks and preflight.
- On this coordinator, run `bash tools/run-local-no-model-check.sh` for local
  gates and use the Mirrors CLI against the reobserved selected remote service
  for model verification.
- After building, run focused suites such as
  `.lake/build/bin/fixtures_replay` or `.lake/build/bin/model_interface_spec`.
- On a separately admitted live-check host, `APALACHE_MC=/path/to/apalache-mc
  lake test` enables live model-checking tiers. The driver also probes local
  fallbacks; merely unsetting `APALACHE_MC` is not an offline gate on this
  coordinator. Report skipped tiers; Python, OpenSSL, and loopback access are
  needed for integration coverage.
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
