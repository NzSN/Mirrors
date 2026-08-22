NL = chr(10)
hdr = open('.erpc.resp2.lean').read()
hdr = hdr[:hdr.index('def RpcResultOk')].rstrip()
q = chr(39)
defs = NL.join([
'def RpcResultOk : RpcResult → Prop',
'  | .checkInvariant _ _ trace => ∀ v ∈ trace, valBounded v ∧ v ≠ Value.vnull',
'  | .query operatorValue _ state trace =>',
'      (∀ v ∈ operatorValue, valBounded v ∧ v ≠ Value.vnull)',
'        ∧ (valBounded state ∧ state ≠ Value.vnull)',
'        ∧ ∀ v ∈ trace, valBounded v ∧ v ≠ Value.vnull',
'  | _ => True',
'',
'/-- Result equality up to valEq at value positions. -/',
'def RpcResultEquiv : RpcResult → RpcResult → Prop',
'  | .checkInvariant s i t, .checkInvariant s' + q + ' i' + q + ' t' + q + ' =>',
'      s = s' + q + ' ∧ i = i' + q + ' ∧ optValEq t t' + q,
'  | .query o i st t, .query o' + q + ' i' + q + ' st' + q + ' t' + q + ' =>',
'      optValEq o o' + q + ' ∧ i = i' + q + ' ∧ valEq st st' + q + ' = true ∧ optValEq t t' + q,
'  | a, b => a = b',
'',
'/-- **§6.6 explorer response round-trip. ** -/',
'theorem decodeRpcResult_encodeRpcResult :',
'    ∀ r : RpcResult, RpcResultOk r →',
'      ∃ r' + q + ', decodeRpcResult (resultMethod r) (encodeRpcResult r) = Except.ok r' + q,
'        ∧ RpcResultEquiv r r' + q + ' := by',
'  intro r hok',
'  cases r with'])
open('.erpc.respdefs.lean','w').write(defs)
print('defs ok')
