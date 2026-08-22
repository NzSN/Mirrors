NL = chr(10)
def J(*parts): return NL.join(parts)

QLIT = NL.join([
'        ("kinds", Json.arr (strsJson kinds |>.toArray)),',
'        ("operator", %OP%),',
'        ("sessionId", Json.str sessionId),',
'        ("timeoutSec", optNat timeoutSec)'])

def qarm(opcase):
    ope = 'Json.null' if opcase == 'none' else 'encValue op'
    lit = QLIT.replace('%OP%', ope)
    pterm = 'Json.mkObj [' + lit + ']'
    el = '[("id", Json.num id), ("jsonrpc", Json.str "2.0"),' + NL + '          ("method", Json.str "query"), ("params", %s)]' % pterm
    pl = '[' + lit + ']'
    L = []
    if opcase == 'none':
        L += ['  | query id sessionId kinds operator timeoutSec =>',
              '      cases operator with',
              '      | none =>',
              '          refine ⟨.query id sessionId kinds none timeoutSec, ?_, rfl, rfl, rfl, by',
              '            intro v hv; exact absurd hv (by simp), rfl⟩']
        ind = '          '
    else:
        L += ['      | some op =>',
              '          obtain ⟨hb1, hb2⟩ := hok op (by simp)',
              '          obtain ⟨op2, hop2dec, hval⟩ := decodeValue_bounded op hb1',
              '          refine ⟨.query id sessionId kinds (some op2) timeoutSec, ?_, rfl, rfl, rfl, hval, rfl⟩']
        ind = '          '
    common = [
      ind + 'have hp : ((%s : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp' % pl,
      ind + 'have pk : ("kinds", Json.arr (strsJson kinds |>.toArray)) ∈ (%s :' % pl,
      ind + '    List (String × Json)) := by simp',
      ind + 'have po : ("operator", %s) ∈ (%s :' % (ope, pl),
      ind + '    List (String × Json)) := by simp',
      ind + 'have ps : ("sessionId", Json.str sessionId) ∈ (%s :' % pl,
      ind + '    List (String × Json)) := by simp',
      ind + 'have pt : ("timeoutSec", optNat timeoutSec) ∈ (%s :' % pl,
      ind + '    List (String × Json)) := by simp',
      ind + 'have hkeys : ((%s :' % el,
      ind + '    List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp',
      ind + 'have mm : ("method", Json.str "query") ∈ (%s :' % el,
      ind + '    List (String × Json)) := by simp',
      ind + 'have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ (%s :' % el,
      ind + '    List (String × Json)) := by simp',
      ind + 'have mp : ("params", %s) ∈ (%s :' % (pterm, el),
      ind + '    List (String × Json)) := by simp',
      ind + 'simp only [encodeRpcRequest, encodeParams, reqId, methodName]',
      ind + 'rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]',
      ind + 'show decodeParams "query" (%s) >>= fun r_ => Except.ok (setReqId id r_) = _' % pterm,
      ind + 'simp only [decodeParams]']
    L += common
    if opcase == 'none':
        L.append(ind + 'rw [strs_of_mkObj hp pk, decOptNullValue_null hp po, str_of_mkObj hp ps, jOptNat_mkObj hp pt]')
    else:
        L.append(ind + 'have hop2 : decOptNullValue (%s) "operator" = Except.ok (some op2) :=' % pterm)
        L.append(ind + '  (decOptNullValue_enc hp po hb1 hb2).choose_spec')
        L.append(ind + 'rw [strs_of_mkObj hp pk, hop2, str_of_mkObj hp ps, jOptNat_mkObj hp pt]')
    L.append(ind + 'rfl')
    return NL.join(L)

