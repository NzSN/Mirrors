#!/usr/bin/env python3
"""Fresh installed C++/ECMA/Rust consumers with checkouts hidden and networking isolated."""
import sys
if __name__ == '__main__' and not (sys.flags.isolated and sys.flags.no_site and sys.dont_write_bytecode):
    print('DPM Python entrypoint requires python3 -I -S -B', file=sys.stderr)
    raise SystemExit(2)

import argparse
import types
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
# Generated helper pins; refresh_host_identity.py updates these before packaging.
_HELPER_SHA256 = {'dpm_host': '250f79d558d2277fe7849fb0b77f91c41b8b2d5d5cdb6618618b97c134e63ff6', 'install_cli': 'ae27986c95369ecaf7561b4496f7f4d87cd7085d1ab338eb9f55577b6b668f21'}  # refreshed helper identities

def _load_helper(name):
    source = Path(__file__).with_name(name + '.py')
    raw = source.read_bytes()
    if len(raw) > 1048576 or hashlib.sha256(raw).hexdigest() != _HELPER_SHA256.get(name):
        raise RuntimeError('DPM helper differs from trusted tool: ' + name)
    module = types.ModuleType(name)
    module.__file__ = str(source)
    sys.modules[name] = module
    exec(compile(raw, str(source), 'exec'), module.__dict__)
    return module

_host = _load_helper('dpm_host')
sha, strict, write, Refusal = (_host.sha, _host.strict, _host.write, _host.Refusal)
_install = _load_helper('install_cli')
inventory, verify = _install.inventory, _install.verify


def run(command, log, expected=0, timeout=300, env=None):
    with Path(log).open('xb') as stream:
        completed=subprocess.run(command,stdout=stream,stderr=subprocess.STDOUT,timeout=timeout,env=env)
    if completed.returncode!=expected:
        raise RuntimeError('unexpected exit '+str(completed.returncode)+': '+str(command)+'; '+str(log))


def rebind(root, language):
    project=strict(root/'project.json')
    app=strict(root/'application.json')
    if language=='ecma':
        description=subprocess.check_output([app['runner'][0],str(root/app['runner'][1]),'--mapping',str(root/'mapping.json'),'--describe'])
        identity=json.loads(description)['identity']
    elif language=='rust':
        identity=json.loads(subprocess.check_output([str(root/'runner'),'--mapping',str(root/'mapping.json'),'--describe']))['identity']
    else:
        identity=dict(project['identity']);identity['implementationSha256']=sha(root/'runner')
    project['identity']=identity
    project['explorerIdentity']=json.loads(subprocess.check_output([str(root/'explorer'),'--describe']))['identity'] if language=='cpp' else identity
    for candidate in project['candidates']:candidate['schedule']['identity']=identity
    for ref in project['artifacts']:
        path=Path(ref['path']);path=path if path.is_absolute() else root/path
        ref['sha256']=sha(path)
    (root/'project.json').write_text(json.dumps(project,sort_keys=True,separators=(',',':'))+'\n')
    return project


