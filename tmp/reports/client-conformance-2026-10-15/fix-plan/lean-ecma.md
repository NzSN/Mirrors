# Fix plan: MirrorLean F1/F2 and MirrorECMA F3

Read-only planning, 2026-10-15. No production files changed, builds, runtime probes, model checks, commits, or deployment performed for this plan. Source locations below refer to the checked current identities, which equal the audit identities.

| Repository | Current HEAD inspected | Working tree observed |
| --- | --- | --- |
| MirrorLean | `b8b9491bd96e3126da55d34a7ba3a4493766dcf3` | Clean |
| MirrorECMA | `19f6ae6ce8d9b073bef888fc66efc4c49f2a07ab` | Existing untracked `.work/`; preserve |
| Mirrors contract | `c17bae951c4d5bbc5818c2a4f82e2d93d07abc52` | Contract source only for this subplan |

## F1: Reject empty effective TLS identity before network acquisition

**Evidence and failure boundary.** `../MirrorLean/MirrorLean/ServerMode.lean:110-112` computes `cfg.serverName.getD host` and calls the native shim without validation. `../MirrorLean/server-mode/native/mirrorlean_tls.c:167-174` begins native setup without validating `server_name`, then `:246-269` conditionally skips the whole SAN identity configuration when the supplied name is null or empty. The preceding CA verification still applies, which explains the exact remote observation: the empty override connects to the CA-valid CN-only peer while the default and wrong-name controls fail. Audit evidence is `remote/tls-results/server-cn.jsonl` and `server.jsonl`. There is no demonstrated fingerprint-pin bypass.

**Smallest fix.** In `connectMirrorTls`, reject an empty effective name immediately after the existing default selection and before `tlsConnect`. Use the established `tlsFail "connectMirrorTls"`/`IO.userError` contract, so the typed wrapper continues its current error mapping. The host default remains unchanged; an empty host with no override therefore also fails this check. Do not silently replace an explicit empty name with another identity, trim names, or invent a pin-only authentication mode. At the public native ABI entry, independently reject `server_name == NULL || *server_name == '\0'` before key/certificate processing, SSL allocation, DNS resolution, or socket creation. Then execute the existing DNS/IP SAN configuration unconditionally for the admitted name. Preserve DNS SNI, no SNI for IP literals, `X509_CHECK_FLAG_NEVER_CHECK_SUBJECT`, existing resource cleanup, TLS 1.3, mTLS, and post-handshake fingerprint handling.

**Files.** Production: `../MirrorLean/MirrorLean/ServerMode.lean`, `../MirrorLean/server-mode/native/mirrorlean_tls.c`. Regression tests: `../MirrorLean/server-mode/Test/ServerMode.lean`. Existing `../MirrorLean/server-mode/test/gen-test-certs.sh` already produces DNS/IP SAN and CN-only peers; reuse it. Update the `TlsClientConfig.serverName` doc comment and README TLS configuration paragraph to say a supplied/effective name must be nonempty. No package split or native dependency change is needed.

**Acceptance cases.**

| Case | Required observation |
| --- | --- |
| Normal DNS SAN | Explicit `localhost` over loopback accepts and exchanges one frame; SNI still configured |
| Normal IP SAN | Default host `127.0.0.1` with no override accepts the IP SAN peer |
| Empty override | Both the public Lean entry and direct exported `tlsConnect` reject locally with the specific empty-name diagnostic; no accepted peer socket or protocol write |
| Empty effective default | Empty host plus absent override rejects before resolving a host |
| Independent native guard | Call the raw Lean extern with an empty name and deliberately missing certificate/key paths: identity error must precede file errors. Review null and empty pointer handling in the same native guard; a direct C harness can exercise null if native ABI runtime coverage is required |
| CN-only | Explicit matching DNS name still rejects a CN-only certificate |
| Wrong DNS/IP identity | Reject mismatched SAN; include a DNS-only certificate for an IP-literal request if the existing fixtures are extended |
| Pin interactions | Correct name/correct pin accepts; correct name/wrong pin rejects before protocol traffic; wrong name/correct pin and empty name/correct pin reject. Pin never substitutes for SAN |
| Existing cleanup/discovery | Existing double-close and bad-pin candidate fallback tests keep their current result |

