# MirrorRust client-guide audit — 2026-10-15

Source: MirrorRust `5049e99886a3d1f775e60190478c26e39c9aefc9`; optional Gate `4a8d0d361589059ad72fe52e05789f302b4b65c8`. Read-only static audit against all 27 C rules, 18 MI rules, and 12 SO rules in the current 1,191-line guide. No builds, tests, live services or model checks ran.

## Shared contract discrepancy

**P2 documentation/contract / C5 versus section 10 — async register_error connection lifetime is inconsistent.** `src/client.rs:249`, `:284`, and `:320` return `RegisterFailed` while retaining their borrowed transport; the queue-pressure smoke deliberately calls `cancel_job` afterward (`tests/server_mode_smoke.rs:899`). Literal C5 says register_error ends the session and requires a new connection. However, guide section 10 (`client-implementation-guide.md:716`) calls register_error terminal only for that register attempt; server `Shell/Mirror/Session.lean:900–904` sends queue-full register_error then returns true to continue dispatch.

This is a confirmed shared documentation/implementation discrepancy, not a confirmed Rust runtime bug. Automatically closing the owner connection can cancel and evict other jobs under C6. Smallest intervention: clarify C5's async registration-attempt exception and align tests after deciding the shared contract. Do not patch all async errors to close without accounting for server behavior and owner-job lifetime.

## Source assessment

Bounded raw UTF-8 framing, terminal synchronous replay/mismatch handling, recursive inline closure construction, exact POSIX key mode, TLS1.3 client authentication/SAN/pinning, canonical compiled negotiation, exact registry matching, explicit fallback, zero pre-admission callbacks and once-only binding disposal all have implementation and checked-in regression evidence. Fresh runtime acceptance remains unverified. Constants, manual sources, state fidelity and metadata provenance retain application responsibility.

Dynamic descriptor negotiation is unadvertised, so MI15–MI17 do not apply. Optional Gate support is the Linux control-v1 Rust SDK plus handwritten Counter acceptance fixture and caller-supplied binding seam. Historical owned/attached × Node/Rust results do not establish a generic generated Rust Gate client or current-source full qualification. Agent-host disclosure/tool mediation is an external obligation.

## Rule-by-rule evidence

