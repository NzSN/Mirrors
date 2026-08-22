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