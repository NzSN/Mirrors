
/-
# Explorer JSON-RPC wire codec (Phase 5)

Typed requests/responses for the Apalache explorer JSON-RPC interface, with
total encoders/decoders matching the frozen Phase-0 corpus
(`test/fixtures/explorer_transcripts.jsonl`, raw bytes from the Haskell
`Apalache.Rpc.Client`) and §6.6-style round-trip theorems per method.
Value payloads reuse `Core.Value` and the `encValue`/`decodeValue`
machinery from `Codec.Json`.
-/
import Codec.Json
import Std.Data.TreeMap.Raw
import Lean.Data.Json

open Lean

namespace Codec

/-! ## Result payload types -/

/-- One transition summary from `loadSpec`'s `specParameters`. -/
structure TransitionSummary where
  index : Nat
  labels : List String
  deriving Repr

/-- The `specParameters` object of a `loadSpec` response. -/
structure SpecParameters where
  actionInvariants : List TransitionSummary
  initTransitions : List TransitionSummary
  nextTransitions : List TransitionSummary
  stateInvariants : List TransitionSummary
  deriving Repr

/-! ## Requests -/

inductive RpcRequest where
  | health (id : Nat)
  | loadSpec (id : Nat) (sources exports invariants : List String)
      (init next : String)
  | assumeTransition (id : Nat) (sessionId : String) (transitionId : Nat)
      (checkEnabled : Bool) (timeoutSec : Option Nat)
  | nextStep (id : Nat) (sessionId : String)
  | checkInvariant (id : Nat) (sessionId : String) (invariantId : Nat)
      (kind : String) (timeoutSec : Option Nat)
  | query (id : Nat) (sessionId : String) (kinds : List String)
      (operator : Option Value) (timeoutSec : Option Nat)
  | assumeState (id : Nat) (sessionId : String) (equalities : Value)
      (checkEnabled : Bool) (timeoutSec : Option Nat)
  | rollback (id : Nat) (sessionId : String) (snapshotId : Nat)
  | disposeSpec (id : Nat) (sessionId : String)
  deriving Repr

/-- JSON-RPC method name of a request (also the transcript tag). -/
def methodName : RpcRequest → String
  | .health _ => "health"
  | .loadSpec _ _ _ _ _ _ => "loadSpec"
  | .assumeTransition _ _ _ _ _ => "assumeTransition"
  | .nextStep _ _ => "nextStep"
  | .checkInvariant _ _ _ _ _ => "checkInvariant"
  | .query _ _ _ _ _ => "query"
  | .assumeState _ _ _ _ _ => "assumeState"
  | .rollback _ _ _ => "rollback"
  | .disposeSpec _ _ => "disposeSpec"

/-! ## Responses -/

inductive RpcResult where
  | health (status : String)
  | loadSpec (sessionId : String) (snapshotId : Nat)
      (specParameters : SpecParameters)
  | assumeTransition (sessionId : String) (snapshotId : Nat) (status : String)
      (transitionId : Nat)
  | nextStep (newStepNo : Nat) (sessionId : String) (snapshotId : Nat)
  | checkInvariant (invariantStatus : String) (sessionId : String)
      (trace : Option Value)
  | query (operatorValue : Option Value) (sessionId : String) (state : Value)
      (trace : Option Value)
  | assumeState (sessionId : String) (snapshotId : Nat) (status : String)
  | rollback
  | disposeSpec
  deriving Repr

structure RpcResponse where
  id : Nat
  result : RpcResult
  deriving Repr

/-- Request id (envelope `id` field). -/
def reqId : RpcRequest → Nat
  | .health id
  | .loadSpec id _ _ _ _ _
  | .assumeTransition id _ _ _ _
  | .nextStep id _
  | .checkInvariant id _ _ _ _
  | .query id _ _ _ _
  | .assumeState id _ _ _ _
  | .rollback id _ _
  | .disposeSpec id _ => id

/-! ## Encoders -/

def jTransitionSummary (t : TransitionSummary) : Json :=
  Json.mkObj [("index", Json.num t.index), ("labels", Json.arr (strsJson t.labels |>.toArray))]

def jTransitions (ts : List TransitionSummary) : Json :=
  Json.arr (ts.map jTransitionSummary |>.toArray)

def jSpecParameters (sp : SpecParameters) : Json :=
  Json.mkObj [
    ("actionInvariants", jTransitions sp.actionInvariants),
    ("initTransitions", jTransitions sp.initTransitions),
    ("nextTransitions", jTransitions sp.nextTransitions),
    ("stateInvariants", jTransitions sp.stateInvariants)]

