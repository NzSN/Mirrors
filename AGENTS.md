# Repository Guidelines

## Project Structure & Architecture

Mirrors is a Lean 4 conformance checker. Keep pure, proved behavior in `Core/` (protocol, traces, diffs, jobs, resources) and wire encoding in `Codec/`. Put process, transport, registry, and CLI effects in `Shell/`; these modules are outside the proof boundary. `Ffi/` contains the small trusted C and Lean native boundary. TLA+ models live in `specs/`, checked-in wire fixtures in `test/fixtures/`, executable test harnesses in `tools/`, and design/interface documentation in `Docs/`. Start with `Docs/architecture-overview.md` before changing a boundary.

## Build, Test, and Development Commands

- `lake build` builds all default Lean libraries, test executables, C shims, and `.lake/build/bin/mirror`.
- `lake test` rebuilds, then runs the ten fixture, differential, transport, registry, Apalache, and end-to-end gates.
- `APALACHE_MC=/path/to/apalache-mc lake test` enables live model-checker tiers; those tiers self-skip when unset.
- `.lake/build/bin/transport_spec` runs a focused built test executable after `lake build`.
- `bash tools/interop/run.sh` runs the cross-language client matrix; read `tools/interop/INTEROP.md` for required sibling checkouts.

After C-only changes, remove the affected shim object and executable before rebuilding because Lake may not relink them automatically.

## Coding Style & Naming Conventions

Follow nearby Lean code: two-space indentation, explicit namespaces, `UpperCamelCase` types and namespaces, `lowerCamelCase` definitions and constructors, and `PascalCase.lean` module files matching imports. Use `/-- ... -/` for public declarations and `/-! ... -/` for module or section rationale. Keep `Ffi/` small and auditable. There is no repository-wide formatter; avoid unrelated reformatting.

## Testing Guidelines

Name Lean suites `tools/*Spec.lean`; keep deterministic protocol data under `test/fixtures/` and TLA+ test models under `test/specs/`. Add proof or fixture coverage for `Core/` and `Codec/` changes, and positive plus failure-path runtime coverage for `Shell/` or `Ffi/`. Run `lake test` before submitting. Preserve exact JSONL bytes and ordered diff hints where fixtures assert compatibility.

## Commits & Pull Requests

History favors concise, imperative, scoped subjects such as `Docs: ...`, `test: ...`, and `t33: ...`. Keep each commit focused. Pull requests should explain the behavior and trust-boundary impact, link the issue or task, list commands run (including skipped external tiers), and note protocol or fixture changes. Include terminal output for CLI behavior; screenshots are only useful for documentation UI changes.

## Security & Configuration

Never commit credentials, private keys, generated PKI, or `.golden-build/` artifacts. TLS private keys used locally must have mode `0600`. Treat OpenSSL, socket, and process-lifecycle changes as security-sensitive and include negative tests.
