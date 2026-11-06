#!/usr/bin/env python3
"""Externally bounded ownership controls; run only on the admitted remote WSL.

The host executes the selected unmodified owned_process and exact CLI handler.
A line hook synchronizes its cleanup entry; every controller exit kills/reaps
owned children. Runner lifetime is independently capped even if the controller
is interrupted. This is a function/handler control, not public-CLI admission.
"""
import argparse
import ast
import ctypes
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import types

SELF = Path(__file__).absolute()
SCENARIOS = ['normal', 'single', 'repeated', 'timeout-first', 'finalization-first',
             'cleanup-entry-timeout-first', 'cleanup-entry-repeated']


def state(pid):
    try:
        return Path('/proc/' + str(pid) + '/stat').read_text().rsplit(')', 1)[1].split()[0]
    except FileNotFoundError:
        return None


def wait_file(path, host, deadline):
    while not path.exists():
        if time.monotonic() > deadline or host.poll() is not None:
            raise RuntimeError('control synchronization failed: ' + str(path))
        time.sleep(0.001)


def reap_adopted_children():
    """Cover a runner killed/adopted before its readiness file was published."""
    deadline = time.monotonic() + 2
    while True:
        try:
            reaped, _status = os.waitpid(-1, os.WNOHANG)
        except ChildProcessError:
            return
        if reaped:
            continue
        for item in Path('/proc').iterdir():
            if not item.name.isdigit():
                continue
            try:
                fields = (item / 'stat').read_text().rsplit(')', 1)[1].split()
                if int(fields[1]) == os.getpid():
                    group = int(fields[2])
                    if group != os.getpgrp():
                        os.killpg(group, signal.SIGKILL)
                    else:
                        os.kill(int(item.name), signal.SIGKILL)
            except (OSError, ValueError, IndexError):
                pass
        if time.monotonic() > deadline:
            raise RuntimeError('adopted process cleanup deadline exceeded')
        time.sleep(0.005)


def runner(root, scenario):
    if os.name != 'nt': signal.signal(signal.SIGTERM, signal.SIG_IGN)
    pending = root / 'control/runner.pending'
    pending.write_text(json.dumps({'pid': os.getpid(), 'pgid': os.getpgrp() if os.name != 'nt' else os.getpid()}))
    pending.rename(root / 'control/runner.json')
    print('runner-ready', flush=True)
    print('runner-error-log', file=sys.stderr, flush=True)
    time.sleep(0.08 if scenario in ['normal', 'finalization-first'] else 6)


