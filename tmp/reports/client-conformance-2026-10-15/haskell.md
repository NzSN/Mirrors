# Haskell reference client audit — 2026-10-15

Folder `ModelMirros` (repository name ModelMirrors), HEAD `5ee414ee16b8aba50ceb480ac8013a56165272bb`. Scope: shipped validate CLI, public Protocol.Client and Stdio/TCP/mTLS transports. No tests, builds, probes or model operations ran.

## Findings

- **P2 / C2** — `src/Protocol/Transport/Core.hs:15`: Send an encoded registration/state above 65,535 bytes, or receive an unterminated peer line growing beyond the limit. Oversized output reaches the Lean server and fails; malicious or misconfigured peers can grow receive memory without bound before JSON parsing. Fix: Centralize final encoded send validation and use bounded raw-byte JSONL readers before Aeson. Test exact ASCII/multibyte boundaries and oversized unterminated lines.
- **P2 / C17/C23** — `src/Protocol/Client.hs:142`: A query/await/cancel for job A receives JobStatus/JobResult for job B, or a validation submission receives a gen-traces acceptance. Public helpers accept unrelated status/outcome; validation can report another job verdict. Conforming servers normally echo the ID, so this is a defensive protocol-failure path. Fix: Compare every returned job ID with the requested ID and require the expected accepted kind. Return a protocol error without continuing on a mismatch.
- **P3 / C27** — `src-tls/Protocol/Transport/Tls.hs:239`: A valid client key has mode 0400, 0700, or special bits with no group/other access. Accepted modes violate the literal 0600 guide contract. No confidentiality exposure is claimed for owner-only access. Fix: Choose exact 0600 enforcement or document the intended private-only policy. Exact enforcement should compare mode & 07777 with 0600.
- **P3-compatibility / C19/section6replygrammar** — `src/Protocol/Client.hs:183`: A legal peer answers cancel_job with a matching terminal job_result. cancelJob returns UnexpectedMessage instead of accepting the acknowledgement. Current Haskell and Lean servers return JobStatus, so this is a grammar compatibility gap rather than a current-server regression. Fix: Accept matching JobResult as a terminal acknowledgement, preserving ID correlation and malformed-reply failure.

C26 case-sensitive pin comparison is a documented historical reference exception. C25 SAN-only verification remains unverified: the source uses dependency defaults and no CN-only negative client fixture was found. Server divergences are not presented as client bugs.

## Rule matrix

