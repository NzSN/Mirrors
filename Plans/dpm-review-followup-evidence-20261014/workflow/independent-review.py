#!/usr/bin/env python3
"""Read-only independent audit of the owned remote DPM acceptance artifacts.

Run in windows-dev Ubuntu WSL. The script starts no build, test, model checker,
application runner or service. Its only output is a JSON record on stdout.
"""
import argparse
import hashlib
import json
import platform
import re
from pathlib import Path


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def read(path):
    return json.loads(path.read_text())


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--status', action='store_true')
    parser.add_argument('--build', type=Path, default=Path(
        '/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build/followup-20261014'))
    parser.add_argument('--root', type=Path, default=Path(
        '/home/jlc/Tools/mirrors-dpm-followup-20261014'))
    parser.add_argument('--gate', type=Path)
    parser.add_argument('--installed', type=Path)
    parser.add_argument('--local-phase', default='local-gates-qualified-phase.exit')
    parser.add_argument('--local-log', default='local-no-model-check-qualified.log')
    parser.add_argument('--acceptance-phase', default='acceptance-phase.exit')
    parser.add_argument('--cancellation', type=Path, required=True)
    parser.add_argument('--public-controls', type=Path, required=True)
    args = parser.parse_args()
    build, root = args.build, args.root
    gate = args.gate or build / 'installed-gate-final'
    phases = {p.name: p.read_text().strip() for p in sorted(build.glob('*phase.exit'))}
    if args.status:
        print(json.dumps({'phaseExits': phases, 'acceptancePresent': (gate / 'acceptance.json').exists(),
                          'profiles': {name: (gate / name / 'acceptance.json').exists()
                                       for name in ['cpp', 'ecma', 'rust']}}, sort_keys=True))
        return
    for name in [args.acceptance_phase, args.local_phase, 'cpp-phase.exit',
                 'python-final-phase.exit', 'languages-phase.exit']:
        require(phases.get(name) == '0', 'remote phase not successful: ' + name)
    require('ALL LOCAL NON-MODEL GATES GREEN' in (build / 'logs' / args.local_log).read_text(),
            'successful full local non-model gate marker missing')
    # Original aggregate jobs retain their failed exits. Credit only their
    # successful stages and the explicit later retries, never erase history.
    require('Build completed successfully (727 jobs)' in (build / 'logs/lean-build.log').read_text(),
            'remote Lean build completion missing')
    python_log = (build / 'logs/dpm-python-final.log').read_text()
    require('Ran 65 tests' in python_log and re.search(r'^OK\s*$', python_log, re.MULTILINE),
            'final remote Python regressions incomplete')
    require('25 gates passed' in (build / 'logs/dpm-spec.log').read_text(), 'pure policy gates incomplete')
    require('11 gates passed' in (build / 'logs/dpm-evidence-spec.log').read_text(),
            'typed evidence gates incomplete')
    summary = read(gate / 'acceptance.json')
    require(summary['status'] == 'passed' and summary['sourceHidden'] is True and
            summary['networkNamespaceIsolated'] is True and summary['installedInventoryUnchanged'] is True,
            'installed acceptance incomplete')
    require(summary['freshModelCheck'] is False, 'unexpected model-check claim')
    expected_roots = {str(root / 'source' / name) for name in ['Mirrors', 'MirrorCPP', 'MirrorECMA', 'MirrorRust']}
    require(set(summary['hiddenSourceRoots']) == expected_roots, 'wrong hidden source roots')
    command = read(gate / 'command.json')
    require('--unshare-net' in command, 'missing network isolation')
    for path in ['/home', '/mnt', '/tmp']:
        require(any(command[i:i+2] == ['--tmpfs', path] for i in range(len(command)-1)),
                'source mount not hidden: ' + path)

    installed = args.installed or root / 'installed-final'
    manifest_path = build / 'installation-manifest-final.json'
    manifest = read(manifest_path)
    actual = set()
    for path in installed.rglob('*'):
        require(not path.is_symlink(), 'symlink in installed inventory')
        if path.is_file():
            name = str(path.relative_to(installed))
            actual.add(name)
            require(name in manifest['files'], 'unlisted installation file: ' + name)
            row = manifest['files'][name]
            require(sha(path) == row['sha256'] and bool(path.stat().st_mode & 0o111) == row['executable'],
                    'installation identity/mode differs: ' + name)
    require(actual == set(manifest['files']), 'installation files missing')

    source = root / 'source/Mirrors'
    identity = (source / 'Shell/Dpm/HostIdentity.lean').read_text()
    interpreter = Path(re.search(r'def interpreter : String := "([^"]+)"', identity).group(1))
    interpreter_hash = re.search(r'def interpreterSha256 : String := "([0-9a-f]+)"', identity).group(1)
    require(sha(interpreter) == interpreter_hash, 'selected interpreter differs')
    host_pins = dict(re.findall(r'\("([^"]+\.py)", "([0-9a-f]{64})"\)', identity))
    require(set(host_pins) == {'cli.py', 'dpm_host.py', 'timeline.py'}, 'unexpected embedded host closure')
    launcher_hash = sha(source / '.lake/build/bin/mirrors_dpm')
    for language in ['cpp', 'ecma', 'rust']:
        require(sha(installed / language / 'bin/mirrors-dpm') == launcher_hash, 'installed launcher differs')
        for name, digest in host_pins.items():
            require(sha(installed / language / 'share/mirrors-dpm' / name) == digest and
                    sha(source / 'tools/deterministic-scheduling' / name) == digest,
                    'installed/source host pin differs: ' + name)
        require(sha(installed / language / 'counter_runner.py') ==
                sha(source / 'tools/deterministic-scheduling/apps/counter_runner.py'), 'runner source differs')

    controls = {'tampered_mapping', 'tampered_runtime', 'unsupported_profile', 'tampered_oracle',
                'bounded_search', 'cleanup_failure', 'isolated_host_import', 'isolated_app_import',
                'request_output_overflow', 'aggregate_output_overflow', 'launcher_policy_argument_refused'}
    profiles, all_ids = [], []
    for language in ['cpp', 'ecma', 'rust']:
        path = gate / language
        accepted, project = read(path / 'acceptance.json'), read(path / 'project.json')
        require(accepted['status'] == 'passed' and accepted['freshConsumerBuilt'] is True and
                accepted['projectSha256'] == sha(path / 'project.json'), 'fresh consumer identity differs')
        require(set(accepted['controls']) == controls, 'missing installed controls')
        mutants = read(path / 'receipt-controls/acceptance.json')
        require(len(mutants) == 8 and all(row['status'] == 'refused' for row in mutants) and
                mutants == accepted['freshReceiptMutants'], 'fresh receipt controls differ')
        reduction = read(path / 'reduction/result.json')
        require(reduction['claim'] == 'minimal_in_admitted_catalog' and reduction['bestReplay'] == 'confirmed'
                and reduction['baselineCost'] == [3, 1, 4, 7] and reduction['bestCost'] == [2, 0, 0, 6]
                and len(reduction['trials']) == 7 and reduction['failure'] is None, 'reduction result differs')
        ids = []
        for response in sorted((path / 'reduction').glob('*/replay/response.json')):
            receipt = read(response)['result']
            execution = receipt['binding']['executions'][0]
            require(receipt['comparison'] == 'step_mismatch' and execution['cleanup'] == 'confirmed'
                    and execution['remainingActors'] == [] and execution['schedule']['identity'] == project['identity'],
                    'reduction execution/cleanup differs')
            ids.append(execution['executionId'])
        require(len(ids) == len(set(ids)) == 10, 'reduction execution identities not fresh')
        all_ids.extend(ids)
        catalog = read(path / 'model-catalog/result.json')
        require(catalog['complete'] is True and len(catalog['rows']) == 8 and
                all(row['comparison'] == 'matched' and row['cleanup'] == 'confirmed' for row in catalog['rows']),
                'catalog comparison incomplete')
        sdk = read(path / 'sdk-exploration/receipt.json')
        require(sdk['complete'] is True and len(sdk['runs']) == 40 and sdk['comparison'] == 'not_requested'
                and sdk['comparisonRuns'] == 0, 'SDK exploration scope differs')
        require(len({row['execution']['executionId'] for row in sdk['runs']}) == 40 and
                all(row['execution']['cleanup'] == 'confirmed' and row['execution']['remainingActors'] == []
                    for row in sdk['runs']), 'SDK execution freshness/cleanup differs')
        for name in ['request-output-overflow', 'aggregate-output-overflow']:
            refusal = read(path / name / 'result.json')
            require(refusal['status'] == 'incomplete' and refusal['process']['processCleanup'] == 'confirmed',
                    'budget refusal cleanup differs')
        require(not (path / 'unadmitted-code-ran').exists(), 'unadmitted import marker present')
        require(read(path / 'isolated-app-import/result.json')['comparison'] == 'step_mismatch',
                'isolated application import changed behavior')
        policy_log = (gate / (language + '-public-policy-option.log')).read_text()
        require('usage: mirrors-dpm' in policy_log and 'project admission:' not in policy_log,
                'public policy argument reached admission')
        profiles.append({'language': language, 'projectSha256': accepted['projectSha256'],
                         'reductionExecutionIds': ids, 'catalogMatches': 8, 'localSdkRuns': 40,
                         'freshReceiptMutantsRefused': 8, 'controls': sorted(controls)})
    require(len(set(all_ids)) == 30, 'cross-profile execution identity collision')
    sync = read(gate / 'controlled-sync-overrun.receipt.json')
    require(sync['outcome'] == 'timed_out' and sync['passed'] is False and sync['cleanup'] == 'confirmed'
            and sync['budgetExceeded'] == {'cleanup': True, 'execution': True}
            and sync['modelComparison'] is False, 'installed callback overrun credited as pass')

    reviewed = ['Codec/Dpm.lean', 'Codec/DpmEvidence.lean', 'Shell/Dpm/Cli.lean', 'Shell/Dpm/HostIdentity.lean',
                'tools/deterministic-scheduling/cli.py', 'tools/deterministic-scheduling/dpm_host.py',
                'tools/deterministic-scheduling/apps/counter_runner.py',
                'tools/deterministic-scheduling/check_cli_installed.py',
                'tools/deterministic-scheduling/tests/test_dpm_host.py',
                'tools/deterministic-scheduling/tests/cancellation_control.py', 'tools/DpmSpec.lean']
    sources = {str(source / name): sha(source / name) for name in reviewed}
    for name in ['src/schedule_sync.cpp', 'include/mirrorcpp/schedule_sync.hpp',
                 'test/unit/schedule_sync_test.cpp', 'test/unit/CMakeLists.txt']:
        path = root / 'source/MirrorCPP' / name
        sources[str(path)] = sha(path)
    fixed_cpp = read(build / 'fixed-cpp-evidence.json')
    require(fixed_cpp['outcome'] == 'evidence_exhausted' and fixed_cpp['passed'] is False and
            fixed_cpp['retainedEventObservationBytes'] <= fixed_cpp['limit'] and
            fixed_cpp['receipt']['cleanup'] == 'confirmed' and fixed_cpp['receipt']['modelComparison'] is False,
            'original C++ over-limit probe still passed or lost cleanup')
    measured_cpp = sum(len(json.dumps(fixed_cpp['receipt'][name], separators=(',', ':')).encode('utf-8'))
                       for name in ['events', 'observations'])
    require(measured_cpp == fixed_cpp['retainedEventObservationBytes'], 'fixed C++ retained byte measurement differs')
    frozen = read(build / 'frozen-inputs.json')
    require(frozen['status'] == 'verified', 'source input freeze missing')
    for row in frozen['selectedChanges']:
        require(sha(root / 'source' / row['repository'] / row['path']) == row['sha256'],
                'compiled selected source changed: ' + row['path'])
    ctest = read(build / 'ctest-timeout-check.json')
    require(ctest['status'] == 'passed' and len(ctest['tests']) == 27 and
            all(any(p['name'] == 'TIMEOUT' and p['value'] == 30.0 for p in t['properties'])
                for t in ctest['tests']), 'CTest synchronization timeout missing')
    cpp_log = (build / 'logs/mirrorcpp_schedule_sync_test.log').read_text()
    require('362 assertions in 27 test cases' in cpp_log, 'controlled synchronization regression count differs')
    cancellation = read(args.cancellation)
    expected = {'normal', 'single', 'repeated', 'timeout-first', 'finalization-first',
                'cleanup-entry-timeout-first', 'cleanup-entry-repeated'}
    require({r['scenario'] for r in cancellation['rows']} == expected, 'cancellation controls missing')
    require(cancellation['sourceSha256'] == {n: sha(source / 'tools/deterministic-scheduling' / n)
            for n in ['cli.py', 'dpm_host.py']}, 'cancellation controls used other source')
    for row in cancellation['rows']:
        result = row['hostResult']
        require(row['runnerStateAfterHostExit'] is None and row['runnerStateAfterControllerCleanup'] is None
                and row['hostStateAfterControllerCleanup'] is None and row['allControllerChildrenReaped'] is True
                and row['controllerReapedRunner'] is False, 'host did not reap its own runner')
        require(result['handlersRestored'] and result['maskRestored'] and result['ownerRegistrationRestored']
                and result['openLogDescriptorsAfterReturn'] == [], 'ownership/signal/log state not restored')
        require('runner-ready' in row['stdoutLog'] and 'runner-error-log' in row['stderrLog'], 'logs missing')
        if row['scenario'] == 'normal':
            require(row['hostExit'] == 0 and result['result'] == 'returned', 'normal execution failed')
        else:
            primary = 'runner timeout' if 'timeout' in row['scenario'] else 'operation cancelled'
            require(row['hostExit'] == 2 and result['exception'] == 'ProcessFailure'
                    and result['message'].startswith(primary + '; '), 'primary failure replaced')
            accounting = result['accounting']
            require(accounting['processCleanup'] == 'confirmed' and
                    accounting['retainedRequestBytes'] == result['retainedBytesAfterReturn'] and
                    accounting['requestOvershoot'] == 0, 'final cancellation accounting missing')
        if row['scenario'].startswith('cleanup-entry-'):
            require(row['cleanupSynchronization']['point'] == 'cleanup-first-instruction',
                    'cleanup entry control was not synchronized before first instruction')
    public = read(args.public_controls)
    require({r['scenario'] for r in public} == {'empty-argument', 'single-cancellation', 'repeated-cancellation'}
            and all(r['status'] == 'passed' and r['doctorExit'] == 0 and r['exit'] == 2
                    and r['runnerAbsentAfterReturn'] is True for r in public), 'public launcher controls failed')
    require(next(r for r in public if r['scenario'] == 'empty-argument')['runner']['argv'][0] == '',
            'empty literal was not retained as an actual argv entry')
    logs = {p.name: sha(p) for p in sorted((build / 'logs').glob('*.log'))}
    print(json.dumps({'schema': 'mirrors.dpm-independent-followup-review/v1',
                      'status': 'no_remaining_confirmed_findings_in_reviewed_scope',
                      'scope': ['Scoped cooperative cancellation including cleanup entry and repeated signals',
                                'Fully wrapped observation/event rows and separator byte admission',
                                'Empty literal argv admission with path and UTF-8 bounds',
                                'Thirty-second synchronization CTest timeout',
                                'Final remote installation identities and actual acceptance artifacts'],
                      'executionHost': platform.node(), 'auditPython': platform.python_version(),
                      'buildRoot': str(build), 'sourceRoot': str(root / 'source'),
                      'gateRoot': str(gate), 'installedRoot': str(installed),
                      'selectedFinalLocalPhase': args.local_phase,
                      'selectedFinalLocalLog': args.local_log,
                      'selectedFinalAcceptancePhase': args.acceptance_phase,
                      'installationManifestSha256': sha(manifest_path), 'installedFilesVerified': len(actual),
                      'launcherSha256': launcher_hash, 'interpreter': str(interpreter),
                      'interpreterSha256': interpreter_hash, 'hostPins': host_pins,
                      'cancellationControlsSha256': sha(args.cancellation),
                      'publicControlsSha256': sha(args.public_controls),
                      'frozenInputsSha256': sha(build / 'frozen-inputs.json'),
                      'cancellationScenariosVerified': sorted(expected),
                      'cppSynchronizationCases': 27, 'cppSynchronizationAssertions': 362,
                      'purePolicyGates': 25, 'pythonRegressionTests': 65, 'ctestTimeoutSeconds': 30,
                      'phaseExits': phases, 'reviewedSourceHashes': sources, 'remoteLogHashes': logs,
                      'historicalPhaseDisposition': {'lean-phase.exit':
                          'Lean build and pure gates passed; stale relocated helper setup diagnostic superseded by python-final-phase.exit'},
                      'profiles': profiles, 'totals': {'reductionExecutions': 30, 'catalogMatches': 24,
                                                     'localSdkRuns': 120, 'freshReceiptMutantsRefused': 24},
                      'installedOverrun': {key: sync[key] for key in
                                          ['outcome', 'passed', 'cleanup', 'budgetExceeded', 'modelComparison']},
                      'sourceHidden': True, 'hiddenSourceRoots': sorted(expected_roots),
                      'networkNamespaceIsolated': True, 'freshModelCheck': False,
                      'localBuildsOrTestsRunByReviewer': False, 'repositoryOrGateMutationsByAudit': False,
                      'limits': ['No fresh model or platform qualification', 'F5 is C++ only; no model comparison',
                                 'Output accounting is not a hard disk quota',
                                 'Returning callback checks do not provide hard in-process interruption',
                                 'Declared trusted platform and stable non-detaching runner prerequisites remain']},
                     indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
