NL = chr(10)
def J(*p): return NL.join(p)
H = {'str': 'mK', 'num': 'mN'}
LEM = {'str': 'str_of_mkObj hp mK', 'num': 'nat_of_mkObj hp mN'}
def scalar_arm(ctor, ctorargs, witness, fields):
    lit = NL.join('        ("%s", %s),' % (k, e) for k, e, lk in fields).rstrip(',')
    pl = '[' + lit + ']'
    L = ['  | %s %s =>' % (ctor, ' '.join(ctorargs)),
         '      refine ⟨.%s %s, ?_, rfl⟩' % (ctor, witness),
         '      have hp : ((%s : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp' % pl]
    for i, (k, e, lk) in enumerate(fields):
        hname = 'm%d' % i
        lem = 'str_of_mkObj hp %s' % hname if lk == 'str' else 'nat_of_mkObj hp %s' % hname
        L += ['      have %s : ("%s", %s) ∈ (%s :' % (hname, k, e, pl),
              '          List (String × Json)) := by simp']
    rws = []
    for i, (k, e, lk) in enumerate(fields):
        rws.append(('str_of_mkObj hp m%d' % i) if lk == 'str' else ('nat_of_mkObj hp m%d' % i))
    L += ['      simp only [encodeRpcResult, decodeRpcResult, resultMethod, reqStr, reqNat]',
          '      rw [%s]' % ', '.join(rws), '      rfl']
    return NL.join(L)
arms = []
arms.append(scalar_arm('health', ['status'], 'status', [('status', 'Json.str status', 'str')]))
arms.append(scalar_arm('assumeTransition', ['sessionId','snapshotId','status','transitionId'],
  'sessionId snapshotId status transitionId',
  [('sessionId','Json.str sessionId','str'),('snapshotId','Json.num snapshotId','num'),
   ('status','Json.str status','str'),('transitionId','Json.num transitionId','num')]))
arms.append(scalar_arm('nextStep', ['newStepNo','sessionId','snapshotId'], 'newStepNo sessionId snapshotId',
  [('newStepNo','Json.num newStepNo','num'),('sessionId','Json.str sessionId','str'),
   ('snapshotId','Json.num snapshotId','num')]))
arms.append(scalar_arm('assumeState', ['sessionId','snapshotId','status'], 'sessionId snapshotId status',
  [('sessionId','Json.str sessionId','str'),('snapshotId','Json.num snapshotId','num'),
   ('status','Json.str status','str')]))
arms.append(J('  | rollback => exact ⟨.rollback, by',
'    simp only [encodeRpcResult, decodeRpcResult, resultMethod], rfl⟩',
'  | disposeSpec => exact ⟨.disposeSpec, by',
'    simp only [encodeRpcResult, decodeRpcResult, resultMethod], rfl⟩'))
open('.erpc.resparm1.lean','w').write(NL.join(arms) + NL)
print('ok')