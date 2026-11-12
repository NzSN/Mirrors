# Source-review follow-up — 2026-11-12

The user approved the practical follow-up recommendations after publication of
`37f2d70651a21e7905e80cecc4ce6016a1c315c2`. This record owns the new observations;
earlier release and qualification receipts retain their exact identities.

## Completed local work

- Removed only two Git-ignored Rust incremental compiler cache directories.
  [Storage inventory](storage.json) records 427,061,689 logical bytes and the
  before/after filesystem headroom. Dated evidence and unrelated files were
  preserved. Available ext4 capacity remains limited; this is not sufficient
  storage admission for a new package/qualification campaign.
- Ran the complete maintained `bash tools/run-local-no-model-check.sh` at
  source `37f2d70`. It exits zero with `ALL LOCAL NON-MODEL GATES GREEN`.
  [Receipt](local-gate.json), [summary](local-gate-summary.json), and
  [runner](run-local-gate.py) retain the command, log digest and scratch policy.
  The 744-job build and isolated DPM build-dependency regression pass. Only
  the two large-copy DPM steps use private RAM-backed scratch; installer
  filesystem tests keep ext4 scratch. Temporary scratch was removed afterward.
- Rechecked all Git-tracked `Plans/dpm*/**/capture.json` inventories with the
  fixed strict JSON identity comparison. [Audit](dpm-capture-audit.json) binds
  52 captures, 260 inventory files and 104 retained traces. All inventory hashes
  match. The 44 captures with inline replies account for 88 traces, all matching
  exactly. Eight historical native captures contain path-only replies for 16
  traces; inline comparison is unavailable there. No coercion-only match or
  strict mismatch was found among the 88 compared traces. These results do not
  establish anything about captures outside this declared set or execute a model.
- Acquired exact rc.11 MirrorGate companion `cd4914b2…` into a separate bare
  input store. [Identity](companion-input.json) binds its commit and tree. The
  sibling MirrorGate checkout remains at `4b379ac0…`; MirrorECMA is `9192171f…`.

[Source/environment observation](source-and-environment.json) records the exact
source payload and built executable hashes. Tracked source was unchanged through
the full gate. Subsequent maintained-status edits are documentation changes and
were not part of that tested commit.

## Validation scope

The coordinator is Ubuntu 24.04.3 WSL2, kernel
`6.18.58.1-microsoft-standard-WSL2`. This local result does not substitute that
host for the selected Ubuntu 26.04.1 WSL2 qualification environment.

The gate's explicit exclusions and skips remain visible in its summary:
optional native C++ integer-map/controlled preparation was not selected;
Windows-only DPM cases and platform/optional Python cases skip as reported;
live Apalache, TLC, remote-model and async resource integration are excluded.
No native dependency graph changed, so no new native rebuild gate was required.

The earlier focused validation passed 76 distribution, 44 collector and 90 DPM
tests, with five Windows-only skips. The new aggregate additionally runs the
complete 154-test evidence suite and remaining compiler/codec/transport suites.
Its passing marker is local source evidence, not installed D, M5, Q1/Q2,
new-package, release or production acceptance.

## Remaining execution gates

| Work | State and next concrete action |
| --- | --- |
| Storage | Cache cleanup is complete; admit enough persistent ext4 capacity before package/distribution construction. No dated artifact cleanup is selected. |
| Native Windows validation | The read-only SSH attempt to the recorded `win10@192.168.150.219` closes with exit 255. The old `~/.ssh/config` is absent here. Obtain the current admitted connection/configuration, reobserve host/runtime identities, then build the exact source and run native regressions. No transfer or remote mutation occurred. |
| Selected WSL2 qualification host | Locate and reobserve the selected Ubuntu 26.04.1 environment. The current 24.04 coordinator receives no substituted profile credit. |
| New candidate | Prepare a fresh version and immutable source/C0 binding, clean packages, both installed audits and affected M5/Q gates after environment/input admission. The released rc.11 tag is unchanged; no replacement tag, package or qualification was created. The acquired Gate object is an input, not acceptance. |
| Compatibility lifecycle | Keep existing behavior and goldens. Complete two actual shipped compatibility cycles, real-workload hashes/counts/divergence/incident records, consumer acknowledgements and tested fallback. Workload entry point and consumer owners are requested but not supplied. Calendar time and synthetic repetitions do not complete these gates. |
| Retirement | Remains a separate future decision after all lifecycle prerequisites; no removal is authorized or performed. |

The November 6 [rc.11 completion record](../completion-rc11-20261106/completion.json)
already records its approved publication, Windows deployment and reboot. Those
operations are not pending work for rc.11. Their observations are historical,
not fresh remote-health checks. Native-runner/M4 planning remains withdrawn from
this campaign under the [October 30 scope decision](../m4-native-host-and-platform-plan-2026-10-07.md).
