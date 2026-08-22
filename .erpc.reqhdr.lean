/-- Wire well-formedness of a request's value payloads. -/
def RpcRequestOk : RpcRequest → Prop
  | .query _ _ _ operator _ => ∀ v ∈ operator, valBounded v ∧ v ≠ Value.vnull
  | .assumeState _ _ equalities _ _ => valBounded equalities ∧ equalities ≠ Value.vnull
  | _ => True

/-- Request equality up to valEq at value positions. -/
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