# Windows compiler and temporary-path repair evidence — 2026-10-26

## Scope and identity

This record binds an uncommitted repair on Mirrors
`81b1f769f84372410a4bee787549d4f484bbcf45`. Exact changed-file, diff, archive
and test-binary hashes are in `source-identity.json`.

The repair has three parts:

1. `Shell.Apalache.SpecSource` canonicalizes an existing temporary base with
   `IO.FS.realPath` before constructing owned session/spec directories. This
   makes the directory spelling used by the process and diagnostic sanitizer
   agree when `TMPDIR` has trailing or repeated separators.
2. `tools/ModelInterfaceSpec.lean` expects the compiler's actual portable `/`
   separator in stale-output summaries. Its concurrent-publication injector
   now starts before publication and polls until a bounded wall-clock deadline,
   rather than missing a short staging window and sleeping with Windows timer
   granularity. Production publication and rollback code is unchanged.
3. `tools/run-local-no-model-check.sh` retains an explicit trailing-`TMPDIR`
   invocation of the real trace-generation failure fixture.

The Windows source archive contained `git archive` of the base commit plus only
these three working-tree files. It was extracted into a new isolated staging
root. The running service and production binaries were not changed.
After the logs and scripts were copied into this directory and their inventory
verified, only that isolated staging root and its source archive were removed.
`windows-cleanup.json` records the post-cleanup absence observation and
preservation of the separate production release.

## Passed focused validation

| Check | Result | Retained output |
| --- | --- | --- |
| Local focused Lake build | Passed | `local-focused-build.log` |
| Local `model_interface_spec` | Passed repeatedly | `local-model-interface.log` |
| Local trace diagnostic fixture with `/tmp`, `/tmp/`, `/tmp//` | All passed | `local-trace-*.log` |
| Windows `model_interface_spec` | Passed, then passed three further consecutive runs | `windows-model-interface-fixes*.log` |
| Windows `apalache_cli_spec` with trailing `TEMP`/`TMP`/`TMPDIR` | Pure/unit scenarios passed; live integration explicitly skipped | `windows-apalache-cli-fixes.log` |

The original eight Windows failures are retained separately in
`../windows-service-upgrade-evidence-20261026/gate-model_interface_spec.log`.
They are not rewritten by this repair record.

## Aggregate result and environment limits

`bash tools/run-local-no-model-check.sh` built all 728 jobs and passed the
repaired suites, but the complete aggregate is **not green**:

- The sandboxed attempt stopped at `check-validate-closure.py` because socket
  creation was denied. See `local-no-model-sandbox.log`.
- An unsandboxed attempt using `/tmp` reached distribution tests but could not
  run their ext4-only installation checks because this coordinator mounts
  `/tmp` as tmpfs.
- With `TMPDIR` moved to the repository's ext4 filesystem, distribution and
  durable-evidence tests passed. The run then reached offline TLA differential
  acquisition: 63 tests ran with three failures/errors and six skips because
  `.golden-build` lacked the original pinned artifacts. See
  `local-no-model-ext4.log`.
- The pinned Apalache archive downloaded with its expected hash. The currently
  served SANY jar instead hashed to
  `d15655eeaff4b3f7b3d65c46b838bc0f35d131b2ef4b1e473689b62c98d4726f`,
  not locked `db131ddb48e7004d823bef4493df7b35694babe37505b9d9fa5685e7a331f1f1`;
  acquisition refused it and removed the temporary download. The pin was not
  changed and the mismatched jar was not accepted.
- Every remaining command after that failing aggregate step passed in a
  separately retained continuation, including both normal and trailing
  temporary-path trace fixtures. See `local-no-model-remainder.log`.

Native integer-map coverage remained skipped because `MIRRORCPP_PREFIX` was not
selected. Live Apalache/Counter/async tiers were not run; no local Apalache or
TLC model operation started. No full cross-client matrix, service reboot,
production upgrade, commit, push, tag or hosted release is claimed.

## Publication reconciliation

This is the exact pre-rebase implementation and validation record, not the
identity of the final delivered commit. While rebasing, upstream `658b9ef`
independently supplied physical temporary-root canonicalization and broader
suffix regressions. The final change retains that upstream implementation and
drops the duplicate local `SpecSource` and no-model-runner edits. The Windows
`ModelInterfaceSpec` stale-path/race repair remains applicable and is retained.
