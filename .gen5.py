import re
# patch gen4.py: trivial for optValEq none none
g = open('.gen4.py').read()
g = g.replace("intro v hv; exact absurd hv (by simp), rfl)", "trivial, rfl)")
g = g.replace("intro v hv; exact absurd hv (by simp), rfl)", "trivial, rfl)")
open('.gen4.py','w').write(g)
print('gen4 patched')
