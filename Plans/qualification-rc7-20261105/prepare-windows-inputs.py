#!/usr/bin/env python3
"""Prepare exact Git source bundles and offline C++ headers for Windows tests."""
import json
import zipfile
from pathlib import Path
from common import OUT, PLAN, ROOT, identity, run, write


def main():
    inputs = OUT / 'windows-inputs'
    inputs.mkdir(mode=0o700)
    mirrors = ROOT / '.golden-build/s3-rc7-20261104/source'
    assert run('windows-input-mirrors-revision', ['git', '-C', mirrors, 'rev-parse', 'HEAD']) == 'f525c6349dc5a5e457757fa040c89312c6703e3a'
    run('windows-input-mirrors-bundle', ['git', '-C', mirrors, 'bundle', 'create', inputs / 'Mirrors.bundle', 'HEAD'])
    cpp = OUT / 'inputs/MirrorCPP'
    run('windows-input-cpp-bundle', ['git', '-C', cpp, 'bundle', 'create', inputs / 'MirrorCPP.bundle', 'HEAD'])
    rust = ROOT / '.golden-build/completion-20261029/MirrorRust'
    assert run('windows-input-rust-revision', ['git', '-C', rust, 'rev-parse', 'HEAD']) == '6b9480ab81717b76ca7f74b41fc554578b70c890'
    run('windows-input-rust-bundle', ['git', '-C', rust, 'bundle', 'create', inputs / 'MirrorRust.bundle', 'HEAD'])
    prefix = OUT / 'cpp-prefix'
    roots = ['include/boost', 'include/nlohmann', 'share/cmake/nlohmann_json']
    with zipfile.ZipFile(inputs / 'cpp-dependencies.zip', 'x', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for relative in roots:
            for path in sorted((prefix / relative).rglob('*')):
                if path.is_file():
                    assert not path.is_symlink()
                    archive.write(path, path.relative_to(prefix).as_posix())
    write(PLAN / 'windows-inputs.json', {'sourceRevision': 'f525c6349dc5a5e457757fa040c89312c6703e3a',
        'cppRevision': '8c542a6b1339cc0b6176465ff7f17a32e614553d',
        'rustRevision': '6b9480ab81717b76ca7f74b41fc554578b70c890',
        'artifacts': [identity(p) for p in sorted(inputs.iterdir())],
        'publicSourceAndHeaderInputsOnly': True})


if __name__ == '__main__':
    main()
