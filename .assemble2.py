head = open('.erpc.head.lean').read()
helpers = open('.erpc.helpers2.lean').read()
arms = open('.erpc.arms.lean').read()
arms2 = open('.erpc.arms2.lean').read()
resp = open('.erpc.resp.lean').read()
NL = chr(10)
# split scalar arms into individual blocks (blank-line separated, start with '  | ')
blocks = [b for b in arms.rstrip().split(NL) ]
# better: split on lines starting with '  | '
import re
scalar = re.split(r'(?m)^(?=  \| )', arms.rstrip())
scalar = [s for s in scalar if s.strip()]
order = ['health', 'loadSpec', 'assumeTransition', 'nextStep', 'checkInvariant', 'query', 'assumeState', 'rollback', 'disposeSpec']
byname = {}
for s in scalar:
    name = s.split()[1]
    byname[name] = s
aq = arms2.split('  | assumeState id sessionId equalities checkEnabled timeoutSec =>')[0].rstrip()
asum = '  | assumeState id sessionId equalities checkEnabled timeoutSec =>' + arms2.split('  | assumeState id sessionId equalities checkEnabled timeoutSec =>')[1].rstrip()
byname['query'] = aq
byname['assumeState'] = asum
final_arms = NL + NL.join(byname[n] for n in order) + NL
reqthm_hdr = NL.join([
'/-- Wire well-formedness of a request', chr(39) + 's value payloads. -/',
'def RpcRequestOk : RpcRequest → Prop',
'  | .query _ _ _ operator _ => ∀ v ∈ operator, valBounded v ∧ v ≠ Value.vnull',
'  | .assumeState _ _ equalities _ _ => valBounded equalities ∧ equalities ≠ Value.vnull',
'  | _ => True',
'',
'/-- Request equality up to valEq at value positions. -/',
'def RpcRequestEquiv : RpcRequest → RpcRequest → Prop',
'  | .query i s k o t, .query i' + chr(39) + ' s' + chr(39) + ' k' + chr(39) + ' o' + chr(39) + ' t' + chr(39) + ' =>',
'      i = i' + chr(39) + ' ∧ s = s' + chr(39) + ' ∧ k = k' + chr(39) + ' ∧ optValEq o o' + chr(39) + ' ∧ t = t' + chr(39),
'  | .assumeState i s e c t, .assumeState i' + chr(39) + ' s' + chr(39) + ' e' + chr(39) + ' c' + chr(39) + ' t' + chr(39) + ' =>',
'      i = i' + chr(39) + ' ∧ s = s' + chr(39) + ' ∧ valEq e e' + chr(39) + ' = true ∧ c = c' + chr(39) + ' ∧ t = t' + chr(39),
'  | a, b => a = b',
'',
'/-- **§6.6 explorer request round-trip.** -/',
'theorem decodeRpcRequest_encodeRpcRequest :',
'    ∀ r : RpcRequest, RpcRequestOk r →',
'      ∃ r' + chr(39) + ', decodeRpcRequest (encodeRpcRequest r) = Except.ok r' + chr(39),
'        ∧ RpcRequestEquiv r r' + chr(39) + ' := by',
'  intro r hok',
'  cases r with'])
out = NL.join([head.rstrip(), '', '/-! ## §6.6-style round-trips -/', '', helpers.rstrip(), reqthm_hdr, final_arms.rstrip(), '', resp.rstrip(), ''])
open('Codec/ExplorerRpc.lean', 'w').write(out + NL)
print('assembled', len(out.splitlines()))
