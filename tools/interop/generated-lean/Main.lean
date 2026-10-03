import CounterMirror
import MirrorLean.ServerMode

/-! Real generated Counter binding transport consumer. Only public model values,
classified outcomes, and validated pin identity are retained in its one JSON row. -/
open Lean MirrorLean MirrorLean.ModelInterface

private structure Recording where
  factoryCount : Nat := 0
  disposedPorts : Nat := 0
  events : Array String := #[]
  observations : Array String := #[]
  strides : Array String := #[]
  reports : Array Json := #[]
  coverage : Array (String × Nat) := #[]
  validatedServerPin : Option String := none

private def required (name : String) : IO String := do
  let some value ← IO.getEnv name | throw (IO.userError s!"missing harness variable {name}")
  return value

private def connect (transport caseName : String) : IO (Except MirrorError Transport) := do
  try
    if transport == "stdio" then return .ok (← spawnMirror (← required "GENERATED_LEAN_MIRROR_BIN"))
    let host ← required "GENERATED_LEAN_HOST"
    let portText ← required "GENERATED_LEAN_PORT"
    let some port := portText.toNat? | throw (IO.userError "invalid harness port")
    if port == 0 || port > 65535 then throw (IO.userError "invalid harness port")
    if transport == "tcp" then return .ok (← connectMirror host port.toUInt16)
    let pin ← if caseName == "wrong-pin" then pure (String.ofList (List.replicate 64 '0'))
      else required "MIRRORS_REMOTE_SERVER_PIN"
    ServerMode.connectMirrorTls' {
      caFile := ← required "MIRRORS_REMOTE_CA"
      certFile := ← required "MIRRORS_REMOTE_CLIENT_CERT"
      keyFile := ← required "MIRRORS_REMOTE_CLIENT_KEY"
      expectedCertSha256 := some pin } host port.toUInt16
  catch error => return .error (.io error)

