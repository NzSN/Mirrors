  | assumeState id sessionId equalities checkEnabled timeoutSec =>
      obtain ⟨eq', heq', hval⟩ := decodeValue_bounded equalities hok
      refine ⟨.assumeState id sessionId eq' checkEnabled timeoutSec, ?_, rfl, rfl, hval, rfl, rfl⟩
      have hp : (([
        ("checkEnabled", Json.bool checkEnabled),
        ("equalities", encValue equalities),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
        List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
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
      have pc : ("checkEnabled", Json.bool checkEnabled) ∈ ([
        ("checkEnabled", Json.bool checkEnabled),
        ("equalities", encValue equalities),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
        List (String × Json)) := by simp
      have pe : ("equalities", encValue equalities) ∈ ([
        ("checkEnabled", Json.bool checkEnabled),
        ("equalities", encValue equalities),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
        List (String × Json)) := by simp
      have ps : ("sessionId", Json.str sessionId) ∈ ([
        ("checkEnabled", Json.bool checkEnabled),
        ("equalities", encValue equalities),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
        List (String × Json)) := by simp
      have pt : ("timeoutSec", optNat timeoutSec) ∈ ([
        ("checkEnabled", Json.bool checkEnabled),
        ("equalities", encValue equalities),
        ("sessionId", Json.str sessionId),
        ("timeoutSec", optNat timeoutSec)] :
        List (String × Json)) := by simp
      simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest, reqStr,
        reqNat, decodeParams]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp,
        jBool_mkObj hp pc, reqField_of_field hp pe (encValue_ne_null hok) heq',
        str_of_mkObj hp ps, jOptNat_mkObj hp pt]
      rfl
  | rollback id sessionId snapshotId =>
      refine ⟨.rollback id sessionId snapshotId, ?_, rfl⟩
      have hp : (([("sessionId", Json.str sessionId), ("snapshotId", Json.num snapshotId)] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "rollback"), ("params", Json.mkObj [
        ("sessionId", Json.str sessionId), ("snapshotId", Json.num snapshotId)])] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mm : ("method", Json.str "rollback") ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "rollback"), ("params", Json.mkObj [
        ("sessionId", Json.str sessionId), ("snapshotId", Json.num snapshotId)])] :
          List (String × Json)) := by simp
      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "rollback"), ("params", Json.mkObj [
        ("sessionId", Json.str sessionId), ("snapshotId", Json.num snapshotId)])] :
          List (String × Json)) := by simp
      have mp : ("params", Json.mkObj [
        ("sessionId", Json.str sessionId), ("snapshotId", Json.num snapshotId)]) ∈ ([
        ("id", Json.num id), ("jsonrpc", Json.str "2.0"),
        ("method", Json.str "rollback"), ("params", Json.mkObj [
        ("sessionId", Json.str sessionId), ("snapshotId", Json.num snapshotId)])] :
          List (String × Json)) := by simp
      have ps : ("sessionId", Json.str sessionId) ∈ ([("sessionId", Json.str sessionId),
          ("snapshotId", Json.num snapshotId)] : List (String × Json)) := by simp
      have pn : ("snapshotId", Json.num (JsonNumber.fromNat snapshotId)) ∈ ([
          ("sessionId", Json.str sessionId), ("snapshotId", Json.num snapshotId)] :
          List (String × Json)) := by simp
      simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest, reqStr,
        reqNat, decodeParams]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp,
        str_of_mkObj hp ps, nat_of_mkObj hp pn]
      rfl
  | disposeSpec id sessionId =>
      refine ⟨.disposeSpec id sessionId, ?_, rfl⟩
      have hp : (([("sessionId", Json.str sessionId)] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "disposeSpec"), ("params", Json.mkObj [("sessionId", Json.str sessionId)])] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mm : ("method", Json.str "disposeSpec") ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "disposeSpec"),
          ("params", Json.mkObj [("sessionId", Json.str sessionId)])] :
          List (String × Json)) := by simp
      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "disposeSpec"),
          ("params", Json.mkObj [("sessionId", Json.str sessionId)])] :
          List (String × Json)) := by simp
      have mp : ("params", Json.mkObj [("sessionId", Json.str sessionId)]) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "disposeSpec"),
          ("params", Json.mkObj [("sessionId", Json.str sessionId)])] :
          List (String × Json)) := by simp
      have ps : ("sessionId", Json.str sessionId) ∈ ([("sessionId", Json.str sessionId)] :
          List (String × Json)) := by simp
      simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest, reqStr,
        reqNat, decodeParams]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp,
        str_of_mkObj hp ps]
      rfl
