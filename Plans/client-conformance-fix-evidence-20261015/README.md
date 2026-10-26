# Client conformance repairs — accepted in the declared WSL scope

Date: 2026-10-15. The approved [remediation plan](../completed/client-conformance-fix-plan-2026-10-15.md) is implemented. All seven original defects, both contract decisions and the planned compatibility follow-ups have scoped remote acceptance. The TLS dependency probe also established a Haskell SAN defect; its separately reviewed H2 repair passed before acceptance.

The fixes are applied to the actual working trees of Mirrors, MirrorLean, MirrorECMA, MirrorCPP, MirrorGate and ModelMirros. MirrorRust is unchanged and passed fresh transport controls. No product commit, push or deployment was performed. The original plan and audit retain their historical status text; this record supplies the implementation result.

[Acceptance data](acceptance.json) · [342-cell assessment](conformance-matrix.json) · [source verification](final-source-verification.json) · [remote results](remote/README.md) · [complete dossier manifest](evidence-manifest.json)

## Repairs and evidence

Each accepted task includes a normal path, the original failure and an integration edge. Runtime acceptance uses the corrected source hashes, rather than the unchanged base commit identities alone.

| Finding / task | Proven cause and smallest change | Normal, failure and integration evidence |
| --- | --- | --- |
| F1 / L1 — Lean TLS identity | An empty override skipped SAN configuration. Reject the empty effective identity before credentials/network and retain a defensive native guard. | Valid SAN/mTLS succeeds; empty identity is refused through public and raw entry points with zero accepts; CN-only, wrong-name and pin controls retain rejection. [Original probe rerun](remote/main/lean-original-postfix.json), [native suite](remote/main/logs/lean2-native-test.log). |
| F2 / L2 — Lean source closure | Comment stripping interpreted markers within strings. Add string/escape state while preserving nested comments, separators and original source bytes. | Normal closure and quoted-marker original case include dependencies; quoted fake dependencies are ignored; shared/cyclic, missing-dependency and final encoded-limit controls pass. [125-test suite](remote/main/logs/lean2-test.log), [original probe rerun](remote/main/lean-original-postfix.json). |
| F3 / E1 — ECMA compiled admission | One callback overload bypassed target/computer pairing admission. Share one pure predicate before transport, registry or construction. | Exact supported sync/async-v1/v2 pairs pass; the original invalid pair has zero factories/sends; report/spawn and descriptor paths pass. [170 focused tests](remote/main/logs/ecma-focused-tests.log), [original probe rerun](remote/main/postfix-ecma-cli.json). |
| F4 / C1 — optional C++ Gate facade | Adapter normalization discarded trusted failure provenance. Capture typed origin/code/stage/operation at the SDK boundary and retain primary and cleanup evidence separately. | Actual SDK/Node workers, rebuilt consumers and 37 actual facade cases pass. Wrong digest acquires no worker; real Mirrors mismatch stays ordinary; spoofed worker codes remain application failures; all 19 attached sibling sessions survive. [Exact matrix](remote/cpp-gate/matrix-final-summary.json), [raw rows](remote/cpp-gate/cpp-failure-matrix-attempt4.jsonl). |
| F5 / M1 — CLI framing | TCP/TLS promoted buffered EOF fragments to complete frames; stdio had the same LF boundary obligation. Reject unterminated payloads and distinguish read errors from clean EOF. | Normal LF/CRLF and exact byte bounds pass; missing LF, reset/read errors, malformed UTF-8 and oversized input fail; actual TCP, authenticated TLS and stdio child paths pass. [Final immutable-producer gate](remote/main/logs/framing-final-producer.log), [original failure rerun](remote/main/frozen-cli-checks.json). |
| F6 / M2 — trace cancellation | Generic failure cleanup emitted cancellation after terminal errors. Only the private local poll-budget outcome permits best-effort cancellation. | Successful capture and budget cancellation pass; terminal protocol/transport/correlation failures emit no further messages; failed cancellation retains the primary outcome. [Focused spec](remote/main/logs/mirrors2-trace_capture_spec.log), [actual CLI controls](remote/main/frozen-cli-checks.json). |
| F7 / H1 — Haskell byte bounds | Core final encoding and actual transport accumulators lacked the common 65,535-byte cap. Check final sends and bound raw stdio/TCP/TLS framing before JSON decode. | The actual old Core emitted 65,536 bytes; fixed Core makes zero writes and retains ordinary 8-byte output. Exact/multibyte limits, coalesced frames, real peers and owner cleanup pass. [H1 results](remote/haskell/README.md). |
| H2 — Haskell SAN-only identity | TLS 2.4.3/x509-validation 1.9.1 accepted CN-only identity and could ignore IP-only SAN. Enforce the existing SAN policy through a name hook and pre-cache guard while preserving chain, CA, time and service checks. | Old CN-only path sent 35 bytes; old correct-IP/different-CN path failed. Fixed 18-test selection passes twice, with 17 zero-write/zero-byte denial receipts per run; DNS/IP/IPv6, cache, CA and pin controls pass. [Reviewed design](haskell-san-followup-plan.md), [independent review](remote/haskell-h2/source-review-h2.md), [results](remote/haskell-h2/README.md). |

