import re
NL = chr(10)
GT = chr(9654)  # actually need plain char; rebuild below
t = open('.erpc.arms2.lean').read()
# 1. none-arm: replace the by-block with trivial
pat = re.compile('by' + NL + r'[ ]+intro v hv; exact absurd hv (by simp), rfl' + re.escape('>') + re.escape('>'))
t2, n1 = pat.subn('trivial' + '>' + '>', t)
print('trivial replacements:', n1)
# 2. query some-arm: reorder obtain before refine
old_some_head = (
"      | some op =>" + NL +
"          obtain [hb1, hb2] := hok op (by simp)".replace('[','<').replace(']','>'))
old_head2 = ("      | some op =>" + NL +
"          obtain " + chr(9474) )
# simpler textual anchor: find '| some op =>' block start and the refine line
i = t2.index('| some op =>')
j = t2.index('refine', i)
# insert hav-order: currently hp..pt haves come after refine; we need po before obtain of enc lemma.
# Actual current structure (from qarm): obtain hb1 hb2 / obtain op2 hop2dec hval / refine / haves / common
# Replace the two obtain lines
old_obtains = ("          obtain " + chr(10216) + "hb1, hb2" + chr(10217) + " := hok op (by simp)" + NL +
"          obtain " + chr(10216) + "op2, hop2dec, hval" + chr(10217) + " := decodeValue_bounded op hb1")
assert old_obtains in t2, "obtains anchor missing"
t2 = t2.replace(old_obtains, "          obtain " + chr(10216) + "hb1, hb2" + chr(10217) + " := hok op (by simp)")
# replace refine line and the following have po line region: we move obtain after po have.
old_refine = "          refine " + chr(10216) + ".query id sessionId kinds (some op2) timeoutSec, ?_, rfl, rfl, rfl, hval, rfl" + chr(10217)
assert old_refine in t2, "refine anchor missing"
# insert obtain of enc-witness right BEFORE refine, and change refine to use w2/hw2.2
new_refine_pre = ("          obtain " + chr(10216) + "w2, hw2" + chr(10217) + " := decOptNullValue_enc hp po hb1 hb2" + NL +
"          refine " + chr(10216) + ".query id sessionId kinds (some w2) timeoutSec, ?_, rfl, rfl, rfl, hw2.2, rfl" + chr(10217))
t2 = t2.replace(old_refine, new_refine_pre)
# replace hop2 have: choose_spec version -> hw2.1
old_hop = t2[t2.index('have hop2'):t2.index('rw [strs_of_mkObj hp pk, hop2')]
new_hop = "have hop2 := hw2.1" + NL + "          "
t2 = t2.replace(old_hop, new_hop)
open('.erpc.arms2.lean','w').write(t2)
print('done')
