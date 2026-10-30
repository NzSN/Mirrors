# Completion S3 clean tagged package record — 2026-10-30

Executes S3.1–S3.9 of the
[completion qualification and release plan](../completion-qualification-release-plan-2026-10-30.md)
under the [S3 executor handoff](../completion-s3-executor-handoff-2026-10-30.md)
and the [completion and release design](../../Docs/completion-qualification-release-design.md).
The S2 source input is the published
[S2 publication record](../completion-s2-publication-evidence-20261030/README.md).

Machine-readable details are in `package-set.json` (`mirrors.s3.package-set/v1`),
`windows-binding.json` (`mirrors.s3.windows-binding/v1`) and `s3-ledger.json`.
`verify.py` rechecks this directory, the retained artifacts and the negative
controls without executing a packaged binary or contacting a service.

**No remote tag, GitHub release, package-registry publication, production
deployment, service replacement, restart or reboot was performed.**

## Result

| Task | State | Result |
| --- | --- | --- |
| S3.1 | Passed | `d737aa0886b9d406e391955756922d9d735d7ec1` is the approved S2 commit; `Shell/Version.lean` embeds `0.2.0-rc.1`. Created the annotated **local-only** tag `v0.2.0-rc.1` (tag object `f135f2809e6612d158c5be176c7ea6429b9d51f3`). The GitHub tag listing showed only `v0.1.0` and `v0.1.1`, so no remote `v0.2.0-rc.1` exists. |
| S3.2 | Passed | New clean checkout `.golden-build/completion-20261030/release-source` detached at `refs/tags/v0.2.0-rc.1`; `git status --porcelain --untracked-files=normal` empty; the tag peels to the S2 commit. |
| S3.3 | Passed | `python3 -m unittest discover -s . -p 'test_*.py' -v` in `tools/release`: 11 tests OK. |
| S3.4 | Passed | `release.py build` from the clean tagged checkout: `lake build` of both binaries and five gate executables, then `fixtures_replay`, `diff_cross`, `model_interface_spec`, `stdio_smoke`, `transport_spec`, `check-client-framing.py` and the relocated-binary CLI smoke all passed. |
| S3.5 | Passed | `SHA256SUMS` verifies; embedded and external `BUILD.json` are byte-identical and bind tag `v0.2.0-rc.1` at `d737aa0`; `mirror --version` prints `v0.2.0-rc.1`; `model_interface_gen --help` exits 2 with `usage:`; `ldd` closure is limited to `libc`, `libm`, `libpthread`, `libdl`, `librt`; the archive holds only the four expected files in two directories; no Lean source, archive, credential, private key or token material. |
| S3.6 | Awaiting external input | No admitted Ubuntu 24.04 runtime exists on this coordinator (Ubuntu 26.04.1 LTS, WSL2, glibc 2.43). `release.py check-archive` was run here and passed, but it is recorded as a **diagnostic only** and grants no Ubuntu 24.04 runtime acceptance. The maximum required `GLIBC_` symbol version in both binaries is 2.25, compatible with Ubuntu 24.04's glibc 2.39, but that is static evidence. |
| S3.7 | Failed — rebuild required | October 29 staged ZIP source = `7e9a27d` + overlay `2777aaa3…` (recomputed tree digest `7bd27aff…` matches). Against S2 `d737aa0`: 8,790 of 8,810 manifest files identical, 20 differ, 397 S2-only paths are planning/documentation/evidence. Every compiled build input is identical, but 12 differing paths are behavioral tooling, tooling tests or interop-client sources (the other 8 are documentation, planning or evidence files), so the handoff's strict reuse condition is not met. The archive is rejected for S2 binding. |
| S3.8 | Passed — packaging only | Retained ZIP hash `bed5c045…a172` equals the October 29 receipt; 7 expected members; all five binary/DLL hashes equal `BUILD.json`; embedded and external `BUILD.json` identical; a deterministic local repack is byte-identical across two runs; `ModelMirrors.exe` carries the `0.2.0-rc.1` string; both executables' PE imports resolve to system DLLs plus the bundled OpenSSL 3 DLLs; no credential material. |
| S3.9 | Partial | `package-set.json` emits the bound Linux artifact and the explicitly rejected Windows artifact with source/build identity, runtime prerequisites, validation scope and retention locations. The "complete Linux/Windows artifact set" exit gate is not met while Windows requires a rebuild. |

## Artifacts

| Artifact | SHA-256 | Bytes | Retention |
| --- | --- | --- | --- |
| `mirrors-v0.2.0-rc.1-linux-x86_64.tar.gz` | `39623040464f71bcaff5f1b1002f93b1eec6d19e0bbecabc9a141b523d90b60a` | 72,209,232 | `.golden-build/completion-20261030/dist-linux/` (ignored, not in Git) |
| `mirrors-v0.2.0-rc.1-linux-x86_64.build.json` | `28beda2c810c085e28b0112d9e8bed5443a5cd64fe7aa62dcf67c0058db8da5a` | 2,874 | same directory |
| `mirrors-v0.2.0-rc.1-windows-x86_64.zip` (rejected) | `bed5c045102b80441a006a36e789164cf8dd50ad737008d3dda53a02d496a172` | 73,723,251 | `.golden-build/completion-20261029/release-artifacts/` (ignored, not in Git) |

Linux binary digests: `mirror` `1140d6fdfb9b1a619df13ecf3dd38791d25b5b72f04a04accf656c507e43e34a`,
`model_interface_gen` `f7bd3c9927c1b2ddfc94ba20cc68ddaf9e6ea00d5eddf3b0b0cdeeac03e6ace2`.

## Observed build environment

Ubuntu 26.04.1 LTS (WSL2, kernel `6.18.54.1-microsoft-standard-WSL2`, x86-64,
ext4), glibc 2.43, cc 15.2.0, OpenSSL 3.5.5, Python 3.14.4, Lake 5.0.0 /
Lean 4.33.0 (`leanprover/lean4:v4.33.0`). No local Apalache or TLC was started.

The first package-build invocation inside the restricted sandbox failed at
`transport_spec` with `socket creation failed`; that is an environmental
diagnostic, not a source failure. The retained passing run executed the same
builder outside the sandbox, and its log is `logs/s3.4-build-linux.log`.

## Reproduction

```bash
# identity (from the shared checkout)
git rev-parse 'v0.2.0-rc.1^{commit}'      # d737aa0886b9d406e391955756922d9d735d7ec1
# release tooling tests
(cd .golden-build/completion-20261030/release-source/tools/release && \
  python3 -m unittest discover -s . -p 'test_*.py' -v)
# artifact verification and diagnostic isolated smoke
(cd .golden-build/completion-20261030/dist-linux && sha256sum -c SHA256SUMS)
python3 tools/release/release.py check-archive --tag v0.2.0-rc.1 \
  --archive .golden-build/completion-20261030/dist-linux/mirrors-v0.2.0-rc.1-linux-x86_64.tar.gz
# this record
python3 Plans/completion-s3-package-evidence-20261030/verify.py
```

## Claim boundary

This record grants a local-only tag, a locally built and verified Linux package
and a packaging-only Windows recheck. It grants **no** Ubuntu 24.04 runtime
acceptance, native M4, full-framework or live-model qualification, Windows
full-gate or reproducible-compilation acceptance, remote tag, release
publication, package-registry publication, deployment, service replacement,
restart or reboot. The Windows ZIP remains explicitly unbound to `d737aa0` until
it is rebuilt on the Windows operator host from that commit.
