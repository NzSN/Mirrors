import Shell.Net.Http
import Shell.Apalache.Cli
import Core.Value
import Codec.Json
import Shell.Mirror.Session
import Lean.Data.Json

/-!
# Shell.Apalache.Explorer — the apalache explorer JSON-RPC client (t14)

Port of the Haskell @Apalache.Rpc.Types@ / @Rpc.Client@ / @Explorer@:
a JSON-RPC 2.0 client over the pure-Lean HTTP client (@Shell.Net.Http@;
the t14 spike decision), the typed method surface, and the explorer
session flows plus server lifecycle (spawn the explorer server on an
ephemeral loopback port, health-poll until ready, terminate on stop).
Transcript parity lives in @tools/ExplorerSpec.lean@.
-/

namespace Shell.Apalache.Explorer

open Lean

/-! ## JSON-RPC envelope -/

inductive RpcError
  /-- Transport-level (HTTP or socket) failure. -/
  | httpError (msg : String)
  /-- JSON-RPC error object from the server. -/
  | protocolError (code : Int) (msg : String)
  /-- Response shape or decode failure. -/
  | parseError (msg : String)
deriving Repr

def rpcErrorText : RpcError → String
  | .httpError m => s!"RpcHttpError {m}"
  | .protocolError c m => s!"RpcProtocolError {c} {m}"
  | .parseError m => s!"RpcParseError {m}"

abbrev RpcResult (α : Type) := Except RpcError α

/-- One JSON-RPC 2.0 request (fields in the recorded transcript order:
id, jsonrpc, method, params — byte-identical to the Haskell encoder). -/
def rpcRequestJson (method : String) (params : Json) (id : Nat) : Json :=
  Json.mkObj
    [ ("id", .num ⟨id, 0⟩)
    , ("jsonrpc", .str "2.0")
    , ("method", .str method)
    , ("params", params) ]

/-- Decode a JSON-RPC 2.0 response envelope. -/
def decodeRpcResponse (j : Json) : RpcResult Json := do
  let obj ← match j with
    | .obj o => pure o
    | _ => .error (.parseError "rpc response is not an object")
  match obj.get? "error" with
  | some (.obj e) =>
      let codeField := e.get? "code"
      let msgField := e.get? "message"
      let codeInt := match codeField with
        | some (.num n) => n.mantissa | _ => 0
      let msgS := match msgField with
        | some (.str s) => s | _ => ""
      .error (.protocolError codeInt msgS)
  | some _ => .error (.parseError "error field must be an object")
  | none =>
      match obj.get? "result" with
      | some r => pure r
      | none => .error (.parseError "no result in rpc response")

/-- The client (Haskell @RpcClient@): loopback port + request-id counter. -/
structure RpcClient where
  port : Nat
  nextId : IO.Ref Nat
  /- Persistent keep-alive connection: the apalache server (Jetty +
     async jsonrpc4s handlers) sporadically answers 200 with an empty
     body when each request arrives on a fresh Connection: close
     socket, so all calls of a session share one connection, like the
     Haskell http-client manager. -/
  conn : IO.Ref (Option Shell.Net.Http.Conn)

def newRpcClient (port : Nat) : IO RpcClient := do
  return ⟨port, ← IO.mkRef 1, ← IO.mkRef none⟩

private def rpcOnce (client : RpcClient) (body : String)
    (dbg? : Option String) : IO (RpcResult String) := do
  -- make sure the persistent connection is open
  let c0 ← client.conn.get
  let c ← match c0 with
    | some c => pure c
    | none =>
        match ← Shell.Net.Http.openConn client.port 30000 with
        | .error e => return .error (.httpError e)
        | .ok c =>
            client.conn.set (some c)
            pure c
  match ← Shell.Net.Http.postKa c client.port "/rpc" body with
  | .error e =>
      -- stale connection: drop it and fail (caller retries once)
      Shell.Net.Http.closeConn c
      client.conn.set none
      if dbg?.isSome then IO.eprintln s!"rpc: transport error ({e})"
      return .error (.httpError e)
  | .ok resp =>
      if dbg?.isSome then
        IO.eprintln s!"rpc: -> {resp.status} len={resp.body.length}"
      if resp.status != 200 then
        return .error (.httpError s!"HTTP {resp.status}")
      else
        return .ok resp.body

