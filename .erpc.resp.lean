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

private theorem arr_ne_null' (a : Array Json) : Json.arr a ≠ Json.null := by
  intro h
  exact Json.noConfusion h

/-! ## §6.6-style round-trips -/

private theorem encValue_ne_of_ne_null (v : Value) (h : v ≠ Value.vnull) :
    encValue v ≠ Json.null := by
  intro he
  cases v with
  | vnull => exact absurd rfl h
  | _ => simp only [encValue, Json.mkObj] at he; exact Json.noConfusion he


private theorem jBool_mkObj {l : List (String × Json)} {k : String} {b : Bool}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : (k, Json.bool b) ∈ l) :
    jBool (Json.mkObj l) k = Except.ok b := by
  simp only [jBool, getObjVal?_mkObj hkeys hm]

private theorem jOptNat_mkObj {l : List (String × Json)} {k : String} {o : Option Nat}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : (k, optNat o) ∈ l) :
    jOptNat (Json.mkObj l) k = Except.ok o := by
  simp only [jOptNat, getObjVal?_mkObj hkeys hm]
  cases o <;> rfl

private theorem jField_of_mkObj {l : List (String × Json)} {k : String} {v : Json}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : (k, v) ∈ l) :
    jField (Json.mkObj l) k = Except.ok v := by
  simp only [jField, getObjVal?_mkObj hkeys hm]

private theorem decOptNullValue_enc {l : List (String × Json)} {k : String} {v : Value}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : (k, encValue v) ∈ l) (hb : valBounded v) (hne : v ≠ Value.vnull) :
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
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : (k, Json.null) ∈ l) :
    decOptNullValue (Json.mkObj l) k = Except.ok none := by
  simp only [decOptNullValue, getObjVal?_mkObj hkeys hm, decOptVal]

