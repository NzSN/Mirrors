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
      have mp : ("params", Json.mkObj [("sessionId", Json.str sessionId)]) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "nextStep"),
          ("params", Json.mkObj [("sessionId", Json.str sessionId)])] :
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
      simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest, reqStr,
        reqNat, decodeParams]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp,
        nat_of_mkObj hp pi, str_of_mkObj hp pk, str_of_mkObj hp ps, jOptNat_mkObj hp pt]
      rfl
