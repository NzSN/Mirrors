import re
NL = chr(10)
arms = open('.erpc.armsf.lean').read()
arms2 = open('.erpc.arms2f.lean').read()
scalar = re.split(r'(?m)^(?=  \| )', arms.rstrip())
scalar = [s for s in scalar if s.strip()]
byname = {}
for s in scalar:
    byname[s.split()[1]] = s
marker = '  | assumeState id sessionId equalities checkEnabled timeoutSec =>'
parts = arms2.split(marker)
aq = parts[0].rstrip()
asum = marker + parts[1].rstrip()
byname['query'] = aq
byname['assumeState'] = asum
order = ['health','loadSpec','assumeTransition','nextStep','checkInvariant','query','assumeState','rollback','disposeSpec']
open('.erpc.finalarms.lean','w').write(NL + NL.join(byname[n] for n in order) + NL)
print('stage b ok', len(byname))
