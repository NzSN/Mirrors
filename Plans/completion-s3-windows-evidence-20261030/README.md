# Completion S3 Windows rebuild and package record — 2026-10-30

Executes the required Windows rebuild and packaging continuation of S3.7–S3.9
under the [S3 Windows executor handoff](../completion-s3-windows-executor-handoff-2026-10-30.md).
The earlier [S3 package record](../completion-s3-package-evidence-20261030/README.md)
and its rejected October 29 Windows row are preserved unedited; this is a
separate result record.

Machine-readable bindings are in `package-receipt.json`
(`mirrors.s3.windows-binding/v1`), with raw host receipts under `receipts/`,
bounded logs under `logs/`, the executed harness under `harness/`, and an
offline verifier in `verify.py`.

**No remote tag push, GitHub release, registry publication, production service
stop/start, binary replacement, configuration change or reboot was performed.**

## Result

| Item | State | Result |
| --- | --- | --- |
| S3.7 Windows rebuild | Passed | Built on `win10` from an archive of the exact local annotated tag `v0.2.0-rc.1` (commit `d737aa0886b9d406e391955756922d9d735d7ec1`, tree `8d2de2561d25c219e685bb46980080c03d7d1c98`) with no overlay. Native `lake build` completed 606 jobs with exit 0. |
| S3.8 Windows package | Passed | `mirrors-v0.2.0-rc.1-windows-x86_64.zip` SHA-256 `8d971bd9a735a70c3e707f11d6a52c0b02b712404d4381dee1d72f678ecfecf3`, 73,725,020 bytes, 7 members. Two independent packagings of the same binaries are byte-identical. |
| S3.9 Windows binding | Passed for this artifact | The new ZIP is bound to tag `v0.2.0-rc.1` / commit `d737aa0` and can replace the rejected row in a downstream `package-set.json` reconciliation. This record does not rewrite the earlier S3 record or claim its S3.9 aggregate gate. |
| Eight Windows gates | Passed | `fixtures_replay`, `diff_cross`, `model_interface_spec`, `stdio_smoke`, `transport_spec`, `jobstore_spec`, `async_resource_spec`, `dpm_sync_spec` all exit 0 with `APALACHE_MC`/`APALACHE_JAR`/`TLA2TOOLS_JAR` unset. No live-model tier was run. |

This is a staged native build and eight-suite package result only. S3.6 Ubuntu
24.04 runtime acceptance, S4 native M4, S5 full Windows/framework qualification
and S6 release admission remain outside this record, as do all public and
production actions.

## Source identity

| Item | Value |
| --- | --- |
| Tag | `v0.2.0-rc.1` (local-only annotated tag; tag object `f135f2809e6612d158c5be176c7ea6429b9d51f3`) |
| Commit | `d737aa0886b9d406e391955756922d9d735d7ec1` |
| Tree | `8d2de2561d25c219e685bb46980080c03d7d1c98` |
| Archive | `git archive --format=tar.gz --prefix=mirrors-d737aa0/ v0.2.0-rc.1` |
| Archive SHA-256 | `9de8226a0738d134c7ed0f0b6e3ebbad375f9169191331eaf204b1f4a8abe274` (21,871,950 bytes) |
| Extracted files | 9,207; content tree digest `e54a22e0ca262b236973db2412f7b7e46fdc5d9489bcfc95e15822005d3b3b40` |
| Extracted identity | No `.git`; `Shell/Version.lean` embeds `0.2.0-rc.1`; per-file path/size/SHA-256 digest recomputed on `win10` equals the local manifest |

`receipts/source-manifest.json` lists every archive member with its mode, byte
size and SHA-256. After the build, gates and packaging, all 9,207 members were
rehashed on `win10` with zero changes outside the expected `.lake` build outputs
and `.golden-build` generated test outputs
(`receipts/post-source-check.json`, `logs/s3.7-post-build-source-integrity.log`). The archive is retained at
`.golden-build/completion-20261030/windows-build/input/mirrors-v0.2.0-rc.1-source.tar.gz`
(ignored). The remote tag listing returned only `refs/tags/v0.1.1`, so
`v0.2.0-rc.1` was not pushed (`logs/s3.7-remote-tag-observation.log`).

