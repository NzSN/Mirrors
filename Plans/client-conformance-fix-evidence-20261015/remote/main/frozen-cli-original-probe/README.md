# Bounded scripted peers for the built-in CLI

Prepared for execution **only in the approved remote Windows machine's Ubuntu
WSL environment**. Preparation does not execute the probe locally. The script
refuses a kernel release without a Microsoft/WSL identifier.

Use an existing `mirror` executable and its corresponding source tree. This
probe never builds, starts a Mirrors server, runs Apalache/TLC, or accesses an
existing model service. Each case starts only the existing CLI in client mode
and a task-owned Python loopback peer. Minimal inline TLA module bytes are the
same fixtures already used by `tools/check-validate-async.py`; the scripted peer
does not evaluate the model.

The remote owner supplies actual paths:

```sh
python3 /approved/remote/path/cli-probes/probe.py \
  --mirror /approved/existing/mirror \
  --source-root /approved/corresponding/Mirrors \
  --work-root /approved/task-owned/scratch
```

Copy `probe.py` and `source-reference.json` together. The scratch parent must
already exist and be owned by this task. The script creates a fresh child
directory and retains all inputs, raw stdout/stderr, peer requests, per-case
results, binary hash/version, source hashes, host identity, and summary there.
The printed `work_root` locates the evidence. No retained artifacts are deleted.

`source-reference.json` binds 11 relevant files at Mirrors
`c17bae951c4d5bbc5818c2a4f82e2d93d07abc52`. A mismatch prevents all cases from
running and records `not-run-source-mismatch`. Source parity plus a binary hash
is not proof of binary construction; use the remote owner's retained build
manifest to associate the existing executable with these source bytes.

## Cases and expected observations

| Case | Exact peer behavior | Correct outcome | Existing-source finding reproduced when |
|---|---|---|---|
| `valid-lf-control` | Read `register_validate`; send `{"proto_step":"spec_validated","result":"valid"}` followed by LF, then half-close peer output | CLI exit 0, stdout `VALID` | Control must pass before interpreting negatives |
| `missing-lf-eof` | Send the same complete JSON bytes **without LF**, then half-close peer output | Refuse the incomplete frame; no successful VALID verdict | CLI instead exits 0 with `VALID` |
| `terminal-protocol-error-cancel` | Read `register_trace_gen_async`; send matching `job_accepted` with kind `gen_traces`; read exact `await_job` with timeout 30; send `protocol_error` | Exit 2 preserving original error, with no further flow writes | Third request is `cancel_job` for the same accepted job |

The async peer optionally acknowledges an observed cancellation with a bounded
`job_status` reply. That acknowledgement does not authorize the extra request;
it simply avoids leaving the scripted fixture waiting. Current `cancelOwned`
sends cancellation without receiving a reply.

Socket reads, accepts, and process waits all have explicit limits. CLI children
have separate process groups. Every case attempts termination, escalates to kill
when necessary, waits/reaps its owned child, closes owned sockets, and joins its
peer thread. No production process is targeted.

A zero probe exit means the control passed, the cases completed without fixture
errors/timeouts, and all owned children/threads were reaped/stopped. It does
**not** mean conformance passed. Consult the two `finding_reproduced` booleans
and the retained requests/results. A fixed binary should produce false for both
booleans while retaining a passing normal control.

## Source basis

- `Main.lean:25` dispatches `validate`; `Main.lean:26` dispatches `trace-gen`.
- `Shell/Cli.lean:667` resolves the validation source closure and builds its
  existing registration; `Shell/Cli.lean:704` starts trace generation.
- `Shell/Transport/Tcp.lean:92` returns a buffered payload at EOF without LF.
- `Shell/Client.lean:38` accepts a valid `spec_validated` response.
- `Shell/TraceCapture.lean:74` converts `protocol_error` into an error result;
  `Shell/TraceCapture.lean:95` then calls cancellation for every such error.
- `tools/check-validate-async.py:59` supplies the exact tiny Main/Child source
  fixture; `:30` and `:36` establish accepted-job and await request shapes.
- `tools/TraceCaptureSpec.lean:112` and `:133` establish trace-job accepted kind
  and the existing register/await/cancel sequence.

This probe covers TCP client framing and trace-capture terminal behavior. It
adds no TLS, Haskell, full-suite, model-checking, or framework qualification claim.
