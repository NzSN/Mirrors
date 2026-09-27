# Q3 readiness report

Date: 2026-09-25 (M5 execution pass). This report is excluded evidence output,
so naming the selection here does not change the selection digest. M5 is not
qualified. Q1 and Q2 are not complete. Nothing was committed, pushed,
published, or deployed, and the remote model-check service was not contacted,
restarted, or reconfigured.

## Selected identity

Catalog selection
`9b187ba71af41cfff8ad681f174f3f88bcadd7b5aee99cac082b589e257e8877`
(`capturedAt` 2026-09-25T10:15:05Z). A live recomputation of every component ref,
both reference-node locks, all four distribution fixtures, the source snapshot,
both caches, and both installs matched this selection; there was no drift when
the installed runs below were executed.

| Component | Revision | Dirty content digest |
| --- | --- | --- |
| Mirrors | `ce75058b3f1c912eb5bee58b81f3bac1dab2714d` | `d9c19d83e47d3dde…` (21 included paths) |
| MirrorECMA | `59b722ac1c36d7c7be87ea7d962a89c6ab6d7145` | `18a80444f6706422…` (5 included paths) |
| MirrorGate | `72880aad92a1ae930239eea354c1fdb1485f655a` | `b0ba43500170a85a…` (3 included paths) |

`.projectile-cache.eld` remains on disk in all three checkouts and is excluded as
`pre-existing-unrelated`; generated catalog files, locks, fixtures, and this
report stay excluded as `evidence-output`. The source snapshot contains none of
them.

| Artifact | Value |
| --- | --- |
| Snapshot | `/tmp/mirrors-candidate-snapshot-e14` |
| Snapshot index SHA-256 | `22fdde17f6b0c568798c3e0fcaff28b71c3a6b1d49f322f901b4f56c251be2a9` |
| Local canonical manifest | `6d9464fbc77b09e6c5758a911848e69409f6aba6734eb9cfeecb3cc13d3fc55b` |
| Local manifest file SHA-256 | `f1f9eeadcc25be83bb14babf7b5a5041123a8ac78558a9b9386994e28c25bd9f` |
| Local cache-index file SHA-256 | `c319c6d1f884e2e0cbb5f98edc0d2edad3bda812018588f53931a10befef1a57` |
| Gate canonical manifest | `df07907cd6b7208f2234d477c8b1eb927b9d17b7e98df11a584d240755b8f87f` |
| Gate manifest file SHA-256 | `b712e46f455b0d8000e8879aaa074ad95509985fc51510ab3ead0e8e9f054916` |
| Gate cache-index file SHA-256 | `2bf2e3436a19cc35e4d3ffc8403370c9a09a1ed4992fdacb3821d3663e040fd0` |
| Local install prefix (registered) | `/tmp/mirrors-candidate-install-local-final` → `6d9464fbc77b09e6…` |
| Gate install prefix (registered) | `/tmp/mirrors-candidate-install-gate-final` → `df07907cd6b7208f…` |
| Evidence store (this pass) | `/tmp/m5-store` (see "Evidence stores" below) |

Both caches pass `tools/distribution/verify.py` without executing their tools,
and both registered prefixes were upgraded transactionally to these exact
manifests with `state=committed`. Earlier selections (`9fe8628b…`, `94b5603d…`,
`5d68417d…`, `67213742…`, `bf1bcbe7…`, `e11`/`d656e6e8…`) remain diagnostic only.

## Evidence stores

The sandbox for this execution pass can write only inside the Mirrors checkout
and `/tmp`; `/home/nzsn/.local/state/mirrors/evidence/v1` is read-only to it.
Retained runs from this pass therefore live in `/tmp/m5-store`, together with
byte copies of the two origin runs already retained in the canonical store.
The canonical store keeps its own copies and was not modified.

Runs recorded before this pass under the same selection were not re-collected:
`mirrorgate.application-campaign.work-queue`
(`run-dce8b40e-4e5d-4d62-a1b8-e3bde4fe02ee`, 10:21:01Z–10:21:16Z) and
`mirrorgate.application-campaign.persistent-transfer`
(`run-2686572d-a84d-42fc-8103-cf47deaf29ef`, 10:21:17Z–10:21:25Z) are
qualified origin-phase runs; copies are in `/tmp/m5-store` so scopes can
reference them offline.

