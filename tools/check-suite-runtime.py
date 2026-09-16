#!/usr/bin/env python3
"""Generate and execute the native suite bridge using only the pinned Node runtime.

This execution gate needs neither an ECMA checkout nor npm packages. Installed
consumer gates separately typecheck the generated companion against MirrorECMA.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile


TRANSPILE = r'''
import {mkdir, readFile, readdir, writeFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
const [sourceRoot, outputRoot, expectedVersion] = process.argv.slice(1);
if (process.versions.node !== expectedVersion) {
  throw new Error(`Suite runtime gate requires pinned Node ${expectedVersion}; got ${process.versions.node}`);
}
await mkdir(outputRoot);
await writeFile(join(outputRoot, 'package.json'), '{"type":"module"}\n');
const sources = (await readdir(sourceRoot)).filter(name => name.endsWith('.ts')).sort();
if (sources.length !== 2) throw new Error('Expected one async module and one suite companion');
for (const name of sources) {
  const source = join(sourceRoot, name);
  const code = stripTypeScriptTypes(await readFile(source, 'utf8'), {
    mode: 'transform', sourceUrl: pathToFileURL(source).href,
  });
  await writeFile(join(outputRoot, name.slice(0, -3) + '.js'), code);
}
'''


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=root / '.lake/build/bin/model_interface_gen')
    parser.add_argument('--node', default='node')
    args = parser.parse_args()
    version = re.search(r'^NODE_VERSION=([0-9.]+)$',
                        (root / 'tools/ci/versions.env').read_text(), re.MULTILINE)
    if version is None:
        raise SystemExit('Missing pinned NODE_VERSION in tools/ci/versions.env')

    def run(arguments):
        result = subprocess.run(arguments, cwd=root, text=True, capture_output=True, timeout=120)
        if result.returncode != 0:
            raise SystemExit(f'{arguments[0]} failed ({result.returncode})\n{result.stdout}{result.stderr}')
        return result.stdout

    with tempfile.TemporaryDirectory(prefix='mirrors-suite-runtime-') as directory:
        scratch = Path(directory)
        bundle = scratch / 'bundle'
        output = scratch / 'compiled'
        run([str(args.compiler.resolve()), 'bundle', '--lock',
             str(root / 'test/fixtures/model-interface/counter/Counter.mirror-interface.lock.json'),
             '--target', 'mirrorecma-async-v1', '--out', str(bundle)])
        run([args.node, '--input-type=module', '--eval', TRANSPILE,
             str(bundle), str(output), version.group(1)])
        print(run([args.node, str(root / 'tools/check-suite-native.mjs'),
                   str(output / 'Counter.suite.js')]), end='')
    print('Suite runtime gate: fresh compiler output executed without an ECMA checkout or npm packages.')


if __name__ == '__main__':
    main()
