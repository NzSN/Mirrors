from __future__ import annotations
import sys, unittest
from pathlib import Path
from types import SimpleNamespace
TOOLS=Path(__file__).resolve().parents[1]; sys.path[:0]=[str(TOOLS),str(TOOLS/'adapters')]
import mirrors, apalache

class AdapterTruthTables(unittest.TestCase):
 def test_mirrors_classify_truth_table(self):
  base={'schema':'mirrors.tla-frontend-inspection/v1','command':'resolve','dependencies':[],'diagnostics':[],'levels':[],'module':'M','ok':True,'operators':[],'source':None,'sources':[],'variables':[]}
  self.assertEqual(mirrors.classify(base,0),'accepted')
  rejected={**base,'ok':False,'module':None,'diagnostics':[{'severity':'error'}]}
  self.assertEqual(mirrors.classify(rejected,1),'rejected')
  for bad in ({**base,'ok':False},{**rejected,'variables':[{'x':1}]},{**base,'extra':1}):
   with self.assertRaises(ValueError): mirrors.classify(bad, 1 if bad.get('ok') is False else 0)
 def test_apalache_classify_truth_table(self):
  done=lambda code,text: SimpleNamespace(status=SimpleNamespace(value='completed'),returncode=code,stdout=text.encode())
  ir={'name':'ApalacheIR','version':'1.0','modules':[{}]}
  self.assertEqual(apalache.classify(done(0,'PASS #0: SanyParser\nParsed successfully\nEXITCODE: OK'),ir),('completed','accepted'))
  self.assertEqual(apalache.classify(done(255,'PASS #0: SanyParser\nParser has failed\nParsing error:\nEXITCODE: ERROR (255)'),None),('completed','rejected'))
  self.assertEqual(apalache.classify(done(255,'anything'),None),('invalid_output','unknown'))
  for state in ('timeout','crash','unavailable'):
   self.assertEqual(apalache.classify(SimpleNamespace(status=SimpleNamespace(value=state),returncode=None,stdout=b''),None),(state,'unknown'))

if __name__=='__main__': unittest.main()
