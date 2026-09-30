# Q3 readiness report

Date: 2026-09-30 (closing-sweep pass, selection m3r5). This report is excluded
evidence output, so naming the selection here does not change the selection
digest. M5 is not qualified. The full local-candidate scope is not complete:
the remote/operator-gated tiers below are blocked, not skipped. Nothing was
committed, pushed, published, or deployed by this pass, and the remote
model-check service was not contacted, restarted, or reconfigured. No local
model checker ran.

## Selected identity

Catalog selection
`fed55175b792feaec86cf71bf7fae1bae680a0313797a5c982f3a6ecc746f025`
(`capturedAt` 2026-09-30T02:08:14Z; BYTE_STABLE: refresh runs 2 and 3 produced
identical digests). A live recomputation of every component ref, both
reference-node locks, all four distribution fixtures, the source snapshot, both
caches, and both installs matched this selection; there was no drift when the
installed runs below were executed.

| Component | Revision | Dirty content digest |
| --- | --- | --- |
| Mirrors | `e6772d594270759913f00a7ad945dcf508318660` | `b434d78eda6d1e763dbdcea8696c5ed23d09f8835c38736f58b30b1456d39680` (0 included, 10 excluded) |
| MirrorECMA | `4992b077dfe1faff914098f4926e3632ea883bb0` | `db0c7085c6e9ad24ef03d50a7b4ca1c8eb3e9b0a1c6cf2bd6d4f9f53aedbb206` (0 included, 1 excluded) |
| MirrorGate | `0fa8a311018db9cbfdf2bb516235c1ec09e1ddbd` | clean |

The excluded paths are the generated catalog files, locks, fixtures, and
`catalog/framework-capabilities.json` (`evidence-output`).
`.projectile-cache.eld` was moved out of all three checkouts for the whole
refresh/collection window and restored afterwards; every credited run below
records empty `includedPaths`, and the source snapshot contains none of these
files.

| Artifact | Value |
| --- | --- |
| Snapshot | `/tmp/mirrors-candidate-snapshot-m3r5` |
| Snapshot index SHA-256 | `83b8f66f030d4bd9b9e5d7eab90dda2df4bf5abf8b506838a3f9ba4b47257cdf` |
| Local canonical manifest | `2bf94a0e76787c25628dabc299d7a0b57eea67bb58b3f440d6ced1b4be86bd34` |
| Local manifest file SHA-256 | `1c446d9401077934b5254bb51dbac3d70b6be5843eb819e6db7d380af3d83d31` |
| Local cache-index file SHA-256 | `43c6c3a55545b0f4d680541e95cf013bb9cefd32f4c7be3d2a56bd40de999a6a` |
| Gate canonical manifest | `6e3afb236698adf1c03c8d0eb66c0a7cc33896f57dc64f1fd8e39f3427f67d15` |
| Gate manifest file SHA-256 | `5b4fc532447c55d61a32aa81cd51dfce19c615d0370092c07ee68c3692b3012d` |
| Gate cache-index file SHA-256 | `43047b274aa1c62ef4f94c0cc5dbc84e20d1961c5aad8b8eacfeedf8ee2ccddb` |
| Local install prefix (registered) | `/tmp/mirrors-candidate-install-local-final` → `2bf94a0e76787c25…` |
| Gate install prefix (registered) | `/tmp/mirrors-candidate-install-gate-final` → `6e3afb236698adf1…` |
| Evidence store (this pass) | `/tmp/m3r5/store` |
| Q2 scope file | `/tmp/m3r5/scope/qualification-scope.json` SHA-256 `e41d4fbcf2d538e916422f70a26b6083c2c999fe86ce2171a14b710c9d7d0c16` |

Both caches pass `tools/distribution/verify.py`, and both registered prefixes
were installed transactionally to these exact manifests with `state=committed`
after the previous contents were replaced. Earlier selections (`5dd41ae9…`,
`b090e999…`, `7cb9d4de…`, `391104b5…`, and older) remain diagnostic only.

## Evidence stores

This pass can write only inside the Mirrors checkout and `/tmp`; retained runs
live in `/tmp/m3r5/store` (17 finalized bundles). The canonical store at
`/home/nzsn/.local/state/mirrors/evidence/v1` was neither read nor modified by
this pass. Consumer captures, scope files, and probe outputs are under
`/tmp/m3r5/out`, `/tmp/m3r5/scope`, and `/tmp/m3r5-work`.

