import Shell.Mirror.Session
import Shell.Transport.Mock
import Shell.ModelInterface.Runtime
import Codec.ModelInterfaceJson
import Codec.ModelInterfaceDistributionJson
import Codec.Json
import Lean.Data.Json

/-!
# Runtime model-interface distribution specification

Always-on, in-memory JSONL sessions over the real synchronous session driver.
The checked-in Counter contract and typed trace are the only fixtures.
-/

namespace ModelInterfaceDistributionSpec

open Core.ModelInterface

abbrev Failures := IO.Ref (List String)

def check (fails : Failures) (name : String) (ok : Bool)
    (detail : String := "") : IO Unit := do
  if !ok then
    if detail.isEmpty then
      fails.modify (fun fs => fs ++ [name])
    else
      fails.modify (fun fs => fs ++ [s!"{name}: {detail}"])

def fixtureRoot : String := "test/fixtures/model-interface/counter"
def contractPath : String := fixtureRoot ++ "/Counter.mirror-interface.json"
def tracePath : String := fixtureRoot ++ "/counter.itf.json"
def lockPath : String := fixtureRoot ++ "/Counter.mirror-interface.lock.json"

def counterConfig : Codec.ApalacheConfig where
  constInit := none
  initPredicate := none
  invariant := ""
  lengthBound := 3
  nextPredicate := none
  paramVars := "parameters"
  specPath := "specs/Counter.tla"

structure Fixtures where
  contract : ContractV1
  evidence : ModelEvidence
  semanticDigest : String

def descriptorRequest (contract : ContractV1) :
    Codec.ModelInterfaceDistributionJson.RequestV1 where
  request := .descriptor
  policy := .require
  acceptDescriptorSchemas := [descriptorSchemaV1]
  contract := .inline contract

def descriptorPreferRequest (contract : ContractV1) :
    Codec.ModelInterfaceDistributionJson.RequestV1 :=
  { descriptorRequest contract with policy := .prefer }

def verifyRequest (contract : ContractV1) (digest : String) :
    Codec.ModelInterfaceDistributionJson.RequestV1 where
  request := .verify
  policy := .require
  acceptDescriptorSchemas := [descriptorSchemaV1]
  expectedSemanticDigest := some digest
  contract := .inline contract

def descriptorIfNoneMatchRequest (contract : ContractV1) (digest : String) :
    Codec.ModelInterfaceDistributionJson.RequestV1 where
  request := .descriptor
  policy := .require
  acceptDescriptorSchemas := [descriptorSchemaV1]
  ifNoneMatch := some digest
  contract := .inline contract

def unsupportedSchemaRequest (contract : ContractV1)
    (policy : NegotiationPolicy) :
    Codec.ModelInterfaceDistributionJson.RequestV1 where
  request := .descriptor
  policy := policy
  acceptDescriptorSchemas := ["mirrors.model-interface-descriptor/v999"]
  contract := .inline contract

def loadFixtures (fails : Failures) : IO (Option Fixtures) := do
  let contractText ← IO.FS.readFile contractPath
  let contract ← match Codec.ModelInterfaceJson.parseContractString contractText with
    | .error error =>
        check fails "fixtures: contract parses" false error
        return none
    | .ok contract => pure contract
  let bundle ← match ← Shell.Mirror.readItfTraceBundle tracePath with
    | .error error =>
        check fails "fixtures: trace bundle parses" false error
        return none
    | .ok bundle => pure bundle
  let some evidence := bundle.evidence
    | check fails "fixtures: typed evidence present" false
      return none
  let resolution := Shell.ModelInterface.Runtime.resolve
    (some (descriptorRequest contract)) (some evidence) (some "parameters")
  check fails "fixtures: runtime descriptor resolves"
    (resolution.decision.status == some .resolved)
    (toString (repr resolution.diagnostics))
  let some lock := resolution.lock
    | check fails "fixtures: runtime lock present" false
      return none
  check fails "fixtures: digest has 64 hex characters"
    (lock.semanticDigest.length == 64) lock.semanticDigest
  let goldenText ← IO.FS.readFile lockPath
  match Codec.ModelInterfaceJson.parseLockString goldenText with
  | .error error => check fails "fixtures: golden lock parses" false error
  | .ok golden =>
      check fails "fixtures: runtime digest equals build-time golden"
        (lock.semanticDigest == golden.semanticDigest)
        s!"runtime={lock.semanticDigest}, golden={golden.semanticDigest}"
  return some { contract, evidence, semanticDigest := lock.semanticDigest }

structure RunningSession where
  client : Shell.Transport.Transport
  task : Task (Except IO.Error Unit)
  done : IO.Ref Bool

def startSessionWith (oracles : Shell.Mirror.Oracles)
    (access : Shell.ModelInterface.Runtime.Access := .descriptor) :
    IO RunningSession := do
  let (client, mirror) ← Shell.Transport.mockPair
  let done ← IO.mkRef false
  let task ← IO.asTask (prio := Task.Priority.dedicated) (do
    try
      Shell.Mirror.run mirror oracles access
    finally
      done.set true)
  return { client, task, done }

def startSession (access : Shell.ModelInterface.Runtime.Access := .descriptor) :
    IO RunningSession :=
  startSessionWith Shell.Mirror.stubOracles access

def startAsyncSessionWith (oracles : Shell.Mirror.Oracles)
    (access : Shell.ModelInterface.Runtime.Access := .descriptor) :
    IO RunningSession := do
  let (client, mirror) ← Shell.Transport.mockPair
  let done ← IO.mkRef false
  let store ← Shell.Jobs.newJobStore 1
  let task ← IO.asTask (prio := Task.Priority.dedicated) (do
    try
      Shell.Mirror.runAsync mirror oracles store access
    finally
      done.set true)
  return { client, task, done }

partial def waitDone (done : IO.Ref Bool) (remaining : Nat) : IO Bool := do
  if ← done.get then return true
  if remaining == 0 then return false
  IO.sleep 1
  waitDone done (remaining - 1)

