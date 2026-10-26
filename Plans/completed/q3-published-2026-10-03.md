# Published candidate: readiness — 2026-10-03

Status: **qualified for `m5-wsl-windows-remote/v1`**, registry profile
`m5-wsl-windows-remote`, qualification class `local-candidate`.
This qualification covers the published component revisions, listed below. It does not qualify a later commit automatically.

## Candidate scope

This freeze includes the compiler/client follow-ups and M6 implementation in
Mirrors and MirrorECMA. The registered source gates and installed profile gates
were rerun against this candidate. The separately pinned compatibility matrix
retains its established client/runtime pins; it does not establish qualification
of every new generated-client feature. All model checking used the owned
Windows oracle. No local Apalache or TLC was started.

All selected implementation paths come from the published revisions below;
there are no admitted implementation edits. Planning/status records and catalog
refresh outputs retain their declared exclusions. Compatibility client pins
remain unchanged and use separate pinned checkouts; this does not extend the
profile to newer client implementations or excluded transport tiers.

## Exact candidate and distribution identities

| Component | Base revision | Included implementation paths |
| --- | --- | --- |
| `mirrorecma` | `a03cf10a8787ff7691a4fd8b8f1013667501dfb7` | 0 |
| `mirrorgate` | `455e196c73332a1b0d85b1d822dfc4aa3542bbd9` | 0 |
| `mirrors` | `291961577b408cc135afe201f272ca684dc622e3` | 0 |

C0: `f01fb7717ca9bab18a68443707f478d49c15a15d420273db1e881c9683b16384`.
C1 approval: `9f5dd089130081d598bcec3136f90bc4419982af1dfd3deecd2f1799b1a41b8c`.
Snapshot-index SHA-256: `8925ea36576ef9e01dae5931198b506ac9a5862c071365b2b2868a1d07a2eb80`.
Outer Q: `run-5b93e3af-9ddf-4bef-979a-9159cbca6dcb`.

3 refreshes reached byte stability. One immutable snapshot produced both
verified caches; both installations committed. Both D audits ran first, with
relocated consumers, source hiding, network isolation and traced execution.
Final installed-tree checks pass. Editor caches remain on disk and outside the
selected source inputs. Planning records are outside identity-bearing catalogs.

