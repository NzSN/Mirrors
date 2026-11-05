#!/usr/bin/env python3
"""Prepare a direct strace ELF with recorded relative loader configuration."""
import json
import shutil
from common import OUT, PLAN, ROOT, environment, identity, run, write


def main():
    package = next((OUT / 'patchelf-input').glob('patchelf_*.deb'))
    unpacked = OUT / 'patchelf-input/root'
    run('patchelf-package-extract', ['dpkg-deb', '-x', package, unpacked])
    patch = unpacked / 'usr/bin/patchelf'
    version = run('patchelf-version', [patch, '--version'])
    tool = OUT / 'tracer'
    (tool / 'bin').mkdir(mode=0o700, parents=True)
    (tool / 'lib').mkdir(mode=0o700)
    original = ROOT / '.golden-build/mw12-20261103/inputs/strace/root/usr/bin/strace'
    binary = tool / 'bin/strace'
    shutil.copyfile(original, binary); binary.chmod(0o755)
    libraries = []
    base = ROOT / '.golden-build/mw12-20261103/inputs/strace/libunwind-root/usr/lib/x86_64-linux-gnu'
    for name in ['libunwind-ptrace.so.0', 'libunwind-x86_64.so.8', 'libunwind.so.8']:
        target = tool / 'lib' / name
        shutil.copyfile(base / name, target)
        libraries.append(identity(target))
    run('strace-rpath-selection', [patch, '--force-rpath', '--set-rpath', '$ORIGIN/../lib', binary])
    assert run('strace-rpath-observation', [patch, '--print-rpath', binary]) == '$ORIGIN/../lib'
    env = environment()
    env.pop('LD_LIBRARY_PATH', None); env.pop('LD_PRELOAD', None)
    run('direct-strace-version', [binary, '--version'], env=env)
    run('direct-strace-probe', [binary, '-f', '-qq', '-o', OUT / 'direct-strace-probe.log', '/usr/bin/true'], env=env)
    write(PLAN / 'tracer-input.json', {'status': 'prepared-and-probed-direct-ELF',
        'original': identity(original), 'artifact': identity(binary), 'libraries': libraries,
        'patchelfPackage': identity(package), 'patchelf': identity(patch), 'patchelfVersion': version,
        'rpath': '$ORIGIN/../lib', 'noSystemPackageInstallation': True,
        'registeredRc7CommandBindingUnchanged': True, 'frameworkCreditGranted': False})


if __name__ == '__main__':
    main()
