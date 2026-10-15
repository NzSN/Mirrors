# Proposed CLI framing and session fixes: F5, F6, D1

Planning only, inspected at Mirrors `c17bae951c4d5bbc5818c2a4f82e2d93d07abc52`.
No implementation, build, test or model operation performed. Other owners share
the workspace. Future compilation and runtime checks belong on remote Ubuntu
WSL; this coordinator performs only lightweight edits/review.

## 1. Settle D1 before changing client lifetime policy

**Recommend request-context semantics.** Keep the current recoverable async
submission behavior. `Shell/Mirror/Session.lean:900–912` emits `register_error`
and returns `true` after a rejected `register_validate_async` or
`register_trace_gen_async`; the failed attempt adds no job to `mine`. A queue-full
or bad-bound rejection must not kill already accepted jobs on that connection.

Proposed contract table for `Docs/client-implementation-guide.md` C5/section 10,
`Docs/interface-reference.md` sections 4/error handling and
`Docs/async-enablement-design.md` section 2:

| Context | Outcome | Continuation |
|---|---|---|
| Async submission on a server-mode connection | `register_error` | Attempt is over; connection and earlier accepted jobs remain usable. No new job ID was issued. Caller may independently query/cancel existing jobs or explicitly submit a new attempt. |
| Accepted async job | `job_result`, cancelled/unknown status | That job or lookup is terminal; connection may operate on other jobs. Never poll unknown expecting it to appear. |
| Replay/validate-only/synchronous generation/negotiated replay | Existing flow-terminal result/error | Stop the flow; no further flow writes; use a fresh connection for a new flow. A required negotiation failure cannot authorize fallback. |
| Any flow | malformed framing/JSON, transport failure, `protocol_error` | Connection is unusable; do not send cancellation or another flow message on it. Existing server end-session cleanup applies. |

Classify by known operation/phase, not human-readable `error` text. Retain wire
messages, error tags and job IDs. Do not add blanket SDK closure after every
`register_error`: C6 makes an owner disconnect cancel/evict its earlier jobs.

**Conditional coordinated server hardening, separate from F6:** the chosen D1
contract must be encoded in shell continuation decisions rather than inferred
from the retained pure phase. The unexpected async-message arm emits
`protocol_error` at `Shell/Mirror/Session.lean:942` but returns `current.1 !=
.done` at line 944; idle may remain live. Delegated synchronous `dispatch` paths
also emit protocol errors at lines 616, 691, 761, 818 and 851 without necessarily
advancing that phase. Fixing only line 942 would therefore be incomplete.

The smallest coherent implementation is an explicit shell continuation outcome
(e.g. `continueAsync` / `endConnection`) in `dispatchAsync`: only successful job
controls and accepted/rejected **async** submission attempts continue. A complete
synchronous flow delegated to `dispatch` always ends this connection when it
returns, on success or failure, independently of the old phase. Unexpected async
messages emit their protocol error and end. This may be expressed directly in
the existing Bool result if each arm is explicit; an enum improves legibility
without requiring a Core protocol/proof change. If reusable dispatcher helpers
are later introduced, propagate their explicit continuation rather than parsing
sent JSON or error strings or maintaining an easily missed ad hoc fatal flag.

Document that mixing a synchronous one-shot registration into a connection with
owned jobs ends that connection and triggers C6. Applications retaining those
jobs should use a separate connection for synchronous work. This is distinct
from a rejected async submission, which must preserve existing jobs. Because
this corrects current phase-dependent continuation, keep it as an explicit D1
compatibility decision/task with its own acceptance evidence, not a hidden
prerequisite of the independently justified F6 client patch.

Extend existing `tools/JobStoreSpec.lean` fake-runner/session scenarios, not the
live-only `AsyncSpec` gate, to prove: accepted job A survives rejected submission
B; A can still be awaited/cancelled on the same connection; B creates no owned
job; malformed input and unexpected async `report_state` terminate dispatch;
owner jobs are evicted on fatal exit, another session's jobs remain intact.
Also cover delegated synchronous registration validation failure while the
retained phase is idle, and replay report/decode failure; both must terminate
without dispatching the next queued request. A fallback-only test is insufficient.
Use its existing injected runners and finite scripted transport EOF/finally
cleanup; never leave an unbounded mockPair receive waiting after session exit.

## 2. F5: reject partial EOF and distinguish read errors

Files: `Shell/Transport/Tcp.lean` (`tcpTransport`, lines 82–99) and
`Shell/Transport/Tls.lean` (`tlsTransport`, lines 168–185).

- Separate zero-byte clean EOF from `fdError`/`tlsError`. Propagate read failure
  as an infrastructure exception; do not convert it to an EOF payload or a
  successfully decoded protocol response. For TLS retain a bounded diagnostic
  from `Ffi.tlsErrmsg` where appropriate.
- Return `none` only for clean EOF with an empty accumulator. Nonempty bytes
  without LF at EOF are an unterminated-frame error even when they form complete
  JSON. Clear/discard the unusable partial buffer before returning/throwing.