asum = J(
'  | assumeState id sessionId equalities checkEnabled timeoutSec =>',
'      obtain ⟨hb1, hb2⟩ := hok',
'      obtain ⟨eq2, heq2dec, hval⟩ := decodeValue_bounded equalities hb1',
'      refine ⟨.assumeState id sessionId eq2 checkEnabled timeoutSec, ?_, rfl, rfl, hval, rfl, rfl⟩',
'      have hp : (([',
'        ("checkEnabled", Json.bool checkEnabled),',
'        ("equalities", encValue equalities),',
'        ("sessionId", Json.str sessionId),',
'        ("timeoutSec", optNat timeoutSec)] :',
'        List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp',
'      have pc : ("checkEnabled", Json.bool checkEnabled) ∈ ([("checkEnabled", Json.bool checkEnabled),',
'        ("equalities", encValue equalities),',
'        ("sessionId", Json.str sessionId),',
'        ("timeoutSec", optNat timeoutSec)] : List (String × Json)) := by simp',
'      have pe : ("equalities", encValue equalities) ∈ ([("checkEnabled", Json.bool checkEnabled),',
'        ("equalities", encValue equalities),',
'        ("sessionId", Json.str sessionId),',
'        ("timeoutSec", optNat timeoutSec)] : List (String × Json)) := by simp',
'      have ps : ("sessionId", Json.str sessionId) ∈ ([("checkEnabled", Json.bool checkEnabled),',
'        ("equalities", encValue equalities),',
'        ("sessionId", Json.str sessionId),',
'        ("timeoutSec", optNat timeoutSec)] : List (String × Json)) := by simp',
'      have pt : ("timeoutSec", optNat timeoutSec) ∈ ([("checkEnabled", Json.bool checkEnabled),',
'        ("equalities", encValue equalities),',
'        ("sessionId", Json.str sessionId),',
'        ("timeoutSec", optNat timeoutSec)] : List (String × Json)) := by simp',
'      have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),',
'          ("method", Json.str "assumeState"), ("params", Json.mkObj [',
'        ("checkEnabled", Json.bool checkEnabled),',
'        ("equalities", encValue equalities),',
'        ("sessionId", Json.str sessionId),',
'        ("timeoutSec", optNat timeoutSec)])] :',
'          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp',
'      have mm : ("method", Json.str "assumeState") ∈ ([("id", Json.num id),',
'          ("jsonrpc", Json.str "2.0"), ("method", Json.str "assumeState"), ("params", Json.mkObj [',
'        ("checkEnabled", Json.bool checkEnabled),',
'        ("equalities", encValue equalities),',
'        ("sessionId", Json.str sessionId),',
'        ("timeoutSec", optNat timeoutSec)])] :',
'          List (String × Json)) := by simp',
'      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id),',
'          ("jsonrpc", Json.str "2.0"), ("method", Json.str "assumeState"), ("params", Json.mkObj [',
'        ("checkEnabled", Json.bool checkEnabled),',
'        ("equalities", encValue equalities),',
'        ("sessionId", Json.str sessionId),',
'        ("timeoutSec", optNat timeoutSec)])] :',
'          List (String × Json)) := by simp',
'      have mp : ("params", Json.mkObj [',
'        ("checkEnabled", Json.bool checkEnabled),',
'        ("equalities", encValue equalities),',
'        ("sessionId", Json.str sessionId),',
'        ("timeoutSec", optNat timeoutSec)]) ∈ ([("id", Json.num id),',
'          ("jsonrpc", Json.str "2.0"), ("method", Json.str "assumeState"), ("params", Json.mkObj [',
'        ("checkEnabled", Json.bool checkEnabled),',
'        ("equalities", encValue equalities),',
'        ("sessionId", Json.str sessionId),',
'        ("timeoutSec", optNat timeoutSec)])] :',
'          List (String × Json)) := by simp',
'      simp only [encodeRpcRequest, encodeParams, reqId, methodName]',
'      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]',
'      show decodeParams "assumeState" (Json.mkObj [',
'        ("checkEnabled", Json.bool checkEnabled),',
'        ("equalities", encValue equalities),',
'        ("sessionId", Json.str sessionId),',
'        ("timeoutSec", optNat timeoutSec)]) >>= fun r_ => Except.ok (setReqId id r_) = _',
'      simp only [decodeParams]',
'      rw [jBool_mkObj hp pc, reqField_of_field hp pe (encValue_ne_of_ne_null equalities hb2) heq2dec,',
'        str_of_mkObj hp ps, jOptNat_mkObj hp pt]',
'      rfl')

open('.erpc.arms2.lean', 'w').write(qarm('none') + NL + NL + qarm('some') + NL + NL + asum + NL)
print('ok')