private theorem decTransitionSummary_jTransitionSummary (t : TransitionSummary) :
    decTransitionSummary (jTransitionSummary t) = Except.ok t := by
  have hkeys : (([("index", Json.num t.index),
      ("labels", Json.arr (strsJson t.labels |>.toArray))] :
      List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
  have mi : ("index", Json.num (JsonNumber.fromNat t.index)) ∈ ([("index", Json.num t.index),
      ("labels", Json.arr (strsJson t.labels |>.toArray))] :
      List (String × Json)) := by simp
  have ml : ("labels", Json.arr (strsJson t.labels |>.toArray)) ∈ ([("index", Json.num t.index),
      ("labels", Json.arr (strsJson t.labels |>.toArray))] :
      List (String × Json)) := by simp
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
  have m1 : ("actionInvariants", jTransitions sp.actionInvariants) ∈ ([
      ("actionInvariants", jTransitions sp.actionInvariants),
      ("initTransitions", jTransitions sp.initTransitions),
      ("nextTransitions", jTransitions sp.nextTransitions),
      ("stateInvariants", jTransitions sp.stateInvariants)] :
      List (String × Json)) := by simp
  have m2 : ("initTransitions", jTransitions sp.initTransitions) ∈ ([
      ("actionInvariants", jTransitions sp.actionInvariants),
      ("initTransitions", jTransitions sp.initTransitions),
      ("nextTransitions", jTransitions sp.nextTransitions),
      ("stateInvariants", jTransitions sp.stateInvariants)] :
      List (String × Json)) := by simp
  have m3 : ("nextTransitions", jTransitions sp.nextTransitions) ∈ ([
      ("actionInvariants", jTransitions sp.actionInvariants),
      ("initTransitions", jTransitions sp.initTransitions),
      ("nextTransitions", jTransitions sp.nextTransitions),
      ("stateInvariants", jTransitions sp.stateInvariants)] :
      List (String × Json)) := by simp
  have m4 : ("stateInvariants", jTransitions sp.stateInvariants) ∈ ([
      ("actionInvariants", jTransitions sp.actionInvariants),
      ("initTransitions", jTransitions sp.initTransitions),
      ("nextTransitions", jTransitions sp.nextTransitions),
      ("stateInvariants", jTransitions sp.stateInvariants)] :
      List (String × Json)) := by simp
  simp only [jSpecParameters, decSpecParameters, reqStr]
  rw [reqField_of_field hkeys m1 (arr_ne_null' _) (decTransitions_enc sp.actionInvariants),
      reqField_of_field hkeys m2 (arr_ne_null' _) (decTransitions_enc sp.initTransitions),
      reqField_of_field hkeys m3 (arr_ne_null' _) (decTransitions_enc sp.nextTransitions),
      reqField_of_field hkeys m4 (arr_ne_null' _) (decTransitions_enc sp.stateInvariants)]
  rfl


/-- Wire well-formedness of a request's value payloads. -/
def RpcRequestOk : RpcRequest → Prop
  | .query _ _ _ operator _ => ∀ v ∈ operator, valBounded v ∧ v ≠ Value.vnull
  | .assumeState _ _ equalities _ _ => valBounded equalities ∧ equalities ≠ Value.vnull
  | _ => True

/-- Request equality up to `valEq` at value positions. -/
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
          ("method", Json.str "health"), ("params", Json.arr #[])] :
          List (String × Json)) := by simp
      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "health"),
          ("params", Json.arr #[])] : List (String × Json)) := by simp
      have mp : ("params", Json.arr #[]) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "health"), ("params", Json.arr #[])] :
          List (String × Json)) := by simp
      simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest, reqStr,
        reqNat, decodeParams]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
      rfl

  | loadSpec id sources exports invariants init next =>
      refine ⟨.loadSpec id sources exports invariants init next, ?_, rfl⟩
      have hp : (([
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("init", Json.str init),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("next", Json.str next),
        ("sources", Json.arr (strsJson sources |>.toArray))] :
        List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
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
      have mm : ("method", Json.str "loadSpec") ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "loadSpec"), ("params", Json.mkObj [
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("init", Json.str init),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("next", Json.str next),
        ("sources", Json.arr (strsJson sources |>.toArray))])] :
          List (String × Json)) := by simp
      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "loadSpec"), ("params", Json.mkObj [
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
        ("sources", Json.arr (strsJson sources |>.toArray))]) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "loadSpec"), ("params", Json.mkObj [
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("init", Json.str init),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("next", Json.str next),
        ("sources", Json.arr (strsJson sources |>.toArray))])] :
          List (String × Json)) := by simp
      simp only [encodeRpcRequest, encodeParams, reqId, methodName]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
      show decodeParams "loadSpec" (Json.mkObj [
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("init", Json.str init),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("next", Json.str next),
        ("sources", Json.arr (strsJson sources |>.toArray))]) >>= fun r_ =>
          Except.ok (setReqId id r_) = _
      simp only [decodeParams]
      rw [strs_of_mkObj hp pe, str_of_mkObj hp pi, strs_of_mkObj hp pv, str_of_mkObj hp pn,
        strs_of_mkObj hp ps]
      rfl
  | assumeTransition id sessionId transitionId checkEnabled timeoutSec =>
      refine ⟨.assumeTransition id sessionId transitionId checkEnabled timeoutSec, ?_, rfl⟩
      have hp : (([
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)] :
        List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "assumeTransition"), ("params", Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)])] :
        List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mm : ("method", Json.str "assumeTransition") ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "assumeTransition"),
          ("params", Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)])] :
        List (String × Json)) := by simp
      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "assumeTransition"),
          ("params", Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)])] :
        List (String × Json)) := by simp
      have mp : ("params", Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)]) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "assumeTransition"),
          ("params", Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)])] :
        List (String × Json)) := by simp
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
      have pr : ("transitionId", Json.num (JsonNumber.fromNat transitionId)) ∈ ([
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)] :
        List (String × Json)) := by simp
      simp only [encodeRpcRequest, encodeParams, reqId, methodName]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
      show decodeParams "assumeTransition" (Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)])] :
        List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mm : ("method", Json.str "assumeTransition") ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "assumeTransition"),
          ("params", Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)])] :
        List (String × Json)) := by simp
      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "assumeTransition"),
          ("params", Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)])] :
        List (String × Json)) := by simp
      have mp : ("params", Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)]) >>= fun r_ => Except.ok (setReqId id r_) = _
      simp only [decodeParams]
      rw [        jBool_mkObj hp pc, str_of_mkObj hp ps, jOptNat_mkObj hp pt, nat_of_mkObj hp pr]
      rfl
  | nextStep id sessionId =>
      refine ⟨.nextStep id sessionId, ?_, rfl⟩
      have hp : (([("sessionId", Json.str sessionId)] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "nextStep"), ("params", Json.mkObj [("sessionId", Json.str sessionId)])] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mm : ("method", Json.str "nextStep") ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "nextStep"),
          ("params", Json.mkObj [("sessionId", Json.str sessionId)])] :
          List (String × Json)) := by simp
      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "nextStep"),
          ("params", Json.mkObj [("sessionId", Json.str sessionId)])] :
          List (String × Json)) := by simp
      have mp : ("params", Json.mkObj [("sessionId", Json.str sessionId)]) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "nextStep"),
          ("params", Json.mkObj [("sessionId", Json.str sessionId)])] :
          List (String × Json)) := by simp
      have ps : ("sessionId", Json.str sessionId) ∈ ([("sessionId", Json.str sessionId)] :
          List (String × Json)) := by simp
      simp only [encodeRpcRequest, encodeParams, reqId, methodName]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
      show decodeParams "nextStep" (Json.mkObj [
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)])] :
        List (String × Json)) := by simp
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
      have pr : ("transitionId", Json.num (JsonNumber.fromNat transitionId)) ∈ ([
        ("checkEnabled", Json.bool checkEnabled),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec),
        ("transitionId", Json.num transitionId)] :
        List (String × Json)) := by simp
      simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest, reqStr,
        reqNat, decodeParams]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp,
        jBool_mkObj hp pc, str_of_mkObj hp ps, jOptNat_mkObj hp pt, nat_of_mkObj hp pr]
      rfl
  | nextStep id sessionId =>
      refine ⟨.nextStep id sessionId, ?_, rfl⟩
      have hp : (([("sessionId", Json.str sessionId)] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "nextStep"), ("params", Json.mkObj [("sessionId", Json.str sessionId)])] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mm : ("method", Json.str "nextStep") ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "nextStep"),
          ("params", Json.mkObj [("sessionId", Json.str sessionId)])] :
          List (String × Json)) := by simp
      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "nextStep"),
          ("params", Json.mkObj [("sessionId", Json.str sessionId)])] :
          List (String × Json)) := by simp
      have mp : ("params", Json.mkObj [("sessionId", Json.str sessionId)]) >>= fun r_ => Except.ok (setReqId id r_) = _
      simp only [decodeParams]
      rw [        str_of_mkObj hp ps]
      rfl
  | checkInvariant id sessionId invariantId kind timeoutSec =>
      refine ⟨.checkInvariant id sessionId invariantId kind timeoutSec, ?_, rfl⟩
      have hp : (([
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
        List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "checkInvariant"), ("params", Json.mkObj [
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
        List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mm : ("method", Json.str "checkInvariant") ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "checkInvariant"),
          ("params", Json.mkObj [
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
        List (String × Json)) := by simp
      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "checkInvariant"),
          ("params", Json.mkObj [
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
        List (String × Json)) := by simp
      have mp : ("params", Json.mkObj [
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)]) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "checkInvariant"),
          ("params", Json.mkObj [
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
        List (String × Json)) := by simp
      have pi : ("invariantId", Json.num (JsonNumber.fromNat invariantId)) ∈ ([
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
      simp only [encodeRpcRequest, encodeParams, reqId, methodName]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
      show decodeParams "checkInvariant" (Json.mkObj [("sessionId", Json.str sessionId)])] :
          List (String × Json)) := by simp
      have ps : ("sessionId", Json.str sessionId) ∈ ([("sessionId", Json.str sessionId)] :
          List (String × Json)) := by simp
      simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest, reqStr,
        reqNat, decodeParams]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp,
        str_of_mkObj hp ps]
      rfl
  | checkInvariant id sessionId invariantId kind timeoutSec =>
      refine ⟨.checkInvariant id sessionId invariantId kind timeoutSec, ?_, rfl⟩
      have hp : (([
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
        List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "checkInvariant"), ("params", Json.mkObj [
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
        List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mm : ("method", Json.str "checkInvariant") ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "checkInvariant"),
          ("params", Json.mkObj [
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
        List (String × Json)) := by simp
      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "checkInvariant"),
          ("params", Json.mkObj [
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
        List (String × Json)) := by simp
      have mp : ("params", Json.mkObj [
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)]) >>= fun r_ => Except.ok (setReqId id r_) = _
      simp only [decodeParams]
      rw [        nat_of_mkObj hp pi, str_of_mkObj hp pk, str_of_mkObj hp ps, jOptNat_mkObj hp pt]
      rfl

  | query id sessionId kinds operator timeoutSec =>
      cases operator with
      | none =>
          refine ⟨.query id sessionId kinds none timeoutSec, ?_, rfl, rfl, rfl, by
            intro v hv; exact absurd hv (by simp), rfl⟩
          have hp : (([
            ("kinds", Json.arr (strsJson kinds |>.toArray)),
            ("operator", Json.null),
            ("sessionId", Json.str sessionId),
            ("timeoutSec", optNat timeoutSec)] :
            List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
          have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
              ("method", Json.str "query"), ("params", Json.mkObj [
            ("kinds", Json.arr (strsJson kinds |>.toArray)),
            ("operator", Json.null),
            ("sessionId", Json.str sessionId),
            ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
          have mm : ("method", Json.str "query") ∈ ([("id", Json.num id),
              ("jsonrpc", Json.str "2.0"), ("method", Json.str "query"), ("params", Json.mkObj [
            ("kinds", Json.arr (strsJson kinds |>.toArray)),
            ("operator", Json.null),
            ("sessionId", Json.str sessionId),
            ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
          have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id),
              ("jsonrpc", Json.str "2.0"), ("method", Json.str "query"), ("params", Json.mkObj [
            ("kinds", Json.arr (strsJson kinds |>.toArray)),
            ("operator", Json.null),
            ("sessionId", Json.str sessionId),
            ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
          have mp : ("params", Json.mkObj [
            ("kinds", Json.arr (strsJson kinds |>.toArray)),
            ("operator", Json.null),
            ("sessionId", Json.str sessionId),
            ("timeoutSec", optNat timeoutSec)]) ∈ ([("id", Json.num id),
              ("jsonrpc", Json.str "2.0"), ("method", Json.str "query"), ("params", Json.mkObj [
            ("kinds", Json.arr (strsJson kinds |>.toArray)),
            ("operator", Json.null),
            ("sessionId", Json.str sessionId),
            ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
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
          simp only [encodeRpcRequest, encodeParams, reqId, methodName]
          rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
          show decodeParams "query" (Json.mkObj [
        ("invariantId", Json.num invariantId),
        ("kind", Json.str kind),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
        List (String × Json)) := by simp
      have pi : ("invariantId", Json.num (JsonNumber.fromNat invariantId)) ∈ ([
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
      simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest, reqStr,
        reqNat, decodeParams]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp,
        nat_of_mkObj hp pi, str_of_mkObj hp pk, str_of_mkObj hp ps, jOptNat_mkObj hp pt]
      rfl

  | query id sessionId kinds operator timeoutSec =>
      cases operator with
      | none =>
          refine ⟨.query id sessionId kinds none timeoutSec, ?_, rfl, rfl, rfl, by
            intro v hv; exact absurd hv (by simp), rfl⟩
          have hp : (([
            ("kinds", Json.arr (strsJson kinds |>.toArray)),
            ("operator", Json.null),
            ("sessionId", Json.str sessionId),
            ("timeoutSec", optNat timeoutSec)] :
            List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
          have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
              ("method", Json.str "query"), ("params", Json.mkObj [
            ("kinds", Json.arr (strsJson kinds |>.toArray)),
            ("operator", Json.null),
            ("sessionId", Json.str sessionId),
            ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
          have mm : ("method", Json.str "query") ∈ ([("id", Json.num id),
              ("jsonrpc", Json.str "2.0"), ("method", Json.str "query"), ("params", Json.mkObj [
            ("kinds", Json.arr (strsJson kinds |>.toArray)),
            ("operator", Json.null),
            ("sessionId", Json.str sessionId),
            ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
          have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id),
              ("jsonrpc", Json.str "2.0"), ("method", Json.str "query"), ("params", Json.mkObj [
            ("kinds", Json.arr (strsJson kinds |>.toArray)),
            ("operator", Json.null),
            ("sessionId", Json.str sessionId),
            ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
          have mp : ("params", Json.mkObj [
            ("kinds", Json.arr (strsJson kinds |>.toArray)),
            ("operator", Json.null),
            ("sessionId", Json.str sessionId),
            ("timeoutSec", optNat timeoutSec)]) >>= fun r_ => Except.ok (setReqId id r_) = _
          simp only [decodeParams]
          rw [            strs_of_mkObj hp pk, decOptNullValue_null hp po, str_of_mkObj hp ps,
            jOptNat_mkObj hp pt]
          rfl
      | some op =>
          obtain ⟨hb1, hb2⟩ := hok op (by simp)
          obtain ⟨op', hop', hval⟩ := decodeValue_bounded op hb1
          refine ⟨.query id sessionId kinds (some op') timeoutSec, ?_, rfl, rfl, rfl, hval, rfl⟩
          have hp : (([
            ("kinds", Json.arr (strsJson kinds |>.toArray)),
            ("operator", encValue op),
            ("sessionId", Json.str sessionId),
            ("timeoutSec", optNat timeoutSec)] :
            List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
          have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
              ("method", Json.str "query"), ("params", Json.mkObj [
            ("kinds", Json.arr (strsJson kinds |>.toArray)),
            ("operator", encValue op),
            ("sessionId", Json.str sessionId),
            ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
          have mm : ("method", Json.str "query") ∈ ([("id", Json.num id),
              ("jsonrpc", Json.str "2.0"), ("method", Json.str "query"), ("params", Json.mkObj [
            ("kinds", Json.arr (strsJson kinds |>.toArray)),
            ("operator", encValue op),
            ("sessionId", Json.str sessionId),
            ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
          have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id),
              ("jsonrpc", Json.str "2.0"), ("method", Json.str "query"), ("params", Json.mkObj [
            ("kinds", Json.arr (strsJson kinds |>.toArray)),
            ("operator", encValue op),
            ("sessionId", Json.str sessionId),
            ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
          have mp : ("params", Json.mkObj [
            ("kinds", Json.arr (strsJson kinds |>.toArray)),
            ("operator", encValue op),
            ("sessionId", Json.str sessionId),
            ("timeoutSec", optNat timeoutSec)]) ∈ ([("id", Json.num id),
              ("jsonrpc", Json.str "2.0"), ("method", Json.str "query"), ("params", Json.mkObj [
            ("kinds", Json.arr (strsJson kinds |>.toArray)),
            ("operator", encValue op),
            ("sessionId", Json.str sessionId),
            ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
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
          have hop2 : decOptNullValue (Json.mkObj [
            ("kinds", Json.arr (strsJson kinds |>.toArray)),
            ("operator", encValue op),
            ("sessionId", Json.str sessionId),
            ("timeoutSec", optNat timeoutSec)]) "operator"
              = Except.ok (some op') :=
            (decOptNullValue_enc hp po hb1 hb2).choose_spec
          simp only [encodeRpcRequest, encodeParams, reqId, methodName]
          rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
          show decodeParams "query" (Json.mkObj [
            ("kinds", Json.arr (strsJson kinds |>.toArray)),
            ("operator", Json.null),
            ("sessionId", Json.str sessionId),
            ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
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