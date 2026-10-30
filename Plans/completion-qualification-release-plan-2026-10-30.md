# Completion and release execution plan

Date: 2026-10-30

Status: detailed plan for all remaining stages. Only the design/plan documents
are being added by this planning task. No acceptance gate, commit, push, tag,
publication, deployment, or reboot is authorized by this file.

Read the normative [completion and release design](../Docs/completion-qualification-release-design.md)
with this plan. Existing completed results and their limits are in the
[October 29 evidence](completion-evidence-20261029/README.md).

## 1. Delivery rules

- Execute from exact admitted identities. Do not transfer acceptance from a
  dated, dirty, different-host, or different-artifact record.
- Keep failed attempts and later passes separate. Required skips and external
  blockers remain visible in the final claim matrix.
- Do not edit October 29 receipts after their final freeze. Put new runs in a
  new dated `Plans/completion-release-evidence-YYYYMMDD/` directory with its
  own inventory and verifier; retain private bulky evidence in the admitted
  owner-only evidence store.
- Do not reset or clean the current shared checkout. Use a separate clean
  checkout for tagged release construction.
- Branch push, local release-tag creation, tag push/release publication,
  production replacement, and reboot are separate explicit approvals.
- The current WSL2 coordinator runs only the repository-owned no-model gate.
  Live model operations use the selected owned remote Mirrors service.

## 2. Roles and external inputs

Roles below are execution responsibilities, not new agent assignments. One
operator may hold several roles, but independent Q2 must remain independent of
the producer execution.

| Role | Responsibility |
| --- | --- |
| Coordinator | Source/evidence freeze, local checks, delivery audit, records |
| Release operator | Clean tag checkout, Linux/Windows package set, release handoff |
| Native operator | Native Linux host, cgroup-v2 delegation, M4 execution |
| Platform operator | Matching Ubuntu 24.04 environment, distribution and M5 producers |
| Windows operator | Full Windows gates, isolated oracle, service lifecycle and reboot |
| Independent verifier | Inventory, Q1/Q2 independence, negative controls, final handoff |

| Required input | Current state | Unblocks |
| --- | --- | --- |
| Reviewed final source payload | Working tree above `7e9a27d` | S1/S2 |
| Exact candidate tag name and local tag approval | `v0.2.0-rc.1` prepared in source, not approved as a tag | S3 |
| Native Linux runner and serving-UID cgroup-v2 parent | Not supplied; WSL2 preflight only | S4 |
| Matching declared Ubuntu 24.04 qualification environment | Coordinator is Ubuntu 26.04.1 | S5-A/S5-B |
| Windows host with current source/runtime and service access | Prior records exist; fresh observation required | S5-B/S7 |
| Owned remote oracle and current mTLS credentials | Must be reobserved; no historical health claim | S5/S7 |
| Branch/tag/publication/deployment/reboot approvals | Not granted by this plan | S2/S3/S7 |

## 3. Dependency schedule

```text
S0 -> S1 -> S2 -> S3 -> S5 -> S6 -> S7 -> S8
             |                  ^
             +-> S4 ------------+

S8 compatibility work spans this release and one later qualifying release.
S4 and S5 can run concurrently once their independent inputs are admitted.
S4 uses the selected Gate source and does not consume the S3 Mirrors packages.
```

An explicitly scoped prerelease may reach S6 with S4 or another non-selected
tier absent, but the handoff must name that absence. It cannot claim the
missing capability or full-framework qualification.

## 4. Stage S0: baseline intake

| ID | State | Task and concrete output | Exit criterion |
| --- | --- | --- | --- |
| S0.1 | Ready | Inventory `git status`, full diff, untracked evidence, ignored logs, companion revisions, and unrelated files. Write a baseline path inventory. | Every changed path is classified as candidate payload, evidence, generated output, credential, or unrelated/preserved |
| S0.2 | Ready | Index October 29 accepted results, failed attempts, skips, and limits. Map F5, profile 6, DPM, matrix, Windows, and Gate receipts to their exact identities. | No completed result is listed as an unconditional remaining implementation task |
| S0.3 | Ready | Record actual coordinator OS/kernel/filesystem, available tools, and absent Ubuntu 24.04/native M4 prerequisites. | Host facts and target declarations are separate |
| S0.4 | Ready | Create the new stage ledger using the claim states in the design. Link this plan, prior evidence, and external input requests. | Every S1-S8 task has a state and owner role |

