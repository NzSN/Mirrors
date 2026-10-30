import copy
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import controlled_model as model

ROOT = Path(__file__).resolve().parents[3]
NATIVE = ROOT / 'test/fixtures/deterministic-scheduling/controlled-sync/native-complete.json'


class ControlledModelTests(unittest.TestCase):
    def witness(self):
        receipt = json.loads(NATIVE.read_text())
        grants, results = receipt['events'][::2], receipt['events'][1::2]
        return {'schema': 'mirrors.controlled-sync-witness/v1', 'modelComparison': False,
                'cost': [2, 0, 4, 14],
                'executionId': receipt['executionId'], 'actors': [event['actor'] for event in grants],
                'operations': [event['operation'] for event in grants],
                'resources': [event['resource'] for event in grants],
                'values': [event['value'] for event in results], 'enabled': [event['enabled'] for event in grants],
                'counts': [row['state']['count'] for row in receipt['observations']],
                'received': [row['state']['received'] for row in receipt['observations']]}

    def remote(self):
        now = datetime.now(timezone.utc)
        config = {'schema': 'mirrors.controlled-model-remote/v1', 'host': '127.0.0.1', 'port': 19129,
                  'pin': '1'*64, 'cert': '/private/client.crt', 'key': '/private/client.key', 'ca': '/private/ca.crt',
                  'observation': '/private/observation.json', 'serverExecutableSha256': '2'*64,
                  'sourceCommit': '3'*40, 'apalacheJarSha256': '4'*64, 'javaExecutableSha256': '5'*64,
                  'javaVersion': '25.0.4+7-LTS'}
        observed = {name: config[name] for name in ['host', 'port', 'serverExecutableSha256', 'sourceCommit',
                    'apalacheJarSha256', 'javaExecutableSha256', 'javaVersion']}
        observed.update(schema='mirrors.controlled-model-observation/v1', serverCertificateSha256='1'*64,
                        processId=123, observedAtUtc=now.isoformat(),
                        certificateNotAfterUtc=(now+timedelta(days=1)).isoformat())
        return config, observed, now

    def test_witness_is_the_actual_observation_and_never_an_expected_state(self):
        witness = self.witness()
        original = model.witness_module(witness)
        self.assertIn('EXTENDS ControlledMutexFifo', original)
        witness['counts'][-1] = 3
        changed = model.witness_module(witness)
        self.assertNotEqual(original, changed)
        self.assertIn(',3>>', changed)
        self.assertFalse(witness['modelComparison'])

    def test_witness_refuses_missing_frames_boolean_integers_and_preclaimed_comparison(self):
        base = self.witness()
        variants = []
        bad = copy.deepcopy(base); bad['counts'].pop(); variants.append(bad)
        bad = copy.deepcopy(base); bad['values'][0] = True; variants.append(bad)
        bad = copy.deepcopy(base); bad['enabled'][0] = ['consumer', 'consumer']; variants.append(bad)
        bad = copy.deepcopy(base); bad['modelComparison'] = True; variants.append(bad)
        bad = copy.deepcopy(base); bad['actors'][0] = 'injected\nMODULE'; variants.append(bad)
        for bad in variants:
            with self.assertRaises(ValueError): model.witness_module(bad)

    def test_selected_remote_requires_current_identity_and_certificate(self):
        config, observed, now = self.remote()
        self.assertEqual(model.admit_remote(config, observed, now), observed)
        for field in ['serverCertificateSha256', 'serverExecutableSha256', 'apalacheJarSha256', 'javaExecutableSha256']:
            bad = dict(observed); bad[field] = '0'*64
            with self.subTest(field=field), self.assertRaises(ValueError): model.admit_remote(config, bad, now)
        for name, value in [('observedAtUtc', (now-timedelta(seconds=301)).isoformat()),
                            ('observedAtUtc', (now+timedelta(seconds=1)).isoformat()),
                            ('certificateNotAfterUtc', (now-timedelta(seconds=1)).isoformat()),
                            ('processId', True), ('port', True)]:
            bad = dict(observed); bad[name] = value
            with self.subTest(field=name), self.assertRaises(ValueError): model.admit_remote(config, bad, now)

    def test_mapping_refuses_boolean_capacity_and_unknown_fields(self):
        value = {'schema': 'mirrors.controlled-model-mapping/v1', 'profile': model.PROFILE,
                 'modelSourceSha256': 'a'*64, 'implementationSha256': 'b'*64,
                 'actors': ['consumer', 'producer'], 'resources': [
                     {'id': 'mutex', 'kind': 'mutex', 'capacity': 0},
                     {'id': 'queue', 'kind': 'queue', 'capacity': 1}],
                 'observations': ['count', 'received'], 'maxDecisions': 32}
        model.mapping(value)
        bad = copy.deepcopy(value); bad['resources'][1]['capacity'] = True
        with self.assertRaises(ValueError): model.mapping(bad)

    def test_clock_tolerance_is_explicit_bounded_and_keeps_stale_refusals(self):
        config, observed, now = self.remote()
        future = dict(observed); future['observedAtUtc'] = (now+timedelta(seconds=4)).isoformat()
        with self.assertRaises(ValueError): model.admit_remote(config, future, now)
        config['clockSkewSeconds'] = 5
        model.admit_remote(config, future, now)
        future['observedAtUtc'] = (now+timedelta(seconds=6)).isoformat()
        with self.assertRaises(ValueError): model.admit_remote(config, future, now)
        stale = dict(observed); stale['observedAtUtc'] = (now-timedelta(seconds=301)).isoformat()
        with self.assertRaises(ValueError): model.admit_remote(config, stale, now)
        config['clockSkewSeconds'] = True
        with self.assertRaises(ValueError): model.admit_remote(config, observed, now)

    def test_in_place_executor_refuses_shell_syntax_and_unpinned_artifacts(self):
        value = {'kind':'ssh-windows','ssh':'/usr/bin/ssh','sshSha256':'a'*64,
                 'config':'/private/ssh-config','configSha256':'b'*64,'alias':'win10',
                 'script':'D:/Owned/controlled-validate.ps1','scriptSha256':'c'*64}
        model.ssh_execution(value)
        for name, replacement in [('alias','win10;echo injected'), ('script',"D:/Owned/a';echo injected"),
                                  ('sshSha256','not-a-digest'), ('kind','arbitrary-command')]:
            bad = dict(value); bad[name] = replacement
            with self.subTest(field=name), self.assertRaises(ValueError): model.ssh_execution(bad)
        bad = copy.deepcopy(value); bad['arbitraryMapping'] = True
        with self.assertRaises(ValueError): model.mapping(bad)


if __name__ == '__main__':
    unittest.main()
