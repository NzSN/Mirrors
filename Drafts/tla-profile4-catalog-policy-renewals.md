# Profile-4 standard-catalog policy renewals

> Status: **reviewed renewal record for fourteen existing outcome-only
> differences**.

Profile 4 adds only unary constant-level declaration facts for
`Sequences.Head` and `Sequences.Tail`, extends the accepted
`acc-standard-modules` source, and advances the profile/corpus identity. It does
not change any of the seven policy fixtures below, their source bytes, their
expected Mirrors outcomes, or the pinned SANY/Apalache behavior previously
independently reviewed under profile 3.

The fresh required baseline is
[`checkpoint-s-profile4-catalog-baseline`](../test/fixtures/tla-frontend/differential/evidence/checkpoint-s-profile4-catalog-baseline/).
It completed 183/183 observations with no unavailable, timeout, crash, or
incomplete row. Its only findings are fourteen stale profile-3 registry entries
and the corresponding fourteen outcome differences:

| Fixture | Narrow policy | References |
| --- | --- | --- |
| `rej-comment-depth` | bounded comment depth | SANY, Apalache |
| `rej-identifier-size` | bounded identifier size | SANY, Apalache |
| `rej-control-character` | control-character rejection | SANY, Apalache |
| `rej-pluscal` | PlusCal outside the frontend profile | SANY, Apalache |
| `rej-duplicate-declaration` | duplicate declarations are errors | SANY, Apalache |
| `rej-real-literal` | integer-only numeric domain | SANY, Apalache |
| `rej-extends-ambiguity` | ambiguous inherited declarations are errors | SANY, Apalache |

Each renewed entry is bound to:

- profile `mirrors-tla-frontend-profile-4`;
- the unchanged exact source digest set already present in the registry;
- Mirrors fingerprint
  `39f72594f27e0ab07806973431326c1b97a24ccb5d33d3bdadbf1cb8b3538f46`;
- SANY fingerprint
  `db131ddb48e7004d823bef4493df7b35694babe37505b9d9fa5685e7a331f1f1`
  or Apalache fingerprint
  `33611081942d392646af60993c599907f1f41752fce4a62304dbf9e2cdad4346`;
- the single `outcome` fact; and
- baseline report SHA-256
  `0e466d93869ec948b7b6c1d8253d4245e86a1a13c14d59648d1b0acbba4e480a`.

No renewal covers standard-module structural facts, `Head`, `Tail`, Unicode,
`ENABLED`, named instances, trace-result delivery, or an unsupported comparison
surface. Any change to a policy source, compared fact, profile, or tool
fingerprint requires another renewal. Final acceptance requires two fresh
required runs after installing these exact bindings.
