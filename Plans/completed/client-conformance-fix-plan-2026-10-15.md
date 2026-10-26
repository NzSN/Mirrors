# Client conformance remediation plan

Date: 2026-10-15. Status: proposed for review; implementation has not started.

Repair the seven implementation gaps from the [client audit](../../tmp/reports/client-conformance-2026-10-15/index.html), reconcile its two shared contract discrepancies, and retain explicit follow-up coverage for the additional observations. Six gaps have remote reproductions; the Haskell framing gap is confirmed from source. Each repair must pass a normal case, the original failure case, and an integration edge before receiving acceptance.

The recommended contract choices are to preserve a server-mode connection after a rejected async submission, and to enforce the existing exact POSIX `0600` key rule consistently. All build and runtime validation belongs on remote Windows-dev Ubuntu WSL. This request produces the plan and its review; implementation, commits, publication and deployment are subsequent work.

## Scope and source baseline

Current heads match the audit and all seven tracked working trees were clean when this plan was prepared. The two unrelated Mirrors untracked paths, `.projectile-cache.eld` and `Plans/dpm-review-remediation-evidence-20261013/`, must remain intact.

| Repository | Exact starting revision | Planned responsibility |
| --- | --- | --- |
| Mirrors | `c17bae951c4d5bbc5818c2a4f82e2d93d07abc52` | Contracts, built-in transports, trace capture, async dispatch and maintained gates |
| MirrorLean | `b8b9491bd96e3126da55d34a7ba3a4493766dcf3` | TLS identity, dependency discovery and key modes |
| MirrorECMA | `19f6ae6ce8d9b073bef888fc66efc4c49f2a07ab` | Compiled selection admission and key modes |
| MirrorCPP | `410c58a175c3135d9cd76c85e33a718f63761855` | Public runner regression controls and key modes |
| MirrorGate | `4a8d0d361589059ad72fe52e05789f302b4b65c8` | Trusted C++ error capture and facade integration |
| ModelMirros | `5ee414ee16b8aba50ceb480ac8013a56165272bb` | Haskell bounded framing and key modes |
| MirrorRust | `5049e99886a3d1f775e60190478c26e39c9aefc9` | Regression control for existing strict key-mode and framing behavior |

Guide SHA-256: `8017baebdb0a73473107a88b16422311afe84a1e3afa754f58887190fc73c7b4`. Audit evidence manifest SHA-256: `fc2230e541a07c3294b5c6b720674f8600a36570f687aa31255550e0b7d16670`.

Before implementation, record fresh heads, tracked diffs, toolchains and affected file hashes. Rebase the task mapping if they changed. Preserve the audit's dated evidence and the October framework qualification records; new sources receive a new acceptance record.

## Contract decisions

### D1 Make terminal behavior depend on the operation

Recommend the following clarification to C5, section 10, the [interface reference](../../Docs/interface-reference.md), and [async design](../../Docs/async-enablement-design.md). No wire tags or job-ID formats change.

| Context and result | Required continuation |
| --- | --- |
| Async submission returns `register_error` | End that attempt. It owns no new job. Preserve the connection and its earlier accepted jobs; allow an explicit new attempt or operations on existing jobs. |
| Accepted async job returns its terminal result/status | End that job or lookup. Other jobs may still use the connection. Do not keep polling an unknown/evicted job. |
| A synchronous replay, validate, generation or exploration flow terminates | Stop that flow and use a fresh connection for a new synchronous flow. Required negotiation failure never authorizes a fallback. |
| `protocol_error`, malformed framing/JSON, or transport failure | Treat the connection as unusable. Send no cancellation or further flow messages on it; server owner cleanup applies. |

This matches the existing async rejection behavior in `Shell/Mirror/Session.lean:900–912` and avoids disconnecting jobs that C6 assigns to that connection. Classification uses operation/phase, never human error text.

The server also needs a small consistency correction: its unexpected async-command path at `Session.lean:942–944` can send `protocol_error` and continue while the phase is idle. Review every `sendError` path reached from async dispatch, including synchronous dispatch on that connection. Make each `dispatchAsync` continuation explicit: accepted/rejected async submissions and job controls continue; unexpected commands end; a synchronous flow ends the connection when delegated dispatch returns, regardless of its retained phase. The existing Bool return can express this without changing Core transitions or proofs. Do not infer usability from an unchanged phase or parse the server's own outgoing messages.

