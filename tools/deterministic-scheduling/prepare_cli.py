#!/usr/bin/env python3
"""Prepare reviewed Counter projects using compiled SDK consumers and retained oracles."""
import sys
if __name__ == '__main__' and not (sys.flags.isolated and sys.flags.no_site and sys.dont_write_bytecode):
    print('DPM Python entrypoint requires python3 -I -S -B', file=sys.stderr)
    raise SystemExit(2)

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
TOOLS = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, value):
    Path(path).write_text(json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cpp-runner', type=Path, required=True)
    parser.add_argument('--cpp-explorer', type=Path, required=True)
    parser.add_argument('--ecma', type=Path, required=True)
    parser.add_argument('--rust-runner', type=Path, required=True)
    parser.add_argument('--cpp-prefix', type=Path)
    parser.add_argument('--rust-devkit', type=Path)
    parser.add_argument('--rust-vendor', type=Path)
    parser.add_argument('--typescript', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    reports = []
    for language, profile in [('cpp', 'mirrorcpp.cooperative-checkpoints/v1'),
                              ('ecma', 'mirrorecma.worker-checkpoints/v1'),
                              ('rust', 'mirrorrust.cooperative-checkpoints/v1')]:
        root = args.out / language
        root.mkdir()
        (root / 'runtime').mkdir()
        (root / 'bin').mkdir()
        (root / 'share/mirrors-dpm').mkdir(parents=True)
        shutil.copy2(ROOT / '.lake/build/bin/mirrors_dpm', root / 'bin/mirrors-dpm')
        shutil.copy2(ROOT / '.lake/build/bin/mirror', root / 'runtime/mirror')
        for name in ['cli.py', 'dpm_host.py', 'timeline.py']:
            shutil.copy2(TOOLS / name, root / 'share/mirrors-dpm' / name)
        shutil.copy2(TOOLS / 'apps/counter_runner.py', root / 'counter_runner.py')
        shutil.copy2(ROOT / 'test/fixtures/deterministic-scheduling/ScheduledCounter.tla', root / 'model.tla')
        mapping = {'schema': 'mirrors.dpm-counter-mapping/v1', 'profile': profile,
            'actors': [{'actor': 'a', 'operation': 'increment-a'}, {'actor': 'b', 'operation': 'increment-b'}],
            'actions': {'read': 'read', 'write': 'write', 'finish': '$done'}}
        write(root / 'mapping.json', mapping)
        correspondence = {'schema': 'mirrors.dpm-trace-correspondence/v1',
            'actionPath': ['action_taken'], 'actorPath': ['parameters', 'actor'],
            'actionMap': mapping['actions'], 'initialBindings': [{'inputPath': ['initial'], 'statePath': ['count']}],
            'ignoredActors': ['spectator']}
        write(root / 'correspondence.json', correspondence)
        if language == 'cpp':
            shutil.copy2(args.cpp_runner, root / 'runner')
            shutil.copy2(args.cpp_explorer, root / 'explorer')
            runner = ['runner']; explorer = ['explorer']
            identity = {'modelSemanticDigest': json.loads((ROOT/'test/fixtures/deterministic-scheduling/ScheduledCounter.lock.json').read_text())['semanticDigest'],
                        'mappingSha256': sha(root / 'mapping.json'), 'implementationSha256': sha(root / 'runner')}
        elif language == 'rust':
            shutil.copy2(args.rust_runner, root / 'runner')
            runner = explorer = ['runner']
            description = subprocess.check_output([str(root/'runner'), '--mapping', str(root/'mapping.json'), '--describe'])
            identity = json.loads(description)['identity']
        else:
            shutil.copytree(args.ecma, root / 'ecma', ignore=shutil.ignore_patterns('__pycache__'))
            node = str(Path(shutil.which('node')).resolve())
            runner = explorer = [node, 'ecma/runner.mjs']
            description = subprocess.check_output([node, str(root/'ecma/runner.mjs'), '--mapping', str(root/'mapping.json'), '--describe'])
            identity = json.loads(description)['identity']
        explorer_identity = json.loads(subprocess.check_output([str(root/'explorer'), '--describe']))['identity'] if language == 'cpp' else identity
        app = {'language': language, 'runner': runner, 'explorer': explorer,
               'mirror': 'runtime/mirror', 'mapping': 'mapping.json', 'spec': 'model.tla'}
        write(root / 'application.json', app)
        # Build prerequisites are packaged separately from the runtime closure.
        if language == 'cpp' and args.cpp_prefix:
            shutil.copytree(args.cpp_prefix, root / 'devkit/prefix')
            for name in ['CMakeLists.txt', 'counter.cpp', 'counter_support.hpp', 'explore.cpp']:
                target=root/'devkit/consumer'/name;target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(TOOLS/name,target)
            (root/'devkit/consumer/CMakeLists.txt').write_text('cmake_minimum_required(VERSION 3.24)\nproject(dpm_installed_consumer LANGUAGES CXX)\nset(CMAKE_CXX_STANDARD 23)\nset(CMAKE_CXX_STANDARD_REQUIRED ON)\nfind_package(mirrorcpp CONFIG REQUIRED)\nfind_package(OpenSSL 3.0 REQUIRED)\nforeach(target counter explore)\nadd_executable(dpm_${target} ${target}.cpp)\ntarget_include_directories(dpm_${target} PRIVATE "${DPM_GENERATED_DIR}")\ntarget_link_libraries(dpm_${target} PRIVATE mirrorcpp::mirrorcpp OpenSSL::Crypto)\ntarget_compile_options(dpm_${target} PRIVATE -Wall -Wextra -Werror)\nendforeach()\n')
            shutil.copytree(ROOT/'test/fixtures/deterministic-scheduling/generated-cpp',root/'devkit/generated')
            sample=ROOT.parent/'MirrorCPP/examples/controlled_sync.cpp'
            if sample.exists(): shutil.copy2(sample,root/'devkit/consumer/controlled_sync.cpp')
        if language == 'rust' and args.rust_devkit:
            for name in ['src','sdk']:
                shutil.copytree(args.rust_devkit/name,root/'devkit'/name)
            for name in ['Cargo.toml','Cargo.lock']:
                shutil.copy2(args.rust_devkit/name,root/'devkit'/name)
            if args.rust_vendor: shutil.copytree(args.rust_vendor,root/'devkit/vendor')
        if language == 'ecma' and args.typescript:
            shutil.copytree(args.typescript,root/'devkit/typescript')
        def ref(path):
            return {'path': str(Path(path).relative_to(root)), 'sha256': sha(path)}
        candidates = []
        for name, initial in [('serial', 0), ('serial-five', 5), ('overlap', 0), ('overlap-five', 5)]:
            captured = root / 'oracles' / name
            shutil.copytree(ROOT/'Plans/dpm-languages-evidence-20261005/oracles/counter'/name, captured)
            trace = json.loads((captured / 'trace-0.itf.json').read_text())
            steps = [{'actor': s['parameters']['actor'], 'checkpoint': '$done' if s['action_taken']=='finish' else s['action_taken']}
                     for s in trace['states'][1:]]
            provenance = {'schema': 'mirrors.dpm-oracle-binding/v1', 'capture': ref(captured/'capture.json'),
                          'model': ref(root/'model.tla'), 'oracleSha256': sha(captured/'trace-0.itf.json'),
                          'correspondence': ref(root/'correspondence.json')}
            write(captured/'binding.json', provenance)
            for spectator in [False, True]:
                candidate_id = name + ('-spectator' if spectator else '')
                plan = {'schema':'mirrors.checkpoint-schedule/v1', 'profile': profile, 'identity': identity,
                    'inputs': {'initial':initial, 'mode':'mutate', 'spectator':spectator},
                    'steps': ([{'actor':'spectator','checkpoint':'$done'}] if spectator else []) + steps}
                candidates.append({'id':candidate_id, 'inputRank': 1 if initial else 0,
                    'schedule':plan, 'oracle':ref(captured/'trace-0.itf.json'), 'provenance':ref(captured/'binding.json')})
        artifacts = [ref(p) for p in sorted(root.rglob('*')) if p.is_file() and 'devkit' not in p.relative_to(root).parts]
        python = str(Path(sys.executable).resolve())
        external = {python}
        if language == 'ecma': external.add(runner[0])
        # Record resolved native runtime dependencies, independent of build tools.
        for native in [root/'bin/mirrors-dpm', root/'runtime/mirror', *([root/'runner'] if language != 'ecma' else [])]:
            result = subprocess.run(['ldd',str(native)],capture_output=True,text=True,check=False)
            for line in result.stdout.splitlines():
                words=line.split()
                for word in words:
                    if word.startswith('/') and Path(word).is_file(): external.add(str(Path(word).resolve()))
        artifacts += [{'path':path,'sha256':sha(path)} for path in sorted(external)]
        project = {'schema':'mirrors.dpm-project/v2','profile':profile,'identity':identity,'explorerIdentity':explorer_identity,
            'command':{'kind':'python-isolated','executable':python,'script':'counter_runner.py',
                       'args':[{'artifact':'application.json'}]}, 'artifacts':artifacts,
            'chains':[{'actor':'a','checkpoints':['read','write','$done']},
                      {'actor':'b','checkpoints':['read','write','$done']},
                      {'actor':'spectator','checkpoints':['$done']}],
            'baseline':'overlap-five-spectator','candidates':candidates,
            'signature':'counter-count-delta/v1',
            'limits':{'attempts':64,'timeoutMs':20000,'totalTimeoutMs':180000,'outputBytes':16*1024*1024,'totalOutputBytes':128*1024*1024}}
        write(root / 'project.json', project)
        reports.append({'language':language,'project':str(root/'project.json'),'sha256':sha(root/'project.json')})
    write(args.out/'projects.json',reports)
    print(json.dumps(reports,indent=2))


if __name__ == '__main__': main()