def finishSession (fails : Failures) (name : String)
    (session : RunningSession) : IO Unit := do
  let completed ← waitDone session.done 2000
  check fails (name ++ ": task terminates") completed
  if completed then
    match session.task.get with
    | .ok () => pure ()
    | .error error =>
        check fails (name ++ ": task outcome") false (toString error)
  else
    -- Best-effort cleanup if a failed assertion left replay waiting for state.
    session.client.send "{"
    let _ ← waitDone session.done 1000

def registrationJsonWithPaths (paths : List String)
    (request : Option Codec.ModelInterfaceDistributionJson.RequestV1) :
    Except String Lean.Json := do
  let base := Codec.encodeClient
    (.registerTraces counterConfig paths)
  Codec.ModelInterfaceDistributionJson.insertRegistrationRequest? base request

def registrationJson
    (request : Option Codec.ModelInterfaceDistributionJson.RequestV1) :
    Except String Lean.Json :=
  registrationJsonWithPaths [tracePath] request

def sendRegistration (client : Shell.Transport.Transport)
    (request : Option Codec.ModelInterfaceDistributionJson.RequestV1) :
    IO (Except String String) := do
  match registrationJson request with
  | .error error => return .error error
  | .ok json =>
      let line := Lean.Json.compress json
      client.send line
      return .ok line

def sendGeneratedRegistrationWith (client : Shell.Transport.Transport)
    (request : Option Codec.ModelInterfaceDistributionJson.RequestV1) :
    IO (Except String Unit) := do
  let base := Codec.encodeClient (.register counterConfig none { numTraces := 1, view := none })
  match Codec.ModelInterfaceDistributionJson.insertRegistrationRequest? base request with
  | .error error => return .error error
  | .ok json =>
      client.send (Lean.Json.compress json)
      return .ok ()

def sendGeneratedRegistration (client : Shell.Transport.Transport)
    (request : Codec.ModelInterfaceDistributionJson.RequestV1) : IO (Except String Unit) :=
  sendGeneratedRegistrationWith client (some request)

def recvLine (client : Shell.Transport.Transport) : IO (Except String String) := do
  match ← client.recv with
  | none => return .error "transport closed"
  | some line => return .ok line

def decodeMirrorLine (line : String) : Except String Codec.MirrorMessage := do
  let json ← Lean.Json.parse line
  (Codec.decodeMirror json).mapError (fun error => error.msg)

def recvMirror (client : Shell.Transport.Transport) :
    IO (Except String Codec.MirrorMessage) := do
  match ← recvLine client with
  | .error error => return .error error
  | .ok line => return decodeMirrorLine line

def sendCount (client : Shell.Transport.Transport) (count : Int) : IO Unit :=
  client.send <| Lean.Json.compress <| Codec.encodeClient <|
    .reportState [("count", .vint count)]

def expectMirror (fails : Failures) (client : Shell.Transport.Transport)
    (name : String) (predicate : Codec.MirrorMessage → Bool) : IO Bool := do
  match ← recvMirror client with
  | .error error =>
      check fails name false error
      return false
  | .ok message =>
      let ok := predicate message
      check fails name ok (toString (repr message))
      return ok

def driveThreeStateReplay (fails : Failures)
    (client : Shell.Transport.Transport) (label : String) : IO Unit := do
  if !(← expectMirror fails client (label ++ ": initial_state") fun
      | .initialState action _ => action == "init"
      | _ => false) then return
  sendCount client 0
  if !(← expectMirror fails client (label ++ ": initial step_ok") fun
      | .stepOk => true | _ => false) then return

  if !(← expectMirror fails client (label ++ ": next_step 1") fun
      | .nextStep action _ => action == "tick"
      | _ => false) then return
  sendCount client 2
  if !(← expectMirror fails client (label ++ ": step_ok 1") fun
      | .stepOk => true | _ => false) then return

  if !(← expectMirror fails client (label ++ ": next_step 2") fun
      | .nextStep action _ => action == "tick"
      | _ => false) then return
  sendCount client 5
  if !(← expectMirror fails client (label ++ ": step_ok 2") fun
      | .stepOk => true | _ => false) then return
  let _ ← expectMirror fails client (label ++ ": all_steps_done") fun
    | .allStepsDone => true
    | _ => false

def receiveSpecValidated (fails : Failures) (client : Shell.Transport.Transport)
    (name : String) :
    IO (Option (String × Option Codec.ModelInterfaceDistributionJson.ReplyV1)) := do
  let line ← match ← recvLine client with
    | .error error =>
        check fails name false error
        return none
    | .ok line => pure line
  match Codec.ModelInterfaceDistributionJson.parseSpecValidatedReplyBytes
      line.toUTF8 with
  | .error error =>
      check fails name false error
      return none
  | .ok (json, reply) =>
      match Codec.decodeMirror json with
      | .ok (.specValidated .valid) =>
          check fails name true
          return some (line, reply)
      | .ok message =>
          check fails name false (toString (repr message))
          return none
      | .error error =>
          check fails name false error.msg
          return none

def scenarioLegacy (fails : Failures) : IO Unit := do
  -- An authenticated transport with no model-interface application grant must
  -- retain byte-identical non-negotiated replay behavior.
  let session ← startSession .disabled
  match ← sendRegistration session.client none with
  | .error error =>
      check fails "legacy: send registration" false error
  | .ok sent =>
      let expectedRegistration := Lean.Json.compress <|
        Codec.encodeClient (.registerTraces counterConfig [tracePath])
      check fails "legacy: registration bytes unchanged"
        (sent == expectedRegistration)
      match ← receiveSpecValidated fails session.client "legacy: spec_validated" with
      | none => pure ()
      | some (line, reply) =>
          let expected := Lean.Json.compress <|
            Codec.encodeMirror (.specValidated .valid)
          check fails "legacy: reply bytes unchanged" (line == expected)
            (line ++ " vs " ++ expected)
          check fails "legacy: no modelInterface extension" reply.isNone
          driveThreeStateReplay fails session.client "legacy"
  finishSession fails "legacy" session