Document the compatibility effect: a synchronous one-shot registration mixed into a connection holding async jobs ends that connection and triggers C6 cleanup. Applications retaining those jobs should use a separate connection for synchronous work. This coordinated D1 task has its own acceptance evidence and is not required to justify the independently scoped M2 client cancellation fix.

Acceptance must prove that accepted job A survives rejected submission B, A remains awaitable/cancellable, B acquires no job, and fatal input cleans only the owner's jobs. Cover the unexpected-command path, a protocol error returned through synchronous dispatch, and successful synchronous completion on a mixed connection. The latter must end the owner connection and clean its earlier jobs while another session's jobs remain usable. Extend the existing fake-runner `tools/JobStoreSpec.lean`; live model checking is unnecessary.

### D2 Keep the exact POSIX key permission rule

Recommend retaining C27 and the interface reference's exact `0600` requirement. Update ECMA, C++, Lean, the built-in CLI and Haskell checks to compare all permission/special bits against `0600`; Rust already does so. Preserve Windows ACL behavior.

The tradeoff is deliberate rejection of owner-only `0400`, `0700` and special-bit modes that five clients currently accept. This is contract alignment; those modes alone do not prove secret disclosure. Return an actionable diagnostic showing that exact `0600` is required. Never chmod a caller's key automatically. Document the changed admission behavior in each affected client's release notes.

Use a common case list across client tests: `0600` succeeds; `0400`, `0700`, group/other-readable modes, and supported special-bit variants fail before protocol bytes. Run POSIX mode tests on an actual POSIX filesystem in remote WSL; DrvFS permission emulation cannot establish this rule. Native Windows ACL validation remains a separately declared platform check.

| Client | Key check | Regression location |
| --- | --- | --- |
| MirrorECMA | `src/transport.ts` | Focused transport tests and existing private-key smoke checks |
| MirrorCPP | `src/detail/tls.cpp` | `test/unit/tls_test.cpp` |
| MirrorLean | `server-mode/native/mirrorlean_tls.c` | `server-mode/Test/ServerMode.lean` |
| Mirrors | `Ffi/tls_shim.c` shared client/server helper | `tools/TransportSpec.lean` and native rebuild gate |
| ModelMirros | `src-tls/Protocol/Transport/Tls.hs` client/server predicates | `test/TlsTransportSpec.hs` |
| MirrorRust control | Existing exact check in `src/transport.rs` | `tests/transport.rs` |

For shared client/server key helpers, align both roles with their documented rule and include a server credential-load control. Assert mode and key bytes are unchanged after acceptance and rejection; verify each special-bit test actually established its requested mode. Record unsupported filesystem cases explicitly.

An alternative would relax the guide to an owner-only policy and change Rust. That would change the published policy; it is not the proposed default.

## Implementation tasks and ownership

One owner keeps each repository's overlapping changes together. The coordinator owns shared contracts, evidence integration and final review. The five implementation owners may run in batches within available agent slots; heavy builds share a bounded resource budget.

