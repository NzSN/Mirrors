# TLA+ differential validation

Verdict: **fail**.

57 fixtures; 75 branches; 171/171 observations.
Semantic SHA-256: `414d703d05e1bf6559cca406cea70442e7cb19b209c1e05b69f5be5d0f951ce5`.

| Comparison status | Count |
| --- | ---: |
| fail | 27 |
| match | 510 |
| not_applicable | 10 |
| unsupported | 269 |

## Findings

- `acc-actions` / sany / levels: fail — unreviewed disagreement
- `acc-precedence` / sany / outcome: fail — unreviewed disagreement
- `acc-precedence` / apalache / outcome: fail — unreviewed disagreement
- `rej-comment-depth` / sany / outcome: fail — unreviewed disagreement
- `rej-comment-depth` / apalache / outcome: fail — unreviewed disagreement
- `rej-identifier-size` / sany / outcome: fail — unreviewed disagreement
- `rej-identifier-size` / apalache / outcome: fail — unreviewed disagreement
- `rej-control-character` / sany / outcome: fail — unreviewed disagreement
- `rej-control-character` / apalache / outcome: fail — unreviewed disagreement
- `rej-pluscal` / sany / outcome: fail — unreviewed disagreement
- `rej-pluscal` / apalache / outcome: fail — unreviewed disagreement
- `rej-duplicate-declaration` / sany / outcome: fail — unreviewed disagreement
- `rej-duplicate-declaration` / apalache / outcome: fail — unreviewed disagreement
- `rej-unicode-spelling` / sany / outcome: fail — unreviewed disagreement
- `rej-unicode-spelling` / apalache / outcome: fail — unreviewed disagreement
- `rej-real-literal` / sany / outcome: fail — unreviewed disagreement
- `rej-real-literal` / apalache / outcome: fail — unreviewed disagreement
- `rej-extends-ambiguity` / sany / outcome: fail — unreviewed disagreement
- `rej-extends-ambiguity` / apalache / outcome: fail — unreviewed disagreement
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