## Build environment

New task-owned staging directory:
`D:/ModelMirrors/staging/s3-windows-20261030-d737aa0`. No existing checkout,
staging tree or production file was reset or modified. The offline `batteries`
package was copied from the October 29 staging tree only after binding its
content digest; no network fetch occurred during the build.

| Tool | Observed |
| --- | --- |
| Host / OS | `DESKTOP-6DKB5JD`, Microsoft Windows NT 10.0.19045.0, PowerShell 5.1.19041.6456 |
| Lean | 4.33.0, commit `d8b18978322de05a8f3dba51ef03cf5461676c17`, x86_64-w64-windows-gnu |
| Lake | 5.0.0-src+d8b1897 (Lean 4.33.0) |
| C compiler | `gcc.exe` (MinGW-W64 x86_64-ucrt-posix-seh, Brecht Sanders r8) 13.2.0 |
| OpenSSL | 3.5.0 CLI and headers/libraries at `D:/Programs/msys2/ucrt64`; bundled DLLs are the same bytes used by the October 29 package |
| Python | 3.10.11 |
| Git | 2.54.0.windows.1 |
| Offline dependency | `batteries` revision `4488d40d070b9700d4d5a6aa342f0d40c31b2a2d` (`v4.33.0`), 3,962 files, content digest `1f6896b77a7e0690d9083ec13ec7c35252cfb9e73d0b94070fdce3ea2dc45354` |

## Build and gates

`lake build mirror model_interface_gen fixtures_replay diff_cross
model_interface_spec stdio_smoke transport_spec jobstore_spec
async_resource_spec dpm_sync_spec` exited 0 in 87.4s (606 jobs);
`logs/build.log` is 93,255 bytes, SHA-256
`0bbc378ae5fae175591f1382f17be9ea99f0cef3ea827f6f276a625638f05da0`.

| Gate | Exit | Result line | Log SHA-256 |
| --- | --- | --- | --- |
| `fixtures_replay` | 0 | `ALL FIXTURES ROUND-TRIP BYTE-IDENTICAL` | `a1ac3ec1016e3876374f06b9344c078979bf1517ad2eb01f2f37f1e21c54528b` |
| `diff_cross` | 0 | `500/500 cases agree with Haskell` | `c756c8eca2e4314e3c42a5b2b6ecf284205075a8f820e9904c4d424a9674f6c7` |
| `model_interface_spec` | 0 | `MODEL INTERFACE SPEC GREEN` | `115609a409cb81cbe2bb938de26e52004835c819dff7697c0ab3b7d6f26ea266` |
| `stdio_smoke` | 0 | `STDIO SMOKE GREEN` | `150e212d9d245bbe9c356ea1df8578e4eb92f38e38b653139d13c56065779cc6` |
| `transport_spec` | 0 | `TRANSPORT SPEC: all green` | `f6962354deb979257d64546f374d934814eba22d43e43a3b8257a8d68f515420` |
| `jobstore_spec` | 0 | `JOBSTORE PARITY GREEN` | `f019ed3c03f0d635f84059339f6cb6a1903c1188393eb00bc0a05afde6824f6c` |
| `async_resource_spec` | 0 | `ASYNC RESOURCE PROOFS GREEN` | `e14caa75aaa0068084e7fd6deddd639a29ed223da67c4480ffca7e11ce6f7dd8` |
| `dpm_sync_spec` | 0 | `DPM CONTROLLED WITNESS SPEC GREEN` | `140867b31de2908bb87a6df57305c60ccd6da439fbbd9c7f07bc5ea4db575302` |

The first `transport_spec` attempt failed its throwaway-PKI cases because the
prepared `PATH` resolved `D:\Programs\Perl\c\bin\openssl.exe` before the OpenSSL
3 CLI. That environmental failure is retained verbatim as
`logs/transport_spec-initial-failure.log`; the authoritative run prepends the
OpenSSL 3.5.0 `msys2/ucrt64/bin` directory and records the resolved CLI in
`receipts/gates.json`. The seven other first-pass logs are retained under
`logs/first-pass/`; they are byte-identical to the authoritative rerun.

## Package

