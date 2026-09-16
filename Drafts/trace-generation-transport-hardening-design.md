# Trace-generation transport hardening design

> Status: **implemented and independently accepted for the TG0–TG3 transport
> hardening scope; the WorkQueue standard-catalog blocker is resolved under
> profile 4, while aggregate TG4/TG5 publication remains blocked by the
> separately excluded MirrorRust validation failures**.
>
> Scope: MirrorECMA-owned registration cleanup, Mirrors-owned bounded trace
> result delivery, and preservation of Apalache trace-generation failures.
> The synchronous and asynchronous generated adapter profiles keep their
> current contracts.

## 1. Problem statement

The generated-adapter MBT path exposed three framework defects around
`register_trace_gen`:

1. MirrorECMA can spawn an owned stdio mirror and then reject an oversized
   registration before entering the cleanup-owned receive loop. The rejected
   promise is visible, but the child remains blocked on stdin and keeps Node's
   event loop alive.
2. Mirrors always puts every generated ITF value in `gen_traces_done`. Exact
   encoding can exceed the uniform 65,535-byte JSONL payload limit, at which
   point the transport throws instead of selecting a representable result.
3. The synchronous trace-file runner discards the detailed error returned by
   `generateTraceFilesIn` and replaces it with `trace generation failed`.

Two application findings are related but are not framework defects:

- a promise-returning implementation port requires `mirrorecma-async-v1`; the
  `mirrorecma-v1` synchronous port is behaving according to its contract; and
- malformed or unreachable TLA+ witnesses must be repaired in the application
  model before scaffolding, generation, or replay.

This design does not raise the line limit. A bounded transport must reject or
select another representable message before writing a line.

## 2. Reproduced evidence and current corrections

The owned-child leak is reproducible through MirrorECMA's public API with a
blocking child and a 70,000-character inline source. Two independent runs
printed the size diagnostic and survived until an external timeout:

```text
protocol line is 70182 UTF-8 bytes; maximum is 65535
attempt=1 exit=124
protocol line is 70182 UTF-8 bytes; maximum is 65535
attempt=2 exit=124
```

The failure occurs before any protocol byte is written. It does not invoke
Apalache.

The current DumpLedgerTransfer source graph is accepted by the profile-3
frontend and has 21 effective variables: thirteen inherited and eight local.
The generated application contract removes the run-profile variables
`action_taken` and `parameters`, leaving 25 actions, one initializer with
`fingerprintMatches`, and 19 observations. Earlier references to twenty source
variables and an empty inherited-variable scaffold are historical, not current
frontend behavior.

The surviving selected DumpLedgerTransfer fixture files compact individually
to approximately 12–33 KiB. They do not reproduce earlier reported
65,286/109,036-byte response measurements. The general outbound defect is
nevertheless source-proven and must have a synthetic exact-boundary regression:
`Codec.encodeMirror` always includes `itfTraces`, and every production transport
rejects the final encoded line above 65,535 bytes.

## 3. Goals

1. An owned MirrorECMA transport is closed exactly once after every
   registration failure, including pre-write size rejection and synchronous
   `send` exceptions.
2. The original registration/application error remains primary when cleanup
   also fails.
3. Known-invalid registrations are rejected before spawning an owned child.
4. Mirrors plans trace-result delivery from the exact final JSON bytes and
   never attempts an oversized send.
5. A durable shared-filesystem result may fall back from inline traces to paths;
   a remote or ephemeral-path result fails explicitly instead of pretending
   that unusable paths are success.
6. Synchronous and asynchronous trace-result messages obey the same size
   policy appropriate to their delivery scope.
7. Trace generation retains bounded, useful Apalache failure evidence through
   cleanup and reports it without leaking unbounded output.
8. Existing in-limit wire bytes, model-interface locks, generated target bytes,
   replay behavior, and the 65,535-byte framing rule remain unchanged.

## 4. Non-goals

- No protocol-v1 line-limit increase.
- No source or trace chunking protocol in this change.
- No conversion of stdio into an asynchronous job session.
- No change to `mirrorecma-v1` or `mirrorecma-async-v1` port signatures.
- No automatic selection of an async target from application implementation
  behavior.
- No application-model, witness, or DumpLedger contract edits.
- No claim that server-local paths are usable by TCP or TLS clients.

Large inline source closures still require a representable registration. A
local stdio caller may use `apalacheConfig.specPath`; a remote caller requires a
future versioned source-upload/chunking mechanism if the complete inline closure
does not fit. Direct `apalache-mc` remains a valid application-side generation
workflow, not a substitute for transport cleanup.

## 5. Current failure paths

### 5.1 Inbound ownership gap

```text
runClientGenTraces(path, request)
  -> resolveTransport(path)
       -> spawnMirror(path)              child is now owned
  -> encode + transport.send(request)
       -> validateProtocolLine throws    no bytes written
  X  genTracesLoop is never entered      its finally cannot close child
```

`runClientExplore` has the same send-before-cleanup shape. Ordinary replay uses
`runLegacyReplay(..., register)` and already performs registration inside its
owned lifecycle.

