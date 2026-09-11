# Model-interface compiler designs

This directory contains the design authority for Mirrors' model-interface
compiler and its proposed TLA+ source frontend.

| Document | Status | Scope |
| --- | --- | --- |
| [Compiler detailed design](design.md) | Implemented version-1 compiler with identified follow-up milestones | Contracts, evidence, resolution, targets, deterministic emission, CLI, diagnostics, and publication |
| [General TLA+ frontend design](tla-frontend-design.md) | Proposed; no frontend implementation is claimed | Lossless parsing, module resolution, semantic elaboration, effective declarations, conformance, and compiler integration |

The frontend is a compiler input module. It does not replace Mirrors' model
protocol, Apalache execution, MirrorECMA bindings, or MirrorGate isolation. The
existing compiler remains authoritative until the frontend design's migration
and acceptance gates pass.

Related documents remain at the parent documentation level:

- [model-interface generation](../model-interface-generation-design.md);
- [generated interface specification](../generated-model-interface-spec.md);
- [runtime distribution and negotiation](../model-interface-runtime-distribution-design.md); and
- [Mirror-Framework usage](../usage-of-mirror-framework.md).

Implementation planning for the proposed frontend is tracked in
[TLA+ frontend tasks](tla-frontend-tasks.md).
The currently blocked parser slice has a focused
[TF2 acceptance recovery plan](tf2-acceptance-tasks.md).
