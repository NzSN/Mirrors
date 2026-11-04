# S3 rc.7 clean packages — 2026-11-04

Status: **accepted for the bounded S3 clean Linux/Windows package stage** after
Codex execution and independent verification. The user changed execution
ownership from Grok to Codex before delegation began; no sub-agent was used.

Exact source is published freeze `f525c6349dc5a5e457757fa040c89312c6703e3a`,
tree `7b8bd98ac69a94497aa66cfe85885e15638d30db`, version `0.2.0-rc.7`.
Main `679b2eb` adds planning records only. The local-only annotated tag
`v0.2.0-rc.7` is object `9c7705c7fc02c692c79c27453bf2897227e54413` in the
task-owned clone. Its peel/tree match the freeze. Fresh before/after remote
observations show main unchanged and no remote rc.7 tag. Shared tag refs,
earlier packages/records and all 240 unrelated files remain unchanged.

## Accepted package identities

| Package | SHA-256 | Bytes |
| --- | --- | --- |
| `mirrors-v0.2.0-rc.7-linux-x86_64.tar.gz` | `3747d37fa884eac6bfbf56c99f1674b81b7bb48dd01993b0f74b45dfb9125d64` | 72,209,154 |
| `mirrors-v0.2.0-rc.7-windows-x86_64.zip` | `6c7043487f91345b36b39aab1e685100654926878597d179dcf4fff2422fca05` | 73,724,526 |

The source archive is 27,460,934 bytes, SHA-256
`940eb8217e0fd0c589c4a87398222aad9513958d84eeff11ab717a13d1124f21`.
All **9,947** source files were independently checked against the immutable
Git blobs, not only the producer's manifest. The exact vendored Batteries
carrier was cloned offline on both hosts; source identity and Git fsck pass.

## Validation and scope

Linux construction uses the maintained tagged release builder. All 11 release
Python tests, five declared executable suites, client-framing gate, relocated
CLI smoke and maintained archive check pass. An additional extracted-package
smoke passes inside bubblewrap with the source checkout and Lean installation
hidden, networking unshared and `PATH=/usr/bin:/bin`. Version, protocol-error
JSONL and compiler-help checks pass using the actual packaged bytes.
Runtime scope is the observed Ubuntu 26.04.1 WSL2 / glibc 2.43 host, not a new
native-Linux or Ubuntu 24.04 ABI claim.

Windows construction runs on `DESKTOP-6DKB5JD` (Windows 10) in a fresh stage
from that exact archive, with no source overlay. Build and all eight suites
pass: fixture replay, cross-codec diff, model-interface spec, stdio smoke,
transport, job store, async resource proofs and DPM controlled witness spec.
Every original source file is unchanged after the gates. Only two expected
generated Rust files were added outside `.lake/`.

The ZIP is written twice from unchanged payload bytes and is byte-identical.
Independent verification checks exact membership/order, embedded/external
manifests, source-built binary hashes, the three declared DLLs, all gate-log
hashes and case-insensitive PE imports against the reviewed closure. A separate
packaged Windows CLI smoke passes with source/Lean absent from `PATH`.
OpenSSL import-library and selected header hashes are recorded as post-build
observations; their file write times predate construction. This is not a
general reproducible-compilation claim.

The observed production PID 9920, executable and baseline public certificate/
DLL hashes remain unchanged. Service stays Running/Automatic; no task-owned
binary process remains. The later independent runtime smoke is followed by
another production PID/executable and cleanup check. No production key material or
production command line is read/exported.

Final independent verification rejects wrong Linux tag, wrong source-archive
hash, a missing Windows gate and an actual in-memory unreviewed PE import.
All checks pass. Git's warning about the pre-existing malformed historical
`Plans/completion-s2-publication-evidence-20261030/.gitattributes` is retained;
Git command exits, clean source checks and complete Git-blob/archive comparison
pass without modifying that historical file.

This is package acceptance only. Full Windows
`lake test`, native optional coverage, live-model operations, installed D/M5/Q,
release publication and deployment remain separate. No local Apalache/TLC,
remote tag push, hosted release, production service operation or reboot.

Task-owned raw outputs are under ignored owner-only
`.golden-build/s3-rc7-20261104/`; Windows writes are confined to the fresh
`D:\ModelMirrors\staging\s3-rc7-20261104-f525c63` and matching task temp directory.
No package binary or build tree is part of a Git delivery by this stage.

## Retained evidence

- `source-identity.json`: annotated tag, source archive/manifest and offline input.
- `linux-package.json`, `windows-collected.json`, `package-set.json`: package
  identities and exact test/host scope.
- `review.json`, `inventory.json`: independent verification and retained hashes.
- `admit.py`, `linux.py`, Windows scripts and `verify.py`: executed workflows.

```sh
python3 Plans/s3-rc7-20261104/verify.py
```

The verifier requires the retained ignored artifacts; it is not a standalone
framework qualifier. Raw build/source trees, logs, repeat ZIP and Windows stage
remain retained. No branch commit/push, tag publication, hosted release,
installation, D/M5/Q producer, production service change or reboot occurs.

The next dependency boundary is S5-A: reobserve the selected environment and
inputs, build/install both exact distribution profiles and pass both installed
audits before dependent qualification producers. Native optional suites,
remote-model/client admission and full Windows qualification remain open.
