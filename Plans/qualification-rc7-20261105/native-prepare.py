#!/usr/bin/env python3
"""Prepare and exercise a fresh native SDK independently of interop CLI pins."""
from common import OUT, PLAN, ROOT, environment, identity, run, write


def main():
    source = OUT / 'inputs/MirrorCPP'
    source.parent.mkdir(mode=0o700)
    run('cpp-sdk-clone', ['git', 'clone', '--no-hardlinks', ROOT.parent / 'MirrorCPP', source])
    run('cpp-sdk-checkout', ['git', '-C', source, 'checkout', '--detach',
        '8c542a6b1339cc0b6176465ff7f17a32e614553d'])
    build, prefix = OUT / 'cpp-build', OUT / 'cpp-prefix'
    run('cpp-sdk-configure', ['cmake', '-S', source, '-B', build, '-DMIRRORCPP_WITH_TLS=ON',
        '-DMIRRORCPP_BUILD_TESTS=OFF', '-DMIRRORCPP_BUILD_EXAMPLES=OFF', '-DMIRRORCPP_BUILD_CLI=ON',
        '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_PREFIX_PATH=' + str(ROOT / '.golden-build/version-0.1/json-package'),
        '-DCMAKE_INSTALL_PREFIX=' + str(prefix)], env=environment())
    run('cpp-sdk-build', ['cmake', '--build', build, '-j', '2'], env=environment())
    run('cpp-sdk-install', ['cmake', '--install', build], env=environment())
    write(PLAN / 'cpp-sdk-input.json', {'sourceRevision': '8c542a6b1339cc0b6176465ff7f17a32e614553d',
          'prefix': str(prefix), 'archive': identity(prefix / 'lib/libmirrorcpp.a'),
          'interopBinary': identity(build / 'cli/mirrorcpp-validate'), 'interopPinAdmissionGranted': False})
    run('cpp-native-integer-maps', ['python3', ROOT / 'tools/check-cpp-integer-maps.py', '--prefix', prefix], env=environment())
    run('cpp-controlled-model-preparation', ['/usr/bin/python3', '-I', '-S', '-B',
        ROOT / 'tools/check-controlled-model.py', '--prefix', prefix, '--out', OUT / 'controlled-native'], env=environment(), timeout=1800)
    write(PLAN / 'native-checks.json', {'status': 'passed-current-rc7-native-checks',
          'integerMapsPassed': True, 'controlledPreparationPassed': True, 'freshModelComparison': False})


if __name__ == '__main__':
    main()