private def execute (transportName caseName : String) (recording : IO.Ref Recording) :
    IO (Except NegotiatedError Unit) := do
  let connected ← connect transportName caseName
  let transport ← match connected with
    | .error error => return .error (.legacy error)
    | .ok value => pure value
  -- This is the exact pin the SDK just verified, not a separately exposed
  -- peer-certificate measurement (Transport does not expose that measurement).
  if transportName == "tls" then
    let pin ← required "MIRRORS_REMOTE_SERVER_PIN"
    recording.modify fun state => { state with validatedServerPin := some pin }
  let transport := { transport with send := fun line => do
    let json ← match Json.parse line with
      | .ok value => pure value
      | .error _ => throw (IO.userError "outbound protocol frame is not JSON")
    if (json.getObjValAs? String "proto_step").toOption == some "report_state" then
      let state ← match json.getObjVal? "state" with
        | .ok value => pure value
        | .error _ => throw (IO.userError "outbound report has no state")
      recording.modify fun current => { current with reports := current.reports.push state }
    transport.send line }
  let specPath ← required "GENERATED_LEAN_SPEC"
  let config : ApalacheConfig := {
    specPath := if transportName == "tls" then "Counter.tla" else specPath
    initPredicate := some "Init"
    nextPredicate := some "Next"
    constInit := some "CInit"
    invariant := "TraceComplete"
    lengthBound := 6
    paramVars := some "parameters" }
  let selectedDigest := if caseName == "wrong-digest" then String.ofList (List.replicate 64 '0')
    else CounterMirror.semanticDigest
  let digest ← match SemanticDigest.fromHex selectedDigest with
    | .error error => return .error error
    | .ok value => pure value
  let factory : AdapterFactory := fun context => do
    recording.modify fun state => { state with factoryCount := state.factoryCount + 1 }
    -- The SUT is created only inside the matched deferred factory.
    let count ← IO.mkRef (0 : Int)
    let port : CounterMirror.Port := {
      «initialize» := do
        recording.modify fun state => { state with events := state.events.push "Initialize" }
        count.set 0
        return .ok ()
      tick := fun input => do
        recording.modify fun state => { state with
          events := state.events.push "Tick"
          strides := state.strides.push (toString input.stride) }
        count.modify (· + input.stride)
        return .ok ()
      observe := do
        let actual ← count.get
        let actual := if caseName == "faulty-observer" then actual + 1 else actual
        recording.modify fun state => { state with
          events := state.events.push "Observe"
          observations := state.observations.push (toString actual) }
        return .ok { count := actual } }
    match ← CounterMirror.bind port context.effectiveConfig with
    | .error error => return .error error
    | .ok binding => return .ok (binding.toLocalBinding do
        let coverage ← binding.coverage
        recording.modify fun state => { state with
          disposedPorts := state.disposedPorts + 1, coverage }
        return .ok ())
  let selection : CompiledAdapterSelection := {
    metadata := { CounterMirror.metadata with semanticDigest := selectedDigest }
    adapterId := "generated-lean-counter-acceptance"
    registry := #[{
      key := { semanticDigest := digest, adapterId := "generated-lean-counter-acceptance" }
      factory }] }
  if transportName == "tls" then
    let source ← IO.FS.readFile specPath
    runClientNegotiated (.transport transport) config { numTraces := 1, view := some "View" }
      selection (some { sources := #[source] })
  else
    let trace ← required "GENERATED_LEAN_TRACE"
    runClientWithTracesNegotiated (.transport transport) config #[trace] selection

private def count (state : State) : Json :=
  match state.get? "count" with
  | some (.int value) => .str (toString value)
  | _ => .null

private def pinMismatch (message : String) : Bool := Id.run do
  let expectedPrefix := "connectMirrorTls: peer certificate fingerprint mismatch (expected " ++
    String.ofList (List.replicate 64 '0') ++ ", got "
  if !message.startsWith expectedPrefix || !message.endsWith ")" then return false
  let actual := ((message.drop expectedPrefix.length).dropEnd 1).copy
  return actual.length == 64 && actual.toList.all (fun c =>
    ('0' <= c && c <= '9') || ('a' <= c && c <= 'f')) &&
    actual != String.ofList (List.replicate 64 '0')

private def outcome : NegotiatedError → Json
  | .legacy (.stepMismatch report) => Json.mkObj [
      ("kind", "step_mismatch"), ("action", .str report.action),
      ("expectedCount", count report.expected), ("actualCount", count report.actual)]
  | .registration failure => Json.mkObj [("kind", "registration_error"), ("code", .str failure.code)]
  | .modelInterface code _ => Json.mkObj [("kind", "model_interface_error"), ("code", .str code)]
  | .legacy (.tls message) => Json.mkObj [("kind", if pinMismatch message then "tls_pin_mismatch" else "tls_error")]
  | .legacy (.io _) => Json.mkObj [("kind", "io_error")]
  | .legacy .transportClosed => Json.mkObj [("kind", "transport_closed")]
  | .legacy (.registerFailed _) => Json.mkObj [("kind", "legacy_registration_error")]
  | _ => Json.mkObj [("kind", "unexpected_error")]

def main (args : List String) : IO UInt32 := do
  let [transport, caseName] := args | return 64
  if !["stdio", "tcp", "tls"].contains transport ||
      !["correct", "faulty-observer", "wrong-digest", "unauthorized", "wrong-pin"].contains caseName then return 64
  let recording ← IO.mkRef ({} : Recording)
  let result ← try execute transport caseName recording
    catch error => pure (.error (.legacy (.io error)))
  let (resultJson, exitCode) : Json × UInt32 := match result with
    | .ok () => (Json.mkObj [("kind", "completed")], 0)
    | .error error => (outcome error, match error with | .legacy (.stepMismatch _) => 1 | _ => 2)
  let recorded ← recording.get
  IO.println (Json.mkObj [
    ("schema", "mirrors.generated-lean-transport-row/v1"),
    ("transport", .str transport), ("case", .str caseName),
    ("semanticDigest", .str CounterMirror.semanticDigest),
    ("validatedServerPin", recorded.validatedServerPin.map Json.str |>.getD .null),
    ("factoryCount", toJson recorded.factoryCount), ("disposedPorts", toJson recorded.disposedPorts),
    ("events", toJson recorded.events), ("observations", toJson recorded.observations),
    ("strides", toJson recorded.strides), ("reports", .arr recorded.reports),
    ("coverage", Json.mkObj (recorded.coverage.toList.map fun (key, value) => (key, toJson value))),
    ("outcome", resultJson)]).compress
  return exitCode
