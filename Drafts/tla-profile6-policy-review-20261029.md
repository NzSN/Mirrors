# Profile-6 policy difference review

Date: 2026-10-29. Review basis: published Mirrors
`7e9a27d0db72ec36b49c6fc5764b2687b565edfd` plus the reviewed Windows
reference-harness overlay. Exact source inputs and executable fingerprints are
retained in the probe report. This document's hash binds the review; the base
commit is provenance, not a claim that it contains this new document.

The fresh required Windows probe completed 61 fixtures, 76 branches and all
183 observations with stable inputs. It has 564 equal comparisons, 292 unsupported
surfaces and fourteen unreviewed outcome differences. Every difference is
Mirrors `rejected`, standalone SANY `accepted`, Apalache `accepted`. No structural
fact, unavailable execution or incomplete observation is excepted.

I inspected each fixture, its current observation and its owning rule in
[language-profile section 9](../Docs/model-interface-compiler/tla-language-profile.md#9-intentional-differences-from-the-reference-baselines):

| Fixture | Review and disposition |
| --- | --- |
| `rej-comment-depth` | Exceeds the published depth-64 nested-comment limit. Both references accept the same source; retain the bounded input policy. |
| `rej-identifier-size` | Exceeds the published identifier-byte limit. Reference acceptance does not remove the compiler resource bound. |
| `rej-control-character` | Contains a control byte outside tab/LF/CR. The profile explicitly rejects these bytes even when references tolerate them. |
| `rej-pluscal` | Contains PlusCal in a comment. Reference comment acceptance does not translate or validate the algorithm; retain the explicit fail-closed profile boundary. |
| `rej-duplicate-declaration` | Duplicates a declaration. References continue with a warning; the profile requires an error and related declaration locations. |
| `rej-real-literal` | Uses a decimal real literal outside the declared integer domain. Reference acceptance does not admit real-valued Mirrors semantics. |
| `rej-extends-ambiguity` | Imports competing declarations. References continue with a warning; the profile refuses to guess the intended declaration. |

These are fourteen new, exact bindings (one per fixture/reference engine),
reviewed from the current probe. The archived profile-5 registry is not an input
to their generation and remains unchanged. The profile-6 `Bags`/catalog migration
and October 28 SANY artifact have their actual pinned identities; these entries
cannot waive a different fingerprint, fixture hash, fact, outcome or profile.
No language rule is changed by renewing these documented policy bindings.

The [probe](../test/fixtures/tla-frontend/differential/evidence/profile6-20261029-probe-portable/report.json)
remains a failed required run because it preceded this review. Final independent
campaigns must use the new registry and reviewed artifact, complete all required
observations, retain zero unresolved findings and have identical semantic bytes.
Any changed fixture, profile, compared value or tool fingerprint requires another
review. Unsupported comparison surfaces remain coverage gaps.
