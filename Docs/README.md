# Mirrors documentation

The [framework map](framework-map.md) covers the related repositories and
distinguishes model clients, generated bindings, Gate evaluators and workers.
The [2026-09-18 documentation audit](related-documentation-audit-20260918.md)
records the inspected revisions, updates and link-check scope.

Remote deployment and client operation: [remote server guide](remote-server-guide.md).
Latest recorded Windows rollout: [2026-09-18 deployment](windows-deployment-20260918.md).

Current application-integration inventory reviewed on 2026-09-17 at Mirrors
`bc6eb7c`, MirrorECMA `9942248`, and MirrorGate `1388526`. This index describes the
implemented interfaces and where to find their evidence; it does not certify
an installed Windows service, a hosted CI run, or a published package.

## Start here

| Task | Read |
| --- | --- |
| Integrate an application with suites and generated adapters | [Role-oriented integration guide](application-integration-guide.md) |
| Run MBT or LLM-assisted development with the Mirror Framework | [Mirror Framework usage guide](usage-of-mirror-framework.md) |
| Test TypeScript application code | [Current MirrorECMA MBT tutorial](mirrorecma-typescript-mbt-user-manual.md) |
| Evaluate framework usability on real applications | [Three-application validation program](application-validation-program.md) |
| Review integration contracts | [Application integration design](application-integration-design.md) |
| Plan integration implementation | [Application integration implementation plan](application-integration-implementation-plan.md) (historical baseline, completed work packages and acceptance criteria) |
| Inspect integration acceptance | [Execution record](application-integration-progress.md) (automated gates, actual restricted authors and fresh-agent onboarding) |
| Build, install, or identify Mirrors | [Product versions and installation](versioning.md) |
| Run validation inside WSL2 or through `r_windev` | [WSL2 validation](wsl2-validation.md) |
| Inspect a TLA+ model with the frontend CLI | [`tla_frontend` guide](model-interface-compiler/tla-frontend-cli.md) |
| Understand component ownership | [Architecture overview](architecture-overview.md), [module details](architecture-details.md) |
| Use the CLI or wire protocol | [Interface reference](interface-reference.md) |
| Implement a client library | [Client implementation guide](client-implementation-guide.md) |
| Generate a typed application port | [Generation design](model-interface-generation-design.md), [compiler designs](model-interface-compiler/README.md) |
| Understand interface negotiation | [Runtime distribution](model-interface-runtime-distribution-design.md) |
| Compare generated language profiles | [Cross-language specification](generated-model-interface-spec.md) |
| Verify async job ownership and resource cleanup | [Async resource model](async-protocol-resource-model.md), [Lean safety proofs](async-resource-lean-proofs.md) |
| Check coverage and run interop | [Client coverage](client-test-coverage.md), [interop commands](../tools/interop/INTEROP.md) |

## Current implementation

- `mirror --version` prints the declared Mirrors product version. Default
  stdio replay is synchronous. TCP `--serve` and mTLS `--server` use connection
  worker pools and process-shared async job stores on Linux and Windows.
  Both accept `--jobs N`; the default is 4 and zero is clamped to 1.
- `model_interface_gen` implements `resolve`, `generate`, `check`, `preflight`,
  additive async `bundle` / `check-bundle` publication,
  proposal-only `scaffold`, and strict `project-trace`. Scaffold accepts one
  raw evidence document per invocation; projection accepts one trace and emits one
  paired receipt. Neither command seals a proposal as a contract.
  Implemented targets are `mirrorecma-v1`, experimental
  `mirrorecma-async-v1`, and `mirrorcpp-v1`.
- MirrorECMA has compiled and dynamic negotiated replay plus async report
  runners, immutable suites, strict matched acceptance, project tools and
  normalized suite results. Gate supplies the optional suite workflow and public
  adapter kit. The former Gate-aware `evaluateSandboxed` facade is outside
  MirrorECMA 2 core and remains available through the Gate-owned
  `mirrorgate-mirrorecma/legacy` integration. MirrorGate owns the shared control
  process, policy, snapshots, worker transport, and Linux/Bubblewrap isolation.
  Native Node, C++ and Rust control SDKs can drive Node and Rust workers;
  the Rust SDK currently selects control-v1 only.
  The C++ model-facing integration is an acceptance integration, not a released
  generic MirrorCPP facade API. See the
  [shared acceptance ledger](https://github.com/NzSN/MirrorECMA/blob/main/docs/shared-orchestration-acceptance.md).
- MirrorRust now has an exact adapter registry and compiled-verify runtime for
  reviewed bindings. Gate owns the new native Rust SDK and evaluator integration;
  see its [implementation/acceptance record](../../MirrorGate/docs/rust-evaluator-sdk-status.md).
  Rust/Lean generated targets, the MirrorLean registry, common generated-binding
  recording vectors and broader sandbox backends remain separate follow-up work.
  The handwritten Rust Counter fixture does not establish a Rust compiler target.

## Validation entry points

[`lakefile.lean`](../lakefile.lean) defines the current `lake test` inventory:
23 test executables (`fixtures_replay`, `diff_cross`, `model_interface_spec`,
`model_interface_distribution_spec`, the five evidence/scaffold/projection
specs, the lexer/parser/resolver/elaboration/frontend/inspection-CLI frontend
gates, `stdio_smoke`, `jobstore_spec`, `apalache_cli_spec`, `explorer_spec`,
`transport_spec`, `registry_spec`, `counter_spec`, and `async_spec`), three
compiler freshness checks (sync TypeScript, async TypeScript, and C++), and
Counter preflight with exact coverage comparison. The driver also runs
`tools/check-async-emitter.py` and `tools/check-suite-bundle.py` for emitter
structure and suite-bundle publication/freshness regressions.
The script rebuilds first. `stdio_smoke` also checks the version CLI.

Set `APALACHE_MC` to an absolute executable path for explicit live coverage.
The Lake script also probes a developer-local Apalache path when the variable
is absent; therefore an unset variable alone does not guarantee an offline
run. Individual external tiers may skip when prerequisites are missing; inspect
their output separately from the aggregate exit status.

`bash tools/interop/run.sh` covers MirrorECMA, MirrorCPP, MirrorLean, MirrorRust, and the
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

- [Concurrent async server resource E2E](async-server-resource-e2e.md): live mTLS
  concurrency, cleanup assertions, and bounded RSS growth regression.
