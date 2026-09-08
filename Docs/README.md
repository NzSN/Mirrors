# Mirrors documentation

Current source inventory reviewed on 2026-09-08 at Mirrors `fe93fe4`,
MirrorECMA `1d02dc0`, and MirrorGate `15608a0`. This index describes the
implemented interfaces and where to find their evidence; it does not certify
an installed Windows service, a hosted CI run, or a published package.

## Start here

| Task | Read |
| --- | --- |
| Test TypeScript application code | [MirrorECMA MBT user manual](mirrorecma-typescript-mbt-user-manual.md) |
| Build, install, or identify Mirrors | [Product versions and installation](versioning.md) |
| Understand component ownership | [Architecture overview](architecture-overview.md), [module details](architecture-details.md) |
| Use the CLI or wire protocol | [Interface reference](interface-reference.md) |
| Implement a client library | [Client implementation guide](client-implementation-guide.md) |
| Generate a typed application port | [Generation design](model-interface-generation-design.md), [compiler contract](model-interface-compiler-design.md) |
| Understand interface negotiation | [Runtime distribution](model-interface-runtime-distribution-design.md) |
| Compare generated language profiles | [Cross-language specification](generated-model-interface-spec.md) |
| Check coverage and run interop | [Client coverage](client-test-coverage.md), [interop commands](../tools/interop/INTEROP.md) |

## Current implementation

- `mirror --version` prints the declared Mirrors product version. Default
  stdio replay is synchronous. TCP `--serve` and mTLS `--server` use connection
  worker pools and process-shared async job stores on Linux and Windows.
  Both accept `--jobs N`; the default is 4 and zero is clamped to 1.
- `model_interface_gen` implements `resolve`, `generate`, `check`, and
  `preflight`. Implemented targets are `mirrorecma-v1`, experimental
  `mirrorecma-async-v1`, and `mirrorcpp-v1`.
- MirrorECMA has compiled and dynamic negotiated replay, async report runners,
  and an experimental `evaluateSandboxed` facade. MirrorGate owns the shared
  control process, policy, snapshots, worker transport, and Linux/Bubblewrap
  isolation. Native Node and C++ control SDKs can drive Node and Rust workers.
  The C++ model-facing integration is an acceptance integration, not a released
  generic MirrorCPP facade API. See the
  [shared acceptance ledger](https://github.com/NzSN/MirrorECMA/blob/main/docs/shared-orchestration-acceptance.md).
- Rust/Lean generated model-interface targets and negotiated static registries,
  the proposed common generated-binding recording vectors, and broader sandbox
  backend support remain separate follow-up work. Existing MirrorRust base-wire
  tests and Gate Rust-worker tests do not imply those features are implemented.

## Validation entry points

[`lakefile.lean`](../lakefile.lean) defines the current `lake test` inventory:
12 test executables (`fixtures_replay`, `diff_cross`, `model_interface_spec`,
`model_interface_distribution_spec`, `stdio_smoke`, `jobstore_spec`,
`apalache_cli_spec`, `explorer_spec`, `transport_spec`, `registry_spec`,
`counter_spec`, `async_spec`), three compiler freshness checks (sync TypeScript,
async TypeScript, and C++), and Counter preflight with exact coverage comparison.
The script rebuilds first. `stdio_smoke` also checks the version CLI.

Set `APALACHE_MC` to an absolute executable path for explicit live coverage.
The Lake script also probes a developer-local Apalache path when the variable
is absent; therefore an unset variable alone does not guarantee an offline
run. Individual external tiers may skip when prerequisites are missing; inspect
their output separately from the aggregate exit status.

`bash tools/interop/run.sh` covers MirrorECMA, MirrorCPP, MirrorRust, and the
Haskell reference client. MirrorGate's required-backend gate and the shared
sandbox matrix are separate; the base interop script is not a sandbox
certification. Follow the linked companion ledgers for exact prerequisites
and dated results. Existing counts in historical reports describe their
recorded runs, not today's test inventory.

## Design history and dated evidence

The [Lean port design](lean4-refactor-design.md),
[initial final review](final-review.md), [TLS review](tls-ffi-review.md), and
[Windows teardown investigation](lean-windows-teardown-analysis.md) preserve
the original rationale, findings, and measurements. The
[worker-pool design](worker-pool-design.md) supersedes the temporary Windows
synchronous fallback; its [implementation ledger](worker-pool-impl-status.md)
records the August 2026 validation and deployments.

Use [async server behavior](async-enablement-design.md) and the
[cutover status](cutover.md) for the resulting behavior. Historical acceptance
counts, remote paths, and deployed binary identities must be reverified before
being used as evidence about a current deployment. The
[semantic notation guide](semantic-notation.md) defines the notation used in
the design documents; it is not an additional runtime protocol.
