# S3.6 Ubuntu 26.04 WSL2 package acceptance — 2026-10-30

Executes S3.6 and the S3.9 reconciliation requested by the
[S5/S3.6 WSL handoff](../completion-s5-wsl-executor-handoff-2026-10-30.md)
under the [completion plan](../completion-qualification-release-plan-2026-10-30.md)
and [design](../../Docs/completion-qualification-release-design.md).

This record **replaces only the S3.6 platform-scope disposition**. The original
[S3 package record](../completion-s3-package-evidence-20261030/README.md) and the
[reconciled package set](../completion-s3-reconciled-evidence-20261030/README.md)
remain unchanged. No commit, push, tag mutation, publication, deployment,
restart, reboot, or production change was performed.

## Result

| Item | Result |
| --- | --- |
| S3.6 | **Passed** in the explicitly selected `ubuntu-26.04-wsl2-x86_64` scope. `release.py check-archive` exited 0 with Lean and Lake absent from an isolated `PATH`, the empty source-lookup working directory, an owner-only mode-`0700` temporary root, and the read-only archive. |
| S3.9 | **Passed** with per-artifact limits: Linux is accepted under the WSL2 scope; Windows remains the S2-bound `8d971bd9…` package with eight selected non-model suites. This is a complete reviewable package set, not release admission. |

## Observed environment

- Ubuntu 26.04.1 LTS (`ID=ubuntu`, `VERSION_ID=26.04`, codename `resolute`).
- Kernel `6.18.54.1-microsoft-standard-WSL2`; virtualization scope `WSL2` only.
- x86_64, glibc 2.43-2ubuntu2.4, ext4 on `/dev/sdd`, 16 CPUs, owner uid/gid 1000.
- Tool paths: `/usr/bin/python3`, `/usr/bin/tar`, `/usr/bin/ldd`, `/usr/bin/git`;
  `lake`/`lean` exist only in the interactive host `PATH`, not in the isolated
  packaged-runtime environment.

`environment.json` records the facts. The scope is never called Ubuntu 24.04 or
native Linux.

## Verified identity

- Local annotated tag `v0.2.0-rc.1`, object `f135f280…`, peels to
  `d737aa0886b9d406e391955756922d9d735d7ec1`; tree `8d2de256…`.
- Archive `mirrors-v0.2.0-rc.1-linux-x86_64.tar.gz`, 72,209,232 bytes,
  SHA-256 `39623040464f71bcaff5f1b1002f93b1eec6d19e0bbecabc9a141b523d90b60a`
  (mode `0444` after acceptance).
- External build manifest `28beda2c…`, byte-identical to the embedded
  `BUILD.json`; both bind tag `v0.2.0-rc.1`, commit `d737aa0`, version
  `0.2.0-rc.1`, and binary digests `1140d6fd…`/`f7bd3c99…`.
- Six archive entries and four files only; no Lean source, tool archive,
  credential, private key, or token material.
- Maximum observed GLIBC symbol versions: `mirror` 2.25,
  `model_interface_gen` 2.17; interpreter `/lib64/ld-linux-x86-64.so.2`.

## Isolated packaged-runtime checks

`check-archive` and the independent CLI pass were run with:

```text
env -i PATH=/usr/bin:/bin HOME=<owner-only> TMPDIR=<owner-only> LC_ALL=C.UTF-8
```

- `command -v lean` and `command -v lake`: absent.
- Working directory: a new empty directory outside the checkout.
- `mirror --version`: `v0.2.0-rc.1`, exit 0.
- Out-of-order protocol smoke: one `protocol_error` message, exit 0.
- `model_interface_gen --help`: `usage:` on stderr, exit 2.
- `ldd` closure: `libc`, `libm`, `libpthread`, `libdl`, `librt`, and the loader only.

Logs: `logs/environment.log`, `logs/archive-source-binding.log`,
`logs/s3.6-check-archive.log`, `logs/packaged-cli.log`,
`logs/elf-requirements.log`, `logs/verifier.log`.

## Verification

```bash
python3 Plans/completion-s3-wsl-evidence-20261030/verify.py
```

The verifier re-hashes the archive and Windows package, compares the
external/embedded manifests, rechecks the tag peel, validates the accepted
scope against the actual `VERSION_ID`, and executes eight refusal controls:
Ubuntu 24.04 relabel, native-Linux relabel, failed check claimed pass, tampered
archive digest, Lean visible in the runtime path, incomplete package set,
unaccepted Linux row, and dropped platform limitation.

## Claim boundary

S3.6 is accepted only for an isolated packaged-runtime smoke on
`ubuntu-26.04-wsl2-x86_64`. It grants no Ubuntu 24.04 runtime acceptance, native
Linux acceptance, live-model or full-framework qualification, native M4,
reproducible compilation, release admission, publication, deployment, or reboot
acceptance. The Windows row remains limited to its recorded eight-suite
packaging/gate scope.
