# Published roadmap candidate: readiness — 2026-10-07

Status: **qualified for m5-wsl-windows-remote/v1**, qualification class
`local-candidate`. This completes the previously pending remote producers and
full-profile verification on a fresh candidate from the published revisions.
The earlier14/18 working-tree candidate remains historical and unchanged.

## Frozen published revisions

| Component | Revision |
| --- | --- |
| Mirrors | f0894d2c89426278900ba79f2b7a1b9b9c5d6620 |
| MirrorECMA | eef6f71f2ff2d22c6e3a83274d150638a010b663 |
| MirrorGate | 455e196c73332a1b0d85b1d822dfc4aa3542bbd9 |

C0: `94271a543085118e47c7fd540ee8d34d3f427fa5f45fedaeba0c852534f4f34a`.
Snapshot index SHA-256:
`e227fb87b3db842d83c97056e6162135579b9054819eadac43c220e7bc62213b`.
Later approval C1:
`28dc8f5abe998d1e2a0e18544e7a83a08b08ba05315962928a0696e34b6d0e10`.

Three refreshes reached byte stability; one immutable source snapshot produced
both verified caches. The bounded compiled build cache was hash-inventoried, not
used as old qualification credit. Both installs committed into the exact
registered prefixes while preserving previous versions; both D audits ran first.

| Distribution | Manifest |
| --- | --- |
| Local | 596aab4bbff91980a17b8e0fc5d6974740a4242449f6398c2f499dfbb177df93 |
| Gate | cd3bef469ea240d89f8719e1a9dccea4853accaa4fe2ce6e1799fe1c2d65a672 |

## Full Q1/Q2 acceptance

All **18 required commands and 16 tiers** pass. Full Q1 verifies **19 linked
nodes**, including both exact D bindings. Independent Q2 accepts **20 selected
bundles**, with repository roots and producer scratch hidden, network namespace
unshared, archive read-only and exact installed verifier/schema/registry/wheels.
The selected compatibility ECMA runtime and Node carrier are independently
hash-verified. Current generated-client/DPM feature scope remains separately
qualified; this compatibility matrix retains its declared client pins.

The [acceptance](m5-published-roadmap-evidence-20261007/acceptance.json) and
[independent result](m5-published-roadmap-evidence-20261007/independent-verification.json)
retain exact bindings. The six controls reject missing artifacts, changed bytes,
wrong D component binding, wrong R0→R1 linkage, wrong R1→R5 linkage and incomplete
required-command profile. The Q2 result SHA-256 is
`2df89d8c1d3f206cd676e04e59208b81e8dfd8a81b37fd51fe30b4e8be738162`.

Correct/faulty installed replay,17-mutant/29-case local campaigns, three Gate
application campaigns, both reproduction branches, shortest-prefix reduction
(2/16 with complete minimality) and ownership-safe prepared-filesystem recovery
pass. Domain reduction has a fresh model-valid LeaseService candidate, a passing
correct baseline, the same real reduced-corpus mismatch and confirmed cleanup;
it makes no global-minimum claim. Recovery reclaims four filesystem resources,
not an active worker tree after restart. Source suites and the compiler migration
helper pass with the recorded optional/excluded skips; no local model checker ran.

## Remote oracle and cleanup

The user authorized the remaining qualification and necessary startup. Existing
verified binary `5949af30735cd1bf515e64fb9d2299023e13b2c36245ce9be696d65944b32dec`
runs as owned native console PID 35888 under original runtime/certificate pins:
Apalache 0.62.2 and Java 25.0.4+7-LTS at 172.20.208.1:8999. Certificates and key
pairs were validated before start; no renewal, re-pinning or source/binary
replacement occurred. Windows writes stayed within MirrorsRemote.

Fresh HourClock bound 3 is VALID; all 22 five-client mTLS cases pass; LeaseService
remote materialization/validation passes. Before/after native observations agree
on process creation, PID, binary/source, complete runtime and TLS identities.
The final owned-process observation finds only the intended resident server and
no remaining owned model/test images. The service remains running for normal use.
This is not Windows service-manager/AUTO_START acceptance.

The startup caller's capture pipe timeout occurred after successful ready
observation; independent live admission succeeded and no duplicate startup was
attempted. First approvalB omitted required capability-observation bindings and
was correctly refused by Q2; that catalog/archive/output remains diagnostic.
Corrected later approval binds only required observed source/local/installed
capabilities to the actual fresh Q result; hosted-CI and package-published claims
remain unknown. No source rule or old proof record was weakened/rewritten.

## Retained producer references

| Command | Fresh public run | Qualification |
| --- | --- | --- |
| framework.install-diagnostics | run-46fac8f1-7074-4d00-9f91-719023a64a3d | qualified |
| framework.install-diagnostics-gate | run-c7fa2a9a-003d-4f57-a29c-f9cabf5c98f2 | qualified |
| mirrors.local-no-model | run-e1ed8f60-afc9-4f87-a686-d688d4a23d86 | qualified |
| mirrorecma.project-check | run-e8c3dc89-c0e5-4bf8-a1fa-5b6aaefcd770 | qualified |
| mirrorecma.test | run-ac1da6d9-71f0-400a-98ca-898dbe2ec203 | qualified |
| mirrorgate.required | run-9933a880-7c41-4d52-b822-9d300c53349a | qualified |
| framework.replay-correct | run-596d71b0-fb4e-4740-9959-b3fc0ffa41ec | qualified |
| framework.replay-faulty | run-3b2171e6-6780-46bd-ac2c-5e0840710168 | qualified |
| framework.mutation-local | run-0ffec770-d5a6-4579-bd81-8c0d4196231c | qualified |
| framework.lease-origin-installed | run-3bf0edf6-9b54-491c-95af-820c184c4df3 | qualified |
| framework.reproduction | run-f6e1f385-5d53-4821-81dc-37ee8a95b99e | qualified |
| framework.reproduction-lease | run-be05ec4f-283e-4363-97a4-3b9fa703565b | qualified |
| framework.reduction-prefix | run-348ca359-5f9c-4a69-a1ae-6b157331941e | qualified |
| framework.mutation-gate | run-bfe425ad-294a-495b-abf7-172dc6244638 | qualified |
| framework.recovery-origin-installed | run-3ce69442-b5c4-4a77-8933-449ece0214d0 | not_qualified |
| mirrorgate.recovery | run-aae7f7e9-fe17-493c-a597-20bf12c5cd4e | qualified |
| mirrors.remote-model-check | run-767eb4d2-d312-4fa7-a956-808d208501a3 | qualified |
| mirrors.interop | run-117a32f9-a974-4262-b2b8-4215ee319ec4 | qualified |
| framework.reduction | run-705afaad-5879-4a28-98b3-5dd4b7bc32df | qualified |
| evidence.offline-verify | run-8de7b167-1dfc-4cee-820c-51f75ec7353f | qualified |

## Retention and scope limits

Public summaries/identity reports are retained beside this document. Full private
producer payloads, source snapshot, dual caches, carriers, scripts, first rejected
approval and independent verification are retained owner-only at
`~/.local/state/mirrors/m5-roadmap-final-20261007`. Credential bytes are excluded.
The earlier October3 and incomplete October7 archives remain unchanged.

M4 aggregate enforcement/active-process restart recovery, native Ubuntu host
acceptance, Windows/macOS Gate backends, service-manager acceptance and the
legacy full all-transport matrix remain separately unqualified. This completes
the selected M5 profile, not those broader roadmap clauses. No commit/push or
package-registry publication is included in this qualification task.
