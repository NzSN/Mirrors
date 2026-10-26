# Published-commit M5 readiness — 2026-10-02

Status: **qualified for `m5-wsl-windows-remote/v1`**, using the
`m5-wsl-windows-remote` registry profile and `local-candidate` qualification class.
This is a fresh qualification of the published source cohort below. The
[earlier working-tree qualification](q3-m5-complete-2026-10-01.md) remains
historical and unchanged; none of its run IDs is reused for this candidate.

## Exact published source and distribution identities

| Repository | Qualified published revision | Included implementation changes |
| --- | --- | --- |
| Mirrors | `29d50ab25ac46ece70c0628f57a70dca4e8aef43` | 0 |
| MirrorECMA | `f2a6a5aa554d745e4497874ede7ce9ee9db9436f` | 0 |
| MirrorGate | `455e196c73332a1b0d85b1d822dfc4aa3542bbd9` | 0 |

C0: `77b9f27dbd6f806708bbf9609ed0169912bd7d0fc78463556c05c59f75cb44f6`.
C1 approval: `bb6845ec78ab9184384ee302eb753b123f3dddc1ef3d8f5ca6662e7d6997942c`.
Combination: `candidate.node-gate`. Outer Q: `run-ef411ef2-976e-4732-818f-2a5aa698412c`.
Snapshot-index SHA-256: `f1f52d72ac600414f38b2fd01e19b544dc02aaa711fdee577629b26a2dcc5124`.

Three identity refreshes reached byte stability. Source revisions match the
published commits exactly and every included-path list is empty. The selected
metadata records remaining editor caches, planning documents and generated
catalog/evidence files through explicit exclusions; those are not implementation
changes. No source, producer, packaging or registry fix was made in this campaign.
The pre-run C0 and subsequent C1 approval are retained separately.

| Distribution | Canonical manifest | Cache-index SHA-256 | Qualified D run |
| --- | --- | --- | --- |
| Local | `54f0c2cb95b9f626dbeaf5880719611a56cb69d1849a4a227fa6b2a160368203` | `1558a514e6c64b64189496dbc5d5f6031df69cd2f53a9002021a145ec0c76b46` | `run-d582b76c-297b-464c-af40-f1ad7f842ce6` |
| Gate | `fd98af39a3e2672919c4075f2400a9105b8145304d15eacffa3b63f48548662c` | `72d1a96b2454ea52bf46bd3b9854b4100a63adaa411c0aaf2f6e88494210b580` | `run-d7aa1a4e-b537-486f-a648-2168fd0b35a9` |

Both caches were rebuilt from the same immutable snapshot and verified before
transactional installation. Both installations committed at
`/tmp/mirrors-candidate-install-{local,gate}-final`. The two fresh D audits
ran first, each exercising its relocated consumer twice with sources hidden,
network unavailable and traced execution. Final installed-tree checks pass and
both CLIs report `v0.0.3.2`; no added bytecode is present.

## Q1 acceptance

All **18 required commands and 16 required tiers pass** for this C0. Source
validation records 129 evidence, 36 distribution and 63 capture tests;
MirrorECMA check and 626 tests pass with 13 optional skips; Gate records
297 supervisor tests and its supported real-backend acceptance passes. The source
gates cover Mirrors' full non-model suite, MirrorECMA check/tests and the required
supported real Gate backend. Local live Apalache/TLC tiers remain intentionally
excluded; all model operations use the Windows oracle.

Installed correct and faulty replay pass their registered baseline/mismatch
contracts and required cleanup. Both WorkQueue and LeaseService R1 runs reproduce
their own fresh finalized R0 references. Prefix reduction uses three actual
independent stability reproductions and checks all 16 prefixes, proving
`shortest_reproducing_prefix`, best **2/16**, complete minimality and a complete
stop. Policy: 40 candidates, 300000 ms total, 45000 ms per candidate,
10000 ms cleanup.

LeaseService R5 consumes its R1's identical required bundle bytes and validates
the declared `Client: 2 -> 1` edit at state 2 using the fresh remote oracle.
It replays the original, passes a correct baseline on the reduced two-occurrence
corpus and preserves the same state-5 `write` failure in the faulty reduced
corpus. Both corpus digests and every cleanup result are checked. Budget:
180000 ms total, 10000 ms cleanup; **no global-minimum claim**. Installed
LeaseService origin, R1 CLI and reduced-corpus replay also pass independently
with all repository roots hidden and network unshared.

Local and Gate mutation aggregates pass the fixed **17-case denominator** across
WorkQueue, PersistentTransfer and LeaseService, with detailed results and required
cleanup. A fresh owned Gate controller exits 74 after preparing four filesystem
resources and before worker launch. That origin retains failed behavior and
unconfirmed physical cleanup without qualification credit. Its linked native
recovery receipt reclaims all four filesystem resources, confirms recovery
cleanup and records no remaining resources.

