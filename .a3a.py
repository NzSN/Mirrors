import re
NL = chr(10)
head = open('.erpc.head.lean').read()
helpers = open('.erpc.helpers2.lean').read()
arms = open('.erpc.arms.lean').read()
arms2 = open('.erpc.arms2.lean').read()
arms = arms.replace("simp only [encodeRpcRequest, encodeParams, reqId, methodName]",
                    "simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest]")
def fix_show(t):
    return re.sub(r'show (decodeParams "[a-zA-Z]+" .*?) >>= fun r_ => Except\.ok \(setReqId id r_\) = _',
                  r'show (\1 >>= fun r_ => Except.ok (setReqId id r_)) = _', t, flags=re.S)
arms = fix_show(arms); arms2 = fix_show(arms2)
arms = arms.replace('[        (', '[' + NL + '        (')
arms2 = arms2.replace('[        (', '[' + NL + '        (')
# query-none trivial fix
arms2 = arms2.replace("rfl, by" + NL + "            intro v hv; exact absurd hv (by simp), rfl" + chr(9654),
                      "rfl, trivial" + chr(9654))
open('.erpc.armsf.lean','w').write(arms)
open('.erpc.arms2f.lean','w').write(arms2)
open('.erpc.headf.lean','w').write(head)
open('.erpc.helpersf.lean','w').write(helpers)
print('stage a ok')
