NL = chr(10)
hdr = open('.erpc.resp2.lean').read()
hdr = hdr[:hdr.index('def RpcResultOk')].rstrip()
parts = [hdr, open('.erpc.respdefs.lean').read().rstrip(),
  open('.erpc.resparm1.lean').read().rstrip(),
  open('.erpc.resparm2.lean').read().rstrip(),
  open('.erpc.resparm3.lean').read().rstrip(),
  open('.erpc.resparm4.lean').read().rstrip(),
  open('.erpc.resparm5.lean').read().rstrip(),
  'end Codec']
out = NL + NL.join(parts) + NL
open('.erpc.resp3.lean','w').write(out)
print('resp3', len(out.splitlines()))