def scenarioDescriptor (fails : Failures) (fixtures : Fixtures) : IO Unit := do
  let session ← startSession
  match ← sendRegistration session.client
      (some (descriptorRequest fixtures.contract)) with
  | .error error =>
      check fails "descriptor: send registration" false error
  | .ok _ =>
      match ← receiveSpecValidated fails session.client
          "descriptor: spec_validated" with
      | none => pure ()
      | some (_, reply) =>
          match reply with
          | some reply =>
              check fails "descriptor: resolved status"
                (reply.status == .resolved)
              check fails "descriptor: semantic digest"
                (reply.semanticDigest == some fixtures.semanticDigest)
              check fails "descriptor: descriptor returned"
                reply.descriptor.isSome
          | none =>
              check fails "descriptor: extension present" false
          driveThreeStateReplay fails session.client "descriptor"
  finishSession fails "descriptor" session

def scenarioNotModified (fails : Failures) (fixtures : Fixtures) : IO Unit := do
  let session ← startSession
  match ← sendRegistration session.client
      (some (descriptorIfNoneMatchRequest fixtures.contract
        fixtures.semanticDigest)) with
  | .error error =>
      check fails "not-modified: send registration" false error
  | .ok _ =>
      match ← receiveSpecValidated fails session.client
          "not-modified: spec_validated" with
      | none => pure ()
      | some (_, reply) =>
          match reply with
          | some reply =>
              check fails "not-modified: status"
                (reply.status == .notModified)
              check fails "not-modified: semantic digest"
                (reply.semanticDigest == some fixtures.semanticDigest)
              check fails "not-modified: descriptor absent"
                reply.descriptor.isNone
              check fails "not-modified: descriptor byte count absent"
                reply.descriptorBytes.isNone
          | none =>
              check fails "not-modified: extension present" false
          driveThreeStateReplay fails session.client "not-modified"
  finishSession fails "not-modified" session

def scenarioUnsupportedRequire (fails : Failures)
    (fixtures : Fixtures) : IO Unit := do
  let session ← startSession
  match ← sendRegistration session.client
      (some (unsupportedSchemaRequest fixtures.contract .require)) with
  | .error error =>
      check fails "unsupported-require: send registration" false error
  | .ok _ =>
      let line ← match ← recvLine session.client with
        | .error error =>
            check fails "unsupported-require: register_error" false error
            pure ""
        | .ok line => pure line
      if !line.isEmpty then
        match Codec.ModelInterfaceDistributionJson.parseRegisterErrorFailureBytes
            line.toUTF8 with
        | .error error =>
            check fails "unsupported-require: structured failure parses" false error
        | .ok (json, failure) =>
            match Codec.decodeMirror json with
            | .ok (.registerError _) =>
                check fails "unsupported-require: register_error tag" true
            | .ok message =>
                check fails "unsupported-require: register_error tag" false
                  (toString (repr message))
            | .error error =>
                check fails "unsupported-require: register_error tag" false error.msg
            match failure with
            | some failure =>
                check fails "unsupported-require: unsupported status"
                  (failure.status == .unsupported)
                check fails "unsupported-require: stable code"
                  (failure.code == "interface_schema_unsupported") failure.code
            | none =>
                check fails "unsupported-require: structured failure present" false
  -- A completed server task proves no replay message was emitted.
  finishSession fails "unsupported-require" session

def scenarioUnsupportedPrefer (fails : Failures)
    (fixtures : Fixtures) : IO Unit := do
  let session ← startSession
  match ← sendRegistration session.client
      (some (unsupportedSchemaRequest fixtures.contract .prefer)) with
  | .error error =>
      check fails "unsupported-prefer: send registration" false error
  | .ok _ =>
      match ← receiveSpecValidated fails session.client
          "unsupported-prefer: spec_validated" with
      | none => pure ()
      | some (_, reply) =>
          match reply with
          | some reply =>
              check fails "unsupported-prefer: unsupported status"
                (reply.status == .unsupported)
              check fails "unsupported-prefer: descriptor identity absent"
                (reply.descriptorSchema.isNone && reply.semanticDigest.isNone &&
                  reply.provenanceDigest.isNone && reply.descriptorBytes.isNone)
              check fails "unsupported-prefer: descriptor absent"
                reply.descriptor.isNone
          | none =>
              check fails "unsupported-prefer: extension present" false
          -- The explicit unsupported reply is followed by legacy replay.
          driveThreeStateReplay fails session.client "unsupported-prefer"
  finishSession fails "unsupported-prefer" session

def scenarioDisabledRequire (fails : Failures) (fixtures : Fixtures) : IO Unit := do
  let session ← startSession .disabled
  match ← sendRegistration session.client
      (some (descriptorRequest fixtures.contract)) with
  | .error error =>
      check fails "disabled-require: send registration" false error
  | .ok _ =>
      let line ← match ← recvLine session.client with
        | .error error =>
            check fails "disabled-require: register_error" false error
            pure ""
        | .ok line => pure line
      if !line.isEmpty then
        match Codec.ModelInterfaceDistributionJson.parseRegisterErrorFailureBytes
            line.toUTF8 with
        | .error error =>
            check fails "disabled-require: structured failure parses" false error
        | .ok (json, failure) =>
            match Codec.decodeMirror json with
            | .ok (.registerError _) =>
                check fails "disabled-require: register_error tag" true
            | .ok message =>
                check fails "disabled-require: register_error tag" false
                  (toString (repr message))
            | .error error =>
                check fails "disabled-require: register_error tag" false error.msg
            match failure with
            | some failure =>
                check fails "disabled-require: unavailable status"
                  (failure.status == .unavailable)
                check fails "disabled-require: stable code"
                  (failure.code == "interface_unavailable") failure.code
            | none =>
                check fails "disabled-require: structured failure present" false
  -- A completed server task proves descriptor-disabled admission never replayed.
  finishSession fails "disabled-require" session

def scenarioVerify (fails : Failures) (fixtures : Fixtures) : IO Unit := do
  let session ← startSession
  match ← sendRegistration session.client
      (some (verifyRequest fixtures.contract fixtures.semanticDigest)) with
  | .error error =>
      check fails "verify: send registration" false error
  | .ok _ =>
      match ← receiveSpecValidated fails session.client "verify: spec_validated" with
      | none => pure ()
      | some (_, reply) =>
          match reply with
          | some reply =>
              check fails "verify: matched status" (reply.status == .matched)
              check fails "verify: semantic digest"
                (reply.semanticDigest == some fixtures.semanticDigest)
              check fails "verify: no descriptor" reply.descriptor.isNone
          | none => check fails "verify: extension present" false
          driveThreeStateReplay fails session.client "verify"
  finishSession fails "verify" session