| Distribution | Manifest digest | Cache-index SHA-256 | D run |
| --- | --- | --- | --- |
| Local | `6894b6d83f125eb4cb76a7c9ca6582e8c74daebe23213bdb43cb154d10d081eb` | `eadbf163dde3566a2dd504a275749e7b041cfbe61c014f1f759af8df8a8c47d5` | `run-2c926686-0c27-4877-bb4e-edc9ba92ff07` |
| Gate | `08286e4257495678f464e38056e00dabec2619ca702a8c9384b84c28734e1638` | `d1fc0f0b2d35cc061442b80641d6debb2eba0e8ee19f27c4c2df690b93cb75dd` | `run-e0df2658-fbad-4ad8-aaf9-85a48872b083` |

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
mTLS verdict/pin/protocol cases pass. Fresh native process, listener,
source/binary, runtime and certificate observations are retained.
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
| `framework.install-diagnostics` | `run-2c926686-0c27-4877-bb4e-edc9ba92ff07` | Qualified | `67e40d7c3fdee692960ed60654d8bf807eb757c2dd6e79fad619ba8be4439759` |
| `framework.install-diagnostics-gate` | `run-e0df2658-fbad-4ad8-aaf9-85a48872b083` | Qualified | `0d11ceda75f2530a9bab4d28e97a7421c1127ee3705f0926f27522f9da1b8a0d` |
| `framework.replay-correct` | `run-60723f58-5ab0-41a5-89c2-0c24e30d5636` | Qualified | `22aff860950b3a7f4e696d752491ae5f85fba8fc06b603f079342c24e294c9bc` |
| `framework.mutation-local` | `run-5dcd2543-5db2-4d56-9e13-2f3c8f8a8ed0` | Qualified | `8aedff9ecf684ab4c6fc2de29c26c508b07f82dfceea1f7d190784aace73dc69` |
| `framework.replay-faulty` | `run-1fb7f543-70da-489c-a6fd-fda825d0421e` | Qualified | `ec233b080cd47002f851543c42896f94497c799b3302200e8b60baa9533b49ff` |
| `mirrors.remote-model-check` | `run-843be88b-f813-4844-b5fe-aca5150ed856` | Qualified | `2a093c22b98966fbe64f5b7b708a8c1962113e5dfe9904ee14837d3345371855` |
| `framework.lease-origin-installed` | `run-96c1a6a9-edab-4e6f-a71f-68ad99e6f2ed` | Qualified | `209c2cc227327be8a117344466f373cfa86411e58f5965b45564ee945d326b67` |
| `framework.reproduction` | `run-a9d2a0dc-61aa-4214-b15b-e2901e80c2e0` | Qualified | `e20bf9de3f1c158816862b7d4a1cbd7f5e56c5468e8c0dc37a5f059a087333e6` |
| `framework.reproduction-lease` | `run-22372e77-d9ca-4fb0-9abc-a2d2dafe2e8c` | Qualified | `706a15cca4078b4277faf3c0c2db81610f574055a43bf230c9fb8eb02c9afc74` |
| `framework.mutation-gate` | `run-c68fbf3f-deb2-4885-ad5a-85583861fba9` | Qualified | `42368806f108f3ffb74e15237c5d0cf588a0e77bbf1574c04cdbf9369096f749` |
| `framework.reduction-prefix` | `run-8783ce51-0334-4d3e-a05b-eda04c4291f4` | Qualified | `3a33d6a58ca461fbb67d9c36fbf8afa45770ca0d5820e58bbfa1896a8818c525` |
| `framework.recovery-origin-installed` | `run-cd3528e3-ff89-4673-bc63-238b5a464b38` | Retained origin; no credit | `9dce9e674f7faa2c98b9698dcacb61798520d41a71f130183a139279930eda28` |
| `mirrorgate.recovery` | `run-f7726609-02e9-4140-ba66-f3fea720f4ed` | Qualified | `49cd8ed81a0979816301e37c91a1e9a8c75af3e7587d43aa6d4676f1daa42ade` |
| `framework.reduction` | `run-2001be89-6de1-4042-ae53-d17a22631b0e` | Qualified | `50f3e7f9cd039a233df255cafec15fbf2eab8c4fcc736375f83cfa5201a922bd` |
| `mirrors.interop` | `run-661d814f-9474-4568-9ccd-1d4a3af3bbfc` | Qualified | `57970b83b7d384fcac0dbeff8d46e685ddd26b3aec26f00550a69cbaf29352b8` |
| `mirrors.local-no-model` | `run-60fcfc95-3ed7-4a4c-aae0-15662c143296` | Qualified | `4fb86f171ad1e08ccc02e667ea97a0ff3bf3096844b845609955515c3b6a4f6b` |
| `mirrorecma.project-check` | `run-f64bc570-b40a-4c71-a890-514dabdef6ac` | Qualified | `13b6ed6d65d185641b4e863dc9fe031e4a590e302d42be3d72902cea6f6caae6` |
| `mirrorecma.test` | `run-10b4d252-1d5c-4a43-9405-67407a625aa7` | Qualified | `7c62191a79448e1f91bf342032f987f4e4b764acf4f77b4e247e2d4ddee5c03a` |
| `mirrorgate.required` | `run-0590b36d-4db9-43a5-8bd6-5e9fa3f1ed2e` | Qualified | `fdcc67f8a0cf5a5b994ae9b2cf3895fb267a74da437528cc5c3c4fe36949e631` |
| `evidence.offline-verify` | `run-5b93e3af-9ddf-4bef-979a-9159cbca6dcb` | Qualified | `6a7ce46d94ac36f8960afb137ffe26e35cfbe65048468902cfd21a92fbdb43d6` |

Authoritative private evidence, the source snapshot, caches, exact interop
carriers/runtime/Node, source Git bundles and independent-verifier output are
retained owner-only at `~/.local/state/mirrors/m5-published-20261003`.
Credential bytes are excluded. Earlier archives and checkpoint entries remain
unchanged. No commit, tag or push was performed for this candidate.

## Qualification limits

Native Ubuntu acceptance, aggregate cgroups, active-process post-restart
recovery, service-manager acceptance and the legacy full all-transport interop
matrix remain outside this profile. The current recovery result covers prepared
filesystem ownership only. Native oracle observations add no Gate recovery or service-manager qualification.
