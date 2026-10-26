# Qualification integrity fixes: readiness — 2026-10-03

Status: **qualified for `m5-wsl-windows-remote/v1`**, registry profile
`m5-wsl-windows-remote`, qualification class `local-candidate`.
This qualification covers the corrected working tree, including the implementation
paths recorded below. It does not qualify a later commit automatically.

## Corrected behavior

- Interop success and counterexamples require the selected client's declared
  terminal verdict and expected exit status. Invalid-option errors, conflicting
  verdicts, transport failures and timeouts fail the gate.
- Both ECMA adapters execute the explicit pinned Node and a clean SDK build from
  the registered compatibility revision. Complete SDK and Node identities are
  checked before and after execution; ambient Node options/module paths are
  removed. The v2 receipt and reviewed runtime pin are required E2 artifacts.
- Planning edits, additions, removals and restorations preserve the full C0
  selection, including catalog capture time. Planning paths are excluded from
  snapshots and recorded in a separate required private before/after audit.
  Historical v1 identities and hashing remain readable and unchanged.

Source validation: **142 evidence tests, 39 distribution tests**, Mirrors' full
non-model suite, MirrorECMA type checking and **19 focused catalog/wrapper tests**
passed. The initial focused Jest invocation could not contact Watchman inside
the sandbox; the focused rerun passed with Watchman disabled. The full registered
source gates were subsequently rerun and qualified for this C0. Live local
Apalache/TLC tiers remain excluded; all model checking used the Windows oracle.

The first candidate stopped at Haskell pin rejection because the new classifier
expected exit 1 instead of its documented infrastructure exit 2. A focused
regression failed before that correction and passed afterward. The candidate
was re-frozen; both distributions and every required tier were run afresh.
The first attempt remains diagnostic and receives no credit for this C0.
A second attempt passed all 22 client cases but could not retain its new
attachments because their file modes were 0644. The producer now uses the common
exclusive mode-0600 writer. A regression exercises real E2 attachment capture
under umask 022. The final candidate was re-frozen and fully rerun; both earlier
attempts are retained diagnostically.

## Exact candidate and distribution identities

| Component | Base revision | Included implementation paths |
| --- | --- | --- |
| `mirrorecma` | `3e7277b1a2812ef03e73a991c14bf9e5d8510c54` | 0 |
| `mirrorgate` | `455e196c73332a1b0d85b1d822dfc4aa3542bbd9` | 0 |
| `mirrors` | `ea8091c0c723f3f561044a5c1efb91d12e7aaf5f` | 20 |

C0: `de4e1864af4c5686d7620592adfead0c9822d9319c745ccc9bdee3ff25e534af`.
C1 approval: `817eb12f7b588e7ae5b9de9698d6fa35d19942adf9a213c86aaf9b083d84012a`.
Snapshot-index SHA-256: `dd9ee5f5294455d9003564763c248da62efa14f270b0368e3dea5d6f96c525a3`.
Outer Q: `run-cb7c34cf-cead-4b1d-85e3-ba3b4a092889`.

2 refreshes reached byte stability. One immutable snapshot produced both
verified caches; both installations committed. Both D audits ran first, with
relocated consumers, source hiding, network isolation and traced execution.
Final installed-tree checks pass. Editor caches remain on disk and outside the
selected source inputs. Planning records are outside identity-bearing catalogs.

| Distribution | Manifest digest | Cache-index SHA-256 | D run |
| --- | --- | --- | --- |
| Local | `e951d8f45ff7cb5eca86b55522e440b4747525ff737d06d0c399f341a26d8e55` | `6468a7d4cce7359b35bb6360c16f9cd06f25c3a5619b9e1036ec74499b7b6182` | `run-5f1bdf28-8ece-42f9-b337-ef53c5d64c56` |
| Gate | `ca7f45fa339f4d111446c86d077e673a9e9eefdb7798738203e4856739002f4d` | `ce242c589bd647a82f9a8a4811e09a496d1e86209809eefcb2c5344de536e326` | `run-c29693ba-8070-430f-aae5-2c994ffb4d54` |

## Q1 and independent Q2

