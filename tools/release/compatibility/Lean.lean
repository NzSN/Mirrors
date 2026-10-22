import MirrorLean
import MirrorLean.ServerMode
open MirrorLean

private def required (name : String) : IO String := do
  let some value ← IO.getEnv name | throw (IO.userError s!"missing {name}")
  return value

private def connect (mode scenario : String) : IO (Except MirrorError Transport) := do
  if mode == "stdio" then return .ok (← spawnMirror (← required "COMPAT_MIRROR"))
  let some port := (← required "COMPAT_PORT").toNat? | throw (IO.userError "invalid port")
  if mode == "tcp" then return .ok (← connectMirror "127.0.0.1" port.toUInt16)
  let pin ← if scenario == "wrong-pin" then pure (String.ofList (List.replicate 64 '0')) else required "COMPAT_PIN"
  ServerMode.connectMirrorTls' {
    caFile := ← required "COMPAT_CA", certFile := ← required "COMPAT_CERT", keyFile := ← required "COMPAT_KEY"
    expectedCertSha256 := some pin
  } "localhost" port.toUInt16

def main : IO UInt32 := do
  let mode ← required "COMPAT_TRANSPORT"
  let scenario ← required "COMPAT_CASE"
  let connected ← connect mode scenario
  if scenario == "wrong-pin" then
    match connected with
    | .error (.tls message) =>
      if message.contains "fingerprint mismatch" then
        IO.println "{\"outcome\":\"pin_mismatch\",\"calls\":0}"
        return 0
      throw (IO.userError message)
    | _ => throw (IO.userError "wrong pin did not produce a fingerprint mismatch")
  let transport ← match connected with
    | .ok value => pure value
    | .error error => throw (IO.userError (MirrorError.toString error))
  let calls ← IO.mkRef 0
  let compute : StateComputer := fun _ _ _ => do
    let index ← calls.get
    calls.modify (· + 1)
    let values : Array Int := #[0, 2, 5]
    let value : Int := if scenario == "mismatch" && index == 1 then 99 else values[index]!
    return State.ofList [("count", .int value)]
  let result ← runClientWithTraces (.transport transport)
    { specPath := "Counter.tla", invariant := "TraceComplete", lengthBound := 6,
      constInit := some "CInit", paramVars := some "parameters" }
    #[System.FilePath.mk (← required "COMPAT_TRACE")] compute
  match scenario, result, ← calls.get with
  | "match", .ok (), 3 => IO.println "{\"outcome\":\"match\",\"calls\":3}"; return 0
  | "mismatch", .error (.stepMismatch _), 2 => IO.println "{\"outcome\":\"step_mismatch\",\"calls\":2}"; return 0
  | _, .error error, _ => throw (IO.userError (MirrorError.toString error))
  | _, _, _ => throw (IO.userError "unexpected successful replay or callback count")