## Qualified installed runs (frozen selection)

| Command | Run | Result |
| --- | --- | --- |
| `framework.install-diagnostics` (D local) | `run-fed6ddbe-52d3-49c7-8416-86b5e5fc2cf3` | qualified, exit 0 |
| `framework.install-diagnostics-gate` (D gate) | `run-6461e670-98bf-40a6-8fa2-57eea34c0777` | qualified, exit 0 |
| `framework.replay-correct` | `run-7260967f-a654-44d9-9671-fc7f7f4bced2` | qualified, exit 0 |
| `framework.replay-faulty` (R0) | `run-1d413f47-c7cd-419a-80d6-36862ff684b9` | qualified, exit 1 (intended mismatch) |
| `framework.reproduction` (R1) | `run-e7b27e35-641e-4a6a-9c4e-d9b8d0b9e549` | qualified, exit 0, `reproduced`; bundle `a1a9f6c75b12442f…` |
| `framework.reduction-prefix` (SR-5a) | `run-dcc51362-9084-4c2d-9eeb-9329bacb8d01` | qualified, exit 0, `shortest_reproducing_prefix`, `minimalityComplete: true`, `stopReason: complete`, best 2/16, cleanup confirmed |
| `framework.mutation-local` | `run-234b1388-3452-493d-86c4-4be99143fa50` | qualified, exit 0 |
| `framework.mutation-gate` | `run-ecde3ef5-dc22-4ff0-90a3-af4e24a12b50` | qualified, exit 0 |
| `mirrorgate.application-campaign.work-queue` | `run-255332cc-7e33-48b3-94bb-b21cb2b4a4af` | qualified origin, exit 0 |
| `mirrorgate.application-campaign.persistent-transfer` | `run-12193603-16a1-431b-be7c-2b95a6454917` | qualified origin, exit 0 |
| `mirrorgate.application-campaign.lease-service` | `run-ea52ddc6-5251-4199-b97b-249fac897a41` | qualified origin, exit 0 |
| `mirrorgate.recovery` | `run-9a3ec017-bae5-4fd6-b62a-c4ce06bb82ce` | qualified, exit 0, `gate-recovery` confirmed |
| `mirrorecma.project-check` | `run-57046a64-1cb6-4561-8f65-84a3b0147b51` | qualified, exit 0 |
| `mirrorecma.test` | `run-de36cf50-e4a9-4dc4-829b-8e2a356beb11` | qualified, exit 0 |
| `mirrorgate.required` | `run-c4621237-8de6-4c87-a472-c5999d008278` | qualified, exit 0 |
| `mirrors.local-no-model` | `run-b2e1269a-ba33-4df1-99b5-3bc08775ab78` | qualified, exit 0 |
| `evidence.offline-verify` (scope check) | `run-eb7d16ac-065a-43bc-994b-e8ca186a869d` | qualified, exit 0, scope `verified`, 16/16 |

Recovery reclaimed the seeded filesystem resource `owned-work` from
`/tmp/m3r5/recovery-state` (`session-m3r5`); its receipt binds the fresh
work-queue campaign envelope (`run-255332cc-7e33-48b3-94bb-b21cb2b4a4af`,
private envelope SHA-256
`e42ae7b33ff9c66612afb765639e63c731b674d54b448f929582ab703994368f`) with
`original-behavior=passed`, `original-cleanup=confirmed`, no cgroup
observations, and receipt cleanup `gate-recovery` confirmed. Aggregate receipts bind the frozen selection and exact component
sets; the gate receipts record `gate-physical` cleanup confirmed.

SR-5a upgrade: the previous credited run (`run-4f97221c…`, selection
`5dd41ae9…`) reported `smallest_observed_reproducing_prefix`,
`minimalityComplete: false`, `stopReason: candidate_failure` because a 1-state
prefix normalized a `coverage_unmet` acceptance failure with
`normalization_context_missing`. MirrorECMA `4992b07` maps that case to "no
signature" on the prefix-probe path only; under m3r5 the same fixture yields
`shortest_reproducing_prefix` with `minimalityComplete: true` and every shorter
prefix validly tested (lengths 16→2 reproduced, length 1 `not_reproduced`).

## Local non-model gate

