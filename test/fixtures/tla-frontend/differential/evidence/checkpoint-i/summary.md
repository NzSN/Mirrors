# TLA+ differential validation

Verdict: **fail**.

57 fixtures; 75 branches; 171/171 observations.
Semantic SHA-256: `e00451640aba6ca3c93fb836c2574cc7567dedee413151853536ddf41d156815`.

| Comparison status | Count |
| --- | ---: |
| fail | 13 |
| match | 510 |
| not_applicable | 10 |
| reviewed_difference | 14 |
| unsupported | 269 |

## Findings

- `acc-actions` / sany / levels: fail — unreviewed disagreement
- `acc-precedence` / sany / outcome: fail — unreviewed disagreement
- `acc-precedence` / apalache / outcome: fail — unreviewed disagreement
- `rej-unicode-spelling` / sany / outcome: fail — unreviewed disagreement
- `rej-unicode-spelling` / apalache / outcome: fail — unreviewed disagreement
- `rej-instance-definition-only` / sany / resolution: fail — unreviewed disagreement
- `rej-instance-definition-only` / sany / levels: fail — unreviewed disagreement
- `rej-instance-variable-substituted` / sany / resolution: fail — unreviewed disagreement
- `rej-instance-variable-substituted` / sany / levels: fail — unreviewed disagreement
- `rej-instance-implicit-substitution` / sany / resolution: fail — unreviewed disagreement
- `rej-instance-implicit-substitution` / sany / levels: fail — unreviewed disagreement
- `rej-substitution-constant-by-state` / sany / resolution: fail — unreviewed disagreement
- `rej-substitution-constant-by-state` / sany / levels: fail — unreviewed disagreement

Raw evidence and exact comparisons: [report.json](report.json).
Unsupported surfaces are coverage gaps, not passed comparisons. This report does not certify complete TLA+ conformance.
