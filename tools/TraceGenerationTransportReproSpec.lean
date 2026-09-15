import Shell.Apalache.Runner
import Shell.Mirror.Session
import Shell.Transport.Stdio
import Codec.Json

/-!
TG0 focused reproductions for trace-generation transport hardening.

The exact-byte controls are green before and after the repair. The behavioral
checks are intentionally red on the original implementation: an oversized
synchronous result reaches the transport, and Apalache evidence is replaced by
the literal `trace generation failed`.
-/

open Shell.Transport

abbrev Failures := IO.Ref (List String)

def check (fails : Failures) (name : String) (ok : Bool)
    (detail : String := "") : IO Unit := do
  if !ok then fails.modify (· ++ [if detail.isEmpty then name else s!"{name}: {detail}"])

def compactMirror (message : Codec.MirrorMessage) : String :=
  Lean.Json.compress (Codec.encodeMirror message)

def traceResultWithPadding (paths : List String) (padding : Nat) : Codec.TraceGenResult :=
  { itfTracePaths := paths
    itfTraces := [.vstr (String.ofList (List.replicate padding 'x'))] }

def exactResultFor (mkMessage : Codec.TraceGenResult → Codec.MirrorMessage)
    (paths : List String) (target : Nat) : Except String Codec.TraceGenResult := do
  let base := (compactMirror (mkMessage (traceResultWithPadding paths 0))).toUTF8.size
  if base > target then throw s!"base message {base} exceeds target {target}"
  let result := traceResultWithPadding paths (target - base)
  let actual := (compactMirror (mkMessage result)).toUTF8.size
  if actual != target then throw s!"wanted {target} bytes, encoded {actual}"
  return result

def cfg : Codec.ApalacheConfig where
  constInit := none
  initPredicate := none
  invariant := "Inv"
  lengthBound := 1
  nextPredicate := none
  paramVars := ""
  specPath := "Spec.tla"

def tc : Codec.TraceConfig := { numTraces := 1, view := none }

def captureTransport (request : String) : IO (Transport × IO.Ref (List String)) := do
  let pending ← IO.mkRef (some request)
  let sent ← IO.mkRef ([] : List String)
  return ({
    scope := .sharedFilesystem
    recv := do
      let next ← pending.get
      pending.set none
      return next
    send := fun line => do
      validateProtocolLine line
      sent.modify (· ++ [line])
  }, sent)

def runSync (result : Codec.TraceGenResult) (dest : Option String) (durable : Bool) :
    IO (Except String (List String)) := do
  let registration := Lean.Json.compress (Codec.encodeClient
    (.registerGenTraces cfg dest none tc))
  let (transport, sent) ← captureTransport registration
  let oracles : Shell.Mirror.Oracles := {
    Shell.Mirror.stubOracles with
    generateTraceFiles := fun _ _ _ _ =>
      pure (.ok { result := result, pathsDurable := durable })
  }
  try
    Shell.Mirror.run transport oracles
    return .ok (← sent.get)
  catch error => return .error (toString error)

def runAsyncScripted (result : Codec.TraceGenResult) :
    IO (Except String (List String × Nat)) := do
  let requests := [
    Lean.Json.compress (Codec.encodeClient
      (.registerGenTracesAsync cfg none none tc)),
    Lean.Json.compress (Codec.encodeClient (.awaitJob "job-0" none)),
    Lean.Json.compress (Codec.encodeClient (.queryJob "job-0")),
    Lean.Json.compress (Codec.encodeClient (.awaitJob "job-0" none))]
  let pending ← IO.mkRef requests
  let sent ← IO.mkRef ([] : List String)
  let generationCount ← IO.mkRef 0
  let transport : Transport := {
    scope := .remote
    recv := do
      match ← pending.get with
      | [] => return none
      | line :: rest => pending.set rest; return some line
    send := fun line => do
      validateProtocolLine line
      sent.modify (· ++ [line])
  }
  let runner : Shell.Jobs.Runner := {
    validate := fun _ _ _ _ => pure (.ok .valid)
    genTraces := fun _ _ _ _ => do
      generationCount.modify (· + 1)
      pure (.ok result)
  }
  let store ← Shell.Jobs.newJobStoreWith 1 runner
  try
    Shell.Mirror.runAsync transport Shell.Mirror.stubOracles store
    return .ok (← sent.get, ← generationCount.get)
  catch error => return .error (toString error)

