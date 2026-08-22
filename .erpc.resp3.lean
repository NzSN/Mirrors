
/-- Method that produces a given result shape. -/

def resultMethod : RpcResult → String
  | .health _ => "health"
  | .loadSpec _ _ _ => "loadSpec"
  | .assumeTransition _ _ _ _ => "assumeTransition"
  | .nextStep _ _ _ => "nextStep"
  | .checkInvariant _ _ _ => "checkInvariant"
  | .query _ _ _ _ => "query"
  | .assumeState _ _ _ => "assumeState"
  | .rollback => "rollback"
  | .disposeSpec => "disposeSpec"

private theorem jSpecParameters_ne_null (sp : SpecParameters) :
    jSpecParameters sp ≠ Json.null := by
  intro h
  simp only [jSpecParameters, Json.mkObj] at h
  exact Json.noConfusion h
def RpcResultOk : RpcResult → Prop
  | .checkInvariant _ _ trace => ∀ v ∈ trace, valBounded v ∧ v ≠ Value.vnull
  | .query operatorValue _ state trace =>
      (∀ v ∈ operatorValue, valBounded v ∧ v ≠ Value.vnull)
        ∧ (valBounded state ∧ state ≠ Value.vnull)
        ∧ ∀ v ∈ trace, valBounded v ∧ v ≠ Value.vnull
  | _ => True

/-- Result equality up to valEq at value positions. -/
def RpcResultEquiv : RpcResult → RpcResult → Prop
  | .checkInvariant s i t, .checkInvariant s' i' t' =>
      s = s' ∧ i = i' ∧ optValEq t t'
  | .query o i st t, .query o' i' st' t' =>
      optValEq o o' ∧ i = i' ∧ valEq st st' = true ∧ optValEq t t'
  | a, b => a = b

/-- **§6.6 explorer response round-trip. ** -/
theorem decodeRpcResult_encodeRpcResult :
    ∀ r : RpcResult, RpcResultOk r →
      ∃ r', decodeRpcResult (resultMethod r) (encodeRpcResult r) = Except.ok r'
        ∧ RpcResultEquiv r r' := by
  intro r hok
  cases r with
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
end Codec