| Task | Owner and exclusive edit scope | Depends on | Acceptance result |
| --- | --- | --- | --- |
| P0 | Coordinator: identity manifest and this plan | None | Current sources/toolchains, writable remote storage and evidence locations recorded |
| D1 | Coordinator with Mirrors owner: guide/reference/async docs; `Shell/Mirror/Session.lean`; `tools/JobStoreSpec.lean` | P0 | Rejected async attempt preserves earlier jobs; every terminal protocol error exits and cleans only owned jobs |
| D2 | Coordinator: shared key-policy text, common mode case list and compatibility decision | P0 | Exact `0600` predicate and POSIX/Windows scope agreed before K1 edits |
| L1 | Lean owner: `MirrorLean/ServerMode.lean`, native TLS shim and server-mode tests | P0 | Empty identity rejected; SAN, pin and mTLS controls remain correct |
| L2 | Lean owner: `MirrorLean/Spec.lean`, root source-resolution tests | P0 | Correct dependency closure despite quoted comment/dependency tokens |
| E1 | ECMA owner: `src/negotiated.ts`, runner admission/tests and replay guide as needed | P0 | Invalid compiled pairing rejected before I/O/construction; valid callback and descriptor modes preserved |
| C1 | C++ integration owner: MirrorGate managed-worker SDK, `integrations/mirrorcpp/` and their tests | P0 | Trusted original failure family/stage survives facade normalization; mismatch and cleanup precedence preserved |
| M1 | Mirrors owner: `Shell/Transport/{Stdio,Tcp,Tls}.lean`, `tools/TransportSpec.lean`, new CLI framing gate | P0 | Unterminated EOF/read-error fragments cannot become accepted frames |
| M2 | Mirrors owner: `Shell/TraceCapture.lean`, capture Lean/Python tests | P0; D1 for final contract assertions | Only local budget exhaustion on a healthy owned pending job sends one cancellation |
| H1 | Haskell owner: transport core/adapters, transport tests and Cabal registration | P0 | All three transports enforce byte bounds before parsing/after encoding |
| K1 | Each repository owner: its existing key check and tests; coordinator owns shared case list/docs | P0, D2 | Five clients align with exact `0600`; Rust remains a passing control |
| V1 | Coordinator and remote executor: fresh builds, focused gates and applicable non-model suites | D1, L1, L2, E1, C1, M1, M2, H1, K1 | All required acceptance cells have retained results and source/binary identities |
| R1 | Independent reviewer; coordinator writes new acceptance record | V1 | Reproductions reject, positive controls pass, ownership and evidence claims reviewed |

The Mirrors owner alone edits `lakefile.lean` and `tools/run-local-no-model-check.sh`. Lean and ECMA owners combine their main fixes with their K1 edits to avoid file conflicts. The Mirrors and Haskell owners likewise combine K1 with their overlapping transport/native tests. The C++ integration owner also owns MirrorCPP's K1 TLS check, while keeping the generic MirrorCPP error type and generated adapters unchanged if the integration design below suffices.

Audit traceability: F1 → L1; F2 → L2; F3 → E1; F4 → C1; F5 → M1; F6 → M2; F7 → H1. D1 and D2/K1 reconcile the two contract discrepancies. Start L1 first because it affects peer authentication; the other independent repair tracks can then proceed in parallel within their file ownership.

### L1 Reject empty TLS identity before connection

Cause: `MirrorLean/ServerMode.lean:111` uses `cfg.serverName.getD host`, so `some ""` bypasses the host default; `server-mode/native/mirrorlean_tls.c:246` skips identity configuration for an empty name.

Validate the effective name in Lean before socket acquisition. Retain a defensive nonempty check in the C entry point, then configure DNS/IP SAN validation unconditionally for valid input. Do not silently replace an explicit empty override with the host. Keep CN fallback disabled, TLS 1.3/mutual authentication intact, and pins additive to CA/SAN verification.

Extend `server-mode/Test/ServerMode.lean` and its temporary certificate generator. Check a matching DNS/IP SAN, default host, explicit valid name, wrong name, CA-valid CN-only peer, and empty override. Cover both no-pin and pinned configurations so a matching pin cannot replace SAN checks. Test the public Lean wrapper and direct exported native entry separately; empty identity must precede deliberately missing credential-path errors, and a bounded listener must observe no acquired socket. Rebuild the actual native target and linked test, not only root Lean modules.

### L2 Make dependency discovery respect string literals

Cause: `MirrorLean/Spec.lean:50` strips `(*` inside a quoted TLA+ string as a comment, hiding a later `INSTANCE` dependency.

Keep the existing two-step pipeline: make the comment stripper track ordinary text, quoted string/escape, line comment and nested block-comment states; preserve string text and token separators/newlines, then let the existing dependency tokenizer skip strings. Fixing comment stripping must not introduce false dependencies from words inside strings. Preserve module discovery order, deduplication, standard-module handling, cycle behavior and existing errors. This task does not add a new TLA+ parser or change the wire format.

Extend the root `test/Main.lean` source-resolution cases for the original marker-before-INSTANCE input, real nested comments, escaped quotes/backslashes, `\\*` markers, multiple dependencies and quoted fake `INSTANCE`/`EXTENDS` tokens. Assert exact source ordering/content, missing-real-module failure, and shared/cyclic closure termination. Test inline registration's final byte bound separately from source discovery.