All **18 required commands and 16 required tiers** pass. Correct/faulty installed
replay and both fresh R0/R1 branches satisfy their baseline/mismatch contracts.
Prefix reduction proves **2/16** with complete minimality. LeaseService R5 has a
valid remote candidate, a passed correct baseline, the same reduced-corpus
state-5 write mismatch and confirmed cleanup; it makes no global-minimum claim.
Both mutation aggregates pass the fixed **17-case** denominator. Recovery
reclaims four owned prepared filesystem resources from its fresh interrupted
origin; that origin is retained without qualification credit. Source-hidden,
offline LeaseService origin, R1 and reduced-corpus replay also pass.

The fresh Windows HourClock check is `VALID`, and all **22** declared five-client
mTLS verdict/pin/protocol cases pass. The stopped owned console was restarted
from its unchanged binary before the campaign; old observations/logs were saved
under `MirrorsRemote/qualification/integrity-20261002/previous`. Fresh process,
listener, source/binary, runtime and certificate observations are retained.
The oracle uses Apalache **0.62.2** and Microsoft Java **25.0.4+7-LTS** at
`172.20.208.1:8999`; its native source identity remains separate from client C0.
Windows work stays under `C:\Users\ayden\Desktop\Workspace\MirrorsRemote`.

The compatibility ECMA runtime was built from `61890cf14d8465df31ba6c95e72eade0a5716a66` with
TypeScript `5.9.3` and Node `v24.15.0`.
Its complete 113-file runtime digest is
`07a403ddcb32082d1fc7fd2d2d6e2f48a1381c58208774a2b3daeb8e7a72d25a`; Node SHA-256 is `d1de76d8edf2fededf6f8b30d244e2c0529ac607923a018283b77e9c74bd932c`.
The independently selected current MirrorECMA component remains as listed above.

Independent Q2 accepts **20 selected bundles and the 19-node scope with both D
bindings**, using installed schema/registry code and six installed pinned wheels.
Repository roots and producer scratch are hidden, networking is unshared, and
the retained archive is read-only. The v2 interop receipt, runtime pin and new
planning audits are included in required artifact hash verification. The retained
complete SDK tree and Node executable independently match the receipt bindings.

| Negative control | Result |
| --- | --- |
| missing-required-artifact | Rejected |
| changed-artifact-byte | Rejected |
| wrong-D-component-binding | Rejected |
| wrong-R0-R1-linkage | Rejected |
| wrong-R1-R5-linkage | Rejected |
| incomplete-command-profile | Rejected |

## Retained run references

