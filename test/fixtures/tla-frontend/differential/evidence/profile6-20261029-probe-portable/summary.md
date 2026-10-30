# TLA+ differential validation

Verdict: **fail**.

61 fixtures; 76 branches; 183/183 observations.
Semantic SHA-256: `375736401fc7f045136ec5f287514fc6e6f75d133c23773a0401480d92f867f2`.

| Comparison status | Count |
| --- | ---: |
| fail | 14 |
| match | 564 |
| unsupported | 292 |

## Findings

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
- `rej-real-literal` / sany / outcome: fail — unreviewed disagreement
- `rej-real-literal` / apalache / outcome: fail — unreviewed disagreement
- `rej-extends-ambiguity` / sany / outcome: fail — unreviewed disagreement
- `rej-extends-ambiguity` / apalache / outcome: fail — unreviewed disagreement

Raw evidence and exact comparisons: [report.json](report.json).
Unsupported surfaces are coverage gaps, not passed comparisons. This report does not certify complete TLA+ conformance.