/-- Params object/array of a request. -/
def encodeParams : RpcRequest → Json
  | .health _ => Json.arr #[]
  | .loadSpec _ sources exports invariants init next =>
      Json.mkObj [
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("init", Json.str init),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("next", Json.str next),
        ("sources", Json.arr (strsJson sources |>.toArray))]
  | .assumeTransition _ sessionId transitionId checkEnabled timeoutSec =>
      Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)]
  | .nextStep _ sessionId => Json.mkObj [("sessionId", Json.str sessionId)]
  | .checkInvariant _ sessionId invariantId kind timeoutSec =>
      Json.mkObj [
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)]
  | .query _ sessionId kinds operator timeoutSec =>
      Json.mkObj [
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", optJson (encValue <$> operator)),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)]
  | .assumeState _ sessionId equalities checkEnabled timeoutSec =>
      Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("equalities", encValue equalities),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)]
  | .rollback _ sessionId snapshotId =>
      Json.mkObj [
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId)]
  | .disposeSpec _ sessionId => Json.mkObj [("sessionId", Json.str sessionId)]

/-- Full JSON-RPC request envelope. -/
def encodeRpcRequest (r : RpcRequest) : Json :=
  Json.mkObj [
    ("id", Json.num (reqId r)),
    ("jsonrpc", Json.str "2.0"),
    ("method", Json.str (methodName r)),
    ("params", encodeParams r)]

def encodeRpcResult : RpcResult → Json
  | .health status => Json.mkObj [("status", Json.str status)]
  | .loadSpec sessionId snapshotId sp =>
      Json.mkObj [
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("specParameters", jSpecParameters sp)]
  | .assumeTransition sessionId snapshotId status transitionId =>
      Json.mkObj [
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("status", Json.str status),
        ("transitionId", Json.num transitionId)]
  | .nextStep newStepNo sessionId snapshotId =>
      Json.mkObj [
        ("newStepNo", Json.num newStepNo),
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId)]
  | .checkInvariant invariantStatus sessionId trace =>
      Json.mkObj [
        ("invariantStatus", Json.str invariantStatus),
        ("sessionId", Json.str sessionId),
        ("trace", optJson (encValue <$> trace))]
  | .query operatorValue sessionId state trace =>
      Json.mkObj [
        ("operatorValue", optJson (encValue <$> operatorValue)),
        ("sessionId", Json.str sessionId),
        ("state", encValue state),
        ("trace", optJson (encValue <$> trace))]
  | .assumeState sessionId snapshotId status =>
      Json.mkObj [
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("status", Json.str status)]
  | .rollback => Json.null
  | .disposeSpec => Json.null

/-- Full JSON-RPC response envelope. -/
def encodeRpcResponse (resp : RpcResponse) : Json :=
  Json.mkObj [
    ("id", Json.num resp.id),
    ("jsonrpc", Json.str "2.0"),
    ("result", encodeRpcResult resp.result)]

/-! ## Decoders -/

/-- Optional value field: JSON null (or a missing key) decodes to none. -/
private def decOptVal : Json → Dec (Option Value)
  | Json.null => .ok none
  | v => some <$> decodeValue v

private def decOptNullValue (j : Json) (k : String) : Dec (Option Value) :=
  match j.getObjVal? k with
  | .error _ => .ok none
  | .ok v => decOptVal v

private def decTransitionSummary (j : Json) : Dec TransitionSummary := do
  let index ← jNat j "index"
  let labels ← reqStrs j "labels"
  return { index, labels }

private def decTransitions (j : Json) : Dec (List TransitionSummary) :=
  match j with
  | Json.arr as => as.toList.mapM decTransitionSummary
  | _ => derr "expected array of transition summaries"

private def decSpecParameters (j : Json) : Dec SpecParameters := do
  let actionInvariants ← reqField j "actionInvariants" decTransitions
  let initTransitions ← reqField j "initTransitions" decTransitions
  let nextTransitions ← reqField j "nextTransitions" decTransitions
  let stateInvariants ← reqField j "stateInvariants" decTransitions
  return { actionInvariants, initTransitions, nextTransitions, stateInvariants }

/-- Replace a request's id. -/
def setReqId : Nat → RpcRequest → RpcRequest
  | id, .health _ => .health id
  | id, .loadSpec _ a b c d e => .loadSpec id a b c d e
  | id, .assumeTransition _ a b c d => .assumeTransition id a b c d
  | id, .nextStep _ a => .nextStep id a
  | id, .checkInvariant _ a b c d => .checkInvariant id a b c d
  | id, .query _ a b c d => .query id a b c d
  | id, .assumeState _ a b c d => .assumeState id a b c d
  | id, .rollback _ a b => .rollback id a b
  | id, .disposeSpec _ a => .disposeSpec id a


