import Codec.Json
import Shell.Transport.Stdio

/-!
# Shell.Transport.TraceDelivery — exact-byte trace-result delivery planning

One trace-generation result has up to three wire representations: the full
inline `gen_traces_done`, the same message with `itfTraces: []` (paths only),
and a bounded `register_error` / terminal `job_result` failure. Which one is
legal depends on facts the transport owns (whether the peer can read paths this
process writes) and on facts the runner owns (whether the returned paths
survive owned-directory cleanup).

This module is the single planner for those decisions. It is pure: the caller
supplies the delivery scope, the path-durability fact, and the result, and the
planner returns one closed message. Every fit decision measures the exact final
compact bytes the transport would send — never an estimate from trace-file
size, character count, or a payload fragment.

The v1 protocol line limit is unchanged at @maxProtocolLineBytes@; a future
chunking protocol would replace the failure arm under a new wire contract.
-/

namespace Shell.Transport.TraceDelivery

open Shell.Transport (DeliveryScope maxProtocolLineBytes)

/-- Stable prefix of every bounded trace-result size failure. Clients match on
this prefix; the rest of the message is informational detail. -/
def traceResultTooLarge : String := "TRACE_RESULT_TOO_LARGE"

/-- One closed delivery decision. @full@ is the unchanged success message,
@pathsOnly@ is a successful success message without inline values, and
@failure@ is a bounded terminal message that carries no physical path. -/
inductive Plan where
  | full (message : Codec.MirrorMessage)
  | pathsOnly (message : Codec.MirrorMessage)
  | failure (message : Codec.MirrorMessage)

/-- The exact line a transport sends for one mirror message. -/
def encodedLine (message : Codec.MirrorMessage) : String :=
  Lean.Json.compress (Codec.encodeMirror message)

/-- The exact byte length the transport would frame. -/
def encodedBytes (message : Codec.MirrorMessage) : Nat :=
  (encodedLine message).toUTF8.size

/-- Does this message fit one v1 protocol line as-is? -/
def fits (message : Codec.MirrorMessage) : Bool :=
  encodedBytes message ≤ maxProtocolLineBytes

/-- Bounded, path-free detail for an undeliverable trace result. -/
def tooLargeError (bytes : Nat) : String :=
  s!"{traceResultTooLarge}: trace result needs {bytes} UTF-8 bytes (limit {maxProtocolLineBytes}) and has no durable path-only delivery"

/-- Plan one synchronous `gen_traces_done` reply: full, paths-only, or a
bounded `register_error`. Paths-only success additionally requires a shared
filesystem and paths that survive the server's owned cleanup. -/
def planSyncResult (scope : DeliveryScope) (pathsDurable : Bool)
    (result : Codec.TraceGenResult) : Plan :=
  let full := Codec.MirrorMessage.genTracesDone result
  if fits full then
    .full full
  else
    let pathsOnly := Codec.MirrorMessage.genTracesDone
      { itfTracePaths := result.itfTracePaths, itfTraces := [] }
    if scope == .sharedFilesystem && pathsDurable && fits pathsOnly then
      .pathsOnly pathsOnly
    else
      .failure (Codec.MirrorMessage.registerError (tooLargeError (encodedBytes full)))

/-- Plan one `job_result` for a trace-generation job: the exact stored outcome
when it fits, otherwise a deterministic bounded terminal error carrying the
same job id. Repeated queries project identically and never re-run a job. -/
def planTraceJobResult (jobId : String) (result : Codec.TraceGenResult) : Plan :=
  let full := Codec.MirrorMessage.jobResult jobId (.genTraces result)
  if fits full then
    .full full
  else
    .failure (Codec.MirrorMessage.jobResult jobId
      (.infraError (tooLargeError (encodedBytes full))))

/-- The message a plan selects. -/
def Plan.message : Plan → Codec.MirrorMessage
  | .full message => message
  | .pathsOnly message => message
  | .failure message => message

end Shell.Transport.TraceDelivery
