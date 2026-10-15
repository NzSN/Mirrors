# Built-in Mirrors CLI client audit — 2026-10-15

Mirrors `c17bae951c4d5bbc5818c2a4f82e2d93d07abc52`. Scope: production `mirror validate`, `trace-gen`, their async helpers and direct/registry TCP/mTLS clients. No SUT replay facade is advertised by these commands. No fresh tests or live model operations ran.

## Source-confirmed findings

- **P2 / C5** — `Shell/TraceCapture.lean:95`: After async job_accepted, await_job receives protocol_error. awaitTraceJob returns .error; run unconditionally invokes cancelOwned. Client writes cancel_job on a flow declared unusable by guide section10. This can add writes/errors after terminal protocol failure and obscures correct ownership cleanup. This is distinct from shared queue-full/register-attempt ambiguity. Smallest intervention: Keep a typed failure/connection-usability distinction and issue cancellation only for locally exhausted polling/caller cancellation while the connection is healthy; terminal protocol errors return directly.
- **P2 / C1** — `Shell/Transport/Tcp.lean:92`: Peer sends a syntactically complete response JSON without finalLF then closes (or read errors). TCP/TLS transport treats incomplete frame as a complete response, so validation/trace-gen may accept a truncated protocol exchange as successful. Bounded payload/UTF8 checks still apply. Smallest intervention: Reject nonempty buffered EOF/error without LF; retain clean EOF and validLF normal path. Add focused rawsocket transport regression and CLI completeJSON-withoutLF negative fixture.
- **P3 / C27** — `Ffi/tls_shim.c:203`: Readable valid client private key has POSIX0400/0700 or special bits with no group/other access. Built-in mTLS client accepts permissions outside the literal0600 contract. This does not establish a confidentiality exposure;400 is narrower access. Smallest intervention: Either enforce exactmode&07777==0600 consistently or explicitly revise the guide if owner-only modes are intended; do not label broad group/other check as literal0600 enforcement.

## Rule matrix

