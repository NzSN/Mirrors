NL = chr(10)
base = open('.erpc.base.lean').read()
mid = open('.erpc.mid.lean').read()
helpers = open('.erpc.helpers.lean').read()
req1 = open('.erpc.req1.lean').read()
req2 = open('.erpc.req2.lean').read()
req3 = open('.erpc.req3.lean').read()
req4 = open('.erpc.req4.lean').read()
rest = open('.erpc.rest.lean').read().rstrip()
if rest.endswith('c'):
    rest = rest[:-1]
parts = [base.rstrip(), mid.rstrip(), helpers.rstrip(), req1.rstrip(), req2.rstrip(), req3.rstrip(), req4.rstrip(), rest, 'end Codec']
out = NL + (NL+NL).join(parts) + NL
open('Codec/ExplorerRpc.lean','w').write(out)
print(len(out.splitlines()))
