# Completion S3 reconciled package set — 2026-10-30

Evidence-only reconciliation of S3.1–S3.9 under the
[S3 reconciliation handoff](../completion-s3-reconcile-executor-handoff-2026-10-30.md)
(cited here by SHA-256
`949311ed97061466c46aedbd5d0b410424ba9c108cb56264a212f482d108ca7d`) and the
[completion qualification and release plan](../completion-qualification-release-plan-2026-10-30.md).
No source was edited, rebuilt, retagged or repackaged; no tag was pushed, no
release or registry publication occurred, and no service was replaced, stopped,
restarted or rebooted.

Inputs, both complete and retained unedited:

- [Initial S3 package record](../completion-s3-package-evidence-20261030/README.md):
  S3.1–S3.6, the original rejected S3.7 row and the S3.8 packaging-only recheck.
- [Windows rebuild record](../completion-s3-windows-evidence-20261030/README.md):
  the accepted S2-bound Windows rebuild and package.

Machine-readable output is `package-set.json` (`mirrors.s3.package-set/v2`,
superseding `v1`), `s3-ledger.json` (`mirrors.s3.reconciled-ledger/v1`),
`inventory.json`, and the offline `verify.py`. Raw checks are under `logs/`.

## Result

| Task | State | Reconciled result |
| --- | --- | --- |
| S3.1 | Passed | `v0.2.0-rc.1` is the annotated local-only tag object `f135f2809e6612d158c5be176c7ea6429b9d51f3`; it peels to S2 commit `d737aa0886b9d406e391955756922d9d735d7ec1`, tree `8d2de2561d25c219e685bb46980080c03d7d1c98`, and `Shell/Version.lean` embeds `0.2.0-rc.1`. |
| S3.2 | Passed | The retained clean checkout is detached at the tag with empty status; the tag peels to the S2 commit. |
| S3.3 | Passed | Retained release-tooling run: 11 unittest cases, exit 0. Log inventory hash rechecked. |
| S3.4 | Passed | Retained clean tagged Linux build: both binaries, five gate executables and seven non-model checks passed. No rebuild in this record. |
| S3.5 | Passed | Linux tar.gz `39623040…b60a`, 72,209,232 bytes, six entries / four files; embedded and external `BUILD.json` are byte-identical and bind the tag and commit; binary hashes and library closure match. |
| S3.6 | Awaiting external input | Still no admitted Ubuntu 24.04 runtime. The Ubuntu 26.04.1 WSL2 `check-archive` run remains diagnostic only. This row is unchanged by reconciliation. |
| S3.7 | Passed — superseding rebuild | Windows native build from an archive of the exact local tag with no overlay: 9,207 files, tree digest `e54a22e0…3b40`, 606 Lake jobs, exit 0. The original October 29 rejection is retained as a failed/replaced attempt. |
| S3.8 | Passed — S2-bound package | Windows ZIP `8d971bd9…ecf3`, 73,725,020 bytes, seven files; member hashes equal the embedded `BUILD.json` and external manifest `69e17843…a3aa2`; repeat packaging is byte-identical; PE imports resolve; eight non-model gates exited 0. |
| S3.9 | Partial | `package-set.json` names both accepted artifacts with source/build identity, validation scope, prerequisites and retention. Partial **only** because S3.6 is open; the Linux/Windows artifact set itself is complete. |

The S3.9 exit criterion in the stage ledger is satisfied by the reconciled
artifact set. Its state remains `partial` because the stage depends on S3.6,
which has no admitted Ubuntu 24.04 runtime input. No completion claim follows.

## Windows row reconciliation

| Item | October 29 attempt (retained) | Accepted replacement |
| --- | --- | --- |
| State | `rejected-rebuild-required` | `bound` |
| SHA-256 | `bed5c045102b80441a006a36e789164cf8dd50ad737008d3dda53a02d496a172` | `8d971bd9a735a70c3e707f11d6a52c0b02b712404d4381dee1d72f678ecfecf3` |
| Bytes | 73,723,251 | 73,725,020 |
| Source | `7e9a27d` + overlay `2777aaa3…` | exact tag `v0.2.0-rc.1` archive, no overlay |
| Binding audit | 8,790 / 8,810 manifest files identical; 20 differ (12 behavioral tooling/tests/client sources); reuse condition not met | 9,207-file manifest and content digest verified on `win10`; post-build rehash found no unexpected changes |
| Disposition | Historical and unedited in the initial S3 record and in `package-set.json#supersededArtifacts` | Sole accepted `windows-x86_64` row |

Neither record was rewritten. The original rejected row remains a retained
failed/replaced attempt; the new row supersedes it only in this reconciliation.