def receipt_controls(root, binary, selected, candidate_id):
    """Refuse mutations of freshly produced receipts using the installed pure helper."""
    directory = root / 'receipt-controls'
    directory.mkdir()
    project = _host.Project(selected, sha(selected), binary)
    project.begin(directory)
    candidate = project.candidates[candidate_id]
    oracle = project.oracle(candidate)
    complete = strict(root / 'match/receipt.json')
    mismatch = strict(root / 'mismatch/receipt.json')
    rows = []
    def refuses(name, receipt):
        try:
            _host.classify(receipt, candidate, project.data['signature'], oracle,
                lambda pairs: project.values(pairs, time.monotonic() + 30))
        except Refusal as error:
            rows.append({'control': name, 'status': 'refused', 'reason': str(error)})
        else:
            raise RuntimeError('fresh receipt mutation accepted: ' + name)
    bad = copy.deepcopy(complete)
    execution = bad['binding']['executions'][0]
    execution['events'] = []; execution['observations'] = [{}]; execution['outcome'] = 'cancelled'
    refuses('original_truncated_cancelled_match', bad)
    bad = copy.deepcopy(complete)
    bad['binding']['executions'][0]['events'][0]['ordinal'] = 1
    refuses('wrong_event_ordinal', bad)
    bad = copy.deepcopy(complete)
    bad['binding']['executions'][0]['observations'][0]['afterSteps'] = True
    refuses('boolean_observation_index', bad)
    bad = copy.deepcopy(complete)
    bad['binding']['executions'][0]['observations'][0]['state']['count'] = True
    refuses('boolean_integer_state_conflation', bad)
    bad = copy.deepcopy(complete)
    bad['binding']['executions'][0]['cleanupAttempts'] = []
    refuses('missing_cleanup_evidence', bad)
    # Mismatch runs use mutate inputs; their admitted correspondence is identical.
    failed_project = _host.Project(root / 'project.json', sha(root / 'project.json'), binary)
    failed_project.begin(directory)
    failed_candidate = failed_project.candidates[candidate_id]
    failed_oracle = failed_project.oracle(failed_candidate)
    bad = copy.deepcopy(mismatch)
    terminal = json.loads(bad['peerTerminalRaw'])
    terminal['actual']['count'] = 999
    bad['peerTerminalRaw'] = json.dumps(terminal)
    try:
        _host.classify(bad, failed_candidate, failed_project.data['signature'], failed_oracle,
            lambda pairs: project.values(pairs, time.monotonic() + 30))
    except Refusal as error:
        rows.append({'control': 'terminal_observation_disagreement', 'status': 'refused', 'reason': str(error)})
    else:
        raise RuntimeError('fresh mismatch terminal mutation accepted')
    exploration = strict(root / 'sdk-exploration/receipt.json')
    for name, bad in [('empty_complete_exploration', copy.deepcopy(exploration)),
                      ('missing_complete_exploration_run', copy.deepcopy(exploration))]:
        bad['runs'] = [] if name.startswith('empty') else bad['runs'][:-1]
        for key in ['attemptedRuns', 'eligibleRuns', 'completedRuns']:
            bad[key] = len(bad['runs'])
        try:
            _host.validate_exploration(bad,
                lambda pairs: project.values(pairs, time.monotonic() + 30), set(),
                project.data['profile'], project.data['explorerIdentity'])
        except Refusal as error:
            rows.append({'control': name, 'status': 'refused', 'reason': str(error)})
        else:
            raise RuntimeError('fresh exploration mutation accepted: ' + name)
    write(directory / 'acceptance.json', rows)
    return rows


