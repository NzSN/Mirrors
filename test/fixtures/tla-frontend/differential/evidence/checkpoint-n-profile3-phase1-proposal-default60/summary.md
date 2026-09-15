# TLA+ differential validation

Verdict: **fail**.

61 fixtures; 76 branches; 183/183 observations.
Semantic SHA-256: `bd4f96eb4a994003d6072901e76fd00798628e915e875593c9e2fbeee46afea7`.

| Comparison status | Count |
| --- | ---: |
| fail | 28 |
| match | 564 |
| unsupported | 292 |

## Findings

- `registry` / registry / reviewed: fail — reviewed-profile3-comment-depth-limit-sany: difference pins differ from verified artifacts
- `registry` / registry / reviewed: fail — reviewed-profile3-comment-depth-limit-apalache: difference pins differ from verified artifacts
- `registry` / registry / reviewed: fail — reviewed-profile3-identifier-size-limit-sany: difference pins differ from verified artifacts
- `registry` / registry / reviewed: fail — reviewed-profile3-identifier-size-limit-apalache: difference pins differ from verified artifacts
- `registry` / registry / reviewed: fail — reviewed-profile3-control-character-policy-sany: difference pins differ from verified artifacts
- `registry` / registry / reviewed: fail — reviewed-profile3-control-character-policy-apalache: difference pins differ from verified artifacts
- `registry` / registry / reviewed: fail — reviewed-profile3-pluscal-profile-limit-sany: difference pins differ from verified artifacts
- `registry` / registry / reviewed: fail — reviewed-profile3-pluscal-profile-limit-apalache: difference pins differ from verified artifacts
- `registry` / registry / reviewed: fail — reviewed-profile3-duplicate-declaration-policy-sany: difference pins differ from verified artifacts
- `registry` / registry / reviewed: fail — reviewed-profile3-duplicate-declaration-policy-apalache: difference pins differ from verified artifacts
- `registry` / registry / reviewed: fail — reviewed-profile3-real-literal-profile-limit-sany: difference pins differ from verified artifacts
- `registry` / registry / reviewed: fail — reviewed-profile3-real-literal-profile-limit-apalache: difference pins differ from verified artifacts
- `registry` / registry / reviewed: fail — reviewed-profile3-extends-ambiguity-policy-sany: difference pins differ from verified artifacts
- `registry` / registry / reviewed: fail — reviewed-profile3-extends-ambiguity-policy-apalache: difference pins differ from verified artifacts
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
