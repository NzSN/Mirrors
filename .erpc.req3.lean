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
          simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest, reqStr,
            reqNat, decodeParams]
          rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp,
            strs_of_mkObj hp pk, decOptNullValue_null hp po, str_of_mkObj hp ps,
            jOptNat_mkObj hp pt]
          rfl
      | some op =>
          obtain ⟨op', hop', hval⟩ := decodeValue_bounded op (hok op (by simp))
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
            (decOptNullValue_enc hp po (hok op (by simp))).choose_spec
          simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest, reqStr,
            reqNat, decodeParams]
          rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp,
            strs_of_mkObj hp pk, hop2, str_of_mkObj hp ps, jOptNat_mkObj hp pt]
          rfl
