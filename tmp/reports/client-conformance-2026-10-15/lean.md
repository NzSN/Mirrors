# MirrorLean client-guide audit — 2026-10-15

Inspected current HEAD `b8b9491bd96e3126da55d34a7ba3a4493766dcf3`. Read-only source and test review; no local builds or tests.

## Findings

### [P2] C25, MI18: Call connectMirrorTls with cfg.serverName := some "" against a CA-valid peer whose SAN does not match the intended host.

At `/home/nzsn/Repos/MirrorLean/server-mode/native/mirrorlean_tls.c:246`. Client skips server hostname/IP authentication and trusts any CA-valid server certificate unless an independent matching pin is also configured.

Smallest fix: Reject an empty effective server name in Lean before native connect and defensively reject it in the C shim. Add wrong-SAN peer + empty override regression.

Confidence: high source-confirmed; live probe pending.

### [P2] C13: Valid TLA+ source contains a string literal "(*" before a subsequent Helper == INSTANCE Dep statement.

At `/home/nzsn/Repos/MirrorLean/MirrorLean/Spec.lean:50`. stripComments enters block-comment depth inside the quoted string and discards later dependency tokens; inline registration omits Dep source and fails remotely.

Smallest fix: Lex and preserve/skip quoted strings while stripping comments; add fixture with comment delimiters inside strings before an INSTANCE reference.

Confidence: high source-confirmed; actual Lean runtime probe pending.

## Peripheral codec drift

Public ApalacheConfig.ofJson? receives explicit null optionals such as constInit:null. Convenience decoder rejects a valid Haskell-style request config; typed outgoing runners omit keys and remain conforming. Make optional/default accessors treat explicit null as absent; test null and absent equivalence.

## Rule matrix

All statuses below mean source support rather than runtime qualification.