| Rule | Status | Evidence | Assessment |
|---|---|---|---|
| C1 | confirmed-gap | `Shell/Transport/Tcp.lean:92` | Outbound compact JSON+LF is correct. TCP/TLS receivers accept EOF/error buffered payload without LF as a complete message; mandatory receive framing gap. |
| C2 | implemented-static | `Shell/Transport/Stdio.lean:40` | Shared65535-byteUTF8 validation; TCP/TLS cap each raw prefix before decoding; max scratch65536 means bounded two-chunk temporary. validate/trace-gen registration preflight checks exact compact final bytes. |
| C3 | implemented-static | `Shell/Client.lean:25` | Codec.decodeMirror dispatches proto_step; additive outer fields ignored; TraceCapture separately retains raw ITF metadata. |
| C4 | implemented-static | `Shell/Client.lean:38` | Validation sends register_validate/async; TraceCapture sends register_trace_gen/async before awaiting its accepted job. |
| C5 | confirmed-gap | `Shell/TraceCapture.lean:95` | Validation exits terminally, but async trace capture sends cancel_job after any await error including received protocol_error. Shared async registration-attempt C5 wording discrepancy remains separate. |
| C6 | implemented-scoped-static | `Shell/Cli.lean:700` | One connection per CLI process; normal EOF/error becomes infrastructure failure and process exit closes descriptors. Transport record has no public explicitclose capability; reusable helpers are not advertised as independent long-lived SDK. |
| C7 | implemented-with-runtime-limit | `Shell/Transport/Tls.lean:323` | No heartbeat or protocol liveness assumption. TLS client sets SO_RCVTIMEO5000 before handshake and leaves it set; shim retries WANT_READ/WANT_WRITE. Exact silent-established-peer timing behavior not freshly checked. |
| C8 | not-applicable | `Main.lean:26` | Built-in validate/trace-gen clients do not implement SUT replay. tools/CounterSpec is a test client, not production CLI replay. |
| C9 | not-applicable | `Shell/Client.lean:38` | No report_state/StateComputer flow in these built-in CLI commands. |
| C10 | not-applicable | `Shell/Client.lean:44` | No replay mismatch-producing flow advertised; unexpected reply returns failure, never waits for all_steps_done. |
| C11 | not-applicable | `Shell/TraceCapture.lean:31` | No SUT report-state encoder; captured ITF is parsed/preserved by trace capture. |
| C12 | not-applicable | `Shell/Cli.lean:721` | numTraces and bound are requested generation controls; no SUT replay step counts assumed. |
| C13 | implemented-static | `Shell/Apalache/SpecSource.lean:269` | resolveClientSources uses captured parsed SourceUnits and recursive EXTENDS/INSTANCE closure, explicit deps/module identity and source limits. CLI final compact registration preflight obeys65k. |
| C14 | implemented-static | `Shell/Cli.lean:672` | ApalacheConfig uses options and Codec encoder; absent/null Haskell semantics handled server-side. CLI supplies default bound10/invariant empty. |
| C15 | application-obligation | `Shell/Cli.lean:334` | --cinit propagates constInit. Arbitrary specs declaring CONSTANTS require caller to choose valid initializer; CLI cannot infer it. |
| C16 | implemented-server-rejected | `Shell/Cli.lean:326` | validate bound is Nat but not locally capped; registration reaches server which rejects outside[1,100] synchronously. Client preflight bound check not required by this rule. trace-gen has separate profile bounds. |
| C17 | implemented-scoped-static | `Shell/Client.lean:86` | Async workflows retain submitting connection until terminal result; not detached submission and no crossconnection facade. Exact accepted job ID carried into waits. |
| C18 | implemented-static | `Shell/Client.lean:57` | await_job timeout30; pending/running statuses recurse, not treated as errors. Trace capture has explicit maxPolls budget. |
| C19 | implemented-scoped-static | `Shell/TraceCapture.lean:43` | Trace capture cancels owned job on failure/budget exhaustion, but overbroad terminal-error cancellation has C5 finding. Validate has no separate cancellation command; CLIexit triggers ownerdisconnect semantics. |
| C20 | implemented-static | `Shell/Client.lean:64` | Async .validate result uses same Codec.ValidateResult/reportValidate as sync; infraError remains failure and genTraces kind rejected. |
| C21 | implemented-static | `Shell/Client.lean:71` | Unknown or evicted exits immediately, never retry-looped. Trace capture also errors immediately, though cancellation cleanup sends an unnecessary followup. |
| C22 | implemented-scoped-static | `Shell/Cli.lean:689` | No connection pool: one selected transport; register_error returns infrastructure failure. No hidden retry of full queue. |
| C23 | implemented-static | `Shell/Client.lean:62` | Only one owned job polled per invocation; every status/result correlation checked, no assumption across jobs/connections. |
| C24 | implemented-static | `Ffi/tls_shim.c:307` | OpenSSL min=maxTLS1.3; client context loads cert/key and verifies CA; no-certificate server handshakes fail. |
| C25 | implemented-static | `Ffi/tls_shim.c:471` | X509_VERIFY_PARAM name or IP identity with NEVER_CHECK_SUBJECT prevents CN fallback. |
| C26 | implemented-static | `Shell/Transport/Tls.lean:354` | PeerSHA256 checked case-insensitively before returning usable Transport; CLI explicit pin overrides registry advertised pin. |
| C27 | confirmed-literal-conformance-gap | `Ffi/tls_shim.c:203` | POSIX key check only rejects group/other access; accepts0400,0700 and special ownerbits, while guide says exactly0600. Windows ACL exception explicit. |
| MI1-MI18 | not-applicable | `Shell/Cli.lean:677` | Built-in validate/trace-gen clients send no negotiation extension; guide explicitly limits modelInterface to register/register_traces. Server/compiler MI support does not imply a negotiating validation client. |
| SO1-SO12 | not-applicable | `Main.lean:26` | No built-in CLI shared Gate evaluator advertised for validate/trace-gen/discovery. Gate support in optional language facades is reviewed separately. |

## Limits

- Read-only static review of shipped CLI/client helper paths; no local/remote builds/tests, model operations or service calls.
- tools/CounterSpec.lean is test scaffolding, not a production full SUT replay SDK.
- No current-source runtime acceptance is claimed from test presence or historical server/CLI gates.
- TLSclient established socket timeout is retained and shim retries WANT_READ; platform timing behavior needs a targeted remote probe before asserting an idle timeout failure.
- CLI process exit owns final descriptor teardown; reusable transport-close API and embedding semantics were not assessed as an independently advertised SDK.
- Remote destPath capture uses explicit mapping with pinnedTLS admission; absent that mapping server paths remain receipt data.

All findings are source-confirmed paths; runtime reproductions remain unrun. The independent shared C5/section10 async registration-attempt discrepancy is recorded in rust.md; it is not used to recommend closing every borrowed async connection.
