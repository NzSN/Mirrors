def RpcResultOk : RpcResult → Prop
  | .checkInvariant _ _ trace => ∀ v ∈ trace, valBounded v
  | .query operatorValue _ state trace =>
      (∀ v ∈ operatorValue, valBounded v) ∧ valBounded state ∧ ∀ v ∈ trace, valBounded v
  | _ => True

/-- Result equality up to `valEq` at value positions. -/
def RpcResultEquiv : RpcResult → RpcResult → Prop
  | .checkInvariant s i t, .checkInvariant s' i' t' =>
      s = s' ∧ i = i' ∧ optValEq t t'
  | .query o i st t, .query o' i' st' t' =>
      optValEq o o' ∧ i = i' ∧ valEq st st' = true ∧ optValEq t t'
  | a, b => a = b

/-- **§6.6 explorer response round-trip.** -/
theorem decodeRpcResult_encodeRpcResult :
    ∀ r : RpcResult, RpcResultOk r →
      ∃ r', decodeRpcResult (resultMethod r) (encodeRpcResult r) = Except.ok r'
        ∧ RpcResultEquiv r r' := by
  intro r hok
  cases r with
  | health status =>
      refine ⟨.health status, ?_, rfl⟩
      have hkeys : (([("status", Json.str status)] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have ms : ("status", Json.str status) ∈ ([("status", Json.str status)] :
          List (String × Json)) := by simp
      simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr]
      rw [str_of_mkObj hkeys ms]
      rfl
  | loadSpec sessionId snapshotId specParameters =>
      refine ⟨.loadSpec sessionId snapshotId specParameters, ?_, rfl⟩
      have hp : (([
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("specParameters", jSpecParameters specParameters)] :
        List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have ms : ("sessionId", Json.str sessionId) ∈ ([
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("specParameters", jSpecParameters specParameters)] :
        List (String × Json)) := by simp
      have mn : ("snapshotId", Json.num (JsonNumber.fromNat snapshotId)) ∈ ([
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("specParameters", jSpecParameters specParameters)] :
        List (String × Json)) := by simp
      have mp : ("specParameters", jSpecParameters specParameters) ∈ ([
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("specParameters", jSpecParameters specParameters)] :
        List (String × Json)) := by simp
      simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, reqNat]
      rw [str_of_mkObj hp ms, nat_of_mkObj hp mn,
        reqField_of_field hp mp (jSpecParameters_ne_null specParameters)
          (decSpecParameters_jSpecParameters specParameters)]
      rfl
  | assumeTransition sessionId snapshotId status transitionId =>
      refine ⟨.assumeTransition sessionId snapshotId status transitionId, ?_, rfl⟩
      have hp : (([
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("status", Json.str status),
        ("transitionId", Json.num transitionId)] :
        List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have ms : ("sessionId", Json.str sessionId) ∈ ([
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("status", Json.str status),
        ("transitionId", Json.num transitionId)] :
        List (String × Json)) := by simp
      have mn : ("snapshotId", Json.num (JsonNumber.fromNat snapshotId)) ∈ ([
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("status", Json.str status),
        ("transitionId", Json.num transitionId)] :
        List (String × Json)) := by simp
      have mt : ("status", Json.str status) ∈ ([
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("status", Json.str status),
        ("transitionId", Json.num transitionId)] :
        List (String × Json)) := by simp
      have mr : ("transitionId", Json.num (JsonNumber.fromNat transitionId)) ∈ ([
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId),
        ("status", Json.str status),
        ("transitionId", Json.num transitionId)] :
        List (String × Json)) := by simp
      simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, reqNat]
      rw [str_of_mkObj hp ms, nat_of_mkObj hp mn, str_of_mkObj hp mt, nat_of_mkObj hp mr]
      rfl
  | nextStep newStepNo sessionId snapshotId =>
      refine ⟨.nextStep newStepNo sessionId snapshotId, ?_, rfl⟩
      have hp : (([
        ("newStepNo", Json.num newStepNo),
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId)] :
        List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mn : ("newStepNo", Json.num (JsonNumber.fromNat newStepNo)) ∈ ([
        ("newStepNo", Json.num newStepNo),
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId)] :
        List (String × Json)) := by simp
      have ms : ("sessionId", Json.str sessionId) ∈ ([
        ("newStepNo", Json.num newStepNo),
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId)] :
        List (String × Json)) := by simp
      have mp : ("snapshotId", Json.num (JsonNumber.fromNat snapshotId)) ∈ ([
        ("newStepNo", Json.num newStepNo),
        ("sessionId", Json.str sessionId),
        ("snapshotId", Json.num snapshotId)] :
        List (String × Json)) := by simp
      simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, reqNat]
      rw [nat_of_mkObj hp mn, str_of_mkObj hp ms, nat_of_mkObj hp mp]
      rfl
  | checkInvariant invariantStatus sessionId trace =>
      cases trace with
      | none =>
          refine ⟨.checkInvariant invariantStatus sessionId none, ?_, rfl, rfl, by intro v hv; exact absurd hv (by simp)⟩
          have hp : (([
            ("invariantStatus", Json.str invariantStatus),
            ("sessionId", Json.str sessionId),
            ("trace", Json.null)] :
            List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
          have mi : ("invariantStatus", Json.str invariantStatus) ∈ ([
            ("invariantStatus", Json.str invariantStatus),
            ("sessionId", Json.str sessionId),
            ("trace", Json.null)] :
            List (String × Json)) := by simp
          have ms : ("sessionId", Json.str sessionId) ∈ ([
            ("invariantStatus", Json.str invariantStatus),
            ("sessionId", Json.str sessionId),
            ("trace", Json.null)] :
            List (String × Json)) := by simp
          have mt : ("trace", Json.null) ∈ ([
            ("invariantStatus", Json.str invariantStatus),
            ("sessionId", Json.str sessionId),
            ("trace", Json.null)] :
            List (String × Json)) := by simp
          simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr]
          rw [str_of_mkObj hp mi, str_of_mkObj hp ms, decOptNullValue_null hp mt]
          rfl
      | some v =>
          obtain ⟨w, hw, hval⟩ := decodeValue_bounded v (hok v (by simp))
          refine ⟨.checkInvariant invariantStatus sessionId (some w), ?_, rfl, rfl, hval⟩
          have hp : (([
            ("invariantStatus", Json.str invariantStatus),
            ("sessionId", Json.str sessionId),
            ("trace", encValue v)] :
            List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
          have mi : ("invariantStatus", Json.str invariantStatus) ∈ ([
            ("invariantStatus", Json.str invariantStatus),
            ("sessionId", Json.str sessionId),
            ("trace", encValue v)] :
            List (String × Json)) := by simp
          have ms : ("sessionId", Json.str sessionId) ∈ ([
            ("invariantStatus", Json.str invariantStatus),
            ("sessionId", Json.str sessionId),
            ("trace", encValue v)] :
            List (String × Json)) := by simp
          have mt : ("trace", encValue v) ∈ ([
            ("invariantStatus", Json.str invariantStatus),
            ("sessionId", Json.str sessionId),
            ("trace", encValue v)] :
            List (String × Json)) := by simp
          have hw2 : decOptNullValue (Json.mkObj [
            ("invariantStatus", Json.str invariantStatus),
            ("sessionId", Json.str sessionId),
            ("trace", encValue v)]) "trace" = Except.ok (some w) :=
              (decOptNullValue_enc hp mt (hok v (by simp))).choose_spec
          simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr]
          rw [str_of_mkObj hp mi, str_of_mkObj hp ms, hw2]
          rfl
  | query operatorValue sessionId state trace =>
      obtain ⟨ho, hst, htr⟩ := hok
      obtain ⟨stw, hstw, hstval⟩ := decodeValue_bounded state hst
      cases hopv : operatorValue with
      | none =>
          cases htrv : trace with
          | none =>
              refine ⟨.query none sessionId stw none, ?_, by trivial, rfl, hstval, by trivial⟩
              have hp : (([
                ("operatorValue", Json.null),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)] :
                List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
              have mo : ("operatorValue", Json.null) ∈ ([
                ("operatorValue", Json.null),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)] :
                List (String × Json)) := by simp
              have ms : ("sessionId", Json.str sessionId) ∈ ([
                ("operatorValue", Json.null),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)] :
                List (String × Json)) := by simp
              have mst : ("state", encValue state) ∈ ([
                ("operatorValue", Json.null),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)] :
                List (String × Json)) := by simp
              have mt : ("trace", Json.null) ∈ ([
                ("operatorValue", Json.null),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)] :
                List (String × Json)) := by simp
              simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, hopv, htrv]
              rw [decOptNullValue_null hp mo, str_of_mkObj hp ms,
                reqField_of_field hp mst (encValue_ne_null hst) hstw,
                decOptNullValue_null hp mt]
              rfl
          | some vt =>
              obtain ⟨tw, htw, htval⟩ := decodeValue_bounded vt (htr vt (by simp [htrv]))
              refine ⟨.query none sessionId stw (some tw), ?_, by trivial, rfl, hstval, htval⟩
              have hp : (([
                ("operatorValue", Json.null),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] :
                List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
              have mo : ("operatorValue", Json.null) ∈ ([
                ("operatorValue", Json.null),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] :
                List (String × Json)) := by simp
              have ms : ("sessionId", Json.str sessionId) ∈ ([
                ("operatorValue", Json.null),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] :
                List (String × Json)) := by simp
              have mst : ("state", encValue state) ∈ ([
                ("operatorValue", Json.null),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] :
                List (String × Json)) := by simp
              have mt : ("trace", encValue vt) ∈ ([
                ("operatorValue", Json.null),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] :
                List (String × Json)) := by simp
              have htw2 : decOptNullValue (Json.mkObj [
                ("operatorValue", Json.null),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)]) "trace" = Except.ok (some tw) :=
                  (decOptNullValue_enc hp mt (htr vt (by simp))).choose_spec
              simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, hopv, htrv]
              rw [decOptNullValue_null hp mo, str_of_mkObj hp ms,
                reqField_of_field hp mst (encValue_ne_null hst) hstw, htw2]
              rfl
      | some vo =>
          obtain ⟨ow, how, hovval⟩ := decodeValue_bounded vo (ho vo (by simp [hopv]))
          cases htrv : trace with
          | none =>
              refine ⟨.query (some ow) sessionId stw none, ?_, hovval, rfl, hstval, by trivial⟩
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
                ("trace", Json.null)] :
                List (String × Json)) := by simp
              have ms : ("sessionId", Json.str sessionId) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)] :
                List (String × Json)) := by simp
              have mst : ("state", encValue state) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)] :
                List (String × Json)) := by simp
              have mt : ("trace", Json.null) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)] :
                List (String × Json)) := by simp
              have how2 : decOptNullValue (Json.mkObj [
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", Json.null)]) "operatorValue" = Except.ok (some ow) :=
                  (decOptNullValue_enc hp mo (ho vo (by simp))).choose_spec
              simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, hopv, htrv]
              rw [how2, str_of_mkObj hp ms,
                reqField_of_field hp mst (encValue_ne_null hst) hstw,
                decOptNullValue_null hp mt]
              rfl
          | some vt =>
              obtain ⟨tw, htw, htval⟩ := decodeValue_bounded vt (htr vt (by simp [htrv]))
              refine ⟨.query (some ow) sessionId stw (some tw), ?_, hovval, rfl, hstval, htval⟩
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
                ("trace", encValue vt)] :
                List (String × Json)) := by simp
              have ms : ("sessionId", Json.str sessionId) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] :
                List (String × Json)) := by simp
              have mst : ("state", encValue state) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] :
                List (String × Json)) := by simp
              have mt : ("trace", encValue vt) ∈ ([
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)] :
                List (String × Json)) := by simp
              have how2 : decOptNullValue (Json.mkObj [
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)]) "operatorValue" = Except.ok (some ow) :=
                  (decOptNullValue_enc hp mo (ho vo (by simp))).choose_spec
              have htw2 : decOptNullValue (Json.mkObj [
                ("operatorValue", encValue vo),
                ("sessionId", Json.str sessionId),
                ("state", encValue state),
                ("trace", encValue vt)]) "trace" = Except.ok (some tw) :=
                  (decOptNullValue_enc hp mt (htr vt (by simp))).choose_spec
              simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, hopv, htrv]
              rw [how2, str_of_mkObj hp ms,
                reqField_of_field hp mst (encValue_ne_null hst) hstw, htw2]
              rfl
c