# Read-only lock migration comparison

Date: 2026-10-07
Status: implemented; 23 migration controls and existing compiler/language gates
passed 2026-10-07. Full candidate qualification is separate.

`model_interface_gen compare-locks --from-lock OLD --to-lock NEW` helps an
application owner assess a freshly resolved interface against its previous lock.
Both inputs use the existing strict bounded lock reader and semantic, contract
and provenance digest validation. JSON output is a
`mirrors.model-interface-migration/v1` report; no files are written.

The result is `unchanged` when both authenticated projections match,
`provenance_only` when semantic identity matches but provenance changes, and
`semantic_change` when semantic identity differs. Raw whitespace and unbound
evidence-origin annotations are not semantic changes. A successful comparison
exits zero for all three kinds; invalid/missing inputs retain normal compiler
error exits. This is an inspection command, not a pass/fail compatibility gate.

The report contains both semantic/provenance identities, deterministic names of
changed canonical semantic sections, `requiresRegeneration`,
`requiresArtifactRefresh` and `semanticIdentityMatches`. Any semantic change
requires regenerating/reviewing the application binding and selecting the new
exact negotiation key. An additive action is not silently called compatible.
Provenance-only changes preserve semantic negotiation identity but require
refreshing artifact/provenance inventories and checking generated output.

Core classifies verified identities; Codec renders the report and compares
canonical JSON sections for explanatory detail; Shell loads bounded inputs;
the CLI strictly limits command-specific options. This changes no existing
lock encoding, generated v1 bytes, protocol or binding behavior. Comparison
validates lock contents; it does not re-open every referenced source/evidence
file, infer review approval, automatically rewrite code, or qualify a runtime.

Acceptance covers equal/provenance-only/semantic-change locks, action and
observation deltas, ordering and origin normalization, duplicate/unknown JSON,
tampered digests, missing input and foreign flags. Input bytes and directory
contents must remain unchanged, including on error. Existing compiler, CLI,
golden and qualification suites remain required.