| Rule | Status | Evidence | Assessment |
|---|---|---|---|
| C1 | partial-static | `src/Protocol/Transport/Core.hs:15` | Aeson encodes JSON objects and transports append LF. TLS splits on LF; Handle getLine APIs hide terminator status, so explicit rejection of partial final EOF frames is not established. Aeson validates UTF-8 while decoding. |
| C2 | confirmed-gap | `src/Protocol/Transport/Core.hs:15` | No 65,535-byte final send checks. TCP/Stdio hGetLine/getLine are unbounded; TLS concatenates its IORef buffer without a cap until LF. Applies to CLI and public library. |
| C3 | implemented-static | `src/Protocol/Format/Json.hs:255` | FromJSON dispatches proto_step and required fields while ignoring additive outer object keys. |
| C4 | implemented-static | `src/Protocol/Client.hs:53` | Each replay, validation, generation and exploration helper sends registration first. Existing-job controls do not register. |
| C5 | implemented-with-shared-contract-discrepancy | `src/Protocol/Client.hs:279` | Stepping returns immediately on mismatch and terminal errors; no further internal flow writes. Reusing caller-owned transport is caller responsibility. Shared C5 async registration wording conflicts with guide section 10 and server behavior. |
| C6 | implemented-scoped-static | `app/Main.hs:155` | The validate CLI brackets transport with tcpClose/tlsClose and maps EOF/errors to exit 2. Library ownership remains caller-managed. tlsClose sends best-effort bye; underlying socket release is documented at process exit. |
| C7 | implemented-static | `src-tls/Protocol/Transport/Tls.hs:263` | No protocol heartbeat or idle deadline assumed by the client library; blocking await supports indefinite waits. |
| C8 | implemented-static | `src/Protocol/Client.hs:279` | InitialState/NextStep dispatches the handler, sends exactly one ReportState, then waits for StepOk or mismatch. |
| C9 | application-obligation | `src/Protocol/Client.hs:39` | Application clientHandler returns the full observable Map. Arbitrary observation fidelity remains application responsibility. |
| C10 | implemented-static | `src/Protocol/Client.hs:292` | handleStep returns Left on StepMismatch immediately without waiting for AllStepsDone. Historical Haskell SERVER trailing-done behavior is not a client defect. |
| C11 | implemented-static | `src/Apalache/Types.hs:230` | Unbounded Integer is emitted as #bigint decimal; integral JSON numbers are accepted. Malformed ITF defense was not freshly verified. |
| C12 | implemented-static | `src/Protocol/Client.hs:279` | stepLoop is message-driven, without hardcoded step counts. |
| C13 | caller-supplied-closure | `app/Main.hs:139` | CLI reads root spec plus explicit --dep files only. It does not advertise automatic recursive resolution. Caller must include the full EXTENDS/INSTANCE closure. The complete send still lacks C2 bounds. |
| C14 | implemented-static | `src/Protocol/Format/Json.hs:15` | Existing Haskell optional encoders send null or omit by message, per the documented oracle asymmetry. |
| C15 | application-obligation | `app/Main.hs:146` | --cinit propagates constInit; caller selects a valid initializer for CONSTANTS. |
| C16 | implemented-server-rejected | `src/Protocol/Client.hs:102` | Bound is passed to registration with no local cap. Server rejects out-of-range values synchronously; this rule does not require local validation. |
| C17 | confirmed-correlation-gap | `src/Protocol/Client.hs:142` | IDs can cross connections, but poll/await/cancel discard returned IDs. Submission also ignores accepted kind. A foreign outcome can be associated with the requested job. |
| C18 | implemented-static | `src/Protocol/Client.hs:153` | awaitJob preserves optional timeout and re-awaits nonterminal status. A terminal status without result makes one final poll, then errors. |
| C19 | partial-compatibility-gap | `src/Protocol/Client.hs:178` | Explicit cancel helper accepts only JobStatus, whereas guide reply grammar also permits JobResult. Both current Haskell and Lean servers return status on cancel; no current-server failure is asserted. |
| C20 | implemented-static | `src/Protocol/Client.hs:199` | runClientValidateAsync unwraps JobValidateDone into the same ValidateResult as sync. Infrastructure errors remain errors. |
| C21 | implemented-static | `src/Protocol/Client.hs:167` | Unknown causes one extra query and then terminal error. There is no indefinite unknown retry loop expecting the job to appear. |
| C22 | implemented-scoped-static | `src/Protocol/Client.hs:116` | No automatic pool. register_error maps to Left, including a full queue. Applications own connection limits. |
| C23 | confirmed-correlation-gap | `src/Protocol/Client.hs:157` | No explicit completion ordering assumption, but dropping returned IDs fails to correlate independent jobs. See C17 finding. |
| C24 | implemented-static | `src-tls/Protocol/Transport/Tls.hs:252` | TLS13 is the only supported version; client credentials and CA are loaded; certificate-request hook returns the credential. |
| C25 | dependency-runtime-unverified | `src-tls/Protocol/Transport/Tls.hs:247` | Uses defaultParamsClient host with CA. No explicit SAN-only policy hook is present. Dependency implementation is unavailable locally; CN-only rejection is not established. Wildcard differences are documented. |
| C26 | documented-reference-exception | `src-tls/Protocol/Transport/Tls.hs:356` | Peer SHA256 pin is checked before protocol but compared as case-sensitive Text. Uppercase valid pins fail. Guide section 10 explicitly records this Haskell difference. Explicit registry pin precedence is correct. |
| C27 | confirmed-literal-conformance-gap | `src-tls/Protocol/Transport/Tls.hs:239` | POSIX check forbids only group/other access (077). It accepts 0400, 0700 and special bits rather than literal 0600. Windows ACL exception is explicit. |
| MI1-MI18 | not-applicable | `src/Protocol/Client.hs:1` | Historical reference client advertises legacy protocol only; no compiled verification or descriptor API. |
| SO1-SO12 | not-applicable | `README.md:39` | No native Haskell Gate control facade is advertised. |

## Limits

- Read-only source audit. No builds, tests, probes, live peers or model operations invoked.
- Haskell reference is a historical oracle, not a newly qualified framework profile or current package acceptance.
- Haskell SERVER trailing AllStepsDone after mismatch and stdio async error-tag differences are not client bugs.
- Case-sensitive C26 pin comparison is an explicitly documented reference exception. Lowercase pins work and wrong pins fail before protocol.
- C25 SAN-only behavior needs dependency-source inspection or a CN-only certificate fixture; no CN fallback defect is asserted.
- Complete inline dependency closure, CONSTANTS initializer, observation fidelity and transport ownership remain caller responsibilities.
- MI and Gate SO profiles are not advertised.
