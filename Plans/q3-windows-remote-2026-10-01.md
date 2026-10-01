# Windows remote work readiness

Date: 2026-10-01
Profile: `m5-wsl-windows-remote/v1` (registry profile ID `m5-wsl-windows-remote`)
Status: requested remote operations passed; full M5 qualification remains incomplete.

The user removes native Ubuntu host acceptance and real aggregate-cgroup
acceptance from M5. WSL-supported installed, isolation/recovery and evidence
requirements remain. The oracle is the current native Windows host at
`172.20.208.1:8999`, pinned mTLS, Apalache 0.62.2 and Microsoft Java
25.0.4+7-LTS. All Windows artifacts and execution remain under
`C:\Users\ayden\Desktop\Workspace\MirrorsRemote`. This is an owned native
console deployment, with observed process lifetime/listener and exact binary,
source, leaf and runtime identities; it establishes no AUTO_START service claim.

## Exact candidate and retained results

Selection: `3fbab48a8e94be8f72c53ea0f3cc07df97b2c04facf8e169b83d29838861c53c`.
The two consecutive identity refreshes matched byte-for-byte. Both caches use
`/tmp/m5-windows-corrected-snapshot` and exact prepared dependency bytes.
The installed prefixes are `/tmp/mirrors-candidate-install-local-final` and
`/tmp/mirrors-candidate-install-gate-final`, both committed.

| Observation | Result and final run |
| --- | --- |
| Local D audit | Qualified `run-d3cfb744-5e95-4507-bbce-84e5ae7be430`; manifest `9918bd3284ef8c3aa907dc7c344b7707bace735643f1aeda198c23f4acb317f6` |
| Gate D audit | Qualified `run-1afaf007-9e84-46fc-93b2-c6dddf841a59`; manifest `01137a9c63258cfb244c49411fc8a29bebb56f06c9a9d432e5e998c183404da3` |
| Remote bounded model check | Qualified `run-af4c9237-c1ac-4886-b8c2-6c8b2e88dd0b`; HourClock `Init`/`Next`/`Inv`, bound 3, `VALID` |
| Remote client interop | Qualified `run-4f0f263b-f8d6-4b9e-9505-50bccebecffc`; 22/22 declared mTLS cases |
| LeaseService origin | Qualified `run-6cbd132d-d9fa-4b82-a0f7-7ead8a807133`; correct baseline and actual expired-token `write` mismatch at state 5, cleanup confirmed |
| Installed domain materializer | Individually qualified `run-c938aa2f-d677-4554-897f-6b8854a3d84e`; input `Client: 2 -> 1` at state 2, remote `model_valid`, `explore_done` confirmed |
| Installed reduced-trace replay | Correct baseline passed and original `write` mismatch at state 5 preserved; exact mismatch signatures equal, cleanup confirmed; three framework repositories hidden and network unshared |
| Mirrors source gate | Qualified `run-815a5a3c-9a2d-42ef-ae91-43702c26a597`; all local non-model gates green, 123 evidence tests included |
| MirrorECMA source gates | Check `run-a5f3dcf5-e277-42ac-bfb1-ec37df7c0c89` and tests `run-dc72b3bb-ce05-43de-b92c-7faa636a4858` qualified; 626 passed, 13 skipped |
| MirrorGate source gate | Qualified `run-603f94cb-b22f-4b24-9fcc-d08ee9b2703a`; supported real WSL backend/control/lifecycle/conformance checks passed with pinned Node; aggregate enforcement not requested |
| Independent archived verification | 10/10 individual bundles verified using installed schemas/registry and installed pinned wheels, with source repositories and original producer scratch hidden and network unshared; deleted required artifact and changed byte both rejected |
| Supporting scope | Nine nodes verified against both exact D bindings. This supporting scope excludes R5 credit and does not satisfy the complete M5 profile. |

The remote interop profile `remote-five-client-mtls/v1` exercises valid/invalid
bounded verdicts and wrong-pin rejection in ECMA, C++, Rust, Lean and Haskell
(15 cases), plus seven ECMA cases: register/replay, deliberate mismatch,
register_traces with an actual Windows fixture, inline register_trace_gen,
register_explore, register_explore_session with done, and inline two-module
sources. The legacy all-transport/local-backend matrix remains separate.
No local Apalache or TLC ran.

The protected LeaseService witness remains the original recorded corpus. Its
model validity was checked freshly against Windows 0.62.2; it is not relabelled
as a newly generated 0.62.2 corpus. The candidate validator is a separately
provided, exact hash-pinned standalone executable; it is not claimed to be a
shipped I4 artifact.

## Corrections and diagnostics

Actual execution exposed two contract bugs. MirrorECMA's remote materializer
compared an unresolved digest Promise with its later resolved value; it now
awaits the digest before comparison. The evidence adapter required an unused
local mirror field that the remote tools/v2 producer explicitly forbids; it now
validates the same five-field closed contract and rejects unexpected mirror,
Apalache and Java fields. Regression checks and real installed reruns passed.

D verification initially wrote Python bytecode into the admitted runtime tree.
Those incidental files were retained outside the tree; reruns used
`PYTHONDONTWRITEBYTECODE=1`, with the original integrity checks retained.
Earlier failed/incomplete runs remain private uncredited diagnostics. No
historical envelope, approval or readiness report was rewritten.

## Remaining M5 qualification

The Windows service/credentials/tool activation blockers are resolved for the
exercised remote profile. Full M5 still requires the complete graph for this
exact candidate. In particular, a credited domain-reduction node must depend
on exactly one finalized R1 carrying the same LeaseService reproduction bundle.
The current fixed `framework.reproduction` invocation names the WorkQueue
reference project; its earlier R1 cannot be substituted for the LeaseService
bundle. Add the corresponding LeaseService producer/registration and retain
its actual R1 result, then link R5 without weakening the scope rule.

Recollect current-candidate correct/faulty project replay, reproduction, prefix
reduction, local/Gate mutation aggregates and interruption/recovery origins and
receipts. Freeze again if those producer changes affect source identity, run
both D audits first, and independently verify the complete installed Q scope
and catalog qualification profile. Historical prefix/reproduction/mutation/
recovery results remain evidence for their own selections.

Public summaries and diagnostic projections are in
[the retained evidence directory](m5-windows-remote-evidence-20261001/README.md).
Authoritative private bundles, original inputs/receipts/observations, the
supporting scope, verifier output and diagnostics are owner-only in
`~/.local/state/mirrors/m5-windows-remote-20261001`. No credential bytes are
archived or published. Changes remain uncommitted.