- Keep complete LF-terminated frames, split/coalesced input, current CRLF
  compatibility, UTF-8 validation and the 65,535-byte bound unchanged. A complete
  buffered frame can be returned before a later read is attempted.
- Do not change the FFI ABI, public Transport shape or introduce a new general
  ownership abstraction. Stdio has the same partial-EOF pattern at
  `Shell/Transport/Stdio.lean:126`; include its equivalent narrow correction for
  uniform C1 behavior, with an explicit stdio EOF regression.

Test homes: extend `tools/TransportSpec.lean` and add a focused
`tools/check-client-framing.py` for the actual CLI. Normal: valid LF and split LF,
including exact byte boundary/multibyte payloads. Failure: same complete JSON
without LF then orderly EOF, partial JSON EOF, and injected/read transport error.
Integration edge: actual TLS 1.3 with temporary CA/client/server credentials,
SAN validation and client authentication; exercise both clean `close_notify`
after a fragment and abrupt underlying socket termination without close_notify.
A TLS EOF test alone does not establish the read-error branch. Bound peer reads,
handshakes and child lifetime, and reap every owned process in finally.

For validate, valid-LF prints VALID/exit 0; unterminated/error frames must exit 2
and print no VALID. For trace generation, rejected frames publish no capture.
The existing audit `cli-probes/probe.py` supplies the TCP reproduction; migrate
its assertions into maintained gates instead of editing dated audit evidence.

## 3. F6: cancel only a healthy, still-pending owned job

Files: `Shell/TraceCapture.lean` lines 43–98, `tools/TraceCaptureSpec.lean`,
`tools/check-trace-capture.py`.

Replace the unclassified `Except String` used privately by `awaitTraceJob` with
an internal typed stop reason, for example `pollBudgetExhausted`,
`terminalJobFailure String`, and `peerOrTransportFailure String`. Preserve the
existing public `run : ... → IO (Except String Capture)` and original diagnostic.
Only local budget exhaustion on a healthy connection with an accepted job
still believed pending/running may request best-effort cancellation. This also
preserves the public helper's explicit zero-budget case after acceptance; the
CLI parser itself requires at least one poll. The code has no
new public caller-cancellation API; do not invent one for this fix.

After `protocol_error`, malformed JSON, wrong correlation/result kind, read
failure/EOF, terminal cancelled/unknown status or terminal job outcome, return
the original failure without further wire writes. Do not retry mutation or
cancel somebody else's reply ID. Failure before `job_accepted` never has a job
to cancel. Cleanup-send failure stays secondary to the local budget diagnostic.
A sent cancellation is a request, not proof of physical worker termination;
retain the existing CLI owner-exit/server cleanup responsibilities.

Update tests that currently *require* overbroad cancellation: the wrong-job
case in `TraceCaptureSpec:133`, and wrong-job/wrong-result/cancelled cases in
`check-trace-capture.py`. Preserve the local poll-budget cancellation test and
add protocol_error/EOF/throwing-recv/malformed reply/unknown/infraError cases.
Assert exact writes: success is register + matching await(s); local exhausted
budget adds one cancel for the owned ID; peer-terminal failures add none.
Use a send callback that throws during budget cancellation to prove the original
failure remains primary. Each failure must leave no published output directory.

## Dependencies, gates and acceptance

1. Approve the D1 table and ownership expectations; update the three contracts.
2. Implement/test F5 independently. If the D1 continuation decision is accepted,
   implement its coordinated shell-only dispatch hardening and ownership tests.
3. Implement F6's private outcome classification against the agreed table.
4. Run focused remote checks, then one existing non-model suite. Independently
   review exact source/binary identities and raw positive/negative evidence.

Existing gates, confirmed from `lakefile.lean:144,263,306,403–415,700,731` and
`tools/run-local-no-model-check.sh:28–30,109`:

```sh
# Run only in the approved remote WSL checkout, never this coordinator.
lake build mirror transport_spec trace_capture_spec jobstore_spec
.lake/build/bin/transport_spec
.lake/build/bin/trace_capture_spec
.lake/build/bin/jobstore_spec
python3 tools/check-client-framing.py       # new maintained gate proposed above
python3 tools/check-trace-capture.py
python3 tools/check-validate-async.py
bash tools/run-local-no-model-check.sh
```

Wire the proposed Python framing gate into `lakefile.lean`'s test driver and the
non-model runner alongside trace-capture/validation scripts. Existing jobstore,
transport and trace-capture executables already have gates; extend them in
place. No `lake test` aggregate or live `AsyncSpec` invocation on this
coordinator: they can discover model-checker fallbacks. None of these repairs
needs new live model operations. If any C shim/header dependency changes become
necessary after implementation review, add `bash tools/check-native-rebuild.sh`
on remote WSL; the planned shell-only changes do not require a shim graph change.

Acceptance: no EOF/read-error fragment becomes a valid protocol message; fatal
peer errors trigger zero follow-up flow writes; local budget cancellation stays
owned and once-only; rejected async submission preserves earlier jobs; fatal
session exit cleans only its owner jobs. Preserve all historical audit evidence
and unrelated caches/worktree content. No commit/push/deploy is included here.
