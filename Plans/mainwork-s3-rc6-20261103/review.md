# Codex review — S3 rc.6 clean packages

Status: **accepted for the bounded S3 clean Linux/Windows package stage**.
This is not release admission, full Windows `lake test`, installed D/M5/Q,
remote-model, framework, deployment or reboot acceptance.

## Delegated execution

- Phase A `task-mw0e4779-txvtie`: local tag, source archive, offline Batteries,
  Linux/Windows input and read-only host admission.
- Phase B `task-mw0esjjk-54r9c6`: clean Linux construction and isolated smoke.
- Phase C `task-mw0esue8-brzhxo`: clean Windows construction, eight suites,
  repeat packaging and PE closure.

The task-owned annotated tag is
`5a2a6fd8728b610db7a6225b4a9d4c5d585344aa`, peeling to accepted freeze
`3c4a87309cc3a81924660497207d7c295759bdc1`. The shared checkout still has no
`refs/tags/v0.2.0-rc.6`; no remote tag exists or was pushed.

## Independent verification

Codex reran phase-A verification, source/tag/Batteries identity checks, Linux
`SHA256SUMS` and maintained `check-archive`, Windows checksum/repeat-ZIP/member/
payload/manifest checks, all eight Windows gate-log hashes and independent PE
import analysis. All passed.

A fresh post-build manifest was then generated inside the task-owned Windows
stage and independently compared against all 9,833 original source records. No
original file is missing or changed. The only additions outside `.lake/` are
`.golden-build/model-interface-rust/CorpusMirror.generated.rs` and
`MultiMirror.generated.rs`, expected `model_interface_spec` outputs retained
outside the package. They are not source overlays.

`verify_s3.py` consolidates these checks with the unified package set, inventory
closure and negative controls. Raw Codex review receipts remain under the
separate ignored `.golden-build/mainwork-s3-rc6-review-20261103/` root.

## Retained failures and corrections

- Phase A retained SSH-config, PowerShell probe and resume failures before its
  final read-only observation succeeded. The production service stayed running
  with unchanged PID, executable, configuration and observed file hashes.
- Linux retained an over-strict checksum-listing failure: the maintained builder
  writes `SHA256SUMS` before `release-notes.txt` and the checksum file itself.
  Every actual checksum line passed. A login-shell `/snap/bin` PATH probe also
  failed before the successful non-login `/usr/bin:/bin` isolated smoke.
- Windows retained a case/path-sort membership failure before correcting the
  ZIP writer to compare member sets and sort POSIX entry names. The first
  post-build comparison also rejected two generated files; the retained record
  now distinguishes those additions from the unchanged 9,833 archive members.
- The first consolidated-verifier attempt omitted `rev-parse` from its tag-peel
  probe. Its failure is retained in the Codex review log; the corrected probe
  and complete verifier then passed.

No failure was converted into a skipped required gate.

## Accepted artifacts and limits

- Linux archive: `9dc8e0ce2203c155bf8150479fd25e19bb5cd9774a6b688fd38fc57e74022038`.
- Windows archive and identical repeat:
  `9919ac2cb96a3dd693df89b02059a559f25aff7e052efc00a60a2e569c87564e`.
- Linux scope: maintained focused non-model release gates and actual Ubuntu
  26.04.1 WSL2 isolated runtime smoke; no DPM CLI.
- Windows scope: exact source build and eight declared non-model suites on
  `DESKTOP-6DKB5JD`; not full `lake test`, not reproducible compilation.

Exact locked Batteries carrier `73130433…`, ptrace/namespace admission, both D
audits, remote/TLS/client admission, M5/Q, full Windows tests and release remain
open. No remote tag, release publication, deployment, service change or reboot
was performed. S5-A remains the next dependency-gated stage.
