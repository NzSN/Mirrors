
/-! ## §6.6-style round-trips -/

private theorem jBool_mkObj {l : List (String × Json)} {k : String} {b : Bool}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : (k, Json.bool b) ∈ l) :
    jBool (Json.mkObj l) k = Except.ok b := by
  simp only [jBool, getObjVal?_mkObj hkeys hm]

private theorem jOptNat_mkObj {l : List (String × Json)} {k : String} {o : Option Nat}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : (k, optNat o) ∈ l) :
    jOptNat (Json.mkObj l) k = Except.ok o := by
  simp only [jOptNat, getObjVal?_mkObj hkeys hm]
  cases o <;> rfl

private theorem jField_of_mkObj {l : List (String × Json)} {k : String} {v : Json}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : (k, v) ∈ l) :
    jField (Json.mkObj l) k = Except.ok v := by
  simp only [jField, getObjVal?_mkObj hkeys hm]

private theorem decOptNullValue_enc {l : List (String × Json)} {k : String} {v : Value}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : (k, encValue v) ∈ l) (hb : valBounded v) :
    ∃ w, decOptNullValue (Json.mkObj l) k = Except.ok (some w) ∧ valEq v w = true := by
  obtain ⟨w, hw, hval⟩ := decodeValue_bounded v hb
  refine ⟨w, ?_, hval⟩
  simp only [decOptNullValue, getObjVal?_mkObj hkeys hm, hw]
  rfl

private theorem decOptNullValue_null {l : List (String × Json)} {k : String}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : (k, Json.null) ∈ l) :
    decOptNullValue (Json.mkObj l) k = Except.ok none := by
  simp only [decOptNullValue, getObjVal?_mkObj hkeys hm]

private theorem decTransitionSummary_jTransitionSummary (t : TransitionSummary) :
    decTransitionSummary (jTransitionSummary t) = Except.ok t := by
  have hkeys : (([("index", Json.num t.index),
      ("labels", Json.arr (strsJson t.labels |>.toArray))] :
      List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
  have mi : ("index", Json.num (JsonNumber.fromNat t.index)) ∈ ([("index", Json.num t.index),
      ("labels", Json.arr (strsJson t.labels |>.toArray))] :
      List (String × Json)) := by simp
  have ml : ("labels", Json.arr (strsJson t.labels |>.toArray)) ∈ ([("index", Json.num t.index),
      ("labels", Json.arr (strsJson t.labels |>.toArray))] :
      List (String × Json)) := by simp
  simp only [jTransitionSummary, decTransitionSummary, reqStr]
  rw [nat_of_mkObj hkeys mi, strs_of_mkObj hkeys ml]
  rfl

private theorem decTransitions_enc :
    ∀ ts : List TransitionSummary,
      decTransitions (Json.arr ((ts.map jTransitionSummary).toArray)) = Except.ok ts := by
  intro ts
  induction ts with
  | nil => rfl
  | cons t rest ih =>
      have harr : ((t :: rest).map jTransitionSummary).toArray.toList
          = jTransitionSummary t :: ((rest.map jTransitionSummary).toArray).toList := by
        simp only [List.map_cons, List.toList_toArray]
      show List.mapM decTransitionSummary (((t :: rest).map jTransitionSummary).toArray).toList = _
      rw [harr, List.mapM_cons, decTransitionSummary_jTransitionSummary t]
      have ih2 : List.mapM decTransitionSummary
          ((rest.map jTransitionSummary).toArray).toList = Except.ok rest := ih
      rw [ih2]
      rfl

private theorem decSpecParameters_jSpecParameters (sp : SpecParameters) :
    decSpecParameters (jSpecParameters sp) = Except.ok sp := by
  have hkeys : (([
      ("actionInvariants", jTransitions sp.actionInvariants),
      ("initTransitions", jTransitions sp.initTransitions),
      ("nextTransitions", jTransitions sp.nextTransitions),
      ("stateInvariants", jTransitions sp.stateInvariants)] :
      List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
  have m1 : ("actionInvariants", jTransitions sp.actionInvariants) ∈ ([
      ("actionInvariants", jTransitions sp.actionInvariants),
      ("initTransitions", jTransitions sp.initTransitions),
      ("nextTransitions", jTransitions sp.nextTransitions),
      ("stateInvariants", jTransitions sp.stateInvariants)] :
      List (String × Json)) := by simp
  have m2 : ("initTransitions", jTransitions sp.initTransitions) ∈ ([
      ("actionInvariants", jTransitions sp.actionInvariants),
      ("initTransitions", jTransitions sp.initTransitions),
      ("nextTransitions", jTransitions sp.nextTransitions),
      ("stateInvariants", jTransitions sp.stateInvariants)] :
      List (String × Json)) := by simp
  have m3 : ("nextTransitions", jTransitions sp.nextTransitions) ∈ ([
      ("actionInvariants", jTransitions sp.actionInvariants),
      ("initTransitions", jTransitions sp.initTransitions),
      ("nextTransitions", jTransitions sp.nextTransitions),
      ("stateInvariants", jTransitions sp.stateInvariants)] :
      List (String × Json)) := by simp
  have m4 : ("stateInvariants", jTransitions sp.stateInvariants) ∈ ([
      ("actionInvariants", jTransitions sp.actionInvariants),
      ("initTransitions", jTransitions sp.initTransitions),
      ("nextTransitions", jTransitions sp.nextTransitions),
      ("stateInvariants", jTransitions sp.stateInvariants)] :
      List (String × Json)) := by simp
  simp only [jSpecParameters, decSpecParameters, reqStr]
  rw [reqField_of_field hkeys m1 (arr_ne_null _) (decTransitions_enc sp.actionInvariants),
      reqField_of_field hkeys m2 (arr_ne_null _) (decTransitions_enc sp.initTransitions),
      reqField_of_field hkeys m3 (arr_ne_null _) (decTransitions_enc sp.nextTransitions),
      reqField_of_field hkeys m4 (arr_ne_null _) (decTransitions_enc sp.stateInvariants)]
  rfl
