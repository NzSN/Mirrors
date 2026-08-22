import Shell.Net.Http
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

def newRpcClient (port : Nat) : IO RpcClient := do
  return ⟨port, ← IO.mkRef 1⟩

/-- One JSON-RPC call over HTTP (Haskell @rpcCall@). -/
def rpcCall (client : RpcClient) (method : String) (params : Json) :
    IO (RpcResult Json) := do
  let id ← client.nextId.modifyGet (fun n => (n, n + 1))
  let body := Json.compress (rpcRequestJson method params id)
  match ← Shell.Net.Http.post client.port "/rpc" body with
  | .error e => return .error (.httpError e)
  | .ok resp =>
      if resp.status != 200 then
        return .error (.httpError s!"HTTP {resp.status}")
      else
        match Json.parse resp.body with
        | .error e => return .error (.parseError e)
        | .ok j => return decodeRpcResponse j

-- PART2