/-- One JSON-RPC call over HTTP (Haskell @rpcCall@). -/
def rpcCall (client : RpcClient) (method : String) (params : Json) :
    IO (RpcResult Json) := do
  let id ← client.nextId.modifyGet (fun n => (n, n + 1))
  let body := Json.compress (rpcRequestJson method params id)
  let dbg? ← IO.getEnv "DSH_EXPLORER_DEBUG"
  if dbg?.isSome then IO.eprintln s!"rpc: POST {method} -> port {client.port}"
  let res1 ← rpcOnce client body dbg?
  let raw ← match res1 with
    | .ok b => pure b
    | .error _ =>
        -- one retry on a fresh connection
        let id2 ← client.nextId.modifyGet (fun n => (n, n + 1))
        let body2 := Json.compress (rpcRequestJson method params id2)
        match ← rpcOnce client body2 dbg? with
        | .ok b => pure b
        | .error e => return .error e
  if raw.isEmpty then
    return .error (.protocolError (-32000) s!"empty 200 body for {method}")
  match Json.parse raw with
  | .error e => return .error (.parseError e)
  | .ok j => return decodeRpcResponse j

/-! ## Typed method surface -/

inductive TransitionStatus | transEnabled | transDisabled | transUnknown
deriving BEq
inductive InvariantStatus | invSatisfied | invViolated | invUnknown
deriving BEq
inductive InvariantKind | stateInvariant | actionInvariant
inductive QueryKind | queryTrace | queryState | queryOperator

structure SpecParams where
  initTransitions : List (Nat × List String)
  nextTransitions : List (Nat × List String)
  stateInvariants : List (Nat × List String)
  actionInvariants : List (Nat × List String)
deriving Repr

structure HealthResult where
  status : String
deriving Repr

structure LoadSpecResult where
  sessionId : String
  snapshotId : Nat
  specParams : SpecParams
deriving Repr

structure LoadSpecParams where
  sources : List String
  init : Option String
  next : Option String
  invariants : List String
  exports : List String

structure Explorer where
  client : RpcClient
  sessionId : String
  snapshot : Nat
  params : SpecParams

private def getStr (j : Json) (k : String) : Except String String :=
  match j.getObjVal? k with
  | .ok (.str s) => .ok s
  | _ => .error s!"field {k}: string expected"

private def getNat (j : Json) (k : String) : Except String Nat :=
  match j.getObjVal? k with
  | .ok (.num n) => .ok n.mantissa.toNat
  | _ => .error s!"field {k}: number expected"

private def getStrList (j : Json) (k : String) : Except String (List String) :=
  match j.getObjVal? k with
  | .ok (.arr as) =>
      let rec toS : List Json → Except String (List String)
        | [] => .ok []
        | x :: rest => match x with
          | .str s => (toS rest).map (s :: ·)
          | _ => .error s!"field {k}: string array expected"
      toS as.toList
  | _ => .error s!"field {k}: array expected"

private def getRefList (j : Json) (k : String) : Except String (List (Nat × List String)) :=
  match j.getObjVal? k with
  | .ok (.arr as) =>
      let rec go : List Json → Except String (List (Nat × List String))
        | [] => .ok []
        | x :: rest => do
            let i ← getNat x "index"
            let ls ← getStrList x "labels"
            let t ← go rest
            return (i, ls) :: t
      go as.toList
  | _ => .error s!"field {k}: array expected"

