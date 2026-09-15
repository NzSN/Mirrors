# DC4 phase-1 default-limit audit checkpoint

This portable archive is the fresh required profile-3 baseline proposed for
independent review; it is not an accepted differential checkpoint.  It was run
with the pinned JDK 25.0.4+7 and the standard required command:

```sh
PATH=.golden-build/tla-differential/jdk/jdk-25.0.4+7/bin:$PATH \
  python3 tools/tla-differential/run.py --required \
  --output .golden-build/tla-differential/profile3-phase1-audit-default60
```

The capture completed 183/183 observations.  Its normalized semantic payload
is `bd4f96eb4a994003d6072901e76fd00798628e915e875593c9e2fbeee46afea7`.
All 28 failures are the 14 seven-policy disagreements and the 14 invalid
pre-installed registry bindings; no failure concerns Unicode, `ENABLED`, or a
qualified named-instance fact.  The active registry had already been modified
by an out-of-scope actor, but its stale Mirrors fingerprint caused every
binding to fail validation, so the runner did not accept or hide a disagreement.

See [the phase-1 renewal proposal](../../../../../../Drafts/tla-junction-profile3-policy-renewals-phase1.md).
Do not update `differences.json` or the task ledger from this checkpoint until
an independent reviewer has approved the proposal.