def wrongDigest : String := String.ofList (List.replicate 64 '0')

def scenarioWrongDigest (fails : Failures) (fixtures : Fixtures) : IO Unit := do
  let session ← startSession
  match ← sendRegistration session.client
      (some (verifyRequest fixtures.contract wrongDigest)) with
  | .error error =>
      check fails "wrong-digest: send registration" false error
  | .ok _ =>
      let line ← match ← recvLine session.client with
        | .error error =>
            check fails "wrong-digest: register_error" false error
            pure ""
        | .ok line => pure line
      if !line.isEmpty then
        match Codec.ModelInterfaceDistributionJson.parseRegisterErrorFailureBytes
            line.toUTF8 with
        | .error error =>
            check fails "wrong-digest: structured failure parses" false error
        | .ok (json, failure) =>
            match Codec.decodeMirror json with
            | .ok (.registerError _) =>
                check fails "wrong-digest: register_error tag" true
            | .ok message =>
                check fails "wrong-digest: register_error tag" false
                  (toString (repr message))
            | .error error =>
                check fails "wrong-digest: register_error tag" false error.msg
            match failure with
            | some failure =>
                check fails "wrong-digest: mismatch status"
                  (failure.status == .mismatch)
                check fails "wrong-digest: stable code"
                  (failure.code == "interface_digest_mismatch") failure.code
                check fails "wrong-digest: expected digest"
                  (failure.expectedSemanticDigest == some wrongDigest)
            | none =>
                check fails "wrong-digest: structured failure present" false
  -- Completion here proves replay never blocked awaiting report_state.
  finishSession fails "wrong-digest" session

def duplicateNestedRequest : String :=
  "{" ++
  "\"proto_step\":\"register_traces\"," ++
  "\"modelInterface\":{" ++
    "\"schema\":\"mirrors.model-interface-negotiation/v1\"," ++
    "\"request\":\"verify\"," ++
    "\"policy\":\"require\"," ++
    "\"policy\":\"prefer\"" ++
  "}" ++
  "}"

def scenarioDuplicateNestedKey (fails : Failures) : IO Unit := do
  let session ← startSession
  session.client.send duplicateNestedRequest
  let _ ← expectMirror fails session.client "duplicate-key: protocol_error" fun
    | .protocolError message =>
        message == Shell.Mirror.invalidClientMessageError
    | _ => false
  finishSession fails "duplicate-key" session

def attackerMarker : String := "PRIVATE_ATTACKER_FIELD_"

/-- A syntactically invalid request just below the JSONL byte cap. The strict
parser's raw diagnostic contains the duplicated attacker-controlled key, so
reflecting that diagnostic would produce a very large response. -/
def nearLimitAttackerMessage : String :=
  let key := attackerMarker ++ String.ofList (List.replicate 32500 'x')
  "{\"proto_step\":\"report_state\",\"" ++ key ++ "\":0,\"" ++ key ++ "\":1}"

/-- Valid strict JSON whose attacker-controlled message tag is rejected by the
client codec. This covers the decode-error boundary separately from the
duplicate-key scanner boundary above. -/
def nearLimitAttackerDecodeMessage : String :=
  let tag := attackerMarker ++ String.ofList (List.replicate 65000 'y')
  "{\"proto_step\":\"" ++ tag ++ "\"}"

def expectSanitizedProtocolError (fails : Failures)
    (client : Shell.Transport.Transport) (label : String) : IO Unit := do
  match ← recvLine client with
  | .error error =>
      check fails (label ++ ": response") false error
  | .ok line =>
      check fails (label ++ ": bounded response")
        (line.toUTF8.size < 256) s!"response bytes={line.toUTF8.size}"
      check fails (label ++ ": attacker field not reflected")
        (!line.contains attackerMarker)
      match decodeMirrorLine line with
      | .ok (.protocolError message) =>
          check fails (label ++ ": stable error")
            (message == Shell.Mirror.invalidClientMessageError) message
      | .ok message =>
          check fails (label ++ ": protocol_error tag") false
            (toString (repr message))
      | .error error =>
          check fails (label ++ ": response decodes") false error

def scenarioAttackerDiagnosticsSanitized (fails : Failures) : IO Unit := do
  let attackerBytes := nearLimitAttackerMessage.toUTF8.size
  check fails "attacker-message: near wire limit"
    (attackerBytes > 65000 &&
      attackerBytes ≤ Codec.StrictJson.defaultLimits.maxBytes)
    s!"bytes={attackerBytes}"
  let decodeBytes := nearLimitAttackerDecodeMessage.toUTF8.size
  check fails "attacker-decode-message: near wire limit"
    (decodeBytes > 65000 &&
      decodeBytes ≤ Codec.StrictJson.defaultLimits.maxBytes)
    s!"bytes={decodeBytes}"

  let sync ← startSession
  sync.client.send nearLimitAttackerMessage
  expectSanitizedProtocolError fails sync.client "attacker sync"
  finishSession fails "attacker sync" sync

  let replay ← startSession
  match ← sendRegistration replay.client none with
  | .error error => check fails "attacker replay: registration" false error
  | .ok _ =>
      let _ ← receiveSpecValidated fails replay.client
        "attacker replay: spec_validated"
      if ← expectMirror fails replay.client "attacker replay: initial_state" fun
          | .initialState _ _ => true
          | _ => false then
        replay.client.send nearLimitAttackerMessage
        expectSanitizedProtocolError fails replay.client "attacker replay"
  finishSession fails "attacker replay" replay

  let async ← startAsyncSessionWith Shell.Mirror.stubOracles
  async.client.send nearLimitAttackerMessage
  expectSanitizedProtocolError fails async.client "attacker async"
  finishSession fails "attacker async" async

  let syncDecode ← startSession
  syncDecode.client.send nearLimitAttackerDecodeMessage
  expectSanitizedProtocolError fails syncDecode.client "attacker decode sync"
  finishSession fails "attacker decode sync" syncDecode

  let replayDecode ← startSession
  match ← sendRegistration replayDecode.client none with
  | .error error => check fails "attacker decode replay: registration" false error
  | .ok _ =>
      let _ ← receiveSpecValidated fails replayDecode.client
        "attacker decode replay: spec_validated"
      if ← expectMirror fails replayDecode.client
          "attacker decode replay: initial_state" fun
          | .initialState _ _ => true
          | _ => false then
        replayDecode.client.send nearLimitAttackerDecodeMessage
        expectSanitizedProtocolError fails replayDecode.client
          "attacker decode replay"
  finishSession fails "attacker decode replay" replayDecode

  let asyncDecode ← startAsyncSessionWith Shell.Mirror.stubOracles
  asyncDecode.client.send nearLimitAttackerDecodeMessage
  expectSanitizedProtocolError fails asyncDecode.client "attacker decode async"
  finishSession fails "attacker decode async" asyncDecode

