# Model-interface compiler designs

This directory contains the design authority for Mirrors' model-interface
compiler and its implemented TLA+ source frontend.

| Document | Status | Scope |
| --- | --- | --- |
| [Compiler detailed design](design.md) | Implemented version-1 compiler with identified follow-up milestones | Contracts, evidence, resolution, targets, deterministic emission, CLI, diagnostics, and publication |
| [General TLA+ frontend design](tla-frontend-design.md) | Design; delivery slices TF0–TF8 implemented and accepted 2026-09-12 | Lossless parsing, module resolution, semantic elaboration, effective declarations, conformance, and compiler integration |
| [TLA+ frontend inspection CLI](tla-frontend-cli.md) | Implemented; TF8 accepted 2026-09-12 | Development-only `tla_frontend` parse/resolve/inspect commands, closed JSON schema, and validation |

The compiler consumes the frontend directly. The operational model protocol,
generated target contracts, Apalache execution, MirrorECMA bindings, and
MirrorGate isolation remain separate surfaces.

Related documents remain at the parent documentation level:

- [model-interface generation](../model-interface-generation-design.md);
- [generated interface specification](../generated-model-interface-spec.md);
- [runtime distribution and negotiation](../model-interface-runtime-distribution-design.md); and
- [Mirror-Framework usage](../usage-of-mirror-framework.md).

Implementation planning and acceptance evidence are tracked in
[TLA+ frontend tasks](tla-frontend-tasks.md).
The parser slice's recovery plan is recorded in
[TF2 acceptance recovery tasks](tf2-acceptance-tasks.md).
