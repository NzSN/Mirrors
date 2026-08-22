NL = chr(10)
q = chr(39)
req_hdr = NL.join([
'/-- Wire well-formedness of a request' + q + 's value payloads. -/',
'def RpcRequestOk : RpcRequest → Prop',
'  | .query _ _ _ operator _ => ∀ v ∈ operator, valBounded v ∧ v ≠ Value.vnull',
'  | .assumeState _ _ equalities _ _ => valBounded equalities ∧ equalities ≠ Value.vnull',
'  | _ => True',
'',
'/-- Request equality up to valEq at value positions. -/',
'def RpcRequestEquiv : RpcRequest → RpcRequest → Prop',
'  | .query i s k o t, .query i' + q + ' s' + q + ' k' + q + ' o' + q + ' t' + q + ' =>',
'      i = i' + q + ' ∧ s = s' + q + ' ∧ k = k' + q + ' ∧ optValEq o o' + q + ' ∧ t = t' + q,
'  | .assumeState i s e c t, .assumeState i' + q + ' s' + q + ' e' + q + ' c' + q + ' t' + q + ' =>',
'      i = i' + q + ' ∧ s = s' + q + ' ∧ valEq e e' + q + ' = true ∧ c = c' + q + ' ∧ t = t' + q,
'  | a, b => a = b',
'',
'/-- **§6.6 explorer request round-trip.** -/',
'theorem decodeRpcRequest_encodeRpcRequest :',
'    ∀ r : RpcRequest, RpcRequestOk r →',
'      ∃ r' + q + ', decodeRpcRequest (encodeRpcRequest r) = Except.ok r' + q,
'        ∧ RpcRequestEquiv r r' + q + ' := by',
'  intro r hok',
'  cases r with'])
open('.erpc.reqhdr.lean','w').write(req_hdr)
print('stage c ok')
