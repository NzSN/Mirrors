# TLA+ differential validation

Verdict: **fail**.

60 fixtures; 75 branches; 180/180 observations.
Semantic SHA-256: `5dd32f9003de7c09771dac69282be01a853fcf5dfd11c4302011b6bf3da3f354`.

| Comparison status | Count |
| --- | ---: |
| fail | 11 |
| match | 540 |
| reviewed_difference | 14 |
| unsupported | 285 |

## Findings

- `acc-actions` / sany / levels: fail — unreviewed disagreement
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
