# MW-12 source reconciliation — 2026-11-03

Status: source preparation reviewed and accepted after corrections. The final
S1 full local gate remains pending explicit approval.

The user requested the next mainwork stage using the same Grok execution and
Codex review process. Baseline HEAD is `75fbf96`. Prepare source `0.2.0-rc.6`;
existing rc.5 refs and artifacts remain immutable. No new tag, commit/push or
public/production operation belongs to this boundary.

- [Source task](source-task.md): version/refresh implementation and regressions.
- [Acquisition task](acquisition-task.md): exact companion and tool inputs.
- [Intake and job IDs](intake.json).
- [Codex outcome review](review.md), including the retained finding/correction.
- Integration command receipts and runtime inputs live under `integration/`.

The selected MirrorECMA `9192171` and MirrorGate `4b379ac` revisions are now
available in clean task-owned copies. A fresh ECMA runtime was prepared from
the selected revision using the locked Node/TypeScript inputs. These are input
preparation results, not live client or installed/framework acceptance.

Catalog/lock and registry integration is complete for this uncommitted candidate.
Mirrors is consistently `0.2.0-rc.6`, and the selected WSL2 C0 is `22596af7…`.
The base catalog is a structural control; no native/Ubuntu-24.04 acceptance is
added. Source refresh uses the selected tree, invalid declarations fail before
writes, and the CLI smoke follows the declared version.

Validation: 68 distribution, 146 evidence and 11 release Python tests pass;
targeted Lean rebuild, actual version output and stdio smoke pass. The corrected
integration harness independently reaches a stable fixed point. Its initial
failed attempt and the first source-selection finding remain retained.

Exact Batteries bytes, actual ptrace/namespace admission and fresh
remote/client/Windows inputs remain missing. A verified userspace tracer is
prepared, but its tracing smoke is denied in this execution context. Neither D
audit ran. The full local no-model gate awaits the approval question presented
this turn. No local model checker, new tag or public/production operation ran.

Verify retained evidence with `python3 Plans/mainwork-mw12-20261103/verify.py`.
Add `--current-source` to check the live working-tree candidate against its C0
and reviewed payload. Artifact integrity does not grant current-source or full
framework qualification to a different later tree.