### E1 Admit compiled computer pairings consistently

Cause: callback selection without an explicit `execution` skips the pairing check in `MirrorECMA/src/negotiated.ts:226–229`. A current test in `test/model-interface-runner.test.ts:367–394` explicitly expects the invalid sync-target/async-contract pairing to succeed.

Centralize local compiled-selection admission and invoke it from every public compiled callback/explicit-execution overload before transport resolution/spawn/readiness, writes, registry lookup or factory acquisition. Accept exactly `mirrorecma-v1` with `mirrors.state-computer/v1`, and `mirrorecma-async-v1` or `mirrorecma-async-v2` with `mirrors.async-state-computer/v1`. Keep `state_computer_contract_mismatch` for a supported target with an incompatible computer contract, and the existing `target_profile_mismatch` for an unsupported target or explicit execution/target mismatch. Explicit sync/async execution retains its corresponding pair and current policy restriction. Split the contradictory test and record the corrected admission behavior as a compatibility change. Migration uses a binding generated for the proper async target; relabeling old generated metadata is insufficient.

Descriptor factories are target-neutral and do not carry compiled target/contract keys. Preserve their authenticated-descriptor ordering and validate dynamic scope constraints at the existing acquisition point after the factory returns the needed scope. Do not add target fields to descriptor selections or force checks before the data exists.

Controls cover implicit and explicit execution, valid sync and async versions, invalid pairs, and zero sends/factory/computer/dispose calls on local rejection. Preserve transport ownership on pre-acquisition rejection, exactly-once cleanup after acquired resources, descriptor sync/async success, and unauthorized/wrong-digest zero-worker behavior. Keep synchronous generated output byte-stable.

### C1 Retain trusted Gate failure provenance in the C++ facade

Cause: the public MirrorCPP runner replaces a factory's code with `adapter_factory_failed`; generated callback catches can replace invoke/observe errors with generic binding errors. Gate's existing conversion also drops stage. The audit runtime probe covered the actual runner with a fake transport; actual backend/worker failure injection remains required.

Prefer capture owned by the Gate integration rather than expanding the generic MirrorCPP `Error` layout or rewriting generated adapters. Add an immutable value snapshot of the managed worker's recorded primary failure, carrying SDK-owned origin/family, code, stage and optional operation ID plus a bounded diagnostic. Preserve the original stage even when empty; keep any local operation context in a separate field. Capture factory/control/attach failures before normalization, and snapshot worker failures before runner-owned dispose can add cleanup failures or release the worker.

The facade uses this trusted record to restore the stable Gate failure code on the public result and expose stage/origin in structured `SandboxEvidence`. Preserve the first primary failure; cleanup/control-shutdown errors remain separately visible and make otherwise successful execution fail. A normal Mirrors `step_mismatch` remains an ordinary mismatch.

`SdkError` alone does not prove origin: worker replies can supply code strings. The SDK must distinguish locally/control-classified admission, protocol and deadline failures from worker application diagnostics. A worker that writes `DEADLINE_EXCEEDED` or a backend-looking code must not gain that trusted family. Cover exception paths and lifecycle/precondition failures that currently bypass `remember_primary`, not just the existing stored-error path.

Test normal replay, wrong digest with zero worker acquisition, real backend admission rejection, malformed worker response, invoke/observe failures, actual SDK deadline expiry, spoofed worker codes, and secondary cleanup failure. Assert public stable code, structured stage/origin, primary precedence and physical cleanup. Rebuild the Gate SDK, facade and downstream C++ consumers together; an additive snapshot/evidence surface does not establish binary compatibility with an old SDK build. If this design cannot cover all callback paths, review a targeted alternative before expanding the generic error interface.

Retain a family matrix for control compatibility, preparation/build/admission, model negotiation, worker transport/protocol, application failure, timeout/cancellation and ordinary Mirrors mismatch. Add an attached-daemon case with a second live session to prove cleanup does not stop the daemon or the other session. Credit SO7 only for the families actually injected through the corrected facade.

### M1 Reject incomplete JSONL frames on every built-in transport

Cause: TCP and TLS receive loops combine clean EOF with read failure, then accept a nonempty buffer without LF. Stdio has the same partial-EOF pattern and belongs in the narrow framing correction.

