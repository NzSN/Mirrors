# Activation and rollback transaction contract

This contract is normative for I3. It assumes a same-filesystem staging and
activation root on the selected ext4 profile. Cross-filesystem activation is
rejected before staging; network filesystems and case-insensitive filesystems are
outside version 1.

## Trust and ownership

The operator supplies an explicit cache root and disposable installation prefix.
The installer opens every path relative to pinned directory handles, refuses
symlinks and unknown existing layouts, and creates owner-only staging and state
directories. It never reads credentials, a home-directory default, sibling
source checkouts or `PATH`. Verification runs no distributed executable or SUT.
Verification may execute only the operator-supplied C3 verifier whose expected
SHA-256 is provided independently of the incoming cache. The installer first
copies its stably opened bytes into an owner-only temporary directory, verifies
the expected digest, and bounds execution time and output. It never selects or
executes the verifier, SUT, server, compiler, client or runtime from the incoming
cache during admission.

The active installation is a single version directory selected by a regular
`active.json` file managed inside the prefix. It contains only the selected
manifest digest and relative version-directory name. A verified temporary
regular file is atomically renamed over `active.json`; symbolic links and
filesystem junctions are forbidden. The transaction journal and manifest name
the previous and staged version by content digest. A previous complete version
is retained until a later explicit pruning operation, which is outside I3.

## States and durable transitions

```text
idle
  -> staging
  -> staged
  -> verified
  -> activating
  -> committed

activating -> rollback-required -> rolled-back
staging|staged|verified -> abandoned-stage
```

Each transition writes and fsyncs a closed journal record before the next
mutation. Artifact bytes are copied into a newly created stage, checked against
the cache index, and fsynced before `verified`. `activating` records both the
previous active digest and staged digest. Activation uses one same-directory
atomic rename of the regular selector. The resulting selection and its parent
directory are fsynced while the journal deliberately remains `activating`.
The materialized version is reverified before the journal becomes `committed`;
there is no durable `active` journal state.

Startup recovery never guesses. An incomplete stage that was never activated is
quarantined as `abandoned-stage`. `activating` with the old selection still
selected verifies the old version and records `rolled-back`. If the new
selection is selected, recovery verifies it and commits; a failed verification
restores the recorded previous selection and records `rolled-back`. Any unknown
selection, missing previous version, ambiguous journal, symlink, changed cache or
cross-device path stops with no deletion.

Activation is idempotent when the requested manifest digest is already active
and fully verified. A hash mismatch, missing dependency, unavailable profile,
write/fsync failure or interruption preserves the previous usable installation.
Rollback changes only the active selection; it does not rewrite artifacts.

## Evidence boundary

The installer emits commands, artifact hashes, transition observations and the
separate behavioral/cleanup/persistence outcomes through E1. A committed
transaction proves only that the checked bytes were activated under the recorded
filesystem assumptions. It does not prove package publication, kernel isolation,
backend availability or application correctness.
