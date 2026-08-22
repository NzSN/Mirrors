
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

/-! ## §6.6-style round-trips -/

private theorem arr_ne_null2 (a : Array Json) : Json.arr a ≠ Json.null := by
  intro h
  exact Json.noConfusion h

private theorem encValue_ne_of_ne_null (v : Value) (h : v ≠ Value.vnull) :
    encValue v ≠ Json.null := by
  intro he
  cases v with
  | vnull => exact absurd rfl h
  | _ => simp only [encValue, Json.mkObj] at he; exact Json.noConfusion he

private theorem jBool_mkObj {l : List (String × Json)} {k : String} {b : Bool}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b)) (hm : (k, Json.bool b) ∈ l) :
    jBool (Json.mkObj l) k = Except.ok b := by
  simp only [jBool, getObjVal?_mkObj hkeys hm]

private theorem jOptNat_mkObj {l : List (String × Json)} {k : String} {o : Option Nat}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b)) (hm : (k, optNat o) ∈ l) :
    jOptNat (Json.mkObj l) k = Except.ok o := by
  simp only [jOptNat, getObjVal?_mkObj hkeys hm]
  cases o <;> rfl

private theorem jField_of_mkObj {l : List (String × Json)} {k : String} {v : Json}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b)) (hm : (k, v) ∈ l) :
    jField (Json.mkObj l) k = Except.ok v := by
  simp only [jField, getObjVal?_mkObj hkeys hm]

private theorem decOptNullValue_enc {l : List (String × Json)} {k : String} {v : Value}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b)) (hm : (k, encValue v) ∈ l)
    (hb : valBounded v) (hne : v ≠ Value.vnull) :
    ∃ w, decOptNullValue (Json.mkObj l) k = Except.ok (some w) ∧ valEq v w = true := by
  obtain ⟨w, hw, hval⟩ := decodeValue_bounded v hb
  refine ⟨w, ?_, hval⟩
  simp only [decOptNullValue, getObjVal?_mkObj hkeys hm]
  have henn := encValue_ne_of_ne_null v hne
  cases hje : encValue v with
  | null => rw [hje] at henn; exact absurd rfl henn
  | str s | num n | bool b | arr a | obj o =>
      rw [hje] at hw
      simp only [decOptVal, hw]
      rfl

private theorem decOptNullValue_null {l : List (String × Json)} {k : String}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b)) (hm : (k, Json.null) ∈ l) :
    decOptNullValue (Json.mkObj l) k = Except.ok none := by
  simp only [decOptNullValue, getObjVal?_mkObj hkeys hm, decOptVal]

