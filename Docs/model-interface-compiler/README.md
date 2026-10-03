# Model-interface compiler designs

This directory contains the design authority for Mirrors' model-interface
compiler and its implemented TLA+ source frontend.

| Document | Status | Scope |
| --- | --- | --- |
| [Compiler detailed design](design.md) | Implemented version-1 compiler with identified follow-up milestones | Contracts, evidence, resolution, targets, deterministic emission, CLI, diagnostics, and publication |
| [Rust target](rust-target.md) | Implemented with native/shared-vector gates and bounded source-hidden offline/mTLS acceptance | Rust types, ports, codecs, ownership, dependencies, generation and validation |
| [Lean target](lean-target.md) | Implemented with required compiled verification, native/shared-vector gates and bounded source-hidden offline/mTLS acceptance | Lean types, ports, codecs, lifecycle, additive registry and shared replay |
| [Trusted suite bundles](suite-bundles.md) | Implemented with focused compiler and executable native bridge gates | Async bundle publication, ownership hashes, immutable model handles and local native conversion |
| [Reviewed scaffolds and corpora](reviewed-corpora.md) | Implemented; public local/Gate integration accepted 2026-10-03 | Explicit review, immutable sealing, workflow provenance, corpus projection and verified replay loading |
| [General TLA+ frontend design](tla-frontend-design.md) | Delivery slices TF0–TF8 accepted 2026-09-12; active language profile 5 | Lossless parsing, module resolution, semantic elaboration, effective declarations, conformance, and compiler integration |
| [TLA+ language profile](tla-language-profile.md) | Active revision 5 | Accepted language subset, standard-module facts, limits, and compatibility policies |
| [WriteSentry compiler extensions](writesentry-extensions.md) | Implemented source extensions with separately recorded acceptance | Frontend profile 5, `mirrorcpp-v2`, replay parameters, and optional CMake consumers |
| [TLA+ frontend inspection CLI](tla-frontend-cli.md) | Implemented; TF8 accepted 2026-09-12 | Development-only `tla_frontend` parse/resolve/inspect commands, closed JSON schema, and validation |
| [TLA+ differential validation](tla-differential-validation-design.md) | Profile-5 retained acceptance recorded 2026-10-01; unsupported comparisons remain uncertified | Pinned reference tools, corpus comparison, reviewed differences, and reproducible evidence |
| [Mixed-junction precedence correction](tla-junction-precedence-design.md) | JP0–JP4 completed 2026-09-13; precedence finding closed | Shared junction precedence, profile revision, corpus migration, and differential acceptance |

The compiler consumes the frontend directly. The operational model protocol,
generated target contracts, Apalache execution, MirrorECMA bindings, and
MirrorGate isolation remain separate surfaces.

The [common conformance gate](../../tools/model-interface-conformance/check.py)
executes synchronous/async TypeScript, C++, Rust and Lean generated consumers.
The [interop guide](../../tools/interop/INTEROP.md) distinguishes their bounded
generated-Counter transport acceptance from the legacy all-transport matrix and
framework qualification. Reviewed scaffold sealing and corpus workflows passed
their declared source and public local/Gate integration gates; the
[M6 execution record](../../Plans/m6-reviewed-scaffolds-and-corpora.md) retains
the exact results and limits.

The active frontend profile and catalog changes are recorded in the
[profile-5 extension contract](writesentry-extensions.md#standard-imports-frontend-profile-5).
The [retained profile-5 final report](../../test/fixtures/tla-frontend/differential/evidence/profile5-20261001-final/summary.md)
records acceptance for its captured inputs and toolchain. Dated profile-4 and
earlier acceptance records remain historical evidence; they do not qualify
profile 5 or certify its unsupported comparisons.

Related documents remain at the parent documentation level:

- [model-interface generation](../model-interface-generation-design.md);
- [generated interface specification](../generated-model-interface-spec.md);
- [runtime distribution and negotiation](../model-interface-runtime-distribution-design.md); and
- [Mirror-Framework usage](../usage-of-mirror-framework.md).

Implementation planning and acceptance evidence are tracked in
[TLA+ frontend tasks](tla-frontend-tasks.md).
The parser slice's recovery plan is recorded in
[TF2 acceptance recovery tasks](tf2-acceptance-tasks.md).
