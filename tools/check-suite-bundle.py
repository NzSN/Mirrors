#!/usr/bin/env python3
"""Always-on bundle ownership, freshness, hash and legacy compatibility gates."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def snapshot(root):
    return {str(path.relative_to(root)): path.read_bytes() for path in root.rglob('*') if path.is_file()}


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=root / '.lake/build/bin/model_interface_gen')
    args = parser.parse_args()
    fixture = root / 'test/fixtures/model-interface/counter'
    lock = fixture / 'Counter.mirror-interface.lock.json'
    inputs = ['--spec', str(root / 'specs/Counter.tla'), '--contract', str(fixture / 'Counter.mirror-interface.json'),
              '--evidence', str(fixture / 'counter.itf.json'), '--param-var', 'parameters', '--lock', str(lock)]

    def run(command, expected=0):
        result = subprocess.run([str(args.compiler.resolve()), *command], cwd=root, capture_output=True, text=True)
        assert result.returncode == expected, f'{command}: {result.returncode}\n{result.stdout}{result.stderr}'
        return result

    with tempfile.TemporaryDirectory(prefix='mirrors-suite-bundle-') as directory:
        scratch = Path(directory)
        out = scratch / 'bundle'
        generate = ['bundle', '--lock', str(lock), '--target', 'mirrorecma-async-v1', '--out', str(out)]
        check = ['check-bundle', *inputs, '--target', 'mirrorecma-async-v1', '--out', str(out)]
        run(generate)
        run(check)
        first = snapshot(out)
        run(generate)
        assert snapshot(out) == first, 'bundle generation is nondeterministic'
        legacy = snapshot(fixture / 'generated-async')
        assert all(first[name] == data for name, data in legacy.items()), 'legacy async output changed'
        manifest_path = out / '.suite-bundle-generated.json'
        manifest = json.loads(manifest_path.read_text())
        assert manifest['schema'] == 'mirrors.suite-bundle/v1'
        assert set(manifest['files']) == set(first)
        assert {item['path'] for item in manifest['payloadSha256']} == set(first) - {manifest_path.name}
        for item in manifest['payloadSha256']:
            assert hashlib.sha256(first[item['path']]).hexdigest() == item['sha256']
        assert manifest['metadataSha256'] == hashlib.sha256(first['bundle-metadata.json']).hexdigest()
        # Freshness is byte exact and read-only, including metadata and companion.
        (out / 'Counter.suite.ts').write_text('stale\n')
        stale = snapshot(out)
        run(check, 1)
        assert snapshot(out) == stale, 'check repaired stale output'
        run(generate)
        assert snapshot(out) == first
        # Ownership validates closed schemas and rejects stale/corrupt manifests.
        invalid = dict(manifest, extra='forbidden')
        manifest_path.write_text(json.dumps(invalid))
        before = snapshot(out)
        run(generate, 1)
        assert snapshot(out) == before
        manifest_path.write_bytes(first[manifest_path.name])
        # Previous compiler-owned files are removed; unrelated files survive.
        (out / 'old.ts').write_text('owned stale file')
        (out / 'user.txt').write_text('authored')
        previous = json.loads(json.dumps(manifest))
        previous['files'].append('old.ts')
        previous['payloadSha256'].append({'path': 'old.ts', 'sha256': hashlib.sha256(b'owned stale file').hexdigest()})
        manifest_path.write_text(json.dumps(previous))
        run(generate)
        assert not (out / 'old.ts').exists()
        assert (out / 'user.txt').read_text() == 'authored'
        # Lock excludes all writers; symlink/collision failures never change bytes.
        publication_lock = out / '.model-interface-generation.lock'
        publication_lock.write_text('active')
        before = snapshot(out)
        run(generate, 1)
        assert snapshot(out) == before
        publication_lock.unlink()
        collision = scratch / 'collision'
        collision.mkdir()
        (collision / 'Counter.suite.ts').write_text('authored')
        run(generate[:-1] + [str(collision)], 1)
        assert snapshot(collision) == {'Counter.suite.ts': b'authored'}
        linked = scratch / 'linked'
        linked.mkdir()
        (linked / 'Counter.suite.ts').symlink_to(collision / 'Counter.suite.ts')
        run(generate[:-1] + [str(linked)], 1)
        assert (collision / 'Counter.suite.ts').read_text() == 'authored'
        before = snapshot(out)
        run(['generate', '--lock', str(lock), '--target', 'mirrorecma-async-v1', '--out', str(out)], 1)
        assert snapshot(out) == before, 'ordinary generation modified a sealed bundle'
        # Existing generation and bundle ownership are never silently adopted.
        legacy_out = scratch / 'legacy'
        run(['generate', '--lock', str(lock), '--target', 'mirrorecma-async-v1', '--out', str(legacy_out)])
        before = snapshot(legacy_out)
        run(generate[:-1] + [str(legacy_out)], 1)
        assert snapshot(legacy_out) == before
        run(['bundle', '--lock', str(lock), '--target', 'mirrorecma-v1', '--out', str(scratch / 'bad')], 1)
        assert not (scratch / 'bad').exists()
    print('Suite bundle: hashes, deterministic generation, legacy bytes, read-only freshness and publication safety passed.')


if __name__ == '__main__':
    main()