def scenarioUnreadableTraceRejectsReplay (fails : Failures)
    (fixtures : Fixtures) : IO Unit := do
  let temporaryRoot ← IO.FS.createTempDir
  try
    let missing := (temporaryRoot / "missing.itf.json").toString
    let session ← startSession
    let request := descriptorRequest fixtures.contract
    match registrationJsonWithPaths [missing] (some request) with
    | .error error =>
        check fails "unreadable-trace: registration encodes" false error
    | .ok json =>
        session.client.send (Lean.Json.compress json)
        let line ← match ← recvLine session.client with
          | .ok line => pure line
          | .error error =>
              check fails "unreadable-trace: register_error" false error
              pure ""
        if !line.isEmpty then
          match Codec.ModelInterfaceDistributionJson.parseRegisterErrorFailureBytes
              line.toUTF8 with
          | .error error =>
              check fails "unreadable-trace: structured failure parses" false error
          | .ok (json, failure) =>
              check fails "unreadable-trace: register_error tag"
                (match Codec.decodeMirror json with
                 | .ok (.registerError _) => true
                 | _ => false)
              check fails "unreadable-trace: preflight code"
                (failure.map (·.code) == some "interface_trace_preflight_failed")
        finishSession fails "unreadable-trace" session
  finally
    try IO.FS.removeDir temporaryRoot catch _ => pure ()

def wrongInputTrace : ItfTrace where
  traceVars := ["action_taken", "count", "parameters"]
  paramVars := ["parameters"]
  traceParams := []
  traceStates := [
    { actionTaken := "init"
      parameters := [("parameters", .vrecord [("stride", .vint 0)])]
      stateVars := [("count", .vint 0)] },
    { actionTaken := "tick"
      parameters := [("parameters", .vrecord [("stride", .vstr "two")])]
      stateVars := [("count", .vint 2)] }
  ]

def scenarioPreflightRejectsReplay (fails : Failures) (fixtures : Fixtures) : IO Unit := do
  let source : SourceDigest := {
    moduleName := "Counter"
    logicalPath := "Counter.tla"
    contentSha256 := String.ofList (List.replicate 64 '0')
  }
  let oracles : Shell.Mirror.Oracles := {
    Shell.Mirror.stubOracles with
      generateTraces := fun _ _ _ _ _ => pure (.ok {
        traces := [wrongInputTrace]
        evidence := some fixtures.evidence
        sources := [source]
      })
  }
  let session ← startSessionWith oracles
  match ← sendGeneratedRegistration session.client
      (verifyRequest fixtures.contract fixtures.semanticDigest) with
  | .error error => check fails "preflight-reject: send registration" false error
  | .ok () =>
      let line ← match ← recvLine session.client with
        | .error error =>
            check fails "preflight-reject: register_error" false error
            pure ""
        | .ok line => pure line
      if !line.isEmpty then
        match Codec.ModelInterfaceDistributionJson.parseRegisterErrorFailureBytes
            line.toUTF8 with
        | .error error =>
            check fails "preflight-reject: structured failure parses" false error
        | .ok (json, failure) =>
            match Codec.decodeMirror json with
            | .ok (.registerError _) =>
                check fails "preflight-reject: register_error tag" true
            | .ok message =>
                check fails "preflight-reject: register_error tag" false
                  (toString (repr message))
            | .error error =>
                check fails "preflight-reject: register_error tag" false error.msg
            match failure with
            | some failure =>
                check fails "preflight-reject: unavailable status"
                  (failure.status == .unavailable)
                check fails "preflight-reject: stable code"
                  (failure.code == "interface_trace_preflight_failed") failure.code
            | none =>
                check fails "preflight-reject: structured failure present" false
  -- A completed server task proves no initial_state/report_state exchange began.
  finishSession fails "preflight-reject" session