def run_host(root, source, scenario):
    raw = (source / 'dpm_host.py').read_bytes()
    module = types.ModuleType('dpm_host')
    module.__file__ = str(source / 'dpm_host.py')
    exec(compile(raw, module.__file__, 'exec'), module.__dict__)
    tree = ast.parse((source / 'cli.py').read_text())
    main = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'main')
    cancelled = next(node for node in main.body if isinstance(node, ast.FunctionDef) and node.name == 'cancelled')
    scope = {'Refusal': module.Refusal, 'host': module}
    exec(compile(ast.Module(body=[cancelled], type_ignores=[]), str(source / 'cli.py'), 'exec'), scope)
    for signum in [signal.SIGTERM, signal.SIGINT]:
        signal.signal(signum, scope['cancelled'])
    original_mask = signal.pthread_sigmask(signal.SIG_BLOCK, set()) if os.name != 'nt' else None
    owned_ast = next(node for node in ast.parse(raw).body
        if isinstance(node, ast.FunctionDef) and node.name == ('_run_windows_process' if os.name == 'nt' else '_run_owned_process'))
    if os.name == 'nt':
        wait_line = next(node.lineno for node in ast.walk(owned_ast)
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
            and node.func.attr == 'terminate')
    else:
        wait_line = next(node.lineno for node in ast.walk(owned_ast)
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
            and isinstance(node.func.value, ast.Name) and node.func.value.id == 'child'
            and node.func.attr == 'wait' and any(keyword.arg == 'timeout' for keyword in node.keywords))
    process_try = next(node for node in owned_ast.body if isinstance(node, ast.Try) and node.finalbody)
    cleanup_entry_line = process_try.finalbody[0].lineno
    entry_control = scenario.startswith('cleanup-entry-')
    synchronized = False
    def check_cancel():
        if os.name == 'nt':
            request = root / 'control/cancel'
            if request.exists():
                request.unlink()
                scope['cancelled'](signal.SIGINT, None)
                pending = root/'control/ack.pending'; pending.write_text('ack')
                pending.rename(root/'control/cancel-ack')
    def trace(frame, event, _arg):
        nonlocal synchronized
        if event == 'line' and frame.f_code.co_filename == module.__file__: check_cancel()
        if (not synchronized and event == 'line' and frame.f_code.co_name == owned_ast.name
                and frame.f_lineno == (cleanup_entry_line if entry_control else wait_line)
                and (os.name == 'nt' or entry_control or frame.f_locals.get('sig') == signal.SIGTERM)):
            synchronized = True
            pending = root / 'control/cleanup.pending'
            pending.write_text(json.dumps({
                'point': 'cleanup-first-instruction' if entry_control else 'term-grace-wait',
                'sourceLine': frame.f_lineno, 'time': time.monotonic()}))
            pending.rename(root / 'control/cleanup-entered')
            deadline = time.monotonic() + 2
            while not (root / 'control/release').exists():
                check_cancel()
                if time.monotonic() > deadline:
                    raise RuntimeError('external cleanup synchronization deadline exceeded')
                time.sleep(0.001)
        return trace
    sys.settrace(trace)
    result = {'result': 'returned'}
    exit_code = 0
    try:
        module.owned_process([sys.executable, '-I', '-S', '-B', str(SELF), '--runner', str(root), scenario],
            root / 'request', 0.2 if scenario in ['timeout-first', 'cleanup-entry-timeout-first'] else 3, 1048576)
    except (module.Refusal, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        result = {'result': 'refused', 'exception': type(error).__name__, 'message': str(error),
                  'accounting': getattr(error, 'accounting', None)}
        exit_code = 2
    finally:
        sys.settrace(None)
    result['handlersRestored'] = all(signal.getsignal(s) is scope['cancelled'] for s in [signal.SIGINT, signal.SIGTERM])
    result['maskRestored'] = (signal.pthread_sigmask(signal.SIG_BLOCK, set()) == original_mask) if os.name != 'nt' else True
    result['ownerRegistrationRestored'] = module._ACTIVE_PROCESS_CANCELLATION is None
    result['retainedBytesAfterReturn'] = module.retained_bytes(root / 'request')
    logs = {str((root / 'request' / name).absolute()) for name in ['stdout.log', 'stderr.log']}
    open_logs = []
    for descriptor in (Path('/proc/self/fd').iterdir() if os.name != 'nt' else []):
        try:
            if os.readlink(descriptor) in logs:
                open_logs.append(descriptor.name)
        except OSError:
            pass
    if os.name == 'nt':
        # Python's file handles do not share delete access on Windows. Probe
        # before host exit, so leaked handles cannot be hidden by process exit.
        for name in ['stdout.log','stderr.log']:
            path = root/'request'/name; moved = path.with_suffix('.closed-probe')
            try:
                path.rename(moved); moved.rename(path)
            except OSError: open_logs.append(name)
    result['signalMaskApplicable'] = os.name != 'nt'
    result['openLogDescriptorsAfterReturn'] = open_logs
    print(json.dumps(result), flush=True)
    return exit_code


def control(source, output, scenario):
    root = output / scenario
    (root / 'control').mkdir(parents=True)
    (root / 'request').mkdir()
    host = subprocess.Popen([sys.executable, '-I', '-S', '-B', str(SELF), '--host', str(root), str(source), scenario],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    runner_pid = None
    result = {'scenario': scenario, 'hostPid': host.pid}
    try:
        deadline = time.monotonic() + 3
        wait_file(root / 'control/runner.json', host, deadline)
        runner_info = json.loads((root / 'control/runner.json').read_text())
        runner_pid = runner_info['pid']
        result.update(runner_info)
        if scenario in ['single', 'repeated', 'cleanup-entry-repeated']:
            os.kill(host.pid, signal.SIGTERM)
        wait_file(root / 'control/cleanup-entered', host, deadline)
        result['cleanupSynchronization'] = json.loads((root / 'control/cleanup-entered').read_text())
        if scenario.startswith('cleanup-entry-'):
            # The trace hook is before the very first cleanup instruction, so
            # this covers the entry/prologue gap in a cleanup-only signal mask.
            os.kill(host.pid, signal.SIGINT)
            if scenario == 'cleanup-entry-repeated':
                os.kill(host.pid, signal.SIGTERM)
        if scenario == 'finalization-first':
            os.kill(host.pid, signal.SIGINT)
        (root / 'control/release').write_text('released')
        if scenario in ['repeated', 'timeout-first']:
            time.sleep(0.02)
            os.kill(host.pid, signal.SIGINT if scenario == 'repeated' else signal.SIGTERM)
            if scenario == 'repeated':
                os.kill(host.pid, signal.SIGTERM)
        stdout, stderr = host.communicate(timeout=4)
        result.update({'hostExit': host.returncode, 'stdout': stdout.decode(), 'stderr': stderr.decode(),
                       'hostResult': json.loads(stdout), 'runnerStateAfterHostExit': state(runner_pid),
                       'stdoutLog': (root / 'request/stdout.log').read_text(),
                       'stderrLog': (root / 'request/stderr.log').read_text()})
    finally:
        # The controller adopts orphaned descendants and reaps them after KILL,
        # including when the source under test reproduces the original failure.
        if runner_pid is None and (root / 'control/runner.json').exists():
            runner_pid = json.loads((root / 'control/runner.json').read_text())['pid']
        for group in [runner_pid, host.pid]:
            if group is not None:
                try:
                    os.killpg(group, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        host.wait(timeout=2)
        if runner_pid is not None:
            deadline = time.monotonic() + 2
            while True:
                try:
                    reaped, _status = os.waitpid(runner_pid, os.WNOHANG)
                    if reaped:
                        result['controllerReapedRunner'] = True
                        break
                except ChildProcessError:
                    result['controllerReapedRunner'] = False
                    break
                if time.monotonic() > deadline:
                    raise RuntimeError('runner reap deadline exceeded')
                time.sleep(0.005)
            result['runnerStateAfterControllerCleanup'] = state(runner_pid)
            assert result['runnerStateAfterControllerCleanup'] is None
        result['hostStateAfterControllerCleanup'] = state(host.pid)
        assert result['hostStateAfterControllerCleanup'] is None
        reap_adopted_children()
        result['allControllerChildrenReaped'] = True
        host.stdout.close()
        host.stderr.close()
        (root / 'control/results.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def control_windows(source, output, scenario):
    # Windows cannot deliver POSIX signals with os.kill: SIGTERM terminates the
    # target. Synchronize the exact CLI callback on the host's main thread.
    module = types.ModuleType('dpm_host'); module.__file__ = str(source / 'dpm_host.py')
    exec(compile((source/'dpm_host.py').read_bytes(), module.__file__, 'exec'), module.__dict__)
    root = output / scenario
    (root/'control').mkdir(parents=True); (root/'request').mkdir()
    owner = module._WindowsJob()
    pipes = []
    def cancel():
        ack = root/'control/cancel-ack'; ack.unlink(missing_ok=True)
        pending = root/'control/cancel.pending'; pending.write_text('cancel')
        pending.rename(root/'control/cancel')
        deadline = time.monotonic()+3
        while not ack.exists():
            if (owner.poll() is not None or time.monotonic()>deadline) and not ack.exists(): raise RuntimeError('cancellation acknowledgement missing')
            time.sleep(0.001)
    class Host:
        def poll(self): return owner.poll()
    host = Host()
    try:
        with open(os.devnull, 'rb') as null:
            pipes = owner.start([sys.executable,'-I','-S','-B',str(SELF),'--host',str(root),str(source),scenario], root, null)
        deadline=time.monotonic()+5
        wait_file(root/'control/runner.json',host,deadline)
        runner_info=json.loads((root/'control/runner.json').read_text())
        if scenario in ['single','repeated','cleanup-entry-repeated']: cancel()
        wait_file(root/'control/cleanup-entered',host,deadline)
        if scenario in ['repeated','timeout-first'] or scenario.startswith('cleanup-entry-') or scenario=='finalization-first': cancel()
        if scenario=='cleanup-entry-repeated': cancel()
        (root/'control/release').write_text('release')
        # Repeated callbacks remain registered throughout cleanup. Deliver both
        # before releasing the synchronized cleanup hook to avoid a timing race.
        while owner.poll() is None:
            if time.monotonic()>deadline: raise RuntimeError('host deadline exceeded')
            time.sleep(0.001)
        stdout,stderr=[pipe.read().decode() for pipe in pipes]
        if not stdout: raise RuntimeError('host produced no result: '+stderr)
        final=json.loads(stdout)
        # No handle to a retained log may remain open when ownership returns.
        for name in ['stdout.log','stderr.log']:
            path=root/'request'/name; moved=path.with_suffix('.probe')
            path.rename(moved); moved.rename(path)
        if owner.active(): raise RuntimeError('live owned process after host exit')
        return {'scenario':scenario,'hostExit':owner.poll(),'hostResult':final,
            'runnerStateAfterHostExit':None,'runnerStateAfterControllerCleanup':None,
            'hostStateAfterControllerCleanup':None,'allControllerChildrenReaped':True,
            'controllerReapedRunner':False,'stdoutLog':(root/'request/stdout.log').read_text(),
            'stderrLog':(root/'request/stderr.log').read_text(),
            'cancellationTransport':'main-thread-exact-cli-handler-callback',
            'cleanupSynchronization':json.loads((root/'control/cleanup-entered').read_text())}
    finally:
        owner.terminate(); owner.close()
        for pipe in pipes: pipe.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--scenario', choices=SCENARIOS)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    if os.name != 'nt':
        libc = ctypes.CDLL(None, use_errno=True)
        if libc.prctl(36, 1, 0, 0, 0) != 0:
            raise RuntimeError('external controller subreaper unavailable')
    rows = [(control_windows if os.name == 'nt' else control)(args.source.absolute(), args.out.absolute(), scenario)
            for scenario in ([args.scenario] if args.scenario else SCENARIOS)]
    result = {'schema': 'mirrors.dpm-cancellation-controls/v1',
        'scope': 'owned-process-and-exact-cli-handler',
        'sourceSha256': {name: hashlib.sha256((args.source / name).read_bytes()).hexdigest()
                         for name in ['cli.py', 'dpm_host.py']}, 'rows': rows}
    (args.out / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--runner':
        runner(Path(sys.argv[2]), sys.argv[3])
    elif len(sys.argv) > 1 and sys.argv[1] == '--host':
        raise SystemExit(run_host(Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4]))
    else:
        main()