private theorem decTransitionSummary_jTransitionSummary (t : TransitionSummary) :
    decTransitionSummary (jTransitionSummary t) = Except.ok t := by
  have hkeys : (([("index", Json.num t.index),
      ("labels", Json.arr (strsJson t.labels |>.toArray))] :
      List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
  have mi : ("index", Json.num (JsonNumber.fromNat t.index)) ∈ ([("index", Json.num t.index),
      ("labels", Json.arr (strsJson t.labels |>.toArray))] : List (String × Json)) := by simp
  have ml : ("labels", Json.arr (strsJson t.labels |>.toArray)) ∈ ([("index", Json.num t.index),
      ("labels", Json.arr (strsJson t.labels |>.toArray))] : List (String × Json)) := by simp
  simp only [jTransitionSummary, decTransitionSummary, reqStr]
  rw [nat_of_mkObj hkeys mi, strs_of_mkObj hkeys ml]
  rfl

private theorem decTransitions_enc :
    ∀ ts : List TransitionSummary,
      decTransitions (Json.arr ((ts.map jTransitionSummary).toArray)) = Except.ok ts := by
  intro ts
  induction ts with
  | nil => rfl
  | cons t rest ih =>
      have harr : ((t :: rest).map jTransitionSummary).toArray.toList
          = jTransitionSummary t :: ((rest.map jTransitionSummary).toArray).toList := by
        simp only [List.map_cons, List.toList_toArray]
      show List.mapM decTransitionSummary (((t :: rest).map jTransitionSummary).toArray).toList = _
      rw [harr, List.mapM_cons, decTransitionSummary_jTransitionSummary t]
      have ih2 : List.mapM decTransitionSummary
          ((rest.map jTransitionSummary).toArray).toList = Except.ok rest := ih
      rw [ih2]
      rfl

private theorem decSpecParameters_jSpecParameters (sp : SpecParameters) :
    decSpecParameters (jSpecParameters sp) = Except.ok sp := by
  have hkeys : (([
      ("actionInvariants", jTransitions sp.actionInvariants),
      ("initTransitions", jTransitions sp.initTransitions),
      ("nextTransitions", jTransitions sp.nextTransitions),
      ("stateInvariants", jTransitions sp.stateInvariants)] :
      List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
  have m1 : ("actionInvariants", jTransitions sp.actionInvariants) ∈ ([("actionInvariants", jTransitions sp.actionInvariants),
      ("initTransitions", jTransitions sp.initTransitions),
      ("nextTransitions", jTransitions sp.nextTransitions),
      ("stateInvariants", jTransitions sp.stateInvariants)] :
      List (String × Json)) := by simp
  have m2 : ("initTransitions", jTransitions sp.initTransitions) ∈ ([("actionInvariants", jTransitions sp.actionInvariants),
      ("initTransitions", jTransitions sp.initTransitions),
      ("nextTransitions", jTransitions sp.nextTransitions),
      ("stateInvariants", jTransitions sp.stateInvariants)] :
      List (String × Json)) := by simp
  have m3 : ("nextTransitions", jTransitions sp.nextTransitions) ∈ ([("actionInvariants", jTransitions sp.actionInvariants),
      ("initTransitions", jTransitions sp.initTransitions),
      ("nextTransitions", jTransitions sp.nextTransitions),
      ("stateInvariants", jTransitions sp.stateInvariants)] :
      List (String × Json)) := by simp
  have m4 : ("stateInvariants", jTransitions sp.stateInvariants) ∈ ([("actionInvariants", jTransitions sp.actionInvariants),
      ("initTransitions", jTransitions sp.initTransitions),
      ("nextTransitions", jTransitions sp.nextTransitions),
      ("stateInvariants", jTransitions sp.stateInvariants)] :
      List (String × Json)) := by simp
  simp only [jSpecParameters, decSpecParameters, reqStr]
  rw [reqField_of_field hkeys m1 (arr_ne_null2 _) (decTransitions_enc sp.actionInvariants),
      reqField_of_field hkeys m2 (arr_ne_null2 _) (decTransitions_enc sp.initTransitions),
      reqField_of_field hkeys m3 (arr_ne_null2 _) (decTransitions_enc sp.nextTransitions),
      reqField_of_field hkeys m4 (arr_ne_null2 _) (decTransitions_enc sp.stateInvariants)]
  rfl
/-- Wire well-formedness of a request's value payloads. -/
def RpcRequestOk : RpcRequest → Prop
  | .query _ _ _ operator _ => ∀ v ∈ operator, valBounded v ∧ v ≠ Value.vnull
  | .assumeState _ _ equalities _ _ => valBounded equalities ∧ equalities ≠ Value.vnull
  | _ => True

/-- Request equality up to valEq at value positions. -/
def RpcRequestEquiv : RpcRequest → RpcRequest → Prop
  | .query i s k o t, .query i' s' k' o' t' =>
      i = i' ∧ s = s' ∧ k = k' ∧ optValEq o o' ∧ t = t'
  | .assumeState i s e c t, .assumeState i' s' e' c' t' =>
      i = i' ∧ s = s' ∧ valEq e e' = true ∧ c = c' ∧ t = t'
  | a, b => a = b

/-- **§6.6 explorer request round-trip.** -/
theorem decodeRpcRequest_encodeRpcRequest :
    ∀ r : RpcRequest, RpcRequestOk r →
      ∃ r', decodeRpcRequest (encodeRpcRequest r) = Except.ok r'
        ∧ RpcRequestEquiv r r' := by
  intro r hok
  cases r with

  | health id =>
      refine ⟨.health id, ?_, rfl⟩
      have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "health"), ("params", Json.arr #[])] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mm : ("method", Json.str "health") ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "health"), ("params", Json.arr #[])] : List (String × Json)) := by simp
      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "health"),
          ("params", Json.arr #[])] : List (String × Json)) := by simp
      have mp : ("params", Json.arr #[]) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "health"), ("params", Json.arr #[])] :
          List (String × Json)) := by simp
      simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
      show (decodeParams "health" (Json.arr #[]) >>= fun r_ => Except.ok (setReqId id r_)) = _
      simp only [decodeParams]
      rfl

  | loadSpec id sources exports invariants init next =>
      refine ⟨.loadSpec id sources exports invariants init next, ?_, rfl⟩
      have hp : (([
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("init", Json.str init),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("next", Json.str next),
        ("sources", Json.arr (strsJson sources |>.toArray))] : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have pe : ("exports", Json.arr (strsJson exports |>.toArray)) ∈ ([
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("init", Json.str init),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("next", Json.str next),
        ("sources", Json.arr (strsJson sources |>.toArray))] :
          List (String × Json)) := by simp
      have pi : ("init", Json.str init) ∈ ([
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("init", Json.str init),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("next", Json.str next),
        ("sources", Json.arr (strsJson sources |>.toArray))] :
          List (String × Json)) := by simp
      have pv : ("invariants", Json.arr (strsJson invariants |>.toArray)) ∈ ([
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("init", Json.str init),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("next", Json.str next),
        ("sources", Json.arr (strsJson sources |>.toArray))] :
          List (String × Json)) := by simp
      have pn : ("next", Json.str next) ∈ ([
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("init", Json.str init),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("next", Json.str next),
        ("sources", Json.arr (strsJson sources |>.toArray))] :
          List (String × Json)) := by simp
      have ps : ("sources", Json.arr (strsJson sources |>.toArray)) ∈ ([
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("init", Json.str init),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("next", Json.str next),
        ("sources", Json.arr (strsJson sources |>.toArray))] :
          List (String × Json)) := by simp
      have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "loadSpec"), ("params", Json.mkObj [
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("init", Json.str init),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("next", Json.str next),
        ("sources", Json.arr (strsJson sources |>.toArray))])] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mm : ("method", Json.str "loadSpec") ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "loadSpec"), ("params", Json.mkObj [
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("init", Json.str init),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("next", Json.str next),
        ("sources", Json.arr (strsJson sources |>.toArray))])] :
          List (String × Json)) := by simp
      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "loadSpec"), ("params", Json.mkObj [
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("init", Json.str init),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("next", Json.str next),
        ("sources", Json.arr (strsJson sources |>.toArray))])] :
          List (String × Json)) := by simp
      have mp : ("params", Json.mkObj [
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("init", Json.str init),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("next", Json.str next),
        ("sources", Json.arr (strsJson sources |>.toArray))]) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "loadSpec"), ("params", Json.mkObj [
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("init", Json.str init),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("next", Json.str next),
        ("sources", Json.arr (strsJson sources |>.toArray))])] :
          List (String × Json)) := by simp
      simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
      show (decodeParams "loadSpec" (Json.mkObj [
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("init", Json.str init),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("next", Json.str next),
        ("sources", Json.arr (strsJson sources |>.toArray))]) >>= fun r_ => Except.ok (setReqId id r_)) = _
      simp only [decodeParams]
      rw [strs_of_mkObj hp pe, str_of_mkObj hp pi, strs_of_mkObj hp pv, str_of_mkObj hp pn, strs_of_mkObj hp ps]
      rfl

  | assumeTransition id sessionId transitionId checkEnabled timeoutSec =>
      refine ⟨.assumeTransition id sessionId transitionId checkEnabled timeoutSec, ?_, rfl⟩
      have hp : (([
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)] : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have pc : ("checkEnabled", Json.bool checkEnabled) ∈ ([
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)] :
          List (String × Json)) := by simp
      have ps : ("sessionId", Json.str sessionId) ∈ ([
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)] :
          List (String × Json)) := by simp
      have pt : ("timeoutSec", optNat timeoutSec) ∈ ([
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)] :
          List (String × Json)) := by simp
      have pr : ("transitionId", Json.num transitionId) ∈ ([
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)] :
          List (String × Json)) := by simp
      have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "assumeTransition"), ("params", Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)])] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mm : ("method", Json.str "assumeTransition") ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "assumeTransition"), ("params", Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)])] :
          List (String × Json)) := by simp
      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "assumeTransition"), ("params", Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)])] :
          List (String × Json)) := by simp
      have mp : ("params", Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)]) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "assumeTransition"), ("params", Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)])] :
          List (String × Json)) := by simp
      simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
      show (decodeParams "assumeTransition" (Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)]) >>= fun r_ => Except.ok (setReqId id r_)) = _
      simp only [decodeParams]
      rw [jBool_mkObj hp pc, str_of_mkObj hp ps, jOptNat_mkObj hp pt, nat_of_mkObj hp pr]
      rfl

  | nextStep id sessionId =>
      refine ⟨.nextStep id sessionId, ?_, rfl⟩
      have hp : (([
        ("sessionId", Json.str sessionId)] : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have ps : ("sessionId", Json.str sessionId) ∈ ([
        ("sessionId", Json.str sessionId)] :
          List (String × Json)) := by simp
      have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "nextStep"), ("params", Json.mkObj [
        ("sessionId", Json.str sessionId)])] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mm : ("method", Json.str "nextStep") ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "nextStep"), ("params", Json.mkObj [
        ("sessionId", Json.str sessionId)])] :
          List (String × Json)) := by simp
      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "nextStep"), ("params", Json.mkObj [
        ("sessionId", Json.str sessionId)])] :
          List (String × Json)) := by simp
      have mp : ("params", Json.mkObj [
        ("sessionId", Json.str sessionId)]) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "nextStep"), ("params", Json.mkObj [
        ("sessionId", Json.str sessionId)])] :
          List (String × Json)) := by simp
      simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
      show (decodeParams "nextStep" (Json.mkObj [
        ("sessionId", Json.str sessionId)]) >>= fun r_ => Except.ok (setReqId id r_)) = _
      simp only [decodeParams]
      rw [str_of_mkObj hp ps]
      rfl

  | checkInvariant id sessionId invariantId kind timeoutSec =>
      refine ⟨.checkInvariant id sessionId invariantId kind timeoutSec, ?_, rfl⟩
      have hp : (([
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have pv : ("invariantId", Json.num invariantId) ∈ ([
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
          List (String × Json)) := by simp
      have pk : ("kind", Json.str kind) ∈ ([
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
          List (String × Json)) := by simp
      have ps : ("sessionId", Json.str sessionId) ∈ ([
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
          List (String × Json)) := by simp
      have pt : ("timeoutSec", optNat timeoutSec) ∈ ([
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
          List (String × Json)) := by simp
      have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "checkInvariant"), ("params", Json.mkObj [
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mm : ("method", Json.str "checkInvariant") ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "checkInvariant"), ("params", Json.mkObj [
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
          List (String × Json)) := by simp
      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "checkInvariant"), ("params", Json.mkObj [
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
          List (String × Json)) := by simp
      have mp : ("params", Json.mkObj [
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)]) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "checkInvariant"), ("params", Json.mkObj [
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
          List (String × Json)) := by simp
      simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
      show (decodeParams "checkInvariant" (Json.mkObj [
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)]) >>= fun r_ => Except.ok (setReqId id r_)) = _
      simp only [decodeParams]
      rw [nat_of_mkObj hp pv, str_of_mkObj hp pk, str_of_mkObj hp ps, jOptNat_mkObj hp pt]
      rfl

  | query id sessionId kinds operator timeoutSec =>
      cases operator with
      | none =>
          refine ⟨.query id sessionId kinds none timeoutSec, ?_, rfl, rfl, rfl, trivial, rfl⟩
          have hp : (([
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
          have pk : ("kinds", Json.arr (strsJson kinds |>.toArray)) ∈ ([
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
              List (String × Json)) := by simp
          have po : ("operator", Json.null) ∈ ([
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
              List (String × Json)) := by simp
          have ps : ("sessionId", Json.str sessionId) ∈ ([
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
              List (String × Json)) := by simp
          have pt : ("timeoutSec", optNat timeoutSec) ∈ ([
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
              List (String × Json)) := by simp
          have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "query"), ("params", Json.mkObj [
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
          have mm : ("method", Json.str "query") ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "query"), ("params", Json.mkObj [
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
          have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "query"), ("params", Json.mkObj [
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
          have mp : ("params", Json.mkObj [
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)]) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "query"), ("params", Json.mkObj [
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
          simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest, optJson]
          rw [show encValue <$> (none : Option Value) = none from rfl]
          dsimp only
          rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
          show (decodeParams "query" (Json.mkObj [
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)]) >>= fun r_ => Except.ok (setReqId id r_)) = _
          simp only [decodeParams]
          rw [strs_of_mkObj hp pk, decOptNullValue_null hp po, str_of_mkObj hp ps, jOptNat_mkObj hp pt]
          rfl

      | some op =>
          obtain ⟨hb1, hb2⟩ := hok op (by simp)
          have hp : (([
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
          have pk : ("kinds", Json.arr (strsJson kinds |>.toArray)) ∈ ([
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
              List (String × Json)) := by simp
          have po : ("operator", encValue op) ∈ ([
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
              List (String × Json)) := by simp
          obtain ⟨w2, hw2⟩ := decOptNullValue_enc hp po hb1 hb2
          refine ⟨.query id sessionId kinds (some w2) timeoutSec, ?_, rfl, rfl, rfl, hw2.2, rfl⟩
          have ps : ("sessionId", Json.str sessionId) ∈ ([
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
              List (String × Json)) := by simp
          have pt : ("timeoutSec", optNat timeoutSec) ∈ ([
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
              List (String × Json)) := by simp
          have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "query"), ("params", Json.mkObj [
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
          have mm : ("method", Json.str "query") ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "query"), ("params", Json.mkObj [
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
          have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "query"), ("params", Json.mkObj [
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
          have mp : ("params", Json.mkObj [
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)]) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "query"), ("params", Json.mkObj [
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
          simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest, optJson]
          rw [show encValue <$> (some op : Option Value) = some (encValue op) from rfl]
          dsimp only
          rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
          show (decodeParams "query" (Json.mkObj [
        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)]) >>= fun r_ => Except.ok (setReqId id r_)) = _
          simp only [decodeParams]
          have hop2 := hw2.1
          rw [strs_of_mkObj hp pk, hop2, str_of_mkObj hp ps, jOptNat_mkObj hp pt]
          rfl
  | assumeState id sessionId equalities checkEnabled timeoutSec =>
      obtain ⟨hb1, hb2⟩ := hok
      obtain ⟨eq2, heq2dec, hval⟩ := decodeValue_bounded equalities hb1
      refine ⟨.assumeState id sessionId eq2 checkEnabled timeoutSec, ?_, rfl, rfl, hval, rfl, rfl⟩
      have hp : (([
        ("checkEnabled", Json.bool checkEnabled),
        ("equalities", encValue equalities),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
        List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have pc : ("checkEnabled", Json.bool checkEnabled) ∈ ([("checkEnabled", Json.bool checkEnabled),
        ("equalities", encValue equalities),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] : List (String × Json)) := by simp
      have pe : ("equalities", encValue equalities) ∈ ([("checkEnabled", Json.bool checkEnabled),
        ("equalities", encValue equalities),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] : List (String × Json)) := by simp
      have ps : ("sessionId", Json.str sessionId) ∈ ([("checkEnabled", Json.bool checkEnabled),
        ("equalities", encValue equalities),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] : List (String × Json)) := by simp
      have pt : ("timeoutSec", optNat timeoutSec) ∈ ([("checkEnabled", Json.bool checkEnabled),
        ("equalities", encValue equalities),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] : List (String × Json)) := by simp
      have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "assumeState"), ("params", Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("equalities", encValue equalities),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mm : ("method", Json.str "assumeState") ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "assumeState"), ("params", Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("equalities", encValue equalities),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
          List (String × Json)) := by simp
      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "assumeState"), ("params", Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("equalities", encValue equalities),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
          List (String × Json)) := by simp
      have mp : ("params", Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("equalities", encValue equalities),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)]) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "assumeState"), ("params", Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("equalities", encValue equalities),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
          List (String × Json)) := by simp
      simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest, optJson, Option.map_none, Option.map_some]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
      show (decodeParams "assumeState" (Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("equalities", encValue equalities),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)]) >>= fun r_ => Except.ok (setReqId id r_)) = _
      simp only [decodeParams]
      rw [jBool_mkObj hp pc,
        reqField_of_field hp pe (encValue_ne_of_ne_null equalities hb2) heq2dec,
        str_of_mkObj hp ps, jOptNat_mkObj hp pt]
      rfl
  | rollback id sessionId snapshotId =>
      refine ⟨.rollback id sessionId snapshotId, ?_, rfl⟩
      have hp : (([
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId)] : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have ps : ("sessionId", Json.str sessionId) ∈ ([
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId)] :
          List (String × Json)) := by simp
      have pn : ("snapshotId", Json.num snapshotId) ∈ ([
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId)] :
          List (String × Json)) := by simp
      have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "rollback"), ("params", Json.mkObj [
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId)])] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mm : ("method", Json.str "rollback") ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "rollback"), ("params", Json.mkObj [
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId)])] :
          List (String × Json)) := by simp
      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "rollback"), ("params", Json.mkObj [
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId)])] :
          List (String × Json)) := by simp
      have mp : ("params", Json.mkObj [
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId)]) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "rollback"), ("params", Json.mkObj [
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId)])] :
          List (String × Json)) := by simp
      simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
      show (decodeParams "rollback" (Json.mkObj [
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId)]) >>= fun r_ => Except.ok (setReqId id r_)) = _
      simp only [decodeParams]
      rw [str_of_mkObj hp ps, nat_of_mkObj hp pn]
      rfl

  | disposeSpec id sessionId =>
      refine ⟨.disposeSpec id sessionId, ?_, rfl⟩
      have hp : (([
        ("sessionId", Json.str sessionId)] : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have ps : ("sessionId", Json.str sessionId) ∈ ([
        ("sessionId", Json.str sessionId)] :
          List (String × Json)) := by simp
      have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "disposeSpec"), ("params", Json.mkObj [
        ("sessionId", Json.str sessionId)])] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mm : ("method", Json.str "disposeSpec") ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "disposeSpec"), ("params", Json.mkObj [
        ("sessionId", Json.str sessionId)])] :
          List (String × Json)) := by simp
      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "disposeSpec"), ("params", Json.mkObj [
        ("sessionId", Json.str sessionId)])] :
          List (String × Json)) := by simp
      have mp : ("params", Json.mkObj [
        ("sessionId", Json.str sessionId)]) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "disposeSpec"), ("params", Json.mkObj [
        ("sessionId", Json.str sessionId)])] :
          List (String × Json)) := by simp
      simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
      show (decodeParams "disposeSpec" (Json.mkObj [
        ("sessionId", Json.str sessionId)]) >>= fun r_ => Except.ok (setReqId id r_)) = _
      simp only [decodeParams]
      rw [str_of_mkObj hp ps]
      rfl