### 5.2 Outbound representability gap

```text
Apalache files
  -> TraceGenResult { paths, traces }
  -> gen_traces_done { itfTracePaths, itfTraces }
  -> exact compact JSON > 65,535 bytes
  -> Transport.send throws
  -> session/process ends without a protocol result
```

The asynchronous `job_result` form carries the same trace result and therefore
needs the same exact-byte planning. A sync-only patch would leave the sibling
failure reachable in server mode.

### 5.3 Diagnostic erasure

`generateTraceFilesIn` already returns `Except String ...` containing Apalache
failure information. `syncOracles.generateTraceFiles` maps `.error _` to
`none`, performs cleanup, and later returns the literal `trace generation
failed`. The information is erased before the session constructs
`register_error`.

## 6. Deep module 1: owned registration exchange

The seam remains MirrorECMA's existing public client functions. Callers learn no
new interface. A private exchange module owns four steps:

```text
prepare exact registration
  -> validate uniform line bound
  -> resolve/acquire transport
  -> send inside owned exchange
  -> receive or replay
  -> close once, preserving the primary failure
```

Conceptual TypeScript interface:

```ts
async function runOwnedRegistration<T>(
  target: string | Transport,
  encodedRegistration: string,
  exchange: (transport: Transport, iterator: AsyncIterator<string>) => Promise<T>,
): Promise<T>
```

The implementation must:

- call `validateProtocolLine(encodedRegistration)` before `resolveTransport`
  when the uniform size failure is knowable without acquiring resources;
- enter a single lifecycle after acquisition, with `send` inside its protected
  body;
- close the transport once on success, send failure, receive failure,
  cancellation, or decoding failure;
- preserve the original failure if `close` also fails; and
- surface a cleanup failure only when there is no earlier failure.

`runClientGenTraces` and `runClientExplore` use this module. Existing replay
registration may either keep `runLegacyReplay` or delegate to the same internal
module after parity tests prove byte and error compatibility. Do not layer a
second cleanup loop around `runLegacyReplay`.

The pre-spawn validation is an optimization with a safety consequence: an
oversized request allocates no child. It does not replace post-acquisition send
cleanup, because pipes and sockets can still fail synchronously.

## 7. Deep module 2: trace-result delivery planning

### 7.1 Delivery facts

Mirrors transports declare one private delivery fact:

```lean
inductive DeliveryScope where
  | sharedFilesystem
  | remote

structure Shell.Transport.Transport where
  scope : DeliveryScope := .remote
  recv : IO (Option String)
  send : String -> IO Unit
```

The stdio adapter sets `sharedFilesystem`; TCP and TLS set `remote`. Test
adapters select the scope explicitly when delivery behavior matters. This is a
real seam because stdio and network adapters have different path usability.

The trace-generation operation also supplies whether returned paths survive
owned temporary-directory cleanup. A nonempty requested destination that was
successfully copied outside the owned session directory is durable. Paths into
the session directory are ephemeral even if they appear in a result.

### 7.2 Pure planner

A pure module receives delivery scope, path durability, and a
`TraceGenResult`. It returns one closed plan:

```lean
inductive TraceDeliveryPlan where
  | full       (message : Codec.MirrorMessage)
  | pathsOnly  (message : Codec.MirrorMessage)
  | failure    (message : Codec.MirrorMessage)
```

Planning uses `Lean.Json.compress (Codec.encodeMirror message)` and UTF-8 byte
length—the exact bytes the transport would send. Estimates based on trace-file
size, character count, or payload-only fragments are forbidden.

Rules for synchronous `gen_traces_done`:

1. If the full message fits, emit it byte-for-byte unchanged.
2. If it does not fit, and scope is `sharedFilesystem`, and paths are durable,
   try the same message with `itfTraces: []`.
3. If the path-only message fits, emit it as successful path-only delivery.
4. Otherwise emit a bounded `register_error` with a stable
   `TRACE_RESULT_TOO_LARGE` prefix and no physical path.
5. Assert that the failure message itself fits before sending it.

Rules for asynchronous `job_result`:

- Network sessions require inline delivery. If the exact job result is too
  large, project it deterministically to the same job id with terminal
  `outcome.error = TRACE_RESULT_TOO_LARGE...`.
- Repeated `query_job`/`await_job` calls produce the same projected terminal
  result. The store's phase remains terminal; no retry or second generation is
  implied.
- A future chunking protocol may replace this error only under a new explicit
  wire contract.

Only trace-generation terminal messages use this planner. Other message types
retain `sendMirror`; their existing producers remain responsible for bounded
fields.

### 7.3 Runner ordering

The runner must decode inline trace contents before deleting its owned session
directory. Its internal result distinguishes wire data from path durability:

```lean
structure GeneratedTraceDelivery where
  result : Codec.TraceGenResult
  pathsDurable : Bool
```

When `destPath` is absent, inline contents remain usable but session-local paths
are not durable. When a nonempty destination copy succeeds, the copied paths are
durable. Cleanup occurs after contents and durability have been captured.

