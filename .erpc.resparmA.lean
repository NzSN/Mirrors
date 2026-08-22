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