For a positive no-network assertion, use an owned loopback listener that records accept count without a blocking accept, or a bounded accept task that is closed/joined after the assertion. The raw entry diagnostic-order test additionally guards against validating only in the public Lean wrapper. Do not claim zero network solely because a connection to an unused port failed.

**Gain, cost, compatibility.** Removes a caller-controlled identity-verification bypass with a small duplicated guard at a public/native trust boundary. Intentional behavior change: `some ""` ceases to mean chain-only TLS; it fails as invalid configuration. Correct nonempty callers and default DNS/IP callers retain wire/API behavior. Release/rebuild the native server-mode package with the Lean change; source-only replacement leaves old native direct callers exposed. No service migration is needed.

## F2: Make the existing lightweight closure scanner lexically string-aware

**Evidence and failure boundary.** `../MirrorLean/MirrorLean/Spec.lean:48-59` strips comment markers without tracking quoted strings. The later tokenizer at `:74-83` does skip strings, but it receives already damaged text (`:99-101`). The remote `MarkerRoot` case returns success with only one source while its control includes the dependency (`remote/closure.jsonl`). Filesystem closure ownership, root ordering, and BFS resolution are already separate at `:112-155` and do not need redesign.

**Smallest fix.** Keep the public `stripComments : String → String` API and current token extraction pipeline. Give the comment stripper explicit normal/string/escaped-string/block-comment depth behavior, with line-comment handling in normal mode only. In string mode copy text unchanged, consuming backslash plus the following character together so escaped quotes/backslashes cannot change mode. Recognize nested block delimiters only inside comments. Replace stripped comment spans with a token separator and preserve newlines so `INSTANCE(* comment *)Dep` cannot become the single identifier `INSTANCEDep`. Continue skipping quoted strings in `dependencyTokens`, so a string containing `INSTANCE Ghost` or `EXTENDS Ghost` never becomes a module request. Do not interpret escape contents or normalize actual model source: the returned `ApalacheSpec.sources` must retain original file bytes/text, as it does now. Keep current built-in filtering, deterministic root-first BFS order, transitive closure, ambiguity detection, and missing-file errors. This is a lexical repair; adding a full TLA+ parser or defining a new malformed-source error contract is outside this fix.

**Files.** Production: `../MirrorLean/MirrorLean/Spec.lean`. Tests: extend `../MirrorLean/test/Main.lean` around `:595-735` and add source fixtures under `../MirrorLean/test/fixtures/root/` (or temporary fixtures following the existing `WithInstComma` pattern). Keep `stripComments` output assertions focused on preserving string text and comment separation, plus public `specFromFiles` closure assertions that prove the user-visible result.

**Acceptance cases.**

| Case | Required observation |
| --- | --- |
| Normal closure | Existing `Root`, `WithInst`, `Advanced`, builtin-only, search-dir, missing and ambiguous fixture cases keep their order/result |
| Marker regression | Valid string with `(*`, `*)`, or `\\*` before a real `INSTANCE DepA` preserves DepA and its transitive dependency |
| Escaped text | Escaped quote/backslash followed by a marker does not end/start the wrong lexical region |
| No false dependency | Strings containing `INSTANCE MissingGhost` or `EXTENDS MissingGhost` do not attempt filesystem resolution |
| Comments stay inert | Nested block and line comments containing keywords/module names do not resolve dependencies; quotes inside comments do not disable comment nesting |
| Boundary separation | `INSTANCE(* nested comment *)DepA` resolves DepA; comment newlines remain separators; multiline `EXTENDS DepA, DepB` retains order |
| Integration edge | A dependency's own marker strings do not hide a transitive `INSTANCE`; root source remains index 0 and every emitted source equals the original fixture text |

**Gain, cost, compatibility.** Restores complete source closure for valid TLA+ while reusing the existing scanner and resolver. Added state is local to one pure helper. The exported comment-stripping result may now retain quoted marker text and whitespace at removed comments; that is the intended correction, and callers should not rely on the previous corrupted text. No wire/schema change, new parsing dependency, or server deployment is required. Residual risk: this remains lexical module-reference extraction rather than validation of all TLA+ syntax; claim tested closure forms, not universal parser conformance.

## F3: Enforce the compiled target/computer pair consistently

