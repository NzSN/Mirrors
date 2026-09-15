"""DV1 reference-adapter calibration; live SANY uses only pinned local artifacts."""
from __future__ import annotations
import json, os, shutil, subprocess, sys, tempfile, unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1]; sys.path[:0]=[str(TOOLS),str(TOOLS/'adapters')]
import corpus, capture, sany, process
REPO=TOOLS.parents[1]; JAR=REPO/'.golden-build/tla-differential/toolchain/downloads/tla2tools-1.8.0.jar'; CLASSES=REPO/'.golden-build/tla-differential/bridge-classes'
# The transport supplies every child process with `deterministic_environment`,
# which does not inherit this interpreter's PATH, so the DV1 Java runtime has to
# be resolved here and passed explicitly like `run.py` and `acquire.py` do.
JAVA=shutil.which('java') or 'java'

class References(unittest.TestCase):
 def live(self):
  if os.environ.get('DV_LIVE_REFERENCES') != '1': self.skipTest('set DV_LIVE_REFERENCES=1 for pinned live references')
 def test_live_pinned_sany_named_unnamed_implicit_and_level(self):
  self.live()
  if not (JAR.is_file() and CLASSES.is_dir()): self.skipTest('pinned SANY bridge unavailable')
  c=corpus.load_corpus(REPO)
  for ident in ('rej-instance-definition-only','rej-instance-unnamed','rej-instance-implicit-substitution','rej-substitution-constant-by-state'):
   f=next(x for x in c.fixtures if x.id==ident)
   with tempfile.TemporaryDirectory() as d:
    p=Path(d); m=capture.materialize_fixture(fixture=f,directory=p/'in'); (m.input_dir/'art').mkdir()
    o=sany.observe(fixture=capture.adapter_fixture(f),materialized=m,config={'java':JAVA,'sany_jar':JAR,'bridge_classes':CLASSES,'version':'1.8.0'},limits=process.ProcessLimits(),artifact_dir=m.input_dir/'art')
    self.assertEqual((o['execution'],o['outcome']),('completed','accepted'),ident)
    self.assertEqual(o['facts']['substitution']['capability'],'supported')
  # Explicit substitutions retain actual identity; unnamed sites retain null name.
  f=next(x for x in c.fixtures if x.id=='rej-instance-unnamed')
  with tempfile.TemporaryDirectory() as d:
   p=Path(d); m=capture.materialize_fixture(fixture=f,directory=p/'in'); (m.input_dir/'art').mkdir(); o=sany.observe(fixture=capture.adapter_fixture(f),materialized=m,config={'java':JAVA,'sany_jar':JAR,'bridge_classes':CLASSES},limits=process.ProcessLimits(),artifact_dir=m.input_dir/'art')
   rows=o['facts']['substitution']['value']; self.assertTrue(any(row['name'] is None for row in rows))
 def test_live_sany_syntax_name_and_level_rejections(self):
  self.live()
  if not (JAR.is_file() and CLASSES.is_dir()): self.skipTest('pinned SANY bridge unavailable')
  c=corpus.load_corpus(REPO)
  for ident in ('rej-open-comment','rej-arity-mismatch'):
   f=next(x for x in c.fixtures if x.id==ident)
   with tempfile.TemporaryDirectory() as d:
    p=Path(d); m=capture.materialize_fixture(fixture=f,directory=p/'in'); (m.input_dir/'art').mkdir(); o=sany.observe(fixture=capture.adapter_fixture(f),materialized=m,config={'java':JAVA,'sany_jar':JAR,'bridge_classes':CLASSES},limits=process.ProcessLimits(),artifact_dir=m.input_dir/'art'); self.assertEqual(o['outcome'],'rejected')
 def test_live_chained_and_two_named_instances_are_distinct(self):
  self.live()
  if not (JAR.is_file() and CLASSES.is_dir()): self.fail('DV_LIVE_REFERENCES=1 requires pinned SANY bridge')
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)
   (p/'Child.tla').write_text('---- MODULE Child ----\nCONSTANT c\nOp == c\n====\n')
   (p/'Root.tla').write_text('---- MODULE Root ----\nCONSTANT a, b\nI == INSTANCE Child WITH c <- a\nJ == INSTANCE Child WITH c <- b\nR == <<I!Op,J!Op>>\n====\n')
   run=subprocess.run([JAVA,'-cp',f'{CLASSES}:{JAR}','SanyBridge','Root.tla'],cwd=p,text=True,capture_output=True)
   value=json.loads(run.stdout); self.assertTrue(value['ok'],run.stderr); rows=next(x for x in value['modules'] if x['name']=='Root')['instances']; self.assertEqual({x['name'] for x in rows},{'I','J'}); self.assertEqual({x['substitutions'][0]['actual']['value'] for x in rows},{'a','b'})
 def test_live_chained_and_local_instance_visibility(self):
  self.live()
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)
   (p/'Child.tla').write_text('---- MODULE Child ----\nCONSTANT c\nOp == c\n====\n')
   (p/'Middle.tla').write_text('---- MODULE Middle ----\nCONSTANT m\nI == INSTANCE Child WITH c <- m\nOp == I!Op\n====\n')
   (p/'Root.tla').write_text('---- MODULE Root ----\nCONSTANT a\nJ == INSTANCE Middle WITH m <- a\nR == J!Op\n====\n')
   run=subprocess.run([JAVA,'-cp',f'{CLASSES}:{JAR}','SanyBridge','Root.tla'],cwd=p,text=True,capture_output=True); value=json.loads(run.stdout); self.assertTrue(value['ok'],run.stderr)
   self.assertEqual(next(x for x in value['modules'] if x['name']=='Root')['instances'][0]['name'],'J')
   self.assertEqual(next(x for x in value['modules'] if x['name']=='Middle')['instances'][0]['name'],'I')
   (p/'Middle.tla').write_text('---- MODULE Middle ----\nCONSTANT m\nLOCAL I == INSTANCE Child WITH c <- m\nOp == I!Op\n====\n')
   run=subprocess.run([JAVA,'-cp',f'{CLASSES}:{JAR}','SanyBridge','Root.tla'],cwd=p,text=True,capture_output=True); local=json.loads(run.stdout)
   self.assertTrue(local['ok'],run.stderr)
   middle=next(x for x in local['modules'] if x['name']=='Middle')['instances'][0]
   self.assertTrue(middle['local'])
 def test_invalid_json_is_never_success(self):
  # A nonexistent Java executable is classified unavailable/unknown by the real transport.
  c=corpus.load_corpus(REPO); f=c.fixtures[0]
  with tempfile.TemporaryDirectory() as d:
   p=Path(d); m=capture.materialize_fixture(fixture=f,directory=p/'in'); (m.input_dir/'art').mkdir(); o=sany.observe(fixture=capture.adapter_fixture(f),materialized=m,config={'sany_jar':'/missing.jar','bridge_classes':'/missing','java':'/missing/java'},limits=process.ProcessLimits(),artifact_dir=m.input_dir/'art'); self.assertEqual((o['execution'],o['outcome']),('unavailable','unknown'))

if __name__=='__main__': unittest.main()