## Qualified installed runs (frozen selection)

| Command | Run | Result |
| --- | --- | --- |
| `framework.replay-correct` | `run-a120cdd5-e296-4ae3-bcd0-c9d2ce2e9351` | qualified, exit 0 |
| `framework.replay-faulty` | `run-2b9bfa73-2c80-428d-96c6-60750c8f76f7` | qualified, exit 1 (intended mismatch) |
| `framework.mutation-local` | `run-ba548a80-6f32-43a1-bc87-a6f1deb8e62f` | qualified, exit 0 |
| `mirrorgate.recovery` | `run-e0cbd2b9-365a-416b-9eb4-2613ce386c39` | qualified, exit 0 |
| `mirrorgate.application-campaign.work-queue` | `run-dce8b40e-4e5d-4d62-a1b8-e3bde4fe02ee` | qualified origin (canonical store) |
| `mirrorgate.application-campaign.persistent-transfer` | `run-2686572d-a84d-42fc-8103-cf47deaf29ef` | qualified origin (canonical store) |
| `evidence.offline-verify` (scope check) | `run-e1f9549f-f446-4a00-8e67-acf1eea1f253` | not qualified: scope correctly rejected |

Recovery reclaimed the filesystem resource `owned-work` from
`/tmp/m5/recovery-state`. Its receipt binds the origin-phase work-queue campaign
envelope (`run-dce8b40e…`, private envelope SHA-256
`230d6ead548674f0833a3f5c05c492590bb5b244e88a8c9dc38c0e4676ecf0c5`), records
`original-behavior=passed` and `original-cleanup=confirmed`, and claims no
cgroup observations. These are individually retained runs, not a verified Q2
scope.

## Local non-model gate

`bash tools/run-local-no-model-check.sh` was executed with its command list
unchanged, but its 40 steps were run individually from a `/tmp` wrapper so a
blocked step could not mask the rest. 35 of the 40 steps exited 0, including
`lake build` (642 jobs), the fixture and codec suites, every model-interface
golden and the Rust checks, distribution and durable-evidence unit tests,
manifest validation, and the two live-tier self-skip checks. The five non-zero
steps are all environment limits of this execution pass:

| Step | Class | Cause |
| --- | --- | --- |
| `validate source closure` | environment (sandbox) | `check-validate-closure.py` cannot create a socket |
| `validate async protocol codec` | environment (sandbox) | `check-validate-async.py` cannot create a socket |
| `transport` | environment (sandbox) | `listenTcp` / server child need loopback |
| `registry` | environment (sandbox) | mock Consul cannot bind `127.0.0.1` |
| `TLA differential offline` | environment (toolchain) | 60 tests ran; `acquire.verify_tools` exits with "Java 25.0.4+7 is required for DV1 qualification" |

One exit-0 step is not fully green and is therefore not credited here:
`explorer pure/unit` prints `EXPLORER SPEC: 3 failures` (`http: server port`,
`http: content-length echo`, `http: chunked decode`, all `socket creation
failed`) and still exits 0, because
[`tools/ExplorerSpec.lean`](../tools/ExplorerSpec.lean) prints its failure list
without setting a non-zero exit code. Its live integration portion self-skips
with `APALACHE_MC` unset. `apalache_cli_spec` is green by both exit code and
output: 19 scenarios ran and `integration` self-skipped.

Harness note: the first two `/tmp` wrappers recorded the two `pure/unit` steps
as `rc=1` without running them, because their labels contain `/` and the
per-step log path became `step-Apalache_CLI_pure/unit.log`, so the shell
redirect failed before the binary started. The corrected wrapper is
`/tmp/m5/gate-steps-v2.sh`; its authoritative run is `/tmp/m5/logs-v3/`
(`steps.txt` plus one log per step). Earlier runs are kept at `/tmp/m5/logs/`
and `/tmp/m5/logs-v2-slash-bug/`, the buggy wrapper copy at
`/tmp/m5/gate-steps-modified.buggy.sh`, and the provenance note at
`/tmp/m5/LOG-PROVENANCE.md`. Direct execution of
`.lake/build/bin/apalache_cli_spec` and `.lake/build/bin/explorer_spec` with
`env -u APALACHE_MC` reproduces the exits above.

