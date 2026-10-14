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
        '/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build'))
    parser.add_argument('--root', type=Path, default=Path(
        '/home/jlc/Tools/mirrors-dpm-remediation-20261013'))
    parser.add_argument('--gate', type=Path)
    parser.add_argument('--installed', type=Path)
    parser.add_argument('--local-phase', default='local-gates-retry-phase.exit')
    parser.add_argument('--local-log', default='local-no-model-check-retry.log')
    parser.add_argument('--acceptance-phase', default='acceptance-phase.exit')
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
                 'lean-focus-phase.exit', 'rust-retry-phase.exit']:
        require(phases.get(name) == '0', 'remote phase not successful: ' + name)
    require('ALL LOCAL NON-MODEL GATES GREEN' in (build / 'logs' / args.local_log).read_text(),
            'successful full local non-model gate marker missing')
    # Original aggregate jobs retain their failed exits. Credit only their
    # successful stages and the explicit later retries, never erase history.
    require('Build completed successfully (727 jobs)' in (build / 'logs/lean-build.log').read_text(),
            'remote Lean build completion missing')
    python_log = (build / 'logs/dpm-python-final.log').read_text()
    require('Ran 58 tests' in python_log and re.search(r'^OK\s*$', python_log, re.MULTILINE),
            'final remote Python regressions incomplete')
    require('16 gates passed' in (build / 'logs/dpm-spec-final.log').read_text(), 'pure policy gates incomplete')
    require('11 gates passed' in (build / 'logs/dpm-evidence-spec-final.log').read_text(),
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
                'tools/deterministic-scheduling/tests/test_dpm_host.py']
    sources = {str(source / name): sha(source / name) for name in reviewed}
    for name in ['src/schedule_sync.cpp', 'include/mirrorcpp/schedule_sync.hpp']:
        path = root / 'source/MirrorCPP' / name
        sources[str(path)] = sha(path)
    logs = {p.name: sha(p) for p in sorted((build / 'logs').glob('*.log'))}
    print(json.dumps({'schema': 'mirrors.dpm-independent-remediation-review/v1',
                      'status': 'no_remaining_confirmed_findings_in_reviewed_scope',
                      'scope': ['Original four findings and evidence/compatibility followups',
                                'Launcher-owned policy parser correction',
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
                      'phaseExits': phases, 'reviewedSourceHashes': sources, 'remoteLogHashes': logs,
                      'historicalPhaseDisposition': {
                          'lean-phase.exit': 'Build succeeded; later host/assertion failures superseded by lean-focus-phase.exit',
                          'languages-phase.exit': 'ECMA passed; Rust offline-cache failure superseded by rust-retry-phase.exit',
                          'local-gates-phase.exit': 'Shared-root fixture rejected relocated build symlink; superseded by retry',
                          'local-gates-final-phase.exit': 'ENOSPC copying test launcher; superseded by retry'},
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
