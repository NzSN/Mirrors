# TLA+ differential validation

Verdict: **fail**.

60 fixtures; 75 branches; 180/180 observations.
Semantic SHA-256: `a3ab1281ab0f3fa65e878b425ae7143708c3c2e0de86f46798fbd0cdb404e608`.

| Comparison status | Count |
| --- | ---: |
| fail | 39 |
| match | 540 |
| unsupported | 285 |

## Findings

- `registry` / registry / reviewed: fail — reviewed-comment-depth-limit-sany: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-comment-depth-limit-apalache: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-identifier-size-limit-sany: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-identifier-size-limit-apalache: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-control-character-policy-sany: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-control-character-policy-apalache: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-pluscal-profile-limit-sany: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-pluscal-profile-limit-apalache: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-duplicate-declaration-policy-sany: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-duplicate-declaration-policy-apalache: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-real-literal-profile-limit-sany: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-real-literal-profile-limit-apalache: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-extends-ambiguity-policy-sany: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-extends-ambiguity-policy-apalache: missing profile/rationale/evidence
- `acc-actions` / sany / levels: fail — unreviewed disagreement
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
