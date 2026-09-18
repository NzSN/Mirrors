# Related-repository documentation audit — 2026-09-18

This is a documentation-only source audit. The [framework map](framework-map.md)
is the shared entry point; application authors should continue through the
[application integration guide](application-integration-guide.md). Gate's
[evaluator/worker selection guide](../../MirrorGate/docs/client-language-support.md)
explains its independent language roles.

| Repository | Inspected base revision | Documentation result |
| --- | --- | --- |
| Mirrors | `c9bcf18` | Nine-repository map, language reading paths, current Rust runtime-versus-emitter status and complete interop inventory |
| MirrorECMA | `d31b1d3` | Shared map navigation and later native Rust acceptance reference without rewriting the historical TypeScript/C++ ledger |
| MirrorGate | `d256e6c` | Evaluator/worker capability guide, native SDK map and scope of Node remote-model examples versus the Rust stdio facade |
| MirrorCPP | `c2549d6` | Corrected stale proposal status, full-result query API, poisoned-connection cleanup and Gate reuse links |
| MirrorLean | `198a063` | Current typed async entry point, historical design labeling and strict bounded framing description |
| MirrorRust | `328e4e6` | Framework/SDK integration entry points and explicit fixture-versus-generated-target boundary |
| MirrorExamples | `c6dfbbe` | Added the previously missing README with inspected models/tests, legacy harness assumptions and current onboarding references |
| MirrorRegistry | `82843a4` | Repaired design link, discovery ownership, and trust-model wording consistent with registry-selected endpoints/pins |
| ModelMirros | `3496251` | Distinguished the Haskell implementation and explicit-dependency CLI from the newer Lean executable |

The audit scans tracked Markdown plus the new documents, excluding unrelated
untracked `.work`, `traces` and `drafts` directories. It checks local file and
heading references, including GitHub main/master links that map to these local
checkouts. External websites and non-current revision URLs were not checked over
the network. Runtime assertions were checked against relevant source/CLI symbols;
this is not a fresh build, live-service inspection, or rerun of dated acceptance.

Validation: **238 Markdown files and 1207 local/cross-repository links**, no
missing local files or heading targets, and `git diff --check` passed in every
changed repository. All changes are Markdown. Historical run counts, deployment
records and evidence hashes retain their original provenance.


## Follow-up completeness pass

The second pass added MirrorRust and MirrorLean to the normative reference-client
inventory, corrected the interop command's mandatory prerequisites and checkout
list, scoped the framework walkthrough to its Node application path, and updated
Gate's architectural dependency description for native evaluator integrations.
The Rust integration README now includes locked-dependency preparation, actual
acceptance commands and its generic-library/Counter-fixture boundary.

The MirrorLean explorer example now unwraps its `Except` results, closes its
session on failures and preserves a primary error during cleanup. The exact
replacement was type-checked with `lake env lean` against the current library;
no model server was started by that check. Runtime acceptance suites were not
rerun for this Markdown-only update.
