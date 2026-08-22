
/-- Wire well-formedness of a request's value payloads. -/
def RpcRequestOk : RpcRequest → Prop
  | .query _ _ _ operator _ => ∀ v ∈ operator, valBounded v
  | .assumeState _ _ equalities _ _ => valBounded equalities
  | _ => True

/-- Request equality up to `valEq` at value positions. -/
def RpcRequestEquiv : RpcRequest → RpcRequest → Prop
  | .query i s k o t, .query i' s' k' o' t' =>
      i = i' ∧ s = s' ∧ k = k' ∧ optValEq o o' ∧ t = t'
  | .assumeState i s e c t, .assumeState i' s' e' c' t' =>
      i = i' ∧ s = s' ∧ valEq e e' = true ∧ c = c' ∧ t = t'
  | a, b => a = b

/-- **§6.6 explorer request round-trip.** -/
theorem decodeRpcRequest_encodeRpcRequest :
    ∀ r : RpcRequest, RpcRequestOk r →
      ∃ r', decodeRpcRequest (encodeRpcRequest r) = Except.ok r'
        ∧ RpcRequestEquiv r r' := by
  intro r hok
  cases r with
  | health id =>
      refine ⟨.health id, ?_, rfl⟩
      have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "health"), ("params", Json.arr #[])] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mm : ("method", Json.str "health") ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "health"), ("params", Json.arr #[])] :
          List (String × Json)) := by simp
      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id),
          ("jsonrpc", Json.str "2.0"), ("method", Json.str "health"),
          ("params", Json.arr #[])] : List (String × Json)) := by simp
      have mp : ("params", Json.arr #[]) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),
          ("method", Json.str "health"), ("params", Json.arr #[])] :
          List (String × Json)) := by simp
      simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest, reqStr,
        reqNat, decodeParams]
      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]
      rfl
