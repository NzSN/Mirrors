# Current roadmap candidate: readiness — 2026-10-07

Status: **incomplete for m5-wsl-windows-remote/v1**. This is the new working-tree
candidate, including the read-only lock migration helper. The October 3
qualified candidate remains historical and supplies no producer credit here.

## Frozen candidate and installed acceptance

C0: `d5358150e9fe041c930a066b6f2f0f88b2f617e782692dd7ad0e9c5b2bfe7109`.
Three refreshes reached byte stability. Snapshot index SHA-256:
`1db2f318dad77ab0bf1190e69f1cdca3fe7056318fb7cf4a8c3ce429a77ccaf9`.
Both caches verify; both canonical-prefix installs committed from one snapshot.

| Distribution | Manifest | D result |
| --- | --- | --- |
| Local | 1327123d01b7401975f3e3cbed83ed1e9e3c496078362c001c3ceb519cf40f9d | Qualified |
| Gate | 27022d4284f484e04a84561165f5f363ba29022c897dea04383b8f7945a26479 | Qualified |

Both D audits relocate twice, hide source roots, isolate networking and exercise
correct/mismatch replay. The installed migration supplement accepts valid locks,
rejects tampering and leaves input bytes unchanged in both source-hidden runtimes.

## Qualified available commands

The [run references](roadmap-next-evidence-20261007/run-references.json) bind each
fresh finalized result. **14 of 18 required command IDs** are qualified. The
additional Gate D is qualified; the recovery interruption origin is retained
without qualification credit. All four source commands pass: Mirrors local
non-model suite, ECMA type checking, ECMA 676 tests with 13 optional skips, and
Gate 297 Python tests with three skips plus 227 Node tests, four integration
cases and native/isolated conformance.

Installed correct/fault replay, local 17-mutant/29-case acceptance, LeaseService
origin, both R1 reproduction branches, shortest-prefix reduction (2/16, complete
minimality), all three Gate application campaigns and ownership-safe recovery
pass. Recovery reclaims four prepared filesystem resources with none remaining;
it is not active-process restart recovery.

Independent installed verification, with source hidden, networking unshared and
read-only inputs, accepts the integrity/linkage of the **16 available bundles**.
Its [result](roadmap-next-evidence-20261007/partial-independent-verification.json)
explicitly sets `q1Complete: false` and `q2FullProfilePassed: false`. This partial
integrity result does not satisfy the required full-profile verifier command or
its six full-scope negative controls.

## Open required work

| Command | Missing fact |
| --- | --- |
| mirrors.remote-model-check | Selected owned Windows oracle is stopped; startup approval pending |
| mirrors.interop | Same oracle required for the declared 22 remote cases |
| framework.reduction | Same oracle required for LeaseService domain materialization/validation |
| evidence.offline-verify | Full linked scope needs the three remote producers first |

The verified existing-binary startup script is prepared under the campaign root.
It pins original executable/runtime/certificate identities, preserves old records
and writes only the new owned Windows qualification directory. No service was
started or reconfigured. Certificate validity ends 2026-10-08T02:47:53Z; resume
must revalidate identity, listener and certificate validity rather than reusing
an expired preflight. Credential renewal, if needed, is a separate operation.

A separate actual full-profile diagnostic correctly refuses the incomplete
scope with `required command is absent: framework.reduction`; it receives no
full-profile credit. Final source/catalog/lock checks and both installed inventory
checks pass. Available private producer evidence, carriers, scripts and immutable
snapshot are retained owner-only at
`~/.local/state/mirrors/m5-roadmap-20261007-incomplete`, excluding TLS credential
bytes. Resume revalidates credentials from the existing owned Windows private root.

## Diagnostics and remaining roadmap scope

Earlier attempts remain diagnostic: foreign fixed-prefix argv preflight,
installed Python bytecode inventory mutation, missing Gate Node runtime root,
and missing installed MIRROR_BIN for mutation. Orchestration was corrected;
source contracts, acceptance rules and old envelopes were not weakened/rewritten.
Actual local mutation receipts independently bind their mirror SHA to D's admitted
mirror-server artifact. Required final receipts are never synthesized for a
failed attempt which produced none.

The [migration guide](../Docs/model-interface-compiler/lock-migration.md) and
[native-host/platform plan](m4-native-host-and-platform-plan-2026-10-07.md)
record source acceptance and next clauses. Native Linux/delegated-cgroup and
post-restart process recovery remain unqualified and outside this selected M5
profile. No new Windows/macOS Gate backend or non-intrusive scheduler is claimed.
No commit/push is included in this task; unrelated caches and Rust edits remain.
