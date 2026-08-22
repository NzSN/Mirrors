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