def scenarioOracleFailureSanitized (fails : Failures) (fixtures : Fixtures) : IO Unit := do
  let internalError :=
    "apalache failed at /srv/private/models/Counter.tla with --run-dir=/tmp/secret"
  let oracles : Shell.Mirror.Oracles := {
    Shell.Mirror.stubOracles with
      generateTraces := fun _ _ _ _ _ => pure (.error internalError)
  }

  -- No request is the compatibility branch: retain the exact historical
  -- human error and do not add an extension.
  let legacy ← startSessionWith oracles
  match ← sendGeneratedRegistrationWith legacy.client none with
  | .error error => check fails "oracle-failure legacy: send" false error
  | .ok () =>
      match ← recvLine legacy.client with
      | .error error => check fails "oracle-failure legacy: reply" false error
      | .ok line =>
          let expected := Lean.Json.compress <|
            Codec.encodeMirror (.registerError internalError)
          check fails "oracle-failure legacy: exact bytes retained"
            (line == expected) s!"{line} vs {expected}"
  finishSession fails "oracle-failure legacy" legacy

  -- In an async connection, the old bypass left the Core phase idle and the
  -- receive loop waiting forever. Negotiated failure must be admitted as a
  -- terminal register step and expose no raw oracle diagnostic.
  let negotiated ← startAsyncSessionWith oracles
  match ← sendGeneratedRegistration negotiated.client
      (descriptorRequest fixtures.contract) with
  | .error error => check fails "oracle-failure negotiated: send" false error
  | .ok () =>
      let line ← match ← recvLine negotiated.client with
        | .error error =>
            check fails "oracle-failure negotiated: reply" false error
            pure ""
        | .ok line => pure line
      if !line.isEmpty then
        check fails "oracle-failure negotiated: raw path hidden"
          (!line.contains "/srv/private" && !line.contains "/tmp/secret" &&
            !line.contains "--run-dir") line
        match Codec.ModelInterfaceDistributionJson.parseRegisterErrorFailureBytes
            line.toUTF8 with
        | .error error =>
            check fails "oracle-failure negotiated: structured failure parses"
              false error
        | .ok (json, failure) =>
            match Codec.decodeMirror json with
            | .ok (.registerError message) =>
                check fails "oracle-failure negotiated: sanitized message"
                  (message == "interface_trace_preflight_failed") message
            | .ok message =>
                check fails "oracle-failure negotiated: register_error tag"
                  false (toString (repr message))
            | .error error =>
                check fails "oracle-failure negotiated: register_error tag"
                  false error.msg
            match failure with
            | some failure =>
                check fails "oracle-failure negotiated: unavailable status"
                  (failure.status == .unavailable)
                check fails "oracle-failure negotiated: stable code"
                  (failure.code == "interface_trace_preflight_failed") failure.code
            | none =>
                check fails "oracle-failure negotiated: structured failure present"
                  false
  finishSession fails "oracle-failure negotiated" negotiated

def scenarioNegotiatedTraceLimits (fails : Failures)
    (fixtures : Fixtures) : IO Unit := do
  let temporaryRoot ← IO.FS.createTempDir
  try
    let boundedDir := temporaryRoot / "bounded"
    IO.FS.createDir boundedDir
    let raw ← IO.FS.readFile tracePath
    IO.FS.writeFile (boundedDir / "a.itf.json") raw
    IO.FS.writeFile (boundedDir / "b.itf.json") raw
    let aggregateBytes := raw.toUTF8.size * 2
    let exact : Shell.Mirror.NegotiatedTraceLoadLimits := {
      maxFiles := 2
      maxAggregateBytes := aggregateBytes
      maxTraces := 2
      maxStates := 6
    }
    match ← Shell.Mirror.loadTraceBundleWithLimits [boundedDir.toString] exact with
    | .error error =>
        check fails "trace-limits: exact aggregate budgets accepted" false error
    | .ok bundle =>
        check fails "trace-limits: exact trace count"
          (bundle.traces.length == 2)
        check fails "trace-limits: exact state count"
          (bundle.traces.foldl
            (fun count trace => count + trace.traceStates.length) 0 == 6)
        check fails "trace-limits: compatible evidence retained"
          bundle.evidence.isSome

    let fileLimits := { exact with maxFiles := 1 }
    match ← Shell.Mirror.loadTraceBundleWithLimits [boundedDir.toString]
        fileLimits with
    | .ok _ =>
        check fails "trace-limits: file count rejected" false
    | .error error =>
        check fails "trace-limits: file count rejected"
          (error.contains "file-count") error
    let byteLimits := { exact with maxAggregateBytes := aggregateBytes - 1 }
    match ← Shell.Mirror.loadTraceBundleWithLimits [boundedDir.toString]
        byteLimits with
    | .ok _ =>
        check fails "trace-limits: aggregate bytes rejected" false
    | .error error =>
        check fails "trace-limits: aggregate bytes rejected"
          (error.contains "aggregate-byte") error
    let traceLimits := { exact with maxTraces := 1 }
    match ← Shell.Mirror.loadTraceBundleWithLimits [boundedDir.toString]
        traceLimits with
    | .ok _ =>
        check fails "trace-limits: trace count rejected" false
    | .error error =>
        check fails "trace-limits: trace count rejected"
          (error.contains "trace-count") error
    let stateLimits := { exact with maxStates := 5 }
    match ← Shell.Mirror.loadTraceBundleWithLimits [boundedDir.toString]
        stateLimits with
    | .ok _ =>
        check fails "trace-limits: state count rejected" false
    | .error error =>
        check fails "trace-limits: state count rejected"
          (error.contains "state-count") error

    -- Exercise the production file-count profile through the real session.
    -- The contents are deliberately invalid: admission must reject the
    -- directory before opening/parsing any of them.
    let overfullDir := temporaryRoot / "overfull"
    IO.FS.createDir overfullDir
    let overfullCount := Shell.Mirror.negotiatedTraceLoadLimitsV1.maxFiles + 1
    for i in [0:overfullCount] do
      IO.FS.writeFile (overfullDir / s!"trace-{i}.itf.json") "not-json"
    let session ← startSession
    let request := descriptorRequest fixtures.contract
    match registrationJsonWithPaths [overfullDir.toString] (some request) with
    | .error error =>
        check fails "trace-limits session: registration encodes" false error
    | .ok json =>
        session.client.send (Lean.Json.compress json)
        let line ← match ← recvLine session.client with
          | .error error =>
              check fails "trace-limits session: register_error" false error
              pure ""
          | .ok line => pure line
        if !line.isEmpty then
          check fails "trace-limits session: internal path hidden"
            (!line.contains temporaryRoot.toString) line
          match Codec.ModelInterfaceDistributionJson.parseRegisterErrorFailureBytes
              line.toUTF8 with
          | .error error =>
              check fails "trace-limits session: structured failure parses"
                false error
          | .ok (json, failure) =>
              check fails "trace-limits session: register_error tag"
                (match Codec.decodeMirror json with
                 | .ok (.registerError _) => true
                 | _ => false)
              check fails "trace-limits session: stable failure code"
                (failure.map (·.code) == some "interface_trace_preflight_failed")
        finishSession fails "trace-limits session" session
  finally
    IO.FS.removeDirAll temporaryRoot