## 5. Stage S1: source and evidence freeze

| ID | State | Task and concrete output | Exit criterion |
| --- | --- | --- | --- |
| S1.1 | Ready | Review behavioral source and contracts, including controlled comparison, TLS timeout handling, installer observations, release version, and compatibility docs. Record reviewed path list. | Complete diff reviewed; no unrelated reset/cleanup |
| S1.2 | Ready | Run `git diff --check`, Markdown/link checks for the new docs, and focused tests for any file changed after its last recorded gate. Retain commands and exits. | No whitespace, navigation, or focused regression failure remains |
| S1.3 | Ready | Regenerate the final October 29 inventory if its payload changed, then run `python3 Plans/completion-evidence-20261029/verify.py`. | Verifier exits zero and reports the intended bounded counts |
| S1.4 | Ready | Verify ignored evidence tracking explicitly; run secret/credential and binary/archive scans over the proposed delivery list. | No private key, credential, binary, tool archive, or unreviewed ignored file is included |
| S1.5 | Ready | Run the final required local gates: `bash tools/run-local-no-model-check.sh` and, for native dependency changes, `bash tools/check-native-rebuild.sh`, using admitted socket/ext4 prerequisites. | `ALL LOCAL NON-MODEL GATES GREEN`; native gate passes where required; live tiers remain reported separately |
| S1.6 | Ready | Freeze source/companion/tool hashes and the validation snapshot. Write `candidate-freeze.json` and a human-readable freeze summary. | All local required checks pass and every external obligation is marked pending or blocked |
| S1.7 | Gate | Present the exact branch-delivery payload and exclusions for approval. | User approves or rejects the concrete S2 operation |

## 6. Stage S2: audited branch publication

| ID | State | Task and concrete output | Exit criterion |
| --- | --- | --- | --- |
| S2.1 | Approval-gated | Stage only the approved paths, including explicitly selected ignored evidence. Compare staged blob hashes with the freeze manifest. | Staged bytes equal reviewed bytes; unrelated paths remain unstaged |
| S2.2 | Approval-gated | Repeat credential/binary scans on the staged payload and inspect `git diff --cached --check`. | No forbidden content or whitespace error |
| S2.3 | Approval-gated | Commit with a scoped subject and push `main`. | Local commit is the audited tree; push reports success |
| S2.4 | Approval-gated | Fetch/reobserve `origin/main`, verify full remote SHA and zero divergence for the published branch, and write `source-delivery-audit.json`. | Remote ref exactly matches the reviewed commit; no tag or release created |

## 7. Stage S3: clean tagged packages

| ID | State | Task and concrete output | Exit criterion |
| --- | --- | --- | --- |
| S3.1 | Approval-gated | Confirm `v0.2.0-rc.1` matches `Shell/Version.lean` and approve local-only tag creation at S2. Any version change returns to S1. | Exact tag name/commit approved; no remote tag mutation |
| S3.2 | Ready after S3.1 | Create a separate clean checkout and local tag. Require clean status and `refs/tags/v0.2.0-rc.1^{commit}` equal to S2. | Release builder identity preconditions hold |
| S3.3 | Ready after S3.2 | Run `python3 -m unittest discover -s tools/release -p 'test_*.py' -v`. | All release identity/package/refusal tests pass |
| S3.4 | Ready after S3.2 | On Linux x86-64 run `python3 tools/release/release.py build --source CLEAN_SOURCE --tag v0.2.0-rc.1 --output EMPTY_DIST`. | Build and focused non-model gates pass; source identity is stable before/after |
| S3.5 | Ready after S3.4 | Verify `SHA256SUMS`, `BUILD.json`, external manifest, executable versions, `ldd`, archive paths/types, and absence of source/credentials. | Archive and both manifests bind the same tag, commit, binaries, and prerequisites |
| S3.6 | Ready after S3.4 | In Ubuntu 24.04 without Lean/source, run `release.py check-archive --tag v0.2.0-rc.1 --archive LINUX_ARCHIVE` after checksum verification. | Isolated runtime smoke passes; observed host is actually Ubuntu 24.04 |
| S3.7 | Ready after S2 | Compare Windows base-plus-overlay inputs with S2. Reuse the staged ZIP only for an audited non-behavioral difference and identical build inputs; otherwise rebuild and rerun affected suites. | Windows archive and binary/DLL hashes are explicitly bound or rejected |
| S3.8 | Ready after S3.7 | Recheck Windows packaging repeatability, version, archive membership, DLL closure, and no-credential rules. | Windows ZIP receipt remains limited to packaging and its actual gates |
| S3.9 | Gate | Emit `package-set.json` with every artifact hash, source/build identity, runtime prerequisite, test scope, and retention location. | Complete reviewable Linux/Windows artifact set; no publication or deployment |

