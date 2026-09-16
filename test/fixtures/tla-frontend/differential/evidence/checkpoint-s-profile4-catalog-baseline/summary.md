# TLA+ differential validation

Verdict: **fail**.

61 fixtures; 76 branches; 183/183 observations.
Semantic SHA-256: `e7f8fd7c2d7e8d7e08430764be0ee0a497235ef15748b48e53e1fed664896ad5`.

| Comparison status | Count |
| --- | ---: |
| fail | 28 |
| match | 564 |
| unsupported | 292 |

## Findings

- `registry` / registry / reviewed: fail — reviewed-profile3-comment-depth-limit-sany: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-profile3-comment-depth-limit-apalache: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-profile3-identifier-size-limit-sany: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-profile3-identifier-size-limit-apalache: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-profile3-control-character-policy-sany: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-profile3-control-character-policy-apalache: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-profile3-pluscal-profile-limit-sany: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-profile3-pluscal-profile-limit-apalache: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-profile3-duplicate-declaration-policy-sany: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-profile3-duplicate-declaration-policy-apalache: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-profile3-real-literal-profile-limit-sany: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-profile3-real-literal-profile-limit-apalache: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-profile3-extends-ambiguity-policy-sany: missing profile/rationale/evidence
- `registry` / registry / reviewed: fail — reviewed-profile3-extends-ambiguity-policy-apalache: missing profile/rationale/evidence
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
