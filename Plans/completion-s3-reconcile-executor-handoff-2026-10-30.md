# Generic-executor S3 package reconciliation handoff

Date: 2026-10-30

## Authority and scope

The user's S3 clean-package approval covers this final package-set
reconciliation. The initial S3 record and the later Windows rebuild record are
both complete inputs. Perform only evidence reconciliation and verification.
No source edit, tag push, release publication, deployment, service operation,
or reboot is authorized.

## Inputs

- Initial S3 record: `Plans/completion-s3-package-evidence-20261030/`.
  Its rejected October 29 Windows row is historical and must remain unchanged.
- Windows rebuild: `Plans/completion-s3-windows-evidence-20261030/`.
  Its new ZIP is the accepted S2-bound Windows artifact.
- Linux archive:
  `.golden-build/completion-20261030/dist-linux/mirrors-v0.2.0-rc.1-linux-x86_64.tar.gz`,
  SHA-256 `39623040464f71bcaff5f1b1002f93b1eec6d19e0bbecabc9a141b523d90b60a`.
- Windows archive:
  `.golden-build/completion-20261030/dist-windows/mirrors-v0.2.0-rc.1-windows-x86_64.zip`,
  SHA-256 `8d971bd9a735a70c3e707f11d6a52c0b02b712404d4381dee1d72f678ecfecf3`.
- Both bind tag `v0.2.0-rc.1` to commit
  `d737aa0886b9d406e391955756922d9d735d7ec1`.

## Required execution

1. Run both input evidence verifiers and independently recheck artifact hashes,
   source/tag binding, external manifests, and retention presence.
2. Create `Plans/completion-s3-reconciled-evidence-20261030/` with a README,
   versioned reconciled `package-set.json`, stage ledger, inventory, and
   offline verifier. Include missing/tampered artifact and inventory negative
   controls.
3. Mark S3.1-S3.5 and the superseding S3.7-S3.8 package work passed. Preserve
   the original S3.7 rejection as a retained failed/replaced attempt.
4. Keep S3.6 `awaiting-external-input`: no actual Ubuntu 24.04 runtime has been
   admitted. The Ubuntu 26.04 archive smoke is diagnostic only.
5. Mark S3.9 `partial` solely because S3.6 is open, not because Windows is
   missing. The package set must name both accepted artifacts, their exact
   validation scopes, and the remaining Ubuntu 24.04 exit criterion.
6. Do not claim S3 completion, Ubuntu 24.04 qualification, native M4, full
   framework qualification, release admission, publication, or deployment.

