  | query id sessionId kinds operator timeoutSec =>
      cases operator with
      | none =>
          refine ⟨.query id sessionId kinds none timeoutSec, ?_, rfl, rfl, rfl, trivial, rfl⟩
          have hp : (([        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
          have pk : ("kinds", Json.arr (strsJson kinds |>.toArray)) ∈ ([        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
              List (String × Json)) := by simp
          have po : ("operator", Json.null) ∈ ([        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
              List (String × Json)) := by simp
          have ps : ("sessionId", Json.str sessionId) ∈ ([        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
              List (String × Json)) := by simp
          have pt : ("timeoutSec", optNat timeoutSec) ∈ ([        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
              List (String × Json)) := by simp
          have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "query"), ("params", Json.mkObj [        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
          have mm : ("method", Json.str "query") ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "query"), ("params", Json.mkObj [        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
          have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "query"), ("params", Json.mkObj [        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
          have mp : ("params", Json.mkObj [        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)]) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "query"), ("params", Json.mkObj [        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
          simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest, optJson]
          rw [show encValue <$> (none : Option Value) = none from rfl]
          dsimp only
          rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
          show decodeParams "query" (Json.mkObj [        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", Json.null),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)]) >>= fun r_ => Except.ok (setReqId id r_) = _
          simp only [decodeParams]
          rw [strs_of_mkObj hp pk, decOptNullValue_null hp po, str_of_mkObj hp ps, jOptNat_mkObj hp pt]
          rfl

      | some op =>
          obtain ⟨hb1, hb2⟩ := hok op (by simp)
          have hp : (([        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
          have pk : ("kinds", Json.arr (strsJson kinds |>.toArray)) ∈ ([        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
              List (String × Json)) := by simp
          have po : ("operator", encValue op) ∈ ([        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
              List (String × Json)) := by simp
          obtain ⟨w2, hw2⟩ := decOptNullValue_enc hp po hb1 hb2
          refine ⟨.query id sessionId kinds (some w2) timeoutSec, ?_, rfl, rfl, rfl, hw2.2, rfl⟩
          have ps : ("sessionId", Json.str sessionId) ∈ ([        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
              List (String × Json)) := by simp
          have pt : ("timeoutSec", optNat timeoutSec) ∈ ([        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
              List (String × Json)) := by simp
          have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "query"), ("params", Json.mkObj [        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
          have mm : ("method", Json.str "query") ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "query"), ("params", Json.mkObj [        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
          have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "query"), ("params", Json.mkObj [        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
          have mp : ("params", Json.mkObj [        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)]) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "query"), ("params", Json.mkObj [        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)])] :
              List (String × Json)) := by simp
          simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest, optJson]
          rw [show encValue <$> (some op : Option Value) = some (encValue op) from rfl]
          dsimp only
          rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
          show decodeParams "query" (Json.mkObj [        ("kinds", Json.arr (strsJson kinds |>.toArray)),
        ("operator", encValue op),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)]) >>= fun r_ => Except.ok (setReqId id r_) = _
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