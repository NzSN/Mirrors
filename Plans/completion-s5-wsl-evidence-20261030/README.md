# S5 Ubuntu 26.04 WSL2 admission and profile-variant record — 2026-10-30

Executes the S5 admission phase requested by the
[WSL handoff](../completion-s5-wsl-executor-handoff-2026-10-30.md) under the
[completion plan](../completion-qualification-release-plan-2026-10-30.md) and
[design](../../Docs/completion-qualification-release-design.md).

**No commit, push, tag move, release, deployment, production change, restart,
reboot, or local model-checker start occurred.** `win10` was observed reachable;
no candidate build, full `lake test`, isolated oracle, or remote credential was
created.

## Result

| Task | State | Result |
| --- | --- | --- |
| S5.1 | **Passed** | Actual host is Ubuntu 26.04.1 LTS, kernel `6.18.54.1-microsoft-standard-WSL2`, x86_64, glibc 2.43, ext4. Scope is `ubuntu-26.04-wsl2-x86_64`, never Ubuntu 24.04 or native Linux. |
| S5.2 | **Blocked** | Provisional identities, toolchain, C0 catalogs, distribution locks, artifacts and model hashes are recorded. The additive profile change is a **new uncommitted candidate input**; the base catalog still carries the pre-candidate refs, and the variant is bound to the current dirty tree and must be refreshed again after commit. |
| S5.3 | **Blocked** | No exact-candidate owner-only installation can be materialized before a new S1/S2 delivery and C0/lock refresh. |
| S5.4 | **Blocked** | Both D installation/distribution audits require an exact-candidate installation. |
| S5.6-S5.11, S5.13-S5.20 | **Not started** | No producer campaigns, DPM renewal, inventory, Q1/Q2 or controls. |
| S5.12 | **Blocked** | `win10` is reachable, but the exact candidate changed; full native `lake test`, integer-map, compiler/model-interface, runtime and TLS tiers were not run. |
| S5.5 | **Blocked externally** | `win10` is reachable. Production PID 9920 remains at its original hash on listener 8999, service `Running`/`Automatic`, with no listener 19131 and no leftover test oracle. No fresh isolated oracle endpoint/certificate, server process/binary, Apalache/JAR, Java or fixture observation was created; no credential files are present here. |

Machine-readable details: `environment.json`, `freeze.json`, `profile-gap.json`,
`source-change.json`, `s5-ledger.json`.

## The profile gap is real

The checked base catalog declares only `ubuntu-24.04` distribution profiles:

- `mirrors.reference-node-checked/ubuntu-24.04-x86_64/v1`
- `mirrors.reference-node-gate/ubuntu-24.04-x86_64/v1`
- `mirrors.reference-fresh-trace/ubuntu-24.04-x86_64/v1`

The installer observes `ubuntu-26.04`, and the installed framework admission
requires the catalog combination platform to equal the observed platform
(`MirrorECMA/src/framework-catalog.ts:1771-1783`; the focused mismatch test is
`MirrorECMA/test/framework-catalog.test.ts:711-729`). Using the 24.04 profile
would therefore fail `platform_identity_mismatch`; relabeling the host would be
dishonest.

## Additive WSL2 variant (new candidate input)

The change adds a **separate** 26.04 WSL2 profile/catalog pair and keeps the
checked 24.04 files byte-unchanged:

- `catalog/framework-catalog-wsl2-26.04.json` — same components, capabilities,
  combination IDs and dependency contract, with 26.04 platforms, profile IDs
  containing `ubuntu-26.04-wsl2`, and an explicit `virtualization: WSL2`
  operator-host prerequisite.
- `distribution/reference-node-wsl2-26.04/` — the corresponding profiles,
  component/dependency locks and fixtures. Distribution profile IDs stay
  `checked-replay-local`, `checked-replay-gate` and `fresh-trace`; combination
  IDs stay `candidate.local-node-checked`, `candidate.node-gate` and
  `candidate.fresh-trace`. The command registry is unchanged.