The fresh Windows bound-3 HourClock check is `VALID`; all **22 declared mTLS
verdict/pin/protocol cases** pass across ECMA, C++, Rust, Lean and Haskell. The
owned native console remains at its observed endpoint `172.20.208.1:8999`, with
the pinned leaf, Apalache **0.62.2** and Microsoft Java **25.0.4+7-LTS**.
Process creation/ownership, listener, source/binary, runtime and certificate
identities are retained before/after. The actual Windows source snapshot remains
separate from the client C0. Windows work stays under
`C:\Users\ayden\Desktop\Workspace\MirrorsRemote`.

## Dependency restoration and fresh run ledger

Interop preflight initially refused because the Haskell checkout was absent.
The exact registered Haskell source was restored and its offline GHC/Cabal build
reproduced the frozen 43,640,168-byte `cc3c378e…` binary exactly. The registry's
ECMA compatibility carrier is prepared in a separate checkout at its pinned
revision; the published MirrorECMA component stays at `f2a6a5a…` and its installed
SDK/source gates run from that published revision. Every registry source/binary
pin stays unchanged. The failed prerequisite attempt is retained diagnostically;
only the successful fresh interop run receives credit. Exact client binaries,
compiled ECMA carrier and reference-source Git bundles are retained owner-only.

These are allowed public run references and public-summary hashes. Private
envelopes, command contexts, receipts and payloads are retained owner-only.

| Command | Run ID | Result | Public-summary SHA-256 |
| --- | --- | --- | --- |
| `framework.install-diagnostics` | `run-d582b76c-297b-464c-af40-f1ad7f842ce6` | Qualified | `0e318e5693d6a763b18cd10505279b22bef20a24d098fb6a5a6afe09ec985cad` |
| `framework.install-diagnostics-gate` | `run-d7aa1a4e-b537-486f-a648-2168fd0b35a9` | Qualified | `ccc940df6e2645fbae353dc04be5e504fd7a94fadcc42e0f19c047f7a35aa756` |
| `framework.replay-correct` | `run-71080fbc-0feb-4265-a1e1-b54c4d7e64fe` | Qualified | `f4fb118ffee8c7d642bb51ab2c48ea00d1169a5527155f0a3263439c06c32529` |
| `framework.mutation-local` | `run-94f2b9b0-5c9e-487d-aea1-44d64953c794` | Qualified | `260974eff5eb4e887e2b0bfe3e238f07a41708b1f7fdf2fbf6beee307f5e2113` |
| `framework.replay-faulty` | `run-59bf1b6e-2582-4d87-8cb1-040a92a8942b` | Qualified | `1b1fbc2352eb75acba1356c56ac0a14cfed336e19741e99c64323dc59f853f00` |
| `mirrors.remote-model-check` | `run-dd035288-1efc-41fa-8b24-38c470546b07` | Qualified | `b08a9460b522ca6e58aba126b76ffe94160997c9a317a2ff88a336de6e1ab87c` |
| `framework.lease-origin-installed` | `run-52ca0ac5-792c-4746-a572-3c9d02dd8e52` | Qualified | `f8c18b3544a42f48c84bd423f937869b47d1620a5d423e0513df6cda82619369` |
| `framework.reproduction` | `run-7ad54f83-a578-4769-b68e-228c00c959d5` | Qualified | `463bd1dfc1e72d04480eb1dfdab37efe7f8b72ccf53ec28ad139a67794588bf6` |
| `framework.reproduction-lease` | `run-8af7baae-f1d8-485e-9774-f17ded0a0b6c` | Qualified | `7f2e30ff2e59ea87a23f63d76a030d09a1c53f890ff923ef8980eb860524e3d7` |
| `framework.reduction-prefix` | `run-bde6deb5-d180-49b9-be45-f54e913e7a29` | Qualified | `3c3ea81da23a3e1e64c2ebd6f1ab5a172fd462c4b61240208a40fdedbfe7166d` |
| `framework.mutation-gate` | `run-d6b86303-dce2-41c1-b172-4925f0a97bb5` | Qualified | `6eed50e15a817ebac5b2f09a023890ecd80371642258f33d5b2b7e607ca63c8b` |
| `framework.recovery-origin-installed` | `run-a0f52849-756e-4319-8cf5-9379f0f9b8dc` | Retained interrupted origin; no credit | `fab70a1d54a4e9b5b66abb74201b1657903230e966e19fbe3c89ee0d2c1039c3` |
| `mirrorgate.recovery` | `run-ba450652-fb85-4814-bbb1-eadade296f49` | Qualified | `4b901fe78396bac9dfdb1632c35dfc22c38ca0d543a1ebb105a2bb2576fd46e6` |
| `framework.reduction` | `run-f987485d-c7e4-4543-b665-7ff1a3619d24` | Qualified | `5264ed6fa369a0b623dd10d9b34826eb90bc16dd26848e412151208320a3a3b8` |
| `mirrors.local-no-model` | `run-daecafee-c363-4b33-9fbf-d14744280cdd` | Qualified | `ff7c903c4eb24198c74d9a074067d2b8daec7e8c1ebc5873d2bcd65cdfacd176` |
| `mirrorecma.project-check` | `run-53970fee-e663-486c-8bf5-dc87d9340f9a` | Qualified | `ee6c5dd0a0f6a6c18a6e1181c70488c48c63af821c330ac70dd88dfeec383bc3` |
| `mirrorecma.test` | `run-9ffc4280-63b6-43b2-84a8-f870f9034d84` | Qualified | `6f4fed18866f70c30ea65b7fb84151a31e439a7ed50fc3f9ef12fbeb6f881e94` |
| `mirrorgate.required` | `run-f6647298-3963-407b-9165-c370539fb2b5` | Qualified | `669ec81fd311326284d7797303fbaf81a2cb8452fa411ccb50e3ba9e47cbe53f` |
| `mirrors.interop` | `run-b4672f24-7cac-4dd2-91ee-4c3ad31889ac` | Qualified | `a3249e9ea930f7ee2033bf4e24606ad9441a5c6b87e7e1672387fd0785bddc2b` |
| `evidence.offline-verify` | `run-ef411ef2-976e-4732-818f-2a5aa698412c` | Qualified | `f194db0265408581d3fd4887f8f6d598daac772d62498df56798a035cc589318` |

