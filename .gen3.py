head = open('.erpc.head.lean').read()
helpers = open('.erpc.helpers2.lean').read()
resp = open('.erpc.resp.lean').read()
NL = chr(10)
def J(*parts): return NL.join(parts)

def lit_of(pfields):
    return NL.join('        ("%s", %s),' % (k, e) for k, e, lk, h in pfields).rstrip(',')

def envlit_of(mth, lit):
    return '[("id", Json.num id), ("jsonrpc", Json.str "2.0"),' + NL + '          ("method", Json.str "%s"), ("params", %s)]' % (mth, lit)

def common_tail(mth, pterm, lit):
    el = envlit_of(mth, pterm)
    return [
      '      have hkeys : ((%s :' % el,
      '          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp',
      '      have mm : ("method", Json.str "%s") ∈ (%s :' % (mth, el),
      '          List (String × Json)) := by simp',
      '      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ (%s :' % el,
      '          List (String × Json)) := by simp',
      '      have mp : ("params", %s) ∈ (%s :' % (pterm, el),
      '          List (String × Json)) := by simp',
      '      simp only [encodeRpcRequest, encodeParams, reqId, methodName]',
      '      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]',
      '      show decodeParams "%s" (%s) >>= fun r_ => Except.ok (setReqId id r_) = _' % (mth, pterm),
      '      simp only [decodeParams]']

LEM = {'str': 'str_of_mkObj hp %s', 'num': 'nat_of_mkObj hp %s', 'bool': 'jBool_mkObj hp %s',
       'optNat': 'jOptNat_mkObj hp %s', 'strs': 'strs_of_mkObj hp %s'}

def gen_arm(mth, ctor, ctorargs, witness, pfields, pre_rws=(), post=''):
    lit = lit_of(pfields)
    pterm = 'Json.mkObj [' + lit + ']'
    pl = '[' + lit + ']'
    lines = ['  | %s %s =>' % (ctor, ' '.join(ctorargs)),
             '      refine ⟨.%s %s, ?_, rfl⟩' % (ctor, witness),
             '      have hp : ((%s : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp' % pl]
    for k, e, lk, h in pfields:
        lines += ['      have %s : ("%s", %s) ∈ (%s :' % (h, k, e, pl),
                  '          List (String × Json)) := by simp']
    lines += common_tail(mth, pterm, lit)
    rl = [LEM[lk] % h for k, e, lk, h in pfields]
    lines.append('      rw [%s]' % ', '.join(rl))
    lines.append('      rfl')
    return NL.join(lines)

EX = 'Json.arr (strsJson exports |>.toArray)'
IN = 'Json.arr (strsJson invariants |>.toArray)'
SO = 'Json.arr (strsJson sources |>.toArray)'
KS = 'Json.arr (strsJson kinds |>.toArray)'

arms = []
arms.append(J(
'  | health id =>',
'      refine ⟨.health id, ?_, rfl⟩',
'      have hkeys : (([("id", Json.num id), ("jsonrpc", Json.str "2.0"),',
'          ("method", Json.str "health"), ("params", Json.arr #[])] :',
'          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp',
'      have mm : ("method", Json.str "health") ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),',
'          ("method", Json.str "health"), ("params", Json.arr #[])] : List (String × Json)) := by simp',
'      have mi : ("id", Json.num (JsonNumber.fromNat id)) ∈ ([("id", Json.num id),',
'          ("jsonrpc", Json.str "2.0"), ("method", Json.str "health"),',
'          ("params", Json.arr #[])] : List (String × Json)) := by simp',
'      have mp : ("params", Json.arr #[]) ∈ ([("id", Json.num id), ("jsonrpc", Json.str "2.0"),',
'          ("method", Json.str "health"), ("params", Json.arr #[])] :',
'          List (String × Json)) := by simp',
'      simp only [encodeRpcRequest, encodeParams, reqId, methodName]',
'      rw [str_of_mkObj hkeys mm, nat_of_mkObj hkeys mi, jField_of_mkObj hkeys mp]',
'      show decodeParams "health" (Json.arr #[]) >>= fun r_ => Except.ok (setReqId id r_) = _',
'      simp only [decodeParams]',
'      rfl'))

arms.append(gen_arm('loadSpec', 'loadSpec', ['id', 'sources', 'exports', 'invariants', 'init', 'next'],
  'id sources exports invariants init next',
  [('exports', EX, 'strs', 'pe'), ('init', 'Json.str init', 'str', 'pi'),
   ('invariants', IN, 'strs', 'pv'), ('next', 'Json.str next', 'str', 'pn'),
   ('sources', SO, 'strs', 'ps')]))

arms.append(gen_arm('assumeTransition', 'assumeTransition',
  ['id', 'sessionId', 'transitionId', 'checkEnabled', 'timeoutSec'],
  'id sessionId transitionId checkEnabled timeoutSec',
  [('checkEnabled', 'Json.bool checkEnabled', 'bool', 'pc'),
   ('sessionId', 'Json.str sessionId', 'str', 'ps'),
   ('timeoutSec', 'optNat timeoutSec', 'optNat', 'pt'),
   ('transitionId', 'Json.num transitionId', 'num', 'pr')]))

arms.append(gen_arm('nextStep', 'nextStep', ['id', 'sessionId'], 'id sessionId',
  [('sessionId', 'Json.str sessionId', 'str', 'ps')]))

arms.append(gen_arm('checkInvariant', 'checkInvariant',
  ['id', 'sessionId', 'invariantId', 'kind', 'timeoutSec'],
  'id sessionId invariantId kind timeoutSec',
  [('invariantId', 'Json.num invariantId', 'num', 'pv'),
   ('kind', 'Json.str kind', 'str', 'pk'),
   ('sessionId', 'Json.str sessionId', 'str', 'ps'),
   ('timeoutSec', 'optNat timeoutSec', 'optNat', 'pt')]))

arms.append(gen_arm('rollback', 'rollback', ['id', 'sessionId', 'snapshotId'],
  'id sessionId snapshotId',
  [('sessionId', 'Json.str sessionId', 'str', 'ps'),
   ('snapshotId', 'Json.num snapshotId', 'num', 'pn')]))

arms.append(gen_arm('disposeSpec', 'disposeSpec', ['id', 'sessionId'], 'id sessionId',
  [('sessionId', 'Json.str sessionId', 'str', 'ps')]))

open('.erpc.arms.lean', 'w').write(NL.join(arms) + NL)
print('arms ok', sum(len(a.splitlines()) for a in arms))
