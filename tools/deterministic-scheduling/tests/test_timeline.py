import copy,hashlib,importlib.util,json,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('timeline',ROOT/'tools/deterministic-scheduling/timeline.py');t=importlib.util.module_from_spec(spec);spec.loader.exec_module(t)
BASE=ROOT/'test/fixtures/deterministic-scheduling/timeline'

def receipt(language='ecma',case='serial-mutate'):
    return (BASE/f'{language}/counter/{case}/receipt.json').read_bytes()

def encode(value):return json.dumps(value).encode()

class TimelineTests(unittest.TestCase):
    def test_actual_cross_language_mismatch_is_not_cleanup_cancellation(self):
        for language in ['ecma','rust']:
            raw=receipt(language);v=t.build_timeline(raw)
            self.assertEqual(v['comparison'],'step_mismatch');self.assertFalse(v['passed']);self.assertEqual(v['executions'][0]['outcome'],'cancelled');self.assertEqual(v['executions'][0]['cleanup'],'confirmed')
            self.assertEqual(v['mismatch']['location']['afterSteps'],2)
            self.assertEqual(v['executions'][0]['rows'][2]['comparison'],'step_mismatch')
            if language=='rust':self.assertIsNone(v['executions'][0]['rows'][2]['modelAction'])
            self.assertIn('Model mismatch',t.render_text(v))
    def test_actual_matched_receipt(self):
        v=t.build_timeline(receipt(case='serial-ok'));self.assertTrue(v['passed']);self.assertTrue(all(r['comparison']=='matched_by_terminal' for r in v['executions'][0]['rows']))
    def test_actual_cleanup_failure_remains_independent(self):
        for language in ['ecma','rust']:
            v=t.build_timeline(receipt(language,'serial-mutate-and-teardown-fail'))
            self.assertEqual(v['comparison'],'step_mismatch');self.assertEqual(v['executions'][0]['cleanup'],'teardown_failed');self.assertFalse(v['passed'])
    def test_actual_repeated_initialization_sections(self):
        v=t.build_timeline(receipt(case='serial-repeat'));self.assertEqual(len(v['executions']),2);self.assertNotEqual(v['executions'][0]['executionId'],v['executions'][1]['executionId'])
    def test_bare_local_success_never_becomes_model_conformance(self):
        d=json.loads(receipt(case='serial-ok'))['binding']['executions'][0];v=t.build_timeline(encode(d));self.assertTrue(v['sourcePassed']);self.assertFalse(v['passed']);self.assertEqual(v['comparison'],'unknown')
    def test_hash_bound_tamper_refusal(self):
        raw=receipt();digest=hashlib.sha256(raw).hexdigest();self.assertEqual(t.build_timeline(raw,digest)['sourceSha256'],digest)
        with self.assertRaises(t.TimelineError):t.build_timeline(raw+b' ',digest)
    def test_duplicate_and_nonfinite_input_refuse(self):
        for raw in [b'{"schema":"x","schema":"x"}',b'{"value":NaN}',b'[]']:
            with self.assertRaises(t.TimelineError):t.build_timeline(raw)
    def test_wrong_order_actor_and_unconfirmed_observation_refuse(self):
        for modify in [lambda e:e['events'][0].update(ordinal=1),lambda e:e['events'][1].update(actor='b'),lambda e:e['observations'][-1].update(afterSteps=3)]:
            d=json.loads(receipt());modify(d['binding']['executions'][0])
            with self.assertRaises(t.TimelineError):t.build_timeline(encode(d))
    def test_unconfirmed_comparison_and_contradictory_pass_refuse(self):
        for modify in [lambda d:d.update(peerTerminal=''),lambda d:d.update(passed=True)]:
            d=json.loads(receipt());modify(d)
            with self.assertRaises(t.TimelineError):t.build_timeline(encode(d))
    def test_truncated_evidence_is_visible_and_not_passing(self):
        d=json.loads(receipt());d['binding']['receiptComplete']=False;d['binding']['executions'].append({'passed':False,'evidenceError':'receipt_byte_bound_exceeded'})
        v=t.build_timeline(encode(d));self.assertFalse(v['receiptComplete']);self.assertFalse(v['passed']);self.assertIn('Evidence incomplete',t.render_text(v))
    def test_ambiguous_actual_does_not_invent_failure_index(self):
        d=json.loads(receipt('rust'));ex=d['binding']['executions'][0];ex['observations'][0]['state']=copy.deepcopy(ex['observations'][-1]['state'])
        v=t.build_timeline(encode(d));self.assertIsNone(v['mismatch']['location'])
    def test_explicit_hash_bound_kit_annotation_and_identity_refusal(self):
        d=json.loads(receipt());identity=d['binding']['executions'][0]['schedule']['identity']
        metadata={'schema':'mirrors.dpm-kit-metadata/v1','modelSemanticDigest':identity['modelSemanticDigest'],'mappingSha256':identity['mappingSha256'],'schedulingProfile':d['binding']['executions'][0]['schedule']['profile'],'relations':[{'actionId':'Read','wireAction':'read','checkpoint':'read'},{'actionId':'Write','wireAction':'write','checkpoint':'write'}]}
        raw=encode(metadata);sha=hashlib.sha256(raw).hexdigest();v=t.build_timeline(encode(d),kit_metadata=raw,kit_sha256=sha)
        self.assertEqual(v['executions'][0]['rows'][1]['modelAction'],'read')
        with self.assertRaises(t.TimelineError):t.build_timeline(encode(d),kit_metadata=raw)
        metadata['mappingSha256']='f'*64;bad=encode(metadata)
        with self.assertRaises(t.TimelineError):t.build_timeline(encode(d),kit_metadata=bad,kit_sha256=hashlib.sha256(bad).hexdigest())
    def test_actual_native_and_cpp_receipts(self):
        paths=list((BASE/'ecma/native').glob('*/receipt.json'))+list((BASE/'cpp/counter').glob('*.receipt.json'))
        count=0
        for p in paths:
            raw=p.read_bytes();schema=json.loads(raw).get('schema')
            if schema not in ['mirrors.scheduled-comparison/v1','mirrors.scheduled-binding/v1','mirrors.checkpoint-replay/v1','mirrors.checkpoint-execution/v1']:continue
            v=t.build_timeline(raw);self.assertEqual(v['sourceSha256'],hashlib.sha256(raw).hexdigest());count+=1
        self.assertGreaterEqual(count,12)
    def test_passing_leaks_and_reused_execution_identity_refuse(self):
        d=json.loads(receipt(case='serial-ok'));d['binding']['executions'][0]['remainingActors']=['a']
        with self.assertRaises(t.TimelineError):t.build_timeline(encode(d))
        d=json.loads(receipt(case='serial-repeat'));d['binding']['executions'][1]['executionId']=d['binding']['executions'][0]['executionId']
        with self.assertRaises(t.TimelineError):t.build_timeline(encode(d))
    def test_cli_read_only_and_no_output_clobber(self):
        with tempfile.TemporaryDirectory() as work:
            root=Path(work);source=root/'receipt.json';source.write_bytes(receipt());out=root/'timeline.json'
            command=['python3',str(ROOT/'tools/deterministic-scheduling/timeline.py'),'--receipt',str(source),'--format','json','--out',str(out)]
            run=subprocess.run(command,capture_output=True);self.assertEqual(run.returncode,0,run.stderr);self.assertEqual(source.read_bytes(),receipt());self.assertEqual(json.loads(out.read_text())['comparison'],'step_mismatch')
            old=out.read_bytes();self.assertEqual(subprocess.run(command,capture_output=True).returncode,2);self.assertEqual(out.read_bytes(),old)
            same=command[:-1]+[str(source)];self.assertEqual(subprocess.run(same,capture_output=True).returncode,2);self.assertEqual(source.read_bytes(),receipt())

if __name__=='__main__':unittest.main()