`mirrors.local-no-model` (exit 0) printed `ALL LOCAL NON-MODEL GATES GREEN`:
`lake build`, the fixture/codec/model-interface suites, distribution and
durable-evidence unit tests, manifest validation, scaffold/TLA suites, and the
two live-tier self-skips. The TLA differential offline step ran with the
locally verified Microsoft OpenJDK `25.0.4+7-LTS` on `PATH` (archive
`75894d10…`, `bin/java` `e7bc0bc0…`; see the pin reconciliation in
`tools/evidence/README.md` and
`Docs/qualification-harness-design.md`), so the JDK prerequisite recorded as an
environment limit in the 2026-09-25 report is closed for local tiers.

## Environment limits of this execution pass

- Approved escalations were available this pass: the D audits ran with
  `ptrace`/`bwrap` and loopback/UNIX sockets in the mirrored execution posture,
  and the refresh/build/install steps wrote the MirrorECMA checkout as needed.
- No local model checker was executed, and `lake test` was never used as a
  gate. The remote service was not contacted; its staged toolchain pins remain
  pending-operator-observation.
- The Mirrors editor cache reappeared in an earlier round and poisoned one
  collection pass (all affected runs were re-collected); this pass kept it out
  for the entire window and verified empty `includedPaths` on every credited
  run, so no credited envelope in this report is affected.

## Required tiers that remain incomplete

| Tier | Exact blocker |
| --- | --- |
| `framework.reduction` (domain tier, SR-5b) | Requires the operator to activate Apalache 0.61.0 / Java 25.0.4+7-LTS on `192.168.150.219:8999` and supply the same-time identity observation; remote oracle mode is implemented but unexercised against a live service. |
| `mirrors.remote-model-check` | Same operator activation and observation; no credentials are present and the service was not contacted. |
| `mirrors.interop` | Missing companion checkouts (`MirrorCPP`, `MirrorLean`, `ModelMirrors`/HS) and no remote-only mode; must not run local model checking here. |
| Delegated cgroup / native Ubuntu | `/sys/fs/cgroup` has no writable delegated parent on this WSL2 host; native-Ubuntu acceptance remains deferred by the 2026-09-29 operator decision. |
| Publication and deployment | Not performed; the parent owns commits/pushes. |

The local-candidate qualification profile still names these tiers, so the
profile as a whole is incomplete even though every locally executable tier is
credited.

## Q2 status

- The installed verifier (`qualification_scope.py` from the local runtime)
  returned `status: verified`, `verifiedRunCount: 16` for scope
  `local-candidate.sr4r5-20260930` (`run-eb7d16ac…`, exit 0), resolving both
  distribution bindings (`2bf94a0e…`/`43c6c3a5…` and `6e3afb23…`/`43047b27…`).
  This is the first scope that credits the reduction tier.
- The repository copy of the same verifier independently returned the same
  verdict before collection.
- `tools/evidence/verify.py --offline` over every finalized bundle in
  `/tmp/m3r5/store` returned `status: verified` for all 17, including the
  credited reduction receipt and both D bindings.
- The full local-candidate profile still lacks the remote/operator-gated tiers
  above; they are recorded blocked, not skipped.

## Milestone status

M3 remains **Partial**. The prefix-reduction half (R4 / SR-5a) is now fully
qualified on this selection: credited receipt with
`shortest_reproducing_prefix`, `minimalityComplete: true`, confirmed cleanup,
and a verified Q2 scope that includes it. The domain-reduction half (R5 /
SR-5b) still depends on the operator service activation. Because a milestone
exit condition requires both halves, no partial status here qualifies M3, and
M5 remains not qualified (interop, remote model check, and the deferred
cgroup/native tiers are still open).

## What would complete M5

1. Operator activates and re-observes the remote service (Apalache 0.61.0 /
   Java 25.0.4+7-LTS) with the same-time identity observation; then run
   `framework.reduction` (domain tier) and `mirrors.remote-model-check`.
2. Provide the interop companion checkouts and a reviewed remote-mode interop
   matrix; run `mirrors.interop` without local model checking.
3. Provision a delegated cgroup-v2 parent on a native Ubuntu host for the
   deferred aggregate-enforcement and native-acceptance tiers.
4. Re-freeze identities after any producer change, then re-run the affected
   tiers, Q1 execution, and the Q2 scope verifier over the complete profile.