## 8. Stage S4: native M4 acceptance

| ID | State | Task and concrete output | Exit criterion |
| --- | --- | --- | --- |
| S4.1 | Blocked externally | Obtain native Linux runner, operator-owned serving-UID cgroup-v2 parent, durable state root, Bubblewrap, loopback, and ptrace admission. | Host/delegation inputs are explicit and operator approved |
| S4.2 | Blocked externally | Freeze Gate commit, journal-v2 schema, backend/recovery source hashes, host, and delegation. Run read-only `preflight_m4.py --gate-root GATE --cgroup-parent PARENT`. | Native host and delegation validate; preflight still claims no enforcement |
| S4.3 | Blocked externally | Create one owned child and run cpu/memory/pids quota writes/readbacks with independent counters. | Kernel observations equal selected limits; owned child cleanup confirmed |
| S4.4 | Blocked externally | Run real descendant enforcement, escape refusal, missing-controller, and resource-pressure controls. | Limits apply to the whole owned tree; escapes and unavailable controls fail closed |
| S4.5 | Blocked externally | Launch a journaled worker tree and retain exact boot/UID/session/PID/start-time/cgroup device/inode/delegation linkage. | Every process claim binds the exact group resource; no PID/path inference |
| S4.6 | Blocked externally | Kill only the owned controller; recover through a new administrative incarnation. | Exact subtree becomes observed-empty before owned filesystem cleanup and claim removal |
| S4.7 | Blocked externally | Exercise wrong identities, PID reuse, inode replacement, stale/torn records, concurrent recovery, unavailable delegation, nonempty retries, and durable retry evidence. | Ambiguity refuses action; retries remain recoverable; no ownership broadening |
| S4.8 | Blocked externally | Verify unrelated process/file sentinels and final resource/process cleanup; retain before/run/recovery linkage. | Sentinels unchanged; no owned test descendants remain |
| S4.9 | Gate | Independent verifier reviews native receipts and emits `m4-native-acceptance.json`. | All selected native rows pass at one identity, or M4 remains explicitly unqualified |

## 9. Stage S5: exact-candidate qualification

### S5-A. Environment and distribution admission

| ID | State | Task and concrete output | Exit criterion |
| --- | --- | --- | --- |
| S5.1 | Blocked externally | Select the declared Ubuntu 24.04 host/profile and record actual OS, kernel/virtualization, filesystem, libc, runtimes, and permissions. | Environment matches the complete declared profile; no Ubuntu 26.04 substitution |
| S5.2 | Ready after S3/S5.1 | Freeze Mirrors/companion SHAs, C0 catalog, distribution locks, package/cache hashes, and model/corpus identities. | One immutable selection is used by every producer |
| S5.3 | Ready after S5.2 | Materialize owner-only installations from admitted caches; hide source and disable network/PATH fallbacks. | Installed runtime contains only declared artifacts and actual host/package observations |
| S5.4 | Ready after S5.3 | Run both required D installation/distribution audits before dependent producers. | Both manifests/cache indexes verify and exact active versions are committed |
| S5.5 | Ready before remote runs | Observe owned remote endpoint, server process/binary, Apalache archive/JAR, Java, certificate validity/pin, and fixture files. Generate credentials independently per host. | Fresh observation satisfies all selected pins; no remote private key export |

### S5-B. Required producers

