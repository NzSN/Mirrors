# Profile-5 differential policy review

Reviewed 2026-10-01 against the retained required baseline run. Profile 5
changes standard import visibility and module content identities. It does not
change the seven strict/resource policies already specified in language-profile
section 9. All 183 observations completed on the selected JDK 25.0.4+7-LTS,
standalone SANY 2.2 / Tools 1.8.0, and Apalache 0.61.0 frontend-only parser.
No local model checking was performed.

The baseline produced fourteen outcome disagreements and no other failures.
Every pair exactly reproduces an existing policy: comment-depth and identifier
resource bounds; forbidden controls; staged PlusCal and real literals; strict
duplicate declarations and ambiguous imports. Each fixture's source hashes and
both reference tool fingerprints match the original reviewed scope exactly.
This review renews only those outcome facts under profile 5 and the newly
observed Mirrors executable fingerprint. It approves no execution failure,
missing fact, changed fixture, new grammar, or changed standard-import behavior.
The changed standard-module fixture matches all supported reference projections.

| Fixture | Reference | Mirrors | Reference outcome | Source scope |
| --- | --- | --- | --- | --- |
| `rej-comment-depth` | `sany` | rejected | accepted | unchanged exact source hash |
| `rej-comment-depth` | `apalache` | rejected | accepted | unchanged exact source hash |
| `rej-identifier-size` | `sany` | rejected | accepted | unchanged exact source hash |
| `rej-identifier-size` | `apalache` | rejected | accepted | unchanged exact source hash |
| `rej-control-character` | `sany` | rejected | accepted | unchanged exact source hash |
| `rej-control-character` | `apalache` | rejected | accepted | unchanged exact source hash |
| `rej-pluscal` | `sany` | rejected | accepted | unchanged exact source hash |
| `rej-pluscal` | `apalache` | rejected | accepted | unchanged exact source hash |
| `rej-duplicate-declaration` | `sany` | rejected | accepted | unchanged exact source hash |
| `rej-duplicate-declaration` | `apalache` | rejected | accepted | unchanged exact source hash |
| `rej-real-literal` | `sany` | rejected | accepted | unchanged exact source hash |
| `rej-real-literal` | `apalache` | rejected | accepted | unchanged exact source hash |
| `rej-extends-ambiguity` | `sany` | rejected | accepted | unchanged exact source hash |
| `rej-extends-ambiguity` | `apalache` | rejected | accepted | unchanged exact source hash |

Evidence: `test/fixtures/tla-frontend/differential/evidence/profile5-20261001-baseline/report.json`
with its raw stdout/stderr artifacts and captured inputs. A fresh final required
run must verify the renewed registry; this review alone is not that verdict.
Renew review for any profile, fixture, tool fingerprint, or compared-field change.
