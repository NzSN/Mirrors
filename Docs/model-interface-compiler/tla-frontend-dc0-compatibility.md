# DC0 differential compatibility contract

This note freezes the input boundary for DC1--DC3.  It is not a profile change,
does not modify the active corpus, and does not approve an exception.

## Evidence status

The authoritative starting evidence is the preserved, independently executed
profile-2 pair: [checkpoint J](../../test/fixtures/tla-frontend/differential/evidence/checkpoint-j/report.json)
and [checkpoint K](../../test/fixtures/tla-frontend/differential/evidence/checkpoint-k/report.json).
Both have semantic SHA-256
`5dd32f9003de7c09771dac69282be01a853fcf5dfd11c4302011b6bf3da3f354` and
the same eleven failures.  `tools/tla-differential/tests/test_dc0_contract.py`
checks that exact set and the SANY facts below without rewriting either report.

The qualified live rerun below now augments the preserved checkpoint evidence.
It used Temurin OpenJDK `25.0.4+7`, standalone TLA+ Tools 1.8.0 (jar SHA-256
`db131ddb48e7004d823bef4493df7b35694babe37505b9d9fa5685e7a331f1f1`), and
Apalache 0.61.0 (jar SHA-256
`33611081942d392646af60993c599907f1f41752fce4a62304dbf9e2cdad4346`).
It remains calibration evidence only: it does not change the profile, corpus,
or the eleven-finding differential verdict.

## Exact handoff contract

| Consumer | Frozen reference fact |
| --- | --- |
| DC1 | The live matrix calibrates `ENABLED`: a constant operand yields state, a state operand yields state, and an action operand yields state; both references reject the temporal operand probe.  SANY also reports `AcceptActions!Increment` at `action` and `AcceptActions!Enabled` at `state`.  `ENABLED` must therefore not unconditionally return `temporal`. |
| DC2 | SANY exposes `I!ChildOp`, arity 0, from `InstanceDefsChild` at constant level; `InstanceStateChild` at action; `ImplicitChild` at action; and `LevelChild` at state.  In all four fixtures `RootOp` retains the same substituted level. |
| DC3 | The live matrix is evidence for all 36 staged glyphs.  The scope decision remains the minimum three: the preserved fixture containing `∧`, `∈`, and `≤` is accepted by both SANY and Apalache while Mirrors rejects it at lex, so these must normalize to `/\`, `\in`, and `<=`, respectively.  No additional accepted glyph is approved for profile migration unless DC3 explicitly adopts it. |

The preserved checkpoint-probe sources and their deterministic UTF-8 SHA-256
calculation are in `tools/tla-differential/tests/dc0_contract.py`.  The live
matrix runner has now generated one isolated, syntactically appropriate source
for every entry in that closed `STAGED_UNICODE_SPELLINGS` enumeration and
recorded each result as accepted-by-both, accepted-by-one, or rejected-by-both.

| Input | SHA-256 |
| --- | --- |
| `unicode/∧` | `17285d4b1e84f798e14f16e1793a38809e16ef5b16a011cf1b2d35927aeaa8a2` |
| `unicode/∈` | `0a3befa0dfdad4359668771ae2923f5a4d6454f50cec4b533e0344c96a63d939` |
| `unicode/≤` | `723f5a2f1667dee77ace76598a7fd541fe1cb751a337c68f0144db2e57bd2f35` |
| `enabled/constant` | `24117074c76530ea3844a161c058ea1bd6c40029673ff5b65d2ec6179ba29bd4` |
| `enabled/state` | `9b1c2fc4173683c9a4e9f9b095334382747d80f9c3d0bb497792eca76811a377` |
| `enabled/action` | `1e23e8f44d6a377a698af5e50320edfc6d69f467822e39298c711b89be59401c` |
| `enabled/temporal` | `8d864a0f6848ed66c5431115a5c7ded59f4c8f1cba1b08e8db0bd59b1db5b36e` |

## Reproduced discrepancy ledger

The preserved J/K reports prove exactly:

- two Unicode outcome disagreements: `rej-unicode-spelling` against SANY and
  Apalache;
- one SANY level disagreement: `acc-actions` / `Enabled`; and
- eight SANY named-instance facts: resolution and level for `I!ChildOp` in the
  four named-instance fixtures.

That is `2 + 1 + (4 * 2) = 11`.  No adapter-derived fact, changed expectation,
or reviewed-difference entry is permitted to discharge any of them.

## Qualified live matrix (2026-09-14)

`tools/tla-differential/tests/run_dc0_live_matrix.py` generated isolated,
UTF-8 inputs for every one of the 36 currently staged glyphs, four `ENABLED`
boundaries, and four named-instance bundles.  Each row was passed separately
to the SANY bridge and Apalache's `SanyParser`; the script retains both native
stdout/stderr streams, every accepted Apalache IR, source digest, command exit
code, and SHA-256 artifact index.  Its semantic payload intentionally excludes
raw log paths because Apalache records a private output directory in its log.

Two full, separately indexed captures were retained at:

```text
.golden-build/tla-differential/dc0-live-matrix-d/
.golden-build/tla-differential/dc0-live-matrix-e/
```

Both contain 44 rows and 207 native artifacts.  Their semantic payloads are
byte-identical, SHA-256:

```text
5d4eaf5a6aa896bf9eb0ffc8bf2b56e5aba7bd3a2c5791a68ea8a5f1bc370848
```

The engines agreed for every row.  Of the Unicode spellings, both accepted
`∧ ∨ ¬ ⇒ ⇔ ≡ ∈ ∉ ⊆ ∪ ∩ ≠ ≤ ≥ ⟨ ⟩ ↦ ‥ □ ◇ ≜ ∘ × ÷`; both rejected
`⊂ ⊇ ⊃ → ← ≺ ≻ ∼ ≈ ∙ ⋆ ○`.  Thus this matrix confirms the DC3 minimum
aliases `∧`, `∈`, and `≤` with independently isolated sources; it does not
approve the other accepted spellings for profile migration.

For `ENABLED`, SANY reported `C` constant / `E` state, `S` state / `E` state,
and `A` action / `E` state.  Both engines rejected the temporal operand probe.
The named-instance roots were accepted by both engines; SANY projected
`I!ChildOp` at constant (direct), action (explicit and implicit variable
substitution), and state (constant-by-state substitution), with arity zero and
the child declaration origins frozen above.

Reproduce a complete indexed run without overwriting evidence:

```sh
for group in unicode enabled named-instance; do
  python3 tools/tla-differential/tests/run_dc0_live_matrix.py \
    --output .golden-build/tla-differential/dc0-live-matrix-new \
    --group "$group" --jobs 8
done
python3 tools/tla-differential/tests/run_dc0_live_matrix.py \
  --output .golden-build/tla-differential/dc0-live-matrix-new --assemble
```
