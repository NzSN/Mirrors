
import re
p = 'Codec/ExplorerRpc.lean'
t = open(p).read()

# --- 1. RpcRequestOk conj ---
t = t.replace("""def RpcRequestOk : RpcRequest → Prop
  | .query _ _ _ operator _ => ∀ v ∈ operator, valBounded v
  | .assumeState _ _ equalities _ _ => valBounded equalities
  | _ => True""",
"""def RpcRequestOk : RpcRequest → Prop
  | .query _ _ _ operator _ => ∀ v ∈ operator, valBounded v ∧ v ≠ Value.vnull
  | .assumeState _ _ equalities _ _ => valBounded equalities ∧ equalities ≠ Value.vnull
  | _ => True""")

# --- 2. assumeState arm: destructure hok ---
t = t.replace("""      obtain ⟨eq', heq', hval⟩ := decodeValue_bounded equalities hok
      refine ⟨.assumeState id sessionId eq' checkEnabled timeoutSec, ?_, rfl, rfl, hval, rfl, rfl⟩""",
"""      obtain ⟨hb1, hb2⟩ := hok
      obtain ⟨eq', heq', hval⟩ := decodeValue_bounded equalities hb1
      refine ⟨.assumeState id sessionId eq' checkEnabled timeoutSec, ?_, rfl, rfl, hval, rfl, rfl⟩""")
t = t.replace("reqField_of_field hp pe (encValue_ne_null hok) heq'",
              "reqField_of_field hp pe (encValue_ne_of_ne_null equalities hb2) heq'")

# --- 3. query some-arm: destructure hok, fix choose_spec uses ---
t = t.replace("obtain ⟨op', hop', hval⟩ := decodeValue_bounded op (hok op (by simp))",
"""obtain ⟨hb1, hb2⟩ := hok op (by simp)
          obtain ⟨op', hop', hval⟩ := decodeValue_bounded op hb1""")
t = t.replace("""              = Except.ok (some op') :=
            (decOptNullValue_enc hp po (hok op (by simp))).choose_spec""",
"""              = Except.ok (some op') :=
            (decOptNullValue_enc hp po hb1 hb2).choose_spec""")

# --- 4. generic tail conversion to show-technique ---
# pattern: IND simp only [encodeRpcRequest, ...decodeParams]\nIND2 rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp,\n REST ] \n IND rfl
pat = re.compile(
 r"(?P<ind>[ ]+)simp only \[encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest, reqStr,\n"
 r"[ ]+reqNat, decodeParams\]\n"
 r"[ ]+rw \[str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp,\n"
 r"(?P<rest>.*?)\]\n"
 r"[ ]+rfl", re.S)

def conv(m):
    start = m.start()
    # nearest preceding '("method", Json.str "MTH")'
    mm = list(re.finditer(r'\("method", Json\.str "([a-zA-Z]+)"\)', t[:start]))
    mth = mm[-1].group(1)
    # nearest preceding have mp : ("params", Json.mkObj [ ... ]) ∈
    mp = list(re.finditer(r'\("params", Json\.mkObj \[(?P<lit>.*?)\]\) ∈', t[:start], re.S))
    lit = mp[-1].group('lit')
    ind = m.group('ind')
    rest = m.group('rest')
    new = (ind + "simp only [encodeRpcRequest, encodeParams, reqId, methodName]\n"
      + ind + "rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]\n"
      + ind + 'show decodeParams "%s" (Json.mkObj [%s]) >>= fun r_ => Except.ok (setReqId id r_) = _\n' % (mth, lit)
      + ind + "simp only [decodeParams]\n"
      + ind + "rw [" + rest + "]\n"
      + ind + "rfl")
    return new

t2, n = pat.subn(conv, t)
print("converted tails:", n)
open(p,'w').write(t2)