The aggregate command itself was also collected
(`mirrors.local-no-model`, exit 1) and is retained without qualification,
because the runner stops at the first socket-blocked step.

## Environment limits of this execution pass

- Sandbox escalation is unavailable: the automatic approval reviewer returns
  `supported API model names are deepseek-flash, deepseek-v4-pro, but you
  passed codex-auto-review`. Every escalated command was refused before
  execution, so work continued sandboxed and no canonical-store write was
  possible.
- The sandbox denies every `socket()` call (AF_INET and AF_UNIX), `ptrace`/
  `strace`, and writes outside the Mirrors checkout and `/tmp`. MirrorECMA and
  MirrorGate checkouts are read-only to this pass.
- Two disclosed workarounds were needed inside the sandbox, neither of which
  changes selected sources: `NODE_OPTIONS=--import /tmp/m5/node-spawnsync-shim.mjs`
  clears the spurious `error=EPERM` that Node's `spawnSync` reports here for
  successfully executed children (the collector records only allowlisted
  environment names, so this is disclosed here rather than in the envelopes),
  and the lease-service origin campaign consumed `/tmp/m5-ecma`, a byte copy of
  the MirrorECMA checkout whose gitignored `dist/` was rebuilt with
  `node_modules/typescript/bin/tsc` because `pnpm` cannot open its store here
  and the live checkout is read-only.

## Required tiers that remain incomplete

| Tier | Exact blocker |
| --- | --- |
| `framework.install-diagnostics` | `run-53420809-3f12-4516-8d13-bbfa0ea6bf46` is retained; the audit computed manifest `6d9464fbc77b09e6…` for the registered prefix and then failed in the relocated replay: `/usr/bin/strace: PTRACE_TRACEME: Operation not permitted`. No qualified D run exists, so no scope can be credited. |
| `framework.mutation-gate` | `application-program-gate-all.mjs` fails instantly with `baseline_failed`: the Gate path connects to the supervisor over a UNIX socket (`sandbox.ts` `ControlClient.connectUnix`), which this sandbox denies. No retained bundle (staging only). |
| `mirrorgate.application-campaign.lease-service` | Same Gate-socket blocker. The earlier failure (`observer-throws` classified `codec` instead of `implementation`) was traced to the stale gitignored `dist/` in the live MirrorECMA checkout, not to selected source; with a rebuilt copy the campaign reaches the Gate session step and then fails with `baseline_failed`. |
| `mirrorecma.project-check` | `run-729a516f-d8cc-4dd3-9d7c-e10dbbdaf82d` retained: `pnpm run check` first runs pnpm's dependency-status check, which triggers `pnpm install`; the install fails immediately (exit 226) with `EROFS: read-only file system, open '/home/nzsn/Repos/MirrorECMA/_tmp_…'` because the live MirrorECMA checkout is read-only to this pass. |
| `mirrorgate.required` | `run-d2b5df32-bd89-4373-aed9-27a04a0e6c16` retained: `scripts/test.sh` fails at `runtimes/rust/target/debug/.cargo-build-lock` (read-only filesystem). |
| `framework.reproduction` | Real adapter gap, now derived in full (`tmp/m5-reproduction-adapter.md`). The frozen registry entry has three reproducible defects: the argv omits the mandatory `--evidence-envelope` and `--output-root` (verbatim run → `code=usage`, exit 2); it passes `--tool-registry installed-registry.json`, which the project layer rejects with `configuration_invalid: toolchain has missing or unknown fields`; and it names `mirror.correct.project.json`, which can never reproduce a mismatch bundle. The rest of the chain was proven end to end on this selection: a probe built a bundle from the qualified faulty R0 (`run-2b9bfa73…`) and the installed CLI returned `status: reproduced`, exit 0, writing `reproduction-result.json` and `reproduction-cleanup.json`. The one missing piece is the identity authority: replay recomputes `identities` from the project and refuses any difference, but `inspectProjectReproductionAuthority` is not among the installed package's 151 public exports — it exists only in `dist/project.js`. Implementing the materializer in Mirrors therefore needs a named decision: MirrorECMA exports the project-layer identity or capture API (R2 card ownership), or Mirrors accepts a dependency on that internal path. Separately, `captureReproduction` cannot consume an R0 JSON artifact for a mismatch (`suite_result_incomplete`: the action lives on the deliberately non-serialized `trustedError`), so a post-hoc builder must construct the signature from the recorded fields. |
| `framework.reduction` | `packages/mirrorecma/scripts/materialize-lease-reduction.mjs` sets `APALACHE_MC` to a pinned local launcher before `startExploreSession`; there is no remote explore-session path, and local model checking is prohibited here. |
| `mirrors.interop` | Missing companion checkouts `MirrorCPP`, `MirrorLean`, and `ModelMirrors` (HS) plus `HS_BIN`; the runner has no remote-only mode and would run local Apalache. |
| `mirrors.remote-model-check` | No operator credentials (`MIRRORS_REMOTE_*`) are present, and the sandbox blocks network access. Selected Apalache 0.61.0 / Java 25.0.4+7 identities remain unverified. |
| Delegated cgroup / native Ubuntu | `/sys/fs/cgroup` has no writable delegated parent on this WSL2 host (kernel `6.6.114.1-microsoft-standard-WSL2`); no real aggregate-enforcement or native-host evidence. |
| Publication and deployment | Not performed. |

