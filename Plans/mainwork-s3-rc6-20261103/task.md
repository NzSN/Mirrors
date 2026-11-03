# S3 rc.6 clean package tasks — 2026-11-03

## Authorization and acceptance boundary

The user requested the immediate S3 step after the accepted source/C0 freeze:
task development, Grok execution and Codex review. This authorizes a local-only
annotated `v0.2.0-rc.6` packaging tag in a separate task-owned clone, clean
Linux construction and the declared clean Windows construction/eight-suite
package smoke. It does not authorize a shared-checkout tag ref change, remote
tag push, hosted release, deployment, service operation, reboot, full Windows
`lake test`, local Apalache/TLC, installed D/M5/Q producer or release admission.

Freeze/source commit:
`3c4a87309cc3a81924660497207d7c295759bdc1`, tree
`5c15228e006f4d1b6efaa7e088488bc4b1fe619e`. Current published `0d95b6f` differs
only by planning/status records; prove that before relying on it. The tag must
peel to the freeze commit, and `Shell/Version.lean` must declare `0.2.0-rc.6`.
Selected WSL2 C0 is
`4bb83aa2efb022e801c7be5d7efb102f32d2f354f01d5d002d4f8897197af1f5`;
base C0 `f2bf471a…` remains a structural control.

Grok executes phases A–C as assigned. Codex independently reviews and owns
acceptance. A completed job or package is not S3 acceptance by itself.

## Shared constraints and ownership

Work only in NEW files under `Plans/mainwork-s3-rc6-20261103/` (except this task
file) and ignored outputs under `.golden-build/mainwork-s3-rc6-20261103/`, plus
a fresh task-owned Windows stage selected after read-only host observation.
Preserve all existing source, tags, packages, evidence, sibling checkouts,
services and unrelated untracked records. Do not edit the shared checkout.

Retain raw stdout/stderr/exit and exact command argv for every material command,
including failed attempts. Use owner-only fresh output/stage paths, refuse to
overwrite an existing path, and resume only from a separately verified exact
stage. Never weaken a check or discard a failure. No credential/private-key
payloads. Keep all manifests `published: false` and `deployed: false`.

## Phase A — source/tag/input admission

1. Record HEAD/tree/status and fresh origin/main and remote rc.6-tag absence.
   Prove `3c4a873..0d95b6f` is planning/status documentation only and the source
   version/tag rule passes maintained release validation.
2. Create a clean separate source clone at the exact freeze commit under the
   ignored task root. Verify status and tree. Create the annotated local-only
   `v0.2.0-rc.6` tag there, record its object/type/peel, and prove the shared
   checkout's tag refs remain unchanged. Never push it.
3. Prepare an offline Batteries input at exact revision
   `4488d40d070b9700d4d5a6aa342f0d40c31b2a2d`, tree
   `5a1de86f7997958aaffec998882c29006b688d1e`, from a verified existing local
   source/bundle. Verify Git objects/history and exact HEAD/tree. This source
   build input does not substitute for the missing locked S5 carrier
   `73130433…` or grant distribution admission.
4. Produce a source archive from the tag only, with archive SHA-256, complete
   per-file hash/byte manifest and file count. Record the tag/source/Batteries
   identities and input inventory. No overlays or generated source edits.
5. Make a read-only observation of the actual Windows host, PowerShell, OS,
   available source-transfer path, Lean 4.33.0/Lake, GCC/OpenSSL/Git and a fresh
   stage location. Do not query or alter the production service beyond the
   minimum read-only observation needed to prove it is not being used.
6. Write intake/source identity/input manifests and a bounded verifier for
   phase-A artifacts. Stop with a precise blocker if any identity is absent.

Exit: exact clean local tag, source archive/manifest, offline Batteries and
observed Linux/Windows construction inputs are ready for B/C.

## Phase B — clean Linux package

Depends on accepted phase-A output. Own only `linux*` evidence files and the
ignored Linux dist/smoke outputs.