def scenarioTraceLimitPolicy (fails : Failures) (fixtures : Fixtures) : IO Unit := do
  let overLimitPaths := List.replicate
    (Shell.Mirror.negotiatedTraceLoadLimitsV1.maxFiles + 1) tracePath

  -- `prefer` treats only the negotiation aggregate budget as optional. The
  -- already-supplied traces are loaded once through the legacy path, evidence
  -- becomes unavailable, and replay still starts.
  let preferred ← startSession
  match registrationJsonWithPaths overLimitPaths
      (some (descriptorPreferRequest fixtures.contract)) with
  | .error error => check fails "trace-limit prefer: registration" false error
  | .ok json =>
      preferred.client.send (Lean.Json.compress json)
      match ← receiveSpecValidated fails preferred.client
          "trace-limit prefer: spec_validated" with
      | none => pure ()
      | some (_, reply) =>
          check fails "trace-limit prefer: unavailable reply"
            (reply.map (·.status) == some .unavailable)
          if ← expectMirror fails preferred.client
              "trace-limit prefer: legacy replay starts" fun
              | .initialState _ _ => true
              | _ => false then
            -- Stop on the first replay mismatch instead of driving all 257
            -- copies. Completion proves the fallback did not wait for a
            -- second generation or strict-load attempt.
            sendCount preferred.client 999
            let _ ← expectMirror fails preferred.client
              "trace-limit prefer: replay mismatch" fun
              | .stepMismatch _ _ _ => true
              | _ => false
            pure ()
  finishSession fails "trace-limit prefer" preferred

  -- The same optional-resource failure is terminal under `require` and must
  -- occur before any replay message.
  let required ← startSession
  match registrationJsonWithPaths overLimitPaths
      (some (descriptorRequest fixtures.contract)) with
  | .error error => check fails "trace-limit require: registration" false error
  | .ok json =>
      required.client.send (Lean.Json.compress json)
      match ← recvLine required.client with
      | .error error => check fails "trace-limit require: response" false error
      | .ok line =>
          match Codec.ModelInterfaceDistributionJson.parseRegisterErrorFailureBytes
              line.toUTF8 with
          | .error error =>
              check fails "trace-limit require: structured failure" false error
          | .ok (json, failure) =>
              check fails "trace-limit require: register_error"
                (match Codec.decodeMirror json with
                 | .ok (.registerError _) => true
                 | _ => false)
              check fails "trace-limit require: preflight code"
                (failure.map (·.code) ==
                  some "interface_trace_preflight_failed")
  finishSession fails "trace-limit require" required

def scenarioIneligibleNegotiationUsesLegacy (fails : Failures)
    (fixtures : Fixtures) : IO Unit := do
  let temporaryRoot ← IO.FS.createTempDir
  try
    let path := temporaryRoot / "legacy-shape.itf.json"
    -- The undeclared field is accepted and ignored by the historical parser,
    -- but marks strict compiler evidence invalid. Unsupported/disabled
    -- requests must not opt legacy replay into that stricter admission path.
    IO.FS.writeFile path <|
      "{\"vars\":[\"action_taken\",\"count\"],\"states\":[{" ++
      "\"action_taken\":\"init\",\"count\":0,\"legacy_extra\":1}]}"
    let runCase (label : String)
        (access : Shell.ModelInterface.Runtime.Access)
        (request : Codec.ModelInterfaceDistributionJson.RequestV1)
        (expected : NegotiationStatus) : IO Unit := do
      let session ← startSession access
      match registrationJsonWithPaths [path.toString] (some request) with
      | .error error => check fails (label ++ ": registration") false error
      | .ok json =>
          session.client.send (Lean.Json.compress json)
          match ← receiveSpecValidated fails session.client
              (label ++ ": spec_validated") with
          | none => pure ()
          | some (_, reply) =>
              check fails (label ++ ": status")
                (reply.map (·.status) == some expected)
              if ← expectMirror fails session.client (label ++ ": initial_state") fun
                  | .initialState _ _ => true
                  | _ => false then
                sendCount session.client 0
                let _ ← expectMirror fails session.client (label ++ ": step_ok") fun
                  | .stepOk => true
                  | _ => false
                let _ ← expectMirror fails session.client
                  (label ++ ": all_steps_done") fun
                  | .allStepsDone => true
                  | _ => false
                pure ()
      finishSession fails label session
    runCase "unsupported legacy loader" .descriptor
      (unsupportedSchemaRequest fixtures.contract .prefer) .unsupported
    runCase "disabled legacy loader" .disabled
      (descriptorPreferRequest fixtures.contract) .unavailable

    let legacyError := "legacy oracle failure remains visible"
    let failingOracles : Shell.Mirror.Oracles := {
      Shell.Mirror.stubOracles with
        generateTraces := fun _ _ _ _ _ => pure (.error legacyError)
    }
    let errorSession ← startSessionWith failingOracles .disabled
    match ← sendGeneratedRegistration errorSession.client
        (descriptorPreferRequest fixtures.contract) with
    | .error error =>
        check fails "disabled legacy error: send" false error
    | .ok () =>
        match ← recvLine errorSession.client with
        | .error error =>
            check fails "disabled legacy error: response" false error
        | .ok line =>
            let expected := Lean.Json.compress <|
              Codec.encodeMirror (.registerError legacyError)
            check fails "disabled legacy error: exact response retained"
              (line == expected) s!"{line} vs {expected}"
    finishSession fails "disabled legacy error" errorSession

    let missingPath := temporaryRoot / "missing.itf.json"
    let missingSession ← startSession .disabled
    match registrationJsonWithPaths [missingPath.toString]
        (some (descriptorPreferRequest fixtures.contract)) with
    | .error error =>
        check fails "disabled trace error: registration" false error
    | .ok json =>
        missingSession.client.send (Lean.Json.compress json)
        match ← recvLine missingSession.client with
        | .error error =>
            check fails "disabled trace error: response" false error
        | .ok line =>
            match Codec.ModelInterfaceDistributionJson.parseRegisterErrorFailureBytes
                line.toUTF8 with
            | .error error =>
                check fails "disabled trace error: parse" false error
            | .ok (json, failure) =>
                check fails "disabled trace error: no interface extension"
                  failure.isNone line
                match Codec.decodeMirror json with
                | .ok (.registerError message) =>
                    check fails "disabled trace error: legacy detail retained"
                      (message.contains "missing.itf.json" &&
                        message != "interface_trace_preflight_failed") message
                | _ => check fails "disabled trace error: register_error" false line
    finishSession fails "disabled trace error" missingSession
  finally
    IO.FS.removeDirAll temporaryRoot