def exactBoundaryControls (fails : Failures) : IO Unit := do
  let durable := ["/tmp/tg0/trace.itf.json"]
  for target in [65535, 65536] do
    match exactResultFor Codec.MirrorMessage.genTracesDone durable target with
    | .error error => check fails s!"sync exact {target}" false error
    | .ok result =>
        check fails s!"sync exact {target}"
          ((compactMirror (.genTracesDone result)).toUTF8.size == target)
  for target in [65535, 65536] do
    match exactResultFor (fun result =>
        Codec.MirrorMessage.jobResult "job-tg0" (.genTraces result)) durable target with
    | .error error => check fails s!"async exact {target}" false error
    | .ok result =>
        check fails s!"async exact {target}"
          ((compactMirror (.jobResult "job-tg0" (.genTraces result))).toUTF8.size == target)

  let counter : Codec.TraceGenResult :=
    { itfTracePaths := ["Counter_0.itf.json"], itfTraces := [.vint 0] }
  let counterSync := compactMirror (.genTracesDone counter)
  let counterAsync := compactMirror (.jobResult "job-counter" (.genTraces counter))
  check fails "Counter sync control remains in-limit"
    (counterSync.toUTF8.size < maxProtocolLineBytes)
  check fails "Counter async control remains in-limit"
    (counterAsync.toUTF8.size < maxProtocolLineBytes)
  IO.println (s!"TG0 bytes: sync-boundary=65535/65536 async-boundary=65535/65536 " ++
    s!"counter-sync={counterSync.toUTF8.size} counter-async={counterAsync.toUTF8.size}")

def syncDeliveryRepros (fails : Failures) : IO Unit := do
  let durable := ["/tmp/tg0/trace.itf.json"]
  match exactResultFor Codec.MirrorMessage.genTracesDone durable 65535 with
  | .error error => check fails "sync 65535 setup" false error
  | .ok result =>
      match ← runSync result (some "/tmp/tg0") true with
      | .error error => check fails "sync 65535 full success" false error
      | .ok [line] =>
          check fails "sync 65535 full success"
            (line == compactMirror (.genTracesDone result))
      | .ok lines => check fails "sync 65535 full success" false (reprStr lines)

  match exactResultFor Codec.MirrorMessage.genTracesDone durable 65536 with
  | .error error => check fails "sync 65536 setup" false error
  | .ok result =>
      match ← runSync result (some "/tmp/tg0") true with
      | .error error =>
          check fails "sync 65536 durable result uses path-only success" false error
      | .ok [line] =>
          let expected := compactMirror (.genTracesDone
            { itfTracePaths := durable, itfTraces := [] })
          check fails "sync 65536 durable result uses path-only success" (line == expected) line
      | .ok lines =>
          check fails "sync 65536 durable result uses path-only success" false (reprStr lines)

  match exactResultFor Codec.MirrorMessage.genTracesDone durable 65536 with
  | .error error => check fails "sync ephemeral setup" false error
  | .ok result =>
      match ← runSync result none false with
      | .error error => check fails "sync ephemeral overflow is bounded terminal error" false error
      | .ok [line] =>
          check fails "sync ephemeral overflow is bounded terminal error"
            (line.toUTF8.size <= maxProtocolLineBytes &&
              line.contains "register_error" && line.contains "TRACE_RESULT_TOO_LARGE") line
      | .ok lines =>
          check fails "sync ephemeral overflow is bounded terminal error" false (reprStr lines)

  let hugePath := "/tmp/" ++ String.ofList (List.replicate 70000 'p')
  let result : Codec.TraceGenResult := { itfTracePaths := [hugePath], itfTraces := [] }
  IO.println s!"TG0 bytes: sync-path-overflow={compactMirror (.genTracesDone result) |>.toUTF8.size}"
  match ← runSync result (some "/tmp/tg0") true with
  | .error error => check fails "sync path-only overflow is bounded terminal error" false error
  | .ok [line] =>
      check fails "sync path-only overflow is bounded terminal error"
        (line.toUTF8.size <= maxProtocolLineBytes &&
          line.contains "register_error" && line.contains "TRACE_RESULT_TOO_LARGE") line
  | .ok lines =>
      check fails "sync path-only overflow is bounded terminal error" false (reprStr lines)

