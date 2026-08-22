
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