def inside(args):
    admitted=Path('/tmp/admitted');work=Path('/tmp/work')
    if not args.hidden_source or any(path.exists() for path in args.hidden_source):
        raise RuntimeError('source checkouts visible or source hiding not declared')
    if os.readlink('/proc/self/ns/net')==args.parent_net:raise RuntimeError('network namespace not isolated')
    original=inventory(admitted)
    reports=[]
    for language in ['cpp','ecma','rust']:
        root=work/language
        shutil.copytree(admitted/language,root)
        if language=='cpp':
            prefix=root/'devkit/prefix'
            run([str(args.cmake),'-S',str(root/'devkit/consumer'),'-B',str(root/'build'),
                 '-DCMAKE_CXX_COMPILER='+str(args.cxx),
                 '-DCMAKE_PREFIX_PATH='+str(prefix),'-DDPM_GENERATED_DIR='+str(root/'devkit/generated'),
                 '-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF','-DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF',
                 '-DCMAKE_BUILD_TYPE=Release'],work/'cpp-configure.log')
            run([str(args.cmake),'--build',str(root/'build'),'--target','dpm_counter','dpm_explore','-j2'],work/'cpp-build.log')
            shutil.copy2(root/'build/dpm_counter',root/'runner');shutil.copy2(root/'build/dpm_explore',root/'explorer')
            # Compile the public F5 API against the installed library/headers.
            run([str(args.cxx),'-std=c++23','-Wall','-Wextra','-Werror',
                 '-I'+str(prefix/'include'),str(root/'devkit/consumer/controlled_sync.cpp'),
                 str(prefix/'lib/libmirrorcpp.a'),'-pthread','-lssl','-lcrypto','-o',str(work/'controlled-sync')],work/'sync-build.log')
            run([str(work/'controlled-sync')],work/'controlled-sync.receipt.json')
            sync=strict(work/'controlled-sync.receipt.json')
            if (sync['modelComparison'] is not False or sync['cleanup']!='confirmed' or not sync['passed'] or
                sync['observations'][-1]['state']!={'count':2,'received':[10,20]}):
                raise RuntimeError('installed controlled resource sample failed')
            overrun_source = work / 'controlled-sync-overrun.cpp'
            overrun_source.write_text(r'''#include <mirrorcpp/schedule_sync.hpp>
#include <chrono>
#include <iostream>
#include <memory>
#include <thread>
int main() {
  namespace sync = mirrorcpp::schedule_sync;
  using namespace std::chrono_literals;
  sync::Adapter adapter;
  adapter.identity = {std::string(64,'1'), std::string(64,'2'), std::string(64,'3')};
  adapter.actors = {"a"};
  adapter.factory = [] {
    auto observations = std::make_shared<int>(0);
    sync::Program program;
    program.workers = {{"a", [](sync::Hook&) {}}};
    program.observe = [observations] {
      if (++*observations == 3) std::this_thread::sleep_for(250ms);
      return nlohmann::json{{"observations", *observations}};
    };
    program.teardown = [] { std::this_thread::sleep_for(150ms); };
    return program;
  };
  sync::Policy policy; policy.execution_timeout = 100ms;
  auto execution = sync::start(std::move(adapter), policy);
  while (!execution->enabled().empty()) execution->advance("a");
  execution->cleanup(1ms);
  auto receipt = execution->receipt();
  std::cout << receipt.dump() << '\n';
  return receipt["passed"] == false && receipt["outcome"] == "timed_out" &&
    receipt["cleanup"] == "confirmed" && receipt["budgetExceeded"]["execution"] == true &&
    receipt["budgetExceeded"]["cleanup"] == true ? 0 : 1;
}
''')
            run([str(args.cxx),'-std=c++23','-Wall','-Wextra','-Werror',
                 '-I'+str(prefix/'include'),str(overrun_source),str(prefix/'lib/libmirrorcpp.a'),
                 '-pthread','-lssl','-lcrypto','-o',str(work/'controlled-sync-overrun')],work/'sync-overrun-build.log')
            run([str(work/'controlled-sync-overrun')],work/'controlled-sync-overrun.receipt.json')
        elif language=='ecma':
            node = strict(root/'application.json')['runner'][0]
            run([node,str(root/'devkit/typescript/bin/tsc'),'-p',str(root/'ecma/tsconfig.json')],work/'ecma-build.log')
            for generated in (root/'ecma/compiled/generated').rglob('*.js'):
                shutil.copy2(generated,root/'ecma'/generated.relative_to(root/'ecma/compiled'))
        else:
            devkit=root/'devkit';(devkit/'.cargo').mkdir()
            (devkit/'.cargo/config.toml').write_text('[source.crates-io]\nreplace-with="vendored-sources"\n[source.vendored-sources]\ndirectory="'+str(devkit/'vendor')+'"\n')
            env={'PATH':'/tmp/toolchain/rust/bin:/usr/bin:/bin','CARGO_HOME':str(work/'cargo'),
                 'RUSTC':'/tmp/toolchain/rust/bin/rustc','LC_ALL':'C.UTF-8'}
            with (work/'rust-build.log').open('xb') as log:
                subprocess.run(['/tmp/toolchain/rust/bin/cargo','build','--offline','--locked'],cwd=devkit,env=env,
                               stdout=log,stderr=subprocess.STDOUT,timeout=300,check=True)
            shutil.copy2(devkit/'target/debug/mirrors-dpm-rust-consumer',root/'runner')
        project=rebind(root,language)
        binary=str(root/'bin/mirrors-dpm');project_path=root/'project.json'
        def cli(operation,name,expected=0,extra=(),selected=project_path):
            command=[binary,operation,'--project',str(selected),'--project-sha256',sha(selected)]
            if operation!='doctor':command+=['--out',str(root/name)]
            run(command+list(extra),work/(language+'-'+name+'.log'),expected=expected,timeout=240)
        cli('doctor','doctor')
        policy_log = work / (language + '-public-policy-option.log')
        run([binary, '--policy', '/bin/false', 'doctor', '--project', str(project_path),
             '--project-sha256', sha(project_path)], policy_log, expected=2)
        if 'usage: mirrors-dpm' not in policy_log.read_text() or 'project admission:' in policy_log.read_text():
            raise RuntimeError('public policy option reached internal project admission')
        cli('replay','mismatch',expected=1)
        cli('reduce','reduction')
        reduction=strict(root/'reduction/result.json')
        if reduction['baselineCost']!=[3,1,4,7] or reduction['bestCost']!=[2,0,0,6] or reduction['bestReplay']!='confirmed':
            raise RuntimeError('installed real reduction failed')
        cli('explore','sdk-exploration',extra=['--space','sdk'])
        exploration=strict(root/'sdk-exploration/result.json')
        if exploration['executed']!=40 or not exploration['complete'] or exploration['modelComparison'] is not False:
            raise RuntimeError('SDK finite exploration denominator differs')
        normal=copy.deepcopy(project)
        for candidate in normal['candidates']:candidate['schedule']['inputs']['mode']='ok'
        normal_path=root/'normal.json';write(normal_path,normal)
        cli('replay','match',selected=normal_path)
        cli('explore','model-catalog',selected=normal_path)
        catalog=strict(root/'model-catalog/result.json')
        if catalog['executed']!=8 or not catalog['complete']:raise RuntimeError('admitted catalog incomplete')
        mutated_receipts = receipt_controls(root, binary, normal_path, project['baseline'])
        # Unlisted adjacent modules must stay inert with every selected pin unchanged.
        marker = root / 'unadmitted-code-ran'
        shadow = 'open(' + repr(str(marker)) + ',"w").write("executed")\n'
        host_shadow = root / 'share/mirrors-dpm/hashlib.py'
        app_shadow = root / 'json.py'
        host_shadow.write_text(shadow); app_shadow.write_text(shadow)
        cli('doctor', 'isolated-host-import')
        cli('replay', 'isolated-app-import', expected=1)
        if marker.exists(): raise RuntimeError('unlisted Python module executed')
        host_shadow.unlink(); app_shadow.unlink()
        receipt=root/'mismatch/receipt.json'
        run([binary,'report','--receipt',str(receipt),'--expected-sha256',sha(receipt),'--format','json'],work/(language+'-timeline.json'))
        run([binary,'report','--receipt',str(root/'reduction/result.json'),'--expected-sha256',sha(root/'reduction/result.json')],work/(language+'-reduction-report.log'))
        # Artifact changes must refuse before any application-runner request.
        mapping=root/'mapping.json';saved=mapping.read_bytes();mapping.write_bytes(b'{}\n')
        cli('doctor','tampered-mapping',expected=2);mapping.write_bytes(saved)
        runtime = root / ('ecma/runner.mjs' if language == 'ecma' else 'runner')
        saved_runtime = runtime.read_bytes(); runtime.write_bytes(saved_runtime + b'\n')
        cli('doctor', 'tampered-runtime', expected=2); runtime.write_bytes(saved_runtime)
        bad=copy.deepcopy(project);bad['profile']='unsupported/v1';bad_path=root/'bad.json';write(bad_path,bad)
        cli('doctor','unsupported-profile',expected=2,selected=bad_path)
        bad_oracle=copy.deepcopy(project);bad_oracle['candidates'][0]['oracle']['sha256']='0'*64
        bad_oracle_path=root/'bad-oracle.json';write(bad_oracle_path,bad_oracle)
        cli('doctor','tampered-oracle',expected=2,selected=bad_oracle_path)
        budget=copy.deepcopy(project);budget['limits']['attempts']=1;budget_path=root/'budget.json';write(budget_path,budget)
        cli('reduce','bounded-reduction',selected=budget_path)
        if strict(root/'bounded-reduction/result.json')['claim']!='best_observed':raise RuntimeError('truncated search claimed minimum')
        cleanup=copy.deepcopy(project)
        for candidate in cleanup['candidates']:candidate['schedule']['inputs']['mode']='mutate-and-teardown-fail'
        cleanup_path=root/'cleanup.json';write(cleanup_path,cleanup)
        cli('replay','cleanup-failure',expected=2,selected=cleanup_path)
        small = copy.deepcopy(project); small['limits']['outputBytes'] = 2048
        small_path = root / 'small-output.json'; write(small_path, small)
        cli('replay', 'request-output-overflow', expected=2, selected=small_path)
        if (root / 'request-output-overflow/receipt.json').exists():
            raise RuntimeError('over-budget replay published a verdict receipt')
        aggregate = copy.deepcopy(project); aggregate['limits']['attempts'] = 1
        aggregate['limits']['totalOutputBytes'] = 67584
        aggregate_path = root / 'small-aggregate.json'; write(aggregate_path, aggregate)
        cli('replay', 'aggregate-output-overflow', expected=2, selected=aggregate_path)
        write(root/'acceptance.json',{'language':language,'status':'passed','projectSha256':sha(project_path),
            'freshConsumerBuilt':True,'sourceHidden':True,'networkNamespaceIsolated':True,
            'baselineCost':reduction['baselineCost'],'bestCost':reduction['bestCost'],
            'catalogModelReplayCases':8,'sdkFiniteCases':40,'bestReplay':'confirmed',
            'controls':['tampered_mapping','tampered_runtime','unsupported_profile','tampered_oracle','bounded_search',
                        'cleanup_failure','isolated_host_import','isolated_app_import','request_output_overflow',
                        'aggregate_output_overflow', 'launcher_policy_argument_refused'], 'freshReceiptMutants': mutated_receipts,
            'freshModelCheck':False})
        reports.append(strict(root/'acceptance.json'))
    verify(admitted,original)
    write(work/'acceptance.json',{'schema':'mirrors.dpm-cli-installed-acceptance/v1','status':'passed',
        'profiles':reports,'sourceHidden':True,'networkNamespaceIsolated':True,
        'installedInventoryUnchanged':True,'hiddenSourceRoots':[str(path) for path in args.hidden_source],
        'buildPrerequisites':{'cmake':str(args.cmake),'cxx':str(args.cxx)},'syncPrimitiveSample':'passed',
        'syncReturningCallbackOverrun':'refused', 'freshModelCheck':False})
    print(json.dumps(strict(work/'acceptance.json'),indent=2))


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--installed',type=Path)
    parser.add_argument('--rust-toolchain',type=Path);parser.add_argument('--out',type=Path)
    parser.add_argument('--inside',action='store_true');parser.add_argument('--parent-net')
    parser.add_argument('--cmake',type=Path,default=Path(shutil.which('cmake') or '/usr/bin/cmake'))
    parser.add_argument('--cxx',type=Path,default=Path(shutil.which('c++') or '/usr/bin/c++'))
    parser.add_argument('--tool-root',type=Path,action='append',default=[])
    parser.add_argument('--hidden-source',type=Path,action='append',default=[])
    args=parser.parse_args()
    if args.inside:return inside(args)
    if not args.installed or not args.rust_toolchain or not args.out:parser.error('installed, rust-toolchain and out required')
    args.out.mkdir(parents=True,exist_ok=False)
    original=inventory(args.installed)
    script=Path(__file__).resolve()
    helpers=args.out/'gate-helpers';helpers.mkdir()
    for name in ['check_cli_installed.py','dpm_host.py','install_cli.py']:
        shutil.copy2(script.with_name(name),helpers/name)
    node=Path(strict(args.installed/'ecma/application.json')['runner'][0]).resolve()
    command=['bwrap','--die-with-parent','--unshare-net','--ro-bind','/','/',
        '--tmpfs','/home','--tmpfs','/mnt','--tmpfs','/tmp','--ro-bind',str(args.installed.resolve()),'/tmp/admitted',
        '--bind',str(args.out.resolve()),'/tmp/work','--ro-bind',str(args.rust_toolchain.resolve()),'/tmp/toolchain/rust',
        '--ro-bind',str(helpers.resolve()),'/tmp/gates','--ro-bind',str(node),str(node)]
    for path in args.tool_root:
        command+=['--ro-bind',str(path.resolve()),str(path.resolve())]
    source_root=script.parents[2]
    hidden=args.hidden_source or [source_root,*(source_root.parent/name for name in ['MirrorCPP','MirrorECMA','MirrorRust'])]
    command+=['--proc','/proc','--dev','/dev','--clearenv',
        '--setenv','PATH','/usr/bin:/bin','--setenv','LC_ALL','C.UTF-8','--chdir','/tmp/work',
        '/usr/bin/python3','-I','-S','-B','/tmp/gates/check_cli_installed.py','--inside','--parent-net',os.readlink('/proc/self/ns/net'),
        '--cmake',str(args.cmake.resolve()),'--cxx',str(args.cxx.resolve())]
    for path in hidden:command+=['--hidden-source',str(path.resolve())]
    write(args.out/'command.json',command)
    subprocess.run(command,timeout=1200,check=True)
    verify(args.installed,original)


if __name__=='__main__':main()