def parseSpecParams (j : Json) : Except String SpecParams := do
  let i ← getRefList j "initTransitions"
  let n ← getRefList j "nextTransitions"
  let s ← getRefList j "stateInvariants"
  let a ← getRefList j "actionInvariants"
  return { initTransitions := i, nextTransitions := n,
           stateInvariants := s, actionInvariants := a }

private def parseLoadSpecResult (j : Json) : RpcResult LoadSpecResult :=
  match do
    let sid ← getStr j "sessionId"
    let snap ← getNat j "snapshotId"
    let sp ← match j.getObjVal? "specParameters" with
      | .ok sp => parseSpecParams sp
      | _ => .error "field specParameters: object expected"
    return { sessionId := sid, snapshotId := snap, specParams := sp : LoadSpecResult }
  with
  | .ok r => .ok r
  | .error e => .error (.parseError e)

def parseTransitionStatus (s : String) : TransitionStatus :=
  if s == "ENABLED" then .transEnabled
  else if s == "DISABLED" then .transDisabled
  else .transUnknown

def parseInvariantStatus (s : String) : InvariantStatus :=
  if s == "SATISFIED" then .invSatisfied
  else if s == "VIOLATED" then .invViolated
  else .invUnknown

def transitionStatusText : TransitionStatus → String
  | .transEnabled => "ENABLED" | .transDisabled => "DISABLED" | .transUnknown => "UNKNOWN"

def invariantStatusText : InvariantStatus → String
  | .invSatisfied => "SATISFIED" | .invViolated => "VIOLATED" | .invUnknown => "UNKNOWN"

private def kindText : InvariantKind → String
  | .stateInvariant => "STATE" | .actionInvariant => "ACTION"

/-! ## The eight methods -/