**Evidence and failure boundary.** `../MirrorECMA/src/negotiated.ts:217-241` allows the async computer contract with `mirrorecma-v1` on the callback path. Explicit `execution: "sync"` adds its own stricter validation at `:815-821`, while explicit async uses a third validator at `:243-263`. Pure preparation occurs before `resolveTransport` at `:657-659` and `:686-688`, so this is an existing correct admission seam. Remote `ecma-result.json` proves the callback invalid pair invokes factory/computer/dispose and sends registration; explicit sync rejects with all those counts zero. The current test `../MirrorECMA/test/model-interface-runner.test.ts:367-394` intentionally expects both `mirrorecma-v1` and `mirrorecma-async-v1` to accept the async contract. That expectation conflicts with `Docs/client-implementation-guide.md:667-670` and must change with the implementation.

**Smallest fix.** Use one local pure validator for the effective compiled key (including optional explicit execution) called by both `selectedKey` and `selectedAsyncKey`, or make those functions delegate to the same compact pair predicate. Accepted target/computer pairs are exactly:

| Target | Computer contract |
| --- | --- |
| `mirrorecma-v1` | `mirrors.state-computer/v1` |
| `mirrorecma-async-v1` | `mirrors.async-state-computer/v1` |
| `mirrorecma-async-v2` | `mirrors.async-state-computer/v1` |

Explicit `execution: "sync"` additionally selects only the synchronous pair; explicit `execution: "async"` selects the async pairs and retains its existing `require` policy restriction. Keep `target_profile_mismatch` for unsupported/wrong-execution targets and `state_computer_contract_mismatch` for supported targets with wrong/unknown computer contracts. Validate before registry resolution, transport acquisition/spawn/readiness, or any factory/fallback construction. Retain exact adapter/digest lookup and effective-config checking; matching digest must not relax this rule. Remove only the duplicate checks superseded by the shared validator, avoiding a runner rewrite.

**Descriptor scope boundary.** Dynamic descriptor selections (`:126-162`) have neither a generated target nor a computer-contract key. Their data descriptor is target-neutral, and the returned factory scope chooses sync/async execution at `:559-575`. Do not invent a compiled target requirement, new descriptor wire field, or pre-factory execution check unavailable until the scope is returned. Preserve authorization before `createRegistry`, execution dispatch after scope creation, serial callbacks, and scope cleanup after failed binding. Cover descriptor direct-registry, sync factory, and async factory paths as integration controls for the shared runner change. This avoids misclassifying valid async dynamic scopes as the F3 compiled-key defect.

**Files.** Production: `../MirrorECMA/src/negotiated.ts`. Tests: `../MirrorECMA/test/model-interface-runner.test.ts`, `../MirrorECMA/test/async-replay-report.test.ts`, and existing dynamic binding tests where needed. Replace the contradictory success parameterization at `:367-394` with sync-profile/async-contract rejection and async-v1/v2 success. Briefly document the exact pair rule in `../MirrorECMA/docs/replay-and-async.md` if examples permit the old pairing. Public type signatures can remain source-compatible; runtime admission is the fix. Do not hand-edit compiler-produced bindings/locks/fixtures.

**Acceptance cases.**

| Case | Required observation |
| --- | --- |
| Normal callbacks | Callback compiled sync target/sync contract and async-v1/v2 target/async contract complete replay, with expected one factory and one cleanup |
| Invalid pair | Sync target/async contract fails with `state_computer_contract_mismatch` across void/report and generated/precomputed-trace public entry points, with and without explicit execution where overload permits |
| Matrix controls | Async targets/sync or unknown contract fail with the contract code; unsupported target and explicit execution/target mismatch retain target code |
| Before side effects | For invalid selection: factory/fallback/computer/dispose, registry resolve if instrumented, transport readiness/iterator/send/close all remain zero. A spawn-allocation test or mocked spawn boundary verifies the string-target path creates no child |
| Digest does not authorize bad pair | Same digest/adapter ID registered under the invalid pair still rejects locally |
| Descriptor integration | Existing authenticated resolved/not-modified descriptor controls keep sync and async dynamic scopes working; unauthorized reply keeps createRegistry at zero; failed binding/timeout disposes an acquired scope once |
| Existing report semantics | Successful callback and explicit execution paths retain their respective ReplayReport/CompiledReplayReport shapes and failure cleanup behavior |
| Compiler stability | Existing generated synchronous Counter is byte-stable and passes freshness checks; async v1/v2 generated bindings still type-check/run through current tests |