def scenarioInvalidEvidencePreferTerminal (fails : Failures)
    (fixtures : Fixtures) : IO Unit := do
  let trace ← match ← Shell.Mirror.readItfTrace tracePath with
    | .ok trace => pure trace
    | .error error =>
        check fails "invalid evidence prefer: fixture trace" false error
        pure default
  let source : SourceDigest := {
    moduleName := "Counter"
    logicalPath := "Counter.tla"
    contentSha256 := String.ofList (List.replicate 64 '0')
  }
  let oracles : Shell.Mirror.Oracles := {
    Shell.Mirror.stubOracles with
      generateTraces := fun _ _ _ _ _ => pure (.ok {
        traces := [trace]
        evidence := some fixtures.evidence
        evidenceInvalid := true
        sources := [source]
      })
  }
  let session ← startSessionWith oracles
  match ← sendGeneratedRegistration session.client
      (descriptorPreferRequest fixtures.contract) with
  | .error error =>
      check fails "invalid evidence prefer: registration" false error
  | .ok () =>
      match ← recvLine session.client with
      | .error error => check fails "invalid evidence prefer: response" false error
      | .ok line =>
          match Codec.ModelInterfaceDistributionJson.parseRegisterErrorFailureBytes
              line.toUTF8 with
          | .error error =>
              check fails "invalid evidence prefer: structured failure" false error
          | .ok (json, failure) =>
              check fails "invalid evidence prefer: register_error"
                (match Codec.decodeMirror json with
                 | .ok (.registerError _) => true
                 | _ => false)
              check fails "invalid evidence prefer: terminal preflight code"
                (failure.map (·.code) ==
                  some "interface_trace_preflight_failed")
  finishSession fails "invalid evidence prefer" session

def scenarioGeneratedFallbackPolicyFlag (fails : Failures)
    (fixtures : Fixtures) : IO Unit := do
  let runCase (label : String)
      (access : Shell.ModelInterface.Runtime.Access)
      (request : Codec.ModelInterfaceDistributionJson.RequestV1)
      (expected : Bool × Bool) : IO Unit := do
    let seen ← IO.mkRef (none : Option (Bool × Bool))
    let oracles : Shell.Mirror.Oracles := {
      Shell.Mirror.stubOracles with
        generateTraces := fun _ _ _ preserve allowFallback => do
          seen.set (some (preserve, allowFallback))
          return .error "injected stop after observing generation policy"
    }
    let session ← startSessionWith oracles access
    match ← sendGeneratedRegistration session.client request with
    | .error error => check fails (label ++ ": registration") false error
    | .ok () =>
        -- The injected stop deliberately ends registration after the flags
        -- cross the oracle seam; its sanitized register_error is not the
        -- subject of this focused assertion.
        let _ ← recvLine session.client
        pure ()
    finishSession fails label session
    check fails (label ++ ": generation flags")
      ((← seen.get) == some expected) (toString (repr (← seen.get)))

  runCase "generated flag prefer" .descriptor
    (descriptorPreferRequest fixtures.contract) (true, true)
  runCase "generated flag require" .descriptor
    (descriptorRequest fixtures.contract) (true, false)
  runCase "generated flag unsupported" .descriptor
    (unsupportedSchemaRequest fixtures.contract .prefer) (false, false)
  runCase "generated flag disabled" .disabled
    (descriptorPreferRequest fixtures.contract) (false, false)

def run : IO UInt32 := do
  let fails ← IO.mkRef ([] : List String)
  let fixtures ← loadFixtures fails
  let scenario (name : String) (body : IO Unit) : IO Unit := do
    IO.eprintln s!"[scenario {name}]"
    try body
    catch error =>
      fails.modify (fun fs => fs ++ [s!"{name}: exception: {error}"])

  scenario "legacy" (scenarioLegacy fails)
  match fixtures with
  | some fixtures =>
      scenario "descriptor" (scenarioDescriptor fails fixtures)
      scenario "not-modified" (scenarioNotModified fails fixtures)
      scenario "unsupported-require" (scenarioUnsupportedRequire fails fixtures)
      scenario "unsupported-prefer" (scenarioUnsupportedPrefer fails fixtures)
      scenario "disabled-require" (scenarioDisabledRequire fails fixtures)
      scenario "verify" (scenarioVerify fails fixtures)
      scenario "wrong-digest" (scenarioWrongDigest fails fixtures)
      scenario "preflight-reject" (scenarioPreflightRejectsReplay fails fixtures)
      scenario "unreadable-trace" (scenarioUnreadableTraceRejectsReplay fails fixtures)
      scenario "oracle-failure-sanitized"
        (scenarioOracleFailureSanitized fails fixtures)
      scenario "negotiated-trace-limits"
        (scenarioNegotiatedTraceLimits fails fixtures)
      scenario "trace-limit-policy" (scenarioTraceLimitPolicy fails fixtures)
      scenario "ineligible-negotiation-legacy-loader"
        (scenarioIneligibleNegotiationUsesLegacy fails fixtures)
      scenario "invalid-evidence-prefer-terminal"
        (scenarioInvalidEvidencePreferTerminal fails fixtures)
      scenario "generated-fallback-policy-flag"
        (scenarioGeneratedFallbackPolicyFlag fails fixtures)
  | none =>
      check fails "negotiated scenarios: fixtures available" false
  scenario "duplicate-nested-key" (scenarioDuplicateNestedKey fails)
  scenario "attacker-diagnostics-sanitized"
    (scenarioAttackerDiagnosticsSanitized fails)

  let failures ← fails.get
  if failures.isEmpty then
    IO.println "MODEL INTERFACE DISTRIBUTION SPEC GREEN"
    return 0
  else
    for failure in failures do IO.eprintln s!"FAIL {failure}"
    IO.eprintln s!"{failures.length} FAILURES"
    return 1

end ModelInterfaceDistributionSpec

def main : IO UInt32 :=
  ModelInterfaceDistributionSpec.run
