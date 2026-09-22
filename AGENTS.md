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
- Model-interface compilation or emission: `Docs/model-interface-compiler/design.md`;
  general TLA+ frontend work: `Docs/model-interface-compiler/tla-frontend-design.md`.
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

## Stopped framework-completion checkpoint (2026-09-22)

Work is intentionally stopped at the user's request. Resume from
`Plans/execution-decisions.md` and `Docs/qualification-harness-design.md`; do
not restart the framework work from its historical queued task-card labels.

- Mirrors, MirrorECMA, and MirrorGate contain the coordinated uncommitted
  implementation. No background worker or qualification command remains live.
- The byte-stable v5 catalog selection is
  `e3b691a60a87708b50c24085303fd313359cef33c50b11f7cc89fbd2358c3b7d`.
  Its snapshot is `/tmp/mirrors-reference-final-snapshot-v5`. The local cache
  build passed with canonical manifest digest
  `6579da18768b3efa5f6e6a61e7d7aa190e25f81bb520b9823f2b7e1a2e7fa8c2`;
  cache-index and manifest file hashes are respectively
  `2d3590e70e61537d97536e3d67af0f563a045d0a32b3d95d297c6993d8cb857a`
  and `942c794d66ef236f279e9b7a10a066da120cd7886d1cf4d307e205093c956321`.
  Installation committed at `/tmp/mirrors-reference-final-local-install-v5`.
- The v5 selection records the pre-commit dirty working trees. The checkpoint
  commits requested after this stop create new clean repository revisions, so
  v5 remains diagnostic and cannot qualify those pushed revisions. Refresh the
  catalog and snapshot from the pushed SHAs before resuming qualification.
- Stop occurred before v5 installed-consumer qualification. The Gate cache was
  not built. Q1, Q2, and Q3 therefore remain incomplete. Earlier v3/v4 failed
  audits are diagnostic only; their findings were fixed in source and covered
  by the current 22-test distribution suite.
- Focused source validation at stop: Mirrors evidence 94/94 and distribution
  22/22; MirrorECMA TypeScript plus installed wrapper/project 19/19 and catalog
  regression 3/3; MirrorGate recovery 40 tests with 34 passes and six
  environment skips, plus installed campaign wrappers 7/7. Model checking was
  excluded from these local results.
- Run every model check through the Mirrors CLI against the deployed service at
  `192.168.150.219:8999`. Do not start local Apalache or TLC. The direct mTLS
  CLI smoke returned `VALID` for bound-3 HourClock. The service still runs
  Apalache 0.58.2 and Java 21.0.11, so that observation is smoke evidence, not
  the selected 0.61.0/25.0.4+7 qualification. Newer toolchains are staged on
  the server but inactive; the service was not restarted or reconfigured.
- The current WSL2 host has no writable delegated cgroup-v2 parent. Real
  aggregate enforcement remains required but unavailable, and WSL2 does not
  establish native Ubuntu host acceptance.

Resume in this order: refresh identities and the immutable snapshot from the
pushed SHAs, rebuild and verify the local cache, run installed-consumer
qualification, build and install the Gate cache from that same snapshot, freeze
the installed evidence commands, run Q1, verify Q2 offline, then update Q3.

## Build and validation

Run commands from the repository root. Use elan with `lean-toolchain`; Linux
builds need a C compiler, OpenSSL 3 development files, and `pkg-config`.

- `lake build` builds libraries, the mirror, and default test executables.
- `.lake/build/bin/mirror` runs synchronous stdio mode.
- `lake test` rebuilds before running the gates defined in `lakefile.lean`,
  including model-interface golden checks and preflight.
- On the memory-constrained coordinator described by the stopped checkpoint,
  run `bash tools/run-local-no-model-check.sh` for local gates and use the
  Mirrors CLI against `192.168.150.219:8999` for model verification.
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