def health (client : RpcClient) : IO (RpcResult HealthResult) := do
  match ← rpcCall client "health" (.arr #[]) with
  | .error e => return .error e
  | .ok j => match getStr j "status" with
    | .ok s => return .ok ⟨s⟩
    | .error e => return .error (.parseError e)

def loadSpec (client : RpcClient) (p : LoadSpecParams) : IO (RpcResult LoadSpecResult) := do
  let params := Json.mkObj
    [ ("sources", .arr (p.sources.map Json.str |>.toArray))
    , ("init", p.init.map Json.str |>.getD .null)
    , ("next", p.next.map Json.str |>.getD .null)
    , ("invariants", .arr (p.invariants.map Json.str |>.toArray))
    , ("exports", .arr (p.exports.map Json.str |>.toArray)) ]
  match ← rpcCall client "loadSpec" params with
  | .error e => return .error e
  | .ok j => return parseLoadSpecResult j

structure AssumeTransitionParams where
  sessionId : String
  transitionId : Nat
  checkEnabled : Bool
  timeoutSec : Option Nat

structure AssumeTransitionResult where
  sessionId : String
  snapshotId : Nat
  transitionId : Nat
  status : TransitionStatus

def assumeTransition (client : RpcClient) (p : AssumeTransitionParams) :
    IO (RpcResult AssumeTransitionResult) := do
  let params := Json.mkObj
    [ ("sessionId", .str p.sessionId)
    , ("transitionId", .num ⟨p.transitionId, 0⟩)
    , ("checkEnabled", .bool p.checkEnabled)
    , ("timeoutSec", p.timeoutSec.map (fun n => .num ⟨n, 0⟩) |>.getD .null) ]
  match ← rpcCall client "assumeTransition" params with
  | .error e => return .error e
  | .ok j =>
      match do
        let sid ← getStr j "sessionId"
        let snap ← getNat j "snapshotId"
        let tid ← getNat j "transitionId"
        let st ← getStr j "status"
        return { sessionId := sid, snapshotId := snap, transitionId := tid,
                 status := parseTransitionStatus st : AssumeTransitionResult }
      with
      | .ok r => return .ok r
      | .error e => return .error (.parseError e)

structure NextStateResult where
  sessionId : String
  snapshotId : Nat
  newStepNo : Nat

def nextStep (client : RpcClient) (sessionId : String) :
    IO (RpcResult NextStateResult) := do
  match ← rpcCall client "nextStep" (Json.mkObj [("sessionId", .str sessionId)]) with
  | .error e => return .error e
  | .ok j =>
      match do
        let sid ← getStr j "sessionId"
        let snap ← getNat j "snapshotId"
        let step ← getNat j "newStepNo"
        return { sessionId := sid, snapshotId := snap, newStepNo := step : NextStateResult }
      with
      | .ok r => return .ok r
      | .error e => return .error (.parseError e)

structure CheckInvariantResult where
  sessionId : String
  status : InvariantStatus
  trace : Option ItfTrace

def checkInvariant (client : RpcClient) (sessionId : String) (invariantId : Nat)
    (kind : InvariantKind) : IO (RpcResult CheckInvariantResult) := do
  let params := Json.mkObj
    [ ("sessionId", .str sessionId)
    , ("invariantId", .num ⟨invariantId, 0⟩)
    , ("kind", .str (kindText kind))
    , ("timeoutSec", .null) ]
  match ← rpcCall client "checkInvariant" params with
  | .error e => return .error e
  | .ok j =>
      let st := match j.getObjVal? "invariantStatus" with
        | .ok (.str s) => parseInvariantStatus s
        | _ => .invUnknown
      let trace := match j.getObjVal? "trace" with
        | .ok tj =>
            match Shell.Mirror.parseItfTrace tj with
            | .ok t => some t | .error _ => none
        | _ => none
      let sid := match getStr j "sessionId" with | .ok s => s | .error _ => sessionId
      return .ok { sessionId := sid, status := st, trace := trace }

structure QueryResult where
  sessionId : String
  state : Option ValueMap

def query (client : RpcClient) (sessionId : String) (kind : QueryKind)
    (op : Option String) : IO (RpcResult QueryResult) := do
  let kindS := match kind with
    | .queryTrace => "TRACE" | .queryState => "STATE" | .queryOperator => "OPERATOR"
  let params := Json.mkObj
    [ ("sessionId", .str sessionId)
    , ("kinds", .arr #[.str kindS])
    , ("operator", op.map Json.str |>.getD .null)
    , ("timeoutSec", .null) ]
  match ← rpcCall client "query" params with
  | .error e => return .error e
  | .ok j =>
      let st := match j.getObjVal? "state" with
        | .ok sj => (Shell.Mirror.decodeStateMap sj).toOption
        | _ => none
      let sid := match getStr j "sessionId" with | .ok s => s | .error _ => sessionId
      return .ok { sessionId := sid, state := st }

structure AssumeStateResult where
  sessionId : String
  snapshotId : Nat
  status : TransitionStatus

def assumeState (client : RpcClient) (sessionId : String) (equalities : ValueMap) :
    IO (RpcResult AssumeStateResult) := do
  let params := Json.mkObj
    [ ("sessionId", .str sessionId)
    , ("checkEnabled", .bool true)
    , ("timeoutSec", .null)
    , ("equalities", Json.mkObj
        (equalities.map (fun (k, v) => (k, Codec.encValue v)))) ]
  match ← rpcCall client "assumeState" params with
  | .error e => return .error e
  | .ok j =>
      match do
        let sid ← getStr j "sessionId"
        let snap ← getNat j "snapshotId"
        let st ← getStr j "status"
        return { sessionId := sid, snapshotId := snap,
                 status := parseTransitionStatus st : AssumeStateResult }
      with
      | .ok r => return .ok r
      | .error e => return .error (.parseError e)

def rollback (client : RpcClient) (sessionId : String) (snapshotId : Nat) :
    IO (RpcResult Unit) := do
  match ← rpcCall client "rollback"
      (Json.mkObj [("sessionId", .str sessionId), ("snapshotId", .num ⟨snapshotId, 0⟩)]) with
  | .error e => return .error e
  | .ok _ => return .ok ()

def disposeSpec (client : RpcClient) (sessionId : String) :
    IO (RpcResult Unit) := do
  match ← rpcCall client "disposeSpec" (Json.mkObj [("sessionId", .str sessionId)]) with
  | .error e => return .error e
  | .ok _ => return .ok ()

/-! ## Base64 (for loadSpec sources) -/

private def b64alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

/-- Base64-encode UTF-8 (Haskell @encodeB64@, standard alphabet). -/
def encodeB64 (s : String) : String := Id.run do
  let bytes := s.toUTF8
  let n := bytes.size
  let mut out := ""
  let mut i := 0
  while i < n do
    let b0 := bytes.get! i
    let b1 := if i + 1 < n then bytes.get! (i+1) else 0
    let b2 := if i + 2 < n then bytes.get! (i+2) else 0
    let trip := (b0.toNat <<< 16) ||| (b1.toNat <<< 8) ||| b2.toNat
    let al := b64alphabet.toList
    let ch (k : Nat) : String := String.ofList [al.getD k 'A']
    out := out ++ ch (trip >>> 18 &&& 63) ++ ch (trip >>> 12 &&& 63)
    if i + 1 < n then out := out ++ ch (trip >>> 6 &&& 63) else out := out ++ "="
    if i + 2 < n then out := out ++ ch (trip &&& 63) else out := out ++ "="
    i := i + 3
  return out

/-! ## Server lifecycle + session flows -/

structure ApalacheServer where
  port : Nat
  process : IO.Process.Child { stdin := .null, stdout := .piped, stderr := .inherit }

/-- Pick an ephemeral loopback port (Haskell @freePort@): bind port 0,
read the assigned port, close. -/
def freePort : IO Nat := do
  let fd ← Ffi.tcpSocket
  if fd == Ffi.fdError then return 8822
  let b ← Ffi.bindLoopback fd 0
  if b == Ffi.fdError then
    Ffi.closeFd fd
    return 8822
  let p ← Ffi.localPort fd
  Ffi.closeFd fd
  return p.toNat

private def killIgnoring {cfg : IO.Process.StdioConfig}
    (child : IO.Process.Child cfg) : IO Unit := do
  try child.kill catch _ => pure ()

/-- Start an apalache explorer server (Haskell @startApalacheServer@):
ephemeral loopback port, server stdout drained to stderr (the stdio
transport carries protocol JSON there), health-polled until ready. -/
def startApalacheServer (mPort : Option Nat) : IO ApalacheServer := do
  let bin ← Shell.Apalache.Cli.apalacheBin
  let port := mPort.getD (← freePort)
  let child ← IO.Process.spawn
    { cmd := bin, args := #["server", s!"--port={port}", "--server-type=explorer"],
      env := #[("LC_ALL", some "C.UTF-8")], stdin := .null,
      stdout := .piped, stderr := .inherit }
  let outH := (child.stdout : IO.FS.Handle)
  let _task ← IO.asTask (prio := Task.Priority.dedicated) do
    let mut line ← outH.getLine
    while !line.isEmpty do
      IO.eprint line
      line ← outH.getLine
  let client ← newRpcClient port
  let mut ready := false
  let mut tries := 0
  while !ready && tries < 60 do
    match ← health client with
    | .ok _ => ready := true
    | _ => IO.sleep 500; tries := tries + 1
  if !ready then
    killIgnoring child
    throw (IO.userError "apalache explorer server did not become healthy")
  return ⟨port, child⟩

/-- Terminate + reap the server (total). -/
def stopApalacheServer (server : ApalacheServer) : IO Unit := do
  killIgnoring server.process
  let _ ← server.process.wait

/-- Run with a started explorer server, guaranteeing shutdown
(Haskell @withApalacheServer@). -/
def withApalacheServer {α : Type} (act : ApalacheServer → IO α) : IO α := do
  let server ← startApalacheServer none
  try act server
  finally stopApalacheServer server

/-- Load a spec into a fresh explorer session (Haskell @newExplorer@);
sources are base64-encoded per the server contract, and the init/next
operator names select the transitions (recorded transcripts use
"Init"/"Next"). -/
def newExplorer (client : RpcClient) (sources : List String)
    (init next : Option String) (invs exports : List String) :
    IO (RpcResult Explorer) := do
  match ← loadSpec client
    { sources := sources.map encodeB64, init := init, next := next,
      invariants := invs, exports := exports } with
  | .error e => return .error e
  | .ok lsr =>
      return .ok { client := client, sessionId := lsr.sessionId,
                   snapshot := lsr.snapshotId, params := lsr.specParams }

/-- Assume init transition 0 (if any) and advance one step
(Haskell @exploreInit@). -/
def exploreInit (expl : Explorer) : IO (RpcResult Explorer) := do
  if expl.params.initTransitions.isEmpty then
    return .ok expl
  else
    match ← assumeTransition expl.client
        { sessionId := expl.sessionId, transitionId := 0,
          checkEnabled := true, timeoutSec := none } with
    | .error e => return .error e
    | .ok _ =>
        match ← nextStep expl.client expl.sessionId with
        | .error e => return .error e
        | .ok nsr => return .ok { expl with snapshot := nsr.snapshotId }

/-- Assume transition tid; when enabled, advance one step (Haskell
@exploreNext@). -/
def exploreNext (expl : Explorer) (tid : Nat) :
    IO (RpcResult (Explorer × TransitionStatus)) := do
  match ← assumeTransition expl.client
      { sessionId := expl.sessionId, transitionId := tid,
        checkEnabled := true, timeoutSec := none } with
  | .error e => return .error e
  | .ok atr =>
      if atr.status == .transEnabled then
        match ← nextStep expl.client expl.sessionId with
        | .error e => return .error e
        | .ok nsr => return .ok ({ expl with snapshot := nsr.snapshotId }, .transEnabled)
      else
        return .ok (expl, atr.status)

/-- Check invariant iid (Haskell @exploreCheck@). -/
def exploreCheck (expl : Explorer) (iid : Nat) :
    IO (RpcResult (InvariantStatus × Option ItfTrace)) := do
  match ← checkInvariant expl.client expl.sessionId iid .stateInvariant with
  | .error e => return .error e
  | .ok cir => return .ok (cir.status, cir.trace)

/-- Query the current state valuation (Haskell @exploreQueryState@). -/
def exploreQueryState (expl : Explorer) : IO (RpcResult ValueMap) := do
  match ← query expl.client expl.sessionId .queryState none with
  | .error e => return .error e
  | .ok qr => match qr.state with
    | some s => return .ok s
    | none => return .error (.parseError "query did not return state")

/-- Assume a full state valuation (Haskell @exploreAssumeState@). -/
def exploreAssumeState (expl : Explorer) (equalities : ValueMap) :
    IO (RpcResult (Explorer × TransitionStatus)) := do
  match ← assumeState expl.client expl.sessionId equalities with
  | .error e => return .error e
  | .ok asr =>
      return .ok ({ expl with snapshot := asr.snapshotId }, asr.status)

/-- Roll back to a snapshot (Haskell @exploreRollback@). -/
def exploreRollback (expl : Explorer) (snap : Nat) : IO (RpcResult Explorer) := do
  match ← rollback expl.client expl.sessionId snap with
  | .error e => return .error e
  | .ok _ => return .ok { expl with snapshot := snap }

/-- Dispose the spec session (best-effort). -/
def exploreDispose (expl : Explorer) : IO (RpcResult Unit) :=
  disposeSpec expl.client expl.sessionId

end Shell.Apalache.Explorer