| Command | Public run ID | Status | Public-summary SHA-256 |
| --- | --- | --- | --- |
| `framework.install-diagnostics` | `run-5f1bdf28-8ece-42f9-b337-ef53c5d64c56` | Qualified | `dd6685ed13bd747da39576ec95add9cdd5d77a55eb9f53eefbd5f5513cca3f78` |
| `framework.install-diagnostics-gate` | `run-c29693ba-8070-430f-aae5-2c994ffb4d54` | Qualified | `ea4547a2b222377fb593aea117c990efdc09caa46b5b9858b116f3ca203f37e0` |
| `framework.replay-correct` | `run-f6192718-d4ca-4c9b-b36b-8dc9c95027f3` | Qualified | `77a8fefb75e7eaa3a588293c05a629333de07de05dbcda6377a5e5ac0d02039e` |
| `framework.mutation-local` | `run-5fa21bd5-ed22-4d5d-afd8-e3eb7deb9a4f` | Qualified | `e4c1a2ae61f9d7acd919c781129a97b4a3808d894a67d9c7af0859b5765f9ab4` |
| `mirrors.remote-model-check` | `run-a9961869-2788-4d35-a204-d384caca5c5b` | Qualified | `e7fffa910e4c9e5fdbc38e5e80b9d4e280d2c763a75e059fd14235d1f0f9e2a7` |
| `framework.replay-faulty` | `run-49020537-1eff-45c4-b7b9-b39ada7e214d` | Qualified | `3d890af7e5224e570ca92b0568580b65ce7d0d7a79ff4d549fd7c65bce297a11` |
| `framework.lease-origin-installed` | `run-04fa0b91-98d0-436b-bc40-5c0ee8ddcb7b` | Qualified | `94193594e672b54354dd7e15d6a73d3d0f8805ad6a0ca3e05b857765e4f9b337` |
| `framework.reproduction` | `run-19f7661c-14c3-4181-a004-ad5de6c86d6f` | Qualified | `cdc2c7ae524ca04ee51d52c7cbebc50f574686b9746b7c97f92e65987f50fa10` |
| `framework.reproduction-lease` | `run-11716f56-0a7e-492f-8b2a-9e87732c5ae7` | Qualified | `1e864c9dfa7da446d8e06b666b8bd275bff60cc2530ed87c59a36ef43f7b9690` |
| `framework.mutation-gate` | `run-62c34b1c-8602-4d4b-aace-e5e7adccaaba` | Qualified | `315c584c0cb5b470db8adbffa53ed2ffc17fe743e99c0274ec6108c8b21298a3` |
| `framework.reduction-prefix` | `run-338af102-707b-4d52-8370-5b4e0aaf15f3` | Qualified | `e267b616d27935e0e25b50eb20e8d941b7231772cae7aecac123217472961c67` |
| `framework.recovery-origin-installed` | `run-cbf25c1c-74bb-4ce6-9cf9-256d234d1a3c` | Retained origin; no credit | `255f2ba506fd7f3fe2a41a6409027ef54f05ed2f9dcb677bb5fd2e07833ce128` |
| `mirrorgate.recovery` | `run-8c477dd4-8b72-4a51-b7c6-c06b1f065c11` | Qualified | `8ab777cafe22caf56402efc3b5430b62934a1c0d4d5a8446a9308bb2a7b36d12` |
| `framework.reduction` | `run-f9a88eae-87be-4cdb-9d2c-9e57b9b70d89` | Qualified | `10367c17e43b9c35053e26c1d0739294561631ed93eda5c52567add6dcc7d930` |
| `mirrors.interop` | `run-5b0faced-552a-4b7a-baca-2fab08a524ca` | Qualified | `727403c0823dd3d71be14708939ba202f993b7ff73595e9e129bb3811cde29d2` |
| `mirrors.local-no-model` | `run-892e45f7-7390-4459-885e-49dfb5467bde` | Qualified | `07ba9dd671def7c5fffea2d6b4aa4d82814cd2fce13e82141679bbdf4c619981` |
| `mirrorecma.project-check` | `run-bcfa2d9e-e4fe-4212-b027-60bb332bf50d` | Qualified | `cdca43351fc89a54cde03266ddb73a78c605196009adaa79f863c1f05498404a` |
| `mirrorecma.test` | `run-406e7ba2-16ba-48ba-89a1-c0d37daf34fd` | Qualified | `50b30f32b8fda450d1051fe6fefffc3b0f1746b82513eda015f4a1f263a0b3e5` |
| `mirrorgate.required` | `run-1c9c5eae-3d77-45c3-8951-63c70c2259c9` | Qualified | `1d1ccc79fa0d088f7d922676f3db0f6d663351e0002911119b4750c87ecf65aa` |
| `evidence.offline-verify` | `run-cb7c34cf-cead-4b1d-85e3-ba3b4a092889` | Qualified | `6de33edec733fef8775dc3c985eaf1e0925d73c1641619c18e7fdd0373828ad8` |

Authoritative private evidence, the source snapshot, caches, exact interop
carriers/runtime/Node, source Git bundles and independent-verifier output are
retained owner-only at `~/.local/state/mirrors/m5-integrity-20261003`.
Credential bytes are excluded. Earlier archives and checkpoint entries remain
unchanged. No commit, tag or push was performed for these fixes.

## Qualification limits

Native Ubuntu acceptance, aggregate cgroups, active-process post-restart
recovery, service-manager acceptance and the legacy full all-transport interop
matrix remain outside this profile. The current recovery result covers prepared
filesystem ownership only. The Windows console restart establishes the fresh
oracle process; it adds no Gate recovery or service-manager qualification.
