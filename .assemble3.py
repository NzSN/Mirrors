head = open('.erpc.head.lean').read()
helpers = open('.erpc.helpers2.lean').read()
arms = open('.erpc.arms.lean').read()
arms2 = open('.erpc.arms2.lean').read()
resp = open('.erpc.resp2.lean').read()
import re
NL = chr(10)

# fix scalar arms in-place: add decodeRpcRequest to simp (arms file from gen3 lacks it? gen3 wrote without)
arms = arms.replace("simp only [encodeRpcRequest, encodeParams, reqId, methodName]",
                    "simp only [encodeRpcRequest, encodeParams, reqId, methodName, decodeRpcRequest]")
# parenthesize show terms
arms = re.sub(r'show (decodeParams "[a-zA-Z]+" .*?) >>= fun r_ => Except\.ok \(setReqId id r_\) = _',
              r'show (\1 >>= fun r_ => Except.ok (setReqId id r_)) = _', arms, flags=re.S)
arms2 = re.sub(r'show (decodeParams "[a-zA-Z]+" .*?) >>= fun r_ => Except\.ok \(setReqId id r_\) = _',
               r'show (\1 >>= fun r_ => Except.ok (setReqId id r_)) = _', arms2, flags=re.S)
# newline-normalize single-line mkObj entries
arms = arms.replace('[        (', '[' + NL + '        (')
arms2 = arms2.replace('[        (', '[' + NL + '        (')

scalar = re.split(r'(?m)^(?=  \| )', arms.rstrip())
scalar = [s for s in scalar if s.strip()]
byname = {}
for s in scalar:
    name = s.split()[1]
    byname[name] = s