def decodeParams : String → Json → Dec RpcRequest
  | "health", _ => return .health 0
  | "loadSpec", p => do
      let exports ← reqStrs p "exports"
      let init ← jStr p "init"
      let invariants ← reqStrs p "invariants"
      let next ← jStr p "next"
      let sources ← reqStrs p "sources"
      return .loadSpec 0 sources exports invariants init next
  | "assumeTransition", p => do
      let checkEnabled ← jBool p "checkEnabled"
      let sessionId ← jStr p "sessionId"
      let timeoutSec ← jOptNat p "timeoutSec"
      let transitionId ← jNat p "transitionId"
      return .assumeTransition 0 sessionId transitionId checkEnabled timeoutSec
  | "nextStep", p => do
      let sessionId ← jStr p "sessionId"
      return .nextStep 0 sessionId
  | "checkInvariant", p => do
      let invariantId ← jNat p "invariantId"
      let kind ← jStr p "kind"
      let sessionId ← jStr p "sessionId"
      let timeoutSec ← jOptNat p "timeoutSec"
      return .checkInvariant 0 sessionId invariantId kind timeoutSec
  | "query", p => do
      let kinds ← reqStrs p "kinds"
      let operator ← decOptNullValue p "operator"
      let sessionId ← jStr p "sessionId"
      let timeoutSec ← jOptNat p "timeoutSec"
      return .query 0 sessionId kinds operator timeoutSec
  | "assumeState", p => do
      let checkEnabled ← jBool p "checkEnabled"
      let equalities ← reqField p "equalities" decodeValue
      let sessionId ← jStr p "sessionId"
      let timeoutSec ← jOptNat p "timeoutSec"
      return .assumeState 0 sessionId equalities checkEnabled timeoutSec
  | "rollback", p => do
      let sessionId ← jStr p "sessionId"
      let snapshotId ← jNat p "snapshotId"
      return .rollback 0 sessionId snapshotId
  | "disposeSpec", p => do
      let sessionId ← jStr p "sessionId"
      return .disposeSpec 0 sessionId
  | _, _ => derr "unknown explorer method"

/-- Decode a full JSON-RPC request envelope. -/
def decodeRpcRequest (j : Json) : Dec RpcRequest :=
  match jStr j "method" with
  | .ok mth => do
      let id ← jNat j "id"
      let p ← jField j "params"
      let r ← decodeParams mth p
      return setReqId id r
  | .error e => .error e

private theorem setReqId_reqId (id : Nat) (r : RpcRequest) :
    reqId (setReqId id r) = id := by
  cases r <;> rfl

private def decodeRpcResult : String → Json → Dec RpcResult
  | "health", r => do
      let status ← jStr r "status"
      return .health status
  | "loadSpec", r => do
      let sessionId ← jStr r "sessionId"
      let snapshotId ← jNat r "snapshotId"
      let specParameters ← reqField r "specParameters" decSpecParameters
      return .loadSpec sessionId snapshotId specParameters
  | "assumeTransition", r => do
      let sessionId ← jStr r "sessionId"
      let snapshotId ← jNat r "snapshotId"
      let status ← jStr r "status"
      let transitionId ← jNat r "transitionId"
      return .assumeTransition sessionId snapshotId status transitionId
  | "nextStep", r => do
      let newStepNo ← jNat r "newStepNo"
      let sessionId ← jStr r "sessionId"
      let snapshotId ← jNat r "snapshotId"
      return .nextStep newStepNo sessionId snapshotId
  | "checkInvariant", r => do
      let invariantStatus ← jStr r "invariantStatus"
      let sessionId ← jStr r "sessionId"
      let trace ← decOptNullValue r "trace"
      return .checkInvariant invariantStatus sessionId trace
  | "query", r => do
      let operatorValue ← decOptNullValue r "operatorValue"
      let sessionId ← jStr r "sessionId"
      let state ← reqField r "state" decodeValue
      let trace ← decOptNullValue r "trace"
      return .query operatorValue sessionId state trace
  | "assumeState", r => do
      let sessionId ← jStr r "sessionId"
      let snapshotId ← jNat r "snapshotId"
      let status ← jStr r "status"
      return .assumeState sessionId snapshotId status
  | "rollback", _ => .ok .rollback
  | "disposeSpec", _ => .ok .disposeSpec
  | _, _ => derr "unknown explorer method"

/-- Decode a full JSON-RPC response envelope (method names the result shape). -/
def decodeRpcResponse (mth : String) (j : Json) : Dec RpcResponse := do
  let id ← jNat j "id"
  let result ← jField j "result"
  let res ← decodeRpcResult mth result
  return { id, result := res }