| ID | State | Task and concrete output | Exit criterion |
| --- | --- | --- | --- |
| S5.6 | Ready after admission | Run source and companion required gates at the frozen selection, including Mirrors no-model, MirrorECMA check/test, and MirrorGate required. | Every registered source command finalizes with the required result |
| S5.7 | Ready after D | Run installed correct/faulty replay, both R1 reproduction branches, and exact origin/bundle linkage. | Correct replay passes; faulty replay produces the declared mismatch; R1 binds exact R0 bytes |
| S5.8 | Ready after R1 | Run LeaseService domain reduction and WorkQueue prefix reduction, including correct/faulty reduced replay and minimality scope. | Reduction receipts bind the exact original R0/R1 inputs and preserve failure signatures |
| S5.9 | Ready after D | Run the complete local/Gate mutation aggregates and prepared-filesystem recovery origin/receipt path. | All declared cases pass; recovery gets only its supported filesystem claim |
| S5.10 | Ready after S5.5 | Run the remote model-check producer and all 22 selected five-client verdict/pin/protocol rows through the Mirrors CLI. | Required VALID/INVALID/wrong-pin/protocol results and before/after identities pass |
| S5.11 | Ready after S3 | Renew source-hidden/network-isolated installed C++/ECMA/Rust DPM acceptance for the exact candidate. | All three profiles pass and retain `freshModelCheck:false` |
| S5.12 | Windows input required | On a separately admitted Windows live-check host, run full native `lake test`, native integer-map, compiler/model-interface, runtime, and TLS long-poll gates at the exact candidate. Any live backend skip remains explicit and prevents a full-suite claim. | No required Windows tier is replaced by the earlier eight-suite pass |
| S5.13 | After every owned run | Confirm job/server/backend cleanup and reobserve source/runtime/fixture stability. | All owned processes are gone except intentionally retained production; no input drift |
| S5.14 | Gate | Reconcile actual completed command/tier membership against `tools/evidence/commands.json` and the selected 18-command/16-tier profile. | No missing, duplicate, optionalized, or substituted required command |

### S5-C. Linked and independent verification

| ID | State | Task and concrete output | Exit criterion |
| --- | --- | --- | --- |
| S5.15 | Ready after producers | Finalize all private bundles/public projections and construct the C0 -> D -> R0 -> R1 -> Q DAG. | All references are finalized, acyclic, unique, and bound to one catalog selection |
| S5.16 | Ready after S5.15 | Run linked installed Q1 across the complete scope. | Q1 accepts every required node and both exact D bindings |
| S5.17 | Independent | Run Q2 from the installed verifier/schema/registry with source/producer scratch hidden, network unshared, and inputs read-only. | Independent Q2 accepts the complete selected scope |
| S5.18 | Independent | Execute missing artifact, changed byte, wrong D, wrong R0/R1, wrong R1/R5, and incomplete-profile controls. | Every negative control is actually rejected and retained |
| S5.19 | Independent | Stop the owned oracle and repeat offline verification from retained verifier/runtime bytes. | Acceptance is byte-identical and needs no live service or source checkout |
| S5.20 | Gate | Emit `framework-qualification.json`, public run references, retention index, and a limitation summary. | One frozen candidate earns only the exact platform/framework scope proven |

## 10. Stage S6: release admission and handoff

| ID | State | Task and concrete output | Exit criterion |
| --- | --- | --- | --- |
| S6.1 | Ready after S3-S5 | Assemble source, package, M4, M5/D/Q, Windows, compatibility, and cleanup results into a claim matrix. | Every claim links evidence and every absent tier is visible |
| S6.2 | Decision | Select full-scope or explicitly scoped prerelease admission. Record any M4/F5/platform exclusion in the release scope. | No missing capability is silently credited |
| S6.3 | Ready after S6.2 | Draft release notes for F5 capability, runtime fixes, compatibility retention, installation prerequisites, evidence scope, and known limits. | Notes agree with machine-readable receipts and artifact contents |
| S6.4 | Ready after S6.2 | Prepare production inventory template, candidate-port checks, hash-guarded replacement, automatic rollback, and post-deployment controls. | Concrete operation names host, paths, old/new hashes, preserved configuration, and rollback triggers |
| S6.5 | Independent | Verify handoff inventory, public/private classification, checksums, and required negative controls. | Independent handoff review passes; no private material included |
| S6.6 | Gate | Present separate approval requests for tag/release publication, optional Windows asset publication, production replacement, and reboot. | User can approve a concrete immutable operation; no mutation has occurred |

## 11. Stage S7: publication, deployment, and reboot

