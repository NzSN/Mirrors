# DPM review follow-up fix plan

Date: 2026-10-14. Status: completed for the declared remote WSL scope.

[Final acceptance](dpm-review-followup-evidence-20261014/README.md) records all
required gates, independent source/evidence review and separately frozen inputs.
The fresh installed and full non-model gates both exited 0. Earlier dossiers
remain unchanged; no fresh model checking, commit or push was performed.

The user requested this plan, a task breakdown, and execution in the same
instruction. [Tasks](dpm-review-followup-tasks-2026-10-14.md) assign ownership,
dependencies and acceptance checks. Heavy work runs on `windows-dev` Ubuntu WSL.

## Reviewed inputs and scope

The working trees start from Mirrors `6e0cbce8649b818d28431774e27731267598180e`,
MirrorCPP `75a63dba6b55a4514b8f0d75687066a2c55c8ef7`, MirrorECMA
`fe9a648136a63a5b348892e69033f44487f641f0`, and MirrorRust
`76061732f9ad46e063941dd48b10d1d9fb56dcb2`. The preceding
[qualification](dpm-review-remediation-evidence-20261014/README.md) binds the
reviewed sources. A subsequent review reproduced three additional findings:

| Finding | Observed failure | Required result |
| --- | --- | --- |
| P2 cancellation during cleanup | A second signal escapes the TERM grace wait; host exits 2 while its non-detaching runner remains alive | Cancellation during cleanup cannot skip TERM/KILL, reaping, stream/resource closure or final accounting |
| P2 C++ evidence admission | A final observation retains 1,054 event/observation bytes under a 1,024-byte limit and reports `passed=true` | Admit complete serialized observation/event rows, including array separators, before retention |
| P3 empty literal | `{literal:""}` fails `_plan` while a nonempty literal passes | Preserve empty literal argv entries; executable/script/artifact paths stay nonempty |
| Optional test isolation | New CTest synchronization cases have no timeout | Apply a finite CTest timeout consistent with neighboring scheduling suites |

Keep the v2 schema, SDK wire bytes, failure signatures, finite catalog ordering
and proof boundary unchanged. F5 remains C++ experimental with
`modelComparison: false`. Current oracle captures can be reused with their
provenance checked. Fresh model generation, broader M4 confinement, native
platform/M5 qualification, publication, deployment and commit/push are outside
this instruction.

## Cancellation and ownership

Make the complete `owned_process` cleanup interval resistant to SIGINT/SIGTERM:
TERM grace waiting, escalation to KILL, reaping, descendant checks, stream
draining, handle closure and final byte accounting. Use scoped cancellation
deferral with restoration on every exit. Preserve the first primary failure;
an additional cancellation cannot replace a timeout/output failure or discard
cleanup facts. Cancellation first received during normal finalization must
still produce a non-success result after cleanup completes.

The mechanism must not swallow cancellation during ordinary acquisition or
execution. Avoid detached cleanup threads and global permanent signal changes.
The existing non-detaching runner/process-group assumption remains. Hard limits
for uninterruptible kernel waits stay outside this correction.

Use an external bounded controller for process regressions. Cover normal exit,
single cancellation, repeated cancellation during TERM grace, and first
cancellation during timeout-triggered cleanup. Verify owned PID/group absence,
final logs/accounting and original failure precedence. The controller kills and
reaps every test-owned process even if an assertion fails. Add a public-launcher
integration control where practicable; distinguish function controls from that
integration result.

## C++ retained evidence

Build the observation row `{afterDecisions,state}` before checking capacity.
For events and observations, charge the actual appended serialized row and
the comma required by a nonempty destination array. Existing array brackets
already belong to the retained size. Factor the calculation if useful so both
append sites use the same rule.

Reject an over-limit row before appending it. Preserve the first failure,
confirmed physical cleanup, deadline flags and bounded failure metadata. The
execution limit covers retained event/observation bytes; separately bounded
declaration metadata is not charged to that limit. Exploration's whole-receipt
limit and failure reserve retain their existing behavior.

Cover a final observation at the exact limit and one byte over, and event
separator accounting at the boundary. An over-limit execution cannot pass;
successful exact-limit evidence must fit the measured bytes. Re-run the
controlled-resource suite and neighboring scheduling/binding/exploration suites.
Set the synchronization CTest timeout to 30 seconds; this is test-owner
isolation, not an SDK in-process interruption guarantee.

## Literal arguments

Separate nonempty path validation from bounded literal validation. Both reject
NULs and overlong UTF-8; literals admit the empty string. Preserve closed
argument objects, unknown-field refusals, literal argv boundaries and mandatory
Python isolation flags. Extend `DpmSpec` with positive empty-literal admission
and negative empty-path, NUL and length cases.

## Remote build and evidence

Preflight current remote resources and task-owned tool/source identities.
Create a fresh follow-up source/build/install namespace; preserve the earlier
installation, source snapshot and dated dossiers. Ordinary ext4 directories
are required for strict paths and atomic installation. Place large outputs on
D: and use the existing task-owned ext4 scratch capacity when necessary.

Transfer only the selected final source changes with SHA-256 verification.
Refresh Python helper/interpreter identities remotely and synchronize generated
source back before freezing the new input manifest. Rebuild Lean launcher and
affected C++ artifacts, prepare new v2 projects and install into a new prefix.
Do not infer acceptance from an earlier installation's hashes.

Run focused regressions, fresh source-hidden/network-isolated C++/ECMA/Rust
installed acceptance, and the remote no-model-check suite. Report explicit live
tier skips. A reviewer other than the implementation owners checks the final
source and actual controls. Record commands, runtime/source/install identities,
raw results and superseded diagnostics in
`Plans/dpm-review-followup-evidence-20261014/`.

Completion requires all task gates, independent review, verified manifests,
new current-status/checkpoint pointers and parent inspection. Preserve previous
checkpoint entries, both dated acceptance dossiers, unrelated editor caches and
ECMA `.work/` byte-for-byte.
