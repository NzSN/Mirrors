#!/usr/bin/env python3
"""Execute generated Rust bindings with native paths and process ownership."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    cargo = shutil.which('cargo')
    repository = Path(os.environ.get('RUST_REPO', str(ROOT.parent / 'MirrorRust'))).resolve()
    if cargo is None or not (repository / 'Cargo.toml').is_file():
        print('SKIP Rust generated binding execution: cargo and a MirrorRust checkout are required (RUST_REPO).')
        return 0
    # This executable emits the synthetic structural-type corpus used below.
    executable = ROOT / '.lake/build/bin' / ('model_interface_spec.exe' if os.name == 'nt' else 'model_interface_spec')
    subprocess.run([str(executable)], cwd=ROOT, check=True)
    work = ROOT / '.golden-build/model-interface-rust'
    work.mkdir(parents=True, exist_ok=True)
    manifest = work / 'Cargo.toml'
    manifest.write_text('''[package]
name = "mirrors-generated-rust-tests"
version = "0.0.0"
edition = "2021"
[dependencies]
num-bigint = "0.4"
serde_json = "1"
mirrorrust = { path = %s }
[lib]
path = %s
''' % (json.dumps(str(repository)), json.dumps(str(ROOT / 'tools/model-interface-rust/tests.rs'))),
        encoding='utf-8', newline='\n')
    os.environ['CARGO_TARGET_DIR'] = str(ROOT / '.golden-build/mirrorrust-target')
    if os.name == 'nt':
        # Compiler helpers and real test executables retain separate job rules.
        from check_windows import main as native_main
        native_main()
        return 0
    return subprocess.run([cargo, 'test', '--manifest-path', str(manifest)], cwd=ROOT).returncode


if __name__ == '__main__':
    raise SystemExit(main())