The Q input scope contains 18 credited nodes and one retained interrupted origin;
Q itself is outside that scope. There are **20 selected bundles** in total.
The additional Gate D audit supplies the second exact distribution binding.
The separate incomplete-profile diagnostic Q is not selected membership.

## Q2 independent verification and controls

The installed verifier, admitted C3 binary, bundled schemas/registry and six
installed pinned wheels independently accept all 20 bundles, the 19-node scope
and the complete named catalog profile. Repository roots and producer scratch
are hidden, the archive is read-only, and a distinct network namespace has no
external routes. Verification checks private/public references, artifact
membership/hashes, command contexts, distribution component ownership, both
R0/R1/reduction branches and recovery's exact original reference.

| Disposable control | Result |
| --- | --- |
| missing-required-artifact | Rejected |
| changed-artifact-byte | Rejected |
| wrong-D-component-binding | Rejected |
| wrong-R0-R1-linkage | Rejected |
| wrong-R1-R5-linkage | Rejected |
| incomplete-command-profile | Rejected |

The incomplete-profile control uses a genuine finalized Q over an otherwise
valid scope with the required remote model check omitted. Basic scope integrity
passes; named profile coverage rejects it. All selected originals remain intact.
Wrong-link controls use actual valid finalized evidence rather than fabricated
producer outcomes.

Private archive: `~/.local/state/mirrors/m5-published-commits-20261002`.
It retains fixed membership, complete E1 store, exact caches/snapshot, C1,
registered and independent Q results, all producer inputs/results, native
observations, source-hidden Lease acceptance, controls and file-hash indexes.
Credential bytes are excluded; prior archives remain unchanged.
[Independent result](/home/nzsn/.local/state/mirrors/m5-published-commits-20261002/independent-verification/result.json).

## Q3 and scope limits

| Milestone | Current acceptance for the published cohort |
| --- | --- |
| M2 | Qualified: both committed installs and both source-hidden D audits pass. |
| M3 | Qualified: both R1 branches, complete prefix/domain reduction and both fixed mutation aggregates pass. |
| M4 required clause | Qualified for prepared-filesystem ownership-safe recovery; aggregate/process claims remain separately unqualified. |
| M5 | Qualified: all 18 required commands/16 tiers and the complete independent two-D scope pass for this published cohort. |

The published source cohort now has complete Q1/Q2/Q3 acceptance for the named
profile. Native Ubuntu and aggregate-cgroup enforcement remain excluded and
separately unqualified. Recovery acceptance covers prepared filesystem resources
before worker launch; active-process post-restart recovery remains ambiguous
without non-PID/cgroup proof. No ambiguous ownership check is relaxed.
The declared 22-case remote matrix does not qualify every legacy transport.
The owned console does not establish AUTO_START or Windows service-manager
acceptance. Hosted CI and production deployment are separate observations.

This campaign changes derived catalog/lock output and reporting documents only.
Its target Git commits remain unchanged. Historical readiness records and
checkpoint entries are preserved. No additional commit or push is performed.