For broker-filtered wrong-response IDs, the honest SDK observation is `CONTROL_DISCONNECTED`, origin `sdk`, family `worker_transport`. The matrix records the injected protocol fault separately. SO7 requires the combined worker transport/protocol family; the tests retain that exact observable classification. Direct SDK malformed-protocol tests retain `worker_protocol`. No new broker schema or status channel was added.

## Shared contracts and compatibility

**D1: terminal behavior follows the operation.** A rejected async submission ends that attempt and preserves the connection's earlier jobs. A terminal accepted-job result ends that job. Synchronous completion, `protocol_error`, malformed framing/JSON or transport failure ends use of the connection. Async dispatch now makes its continuation explicit, including delegated synchronous paths. JobStore tests prove rejected B preserves accepted A, owner-fatal cleanup removes only its jobs, and another session survives. A synchronous flow mixed into a connection holding async jobs ends that connection and cleans its owned jobs; use separate connections when retaining those jobs. [Contract](../../Docs/client-implementation-guide.md), [session tests](remote/main/logs/mirrors2-jobstore_spec.log).

**D2 / K1: exact POSIX `0600`.** All six clients enforce `(mode & 07777) == 0600`; five implementations were aligned and unchanged Rust was rechecked. Real POSIX mode cases cover accepted `0600`, rejected owner-only `0400`/`0700`, group/other access and established special bits. Tests retain key bytes and modes and cover shared server credential loading. Caller keys are never chmodded automatically. Native Windows ACL behavior is a separate platform check. Each affected client's contract/release documentation records the admission change.

Additional planned follow-ups are complete: Haskell verifies echoed job IDs/accepted kinds and accepts both legal cancellation response forms; Lean's convenience decoder treats absent/null optional strings consistently while rejecting malformed values. These remain defensive/API compatibility improvements. The original audit did not establish a normal typed-wire null defect or an explicit normative ID-equality requirement. Haskell fingerprint comparison remains the documented case-sensitive reference exception.

Rebuild the Gate C++ SDK, facade and consumers together: the added structured diagnostics change their source/ABI boundary. Generic MirrorCPP `Error`, generated adapter sources, synchronous generated outputs and frozen wire fixtures are unchanged. Rollback is per coherent repository unit with its tests/docs; SDK/facade consumers must move together. There is no persisted-data migration.

## Validation and build boundary

All compilation and runtime probes ran on the selected owned `windows-dev` Ubuntu WSL host. No local build/test or model checker was run. Scripted protocol peers, real TLS peers, fake model runners and actual Gate controllers/workers exercised these defects without model comparison.

| Target | Final accepted checks |
| --- | --- |
| MirrorLean | 125 root tests, zero failures; async suite with `MIRROR_BIN` removed; model-interface suite; native TLS/discovery and no-change native build; original audit controls rerun. |
| Mirrors | Transport, trace-capture and JobStore specs; maintained framing/trace-capture/validate-async gates; native rebuild dependency gate; full `run-local-no-model-check.sh` ending `ALL LOCAL NON-MODEL GATES GREEN`, including native integer maps against the freshly installed corrected C++ SDK. |
| MirrorECMA | Three typechecks, seven focused Jest suites / 170 tests, repeated dist build and full pinned non-live CI. CI reports 43 suites / 708 tests passed, with one suite / 13 tests skipped; skipped live coverage receives no acceptance credit. Package consumers and original admission controls pass. |
| MirrorCPP / Gate | Fresh warnings-as-errors SDK build and 3 CTests; actual SDK worker controls; separate TLS-enabled Debug build with 103 key-mode assertions and 167 assertions across 10 TLS cases; installed consumers; 37 facade rows, including two intentional cleanup failures and all 19 attached-session survival checks. |
| Haskell | Full library/test compilation; H1's 16 selected non-model tests plus paired actual-Core probe; final H2's 18 non-model tests twice and no-change binary hash. H1 and H2 evidence retain distinct source snapshots. |
| MirrorRust control | Fresh locked/offline transport target: four tests passed; locked archives verified; all 78 source files unchanged. |

The native rebuild gate verified C source, included-header, compiler identity and OpenSSL include/library invalidation through objects and linked executables, followed by no-change checks. Lean/native, C++ and Haskell no-change builds retained their checked binaries. Repeated ECMA output and selected Gate typed outcomes were stable. This establishes the recorded incremental and protocol/output boundaries; it does not assert universal bit reproducibility across unrelated build environments.

A parallel compiler relink caused the Gate producer hash guard to refuse an intermediate run before any row. Final acceptance sequenced native work, restored the explicit compiler, verified inputs and copied the producer to a separate mode-0555 immutable path. Final CLI framing/original controls and the 37-row Gate run all use that copy. Earlier failures remain diagnostic records, rather than receiving passing credit. [Detailed workflow and tool provenance](remote/README.md).