Return `none` only for clean EOF with an empty accumulator. Distinguish read-error sentinels and fail with an infrastructure diagnostic. A nonempty EOF fragment is an unterminated-frame error even when it is valid JSON. Mark/discard unusable partial state. Preserve complete buffered LF frames, current CRLF handling, split/coalesced input, strict UTF-8 and the 65,535-byte payload bound. Keep the FFI interface unchanged.

Extend `tools/TransportSpec.lean` and add proposed `tools/check-client-framing.py` for actual `mirror validate`/trace-generation behavior. Cover normal LF, split LF, multiple frames, empty EOF, valid JSON without LF, partial JSON, read failure and byte boundaries. Exercise real TLS close-notify EOF and abrupt socket termination separately; the original audit only exercised plain TCP. Invalid frames must print no `VALID`, exit with failure, and publish no capture. Bound all peers/children and reap them in `finally`.

### M2 Cancel only after local poll-budget exhaustion

Cause: `Shell/TraceCapture.lean:95` cancels after every `awaitTraceJob` error, including terminal `protocol_error` and job outcomes.

Give the private await helper typed stop reasons: local poll-budget exhaustion, terminal job outcome, and peer/protocol/transport failure. Preserve the public `Except String Capture` interface and diagnostics. Send best-effort `cancel_job` only for an accepted owned job still believed pending/running on a healthy connection when the local budget expires, including the helper's explicit zero-budget case after acceptance.

After protocol error, malformed reply, wrong correlation/result kind, EOF/read failure, cancelled/unknown status or terminal job failure, return without further wire writes. Failure before acceptance owns no job. A failed cancellation must not overwrite the original budget diagnostic, and cancellation acceptance alone is not proof of worker termination.

Update existing tests that currently expect cancellation after wrong-job/wrong-result/cancelled replies. Extend `tools/TraceCaptureSpec.lean` and `tools/check-trace-capture.py`: exact write sequences, success, pending/running budget exhaustion, protocol error, malformed reply, throwing receive, infra error and cancellation-send failure. Check that failure publishes no output and that the CLI closes its owned connection.

### H1 Bound final encoded output and raw receive accumulation

Cause: Haskell `Protocol.Transport.Core.sendMsg` encodes without a final size check, while TCP/stdio line reads and TLS buffer growth are unbounded.

Place final encoded UTF-8 payload validation in transport core and enforce the same predicate in built-in `send` methods so direct transport callers cannot bypass it. Add reusable bounded LF framing behind the existing transport interface. Adapt stdio, TCP and TLS to feed bounded raw chunks or bounded buffered-handle reads without changing exported constructors unnecessarily. Count at most 65,535 bytes before LF, reject oversized input before JSON parsing, distinguish clean empty EOF from an incomplete frame, and preserve bytes after an LF for the next frame. Inspect each LF-delimited frame before treating a coalesced chunk as oversized. An oversized/incomplete frame must poison or close that transport rather than leave its tail eligible for another request. An oversized send must emit zero bytes. Define and test the bounded retained payload plus fixed input-chunk/suffix allowance; do not decode partial UTF-8 chunks independently.

Do not alter ordinary JSON encoding, record keys, optional fields, ITF integers or frozen Haskell corpus files. Shared transport-core changes affect server use too: include a normal server-side request/reply round trip and an oversized inbound request refusal with owned resource cleanup.

Extend `test/TcpTransportSpec.hs`, `test/TlsTransportSpec.hs`, and add focused stdio/framing cases registered in `test/Main.hs` and `ModelMirrors.cabal`. Cover final encoded lengths 65,534/65,535/65,536, multibyte UTF-8 boundaries, escaped JSON, fragmented/coalesced lines, strict LF/EOF behavior, long unterminated input with bounded retained memory, and zero-write send rejection. Test actual adapters rather than only a byte helper. Establish Haskell toolchain/package availability on remote WSL before scheduling its build.

## Additional observations and follow-up decisions

Keep these visible without treating them as seven already-proven runtime defects.