| ID | State | Task and concrete output | Exit criterion |
| --- | --- | --- | --- |
| S7.1 | Approval-gated | Reobserve remote source/tag/release state; refuse existing or moved tags and existing drafts/releases. | Target is unused and source remote identity matches S6 |
| S7.2 | Approval-gated | Push the selected tag with approval that explicitly includes automated GitHub release publication. | Remote tag remains at the approved commit |
| S7.3 | Publication workflow | Observe tooling, build, isolated archive check, draft asset creation, and publication jobs. Do not rerun blindly over a partial draft. | Workflow succeeds or the exact failed/draft state is retained for review |
| S7.4 | After publication | Verify peeled tag commit, asset names/hashes/checksums, release notes, prerelease and Latest flags. | Published assets equal S6; prerelease is not Latest |
| S7.5 | Optional approval-gated | Publish the reviewed Windows ZIP separately if selected. | Windows asset hash equals S6; no existing asset overwritten |
| S7.6 | Before deployment | Reobserve production service, paths, configuration, executable/DLL/runtime hashes, listener, and credential metadata. Retain rollback copy. | Current old identity and rollback bytes are known; no historical health assumption |
| S7.7 | Before replacement | Run candidate on an isolated port and execute sync/async valid/invalid mTLS plus selected protocol/client checks. | All candidate controls pass and owned candidate processes clean up |
| S7.8 | Approval-gated | Hash-guard stop/replace/start production while preserving configuration and automatic rollback. | Installed bytes equal S6 or previous bytes are restored automatically |
| S7.9 | After replacement | Run production four-way mTLS controls, backend/version/hash/configuration checks, and unexpected-process inspection. | All controls pass; negative cases remain rejected; production identity is stable |
| S7.10 | On any deployment failure | Restore previous bytes/configuration and rerun the same live controls. | Old service health is independently reestablished; failed deployment remains failed |
| S7.11 | Separate approval-gated | Reboot the selected host and recheck AUTO_START, hashes, listener, backend, TLS identity, and four-way controls. | Reboot persistence passes at the deployed identity |
| S7.12 | Gate | Finalize `deployment.json` and lifecycle receipts with explicit publication/deployment/reboot scopes. | Only successfully observed operations are marked complete |

## 12. Stage S8: retention and compatibility lifecycle

| ID | State | Task and concrete output | Exit criterion |
| --- | --- | --- | --- |
| S8.1 | After S7 | Finalize private/public evidence indexes, permissions, artifact retention, rollback retention, and post-deployment observation. | Independent retention verification passes without credentials |
| S8.2 | Current and next release | Retain stdio `register_error`, Haskell oracle, golden bytes, and supported client behavior. | No compatibility removal in this candidate |
| S8.3 | Two shipped cycles | Run independent full declared compatibility matrices for both implementations, including Rust and async error-tag rows. | Two consecutive shipped cycles are green with no required skips |
| S8.4 | Two shipped cycles | Record real-workload soak hashes, counts, byte comparisons, differences, failures, incidents, and resolutions. | Dated execution ledger is complete; calendar time alone earns no credit |
| S8.5 | After S8.3/S8.4 | Confirm zero unresolved divergence, consumer migration acknowledgements, and tested fallback/rollback. | Retirement prerequisites are either all met or retirement remains unapproved |
| S8.6 | Separate future decision | If admitted, prepare deprecation notice, migration guide, compatibility release, fresh goldens/matrix, and historical oracle retention. | Removal occurs only in that separately approved release |

## 13. Traceability to the October 29 work packages

| Earlier package | Disposition in this plan |
| --- | --- |
| W0 reconciliation | S0 and S1; historical receipts remain unchanged |
| W1 finite F5 comparison | Completed scoped input; S5 repeats only required exact-candidate integration or invalidated controls |
| W2 profile-6 T/U | Completed scoped input; rerun under the design's source/toolchain invalidation rules |
| W3 exact-candidate acceptance | S1-S5, including packages, full Windows, M5/D/Q, and independent verification |
| W4 native M4 | S4; externally blocked until native host/delegation arrives |
| W5 compatibility | Decision retained in S0; measured lifecycle in S8 |
| W6 release candidate | S3 and S6-S8; no public/production operation without concrete approval |

## 14. Final completion definition

The campaign is complete only when:

1. the selected source commit and all artifact bytes are immutable and audited;
2. every selected required stage is `passed`, or the release is explicitly
   scoped and names each absent tier;
3. exact-candidate Q1/Q2 and all negative controls pass for the claimed
   framework profile;
4. native M4 is either actually accepted under S4 or explicitly outside the
   approved release scope;
5. published refs/assets match the handoff, if publication was selected;
6. deployed bytes and live controls match the handoff, if deployment was
   selected;
7. reboot acceptance is separately evidenced or remains unclaimed;
8. retention, rollback, cleanup, and compatibility obligations are recorded.

No single local aggregate, green matrix, branch push, release workflow, service
status, or elapsed interval satisfies this completion definition by itself.