| Rule | Status | Evidence | Note |
|---|---|---|---|
| C1 | source-supported | `MirrorLean/Transport.lean:48`, `MirrorLean/Transport.lean:70`, `MirrorLean/Protocol.lean:401` | All built-in transports delimit lines with LF, reject empty/unterminated input and strict-decode UTF-8; replay codec requires object proto_step. |
| C2 | source-supported | `MirrorLean/Transport.lean:48`, `MirrorLean/Transport.lean:81`, `MirrorLean/Transport.lean:150`, `MirrorLean/ServerMode.lean:136` | Outbound raw UTF-8 payload checked at 65535; stdio bounded byte reads; TCP/TLS shared accumulator bounded plus at most fixed 4096-byte read. |
| C3 | source-supported | `MirrorLean/Protocol.lean:401`, `MirrorLean/Async.lean:32` | Dispatch on string proto_step and read selected keys, ignoring unknown outer keys; stricter MI objects handled separately. |
| C4 | source-supported | `MirrorLean/Client.lean:176`, `MirrorLean/Client.lean:254`, `MirrorLean/Async.lean:115` | Replay/explorer/validate start with register; jobs query without registration on network-only Connection. Stdio refuses Connection adoption. |
| C5 | source-supported-with-contract-interpretation | `MirrorLean/Client.lean:85`, `MirrorLean/Client.lean:254`, `MirrorLean/Client.lean:316`, `MirrorLean/Async.lean:134` | Replay/explorer/validate terminal paths close; job submission register_error ends its attempt while retaining Connection. Guide section 10 and server dispatchAsync permit that async attempt interpretation, despite broad C5 wording. |
| C6 | source-supported | `MirrorLean/Client.lean:162`, `MirrorLean/Async.lean:120`, `test/AsyncSupport.lean:91` | Owned replay transports close on success/failure; persistent Connection has serialized idempotent close; EOF poisons async connections. Job eviction is server behavior; source tests cover cross-owner lifetime. |
| C7 | source-supported | `server-mode/native/mirrorlean_tls.c:299`, `MirrorLean/Async.lean:153` | No protocol heartbeat or idle timer. TLS timeout cleared after handshake. queryJob available for polling. |
| C8 | source-supported | `MirrorLean/Client.lean:98` | Shared replay invokes computer once then sends one report_state for initial_state and next_step. |
| C9 | source-supported-with-application-obligation | `MirrorLean/Value.lean:218`, `MirrorLean/Client.lean:98` | State.toJson encodes every supplied field as ITF; full observable-state honesty/completeness remains caller binding obligation. |
| C10 | source-supported | `MirrorLean/Client.lean:113`, `test/Main.lean:479` | step_mismatch returns error immediately; main owner closes, without expecting all_steps_done. |
| C11 | source-supported | `MirrorLean/Value.lean:87`, `MirrorLean/Value.lean:129`, `test/ModelInterface.lean:311` | Arbitrary precision Int encodes as decimal #bigint and integral bare JSON is accepted. |
| C12 | source-supported | `MirrorLean/Client.lean:85` | Replay loops until actual terminal reply, no assumed trace length. |
| C13 | confirmed-source-defect | `MirrorLean/Spec.lean:48`, `MirrorLean/Spec.lean:99`, `MirrorLean/Spec.lean:126` | Closure resolver recursively handles EXTENDS/INSTANCE and errors on ambiguity, but comment stripping ignores quoted strings: a string containing (* before a later INSTANCE can hide required dependency. |
| C14 | outbound-supported-decoder-drift | `MirrorLean/Protocol.lean:47`, `MirrorLean/Protocol.lean:114`, `MirrorLean/Protocol.lean:128` | Typed outbound config omits absent optionals and is conforming. Public ApalacheConfig.ofJson? rejects explicit null optional fields; this affects convenience request decoding, not normal typed runner emission. |
| C15 | source-supported-with-application-obligation | `MirrorLean/Protocol.lean:114` | constInit and paramVars encode unchanged when supplied; applications must set constInit for CONSTANTS specs. |
| C16 | source-supported | `MirrorLean/Client.lean:254`, `MirrorLean/Async.lean:143`, `test/AsyncSupport.lean:77` | Sync and async helpers reject bounds outside [1,100] before writes. |
| C17 | source-supported | `MirrorLean/Async.lean:153`, `test/AsyncSupport.lean:91` | Job IDs are plain opaque strings queryable on independent Connections; source live test reverse-awaits different submitter jobs. |
| C18 | source-supported | `MirrorLean/Async.lean:90`, `MirrorLean/Async.lean:156`, `test/AsyncSupport.lean:102` | await sends optional timeout unchanged and returns status/result, including terminal replies; no hidden timeout/error conversion. |
| C19 | source-supported | `MirrorLean/Async.lean:159`, `test/AsyncSupport.lean:125` | cancelJob explicitly issues cancel_job and returns server result; process termination is server responsibility. |
| C20 | source-supported | `MirrorLean/Async.lean:63`, `MirrorLean/Protocol.lean:405` | Async validate outcome decodes through same ValidateResult.ofJson? as sync registration. |
| C21 | source-supported | `MirrorLean/Async.lean:52`, `test/fixtures/client-conformance/async-replies.json:1` | unknown phase is returned directly to caller; library contains no automatic retry loop. |
| C22 | source-supported | `MirrorLean/Async.lean:134` | No implicit pool; caller sizes connection use. queue-full register_error surfaced as registerFailed, no retry. |
| C23 | source-supported | `MirrorLean/Async.lean:101`, `test/AsyncSupport.lean:102` | No cross-connection ordering assumption; jobs correlated exactly by requested jobId and submission kind. |
| C24 | source-supported | `server-mode/native/mirrorlean_tls.c:183`, `server-mode/native/mirrorlean_tls.c:201` | Opt-in native shim fixes min/max TLS1.3, loads client chain/key, checks key pairing and verifies CA. |
| C25 | confirmed-source-defect | `MirrorLean/ServerMode.lean:111`, `server-mode/native/mirrorlean_tls.c:246` | Normal nonempty hostname/IP selects SAN-only validation, but public serverName=some empty string reaches C branch that entirely skips SAN identity setup. |
| C26 | source-supported-with-deployment-obligation | `MirrorLean/ServerMode.lean:120`, `MirrorLean/ServerMode.lean:212` | Configured direct/registry pin compared case-insensitively before returning Transport; mismatches close. Registry pin is optional in ServiceInfo, so deployments requiring pins must supply them. |
| C27 | source-supported-security-policy | `server-mode/native/mirrorlean_tls.c:77`, `server-mode/Test/ServerMode.lean:377` | POSIX group/other permissions fail before network; owner-only modes such as 0400 are accepted (safe but literal exact-0600 wording is broader than actual policy). OpenSSL supplies wildcard matching. |
| MI1 | source-supported | `MirrorLean/Client.lean:176`, `MirrorLean/ModelInterface.lean:162`, `MirrorLean/ModelInterface.lean:250` | Legacy StateComputer/MirrorError remain separate; only additive negotiated register/register_traces encode extension. |
| MI2 | source-supported | `MirrorLean/ModelInterface/Native.lean:134`, `MirrorLean/ModelInterface.lean:162` | Metadata inert; no descriptor interpreter/load/retrieve APIs. Trusted compiled binding receives model state, app port projection belongs generated binding. |
| MI3 | source-supported-with-build-obligation | `MirrorLean/ModelInterface/Native.lean:134`, `MirrorLean/ModelInterface.lean:171` | GeneratedMetadata embeds digest and normalized contract; runtime validates static metadata and exact-key factory. Compiler-owned generated sources must remain unedited in consumer builds. |
| MI4 | source-supported | `MirrorLean/ModelInterface.lean:167`, `MirrorLean/ModelInterface.lean:211` | Target/computer contract validated before transport; returned binding assertCompatibleConfig checked before replay callbacks. |
| MI5 | source-supported | `MirrorLean/ModelInterface/StrictJson.lean:53`, `MirrorLean/ModelInterface/Validation.lean:6`, `MirrorLean/ModelInterface.lean:48` | Bounded duplicate-aware parser, canonical digest parser, strict allowed/required keys and bounded closed companion contracts. |
| MI6 | source-supported | `MirrorLean/ModelInterface.lean:180` | Registration sends complete contract under inline, no path inference or digest reference. |
| MI7 | source-supported-with-build-obligation | `MirrorLean/ModelInterface.lean:171`, `MirrorLean/ModelInterface.lean:154` | Contract and digest drawn from single generated metadata selection; returned exact digest rechecked. Provenance/model name cannot substitute identity. |
| MI8 | source-supported | `MirrorLean/ModelInterface.lean:226`, `test/ModelInterface.lean:128` | Pure preparation before transport; admitMatched precedes sole withBinding factory path; malformed/missing/denied/wrong digest constructs nothing. |
| MI9 | source-supported | `MirrorLean/ModelInterface.lean:146` | Only matched with supported schema and exact canonical digest; non-null descriptor/descriptorBytes forbidden. |
| MI10 | not-applicable-profile | `MirrorLean/ModelInterface.lean:180` | Lean advertises required verification only; no prefer or fallback API and no silent downgrade. |
| MI11 | source-supported | `MirrorLean/ModelInterface.lean:61`, `MirrorLean/ModelInterface.lean:87` | Immutable array exact four-part BEq key, ambiguity rejects; no range/latest/closest matching. |
| MI12 | source-supported-with-application-freshness-obligation | `MirrorLean/ModelInterface.lean:202`, `MirrorLean/ModelInterface.lean:244` | Factory called once after matched; runner rechecks digest/config before replay. Returning truly fresh application resources remains factory contract. |
| MI13 | source-supported | `MirrorLean/ModelInterface.lean:194`, `MirrorLean/ModelInterface.lean:219`, `test/ModelInterface.lean:162` | Legacy and negotiated share Internal.replay; successful acquisition always scopes single dispose; primary failure wins over disposal/close errors. |
| MI14 | source-supported | `MirrorLean/ModelInterface.lean:15`, `MirrorLean/ModelInterface.lean:119` | Separate NegotiatedError server registration, local model-interface and legacy carriers; stable local codes preserved. |
| MI15 | not-applicable-profile | `MirrorLean/ModelInterface.lean:158` | No dynamic descriptor interpreter/cache profile advertised; strict verify rejects descriptor payload. |
| MI16 | not-applicable-profile | `MirrorLean/ModelInterface.lean:158` | No dynamic descriptor interpreter/cache profile advertised; strict verify rejects descriptor payload. |
| MI17 | not-applicable-profile | `MirrorLean/ModelInterface.lean:158` | No dynamic descriptor interpreter/cache profile advertised; strict verify rejects descriptor payload. |
| MI18 | source-supported-with-C25-defect | `MirrorLean/ModelInterface.lean:119`, `test/ModelInterface.lean:155`, `MirrorLean/ServerMode.lean:111` | Authorization denial terminal with zero factory; no retry dropping negotiation. SAN protection still inherits empty-serverName defect C25. |
| SO1 | not-applicable-profile | `README.md:9` | No native Lean Gate facade advertised; source README explicitly calls Gate evaluation future profile. No sandbox conformance credit claimed. |
| SO2 | not-applicable-profile | `README.md:9` | No native Lean Gate facade advertised; source README explicitly calls Gate evaluation future profile. No sandbox conformance credit claimed. |
| SO3 | not-applicable-profile | `README.md:9` | No native Lean Gate facade advertised; source README explicitly calls Gate evaluation future profile. No sandbox conformance credit claimed. |
| SO4 | not-applicable-profile | `README.md:9` | No native Lean Gate facade advertised; source README explicitly calls Gate evaluation future profile. No sandbox conformance credit claimed. |
| SO5 | not-applicable-profile | `README.md:9` | No native Lean Gate facade advertised; source README explicitly calls Gate evaluation future profile. No sandbox conformance credit claimed. |
| SO6 | not-applicable-profile | `README.md:9` | No native Lean Gate facade advertised; source README explicitly calls Gate evaluation future profile. No sandbox conformance credit claimed. |
| SO7 | not-applicable-profile | `README.md:9` | No native Lean Gate facade advertised; source README explicitly calls Gate evaluation future profile. No sandbox conformance credit claimed. |
| SO8 | not-applicable-profile | `README.md:9` | No native Lean Gate facade advertised; source README explicitly calls Gate evaluation future profile. No sandbox conformance credit claimed. |
| SO9 | not-applicable-profile | `README.md:9` | No native Lean Gate facade advertised; source README explicitly calls Gate evaluation future profile. No sandbox conformance credit claimed. |
| SO10 | not-applicable-profile | `README.md:9` | No native Lean Gate facade advertised; source README explicitly calls Gate evaluation future profile. No sandbox conformance credit claimed. |
| SO11 | not-applicable-profile | `README.md:9` | No native Lean Gate facade advertised; source README explicitly calls Gate evaluation future profile. No sandbox conformance credit claimed. |
| SO12 | not-applicable-profile | `README.md:9` | No native Lean Gate facade advertised; source README explicitly calls Gate evaluation future profile. No sandbox conformance credit claimed. |

## Validation and remaining work

- No local compilation, tests, modelchecker or source edits performed.
- No current-revision runtime qualification inferred from old acceptance records.
- C25 and C13 findings are source-confirmed; bounded remote WSL probes are recommended before describing them as runtime reproduced.
- Application-observer fidelity, CONSTANTS constInit selection, pool sizing, build-generated identity provenance and truly fresh factories require consumer/application evidence.
- Async register_error is interpreted as terminal for the submit attempt per guide section10 and actual Mirrors dispatchAsync; broad C5 wording should be clarified if strict connection-terminal semantics are intended.
- SO12 exists in current guide and was also classified N/A.

Inspected test coverage:
- `/home/nzsn/Repos/MirrorLean/test/Main.lean:372` — framing UTF-8 boundary, normal/mismatch replay, recursive closure, TCP loopback; inspected, not run.
- `/home/nzsn/Repos/MirrorLean/test/AsyncSupport.lean:22` — shared async vectors, wrong IDs/kind, framing failure, EOF/close, optional live cross-owner/cancel; inspected, not run.
- `/home/nzsn/Repos/MirrorLean/test/ModelInterface.lean:128` — admission negatives zero factories, lifecycle primary/disposal failure, registry and bounds, native codecs; inspected, not run.
- `/home/nzsn/Repos/MirrorLean/server-mode/Test/ServerMode.lean:320` — TLS normal, CA/pin/SAN/CN/permissions/TLS1.2 failures and close; inspected, not run.