/-- Method that produces a given result shape. -/

def resultMethod : RpcResult → String
  | .health _ => "health"
  | .loadSpec _ _ _ => "loadSpec"
  | .assumeTransition _ _ _ _ => "assumeTransition"
  | .nextStep _ _ _ => "nextStep"
  | .checkInvariant _ _ _ => "checkInvariant"
  | .query _ _ _ _ => "query"
  | .assumeState _ _ _ => "assumeState"
  | .rollback => "rollback"
  | .disposeSpec => "disposeSpec"

private theorem jSpecParameters_ne_null (sp : SpecParameters) :
    jSpecParameters sp ≠ Json.null := by
  intro h
  simp only [jSpecParameters, Json.mkObj] at h
  exact Json.noConfusion h
def RpcResultOk : RpcResult → Prop
  | .checkInvariant _ _ trace => ∀ v ∈ trace, valBounded v ∧ v ≠ Value.vnull
  | .query operatorValue _ state trace =>
      (∀ v ∈ operatorValue, valBounded v ∧ v ≠ Value.vnull)
        ∧ (valBounded state ∧ state ≠ Value.vnull)
        ∧ ∀ v ∈ trace, valBounded v ∧ v ≠ Value.vnull
  | _ => True

/-- Result equality up to valEq at value positions. -/
def RpcResultEquiv : RpcResult → RpcResult → Prop
  | .checkInvariant s i t, .checkInvariant s' i' t' =>
      s = s' ∧ i = i' ∧ optValEq t t'
  | .query o i st t, .query o' i' st' t' =>
      optValEq o o' ∧ i = i' ∧ valEq st st' = true ∧ optValEq t t'
  | a, b => a = b

