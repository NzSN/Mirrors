import MirrorLean
import MirrorLean.ServerMode
open MirrorLean
def required (name : String) : IO String := do
  match ← IO.getEnv name with
  | some value => pure value
  | none => throw (IO.userError s!"missing {name}")
def main : IO UInt32 := do
  let cert ← required "MIRRORS_REMOTE_CLIENT_CERT"
  let key ← required "MIRRORS_REMOTE_CLIENT_KEY"
  let ca ← required "MIRRORS_REMOTE_CA"
  let pin ← required "MIRRORS_REMOTE_SERVER_PIN"
  let inv ← required "M5_INTEROP_INV"
  let bound := (← required "M5_INTEROP_BOUND").toNat!
  let specResult ← specFromFile (System.FilePath.mk (← required "M5_INTEROP_SPEC"))
  let spec ← match specResult with
    | .ok spec => pure spec
    | .error e => throw (IO.userError (SpecError.toString e))
  let cfg : ApalacheConfig := {
    specPath := "HourClock.tla", invariant := inv, lengthBound := bound,
    initPredicate := some "Init", nextPredicate := some "Next" }
  let tls : ServerMode.TlsClientConfig := {
    caFile := ca, certFile := cert, keyFile := key, expectedCertSha256 := some pin }
  let t ← ServerMode.connectMirrorTls tls "172.20.208.1" 8999
  match ← runClientValidate (.transport t) cfg bound (some spec) with
  | .ok _ => IO.println "VALID"; return 0
  | .error e => IO.eprintln (MirrorError.toString e); return 1