| Observation | Proposed follow-up and acceptance |
| --- | --- |
| Haskell discards echoed job IDs/accepted kind | After H1, add local correlation checks for accepted/status/result replies. A wrong ID or kind must fail without returning another job's result or cancelling that ID. Preserve valid replies. State the stronger expectation in the guide before counting it as a numbered conformance gate. |
| Haskell `cancelJob` accepts only `job_status` | Accept both legal response shapes in section 6 using the existing decoder, validate correlation, and test terminal `job_result` as well as current-server status replies. This closes a source-only compatibility gap. |
| Lean config decoder rejects explicit `constInit: null` | Align optional string decoding with absent-equals-null semantics, preserve type errors for nonstrings, and add absent/null/string/wrong-type round-trip cases. Normal typed outbound omission remains stable. |
| Haskell SAN behavior and fingerprint exception | Run CA-valid SAN/CN/wildcard/IP and pin cases against the actual installed TLS dependency on remote WSL. Record the documented case-sensitive-pin exception explicitly. A policy change or proven new defect gets a separate reviewed task; no CN-fallback defect has yet been established. |

These tasks can follow the main repair gate. Haskell cancellation grammar and reply correlation should share one owner to avoid overlapping `Protocol/Client.hs` edits. Full client conformance cannot be claimed while applicable TLS policy remains unverified or an accepted exception is omitted from the scope statement.

## Execution and validation sequence

1. **Freeze and settle contracts.** Review D1/D2, record fresh source/toolchain identities, establish remote disk and dependency capacity, and retain the baseline reproductions unchanged.
2. **Implement focused repairs.** Owners add the regression at the public interface, confirm the original behavior fails that expectation remotely, apply the smallest change, then run the normal/failure/integration controls. Keep deterministic case IDs and exact transport write assertions.
3. **Integrate once.** Build changed targets from the corrected sources and run affected offline suites. Use a fresh remote source/build/install namespace and immutable dependency caches where compatible; old audit binaries are controls, not repaired artifacts. Avoid concurrent clean/build operations on one output tree.
4. **Review acceptance evidence.** Bind heads plus working diffs/file hashes, compiler/library versions, build commands, binary hashes, case results and cleanup receipts. Independently review C++ trust/cleanup, TLS identity, bounds and session ownership. Update all 342 audit cells only where new evidence supports it.
5. **Record scoped completion.** Save a new dated remediation record and remaining platform/live tiers. Commit/push or a new release qualification remains a separate requested action.

### Remote build and gate boundaries

All commands below are proposed remote commands. No compilation, runtime probe or model checker runs on this coordinator for this plan.

| Target | Focused gate and build requirements |
| --- | --- |
| Mirrors | `lake build mirror transport_spec trace_capture_spec jobstore_spec`; run those three spec executables, the new `python3 tools/check-client-framing.py`, existing trace-capture/validate-async scripts, then `bash tools/run-local-no-model-check.sh` once after integration. Wire the new gate into both maintained drivers. |
| MirrorLean root | `lake build test async-test model-interface-test`; run `.lake/build/bin/test`, `env -u MIRROR_BIN .lake/build/bin/async-test`, and `.lake/build/bin/model-interface-test`. Removing `MIRROR_BIN` avoids the async test's live-server branch. Root uses its own `lean-toolchain`. |
| MirrorLean native TLS | In `server-mode/`, `lake build server-mode-test`; run `.lake/build/bin/server-mode-test`. Its package/toolchain and native TLS object are separate from the root package. Verify a C/header change relinks the executable and a no-change rebuild does no native work. |
| MirrorECMA | Frozen dependency install; `pnpm run check`, `pnpm run check:model-interface`, `pnpm run check:examples`; `pnpm run test --runInBand --no-watchman` with runner/report/dynamic/spawn-allocation test files. Build fresh `dist` before the actual public-overload probe. Then run `MIRRORS_ROOT=<owned-remote-root> MIRRORS_REF=<full-new-SHA> pnpm run ci` without `--live`. Use its own published compiler baseline. |
| MirrorCPP and Gate C++ | Use a separate Debug MirrorCPP TLS/unit-test build for K1, and Gate's `bash scripts/test-control-cpp.sh` for its SDK tests with a bounded `CMAKE_BUILD_PARALLEL_LEVEL`. Configure `integrations/mirrorcpp` against the exact corrected `MIRRORCPP_ROOT`; build `mirrorgate_mirrorcpp_counter` and `mirrorgate_mirrorcpp_receipt_tests`. That integration intentionally disables MirrorCPP TLS/tests; it cannot replace the separate K1 build. Run actual Gate controls with finite timeouts, plus existing packaging smoke for a fresh consumer. |
| Haskell | Build the existing `ModelMirrors-test` suite and run selected Tasty transport/client cases with `cabal test ModelMirrors-test --test-options=...` after retaining the selected test list. Existing whole TCP/TLS groups include model-backed tests; select explicit non-model cases or split those groups. Run the new framing cases and changed server use paths with `LC_ALL=C.UTF-8`. |
| Rust control | Run `cargo test --test transport` from a fresh source-matched build; it includes exact-mode, byte-boundary, stdio and loopback TCP controls. No Rust behavior change is planned under the recommended D2 choice. |

