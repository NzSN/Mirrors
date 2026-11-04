# Recovered-source rc.7 freeze — 2026-11-04

Status: **accepted for the bounded local rc.7 source/C0 freeze** after the
user-authorized full local non-model gate and independent verification.
This is not shared branch publication, package, installed D, M5/Q, Windows,
remote-model, framework, release or deployment acceptance.

## Source and candidate identities

| Item | Identity |
| --- | --- |
| Shared published base, unchanged | `d541d242d977308ddc1b7fe6c92b75eb0548b3ef` |
| Clean task-owned freeze commit | `f525c6349dc5a5e457757fa040c89312c6703e3a` |
| Product version | `0.2.0-rc.7` |
| Base structural-control C0 | `1d77a753123b10349ded102879e8bc29f54755d613f3c76e5e8bfb6b8e614ec2` |
| Selected Ubuntu 26.04 WSL2 C0 | `e673c65e1220d3d71f0ba200db77210267e342a7614d51a17168460afb02ff88` |
| MirrorECMA | `9192171fc5f8d8457f8d13ffaafa117222914ec2`, clean |
| MirrorGate | `4b379ac0c017e7621c945ebf8c106cd98a6c70d1`, clean |
| Batteries carrier | `f6efbfeb6353195c3318e3ef6e46d3e4e87897659989cd7322156d9e8a5f1cd3`, 3,684,180 bytes |

The task-owned repository is
`.golden-build/source-freeze-rc7-20261104/source`. Its clean local commit has
parent `d541d24`; it records the four reviewed version/documentation changes and
initial task planning receipts. It does not modify shared branch refs or create
a tag. The shared checkout retains the reviewed source edits for later delivery.

## Validation

The user requested performing the next stage after recovery publication,
authorizing the previously proposed rc.7 preparation and full local gate.
`bash tools/run-local-no-model-check.sh` passed in 139.8 seconds with
`ALL LOCAL NON-MODEL GATES GREEN`. Lake reports 737 jobs; DPM 87,
distribution 73 and durable-evidence 146 tests pass. The offline TLA suite
runs 81 tests with six documented skips. Native integer maps/controlled native
preparation remain skipped because `MIRRORCPP_PREFIX` is unset. All live-model
exclusions/self-skips remain explicit; no local Apalache/TLC was started.

Execution uses the admitted host context and owner-only ext4 temporary storage.
Actual host is Ubuntu 26.04.1 WSL2, kernel
`6.18.54.1-microsoft-standard-WSL2`, glibc 2.43. Source and pinned companion
identities remain stable before/after the full gate. The rebuilt mirror prints
exactly `v0.2.0-rc.7`. No C/native dependency graph change requires a separate
native-rebuild graph gate for this payload.

The gate ran against the reviewed shared worktree. A maintained snapshot of
that exact validated source is retained. The independently materialized clean
commit and both final source snapshots have the same source tree-index hash.
This equality uses the maintained source-snapshot policy, which excludes
planning receipts; it does not claim byte equality of the complete Git trees
or transfer installed/framework qualification.

Each catalog/lock family is copied into owner-only isolated staging. Refreshes
run from the clean task-owned source with explicit catalogs/lock roots and
`--skip-component-records --skip-render`. Two producer refreshes and an
independent third refresh are byte-stable. Both C0s bind clean exact source and
companion refs and declare Mirrors rc.7. The selected carrier satisfies both
dependency locks. Both complete source snapshots and all candidate files verify.
Shared catalogs/locks remain unchanged; the base profile is a structural control
and receives no installed Ubuntu 24.04 acceptance on this host.

Independent verification reconstructs the source snapshot from the clean commit
and rejects six actual controls: changed catalog and substituted snapshot component
for each family, plus missing carrier and same-size carrier corruption.
All 240 unrelated untracked files remain byte-identical. Shared Git index and
branch refs remain unchanged.

## Evidence and reproduction

`intake.json`, `gate-result.json`, `freeze-manifest.json`, `review.json` and
`inventory.json` bind inputs, gate output, clean task-owned identity, candidate
files, snapshots, validation scope and required retained receipts. `run-gate.py`,
`prepare.py` and `verify.py` document the executed operations. Preparation and
gate outputs refuse overwrite; do not rerun those producers over retained paths.

```sh
python3 Plans/source-freeze-rc7-20261104/verify.py
```

Raw logs, task-owned Git objects and source/candidate/snapshot trees remain under
ignored owner-only `.golden-build/source-freeze-rc7-20261104/`. The verifier needs
those retained artifacts and the reviewed rc.7 worktree; it is not a standalone
fresh-clone framework verifier.

## Next boundaries

Deliver the reviewed rc.7 source and new records through a separately authorized
shared commit/push, reconciling the resulting exact identity with this local
freeze before package construction. Preserve the earlier immutable rc.6
package/tag identity. An unused rc.7 tag still needs a fresh ref observation and
its separate local-tag/build boundary. New Linux/Windows packages precede final
installed distribution admission. Both D audits, fresh remote/runtime/client
admission, M5/Q, full Windows tests and release remain separate.

No shared branch commit/push, tag, package/cache build, installation, remote model
operation, service change, deployment or reboot is performed by this stage.
