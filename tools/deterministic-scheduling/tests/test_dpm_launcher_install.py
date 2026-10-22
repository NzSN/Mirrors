"""Exercise the built launcher through real installation and relocation.

The admitted runner is deliberately inert: doctor must not acquire it. These
checks reuse a retained oracle and receipt; they do not qualify SDK replay,
source-hidden execution, or fresh model checking.
"""
import hashlib
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
TOOLS = ROOT / 'tools/deterministic-scheduling'
LAUNCHER = ROOT / '.lake/build/bin/mirrors_dpm'
HELPERS = ('cli.py', 'dpm_host.py', 'timeline.py')


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n')


@unittest.skipUnless(sys.platform == 'linux', 'installed launcher checks require Linux renameat2 and shell')
class InstalledLauncherTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(LAUNCHER.is_file(), 'build mirrors_dpm before this suite')
        temporary = tempfile.TemporaryDirectory(prefix='mirrors-dpm-launcher-')
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.outside = self.work / 'outside'
        self.outside.mkdir()
        self.runner_marker = self.work / 'runner-executed'
        self.tamper_marker = self.work / 'untrusted-helper-executed'
        self.source = self.work / 'prepared'
        self.package = self.source / 'cpp'
        self.prepare_package()

    def run_command(self, command):
        return subprocess.run([str(item) for item in command], cwd=self.outside,
                              capture_output=True, text=True, timeout=30)

    def installer(self, *args):
        return self.run_command([sys.executable, '-I', '-S', '-B',
                                 TOOLS / 'install_cli.py', *args])

    def assert_succeeded(self, process):
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)

    def prepare_package(self):
        package = self.package
        (package / 'bin').mkdir(parents=True)
        (package / 'share/mirrors-dpm').mkdir(parents=True)
        shutil.copy2(LAUNCHER, package / 'bin/mirrors-dpm')
        for name in HELPERS:
            shutil.copy2(TOOLS / name, package / 'share/mirrors-dpm' / name)

        # Any accidental acquisition is observable even if its exit is ignored.
        runner = package / 'runner'
        runner.write_text('#!/bin/sh\nprintf executed > ' +
                          shlex.quote(str(self.runner_marker)) + '\nexit 97\n')
        runner.chmod(0o755)
        captured = package / 'oracle'
        shutil.copytree(ROOT / 'Plans/dpm-languages-evidence-20261005/oracles/counter/serial',
                        captured)
        request = json.loads((captured / 'request.json').read_text())
        (package / 'model.tla').write_text(request['spec']['sources'][0])
        correspondence = {
            'schema': 'mirrors.dpm-trace-correspondence/v1',
            'actionPath': ['action_taken'], 'actorPath': ['parameters', 'actor'],
            'actionMap': {'read': 'read', 'write': 'write', 'finish': '$done'},
            'initialBindings': [{'inputPath': ['initial'], 'statePath': ['count']}],
            'ignoredActors': [],
        }
        write_json(package / 'correspondence.json', correspondence)

        def ref(path):
            return {'path': str(path.relative_to(package)), 'sha256': sha(path)}

        trace_path = captured / 'trace-0.itf.json'
        trace = json.loads(trace_path.read_text())
        provenance = {
            'schema': 'mirrors.dpm-oracle-binding/v1',
            'capture': ref(captured / 'capture.json'), 'model': ref(package / 'model.tla'),
            'oracleSha256': sha(trace_path),
            'correspondence': ref(package / 'correspondence.json'),
        }
        write_json(captured / 'binding.json', provenance)
        lock = ROOT / 'test/fixtures/deterministic-scheduling/ScheduledCounter.lock.json'
        identity = {
            'modelSemanticDigest': json.loads(lock.read_text())['semanticDigest'],
            'mappingSha256': sha(package / 'correspondence.json'),
            'implementationSha256': sha(runner),
        }
        profile = 'mirrorcpp.cooperative-checkpoints/v1'
        schedule = {
            'schema': 'mirrors.checkpoint-schedule/v1', 'profile': profile,
            'identity': identity,
            'inputs': {'initial': int(trace['states'][0]['count']['#bigint'])},
            'steps': [{'actor': state['parameters']['actor'],
                       'checkpoint': correspondence['actionMap'][state['action_taken']]}
                      for state in trace['states'][1:]],
        }
        shutil.copy2(ROOT / 'test/fixtures/deterministic-scheduling/timeline/cpp/counter/mutate.receipt.json',
                     package / 'retained.receipt.json')
        project = {
            'schema': 'mirrors.dpm-project/v2', 'profile': profile, 'identity': identity,
            'explorerIdentity': None,
            'command': {'kind': 'native', 'executable': 'runner', 'args': []},
            'artifacts': [ref(path) for path in sorted(package.rglob('*')) if path.is_file()],
            'chains': [{'actor': actor, 'checkpoints': ['read', 'write', '$done']}
                       for actor in ('a', 'b')],
            'baseline': 'serial',
            'candidates': [{'id': 'serial', 'inputRank': 0, 'schedule': schedule,
                            'oracle': ref(trace_path), 'provenance': ref(captured / 'binding.json')}],
            'signature': 'exact-terminal/v1',
            'limits': {'attempts': 8, 'timeoutMs': 1000, 'totalTimeoutMs': 5000,
                       'outputBytes': 10000, 'totalOutputBytes': 1048576},
        }
        write_json(package / 'project.json', project)

    def install(self, source, destination):
        manifest = self.work / (destination.name + '-manifest.json')
        result = self.installer('manifest', '--source', source, '--out', manifest)
        self.assert_succeeded(result)
        self.assertEqual(result.stdout.strip(), sha(manifest))
        return self.installer('install', '--source', source, '--manifest', manifest,
                              '--manifest-sha256', sha(manifest), '--dest', destination)

    def tamper(self, package, name):
        helper = package / 'share/mirrors-dpm' / name
        helper.write_text('with open(' + repr(str(self.tamper_marker)) +
                          ', "w") as output:\n    output.write("executed")\n'
                          'raise SystemExit("untrusted helper executed")\n')
        return helper

    def assert_helper_refused(self, process, name):
        self.assertEqual(process.returncode, 2, process.stdout + process.stderr)
        self.assertIn('DPM host artifact differs: ' + name, process.stderr)
        self.assertFalse(self.tamper_marker.exists(), 'untrusted helper ran')
        self.assertFalse(self.runner_marker.exists(), 'doctor acquired the runner')

    def test_install_relocate_doctor_and_retained_report(self):
        destination = self.work / 'installed'
        result = self.install(self.source, destination)
        self.assert_succeeded(result)
        self.assertEqual(json.loads(result.stdout)['status'], 'installed')
        self.assertFalse(self.runner_marker.exists(), 'staged doctor acquired the runner')
        relocated = self.work / 'relocated'
        destination.rename(relocated)
        package = relocated / 'cpp'
        binary = package / 'bin/mirrors-dpm'
        before = {str(path.relative_to(package)): sha(path)
                  for path in package.rglob('*') if path.is_file()}
        help_result = self.run_command([binary, '--help'])
        self.assert_succeeded(help_result)
        self.assertIn('doctor', help_result.stdout)
        project = package / 'project.json'
        doctor = self.run_command([binary, 'doctor', '--project', project,
                                   '--project-sha256', sha(project)])
        self.assert_succeeded(doctor)
        self.assertEqual(json.loads(doctor.stdout), {
            'schema': 'mirrors.dpm-doctor/v1', 'status': 'accepted',
            'profile': 'mirrorcpp.cooperative-checkpoints/v1', 'candidateCount': 1,
            'projectSha256': sha(project), 'scope': 'admitted-catalog-only',
        })
        self.assertFalse(self.runner_marker.exists(), 'relocated doctor acquired the runner')
        receipt = package / 'retained.receipt.json'
        report_args = [binary, 'report', '--receipt', receipt, '--format', 'json',
                       '--expected-sha256']
        report = self.run_command([*report_args, sha(receipt)])
        self.assert_succeeded(report)
        timeline = json.loads(report.stdout)
        self.assertEqual(timeline['schema'], 'mirrors.dpm-timeline/v1')
        self.assertEqual(timeline['sourceSha256'], sha(receipt))
        self.assertEqual(timeline['comparison'], 'step_mismatch')
        self.assertFalse(timeline['passed'])
        self.assertEqual(timeline['executions'][0]['cleanup'], 'confirmed')
        self.assertIn('no fresh replay or model qualification', timeline['scope'])
        refused = self.run_command([*report_args, '0' * 64])
        self.assertEqual(refused.returncode, 2, refused.stderr)
        self.assertIn('receipt digest differs', refused.stderr)
        self.assertEqual(refused.stdout, '')
        after = {str(path.relative_to(package)): sha(path)
                 for path in package.rglob('*') if path.is_file()}
        self.assertEqual(after, before, 'read-only commands changed the installed tree')

    def test_staged_doctor_refuses_helper_tamper_before_activation(self):
        for name in HELPERS:
            with self.subTest(helper=name):
                source = self.work / ('tampered-' + name)
                shutil.copytree(self.source, source)
                package = source / 'cpp'
                helper = self.tamper(package, name)
                # Both project and fresh installation manifest admit the changed
                # bytes. Only the compiled launcher's independent pin rejects them.
                project_path = package / 'project.json'
                project = json.loads(project_path.read_text())
                for artifact in project['artifacts']:
                    if artifact['path'] == str(helper.relative_to(package)):
                        artifact['sha256'] = sha(helper)
                write_json(project_path, project)
                destination = self.work / ('refused-' + name)
                process = self.install(source, destination)
                self.assert_helper_refused(process, name)
                self.assertFalse(destination.exists(), 'refused installation was activated')
                self.assertEqual(list(self.work.glob('.' + destination.name + '.staging-*')), [])
                shutil.rmtree(source)

    def test_installed_launcher_refuses_changed_helpers_before_execution(self):
        for name in HELPERS:
            with self.subTest(helper=name):
                destination = self.work / ('installed-' + name)
                self.assert_succeeded(self.install(self.source, destination))
                package = destination / 'cpp'
                self.tamper(package, name)
                process = self.run_command([package / 'bin/mirrors-dpm', '--help'])
                self.assert_helper_refused(process, name)
                shutil.rmtree(destination)


if __name__ == '__main__':
    unittest.main()
