import Shell.Transport.Stdio
import Codec.Json
import Codec.Bridge

/-!
# Client-side protocol session (t16)

Port of the Haskell @Protocol.Client@ surface the validate CLI needs
(@runClientValidate@): send one @ClientMessage@ per line, receive one
@MirrorMessage@ per line, and map the register-validate exchange onto
@ValidateResult@. Failures come back as @Except String@ exactly like
the Haskell @Either Text@.
-/

namespace Shell.Client

/-- Send one encoded client message (one JSON line). -/
def sendMsg (t : Shell.Transport.Transport) (m : Codec.ClientMessage) : IO Unit :=
  t.send (toString (Lean.Json.compress (Codec.encodeClient m)))

/-- Receive and decode one mirror message; @none@ = EOF/undecodable
line, mirroring Haskell recvMsg's error path. -/
def recvMsg (t : Shell.Transport.Transport) :
    IO (Except String Codec.MirrorMessage) := do
  match ← t.recv with
  | none => return .error "connection closed"
  | some line =>
      match Lean.Json.parse line with
      | .error e => return .error s!"bad json: {e}"
      | .ok j =>
          match Codec.decodeMirror j with
          | .ok m => return .ok m
          | .error _ => return .error "bad mirror message"

/-- The validate-only client exchange (Haskell @runClientValidate@):
@RegisterValidate@ then expect @SpecValidated@ / @RegisterError@ /
@ProtocolError@. -/
def runClientValidate (t : Shell.Transport.Transport)
    (cfg : Codec.ApalacheConfig) (bound : Nat) (spec : Option Codec.SpecConfig) :
    IO (Except String Codec.ValidateResult) := do
  sendMsg t (Codec.ClientMessage.registerValidate cfg bound spec)
  match ← recvMsg t with
  | .error e => return .error e
  | .ok m =>
      match m with
      | .specValidated v => return .ok v
      | .registerError e => return .error e
      | .protocolError e => return .error e
      | _ => return .error "unexpected message: expected spec_validated"

/-- Keep the submitting connection alive and long-poll the exact accepted job.
Only pending/running statuses are retryable; terminal failures and malformed
correlations must not become an endless polling loop. -/
private partial def awaitValidationJob (t : Shell.Transport.Transport)
    (jobId : String) : IO (Except String Codec.ValidateResult) := do
  sendMsg t (.awaitJob jobId (some 30))
  match ← recvMsg t with
  | .error error => return .error error
  | .ok message =>
    match message with
    | .jobResult id outcome =>
      if id != jobId then return .error "async validation job id mismatch"
      match outcome with
      | .validate result => return .ok result
      | .infraError error => return .error error
      | .genTraces _ => return .error "unexpected trace-generation result for validation job"
    | .jobStatus id phase =>
      if id != jobId then return .error "async validation job id mismatch"
      match phase with
      | .pending | .running => awaitValidationJob t jobId
      | .cancelled => return .error "async validation job cancelled"
      | .unknown => return .error "async validation job unknown or evicted"
      | .done | .failed => return .error "async validation job ended without a result"
    | .registerError error | .protocolError error => return .error error
    | _ => return .error "unexpected message: expected async validation job result"

/-- Submit async validation, then await its terminal verdict on the same
connection. This is a waiting CLI workflow, not detached job submission. -/
def runClientValidateAsync (t : Shell.Transport.Transport)
    (cfg : Codec.ApalacheConfig) (bound : Nat) (spec : Option Codec.SpecConfig) :
    IO (Except String Codec.ValidateResult) := do
  sendMsg t (.registerValidateAsync cfg bound spec)
  match ← recvMsg t with
  | .error error => return .error error
  | .ok message =>
    match message with
    | .jobAccepted jobId .validate =>
      if jobId.isEmpty then return .error "empty async validation job id"
      awaitValidationJob t jobId
    | .registerError error | .protocolError error => return .error error
    | _ => return .error "unexpected message: expected validation job_accepted"

end Shell.Client