- `tools/distribution/manifest_check.py` — `validate_locks` accepts an explicit
  catalog path.
- `tools/distribution/build.py` — `--locks-root` and `--catalog`, defaulting to
  the checked 24.04 pair.
- `tools/distribution/install.py` — `require_profile_host` refuses a catalog
  profile whose ID contains `wsl2` unless `/proc/sys/kernel/osrelease` is the
  observed `microsoft-standard-WSL2` family.
- `tools/distribution/refresh_identity.py` — variant refresh via
  `--catalog/--locks-root`, with `--skip-component-records` and
  `--skip-render`; the variant catalogs/locks are excluded from the Mirrors
  dirty-content hash because C0 freezes them separately.

### Verification performed here

- `python3 -m unittest discover -s tools/distribution -p 'test_*.py' -v` with an
  ext4 `TMPDIR`: **46 tests OK**, including three new WSL2 profile/admission
  tests and the additive-lock resolution test.
- `framework_catalog validate` on both catalogs:
  - base `ecd80f70…`
  - variant `5603d9d4…`
- `refresh_identity.py` variant smoke: `IDENTITY REFRESH GREEN`, followed by a
  successful `validate_locks` on the refreshed variant.
- `bash tools/run-local-no-model-check.sh` with loopback socket access:
  `ALL LOCAL NON-MODEL GATES GREEN`, including `FRAMEWORK CATALOG SPEC GREEN`.
- `python3 Plans/completion-s5-wsl-evidence-20261030/verify.py`: exits 0 and
  rejects six negative controls (24.04 relabel, S5.3 pass claim, tag move,
  variant relabel, removed WSL2 guard, tampered variant digest).

Logs: `logs/distribution-tests.log`, `logs/catalog-validation.log`,
`logs/refresh-variant-smoke.log`, `logs/local-no-model.log`,
`logs/environment-toolchain.log`, `logs/companions.log`,
`logs/artifacts-tag.log`, `logs/profile-gap.log`, `logs/verifier.log`.

## Why S5 stops here

The handoff requires an additive profile change to be recorded as a new candidate
input and S5 continuation to stop until a new S1/S2 delivery is approved. The
working tree is now dirty above `d737aa0`; the local annotated tag
`v0.2.0-rc.1` still points at `d737aa0` and must not be moved. Both catalogs and
the new locks also need a fresh component-identity refresh at the new commit
before they can be the exact C0.

Required next sequence:

1. Approve, commit and push the additive source change as a new S1/S2 candidate.
2. Create a new clean checkout/tag; rebuild Linux and Windows packages (S3).
3. Refresh the base and WSL2 catalogs/locks at the new commit, then build and
   install the WSL2 local/Gate caches with `--catalog`/`--locks-root` (S5.2/S5.3).
4. Complete both D audits, then the full 18-command/16-tier M5 inventory,
   including a freshly observed isolated Windows oracle and the 22-row matrix.
5. Run full native Windows `lake test` at the exact candidate.
6. Run linked Q1, independent Q2, all six negative controls and offline replay.

## Reproduce

```bash
cd tools/distribution
TMPDIR=/home/lsz/Codebase/Mirrors/.golden-build/tmp \
  python3 -m unittest discover -s . -p 'test_*.py' -v
cd ../..
.lake/build/bin/framework_catalog validate catalog/framework-catalog.json
.lake/build/bin/framework_catalog validate catalog/framework-catalog-wsl2-26.04.json
TMPDIR=/home/lsz/Codebase/Mirrors/.golden-build/tmp \
  bash tools/run-local-no-model-check.sh
python3 Plans/completion-s5-wsl-evidence-20261030/verify.py
```

## Claim boundary

Only S5.1 is accepted. No framework qualification, installed consumer
acceptance, D audit, remote model check, 22-row matrix, full Windows test, Q1/Q2,
release admission, publication, deployment, reboot, or production stability
acceptance is claimed. The new profile variant is a source-input enabler; it is not itself a
platform qualification.
