# Profile-3 policy-renewal proposal — DC4 phase 1

Status: **independently reviewed and approved for the fourteen exact bindings below.**

This proposal is bound to the fresh, portable default-limit checkpoint
[`checkpoint-n-profile3-phase1-proposal-default60`](../test/fixtures/tla-frontend/differential/evidence/checkpoint-n-profile3-phase1-proposal-default60/).
Its archived report SHA-256 is
`391225623e8a752dab9727df73beb7f30a46dd08176a32e93dbc5ef51298325c` and
its normalized semantic SHA-256 is
`bd4f96eb4a994003d6072901e76fd00798628e915e875593c9e2fbeee46afea7`.

The required run completed all 183 observations.  It reports exactly 28
findings: fourteen stale pre-installed profile-3 registry bindings whose
Mirrors fingerprint is wrong, plus the corresponding fourteen unreviewed
`outcome` disagreements.  There are no incomplete, unavailable, setup, or
execution-crash observations.  No Unicode, `ENABLED`, or qualified-instance
comparison is a finding.  The 292 unsupported comparisons remain explicitly
unsupported.

## Exact proposed renewal bindings

Every proposed entry has profile `mirrors-tla-frontend-profile-3`, fact
`outcome`, expected Mirrors outcome `rejected`, and observed reference outcome
`accepted`.  The exact runtime tool fingerprints are:

- Mirrors: `ca58e57aeeaf586e7e8d3d21447c28bf77a9da9da5d5bdd322c8f0c9a634c89b`
- SANY / TLA+ Tools 1.8.0: `db131ddb48e7004d823bef4493df7b35694babe37505b9d9fa5685e7a331f1f1`
- Apalache 0.61.0: `33611081942d392646af60993c599907f1f41752fce4a62304dbf9e2cdad4346`

| Fixture / source digest | Narrow policy | Proposed references |
| --- | --- | --- |
| `rej-comment-depth` — `rejected/RejectCommentDepth.tla` `df0c74196e3d8bedb0e5b0a862bda6769bfc5fa6ef9db3a6c8b0f2a410976054` | bounded comment depth | SANY, Apalache |
| `rej-identifier-size` — `rejected/RejectIdentifierSize.tla` `39402a07e57399611cef45842f41f99b3db62b37cee3c3780577039ce1f78da9` | bounded identifier size | SANY, Apalache |
| `rej-control-character` — `rejected/RejectControlCharacter.tla` `9909854c5da713b6f700bcac297582a78e68b7d52d8f23848eeb25aad4ed0c7e` | control-character policy | SANY, Apalache |
| `rej-pluscal` — `rejected/RejectPlusCal.tla` `eb6a332c5d5b37e40eb4c962b97ba8bc2197f5613861a64a3d1707ba0d05840f` | PlusCal outside profile | SANY, Apalache |
| `rej-duplicate-declaration` — `rejected/RejectDuplicateDeclaration.tla` `6f59f6ec64025d8d9bca15b59985b17958e7f9c1bfe7ad3796f41017423ed977` | duplicate declarations | SANY, Apalache |
| `rej-real-literal` — `rejected/RejectRealLiteral.tla` `54cb23f1a9ea7d961d20ce15304b7c17fcc9291b1009044f5e2da95e46367e6b` | integer-only numeric domain | SANY, Apalache |
| `rej-extends-ambiguity` — `AmbLeft.tla` `7ba4f10d53c5338f6b2399bb4b65837a1c941fba74bdd71f7552d79394d9a20a`; `AmbRight.tla` `bde77d11adc90fc6317faffb32978c6703292c6e52d96d9f39c429c3e77d3c05`; `AmbRoot.tla` `21ac860813e2ddedf93064fa09e53751eceacd6e9b2bfc016c8c4182704a3c02` | ambiguous inherited declarations are an error | SANY, Apalache |

Thus the approved registry renewal has fourteen independently reviewed entries: one
for each fixture/policy pair and reference engine.  Each must bind exactly the
profile, source digest(s), Mirrors fingerprint above, one reference fingerprint
above, and the sole `outcome` fact.  It must not cover the eleven DC1--DC3
matches or any unsupported surface.

## Independent review record

An independent reviewer verified the archive and raw-artifact hashes, the 183
completed observations, the fourteen exact policy/reference pairs, their source
digests, and the `ca58e57a...` Mirrors fingerprint. The reviewer approved only
these fourteen `outcome` bindings. This review does not cover any Unicode,
`ENABLED`, qualified-instance, or unsupported comparison surface.

The installed registry must cite checkpoint N rather than checkpoint L. Any
source, profile, tool fingerprint, or fact change requires a new review.
