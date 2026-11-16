# rc.12 completion continuation — 2026-11-16

The user requested resuming and iterating through the remaining work. This
campaign prepares `0.2.0-rc.12` for the November 12 source fixes. Earlier rc.11
source, release, qualification and deployment records keep their original scope.

Fresh intake observes Ubuntu 26.04.1 WSL2, approximately 762 GiB free in the
repository filesystem, working explicit-config Windows SSH access, exact retained
MirrorECMA `9192171f…` and MirrorGate `cd4914b2…` checkouts, and the pinned tracer
and offline distribution inputs. The Windows service is Running/Auto with the
released rc.11 executable hash. Its server certificate expired November 13;
service state alone does not admit an mTLS model operation.

## Current exact-candidate outcome

The [final identity/qualification audit](result.json) accepts the complete selected
candidate at `6882d5b8b4787977e847e5a77467b30bfdac19a2` and C0 `b44fe3d9…`.
The full native Windows driver passes, including all seven Rust tests and Job
cleanup. All 10,448 native source files match their Git blobs. The three new
oracle/installer regressions also pass explicitly on Windows with no skips;
native DPM discovery contains 95 cases. [Native validation](windows-full-result.json),
[regressions](native-new-regressions.json), [repeatable Windows package](windows-package.json)
and [local archive-member verification](windows-package-local-verification.json)
retain the exact identities.

Fresh remote model validation, all 22 five-client mTLS rows, remote domain
reduction and [13 finite controlled C++ executions](controlled-model-result.json)
pass. The two distribution audits and fresh local/remote producers form the
complete 19-node graph. [Linked Q1](rc12-c0-final-q1-result.json) and
[installed-only Q2](independent-q2-result.json) accept all 20 sealed bundles with
six actual integrity/link/profile negative controls. [Offline Q2 after shutdown](offline-after-shutdown.json)
is identical. [Cleanup](fixture-cleanup.json) verifies the owned oracle and tunnel
are stopped; production remains unchanged.

This is exact-candidate qualification, with public publication, production trust
renewal/deployment, reboot and the measured compatibility lifecycle still pending.
The [operation card](operations.md) names the concrete source/tag/assets, current
production identities, expired trust chain and proposed renewal/rollback checks.

## Earlier local completion and retained boundaries

Clean task-owned source is `6882d5b8b4787977e847e5a77467b30bfdac19a2`, with a
local-only annotated `v0.2.0-rc.12` tag. Selected WSL2 C0 is
`b44fe3d94c0afab187642923f81eef4a387b579289a63231bf649bdb3325456d`;
the base C0 remains a structural control. The shared branch and index are unchanged.

| Work | Result and retained evidence |
| --- | --- |
| Local source | [Full maintained gate](rc12-gate-result-final.json) passes, including C++ integer-map/controlled preparation and all declared non-model suites. The first version-expectation failure is retained separately. |
| Source/C0 freeze | [Freeze](rc12-freeze-manifest.json), [independent regeneration and six negative controls](rc12-freeze-review.json); both catalog refreshes are byte-stable. |
| Linux package | [Release/archive checks and source-hidden, network-isolated smoke](linux-package.json) pass. Archive SHA-256 is `dab25c57260c79228bb539609b09039bfca74c6aacf5f968754a72a3a4353cd1`. This is Ubuntu 26.04.1 WSL2 acceptance, without an Ubuntu 24.04 ABI claim. |
| Installed distribution | Both caches/installs are built from the selected snapshots; [both registered audits](rc12-registered-installed-audits.json) pass and verify offline. |
| Source producers | Fresh Mirrors, MirrorECMA typecheck/test and MirrorGate required gates pass and are sealed at the new C0. |
| Installed application producers | Correct/faulty replay, local/Gate mutation campaigns, linked reproductions, prefix reduction and prepared interruption/recovery pass. Expected mismatch/abrupt-origin exit codes remain distinct from infrastructure errors. |
| DPM | [All three installed profiles](installed-dpm-result.json) pass with fresh C++/Node/Rust consumers, source hidden and networking isolated; `freshModelCheck:false`. |
| Independent installed consumption | [Sixteen sealed bundles and their local dependency graph](local-installed-verification.json) verify with installed tools, read-only inputs and source/network isolation. Four actual tamper/link controls reject; [four historical stale-audit controls](stale-audit-negative-controls.json) also reject. This is an explicitly incomplete M5 subgraph, without complete M5/Q1/Q2 acceptance. |
| Current fixture admission | [Host probes](host-admission.json) and [new fixture certificates](fixture-pki.json) pass. Private keys remain on their generating hosts. Production credentials are unchanged. |

Fresh raw artifacts are under `.golden-build/completion-rc12-20261116/`.
All 240 pre-existing unrelated files are inventoried and preserved. The clean
candidate and its frozen source remain unchanged; this README and maintained
status/checkpoint follow-up are later documentation, outside that tested commit.

## Remaining work and concrete continuation

The initial automatic rejection of source transfer is historical. The user's
subsequent explicit approval is recorded in [the approval receipt](native-transfer-approved.json);
the exact approved bundle was transferred and tested. Remote fixture checks
subsequently passed review after the [payload admission](remote-payload-admission.json)
established their fixed synthetic-fixture scope and already-transferred model
bytes. No private application workload or credential bytes were exported.

The supplemental native regression stdin transport timed out before starting a
runner; process observation found no owned process or runner file. A file-based
retry under the tested native Job wrapper passes. The first cleanup SSH connection
also closed before returning a result; the guarded retry succeeds. Both original
attempts are retained without changing acceptance or downgrading a required gate.

Public branch/tag/prerelease publication and the Windows asset are prepared but
not performed. Production CA, server and default client certificates all expired
November 13. [Read-only prerequisites](production-renewal-prerequisites.json)
confirm the existing CA signing key is present without reading/exporting it.
Production trust renewal, client coordination, deployment and a separately approved
host-reboot window remain required; a leaf-only renewal cannot repair that chain.
No rc.12 remote branch/tag, hosted release, production credential/configuration/
binary replacement or reboot operation occurred.

The two actual shipped compatibility cycles, real-workload soak ledger,
consumer acknowledgements and tested fallback remain measured external gates.
Their entry point and owners have been requested. Retirement is a separate
decision after those gates; native-runner/M4 planning remains withdrawn.
The [lifecycle readiness record](lifecycle-readiness.json) names the missing
inputs and grants zero complete-cycle credit.