## Accepted artifact set

| Artifact | SHA-256 | Bytes | Retention (ignored, not in Git) |
| --- | --- | --- | --- |
| `mirrors-v0.2.0-rc.1-linux-x86_64.tar.gz` | `39623040464f71bcaff5f1b1002f93b1eec6d19e0bbecabc9a141b523d90b60a` | 72,209,232 | `.golden-build/completion-20261030/dist-linux/` |
| `mirrors-v0.2.0-rc.1-windows-x86_64.zip` | `8d971bd9a735a70c3e707f11d6a52c0b02b712404d4381dee1d72f678ecfecf3` | 73,725,020 | `.golden-build/completion-20261030/dist-windows/` |

Both external manifests are retained beside their archives and are byte-identical
to the manifests embedded in the artifacts:

- Linux `mirrors-v0.2.0-rc.1-linux-x86_64.build.json`
  `28beda2c810c085e28b0112d9e8bed5443a5cd64fe7aa62dcf67c0058db8da5a` (2,874 bytes).
- Windows `mirrors-v0.2.0-rc.1-windows-x86_64.build.json`
  `69e17843f7de338cd993402c4a98e25ec9e8e4686fa64628826a71ea1e4a3aa2` (9,690 bytes).

Accepted validation scopes are deliberately unequal:

- Linux: `fixtures_replay`, `diff_cross`, `model_interface_spec`, `stdio_smoke`,
  `transport_spec`, `check-client-framing.py`, relocated-binary CLI smoke; no
  live-model, native M4 or Ubuntu 24.04 runtime tier.
- Windows: native build plus `fixtures_replay`, `diff_cross`,
  `model_interface_spec`, `stdio_smoke`, `transport_spec`, `jobstore_spec`,
  `async_resource_spec`, `dpm_sync_spec`; no full `lake test`, M5 matrix,
  production lifecycle, reboot or reproducible-compilation claim.

## Verification performed here

1. Both input verifiers were executed and exited 0:
   - `python3 Plans/completion-s3-package-evidence-20261030/verify.py`
     (`inventoryFiles: 18`, rejected Windows row still refused);
   - `python3 Plans/completion-s3-windows-evidence-20261030/verify.py`
     (`inventoryFiles: 45`, 8/8 gates, 7 ZIP members).
   Logs: `logs/input-s3-package-verifier.log`,
   `logs/input-s3-windows-verifier.log`.
2. Independent rechecks, not trusting the inputs' pass status:
   tag object/type/peeled commit/tree and embedded version
   (`logs/reconciliation-identity.log`); artifact, manifest, source-archive and
   superseded-ZIP hashes with byte counts
   (`logs/reconciliation-artifact-hashes.log`); archive members rehashed, both
   embedded manifests compared byte-for-byte to their external copies, and the
   input records' recorded digests rechecked (superseded package-set, original
   ledger, Windows binding, Windows receipt) by `verify.py`.
3. `python3 Plans/completion-s3-reconciled-evidence-20261030/verify.py`
   re-hashes the inventory, both archives, both external manifests, the retained
   source archive and the superseded October 29 ZIP, then validates the ledger
   states. Log: `logs/reconciled-verifier.log`.

Negative controls in `verify.py`: missing record file, tampered record digest,
missing artifact, same-size all-zero artifact, tampered artifact digest,
escalating S3.6 to `passed`, escalating S3.9 to `passed`, and un-binding the
Windows row. Each control must be refused.

## Reproduction

```bash
python3 Plans/completion-s3-package-evidence-20261030/verify.py
python3 Plans/completion-s3-windows-evidence-20261030/verify.py
git rev-parse v0.2.0-rc.1 'v0.2.0-rc.1^{commit}' 'v0.2.0-rc.1^{tree}'
sha256sum .golden-build/completion-20261030/dist-linux/mirrors-v0.2.0-rc.1-linux-x86_64.tar.gz \
          .golden-build/completion-20261030/dist-windows/mirrors-v0.2.0-rc.1-windows-x86_64.zip
python3 Plans/completion-s3-reconciled-evidence-20261030/verify.py
```

## Claim boundary

This record reconciles existing evidence. It grants no S3 completion, no Ubuntu
24.04 runtime acceptance, no native M4, no full-framework or live-model
qualification, no release admission, no reproducible-compilation claim, no
remote tag, no GitHub release, no registry publication, no deployment, and no
service replacement, restart or reboot. The Ubuntu 26.04 archive smoke remains a
diagnostic. The local-only tag `v0.2.0-rc.1` remains unpushed.