| Rule | Status | Evidence | Assessment |
|---|---|---|---|
| C1 | implemented-static | `MirrorRust/src/transport.rs:283` | Shared JSONL writer appends LF; bounded UTF-8 receiver; protocol encoders emit objects. |
| C2 | implemented-static | `MirrorRust/src/transport.rs:299` | Receiver uses Read::take(65537); checks raw bytes before protocol decoding. Send checks String byte length <=65535 before writing. tests/transport.rs exact and multibyte boundaries. |
| C3 | implemented-static | `MirrorRust/src/protocol.rs:623` | Dispatches string proto_step and reads required keys without rejecting additive outer fields. |
| C4 | implemented-static | `MirrorRust/src/client.rs:95` | Replay, generation and validation helpers register first. Job helpers query existing IDs directly and reject stdio async before writing. |
| C5 | shared-contract-discrepancy | `MirrorRust/src/client.rs:249`; guide:716; server Session.lean:900 | C5 blanket-close wording conflicts with section10 and the server async dispatch loop. Rust intentionally retains the connection for other owned jobs. |
| C6 | implemented-static | `MirrorRust/src/transport.rs:242` | Consumed replay transports close on completion and error; close/Drop tolerate network NotConnected. Async owner lifetime remains caller-managed. |
| C7 | implemented-static | `MirrorRust/src/transport.rs:170` | Only handshake read/write timeouts are installed and cleared after handshake; no protocol heartbeat or established idle timeout. |
| C8 | implemented-static | `MirrorRust/src/client.rs:445` | Initial and action branches each compute then send one report_state. |
| C9 | application-obligation | `MirrorRust/src/client.rs:26` | StateComputer returns observable State; full state is encoded. SDK cannot prove that arbitrary application observations are complete or truthful. |
| C10 | implemented-static | `MirrorRust/src/client.rs:465` | StepMismatch returns immediately, preserving hints; no trailing all_steps_done wait. |
| C11 | implemented-static | `MirrorRust/src/protocol.rs:11` | Value::Int is BigInt and clean encoder uses #bigint; tests/protocol.rs:506 round-trips beyond native integer precision. |
| C12 | implemented-static | `MirrorRust/src/client.rs:442` | Replay dispatch loop continues until terminal response rather than a fixed step count. |
| C13 | implemented-static | `MirrorRust/src/spec.rs:154` | spec_from_files builds recursive EXTENDS/INSTANCE closure, handles multiline/comments, canonical-path cycles and ambiguity. Complete registration limit enforced by Transport.send; manual ApalacheSpec remains caller responsibility. |
| C14 | implemented-static | `MirrorRust/src/protocol.rs:190` | Optional config values use Option and skip None; caller chooses concrete required/default fields. Does not implement server config decoding. |
| C15 | application-obligation | `MirrorRust/src/protocol.rs:198` | const_init is exposed; README quickstart and tests/server_mode_smoke.rs:517 explicitly supply CInit for Counter. Arbitrary application CONSTANTS require caller configuration. |
| C16 | implemented-static | `MirrorRust/src/client.rs:201` | Sync and async validation preflight bounds [1,100] before writes. |
| C17 | implemented-static | `MirrorRust/src/client.rs:333` | Job ID supplied by caller, no connection-local ID assumption. tests/server_mode_smoke.rs:730 covers cross-connection owner and observer lifetimes. |
| C18 | implemented-static | `MirrorRust/src/client.rs:345` | await_job accepts optional timeout and returns Status versus Result without implicit retry or timeout conversion. |
| C19 | implemented-static | `MirrorRust/src/client.rs:363` | Explicit cancel_job helper; tests/server_mode_smoke.rs:823 covers running cancellation; process termination remains server authority. |
| C20 | implemented-static | `MirrorRust/src/protocol.rs:306` | JobOutcome::Validate reuses SpecResult; live-smoke source compares async result to sync validation. No fresh live run. |
| C21 | implemented-static | `MirrorRust/src/protocol.rs:685` | Unknown is a distinct phase returned once; library has no unknown retry loop. Smoke loop exits immediately on Unknown. |
| C22 | implemented-static | `MirrorRust/src/client.rs:249` | Full queue maps to RegisterFailed; no pool is imposed by library. Terminal connection handling has separate C5 gap. |
| C23 | implemented-static | `MirrorRust/src/client.rs:314` | Replies must correlate exact job IDs; independent queries do not assume completion order; reverse-order await smoke present. |
| C24 | implemented-static | `MirrorRust/src/transport.rs:159` | rustls configured TLS13 only with client certificate/key and CA roots. TLS12/client-auth failure smoke present; not rerun. |
| C25 | implemented-static | `MirrorRust/src/transport.rs:165` | Default rustls/webpki server-name verifier uses SAN, DNS/IP ServerName; CN-only rejection smoke at tests/server_mode_smoke.rs:354. |
| C26 | implemented-static | `MirrorRust/src/transport.rs:189` | SHA256 leaf pin compared after handshake and before Transport returned/protocol bytes. Registry precedence preserves pin_override then caller pin then candidate pin in registry.rs:130. |
| C27 | implemented-static | `MirrorRust/src/transport.rs:345` | POSIX mode requires mode&07777 ==0600 before credential load. Transport tests reject readonly/group/special bits; non-Unix uses ACL/platform policy. |
| MI1 | implemented-static | `MirrorRust/src/client.rs:95` | Legacy encoders have no modelInterface; legacy Error API retained; tests/legacy_compatibility.rs:23 tests signature and wire. |
| MI2 | implemented-static | `MirrorRust/src/model_interface.rs:129` | Metadata is inert JSON/digest, exact local factory registry; no received executable retrieval or dynamic interpreter. |
| MI3 | implemented-static | `MirrorRust/src/model_interface.rs:1126` | Complete metadata and canonical semantic digest select compiled binding. Generated-file provenance/freshness is compiler/application-owned and needs coordinated gate. |
| MI4 | implemented-static | `MirrorRust/src/model_interface.rs:1557` | Contract-version preflight and post-creation assert_compatible_config precede computer/observer replay; compatibility function is binding-owned. |
| MI5 | implemented-static | `MirrorRust/src/model_interface.rs:587` | Strict lexical duplicate-aware, byte/depth/node-limited parser; nested closed-shape contract, negotiation and failure checks. Additive outer fields retained. |
| MI6 | implemented-static | `MirrorRust/src/model_interface.rs:1140` | Request always includes complete contract inline; no contract reference or companion inference. |
| MI7 | implemented-static | `MirrorRust/src/model_interface.rs:1126` | make_verify_request obtains digest and validated contract from same GeneratedModelInterface. Metadata authenticity remains trusted build responsibility. |
| MI8 | implemented-static | `MirrorRust/src/model_interface.rs:1531` | First reply strictly decoded before factory; all failures close consumed transport; negative tests require zero callbacks. |
| MI9 | implemented-static | `MirrorRust/src/model_interface.rs:1411` | Compiled verify accepts only matched accepted descriptor schema and exact parsed digest, rejects descriptor payload/bytes and inappropriate statuses. |
| MI10 | implemented-static | `MirrorRust/src/model_interface.rs:1377` | Prefer fallback requires explicit separate factory; malformed/digest mismatch fail; selected negotiated factory is not reused implicitly. |
| MI11 | implemented-static | `MirrorRust/src/model_interface.rs:213` | Exact four-field registry match; zero/multiple matches yield classified errors without invoking factories. |
| MI12 | implemented-static | `MirrorRust/src/model_interface.rs:1532` | Fresh creation after checked authority; binding digest and effective config rechecked before shared replay. Factory must itself return fresh binding. |
| MI13 | implemented-static | `MirrorRust/src/model_interface.rs:1553` | Shared run_stepping_loop; catch_unwind surrounds binding validation/replay; one dispose attempted, primary failure preserved. |
| MI14 | implemented-static | `MirrorRust/src/model_interface.rs:22` | Separate NegotiatedError::ModelInterface stable codes, Registration structured errors, Legacy preserves legacy variants. |
| MI15 | not-applicable | `MirrorRust/src/model_interface.rs:1411` | Dynamic descriptor profile not advertised or implemented; compiled path rejects resolved/not_modified. |
| MI16 | not-applicable | `MirrorRust/src/model_interface.rs:1484` | No dynamic descriptor cache or ifNoneMatch path. |
| MI17 | not-applicable | `MirrorRust/src/model_interface.rs:1484` | No dynamic handler interpreter profile; static generated adapter is a separate contract. |
| MI18 | implemented-static | `MirrorRust/src/model_interface.rs:1308` | Authorization register_error is terminal; no negotiation-dropping retry. TCP/mTLS identity and pin handling remain independent transport paths. |
| SO1 | implemented-scoped-static | `MirrorGate/integrations/mirrorrust/src/lib.rs:386` | Facade delegates prepare/authorize/acquire/cleanup to Gate Rust SDK; no MirrorECMA evaluator prerequisite. Scope is optional control-v1 Counter fixture and caller-supplied binding seam. |
| SO2 | implemented-scoped-static | `MirrorGate/sdk/rust/src/transport.rs:367` | Owned stdio startup versus attached Unix; attached close reports NotOwned; process shutdown belongs only to owned child. |
| SO3 | implemented-scoped-static | `MirrorGate/integrations/mirrorrust/src/lib.rs:509` | Separate Gate control, Mirrors stdio negotiated runner and managed public worker channel. |
| SO4 | implemented-scoped-static | `MirrorGate/integrations/mirrorrust/src/lib.rs:306` | Trusted Counter binding projects declared Initialize/Tick and Stride and observes Count. Does not send raw model messages/state/credentials to worker. Arbitrary user binding still trusted. |
| SO5 | implemented-scoped-static | `MirrorGate/integrations/mirrorrust/src/lib.rs:515` | Worker authorization/acquisition/connect occurs only inside post-match factory, after prepare/admission. |
| SO6 | implemented-scoped-static | `MirrorGate/integrations/mirrorrust/src/lib.rs:461` | Gate prepare snapshot/challenge used for authorize; manifest digest/model revision/runtime/submission remain separate inputs. Supervisor implementation itself outside this Rust audit. |
| SO7 | implemented-scoped-static | `MirrorGate/integrations/mirrorrust/src/lib.rs:95` | Gate code families retained as mirrorgate.* codes; negotiated/registration/legacy mismatch preserved; no raw subprocess isolation fallback. Error classification accuracy requires live failure gate. |
| SO8 | implemented-scoped-static | `MirrorGate/integrations/mirrorrust/src/lib.rs:205` | worker.finish and session.close use authoritative cleanup; confirms Closed/Succeeded/no resources. Primary result retained if cleanup also fails. Control close checked separately. |
| SO9 | implemented-scoped-static | `MirrorGate/sdk/rust/src/control.rs:442` | Connection/session-bound opaque authorizations/reservations; Unix socket verification validates filesystem identity/owner/mode. No remote control profile advertised. |
| SO10 | external-obligation | `MirrorGate/integrations/mirrorrust/README.md:6` | Library trusted evaluator can return private mismatch detail; host must restrict tools/context and disclosure. Counter privacy canary historical tests do not prove arbitrary host blindness or observation fidelity. |
| SO11 | implemented-scoped-static | `MirrorGate/sdk/rust/src/control.rs:329` | Control-v1 hello capabilities, request correlation, bounded strict codecs, opaque session handles, cleanup outcomes and shared fixtures present. Does not advertise control-v2 managed hosting. |
| SO12 | historical-evidence-only | `MirrorGate/docs/rust-evaluator-sdk-status.md:63` | Historical real 20-row owned/attached x Node/Rust matrix and reference-facade parity documented. Not rerun for current source, not generic generated Rust Gate acceptance, no current framework qualification credit. |

## Validation limits

- Read-only static audit; no local or remote builds/tests/model operations/services invoked.
- No blanket current-source conformance acceptance. Source paths and checked-in tests establish implementation intent, not current backend/runtime success.
- Application state fidelity, constInit selection, complete manual inline sources, trusted metadata provenance, and agent-host mediation remain explicit application/operator obligations.
- Gate supervisor/backend implementation and full runtime shim code were not re-audited as part of Rust facade review.
- Dynamic descriptor profile MI15-MI17, explorer facade, remote Gate control, control-v2 Rust hosting, other host backends and generic generated Rust Gate application acceptance are not advertised by these scoped entrypoints.

The JSON companion lists normal, failure and integration-edge regression sources. Those tests were inspected, not executed.