## Q2 status

Two verifiers from the installed local runtime were exercised against
`/tmp/m5-store` and against copies of it:

- `verification/bundle/tools/evidence/qualification_scope.py --scope
  /tmp/m5/scope/qualification-scope.json --store …` rejects a scope that
  credits the failed distribution run with `credited qualification run is not
  qualified: run-53420809-…`; that rejected attempt is itself retained as
  `run-e1f9549f…`. This check runs before artifact integrity, so while the
  distribution binding is unqualified the scope verifier cannot reach the
  tamper checks.
- `verification/bundle/tools/evidence/verify.py --offline <bundle>` is where the
  integrity path was exercised, one bundle at a time: the untouched
  `run-a120cdd5…` bundle returns `status: verified` (exit 0); the same bundle
  with `artifacts/private/stdout.log` deleted fails with `[Errno 2] No such file
  or directory: 'stdout.log'`; a `run-2b9bfa73…` bundle with one flipped byte in
  that file fails with `bundle record identity mismatch:
  artifacts/private/stdout.log` (both exit 1). The tampered copies are kept at
  `/tmp/m5-tamper-a` and `/tmp/m5-tamper-b`.
- verification reads only the store bundle, so producer scratch removal does not
  affect it.

Integrity detection works, but no verified scope exists for this selection
because Q2 requires a qualified D binding, and the distribution run is blocked
by the sandbox `ptrace` restriction. Q2 is therefore incomplete rather than
failed.

## Milestone status

Individually qualified on the frozen selection: installed correct and faulty
replay, local mutation aggregate, filesystem recovery bound to an origin-phase
Gate campaign, and two of three origin campaigns. Not established: installation
audit (D), Gate mutation aggregate, LeaseService origin campaign, reproduction,
reduction, interop, remote model check, delegated cgroup enforcement, native
Ubuntu acceptance, publication. M5 is not qualified and Q1/Q2 remain
incomplete.

## What would complete M5

1. Re-run the installed and source commands in an environment with loopback and
   UNIX sockets, `ptrace`, and a writable canonical evidence store (escalated
   approval or a native Ubuntu fixture).
2. `pnpm run build` (or `pnpm run build:application-validation`) in the live
   MirrorECMA checkout, or have the origin command consume a built snapshot, so
   the source Gate campaigns do not depend on a stale gitignored `dist/`.
3. Resolve the identity-authority decision for `framework.reproduction`
   (export the project-layer identity/capture API, or accept the internal path),
   fix its three registry defects, then implement and review the R0-to-bundle
   materializer as designed in `tmp/m5-reproduction-adapter.md`; add a remote
   explore-session mode for `framework.reduction`.
4. Activate and re-observe the remote service at selected Apalache 0.61.0 /
   Java 25.0.4+7, supply the interop companion checkouts, and provide a
   delegated cgroup-v2 parent on native Ubuntu.
5. Re-freeze identities after any producer change, then re-run Q1 and the Q2
   verifier over the full required scope.