def asyncDeliveryRepro (fails : Failures) : IO Unit := do
  let paths := ["/tmp/tg0/trace.itf.json"]
  match exactResultFor (fun result =>
      Codec.MirrorMessage.jobResult "job-0" (.genTraces result)) paths 65536 with
  | .error error => check fails "async 65536 setup" false error
  | .ok result =>
      match ← runAsyncScripted result with
      | .error error =>
          check fails "async 65536 is terminal, bounded, and idempotent" false error
      | .ok (accepted :: terminals, runs) =>
          let acceptedOk := accepted.contains "job_accepted" && accepted.contains "job-0"
          let terminalOk := terminals.length == 3 && terminals.all (fun line =>
            line.toUTF8.size <= maxProtocolLineBytes &&
            line.contains "job_result" && line.contains "job-0" &&
            line.contains "TRACE_RESULT_TOO_LARGE")
          check fails "async 65536 is terminal, bounded, and idempotent"
            (acceptedOk && terminalOk && terminals[0]? == terminals[1]? &&
              terminals[1]? == terminals[2]? && runs == 1)
            s!"runs={runs} replies={reprStr (accepted :: terminals)}"
      | .ok ([], _) =>
          check fails "async 65536 is terminal, bounded, and idempotent" false "no replies"

  let hugePath := "/tmp/" ++ String.ofList (List.replicate 70000 'p')
  let pathOverflow : Codec.TraceGenResult := { itfTracePaths := [hugePath], itfTraces := [] }
  IO.println (s!"TG0 bytes: async-path-overflow=" ++
    s!"{compactMirror (.jobResult "job-0" (.genTraces pathOverflow)) |>.toUTF8.size}")
  match ← runAsyncScripted pathOverflow with
  | .error error => check fails "async path overflow is bounded terminal error" false error
  | .ok (_accepted :: terminals, runs) =>
      check fails "async path overflow is bounded terminal error"
        (terminals.length == 3 && terminals.all (fun line =>
          line.toUTF8.size <= maxProtocolLineBytes &&
          line.contains "job_result" && line.contains "TRACE_RESULT_TOO_LARGE") && runs == 1)
        s!"runs={runs} replies={reprStr terminals}"
  | .ok ([], _) =>
      check fails "async path overflow is bounded terminal error" false "no replies"

def diagnosticRepro (fails : Failures) : IO Unit := do
  let result ← Shell.Apalache.syncOracles.generateTraceFiles cfg none none tc
  match result with
  | .ok value => check fails "Apalache failure stays an error" false (reprStr value)
  | .error error =>
      check fails "Apalache error keeps stable category"
        (error.contains "APALACHE_TRACE_GENERATION_FAILED") error
      check fails "Apalache error keeps exit status" (error.contains "42") error
      check fails "Apalache error keeps stdout" (error.contains "synthetic stdout") error
      check fails "Apalache error keeps stderr" (error.contains "synthetic stderr") error
      check fails "Apalache error keeps multibyte text" (error.contains "测试") error
      check fails "Apalache error is truncated and bounded"
        (error.contains "truncated" && error.toUTF8.size <= 8192) s!"bytes={error.toUTF8.size}"
      check fails "Apalache error sanitizes owned run directory"
        (error.contains "<run>" && !error.contains "modelmirrors-session-") error

def main : IO Unit := do
  let fails ← IO.mkRef ([] : List String)
  exactBoundaryControls fails
  syncDeliveryRepros fails
  asyncDeliveryRepro fails
  diagnosticRepro fails
  let failures ← fails.get
  if failures.isEmpty then
    IO.println "TRACE GENERATION TRANSPORT REPROS GREEN"
  else
    for failure in failures do IO.eprintln s!"FAIL: {failure}"
    throw (IO.userError s!"{failures.length} trace-generation hardening repro(s) remain red")