Record observed tool versions against repository manifests/pins. The audit observed remote Node 24.19.0 whereas `tools/ci/versions.env` names 24.15.0, and different Lean packages have independent toolchains. Resolve each target's supported pin and record an override if required; an installed tool being newer is not parity proof. The CI Apalache pin is historical and differs from the selected live-service record; these non-model fixes do not require an oracle version migration.

Remote preflight must recheck capacity: the audit recorded only about 722 MiB free on the WSL root while D: had space. Use a new owned D:-backed workspace for large outputs, with a POSIX-backed location for key-mode tests. Do not delete or remount earlier evidence/install images to make room. Limit build concurrency from measured capacity, and reuse dependency caches read-only where toolchain-compatible.

After a normal rebuild, repeat the no-change incremental build and deterministic protocol/corpus checks. Confirm expected native targets relink after C/header edits and remain untouched on no-change runs. K1 changes the Mirrors TLS C shim: run `bash tools/check-native-rebuild.sh` on remote WSL to verify that affected native path; do not expand into a build-graph redesign. Bit-identical whole binaries are not an assumed build-system guarantee; retain hashes and compare reproducible wire/generated outputs instead. No build-system migration is needed.

### Integration and remaining environment checks

The main fixes can be accepted with scripted protocol peers, real TLS peers, fake model runners and actual Gate control/worker processes, all on remote WSL. No new model run is necessary to prove these error paths. Actual Gate admission/protocol/deadline controls are required for C1; the previous fake-transport test alone is insufficient. Gate's broad control conformance runner starts local Apalache: use the supplied-trace/focused control path for this repair, rather than inheriting that runner's live tiers.

A later full cross-client/live qualification must follow [interop instructions](../../tools/interop/INTEROP.md) with an owned remote service and explicit full Mirrors SHA. Reobserve its endpoint, binary, runtime, current certificate validity and pins first. The old October 7 certificate identity expired and cannot authorize a current connection. Never invoke `tools/interop/run.sh` or `lake test` blindly here: both can lead into local model-checker tiers.

Hosted CI must still confirm the selected compiler/tool pins and all required gates. Native Windows/macOS TLS/ACL behavior, broader Gate backends, and any full-current-source qualification remain separate from WSL acceptance. Unsupported tiers are recorded as unverified, not successful skips.

## Acceptance and rollback

The repair gate is complete only when every main task has its stated normal, original-failure and integration result, all owned peers/processes are gone, generated sync/wire output remains stable, and an independent review finds no unresolved defect in the changed scope. Report main repair completion separately from follow-up observations and full guide conformance.

Keep changes in cohesive per-repository units: contracts/session semantics; TLS/key modes; dependency discovery; ECMA admission; C++ Gate provenance; bounded Haskell framing; CLI framing/cancellation. Review and revert a unit with its tests/docs if needed. The C++ SDK/facade/consumer build must move or roll back together. Any future strict-key rollout needs release notes and a diagnostic rather than automatic key mutation. No production service, certificate, registry or persisted data migration is part of these repairs.

## Plan review

Independent review completed with no remaining material findings in the reviewed plan. Four corrections were incorporated: isolate Lean's live-test trigger, use the repository's Jest invocation, make synchronous dispatch termination and owner cleanup explicit, and complete D2/K1 dependencies and ownership. The [review record](../../tmp/reports/client-conformance-2026-10-15/fix-plan/independent-review.md) retains the findings and their resolution.

This verdict covers the proposed repair design, task boundaries and source-backed validation commands. Implementation and all new build/runtime acceptance results remain pending.
