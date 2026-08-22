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
