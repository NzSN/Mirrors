#!/usr/bin/env python3
"""Build and exercise admitted DPM artifacts with source trees/network hidden."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(root, rows):
    for relative, expected in rows.items():
        path = root / relative
        if path.is_symlink() or not path.is_file() or sha(path) != expected:
            raise RuntimeError('missing or changed admitted artifact: ' + relative)


def inside():
    admitted = Path('/tmp/admitted'); work = Path('/tmp/work')
    rows = json.loads((admitted / 'manifest.json').read_text())
    verify(admitted, rows)
    assert not Path('/home/nzsn/Repos/Mirrors').exists()
    assert not Path('/home/nzsn/Repos/MirrorCPP').exists()
    capability = json.loads((admitted / 'prefix/share/mirrorcpp/scheduling-capabilities.json').read_text())
    assert capability['schema'] == 'mirrorcpp.scheduling-capabilities/v1'
    assert capability['claims']['genericNativeScheduler'] is False
    assert capability['claims']['hardInProcessTermination'] is False
    controls = []
    probe = work / 'artifact-control'; probe.mkdir()
    sample = admitted / 'prefix/share/mirrorcpp/scheduling-capabilities.json'
    shutil.copy2(sample, probe / 'capability.json')
    expected = {'capability.json': sha(sample)}
    verify(probe, expected)
    (probe / 'capability.json').write_text('{}\n')
    for mode in ['tampered', 'missing']:
        if mode == 'missing': (probe / 'capability.json').unlink()
        try: verify(probe, expected)
        except RuntimeError: controls.append(mode)
        else: raise RuntimeError('artifact verifier accepted ' + mode)
    def run(command, name):
        with (work / (name + '.log')).open('w') as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=240)
    kit = admitted / 'kit'
    native_generated = admitted / 'native-generated'
    native_options = ['-DDPM_NATIVE_GENERATED_DIR=' + str(native_generated)] if native_generated.is_dir() else []
    run(['cmake', '-S', str(kit / 'tools/deterministic-scheduling'), '-B', '/tmp/work/build',
         '-DCMAKE_CXX_COMPILER=/usr/bin/c++', '-DCMAKE_BUILD_TYPE=Release',
         '-DCMAKE_PREFIX_PATH=/tmp/admitted/prefix', '-Dmirrorcpp_DIR=/tmp/admitted/prefix/lib/cmake/mirrorcpp',
         '-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF', '-DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF', *native_options], 'configure')
    targets = ['dpm_counter', 'dpm_explore'] + (['dpm_native'] if native_generated.is_dir() else [])
    run(['cmake', '--build', '/tmp/work/build', '--target', *targets, '-j2'], 'build')
    run(['python3', str(kit / 'tools/deterministic-scheduling/check.py'),
         '--runner', '/tmp/work/build/dpm_counter', '--mirror', '/tmp/admitted/runtime/mirror',
         '--fixture', str(kit / 'test/fixtures/deterministic-scheduling'),
         '--trace', str(kit / 'test/fixtures/deterministic-scheduling/type-evidence.itf.json'),
         '--installed-prefix', '/tmp/admitted/prefix', '--out', '/tmp/work/replay'], 'replay')
    run(['python3', str(kit / 'tools/deterministic-scheduling/check_exploration.py'),
         '--runner', '/tmp/work/build/dpm_explore', '--out', '/tmp/work/exploration'], 'exploration')
    profile_controls = []
    for mode in ['unsupported-profile', 'unsupported-mapping']:
        schedule = json.loads((work / 'replay/ok.schedule.json').read_text())
        mapping = json.loads((work / 'replay/mapping.json').read_text())
        if mode == 'unsupported-profile': schedule['profile'] = 'unsupported/v99'
        else: mapping['actions']['read'] = 'wrong-checkpoint'
        schedule_path = work / (mode + '.schedule.json')
        mapping_path = work / (mode + '.mapping.json')
        schedule_path.write_text(json.dumps(schedule)); mapping_path.write_text(json.dumps(mapping))
        report_path = work / (mode + '.receipt.json')
        result = subprocess.run(['/tmp/work/build/dpm_counter', '--mirror', '/tmp/admitted/runtime/mirror',
            '--spec', str(kit / 'test/fixtures/deterministic-scheduling/ScheduledCounter.tla'),
            '--trace', str(kit / 'test/fixtures/deterministic-scheduling/type-evidence.itf.json'),
            '--schedule', str(schedule_path), '--mapping', str(mapping_path), '--out', str(report_path)],
            capture_output=True, text=True, timeout=20)
        (work / (mode + '.log')).write_text(result.stdout + result.stderr)
        assert result.returncode == 2 and not report_path.exists(), mode + ' accepted'
        profile_controls.append(mode)
    verify(admitted, rows)
    report = {'schema': 'mirrors.dpm5-installed-acceptance/v1', 'status': 'passed',
              'scope': 'Linux installed cooperative binding and finite local exploration',
              'sourceHidden': True, 'networkNamespaceIsolated': True,
              'replayCases': 15, 'explorationCases': 11, 'artifactControls': controls, 'compatibilityControls': profile_controls,
              'freshModelCheck': False, 'nativeWindowsAcceptance': 'separate native acceptance record required',
              'nativeControllerCompiled': native_generated.is_dir(),
              'manifestSha256': sha(admitted / 'manifest.json'),
              'capabilityDeclarationSha256': sha(sample),
              'evidence': {name: sha(work / name) for name in ['replay/acceptance.json', 'exploration/acceptance.json']}}
    (work / 'acceptance.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sdk-build', type=Path, required=True)
    parser.add_argument('--dependency-prefix', type=Path, required=True)
    parser.add_argument('--native-generated', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args(); out = args.out.resolve(); out.mkdir(parents=True, exist_ok=False)
    admitted = out / 'admitted'; prefix = admitted / 'prefix'; prefix.mkdir(parents=True)
    for relative in ['include/boost', 'include/nlohmann', 'share/cmake/nlohmann_json']:
        shutil.copytree(args.dependency_prefix / relative, prefix / relative)
    with (out / 'install.log').open('w') as log:
        subprocess.run(['cmake', '--install', str(args.sdk_build.resolve()), '--prefix', str(prefix)],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    kit = admitted / 'kit'
    shutil.copytree(ROOT / 'tools/deterministic-scheduling', kit / 'tools/deterministic-scheduling',
                    ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copytree(ROOT / 'test/fixtures/deterministic-scheduling', kit / 'test/fixtures/deterministic-scheduling')
    if args.native_generated: shutil.copytree(args.native_generated, admitted / 'native-generated')
    (admitted / 'runtime').mkdir(); shutil.copy2(ROOT / '.lake/build/bin/mirror', admitted / 'runtime/mirror')
    rows = {str(p.relative_to(admitted)): sha(p) for p in sorted(admitted.rglob('*')) if p.is_file()}
    (admitted / 'manifest.json').write_text(json.dumps(rows, indent=2) + '\n')
    work = out / 'work'; work.mkdir()
    command = ['bwrap', '--die-with-parent', '--unshare-net', '--ro-bind', '/', '/', '--tmpfs', '/home',
               '--tmpfs', '/tmp', '--ro-bind', str(admitted), '/tmp/admitted', '--bind', str(work), '/tmp/work',
               '--proc', '/proc', '--dev', '/dev', '--clearenv', '--setenv', 'PATH', '/usr/bin:/bin',
               '--setenv', 'HOME', '/tmp/work', '--setenv', 'LC_ALL', 'C.UTF-8', '--chdir', '/tmp/work',
               '/usr/bin/python3', '/tmp/admitted/kit/tools/deterministic-scheduling/check_installed.py', '--inside']
    (out / 'command.json').write_text(json.dumps(command, indent=2) + '\n')
    subprocess.run(command, check=True, timeout=600)
    verify(admitted, rows)


if __name__ == '__main__':
    if sys.argv[1:] == ['--inside']: inside()
    else: main()