/-- **§6.6 explorer response round-trip. ** -/
theorem decodeRpcResult_encodeRpcResult :
    ∀ r : RpcResult, RpcResultOk r →
      ∃ r', decodeRpcResult (resultMethod r) (encodeRpcResult r) = Except.ok r'
        ∧ RpcResultEquiv r r' := by
  intro r hok
  cases r with
  | health status =>
      refine ⟨.health status, ?_, rfl⟩
      have hp : (([        ("status", Json.str status)] : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have m0 : ("status", Json.str status) ∈ ([        ("status", Json.str status)] :
          List (String × Json)) := by simp
      simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, reqNat]
      rw [str_of_mkObj hp m0]
      rfl
  | assumeTransition sessionId snapshotId status transitionId =>
      refine ⟨.assumeTransition sessionId snapshotId status transitionId, ?_, rfl⟩
      have hp : (([        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("status", Json.str status),
        ("transitionId", Json.num transitionId)] : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have m0 : ("sessionId", Json.str sessionId) ∈ ([        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("status", Json.str status),
        ("transitionId", Json.num transitionId)] :
          List (String × Json)) := by simp
      have m1 : ("snapshotId", Json.num snapshotId) ∈ ([        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("status", Json.str status),
        ("transitionId", Json.num transitionId)] :
          List (String × Json)) := by simp
      have m2 : ("status", Json.str status) ∈ ([        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("status", Json.str status),
        ("transitionId", Json.num transitionId)] :
          List (String × Json)) := by simp
      have m3 : ("transitionId", Json.num transitionId) ∈ ([        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("status", Json.str status),
        ("transitionId", Json.num transitionId)] :
          List (String × Json)) := by simp
      simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, reqNat]
      rw [str_of_mkObj hp m0, nat_of_mkObj hp m1, str_of_mkObj hp m2, nat_of_mkObj hp m3]
      rfl
  | nextStep newStepNo sessionId snapshotId =>
      refine ⟨.nextStep newStepNo sessionId snapshotId, ?_, rfl⟩
      have hp : (([        ("newStepNo", Json.num newStepNo),
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId)] : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have m0 : ("newStepNo", Json.num newStepNo) ∈ ([        ("newStepNo", Json.num newStepNo),
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId)] :
          List (String × Json)) := by simp
      have m1 : ("sessionId", Json.str sessionId) ∈ ([        ("newStepNo", Json.num newStepNo),
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId)] :
          List (String × Json)) := by simp
      have m2 : ("snapshotId", Json.num snapshotId) ∈ ([        ("newStepNo", Json.num newStepNo),
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId)] :
          List (String × Json)) := by simp
      simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, reqNat]
      rw [nat_of_mkObj hp m0, str_of_mkObj hp m1, nat_of_mkObj hp m2]
      rfl
  | assumeState sessionId snapshotId status =>
      refine ⟨.assumeState sessionId snapshotId status, ?_, rfl⟩
      have hp : (([        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("status", Json.str status)] : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have m0 : ("sessionId", Json.str sessionId) ∈ ([        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("status", Json.str status)] :
          List (String × Json)) := by simp
      have m1 : ("snapshotId", Json.num snapshotId) ∈ ([        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("status", Json.str status)] :
          List (String × Json)) := by simp
      have m2 : ("status", Json.str status) ∈ ([        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("status", Json.str status)] :
          List (String × Json)) := by simp
      simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, reqNat]
      rw [str_of_mkObj hp m0, nat_of_mkObj hp m1, str_of_mkObj hp m2]
      rfl
  | rollback => exact ⟨.rollback, by
    simp only [encodeRpcResult, decodeRpcResult, resultMethod], rfl⟩
  | disposeSpec => exact ⟨.disposeSpec, by
    simp only [encodeRpcResult, decodeRpcResult, resultMethod], rfl⟩
  | loadSpec sessionId snapshotId specParameters =>
      refine ⟨.loadSpec sessionId snapshotId specParameters, ?_, rfl⟩
      have hp : (([
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("specParameters", jSpecParameters specParameters)] :
        List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mK : ("sessionId", Json.str sessionId) ∈ ([("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("specParameters", jSpecParameters specParameters)] : List (String × Json)) := by simp
      have mN : ("snapshotId", Json.num (JsonNumber.fromNat snapshotId)) ∈ ([("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("specParameters", jSpecParameters specParameters)] : List (String × Json)) := by simp
      have mS : ("specParameters", jSpecParameters specParameters) ∈ ([("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("specParameters", jSpecParameters specParameters)] : List (String × Json)) := by simp
      simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, reqNat]
      rw [str_of_mkObj hp mK, nat_of_mkObj hp mN,
        reqField_of_field hp mS (jSpecParameters_ne_null specParameters)
          (decSpecParameters_jSpecParameters specParameters)]
      rfl
  | checkInvariant invariantStatus sessionId trace =>
      cases htrv : trace with
      | none =>
          refine ⟨.checkInvariant invariantStatus sessionId none, ?_, rfl, rfl, trivial⟩
          have hp : (([
            ("invariantStatus", Json.str invariantStatus),
            ("sessionId", Json.str sessionId),
            ("trace", Json.null)] :
            List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
          have mi : ("invariantStatus", Json.str invariantStatus) ∈ ([
            ("invariantStatus", Json.str invariantStatus),
            ("sessionId", Json.str sessionId),
            ("trace", Json.null)] : List (String × Json)) := by simp
          have ms : ("sessionId", Json.str sessionId) ∈ ([
            ("invariantStatus", Json.str invariantStatus),
            ("sessionId", Json.str sessionId),
            ("trace", Json.null)] : List (String × Json)) := by simp
          have mt : ("trace", Json.null) ∈ ([
            ("invariantStatus", Json.str invariantStatus),
            ("sessionId", Json.str sessionId),
            ("trace", Json.null)] : List (String × Json)) := by simp
          simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, optJson, htrv]
          rw [show encValue <$> (none : Option Value) = none from rfl]
          dsimp only
          rw [str_of_mkObj hp mi, str_of_mkObj hp ms, decOptNullValue_null hp mt]
          rfl
      | some v =>
          have hp : (([
            ("invariantStatus", Json.str invariantStatus),
            ("sessionId", Json.str sessionId),
            ("trace", encValue v)] :
            List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
          have mt : ("trace", encValue v) ∈ ([
            ("invariantStatus", Json.str invariantStatus),
            ("sessionId", Json.str sessionId),
            ("trace", encValue v)] : List (String × Json)) := by simp
          obtain ⟨w, hw2⟩ := decOptNullValue_enc hp mt (hok v (by simp [htrv])).1 (hok v (by simp [htrv])).2
          refine ⟨.checkInvariant invariantStatus sessionId (some w), ?_, rfl, rfl, hw2.2⟩
          have mi : ("invariantStatus", Json.str invariantStatus) ∈ ([
            ("invariantStatus", Json.str invariantStatus),
            ("sessionId", Json.str sessionId),
            ("trace", encValue v)] : List (String × Json)) := by simp
          have ms : ("sessionId", Json.str sessionId) ∈ ([
            ("invariantStatus", Json.str invariantStatus),
            ("sessionId", Json.str sessionId),
            ("trace", encValue v)] : List (String × Json)) := by simp
          simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, optJson, htrv]
          rw [show encValue <$> (some v : Option Value) = some (encValue v) from rfl]
          dsimp only
          rw [str_of_mkObj hp mi, str_of_mkObj hp ms, hw2.1]
          rfl
  | query operatorValue sessionId state trace =>
      obtain ⟨ho, hst, htr⟩ := hok
      obtain ⟨stw, hstw, hstval⟩ := decodeValue_bounded state hst.1
      cases hopv : operatorValue with
      | none =>
          cases htrv : trace with
          | none =>
              refine ⟨.query none sessionId stw none, ?_, trivial, rfl, hstval, trivial⟩
              have hp : (([
                ("operatorValue", Json.null),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)] :
                List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
              have ms : ("sessionId", Json.str sessionId) ∈ ([
                ("operatorValue", Json.null),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)] : List (String × Json)) := by simp
              have mst : ("state", encValue state) ∈ ([
                ("operatorValue", Json.null),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)] : List (String × Json)) := by simp
              simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, optJson, hopv, htrv]
              rw [show encValue <$> (none : Option Value) = none from rfl]
              dsimp only
              rw [str_of_mkObj hp ms,
                reqField_of_field hp mst (encValue_ne_of_ne_null state hst.2) hstw]
              rfl
          | some vt =>
              have hp : (([
                ("operatorValue", Json.null),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] :
                List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
              have mt : ("trace", encValue vt) ∈ ([
                ("operatorValue", Json.null),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] : List (String × Json)) := by simp
              obtain ⟨tw, htw2⟩ := decOptNullValue_enc hp mt
                (htr vt (by simp [htrv])).1 (htr vt (by simp [htrv])).2
              refine ⟨.query none sessionId stw (some tw), ?_, trivial, rfl, hstval, htw2.2⟩
              have ms : ("sessionId", Json.str sessionId) ∈ ([
                ("operatorValue", Json.null),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] : List (String × Json)) := by simp
              have mst : ("state", encValue state) ∈ ([
                ("operatorValue", Json.null),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] : List (String × Json)) := by simp
              simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, optJson, hopv, htrv]
              rw [show encValue <$> (none : Option Value) = none from rfl,
                show encValue <$> (some vt : Option Value) = some (encValue vt) from rfl]
              dsimp only
              rw [str_of_mkObj hp ms,
                reqField_of_field hp mst (encValue_ne_of_ne_null state hst.2) hstw, htw2.1]
              rfl
      | some vo =>
          cases htrv : trace with
          | none =>
              have hp : (([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)] :
                List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
              have mo : ("operatorValue", encValue vo) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)] : List (String × Json)) := by simp
              obtain ⟨ow, how2⟩ := decOptNullValue_enc hp mo
                (ho vo (by simp [hopv])).1 (ho vo (by simp [hopv])).2
              refine ⟨.query (some ow) sessionId stw none, ?_, how2.2, rfl, hstval, trivial⟩
              have ms : ("sessionId", Json.str sessionId) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)] : List (String × Json)) := by simp
              have mst : ("state", encValue state) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)] : List (String × Json)) := by simp
              simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, optJson, hopv, htrv]
              rw [show encValue <$> (some vo : Option Value) = some (encValue vo) from rfl,
                show encValue <$> (none : Option Value) = none from rfl]
              dsimp only
              rw [how2.1, str_of_mkObj hp ms,
                reqField_of_field hp mst (encValue_ne_of_ne_null state hst.2) hstw]
              rfl
          | some vt =>
              have hp : (([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] :
                List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
              have mo : ("operatorValue", encValue vo) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] : List (String × Json)) := by simp
              have mt : ("trace", encValue vt) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] : List (String × Json)) := by simp
              obtain ⟨ow, how2⟩ := decOptNullValue_enc hp mo
                (ho vo (by simp [hopv])).1 (ho vo (by simp [hopv])).2
              obtain ⟨tw, htw2⟩ := decOptNullValue_enc hp mt
                (htr vt (by simp [htrv])).1 (htr vt (by simp [htrv])).2
              refine ⟨.query (some ow) sessionId stw (some tw), ?_, how2.2, rfl, hstval, htw2.2⟩
              have ms : ("sessionId", Json.str sessionId) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] : List (String × Json)) := by simp
              have mst : ("state", encValue state) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] : List (String × Json)) := by simp
              simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, optJson, hopv, htrv]
              rw [show encValue <$> (some vo : Option Value) = some (encValue vo) from rfl,
                show encValue <$> (some vt : Option Value) = some (encValue vt) from rfl]
              dsimp only
              rw [how2.1, str_of_mkObj hp ms,
                reqField_of_field hp mst (encValue_ne_of_ne_null state hst.2) hstw, htw2.1]
              rfl
end Codec