This private shell type must not enter `Codec/` or the public protocol.

## 8. Deep module 3: bounded Apalache failure evidence

Replace the `Option` conversion in `syncOracles.generateTraceFiles` with an
`Except` flow that retains the original failure through cleanup:

```text
generateTraceFilesIn error
  -> bounded/sanitized TraceGenerationFailure
  -> release captured spec and remove session directory
  -> register_error containing stable code + useful detail
```

The error formatter must be shared by synchronous trace-file generation and
the equivalent asynchronous job runner. Its interface accepts exit status,
stdout, stderr, and the owned run-directory prefix; it returns a bounded UTF-8
string that:

- begins with a stable category such as `APALACHE_TRACE_GENERATION_FAILED`;
- retains the exit code and a useful tail of stdout/stderr;
- replaces the owned physical run-directory prefix with `<run>`;
- respects a byte budget small enough for the enclosing protocol message;
- states when output was truncated; and
- never changes an Apalache/spec verdict into success.

If cleanup fails after generation already failed, generation remains primary
and cleanup is logged/attached as secondary evidence. If generation succeeded
but cleanup fails, cleanup is the operation failure.

## 9. Wire compatibility

No new message tag or required field is introduced.

- In-limit `gen_traces_done` and `job_result` bytes remain identical.
- Path-only success uses the existing fields with `itfTraces: []`.
  MirrorECMA already decodes absent or empty inline traces and can consume
  returned paths.
- Oversized synchronous results use existing `register_error`.
- Oversized async results use existing `job_result.outcome.error`.
- The 65,535-byte payload limit remains uniform in both directions.

Documentation must correct the current implication that every inline source
closure or trace result necessarily fits one record. `spec.sources` is portable
only when the final encoded registration fits; `destPath` enables path-only
fallback only for a shared-filesystem transport with a durable copy.

## 10. Failure matrix

| Condition | Required result |
| --- | --- |
| Oversized registration known before spawn | Reject; zero child allocation |
| Send throws after transport acquisition | Close exactly once; send error primary |
| Receive/decode fails | Close exactly once; receive/decode error primary |
| Full trace reply fits | Existing byte-identical success |
| Full reply too large; shared filesystem + durable paths; paths fit | `gen_traces_done` with paths and empty traces |
| Full reply too large; paths ephemeral or transport remote | Bounded terminal size error |
| Path-only reply also too large | Bounded terminal size error |
| Async job result too large | Same job id, terminal error outcome, repeatable |
| Apalache fails with output | Bounded categorized detail; cleanup still runs |
| Apalache fails and cleanup fails | Apalache failure primary; cleanup secondary |
| Apalache succeeds and cleanup fails | Cleanup failure |

## 11. Verification strategy

The regression surface crosses the same interfaces as production:

- MirrorECMA public `runClientGenTraces` with a real blocking child;
- scripted transports for exact close counts and primary-error precedence;
- exact boundary encodings at 65,535 and 65,536 bytes;
- stdio, TCP, and TLS transport scopes;
- synchronous `gen_traces_done` and asynchronous `job_result`;
- destination-present and destination-absent generation;
- injected Apalache stdout/stderr, exit, and cleanup failures;
- unchanged Counter trace-generation bytes below the limit; and
- the generated async DumpLedgerTransfer replay using checked-in trace files,
  without requiring the framework to regenerate application witnesses.

The final cross-repository gate includes MirrorECMA's full tests, Mirrors'
`lake test`, model-interface golden checks, `tools/interop/run.sh`, and the
application's model-interface check plus generated MBT correct/faulty cases.
Every unavailable external tier is reported separately from a pass.

## 12. Rejected alternatives

### Raise or disable the line cap

Rejected. It weakens bounded framing, does not establish a new interoperable
limit, and only moves the failure to a larger model or trace.

### Kill only the child in `runClientGenTraces`

Rejected. Cleanup ownership also applies to custom transports, sockets,
`runClientExplore`, readiness failures, and cleanup-error precedence. The deep
module belongs at the owned registration seam.

### Always omit inline traces

Rejected. Network clients cannot use server-local paths, and existing in-limit
reply bytes are compatibility evidence.

### Always fall back to paths when the reply is large

Rejected. Session-directory paths may already be deleted, and remote clients
cannot assume a shared filesystem.

### Catch the final transport exception and exit quietly

Rejected. It prevents a crash but gives the client no terminal protocol result
and loses the reason the result was unrepresentable.

### Put direct Apalache execution inside MirrorECMA

Rejected. It duplicates Mirrors-owned generation semantics and configuration.
Applications may invoke Apalache directly as an explicit workflow, but the
client library does not become a second trace-generation implementation.

## 13. Open decision

Remote source or trace payloads larger than one v1 record require a future
versioned transfer mechanism. The follow-up design must choose chunked JSONL,
content-addressed upload, or an authenticated server-side artifact reference.
This decision does not block the fail-closed v1 hardening specified here.
