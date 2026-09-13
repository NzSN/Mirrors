# Proposed profile-2 policy renewals

`proposed-profile2-policy-renewals.json` contains fourteen uninstalled entries:
the existing seven reviewed policy differences, once per reference engine. Each
is bound to profile `mirrors-tla-frontend-profile-2`, the baseline checkpoint
report `checkpoint-jp4-baseline/report.json` (SHA-256
`f82828a12bed42c482e8a5aee3bd37685990999f97ef60a62c906b4564e8e5fc`), current
Mirrors binary fingerprint
`443cb7901568a88a19a82f3f0c432f775c0267db197ce7a76efde3d9de048110`, and the
captured profile-2 source hashes. Their `review` metadata is deliberately
marked pending; this file and the proposals must be independently reviewed
before replacing the live profile-1 registry.

The baseline has 180 completed observations. It closes both precedence cases.
It does not propose entries for Unicode, ENABLED-level, or named-instance
projection disagreements.

## Independent approval

`junction_policy_review_final` independently approved all fourteen entries on
the exact fixture, field, source-digest, profile, and engine-pin scope. The
approved renewals cover only the historic seven profile policies, once for each
reference engine. The baseline was captured from dirty worktree state at commit
`e079588bd3ff8b81d1404f0d58c7abdde2a7d372`; `report.json` records the exact
captured source, summary, and binary hashes, so this commit field is an ancestry
label rather than a claim of a clean committed implementation. The ENABLED
disagreement remains unreviewed: Mirrors reports it as temporal while SANY
reports it as state.
