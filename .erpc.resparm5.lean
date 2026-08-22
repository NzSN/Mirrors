      | some vo =>
          cases htrv : trace with
          | none =>
              have hp : (([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)] :
                List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
              have mo : ("operatorValue", encValue vo) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)] : List (String × Json)) := by simp
              obtain ⟨ow, how2⟩ := decOptNullValue_enc hp mo
                (ho vo (by simp [hopv])).1 (ho vo (by simp [hopv])).2
              refine ⟨.query (some ow) sessionId stw none, ?_, how2.2, rfl, hstval, trivial⟩
              have ms : ("sessionId", Json.str sessionId) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)] : List (String × Json)) := by simp
              have mst : ("state", encValue state) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)] : List (String × Json)) := by simp
              simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, optJson, hopv, htrv]
              rw [show encValue <$> (some vo : Option Value) = some (encValue vo) from rfl,
                show encValue <$> (none : Option Value) = none from rfl]
              dsimp only
              rw [how2.1, str_of_mkObj hp ms,
                reqField_of_field hp mst (encValue_ne_of_ne_null state hst.2) hstw]
              rfl
          | some vt =>
              have hp : (([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] :
                List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
              have mo : ("operatorValue", encValue vo) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] : List (String × Json)) := by simp
              have mt : ("trace", encValue vt) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] : List (String × Json)) := by simp
              obtain ⟨ow, how2⟩ := decOptNullValue_enc hp mo
                (ho vo (by simp [hopv])).1 (ho vo (by simp [hopv])).2
              obtain ⟨tw, htw2⟩ := decOptNullValue_enc hp mt
                (htr vt (by simp [htrv])).1 (htr vt (by simp [htrv])).2
              refine ⟨.query (some ow) sessionId stw (some tw), ?_, how2.2, rfl, hstval, htw2.2⟩
              have ms : ("sessionId", Json.str sessionId) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] : List (String × Json)) := by simp
              have mst : ("state", encValue state) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] : List (String × Json)) := by simp
              simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, optJson, hopv, htrv]
              rw [show encValue <$> (some vo : Option Value) = some (encValue vo) from rfl,
                show encValue <$> (some vt : Option Value) = some (encValue vt) from rfl]
              dsimp only
              rw [how2.1, str_of_mkObj hp ms,
                reqField_of_field hp mst (encValue_ne_of_ne_null state hst.2) hstw, htw2.1]
              rfl
