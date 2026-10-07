# Approved DPM usability features

Date: 2026-10-07
Status: first slice F1/F2 implemented and source accepted; F3–F5 approved
follow-ons. Design below was frozen before implementation.
[First-slice evidence](dpm-usability-evidence-20261007/README.md) records exact
source/helper/input identities and honest qualification limits.

The user approved five recommendations after the completed DPM and M5 profiles:
generated integration kit, unified counterexample timeline, schedule-aware
reduction, installed cross-language CLI and experimental synchronization wrappers.
Start with features 1 and 2 as recommended. Features 3–5 are approved follow-on
slices with distinct contracts/exit gates below, not claimed implemented by a plan.
Broader M4 stays separate. Preserve the concurrent documentation synchronization,
all frozen evidence, unrelated Rust edit and editor caches. No commit/push.

## Module interface and first delivery

The kit is a compiler publication mode, not another scheduler or model interpreter.
`model_interface_gen generate-dpm --lock FILE --mapping FILE --target TARGET --out DIR`
loads the existing verified lock and a strict bounded application-reviewed mapping.
`check-dpm` compares expected outputs read-only. Targets are C++v1/v2,
async-ECMAv1/v2 and Rustv1/v2; synchronous ECMA and Lean have no accepted DPM
execution profile and reject before publication. Ordinary generation stays byte
stable. The compiler publishes ordinary bindings plus a generated schedule helper,
canonical mapping/identity metadata and an integration example through its existing
ownership/locking/atomic replacement machinery. Application behavior is copied
and implemented outside generated owned files, never inferred or overwritten.

`mirrors.dpm-kit-plan/v1` binds the model semantic digest, declared actor/operation
pairs and every transition action ID. Each action selects a fixed declared actor
or an explicit string-typed generated input ID, and declares its destination
checkpoint. It is data, never an expression, source path, shell command or code.
Bound actors 64, mappings 256, identifiers 128, and whole input using compiler strict
JSON bounds. Reject duplicate/unknown fields/IDs, missing/extra actions, unknown
actors/inputs, non-string actor inputs, unsupported target and wrong model identity.
The application owns binary identity, factories, actual hooks and observation.
A generated helper resolves an action+actor argument to SDK `Step`; it validates
actor membership and cannot create a SUT or silently repair a mismatched schedule.
Mapping metadata/hash and lock semantics bind the artifact; runtime comparison
continues through the ordinary generated binding and existing SDK session.

The timeline is read-only diagnostic orchestration. It consumes existing
`mirrors.scheduled-comparison/v1` receipts for C++, ECMA and Rust, validates bounded
structure/event order/identity and produces `mirrors.dpm-timeline/v1` JSON plus a
terminal table. Show admitted step, accepted permit, actual arrival, observed
state, model action/checkpoint relation where exact, genuine comparison/mismatch
and cleanup separately. Missing action/source/model attribution stays unknown.
Rust/C++ receipts without explicit stateIndex cannot manufacture a failing row;
retain mismatch globally unless a consistent event/observation index establishes
it. Repeated initialization produces separate execution sections.
A mismatch followed by successful cancellation cleanup is still a mismatch, not
an application cancellation diagnosis. Truncated evidence, incomplete cleanup,
unknown verdict, malformed ordering or source/output tamper never become a pass.
No receipt is rewritten; raw inputs remain hash-bound. Differences use actual
expected/actual values and retained ordered hints, not a new model interpreter.

## Ownership and architecture

Pure mapping types/admission live in Core; strict mapping/report codecs in Codec;
kit emission/publication and CLI in Shell/tools. The timeline is a host-side
Python diagnostic module under tools/deterministic-scheduling; no wire or SDK
report-schema change is needed. Use one seam for validation/structured reports
and a separate renderer; CLI callers and tests cross that same seam.

The first real vertical slice regenerates C++/ECMA/Rust Counter bindings+helpers
from the checked lock, compiles native helpers and uses them in a fresh consumer.
It drives actual workers via existing binding sessions and detects a genuine
mutation with the existing Mirrors comparison path. Use retained counter oracles
only when explicitly hash-matched; no fresh model-check claim is inferred.
Native WriteSentry mapping is a separate richer multi-phase adapter; the initial
kit's one-transition/one-interval contract does not claim automatic native binding.

## Follow-on slices and acceptance

| Feature | Contract/exit gate | State |
| --- | --- | --- |
| F1 Generated kit | All three language helpers compile; real generated replay; static admission negatives; readonly freshness; ownership rollback/unrelated files; v1 bytes stable | Source accepted: six target modes and three actual SDK helper/seed compiles |
| F2 Timeline | Actual pass/mismatch/cleanup/repeated/native receipts render; input bytes unchanged; malformed/tampered/incomplete controls; no invented model attribution | Source accepted: real match/mismatch plus integrity and unknown-attribution controls |
| F3 DPM reducer | Reduce inputs/actors/preemptions only through valid reconstructed schedules; fresh replay and same mismatch+cleanup; deterministic budgets and honest minimality scope | Approved follow-on |
| F4 Installed CLI | Package a standard replay/explore/report interface around existing SDK runners; explicit installed artifacts/dependencies; source-hidden offline consumer and tamper/refusal gates | Approved follow-on |
| F5 Synchronization wrappers | Separate experimental profile for controlled blocking/resources; explicit enabledness and ownership; two real abstractions and tests preserving intended lock/queue semantics; no unmodified-binary/preemption claim | Approved research/prototype follow-on |

F3 must preserve actor-local chains; dropping arbitrary intervals may be unrealizable.
F4 reuses existing replay/explorer/timeline rather than changing wire messages.
F5 cannot simply park an actor while holding a lock needed by the next permitted
actor. The coordinator must account for blocked/enabled actors before claiming a
wrapper can explore synchronization operations. CHESS-style API shimming is a
reference design, not current implemented support.

## Validation and reporting

Extend focused Core/codec/compiler/CLI gates and register them in Lake/local gates.
Compile helpers with actual SDKs and run genuine Counter comparison; timeline tests
use immutable retained receipts plus explicit malformed controls. Report source,
installed acceptance and qualification separately. Source/tool changes invalidate
future current-source qualification; the old C094271… remains its frozen record.
Do not rerun/start a model checker locally or rewrite historical acceptance files.
