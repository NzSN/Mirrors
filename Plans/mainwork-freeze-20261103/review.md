# Codex review — MW-12 final source/C0 freeze

Status: **accepted after correction for the bounded F0–F4 source/C0 freeze**.
This accepts the freeze candidate, not installation, D, M5/Q, Windows,
remote-model, framework or release qualification. Grok's original report and
result remain execution records; this review is the acceptance overlay.

## Delegation and findings

Initial Grok job `task-mw0cdcb1-864xea` prepared the candidates. Codex rejected
the first outcome for four reasons: candidate directories were not uniformly
owner-only, the initial failed verifier receipt had been deleted, the verifier
did not directly compare S1 actual/expected hashes, and it lacked an independent
refresh fixed-point check. Correction job `task-mw0cxvlw-sns8x8` addressed all
four without changing the C0/catalog/lock/snapshot content bytes.

The initial failure is now retained as a recovered transcript, explicitly not
as the deleted original files. A second `FileExistsError` failure is also
retained. Candidate directories are mode 0700, future preparation enforces that
mode, S1 hash equality has a negative control, and third refreshes retain their
stdout/stderr/exit evidence outside the inventory closure.

## Independent reproduction

- Baseline selected refs were clean Mirrors `3c4a873`, MirrorECMA `9192171` and
  MirrorGate `4b379ac`; C3 SHA-256 remained `5a64a5bd…`. The validated-to-freeze
  delta contained only the two planning-documentation paths.
- A separate Codex fixed-point run refreshed independent copies of both
  candidates. Every file remained byte-identical and the selections remained
  base `f2bf471a…` and WSL2 `4bb83aa2…`.
- After correction, Codex ran `verify.py` independently: exit 0,
  `FREEZE VERIFY GREEN` and `NEGATIVE CONTROL GREEN`.
- Codex independently ran the distribution suite: 68 tests, exit 0, `OK`; and
  the durable-evidence suite: 146 tests, exit 0, `OK`, using an ext4 review
  TMPDIR.
- The retained initial failure transcript and second failure traceback match
  the correction report. All candidate directories checked are mode 0700.

Raw Codex review logs are under the separate ignored
`.golden-build/mainwork-freeze-review-20261103/` root and do not enter the Grok
inventory. The reviewed inventory closes over 6,378 files: ten Git-payload
candidates and 6,368 ignored raw artifacts; `inventory.json` excludes its own
unstable self-hash as documented by the verifier.

## Accepted identities and limits

| Family | Role | Canonical C0 selection |
| --- | --- | --- |
| base | structural control only | `f2bf471a2eba49d39a414bcee2c498d05dd350ac0494c5dd482ea292ccd30a0a` |
| WSL2 | selected `ubuntu-26.04-wsl2-x86_64` | `4bb83aa2efb022e801c7be5d7efb102f32d2f354f01d5d002d4f8897197af1f5` |

The accepted freeze revision is
`3c4a87309cc3a81924660497207d7c295759bdc1`, tree
`5c15228e006f4d1b6efaa7e088488bc4b1fe619e`. The full local non-model gate was
executed at parent `25b62541…`; only the proved planning-documentation delta
separates it from the freeze. No other qualification is transferred.

Exact Batteries bytes, ptrace/namespace admission, installed D audits,
remote/TLS/client/Windows inputs, M5/Q and release remain open. No commit/push,
tag, package, cache build, installation, D audit, remote/local model operation,
deployment, service change or reboot is part of this acceptance.
