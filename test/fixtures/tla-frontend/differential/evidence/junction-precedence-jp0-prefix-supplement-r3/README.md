# JP0 final prefix-layout supplement

This is the authoritative prefix supplement. It verifies the pinned tools and
uses the bounded DV2 adapters with separate source staging per engine. The two
accepted cases retain Apalache IR showing `OR(AND(A, B), C)` for an aligned
opposite marker after a two-item conjunction list and `AND(A, OR(B, C))` for
an opposite infix inside the second item.

The parenthesized outdented continuation and the prefix switch-back form
`/\ A`, `\/ B`, `/\ C` are rejected by all three tools; neither is evidence of
a Mirrors-only boundary regression. `matrix.json` has SHA-256
`3d6a79762b92dc376f68610c107362d3867d7ad508a60c7c889ed75f34376197`.
Earlier supplement attempts are retained under ignored
`.golden-build/tla-differential/jp0-superseded/`.

Raw inputs and native logs are retained in `raw-evidence.tar.gz`; its digest
and restoration command are in `artifact-index.json`. Restore from this
directory with `tar -xzf raw-evidence.tar.gz --strip-components=1`. Every packed
file was compared byte-for-byte with the loose evidence before removal.
