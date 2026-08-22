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