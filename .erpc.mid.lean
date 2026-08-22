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

/-- Wire well-formedness of a response's value payloads. -/