import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from build import write_reference_project

class ReferenceProjectTests(unittest.TestCase):
    def prepare(self, root):
        apps=root/'applications';apps.mkdir();package=root/'packages/mirrorecma';package.mkdir(parents=True)
        (package/'package.json').write_text(json.dumps({'name':'mirrorecma','version':'2.0.0'}))
        for folder,name in [('work-queue','WorkQueue'),('lease-service','LeaseService')]:
            artifacts=apps/f'examples/{folder}/artifacts';artifacts.mkdir(parents=True)
            (artifacts/'witness.itf.json').write_bytes(folder.encode())
            module=apps/f'dist-validation/examples/{folder}/artifacts/bundle/{name}.suite.js';module.parent.mkdir(parents=True);module.write_bytes(name.encode())
        server=root/'ModelMirrors';server.write_bytes(b'server');compiler=root/'compiler';compiler.write_bytes(b'compiler')
        return apps,server,compiler,package
    def test_lease_project_pins_two_occurrences_and_selects_real_expired_token_adapter(self):
        with tempfile.TemporaryDirectory() as tmp:
            apps,server,compiler,package=self.prepare(Path(tmp));write_reference_project(apps,server,compiler,package,application='lease-service')
            p=apps/'lease-project';project=json.loads((p/'mirror.faulty.project.json').read_text());traces=project['replay']['traces']
            self.assertEqual(len(traces),2);self.assertEqual(traces[0],traces[1])
            self.assertEqual(traces[0]['sha256'],hashlib.sha256((p/traces[0]['path']).read_bytes()).hexdigest())
            self.assertEqual(project['model']['export'],'LeaseServiceModel')
            self.assertEqual(project['model']['moduleSha256'],hashlib.sha256((p/project['model']['module']).read_bytes()).hexdigest())
            self.assertEqual(project['suiteId'],'lease-service.reference-installed/v1')
            self.assertEqual(project['acceptance']['requiredActions'],['Acquire','Advance','Release','Renew','Write'])
            self.assertIn("createLeaseAdapter('expired-token')",(p/'reference-faulty-adapter.mjs').read_text())
            self.assertIn("createLeaseAdapter('correct')",(p/'reference-correct-adapter.mjs').read_text())
            self.assertEqual(project['frameworkAdmission'],'required')
    def test_workqueue_project_remains_separate_and_gate_lock_selects_all_packages(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);apps,server,compiler,package=self.prepare(root);gate=root/'gate.json';gate.write_text(json.dumps({'name':'mirrorgate-mirrorecma','version':'2.0.0'}))
            for app in ['work-queue','lease-service']:write_reference_project(apps,server,compiler,package,gate,app)
            q=json.loads((apps/'reference-project/mirror.faulty.project.json').read_text());self.assertEqual(q['suiteId'],'work-queue.reference-installed/v1');self.assertEqual(len(q['replay']['traces']),1)
            self.assertIn("createWorkQueueAdapter('enqueue-drops'",(apps/'reference-project/reference-faulty-adapter.mjs').read_text())
            for name in ['reference-project','lease-project']:
                lock=json.loads((apps/name/'mirror.toolchain.json').read_text());self.assertEqual(set(lock['packages']),{'mirrorecma','mirrorgate-mirrorecma'})
                self.assertEqual(lock['tools']['server']['sha256'],hashlib.sha256(server.read_bytes()).hexdigest())
    def test_unsupported_reference_application_fails_before_writing(self):
        with tempfile.TemporaryDirectory() as tmp:
            apps,server,compiler,package=self.prepare(Path(tmp))
            with self.assertRaisesRegex(ValueError,'unsupported reference project'):write_reference_project(apps,server,compiler,package,application='unknown')
            self.assertFalse((apps/'reference-project').exists());self.assertFalse((apps/'lease-project').exists())