## Source and artifact identities

The coordinator independently verified **9,224 selected source files** against the applied checkouts, all **281 retained artifacts** in the main/H1/H2 leaf manifests, all seven unchanged HEADs and clean `git diff --check` results. The final C++/Gate 493-file manifest also matches the applied source. [Verification details and all changed-file hashes](final-source-verification.json).

| Repository | Unchanged starting HEAD | Selected final files | Changed source/doc/test files |
| --- | --- | ---: | ---: |
| Mirrors | `c17bae951c4d5bbc5818c2a4f82e2d93d07abc52` | 8,067 | 17 |
| MirrorLean | `b8b9491bd96e3126da55d34a7ba3a4493766dcf3` | 74 | 16 |
| MirrorECMA | `19f6ae6ce8d9b073bef888fc66efc4c49f2a07ab` | 392 | 9 |
| MirrorCPP | `410c58a175c3135d9cd76c85e33a718f63761855` | 179 | 4 |
| MirrorGate | `4a8d0d361589059ad72fe52e05789f302b4b65c8` | 314 | 14 |
| ModelMirros | `5ee414ee16b8aba50ceb480ac8013a56165272bb` | 120 | 16 |
| MirrorRust | `5049e99886a3d1f775e60190478c26e39c9aefc9` | 78 | 0 |

The source-file counts cover the selected remote build inputs, including unchanged repository evidence; they are not counts of tested functions. The 76 changed files exclude the new plan and this acceptance dossier. Existing AGENTS files, prior checkpoint/qualification records, Mirrors Core/Codec proofs, existing frozen fixtures and generated outputs were preserved. Unrelated editor caches and ECMA `.work/` remain present.

The final Mirrors producer is `D:/Desktop/Workspaces/Mirrors-client-fixes-20261015/cpp-gate/immutable/mirror`, SHA256:

```text
6e06ecd3d4d2975a42db2a1822b2d28d9e382f6d5b9bf48fa36c6c9ce27fa77d
```

[Main compiled identities](remote/main/compiled-artifact-identities.json) retain 272 executable/object/output records; child manifests retain their separate binaries. Remote-only temporary snapshot commits bind the full-SHA ECMA CI invocation: Mirrors `0a65f7ff7804ddafaa520eaeb5af7624e7852ed1`, ECMA `4cf1ea5a5cc4cef64fb2f4b6dbc142cbb3ca72af`. The final test-only Python socket-portability delta postdates that CI snapshot, changes no compiled input, and passed its full focused gate against the final immutable producer. Actual checkout HEADs above are unchanged.

[Source review 1](reviews/source-review-1.md), [source review 2](reviews/source-review-2.md), [H2 independent review](remote/haskell-h2/source-review-h2.md) and [final delta review](reviews/final-source-review.md) record review scope and corrections. [Initial application](reviewed-changes.json), [later reviewed deltas](applied-updates.jsonl) and the final file inventory identify the exact applied bytes.

## Environment, cleanup and remaining scope

Explicit tools were Lean 4.33.0, Node 24.15.0, pnpm 11.22.0, CMake 3.28.4, Python 3.12.14, GHC 9.14.1/Cabal 3.16.1.0 and signed Hackage index-state `2026-09-01T00:00:00Z`. GCC/G++ 12.3 is a recorded environment override; GCC13 baseline parity remains unchecked. A privately built real Bubblewrap 0.9.0 ran in its own namespace as an unprivileged user; system Bubblewrap bytes remained unchanged. Locked dependencies and compiler downloads were hash-verified.

Low WSL root capacity required one new 24-GiB D-backed ext4 image. Sources/tools and POSIX permission tests used that image; heavy outputs used the new D: namespace. Independent native streams were bounded to two jobs each, normally four aggregate. Earlier source/install/evidence images were preserved. No build-system migration was introduced.

All owned compiler/test/controller processes and the image keeper are closed. The new bind/mount were flushed and unmounted and the loop device detached. The image and build/tool bytes remain available through the recorded nonformatting [recovery workflow](remote/workflow/recover-new-image.sh). [Cleanup receipt](remote/cleanup-receipt.json). Private keys, binaries, dependency caches and images remain remote; only evidence and workflow scripts are retained here.

Remaining checks, in priority order:

1. Hosted CI with repository tool pins, including GCC13 parity, and native Windows/macOS TLS/ACL runtime checks.
2. Broader Gate backends and current-source Rust-worker replay under a separately frozen profile.
3. Fresh full cross-client/live qualification against a reobserved owned remote service, with current endpoint/runtime/certificate identities. No new M5/platform qualification is claimed by these remediation gates.

The 342-cell assessment preserves historical source support, conditional applicability, caller obligations and unverified runtime limits. The new record adds 24 numbered remediation overlays and one optional ECMA assessment; 318 numbered cells receive no new assessment. This repair acceptance does not turn the full client guide green.