| Member | Bytes | SHA-256 |
| --- | --- | --- |
| `bin/ModelMirrors.exe` | 111,192,576 | `5500df1b9b8a028d93a5a79a13e5aa3dba8e92a5da4ad4fb39f285d097cc6627` |
| `bin/model_interface_gen.exe` | 112,591,360 | `83a2c353af98de0246378ee5c922951b27f1544692df154c7e07144243e1bfbd` |
| `bin/libcrypto-3-x64.dll` | 5,689,843 | `7909ab97fd1226890af8448a43cb9acd0e9758bfd595298c46c125211c3e61c7` |
| `bin/libssl-3-x64.dll` | 1,025,928 | `85377317f9fbc5a0b8264ba25c87670dbce2fe0988d186eb98d107460d8b416c` |
| `bin/zlib1.dll` | 128,488 | `93e9243a44c29200eeacaf9658efe2558581770e4b11ca4b500e18e424a6e3b5` |
| `BUILD.json` | 9,690 | `69e17843f7de338cd993402c4a98e25ec9e8e4686fa64628826a71ea1e4a3aa2` |
| `README.txt` | 217 | (recorded in `package-receipt.json` and the ZIP audit) |

Verified: member set and types; every member size/hash; embedded `BUILD.json`
equals the external manifest byte-for-byte; `ModelMirrors.exe --version` prints
`v0.2.0-rc.1` and the binary contains the ASCII version string; no Lean source,
`.olean`, key, certificate, token or private-key material is present; fixed ZIP
metadata (`2026-10-30T00:00:00`, mode `0600`) and byte-identical repeat packaging.

PE import closure (recomputed by `verify.py`): both executables import only
system DLLs plus the bundled `libcrypto-3-x64.dll`/`libssl-3-x64.dll`; bundled
DLLs add only system CRT/Kernel32/WS2_32/ADVAPI32/CRYPT32/USER32 imports.
`zlib1.dll` imports `KERNEL32.dll`/`msvcrt.dll`. There are no unresolved imports.

Artifact retention (ignored, not in Git):
`.golden-build/completion-20261030/dist-windows/mirrors-v0.2.0-rc.1-windows-x86_64.zip`
and the external `.build.json` manifest in the same directory.

## Production preservation

Read-only observations before and after the build/test/package work:

- Production `ModelMirrors.exe` remains SHA-256
  `8173ddea65f78a88b1a303f8a233dd7113b28e7dc8aefd8916a5add25a3687cc`, PID 9920,
  service `Running`, same command line and certificate paths.
- Certificate/public configuration hashes are unchanged; only the private-key
  file's hash is recorded, with no key contents copied.
- No process remains whose path or command line belongs to the task staging
  directory (`taskOwnedDescendantCount: 0`; observer ancestry excluded).

## Reproduction

```bash
# source identity from the shared checkout
git rev-parse 'v0.2.0-rc.1^{commit}'   # d737aa0886b9d406e391955756922d9d735d7ec1
git rev-parse 'v0.2.0-rc.1^{tree}'     # 8d2de2561d25c219e685bb46980080c03d7d1c98
# artifact identity
sha256sum .golden-build/completion-20261030/dist-windows/mirrors-v0.2.0-rc.1-windows-x86_64.zip
# offline record and artifact verification (no network, no packaged execution)
python3 Plans/completion-s3-windows-evidence-20261030/verify.py
```

Host-side harness copies are in `harness/`: source transfer verification,
dependency capture, build and gate execution, packaging, retry and final
observation. They are retained as executed; paths are absolute to the staging
directory named above.

## Integrity and claim boundary

`verify.py` checks this record's inventory, the source manifest, the raw
receipts, the retained ZIP and external manifest, gate logs, production
observation and DLL closure, then runs missing/tampered negative controls
against copies in a temporary directory. It never executes a packaged binary,
starts a model checker or contacts a service.

The record grants a staged native Windows rebuild from the exact local tag and
eight non-model suites. It grants no full `lake test`, no live-model tier, no
reproducible-compilation claim, no Ubuntu 24.04 runtime acceptance, no native
M4/framework qualification, and no release admission, publication, deployment,
service replacement, restart or reboot.
