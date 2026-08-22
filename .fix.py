p='Codec/ExplorerRpc.lean'
t=open(p).read()
NL=chr(10)
old_orphan = NL+NL+"/-- Wire well-formedness of a response's value payloads. -/"+NL+NL+NL+"/-! ## §6.6-style round-trips -/"+NL+NL+"private theorem encValue_ne_null' (v : Value) : encValue v ≠ Json.null := by"+NL+"  cases v <;> simp [encValue]"+NL
new_block = NL+NL+"private theorem arr_ne_null' (a : Array Json) : Json.arr a ≠ Json.null := by"+NL+"  intro h"+NL+"  exact Json.noConfusion h"+NL+NL+"/-! ## §6.6-style round-trips -/"+NL+NL+"private theorem encValue_ne_of_ne_null (v : Value) (h : v ≠ Value.vnull) :"+NL+"    encValue v ≠ Json.null := by"+NL+"  intro he"+NL+"  cases v with"+NL+"  | vnull => exact absurd rfl h"+NL+"  | _ => simp only [encValue, Json.mkObj] at he; exact Json.noConfusion he"+NL+NL
assert old_orphan in t, 'orphan not found'
t = t.replace(old_orphan, new_block)
t = t.replace('arr_ne_null _', "arr_ne_null' _")
open(p,'w').write(t)
print('ok')