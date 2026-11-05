#!/usr/bin/env python3
"""Use retained header dependencies for a fresh SDK build and native checks."""
import shutil
from common import OUT, PLAN, ROOT, environment, identity, run, write


def main():
    source = OUT / 'inputs/MirrorCPP'
    assert run('cpp-offline-source', ['git', '-C', source, 'rev-parse', 'HEAD']) == '8c542a6b1339cc0b6176465ff7f17a32e614553d'
    prefix, build = OUT / 'cpp-prefix', OUT / 'cpp-build-offline'
    assert not prefix.exists() and not build.exists()
    shutil.copytree(ROOT / '.golden-build/completion-20261029/cpp-prefix', prefix)
    run('cpp-offline-configure', ['cmake', '-S', source, '-B', build, '-DMIRRORCPP_WITH_TLS=ON',
        '-DMIRRORCPP_BUILD_TESTS=OFF', '-DMIRRORCPP_BUILD_EXAMPLES=OFF', '-DMIRRORCPP_BUILD_CLI=ON',
        '-DCMAKE_BUILD_TYPE=Release', '-DFETCHCONTENT_FULLY_DISCONNECTED=ON',
        '-DBoost_INCLUDE_DIR=' + str(prefix / 'include'),
        '-Dnlohmann_json_DIR=' + str(prefix / 'share/cmake/nlohmann_json'),
        '-DCMAKE_INSTALL_PREFIX=' + str(prefix)], env=environment())
    run('cpp-offline-build', ['cmake', '--build', build, '-j', '2'], env=environment())
    run('cpp-offline-install', ['cmake', '--install', build], env=environment())
    for header in (source / 'include/mirrorcpp').rglob('*'):
        if header.is_file():
            assert header.read_bytes() == (prefix / 'include/mirrorcpp' / header.relative_to(source / 'include/mirrorcpp')).read_bytes()
    write(PLAN / 'cpp-sdk-input.json', {'sourceRevision': '8c542a6b1339cc0b6176465ff7f17a32e614553d',
          'prefix': str(prefix), 'freshArchive': identity(prefix / 'lib/libmirrorcpp.a'),
          'freshInteropBinary': identity(build / 'cli/mirrorcpp-validate'),
          'externalHeaderDependencies': 'retained Boost/nlohmann headers from prior prefix; explicit offline selection',
          'interopPinAdmissionGranted': False})
    run('cpp-integer-maps-offline', ['python3', ROOT / 'tools/check-cpp-integer-maps.py', '--prefix', prefix], env=environment())
    run('cpp-controlled-preparation-offline', ['/usr/bin/python3', '-I', '-S', '-B',
        ROOT / 'tools/check-controlled-model.py', '--prefix', prefix, '--out', OUT / 'controlled-native'], env=environment(), timeout=1800)
    write(PLAN / 'native-checks.json', {'status': 'passed-current-rc7-native-checks',
          'integerMapsPassed': True, 'controlledPreparationPassed': True, 'freshModelComparison': False})


if __name__ == '__main__':
    main()
