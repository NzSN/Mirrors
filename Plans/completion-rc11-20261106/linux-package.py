#!/usr/bin/env python3
"""Build exact tagged Linux binaries, verify archive, and run isolated smoke."""
import json
import os
import tarfile
from pathlib import Path

from common import COMMIT, OUT, PLAN, ROOT, SOURCE, TAG, identity, run, write


def main():
    source = json.loads((PLAN / 'source-identity.json').read_text())
    env = dict(os.environ)
    env['TMPDIR'] = str(OUT / 'tmp')
    for key in ('APALACHE_MC', 'APALACHE_JAR', 'TLA2TOOLS_JAR', 'LD_LIBRARY_PATH', 'LD_PRELOAD'):
        env.pop(key, None)
    run('release-tests', ['python3', '-m', 'unittest', 'discover', '-s', 'tools/release',
                          '-p', 'test_*.py', '-v'], cwd=SOURCE, env=env)
    dist = OUT / 'linux-dist'
    assert not dist.exists()
    run('linux-release-build', ['python3', SOURCE / 'tools/release/release.py', 'build',
        '--source', SOURCE, '--tag', TAG, '--output', dist], cwd=SOURCE, env=env, timeout=3600)
    name = 'mirrors-' + TAG + '-linux-x86_64'
    archive = dist / (name + '.tar.gz')
    external = dist / (name + '.build.json')
    for line in (dist / 'SHA256SUMS').read_text().splitlines():
        sha, filename = line.split('  ', 1)
        assert identity(dist / filename)['sha256'] == sha
    metadata = json.loads(external.read_text())
    assert metadata['commit'] == COMMIT and metadata['tag'] == TAG
    assert metadata['passedGates'] == ['fixtures_replay', 'diff_cross', 'model_interface_spec',
        'stdio_smoke', 'transport_spec', 'check-client-framing.py', 'relocated-binary-cli-smoke']
    run('linux-maintained-archive-check', ['python3', SOURCE / 'tools/release/release.py',
        'check-archive', '--tag', TAG, '--archive', archive], env=env)
    extract = OUT / 'linux-smoke'
    extract.mkdir(mode=0o700)
    with tarfile.open(archive) as handle:
        members = handle.getmembers()
        assert len(members) == 6
        expected = {name, name + '/bin', name + '/README.txt', name + '/BUILD.json',
                    name + '/bin/mirror', name + '/bin/model_interface_gen'}
        assert {m.name for m in members} == expected
        assert all(m.isdir() or m.isfile() for m in members)
        assert handle.extractfile(name + '/BUILD.json').read() == external.read_bytes()
        handle.extractall(extract, filter='data')
    package = extract / name
    for binary, rec in metadata['binaries'].items():
        assert identity(package / 'bin' / binary)['sha256'] == rec['sha256']
    sandbox = ['/usr/bin/bwrap', '--die-with-parent', '--unshare-net', '--ro-bind', '/', '/',
        '--dev-bind', '/dev', '/dev', '--proc', '/proc', '--tmpfs', '/tmp',
        '--ro-bind', str(package), '/tmp/package', '--tmpfs', str(ROOT.parent),
        '--tmpfs', str(Path.home() / '.elan'), '--chdir', '/tmp/package',
        '--setenv', 'PATH', '/usr/bin:/bin', '--unsetenv', 'LD_LIBRARY_PATH', '--unsetenv', 'LD_PRELOAD']
    checks = "import json,os,pathlib,shutil; assert not pathlib.Path('/home/lsz/Codebase/Mirrors/Shell/Version.lean').exists(); assert shutil.which('lean') is None; assert shutil.which('lake') is None; print(json.dumps({'path':os.environ['PATH'],'netns':os.readlink('/proc/self/ns/net'),'sourceHidden':True,'leanUnavailable':True}))"
    isolation = json.loads(run('linux-isolation-check', sandbox + ['/usr/bin/python3', '-I', '-S', '-c', checks], env=env))
    version = run('linux-isolated-version', sandbox + ['/tmp/package/bin/mirror', '--version'], env=env)
    assert version == TAG
    protocol = json.loads(run('linux-isolated-protocol', sandbox + ['/tmp/package/bin/mirror'],
        env=env, stdin='{"proto_step":"report_state","state":{}}\n'))
    assert protocol['proto_step'] == 'protocol_error'
    run('linux-isolated-compiler-help', sandbox + ['/tmp/package/bin/model_interface_gen', '--help'],
        env=env, ok=(2,))
    assert run('linux-final-source-status', ['git', '-C', SOURCE, 'status', '--porcelain=v1']) == ''
    write(PLAN / 'linux-package.json', {'schema': 'mirrors.s3-rc11.linux-package/v1',
        'published': False, 'deployed': False, 'commit': COMMIT, 'tag': TAG,
        'tagObject': source['tagObject'], 'archive': identity(archive),
        'externalManifest': identity(external), 'checksums': identity(dist / 'SHA256SUMS'),
        'passedGates': metadata['passedGates'], 'isolatedSmoke': isolation,
        'mirrorVersion': version, 'hostRelease': Path('/etc/os-release').read_text(),
        'scope': 'focused Linux non-model release gates and source-hidden/network-isolated Ubuntu 26.04 WSL2 smoke',
        'installedDOrM5OrQ': False, 'releaseAdmission': False})
    print('LINUX PACKAGE VERIFIED', identity(archive)['sha256'], flush=True)


if __name__ == '__main__':
    main()
