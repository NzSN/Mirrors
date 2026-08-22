import re
NL = chr(10)
resp = open('.erpc.resp.lean').read()
rest = open('.erpc.rest.lean').read()
# drop old mangled tail: rest ends 'c'
rest = rest.rstrip()
if rest.endswith('c'): rest = rest[:-1]
rest = rest.rstrip()

# 1. RpcResultOk conj version
rest = rest.replace("""def RpcResultOk : RpcResult → Prop
  | .checkInvariant _ _ trace => ∀ v ∈ trace, valBounded v
  | .query operatorValue _ state trace =>
      (∀ v ∈ operatorValue, valBounded v) ∧ valBounded state ∧ ∀ v ∈ trace, valBounded v
  | _ => True""",
"""def RpcResultOk : RpcResult → Prop
  | .checkInvariant _ _ trace => ∀ v ∈ trace, valBounded v ∧ v ≠ Value.vnull
  | .query operatorValue _ state trace =>
      (∀ v ∈ operatorValue, valBounded v ∧ v ≠ Value.vnull) ∧ valBounded state
        ∧ ∀ v ∈ trace, valBounded v ∧ v ≠ Value.vnull
  | _ => True""")
assert 'Value.vnull' in rest

# 2. decodeValue_bounded valBounded args -> .1
rest = rest.replace('decodeValue_bounded v (hok v (by simp))', 'decodeValue_bounded v (hok v (by simp)).1')
rest = rest.replace('decodeValue_bounded vt (htr vt (by simp [htrv]))', 'decodeValue_bounded vt (htr vt (by simp [htrv])).1')
rest = rest.replace('decodeValue_bounded vo (ho vo (by simp [hopv]))', 'decodeValue_bounded vo (ho vo (by simp [hopv])).1')

# 3. decOptNullValue_enc uses -> add .2 arg and take .1 of choose_spec
rest = rest.replace('(decOptNullValue_enc hp mt (hok v (by simp))).choose_spec',
                    '(decOptNullValue_enc hp mt (hok v (by simp)).1 (hok v (by simp)).2).choose_spec).1')
rest = rest.replace('(decOptNullValue_enc hp mt (htr vt (by simp))).choose_spec',
                    '(decOptNullValue_enc hp mt (htr vt (by simp)).1 (htr vt (by simp)).2).choose_spec).1')
rest = rest.replace('(decOptNullValue_enc hp mo (ho vo (by simp))).choose_spec',
                    '(decOptNullValue_enc hp mo (ho vo (by simp)).1 (ho vo (by simp)).2).choose_spec).1')

# 4. assumeState result arm? it has no Value; checkInvariant none-arm 'by intro v hv' fine.
# 5. assemble resp_final
i1 = resp.index("private theorem arr_ne_null'")
resp_final = resp[:i1].rstrip() + NL + NL + rest + NL + NL + 'end Codec' + NL
open('.erpc.resp2.lean','w').write(resp_final)
print('resp2 lines', len(resp_final.splitlines()))
