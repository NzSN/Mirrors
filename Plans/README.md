# Plans and execution records

Reviewed 2026-11-17 against the November 16 completion records and source
`58d24c5eabcde7d8dfeafbeb82f9064879427eea`. Start with
[current status](../Docs/current-status.md), the newest
[checkpoint](../CHECKPOINTS.md), and [execution decisions](execution-decisions.md).

## Current work

| Work | Contract and current evidence | Remaining boundary |
| --- | --- | --- |
| Compatibility lifecycle, S8 | [Lifecycle decision](compatibility-lifecycle-decision-2026-10-29.md), [cutover contract](../Docs/cutover.md), [stage definitions](completion-qualification-release-plan-2026-10-30.md), [progress](s8-dumpledger-workload-20261116/lifecycle-progress.json) | Two complete consecutive shipped cycles with every declared compatibility row and real-workload records; named consumer owners, trust updates, migration acknowledgements, soak/incident records and tested fallback. Accepted complete cycles: zero. Retirement requires its own later decision. |
| Qualification before another release | [rc.12 qualification](completion-rc12-20261116/result.json), [rc.12 operation completion](completion-rc12-20261116/completion.json) | rc.12 acceptance binds source `6882d5b8…` and its recorded C0. Later runtime fixes at `58d24c5…` have recorded local non-model validation only; a later candidate needs its own freeze and affected qualification gates before shipping. |
| Reproduction governance proposal | [Handling governance](handling-governance.md) | The proposed policy remains pending ratification; the cleanup does not implement or approve it. |
| Separate framework capabilities | [Framework roadmap](mirror-framework-improvements.md) | Broader M4/platform capabilities remain outside the completed profile. [Native-runner/M4 execution planning](m4-native-host-and-platform-plan-2026-10-07.md) remains withdrawn from this campaign. |

The [three-input DumpLedger replay](s8-dumpledger-workload-20261116/replay-summary.json)
is complete for its bounded engine-level profile. It supplies no full-cycle,
HTTP/auth/streaming, batch, historical or long-running-soak acceptance. Private
observations and operator inputs retain their existing private locations.

## Completed work

- [Completed plan archive](completed/README.md): accepted implementation and
  qualification plans, each limited to its recorded scope and identities.
- [rc.12 completion](completion-rc12-20261116/completion.json): publication,
  production trust renewal, deployment and post-reboot verification completed
  on November 16. This is a dated result, not a new remote health observation.
- [Bounded DumpLedger replay](s8-dumpledger-workload-20261116/README.md): the
  approved three-input replay and scoped aggregate publication are complete;
  the enclosing compatibility lifecycle remains open.

## Historical material

[Superseded plans](archived/README.md) retain older task queues and intermediate
failed or incomplete scope. Archiving them does not turn those outcomes into
passes. The current lifecycle obligations above replace their old work queues.

Dated evidence directories, readiness reports, machine-readable receipts,
inventories and exact operation handoffs remain at their recorded paths.
Some old plan paths contain a short link to the archive so those unchanged
records still resolve. Pre-existing untracked plans and evidence remain local
and untouched. The append-only checkpoint and decision history retains its
original entries and acceptance boundaries.