1. Run release Python tests and the maintained builder:

   ```bash
   python3 -m unittest discover -s tools/release -p 'test_*.py' -v
   python3 tools/release/release.py build \
     --source "$CLEAN_SOURCE" --tag v0.2.0-rc.6 --output "$EMPTY_DIST"
   ```

   Use an ext4 task-owned TMPDIR. The builder supplies focused non-model build,
   fixtures/diff/model-interface/stdio/transport/client-framing and relocated
   CLI gates. Do not add local model checkers or the DPM CLI.
2. Verify `SHA256SUMS`, run maintained `check-archive`, and independently check
   exact archive membership, binary hashes, tag/commit/build manifest and
   allowed dynamic-library closure.
3. Run a second isolated archive/runtime smoke on the freshly observed actual
   Ubuntu 26.04.1 WSL2 host with source checkout and Lean absent from the
   packaged runtime PATH. Record the actual OS/runtime identities; do not copy
   the historical Ubuntu 24.04 smoke claim.
4. Produce `linux-build.json`, `linux-archive.json`, `linux-smoke.json`,
   `package-set.json` and raw logs. Bind archive, external build manifest,
   checksums, both binaries, source commit/tag, gates and explicit focused
   non-model-only scope.

Exit: maintained Linux builder and both archive checks pass with retained
identities, or a precise retained failure blocks acceptance.

## Phase C — clean Windows package

Depends on accepted phase-A output. Own only `windows*` evidence files/scripts
and the ignored Windows dist/review outputs plus the fresh observed Windows
stage. Do not execute the rc.5 campaign scripts; write reviewed rc.6-specific
scripts from the maintained contract.

1. Transfer only the phase-A source archive and verified offline Batteries
   input. Verify archive and complete extracted source manifest before and
   after all build/gates. No source overlay.
2. Build `mirror`, `model_interface_gen`, and exactly the eight package-smoke
   executables: `fixtures_replay`, `diff_cross`, `model_interface_spec`,
   `stdio_smoke`, `transport_spec`, `jobstore_spec`, `async_resource_spec`,
   `dpm_sync_spec`. Run exactly those eight suites, not full `lake test`.
   Remove Apalache/TLC environment selectors. Record exact tool/binary/OpenSSL
   import-library hashes and all command logs.
3. Package only required `bin/` payloads, `README.txt` and `BUILD.json` under
   `mirrors-v0.2.0-rc.6-windows-x86_64/`. No source, `.lake`, credential or
   staging member. Record tag, embedded version, freeze commit/tree, toolchain,
   file hashes and eight-suite scope.
4. Write the ZIP twice from unchanged packaged bytes and require equal SHA-256.
   Verify PE imports case-insensitively against the reviewed rc.5 system set:
   `ADVAPI32.dll`, `IPHLPAPI.DLL`, `KERNEL32.dll`, `SHELL32.dll`, `USER32.dll`,
   `USERENV.dll`, `WS2_32.dll`, `bcrypt.dll`, `dbghelp.dll`, `icu.dll`,
   `ole32.dll`, `ucrtbase.dll`, `msvcrt.dll`, `CRYPT32.dll`, `ntdll.dll`, plus
   `api-ms-win-*` and packaged DLL members. Any new import aborts packaging.
5. Produce `windows-build.json`, `windows-package.json`, package-set rows,
   archive/external-manifest/checksum records and all before/after/source/gate
   receipts. State explicitly: not full `lake test`, not reproducible
   compilation, not release admission.

Exit: exact source build, eight suites, repeat packaging and PE closure pass,
or a precise retained failure blocks acceptance.

## Phase D — Codex review

Codex independently verifies tag/source binding, archive members/hashes,
maintained Linux archive checks and isolated smoke, Windows repeat ZIP/PE
closure, eight-suite receipts, before/after source stability, inventory closure
and negative controls. Review may return defects for correction. Final records
must distinguish package acceptance from all pending S5/S6 qualification.