**Gain, cost, compatibility.** Closes the single overload-dependent admission bypass and reduces future drift by reusing the validation seam already before effects. Intentional runtime tightening breaks callers that registered async computers under `mirrorecma-v1`; migration is to generate/use the appropriate async target and its exact key, or use a real synchronous binding with the synchronous pair. Do not merely relabel metadata for a binding generated under another target. Correct profile callers retain source/wire compatibility. New package build is required, not a server migration.

## Remote validation plan and delivery gates

All compilation and test execution must run in a fresh owned remote WSL source tree, through the approved remote workflow; this coordinator performs source review only. Freeze full new commit/patch identities, manifest changed files, and confirm remote source parity before testing. Retain pre-fix audit evidence and write new result manifests separately. Never modify the previously qualified installed artifacts in place. Keep Node/pnpm/Lean/OpenSSL identities in the evidence; use repository tool pins and an explicit full new `MIRRORS_REF` when pairing a newer compiler. These fixes require no Apalache/TLC operation.

Existing manifest-backed commands (not executed for this plan):

```bash
# In the owned remote MirrorLean root:
lake build test async-test model-interface-test
.lake/build/bin/test
env -u MIRROR_BIN .lake/build/bin/async-test
.lake/build/bin/model-interface-test

# In the owned remote MirrorLean/server-mode directory:
lake build server-mode-test server-mode-test-discovery
.lake/build/bin/server-mode-test
.lake/build/bin/server-mode-test-discovery

# In the owned remote MirrorECMA root:
pnpm install --frozen-lockfile
pnpm run check
pnpm run check:model-interface
pnpm run check:examples
pnpm run test --runInBand --no-watchman test/model-interface-runner.test.ts test/async-replay-report.test.ts test/model-interface-dynamic.test.ts test/async-dynamic-binding.test.ts test/client-spawn-allocation.test.ts
pnpm run build
```

The Lean commands above name existing targets in `lakefile.toml` and `server-mode/lakefile.lean`; the TLS test binary generates its own ephemeral PKI. `test/Async.lean:5-18` runs framing/vector checks unconditionally and starts a live server only when `MIRROR_BIN` is set, so the command explicitly removes that variable. Its frame/vector coverage counts; its omitted live job tier does not. `test/ModelInterface.lean:347-355` runs the local scripted admission/lifecycle/registry/resource/registration/replay/codec suites. After focused tests pass, run MirrorECMA's existing non-live coordinated gate with a frozen remote Mirrors compiler checkout:

```bash
MIRRORS_ROOT=/absolute/owned/remote/Mirrors MIRRORS_REF=<full-frozen-new-SHA> pnpm run ci
```

`scripts/ci/check.sh` without `--live` explicitly runs compiler/offline replay coverage, including generated sync and async Counter smoke and package boundaries. Do not invoke its `--live` path for these fixes. It pins Node `24.15.0` and pnpm `11.22.0` in the inspected repository; reobserve actual tools when executing. Record generated compiler output checks, including no synchronous fixture diff. Lean native rebuilding uses its existing server-mode Lake target; no native dependency-graph edit is proposed. Actual OpenSSL/DNS/IP/pin runtime behavior and all new assertions remain unverified until these remote runs pass.

Commit and review F1, F2, and F3 as separate scoped changes with independent evidence and rollback by reverting the corresponding commit/rebuilding the affected client. F1 should lead because it concerns peer authentication; F2/F3 can proceed independently after the plan is accepted. Stage only the reviewed source/test/doc paths, preserve `.work/` and unrelated caches, and report exact new identities. Passing these tests grants only the scoped regression claims, not a fresh universal client qualification.

## Explicit follow-up, outside the three fixes

`../MirrorLean/MirrorLean/Protocol.lean:47-50` accepts absent optional strings but rejects explicit JSON null. The prior probe records absent `constInit` success/null failure. Typed outbound requests omit absent fields and satisfy C14, so do not silently fold a nullable codec change into F2. If accepted as a separate convenience-decoder compatibility task, specify absent/null/string equivalence and malformed non-string rejection, preserve outbound omission, add focused codec tests, and review all uses of the shared optional-string helper before changing it. No extra conformance defect or fix credit is claimed here.
