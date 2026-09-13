# JP0 junction-precedence baseline calibration

Command: `python3 tools/tla-differential/tests/junction_calibration.py --output test/fixtures/tla-frontend/differential/evidence/junction-precedence-jp0-r5`.
The script first ran `acquire.verify_tools()`, then used the DV2 Mirrors, SANY,
and Apalache adapters, their strict classifiers, private JVM temporary roots,
`-XX:-UsePerfData`, and bounded 60-second process limits. Each engine received
a separate materialized source directory. Raw stdout/stderr, native artifacts,
and strict observations are under `fixtures/`; `matrix.json` is the concise
result and has SHA-256 `0379eceb57e3c3cd7c4e3dd708b01630748e7bb1f26df0b56a04a7d109c97217`.

All 48 observations completed with a classified outcome. The baseline Mirrors
binaries accept the three unparenthesized mixed chains, while SANY rejects them
and Apalache rejects them with exit 255. Homogeneous chains, all four explicit
parenthesized forms, and the supported symbolic/word homogeneous alias are
accepted by all tools. The word-alias mixture has the same disagreement. The
single prefix item, homogeneous prefix list, nested prefix list, same-column
opposite prefix continuation, and inline opposite prefix form are accepted by
all tools; these layout observations are evidence, not inferred policy.
Apalache's retained IR gives the grouping projections: `prefix-mixed-column` is
`OR(AND(A), B)`, `prefix-inline-opposite` is `AND(OR(A, B))`, and
`prefix-nested` is `AND(A, OR(B, C))`. The raw `parsed.json` artifacts are
under each case's Apalache native-artifact directory.

The profile-1 live consumers are `LanguageProfile.default` in
`Core/Tla/Lexer.lean`, `ParserProfile.default` in `Core/Tla/Parser.lean`, the
manifest, 33 frozen expected summaries, the differential difference registry,
and explicit assertions in `tools/TlaLexerSpec.lean` and `tools/TlaParserSpec.lean`.
`tools/TlaParserSpec.lean` and `tools/TlaElaborationSpec.lean` only decode and
compare frozen `mirrors.tla-frontend-summary/1` files; no reusable summary
exporter exists. `tools/TlaDifferentialDriver.lean` is the available real
frontend projection path for a future deterministic exporter.

The source tree changed while calibration was running. `matrix.json` records
the hashes of the unrebuild baseline CLI and driver plus the current parser
source hash, explicitly noting the mismatch. Do not treat this checkpoint as
evidence for a rebuilt parser revision.

Raw inputs and native logs are retained in `raw-evidence.tar.gz`; its digest
and restoration command are in `artifact-index.json`. Restore from this
directory with `tar -xzf raw-evidence.tar.gz --strip-components=1`. Every packed
file was compared byte-for-byte with the loose evidence before removal.
