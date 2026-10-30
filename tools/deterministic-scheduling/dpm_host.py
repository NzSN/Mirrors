"""Effectful DPM host. Pure admission/search order is supplied by Core.Dpm."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import signal
import selectors
import stat
import subprocess
import time
import uuid


class Refusal(RuntimeError):
    pass


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as source:
        for block in iter(lambda: source.read(65536), b''):
            h.update(block)
    return h.hexdigest()


def strict(path, limit=32 * 1024 * 1024):
    path = Path(path)
    regular(path)
    if path.stat().st_size > limit:
        raise Refusal('JSON byte bound exceeded')
    with path.open('rb') as stream:
        raw = stream.read(limit + 1)
    if len(raw) > limit: raise Refusal('JSON byte bound exceeded')
    return strict_bytes(raw)


def strict_bytes(raw):
    def pairs(rows):
        result = {}
        for key, value in rows:
            if key in result:
                raise Refusal('duplicate JSON field: ' + key)
            result[key] = value
        return result
    def nonfinite(value):
        raise Refusal('nonfinite JSON number: ' + value)
    try:
        value = json.loads(raw, object_pairs_hook=pairs, parse_constant=nonfinite)
    except (ValueError, UnicodeError, RecursionError) as error:
        raise Refusal('invalid JSON') from error
    def bounded(node, depth=0):
        if depth > 64:
            raise Refusal('JSON depth bound exceeded')
        if isinstance(node, dict):
            for item in node.values(): bounded(item, depth + 1)
        elif isinstance(node, list):
            for item in node: bounded(item, depth + 1)
    bounded(value)
    return value


def regular(path):
    path = Path(path).absolute()
    for part in [path, *path.parents]:
        if part.is_symlink():
            raise Refusal('symlink artifact: ' + str(path))
    if not stat.S_ISREG(path.stat().st_mode):
        raise Refusal('artifact is not a regular file: ' + str(path))
    return path


def exact(value, fields):
    if not isinstance(value, dict) or set(value) != set(fields):
        raise Refusal('missing or unknown fields')


def write(path, value):
    with Path(path).open('x', encoding='utf-8') as output:
        json.dump(value, output, sort_keys=True, separators=(',', ':'), allow_nan=False)
        output.write('\n')


REPORT_RESERVE = 65536


class BudgetExceeded(Refusal):
    pass


class ProcessFailure(Refusal):
    def __init__(self, primary, cleanup, measured, limit, discarded):
        self.accounting = {'processCleanup': cleanup, 'retainedRequestBytes': measured,
                           'requestOutputBytes': limit,
                           'requestOvershoot': max(0, measured - limit) if measured is not None else None,
                           'logsTruncated': discarded > 0, 'observedDiscardedBytes': discarded}
        super().__init__(str(primary) + '; ' + json.dumps(self.accounting, sort_keys=True))


def retained_bytes(root):
    """Logical file bytes, counted per retained name, with a bounded directory walk."""
    total = 0
    pending = [Path(root)]
    entries = 0
    while pending:
        directory = pending.pop()
        if directory.is_symlink(): raise Refusal('symlink output directory')
        with os.scandir(directory) as children:
            for child in children:
                entries += 1
                if entries > 32768: raise Refusal('output entry bound exceeded')
                info = child.stat(follow_symlinks=False)
                if stat.S_ISDIR(info.st_mode): pending.append(Path(child.path))
                elif stat.S_ISREG(info.st_mode): total += info.st_size
                else: raise Refusal('nonregular output: ' + child.name)
    return total


class EvidenceBudget:
    """One accounting owner for every request and retained operation artifact.

    This checks acceptance, not disk quotas. Failed raw files are never rewritten.
    The report reserve belongs to the operation, outside normal request capacity.
    """
    def __init__(self, root, limit, reserve=REPORT_RESERVE):
        self.root, self.limit, self.reserve = Path(root), limit, reserve
        self.exceeded = None

    def available(self, final=False):
        return max(0, self.limit - (0 if final else self.reserve) - retained_bytes(self.root))

    def audit(self, directory=None, request_limit=None, final=False):
        total = retained_bytes(self.root)
        request_size = retained_bytes(directory) if directory is not None else 0
        ceiling = self.limit if final else self.limit - self.reserve
        if total > ceiling or (request_limit is not None and request_size > request_limit):
            self.exceeded = {'retainedBytes': total, 'totalOutputBytes': self.limit,
                             'requestBytes': request_size, 'outputBytes': request_limit,
                             'observedOvershoot': max(0, total - self.limit,
                                 request_size - (request_limit or request_size))}
            raise BudgetExceeded('runner output bound exceeded: ' + json.dumps(self.exceeded, sort_keys=True))
        return total

    def write(self, path, value, final=False):
        # Objects originate from bounded project/receipt inputs. Encode incrementally,
        # stopping at the remaining retention allowance before publishing any file.
        available = self.available(final)
        chunks, size = [], 1
        for chunk in json.JSONEncoder(sort_keys=True, separators=(',', ':'), allow_nan=False).iterencode(value):
            chunk = chunk.encode('utf-8')
            size += len(chunk)
            if size > available: raise BudgetExceeded('host evidence output budget exhausted')
            chunks.append(chunk)
        if size > available: raise BudgetExceeded('host evidence output budget exhausted')
        with Path(path).open('xb') as stream:
            for chunk in chunks: stream.write(chunk)
            stream.write(b'\n')
        self.audit(final=final)


def _group_alive(group):
    for item in Path('/proc').iterdir():
        if not item.name.isdigit(): continue
        try:
            status = (item / 'stat').read_text().rsplit(')', 1)[1].split()
            if int(status[2]) == group and status[0] != 'Z': return True
        except (OSError, ValueError, IndexError): pass
    return False


_ACTIVE_PROCESS_CANCELLATION = None


def cancel_operation(_signal, _frame):
    """CLI main-thread signal callback; an active owner checks cancellation itself."""
    current = _ACTIVE_PROCESS_CANCELLATION
    if current is None:
        raise Refusal('operation cancelled')
    current.cancelled = True


class _OwnedCancellation:
    """Register before acquisition, including the entire cleanup entry/prologue.

    Signals only record a flag while an owned operation is active. Ordinary
    execution checks it; cleanup completes without signal-raised exceptions.
    No signal handler/mask changes or detached cleanup threads are needed.
    """
    def __init__(self):
        self.cancelled = False
        self.accounting = None

    def __enter__(self):
        global _ACTIVE_PROCESS_CANCELLATION
        self.previous = _ACTIVE_PROCESS_CANCELLATION
        _ACTIVE_PROCESS_CANCELLATION = self
        return self

    def __exit__(self, exception_type, _exception, _traceback):
        global _ACTIVE_PROCESS_CANCELLATION
        _ACTIVE_PROCESS_CANCELLATION = self.previous
        # Capture a late flag received after the worker's last cancellation check
        # but before ownership ended. An existing primary exception wins.
        if exception_type is None and self.cancelled:
            raise ProcessFailure(Refusal('operation cancelled'), *self.accounting)

    def check(self):
        if self.cancelled:
            raise Refusal('operation cancelled')


def owned_process(command, directory, timeout, max_bytes, budget=None, accepted_exits=(0,), input_path=None):
    """Run one non-detaching process group, bound stream retention, audit all files."""
    with _OwnedCancellation() as cancellation:
        return _run_owned_process(command, directory, timeout, max_bytes, budget, cancellation, accepted_exits, input_path)


def _run_owned_process(command, directory, timeout, max_bytes, budget, cancellation, accepted_exits, input_path):
    directory = Path(directory)
    budget = budget or EvidenceBudget(directory, max_bytes, reserve=0)
    logs = [directory / 'stdout.log', directory / 'stderr.log']
    handles = [p.open('xb') for p in logs]
    child = None
    input_handle = None
    selector = selectors.DefaultSelector()
    deadline = time.monotonic() + timeout
    primary = None
    cleanup = 'confirmed'
    discarded = 0
    try:
        cancellation.check()
        budget.audit(directory, max_bytes)
        if input_path is not None:
            selected_input = regular(input_path)
            if selected_input.stat().st_size > max_bytes: raise Refusal('owned input stream exceeds operation bound')
            input_handle = selected_input.open('rb')
        child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            stdin=input_handle, cwd=directory, start_new_session=True,
            env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C.UTF-8', 'PYTHONDONTWRITEBYTECODE': '1'})
        for pipe, handle in zip([child.stdout, child.stderr], handles):
            os.set_blocking(pipe.fileno(), False)
            selector.register(pipe, selectors.EVENT_READ, handle)
        while True:
            cancellation.check()
            for key, _ in selector.select(0.01):
                block = os.read(key.fileobj.fileno(), 65536)
                if not block:
                    selector.unregister(key.fileobj)
                    key.fileobj.close()
                    continue
                available = min(max_bytes - retained_bytes(directory), budget.available())
                retained = max(0, min(len(block), available))
                key.data.write(block[:retained]); key.data.flush()
                if retained < len(block):
                    discarded += len(block) - retained
                    raise BudgetExceeded('runner output stream bound exceeded; discardedBytes=' + str(discarded))
            budget.audit(directory, max_bytes)
            exited = child.poll() is not None
            if exited:
                if _group_alive(child.pid): raise Refusal('runner exited with live owned descendants')
                if not selector.get_map(): break
            if time.monotonic() >= deadline: raise Refusal('runner timeout')
        if child.returncode not in accepted_exits: raise Refusal('runner failed: ' + str(child.returncode))
    except (Refusal, OSError, subprocess.SubprocessError) as error:
        primary = error
    finally:
        if input_handle is not None: input_handle.close()
        if child is not None:
            for sig in [signal.SIGTERM, signal.SIGKILL]:
                try: os.killpg(child.pid, sig)
                except ProcessLookupError: pass
                try: child.wait(timeout=0.2)
                except subprocess.TimeoutExpired: pass
            child.wait()
            cleanup_deadline = time.monotonic() + 0.5
            while _group_alive(child.pid) and time.monotonic() < cleanup_deadline:
                time.sleep(0.01)
            if _group_alive(child.pid): cleanup = 'incomplete'
        # Drain any buffered bytes without blocking or growing retained logs.
        for key in list(selector.get_map().values()):
            try:
                drain_deadline = time.monotonic() + 0.2
                while time.monotonic() < drain_deadline:
                    block = os.read(key.fileobj.fileno(), 65536)
                    if not block: break
                    available = min(max_bytes - retained_bytes(directory), budget.available())
                    retained = max(0, min(len(block), available))
                    key.data.write(block[:retained]); key.data.flush()
                    discarded += len(block) - retained
            except BlockingIOError: pass
            finally: key.fileobj.close()
        selector.close()
        for handle in handles: handle.close()
        try: budget.audit(directory, max_bytes)
        except (Refusal, OSError) as error:
            if primary is None: primary = error
        if discarded and primary is None:
            primary = BudgetExceeded('runner output stream bound exceeded; discardedBytes=' + str(discarded))
        try: measured = retained_bytes(directory)
        except (Refusal, OSError): measured = None
        cancellation.accounting = (cleanup, measured, max_bytes, discarded)
        if cancellation.cancelled and primary is None:
            primary = Refusal('operation cancelled')
        if primary is not None:
            raise ProcessFailure(primary, cleanup, measured, max_bytes, discarded)
        if cleanup != 'confirmed': raise Refusal('owned process cleanup incomplete')
    return child.returncode


class Project:
    def __init__(self, path, expected, policy):
        self.path = regular(path)
        self.root = self.path.parent
        if sha(self.path) != expected: raise Refusal('project digest differs from trusted selection')
        self.digest = expected
        self.data = strict(self.path, 4 * 1024 * 1024)
        plan = subprocess.run([str(policy), '_plan', str(self.path)], capture_output=True,
                              timeout=30, check=False)
        if plan.returncode: raise Refusal('project admission: ' + plan.stderr.decode(errors='replace'))
        self.plan = json.loads(plan.stdout)
        self.candidates = {c['id']: c for c in self.data['candidates']}
        self.seen = set()
        self.checked = {}
        self.check()
        declared = {str(self.resolve(r['path'])) for r in self.data['artifacts']}
        command = self.data['command']
        def admitted(value):
            path = str(self.resolve(value))
            if path not in declared: raise Refusal('runner command is outside admitted artifact closure')
            return path
        executable = admitted(command['executable'])
        if not os.access(executable, os.X_OK): raise Refusal('runner is not executable')
        self.command = [executable]
        if command['kind'] == 'python-isolated':
            self.command += ['-I', '-S', '-B', admitted(command['script'])]
        self.command += [admitted(arg['artifact']) if 'artifact' in arg else arg['literal']
                         for arg in command['args']]
        self.policy = Path(policy)
        self.budget = None
        self.value_checks = 0
        self.oracles = {}

    def begin(self, output):
        reserve = REPORT_RESERVE + self.data['limits']['attempts'] * 1024
        require(self.data['limits']['totalOutputBytes'] > reserve, 'operation budget cannot reserve final report')
        self.budget = EvidenceBudget(output, self.data['limits']['totalOutputBytes'], reserve)

    def write(self, path, value, final=False):
        if self.budget is None: raise Refusal('operation evidence budget not initialized')
        self.budget.write(path, value, final)

    def record_failure(self, error):
        if self.budget is None: return
        path = self.budget.root / 'result.json'
        if path.exists(): return
        try:
            before = retained_bytes(self.budget.root)
            report = {'schema': 'mirrors.dpm-refusal/v1', 'status': 'incomplete',
                      'failure': str(error)[:4096], 'projectSha256': self.digest,
                      'retainedBytes': before, 'totalOutputBytes': self.budget.limit,
                      'observedOvershoot': max(0, before - self.budget.limit),
                      'accounting': 'failed-evidence-retained-not-a-disk-quota',
                      'process': getattr(error, 'accounting', {'processCleanup': 'unknown'})}
            # Failed direct writes can already exceed the limit. Preserve them and
            # add only this reserved bounded diagnostic; never claim acceptance.
            for _ in range(8):
                raw = (json.dumps(report, sort_keys=True, separators=(',', ':')) + '\n').encode()
                total = before + len(raw)
                if report['retainedBytes'] == total: break
                report['retainedBytes'] = total
                report['observedOvershoot'] = max(0, total - self.budget.limit)
            require(len(raw) <= REPORT_RESERVE, 'failure report reserve exceeded')
            with path.open('xb') as output: output.write(raw)
        except (OSError, Refusal, ValueError):
            # The caller also emits the primary reason to stderr.
            pass

    def resolve(self, path):
        p = Path(path)
        if not p.is_absolute():
            if '..' in p.parts: raise Refusal('relative artifact escapes project')
            p = self.root / p
        return p.absolute()

    def artifact(self, ref):
        exact(ref, ['path', 'sha256'])
        path = regular(self.resolve(ref['path']))
        if sha(path) != ref['sha256']: raise Refusal('artifact changed: ' + ref['path'])
        self.checked[str(path)] = ref['sha256']
        return path

    def check(self):
        if sha(self.path) != self.digest: raise Refusal('project changed during run')
        for ref in self.data['artifacts']: self.artifact(ref)
        for candidate in self.candidates.values():
            self.artifact(candidate['oracle'])
            self.artifact(candidate['provenance'])
        for path, digest in self.checked.items():
            regular(path)
            if sha(path) != digest: raise Refusal('admitted input changed during run')

    def oracle(self, candidate):
        """Verify retained remote capture and exact candidate correspondence independently."""
        oracle = self.artifact(candidate['oracle'])
        provenance = strict(self.artifact(candidate['provenance']))
        exact(provenance, ['schema', 'capture', 'model', 'oracleSha256', 'correspondence'])
        if provenance['schema'] != 'mirrors.dpm-oracle-binding/v1': raise Refusal('unknown oracle authority')
        if provenance['oracleSha256'] != candidate['oracle']['sha256']: raise Refusal('oracle binding differs')
        capture_path = self.artifact(provenance['capture'])
        model = self.artifact(provenance['model'])
        capture = strict(capture_path)
        if capture.get('schema') != 'mirrors.remote-trace-capture/v1': raise Refusal('not retained model capture')
        if not isinstance(capture.get('files'), list): raise Refusal('capture inventory missing')
        files = {}
        for ref in capture['files']:
            exact(ref, ['path', 'sha256'])
            if Path(ref['path']).is_absolute() or '..' in Path(ref['path']).parts:
                raise Refusal('capture path escapes')
            file_path = regular(capture_path.parent / ref['path'])
            if sha(file_path) != ref['sha256']: raise Refusal('capture inventory tamper')
            self.checked[str(file_path)] = ref['sha256']
            files[ref['path']] = file_path
        if not any(str(p) == str(oracle) for p in files.values()): raise Refusal('oracle absent from capture')
        request = strict(files['request.json'])
        replies = [json.loads(line) for line in files['replies.jsonl'].read_text().splitlines() if line.strip()]
        if not any(r.get('proto_step') == 'gen_traces_done' for r in replies):
            raise Refusal('remote capture has no completed trace result')
        if request.get('proto_step') != 'register_trace_gen' or request.get('spec', {}).get('sources', [None])[0] != model.read_text():
            raise Refusal('capture model source differs')
        correspondence = strict(self.artifact(provenance['correspondence']))
        exact(correspondence, ['schema', 'actionPath', 'actorPath', 'actionMap', 'initialBindings', 'ignoredActors'])
        if correspondence['schema'] != 'mirrors.dpm-trace-correspondence/v1':
            raise Refusal('unsupported trace correspondence')
        def lookup(value, keys):
            if not isinstance(keys, list) or not keys or len(keys) > 16:
                raise Refusal('invalid correspondence path')
            for key in keys:
                if not isinstance(key, str) or not isinstance(value, dict) or key not in value:
                    raise Refusal('correspondence value missing')
                value = value[key]
            return value
        def native(value):
            if isinstance(value, dict) and set(value) == {'#bigint'}:
                return int(value['#bigint'])
            return value
        schedule = candidate['schedule']
        ignored = correspondence['ignoredActors']
        if not isinstance(ignored, list) or len(ignored) > 16 or len(set(ignored)) != len(ignored):
            raise Refusal('invalid model-inert actor declaration')
        actual_steps = []
        for step in schedule['steps']:
            if step['actor'] in ignored:
                if step['checkpoint'] != '$done' or actual_steps:
                    raise Refusal('model-inert actor must finish during initialization')
            else: actual_steps.append(step)
        trace = strict(oracle)
        if not any(trace in reply.get('itfTraces', []) for reply in replies if reply.get('proto_step') == 'gen_traces_done'):
            raise Refusal('oracle differs from actual remote reply')
        states = trace.get('states')
        if not isinstance(states, list) or not states or len(states) > 4097:
            raise Refusal('oracle states unavailable')
        action_map = correspondence['actionMap']
        if not isinstance(action_map, dict) or not action_map or len(action_map) > 256:
            raise Refusal('invalid action mapping')
        expected_steps = []
        initial_action = lookup(states[0], correspondence['actionPath'])
        require(isinstance(initial_action, str), 'initial oracle model action missing')
        model_actions = [initial_action]
        for state in states[1:]:
            action = lookup(state, correspondence['actionPath'])
            if not isinstance(action, str) or action not in action_map: raise Refusal('unmapped oracle action')
            model_actions.append(action)
            expected_steps.append({'actor': lookup(state, correspondence['actorPath']),
                                   'checkpoint': action_map[action]})
        if expected_steps != actual_steps: raise Refusal('candidate/oracle step correspondence differs')
        for binding in correspondence['initialBindings']:
            exact(binding, ['inputPath', 'statePath'])
            expected_initial = native(lookup(states[0], binding['statePath']))
            actual_initial = lookup(schedule['inputs'], binding['inputPath'])
            if type(expected_initial) is not type(actual_initial) or expected_initial != actual_initial:
                raise Refusal('candidate/oracle initialization differs')
        indices = [0]
        for step in schedule['steps']:
            indices.append(indices[-1] + (0 if step['actor'] in ignored else 1))
        context = {'path': oracle, 'states': states, 'observationStateIndices': indices,
                   'modelActions': model_actions}
        self.oracles[candidate['id']] = context
        return context

    def values(self, pairs, deadline):
        results = []
        for offset in range(0, len(pairs), 4096):
            directory = self.budget.root / ('value-check-' + str(self.value_checks))
            self.value_checks += 1
            directory.mkdir()
            self.write(directory / 'input.json', {'schema': 'mirrors.dpm-value-check/v1',
                                                  'pairs': pairs[offset:offset + 4096]})
            remaining = min(30, deadline - time.monotonic())
            if remaining <= 0: raise Refusal('total time budget exhausted during value validation')
            owned_process([str(self.policy), '_value-check', str(directory / 'input.json')],
                          directory, remaining, self.data['limits']['outputBytes'], self.budget)
            result = strict(directory / 'stdout.log', self.data['limits']['outputBytes'])
            exact(result, ['schema', 'results'])
            rows = result['results']
            require(result['schema'] == 'mirrors.dpm-value-check-result/v1' and isinstance(rows, list) and
                    len(rows) == len(pairs[offset:offset + 4096]), 'typed value helper response differs')
            for row in rows:
                exact(row, ['equal', 'counterDelta'])
                require(type(row['equal']) is bool and (row['counterDelta'] is None or
                        isinstance(row['counterDelta'], str)), 'typed value helper result malformed')
            results.extend(rows)
        return results

    def request(self, operation, candidate_id, directory, deadline):
        directory.mkdir()
        self.check()
        candidate = self.candidates[candidate_id]
        self.oracle(candidate)
        request_id = uuid.uuid4().hex
        request = {'schema': 'mirrors.dpm-runner-request/v1', 'operation': operation,
                   'requestId': request_id, 'projectSha256': self.digest,
                   'project': str(self.path), 'candidateId': candidate_id}
        self.write(directory / 'request.json', request)
        remaining = min(self.data['limits']['timeoutMs'] / 1000, deadline - time.monotonic())
        if remaining <= 0: raise Refusal('total time budget exhausted')
        owned_process(self.command + ['--request', str(directory / 'request.json'),
            '--response', str(directory / 'response.json')], directory, remaining,
            self.data['limits']['outputBytes'], self.budget)
        response = strict(directory / 'response.json', self.data['limits']['outputBytes'])
        exact(response, ['schema', 'operation', 'requestId', 'projectSha256', 'candidateId', 'result'])
        if (response['schema'] != 'mirrors.dpm-runner-response/v1' or
            any(response[k] != request[k] for k in ['operation', 'requestId', 'projectSha256', 'candidateId'])):
            raise Refusal('stale or unrelated runner response')
        self.check()
        return response['result']

    def replay(self, candidate_id, directory, deadline):
        directory.mkdir()
        candidate = self.candidates[candidate_id]
        materialized = self.request('materialize', candidate_id, directory / 'materialize', deadline)
        if not same_json(materialized, {'schedule': candidate['schedule'], 'oracle': candidate['oracle'],
                                       'provenance': candidate['provenance']}):
            raise Refusal('materializer changed admitted candidate')
        result = self.request('replay', candidate_id, directory / 'replay', deadline)
        verdict, fingerprint, ids = classify(result, candidate, self.data['signature'],
            self.oracles[candidate_id], lambda pairs: self.values(pairs, deadline))
        if any(i in self.seen for i in ids): raise Refusal('execution identity reused')
        self.seen.update(ids)
        return verdict, fingerprint, result


def require(condition, message):
    if not condition: raise Refusal(message)


def same_json(left, right):
    """Structural JSON identity, without Python's Boolean/integer coercion."""
    return json.dumps(left, sort_keys=True, separators=(',', ':'), allow_nan=False) == json.dumps(
        right, sort_keys=True, separators=(',', ':'), allow_nan=False)


def text_id(value):
    return isinstance(value, str) and 0 < len(value.encode('utf-8')) <= 128 and '\x00' not in value


def validate_execution(execution, schedule, complete):
    """Check the actual SDK event sequence; return its consecutive observed prefix."""
    require(isinstance(execution, dict) and isinstance(schedule, dict), 'execution/schedule object required')
    profile = schedule.get('profile')
    cpp = profile == 'mirrorcpp.cooperative-checkpoints/v1'
    require(profile in ['mirrorcpp.cooperative-checkpoints/v1', 'mirrorecma.worker-checkpoints/v1',
                        'mirrorrust.cooperative-checkpoints/v1'], 'unknown execution profile')
    expected_schema = 'mirrors.checkpoint-replay/v1' if cpp else 'mirrors.checkpoint-execution/v1'
    require(execution.get('schema') == expected_schema and
            type(execution.get('generation')) is int and execution['generation'] > 0,
            'unsupported or malformed SDK execution')
    require(text_id(execution.get('executionId')), 'fresh execution identity missing')
    require(same_json(execution.get('schedule'), schedule), 'actual execution differs from candidate')
    require(schedule.get('schema') == 'mirrors.checkpoint-schedule/v1', 'invalid embedded schedule schema')
    identity = schedule.get('identity')
    require(isinstance(identity, dict) and set(identity) == {'implementationSha256', 'mappingSha256', 'modelSemanticDigest'}
            and all(isinstance(v, str) and len(v) == 64 and all(c in '0123456789abcdef' for c in v)
                    for v in identity.values()), 'invalid embedded identity')
    steps = schedule.get('steps')
    require(isinstance(steps, list) and 0 < len(steps) <= 65536, 'invalid execution step count')
    actors = execution.get('actors')
    require(isinstance(actors, list) and 0 < len(actors) <= 1024, 'actor declarations missing')
    declared = {}
    for actor in actors:
        exact(actor, ['actor', 'operation'])
        require(text_id(actor['actor']) and text_id(actor['operation']) and actor['actor'] not in declared,
                'invalid or duplicate actor declaration')
        declared[actor['actor']] = actor['operation']
    require(cpp or len(set(declared.values())) == len(declared), 'duplicate operation declaration')
    checkpoints = execution.get('checkpoints')
    require(isinstance(checkpoints, list) and all(text_id(c) and not c.startswith('$') for c in checkpoints)
            and len(checkpoints) == len(set(checkpoints)), 'invalid checkpoint declarations')
    selected = set()
    finished = set()
    for step in steps:
        exact(step, ['actor', 'checkpoint'])
        actor, checkpoint = step['actor'], step['checkpoint']
        require(text_id(actor) and text_id(checkpoint) and actor in declared and actor not in finished and
                (checkpoint == '$done' or checkpoint in checkpoints), 'invalid admitted execution step')
        selected.add(actor)
        if checkpoint == '$done': finished.add(actor)
    require(selected == finished == set(declared), 'actor declarations differ from complete schedule')
    if not cpp:
        threads = execution.get('actorThreads')
        require(isinstance(threads, dict) and set(threads) == set(declared), 'actor thread evidence incomplete')
        valid_thread = (lambda value: type(value) is int and value > 0) if profile.startswith('mirrorecma.') else text_id
        require(all(valid_thread(value) for value in threads.values()) and
                len(set(threads.values())) == len(threads), 'actor thread identities invalid')
    require(execution.get('coverage') == 'recorded-schedule-only', 'unknown execution coverage')
    require(execution.get('cleanup') == 'confirmed' and execution.get('remainingActors') == [],
            'SDK cleanup unconfirmed')
    attempts = execution.get('cleanupAttempts')
    require(isinstance(attempts, list) and 0 < len(attempts) <= 4096, 'cleanup attempts missing')
    cleanup_key = 'status' if cpp else 'cleanup'
    for attempt in attempts:
        require(isinstance(attempt, dict) and attempt.get(cleanup_key) in
                ['confirmed', 'incomplete', 'teardown_failed'] and isinstance(attempt.get('remainingActors'), list),
                'malformed cleanup attempt')
    last = attempts[-1]
    require(last.get(cleanup_key) == 'confirmed' and last.get('remainingActors') == [] and
            not last.get('error') and not last.get('detail'), 'final cleanup attempt contradicts confirmation')
    require(type(execution.get('passed')) is bool and type(execution.get('scheduleCompleted')) is bool,
            'completion flags must be Boolean')
    require(execution.get('outcome') in ['completed', 'cancelled'], 'execution primary failure: ' + str(execution.get('outcome')))
    if 'budgetExceeded' in execution:
        flags = execution['budgetExceeded']
        require(isinstance(flags, dict) and flags and all(v is False for v in flags.values()), 'execution budget exceeded')
    events, observations = execution.get('events'), execution.get('observations')
    require(isinstance(events, list) and len(events) % 2 == 0 and len(events) <= 2 * len(steps),
            'unpaired or excessive execution events')
    length = len(events) // 2
    previous = {actor: '$start' for actor in declared}
    for index in range(length):
        step = steps[index]
        actor = step['actor']
        for offset, kind, checkpoint in [(0, 'permit', previous[actor]), (1, 'arrival', step['checkpoint'])]:
            event = events[2 * index + offset]
            require(isinstance(event, dict) and type(event.get('ordinal')) is int and
                    event['ordinal'] == 2 * index + offset and type(event.get('step')) is int and
                    event['step'] == index and event.get('kind') == kind and event.get('actor') == actor and
                    event.get('operation') == declared[actor] and event.get('checkpoint') == checkpoint,
                    'event/permit/arrival differs from actual scheduled interval')
        previous[actor] = step['checkpoint']
    require(isinstance(observations, list) and len(observations) == length + 1,
            'execution observations must cover the consecutive prefix')
    states = []
    for after, observation in enumerate(observations):
        require(isinstance(observation, dict) and type(observation.get('afterSteps')) is int and
                observation['afterSteps'] == after and isinstance(observation.get('state'), dict),
                'observation index or state malformed')
        states.append(observation['state'])
    full = length == len(steps)
    if complete or execution['passed'] or execution['scheduleCompleted']:
        require(full and execution['passed'] is True and execution['scheduleCompleted'] is True and
                execution['outcome'] == 'completed', 'incomplete or contradictory passing execution')
    else:
        require(not full and execution['passed'] is False and execution['scheduleCompleted'] is False and
                execution['outcome'] == ('completed' if cpp else 'cancelled'),
                'comparison prefix outcome differs from SDK profile')
    return {'executionId': execution['executionId'], 'length': length, 'states': states,
            'steps': steps, 'actors': declared, 'complete': full}


def classify(receipt, candidate, signature, oracle=None, value_check=None):
    require(isinstance(receipt, dict) and receipt.get('schema') == 'mirrors.scheduled-comparison/v1',
            'comparison receipt required')
    require(oracle is not None and value_check is not None, 'checked oracle and typed value checker required')
    binding = receipt.get('binding')
    require(isinstance(binding, dict), 'binding evidence missing')
    executions = binding.get('executions')
    require(binding.get('schema') == 'mirrors.scheduled-binding/v1' and binding.get('disposed') is True and
            binding.get('receiptComplete') is True and type(binding.get('initializations')) is int and
            binding['initializations'] == 1 and type(binding.get('disposals')) is int and binding['disposals'] == 1 and
            isinstance(executions, list) and len(executions) == 1, 'binding evidence incomplete')
    comparison = receipt.get('comparison')
    require(comparison in ['matched', 'step_mismatch'], 'comparison incomplete or contradictory')
    checked = validate_execution(executions[0], candidate['schedule'], comparison == 'matched')
    if 'actualIdentity' in receipt:
        require(same_json(receipt['actualIdentity'], candidate['schedule']['identity']), 'comparison actual identity differs')
    raw_terminal = receipt.get('peerTerminalRaw')
    require(isinstance(raw_terminal, str) and len(raw_terminal.encode('utf-8')) <= 32*1024*1024,
            'actual peer terminal missing')
    terminal = strict_bytes(raw_terminal)
    require(isinstance(terminal, dict), 'actual peer terminal object required')
    client = receipt.get('client')
    require(isinstance(client, dict) and not client.get('cleanupError'), 'client cleanup failure or missing client')
    states = checked['states']
    indices = oracle['observationStateIndices']
    require(len(indices) == len(checked['steps']) + 1, 'oracle observation correspondence incomplete')
    pairs = [{'expected': oracle['states'][indices[index]], 'actual': state, 'mode': 'model'}
             for index, state in enumerate(states)]
    if comparison == 'matched':
        exact(terminal, ['proto_step'])
        require(not any(client.get(key) for key in ['kind', 'error', 'expected', 'actual']), 'successful client carries failure facts')
        if 'report' in client:
            report = client['report']
            require(isinstance(report, dict) and report.get('status') == 'completed' and
                    type(report.get('acceptedTraces')) is int and report['acceptedTraces'] == 1 and
                    type(report.get('acceptedSteps')) is int and report['acceptedSteps'] == indices[-1],
                    'successful client report contradicts oracle completion')
        require(terminal.get('proto_step') == 'all_steps_done' and receipt.get('peerTerminal') == 'all_steps_done' and
                receipt.get('passed') is True and client.get('status') == 'succeeded',
                'match evidence contradicts completion')
        require(all(row['equal'] for row in value_check(pairs)), 'observed execution differs from admitted oracle')
        return 'matched', None, [checked['executionId']]
    require(terminal.get('proto_step') == 'step_mismatch' and receipt.get('peerTerminal') == 'step_mismatch' and
            receipt.get('passed') is False and client.get('status') == 'failed' and client.get('kind') == 'step_mismatch',
            'comparison incomplete or contradictory')
    expected, actual = terminal.get('expected'), terminal.get('actual')
    require(isinstance(expected, dict) and isinstance(actual, dict), 'mismatch states missing')
    after = checked['length']
    initial_mismatch = after == 0 and indices[0] == 0
    require((initial_mismatch and signature == 'exact-terminal/v1') or
            (after > 0 and indices[after] > indices[after - 1]),
            'mismatch has no eligible initial observation or actual model interval')
    if 'stateIndex' in client:
        require(type(client['stateIndex']) is int and client['stateIndex'] == indices[after], 'client mismatch state index differs')
    if 'traceIndex' in client:
        require(type(client['traceIndex']) is int and client['traceIndex'] == 0, 'client mismatch trace index differs')
    if 'action' in client:
        actions = oracle.get('modelActions')
        require(isinstance(actions, list) and len(actions) == len(oracle['states']) and
                client['action'] == actions[indices[after]], 'client mismatch model action differs')
    pairs += [
        {'expected': oracle['states'][indices[after]], 'actual': expected, 'mode': 'model'},
        {'expected': states[-1], 'actual': actual, 'mode': 'exact'},
        {'expected': expected, 'actual': client.get('expected'), 'mode': 'exact'},
        {'expected': actual, 'actual': client.get('actual'), 'mode': 'exact'},
        {'expected': expected, 'actual': actual, 'mode': 'counter' if signature == 'counter-count-delta/v1' else 'exact'}]
    comparisons = value_check(pairs)
    model = comparisons[:len(states)]
    require(all(row['equal'] for row in model[:-1]) and model[-1]['equal'] is False,
            'mismatch does not follow an oracle-matching observed prefix')
    require(all(row['equal'] for row in comparisons[len(states):-1]), 'terminal/client/oracle/observation states differ')
    require(comparisons[-1]['equal'] is False, 'mismatch states are equal')
    if signature == 'counter-count-delta/v1':
        delta = comparisons[-1]['counterDelta']
        require(delta is not None and checked['steps'][after - 1]['checkpoint'] == 'write',
                'counter normalization refuses unrelated mismatch')
        fingerprint = {'profile': signature, 'action': 'write', 'path': ['count'], 'delta': delta}
    else:
        require(signature == 'exact-terminal/v1', 'unsupported failure signature')
        fingerprint = {'profile': signature, 'expected': expected, 'actual': actual,
                       'checkpoint': checked['steps'][after - 1]['checkpoint'] if after else None}
    return 'step_mismatch', fingerprint, [checked['executionId']]


def validate_exploration(receipt, value_check=None, seen=None, profile=None, expected_identity=None):
    require(isinstance(receipt, dict) and receipt.get('schema') == 'mirrors.finite-exploration/v1',
            'SDK exploration receipt required')
    require(value_check is not None, 'typed exploration value checker required')
    require(expected_identity is not None, 'selected explorer identity required')
    require(type(receipt.get('complete')) is bool and receipt.get('comparison') == 'not_requested' and
            receipt.get('comparisonRequired') is False and type(receipt.get('comparisonRuns')) is int and
            receipt['comparisonRuns'] == 0, 'local explorer returned unexpected comparison authority')
    runs = receipt.get('runs')
    require(isinstance(runs, list) and len(runs) <= 4096 and type(receipt.get('attemptedRuns')) is int and
            len(runs) == receipt['attemptedRuns'], 'exploration run denominator differs')
    seen = set() if seen is None else seen
    new_ids = set()
    pairs = []
    identity = expected_identity
    seen_schedules = set()
    shapes_by_input = {}
    observed_categories = {}
    expected_chains = None
    inputs = receipt.get('declaredInputs')
    require(isinstance(inputs, list) and inputs and all(isinstance(value, dict) for value in inputs),
            'exploration input declarations missing')
    counts = ['eligibleRunsLowerBound', 'enumeratedScheduleShapes', 'inputAssignments', 'completedRuns']
    require(all(type(receipt.get(name)) is int and receipt[name] >= 0 for name in counts),
            'invalid exploration denominator counts')
    require(type(receipt.get('denominatorKnown')) is bool and type(receipt.get('enumerationExhausted')) is bool,
            'invalid exploration denominator flags')
    assignments, shapes = receipt['inputAssignments'], receipt['enumeratedScheduleShapes']
    lower = receipt['eligibleRunsLowerBound']
    require(assignments == len(inputs) and lower == shapes * assignments and
            receipt['completedRuns'] <= len(runs) <= lower,
            'exploration denominator contradicts declared shapes/inputs/attempts')
    if receipt['denominatorKnown']:
        require(type(receipt.get('eligibleRuns')) is int and receipt['eligibleRuns'] == lower,
                'known exploration denominator differs from lower bound')
    else:
        require(receipt.get('eligibleRuns') is None and not receipt['enumerationExhausted'],
                'unknown exploration denominator contradicts exhaustion')
    if receipt['enumerationExhausted']:
        require(receipt['denominatorKnown'] and len(runs) == lower,
                'exhausted exploration omits eligible runs')
    categories = receipt.get('categories')
    require(isinstance(categories, dict) and all(text_id(key) and type(count) is int and count >= 0
            for key, count in categories.items()) and sum(categories.values()) == len(runs),
            'exploration category counts contradict attempts')
    require(receipt['completedRuns'] == categories.get('passed', 0),
            'exploration completed count contradicts passed category')
    require(text_id(receipt.get('stopReason')) and receipt.get('status') ==
            ('complete' if receipt['complete'] else 'incomplete'), 'exploration stop/status facts malformed')
    if receipt['complete']:
        require(bool(runs) and receipt['stopReason'] == 'complete' and
                receipt.get('firstFailure') is None and receipt.get('firstCounterexample') is None,
                'complete exploration is empty or carries stop/failure facts')
    else:
        require(receipt['stopReason'] != 'complete', 'incomplete exploration claims complete stop')
    for ordinal, row in enumerate(runs):
        require(isinstance(row, dict) and type(row.get('ordinal')) is int and row['ordinal'] == ordinal,
                'exploration row ordering differs')
        schedule = row.get('schedule')
        require(isinstance(schedule, dict), 'exploration schedule missing')
        if profile is not None: require(schedule.get('profile') == profile, 'exploration profile differs')
        require(same_json(schedule.get('identity'), identity), 'exploration identity changed across runs')
        outer_profile = {'mirrorcpp.cooperative-checkpoints/v1': 'mirrorcpp.finite-checkpoint-exploration/v1',
                         'mirrorecma.worker-checkpoints/v1': 'mirrorecma.finite-checkpoint-exploration/v1',
                         'mirrorrust.cooperative-checkpoints/v1': 'mirrorrust.finite-checkpoint-exploration/v1'}
        require(receipt.get('profile') == outer_profile.get(schedule.get('profile')), 'exploration profile/schema differs')
        input_index = row.get('inputIndex')
        require(type(input_index) is int and 0 <= input_index < len(inputs) and
                same_json(schedule.get('inputs'), inputs[input_index]), 'exploration input assignment differs')
        key = json.dumps(schedule, sort_keys=True, separators=(',', ':'))
        require(key not in seen_schedules, 'duplicate exploration schedule')
        seen_schedules.add(key)
        shape = json.dumps(schedule.get('steps'), sort_keys=True, separators=(',', ':'))
        shapes_by_input.setdefault(input_index, set()).add(shape)
        category = row.get('category')
        require(text_id(category), 'exploration row category missing')
        observed_categories[category] = observed_categories.get(category, 0) + 1
        checked = validate_execution(row.get('execution'), schedule, receipt['complete'])
        chains = {actor: [step['checkpoint'] for step in checked['steps'] if step['actor'] == actor]
                  for actor in checked['actors']}
        if expected_chains is None: expected_chains = chains
        require(chains == expected_chains, 'exploration actor chains changed')
        execution_id = checked['executionId']
        require(execution_id not in seen and execution_id not in new_ids, 'exploration execution reused')
        new_ids.add(execution_id)
        if receipt['complete']: require(row.get('category') == 'passed', 'complete exploration contains failed run')
        pairs += [{'expected': state, 'actual': state, 'mode': 'exact'} for state in checked['states']]
    require({key: count for key, count in categories.items() if count} == observed_categories,
            'exploration categories differ from retained run rows')
    if receipt['complete']:
        retained_shapes = set().union(*shapes_by_input.values())
        require(len(retained_shapes) == shapes and set(shapes_by_input) == set(range(assignments)) and
                all(value == retained_shapes for value in shapes_by_input.values()),
                'complete exploration omits a declared shape/input pairing')
    if 'actualIdentity' in receipt:
        require(same_json(receipt['actualIdentity'], identity), 'exploration actual identity differs')
    require(all(row['equal'] for row in value_check(pairs)), 'invalid exploration state')
    if receipt['complete']:
        require(receipt.get('denominatorKnown') is True and receipt.get('enumerationExhausted') is True and
                type(receipt.get('eligibleRuns')) is int and receipt['eligibleRuns'] == len(runs) and
                type(receipt.get('completedRuns')) is int and receipt['completedRuns'] == len(runs) and
                receipt.get('status') == 'complete', 'complete exploration lacks exhaustive denominator')
    seen.update(new_ids)


def reduce(project, output):
    deadline = time.monotonic() + project.data['limits']['totalTimeoutMs'] / 1000
    baseline = project.data['baseline']
    first = project.replay(baseline, output / 'baseline-0', deadline)
    # Exact-terminal fingerprints can contain large states. Reserve their actual
    # serialized size in addition to bounded report/trial metadata before acquiring again.
    project.budget.reserve += len(json.dumps(first[1], sort_keys=True, separators=(',', ':')).encode('utf-8'))
    project.budget.audit()
    second = project.replay(baseline, output / 'baseline-1', deadline)
    if first[0] != 'step_mismatch' or not same_json(first[:2], second[:2]): raise Refusal('baseline is not a stable failure')
    order = project.plan['order']
    costs = {r['id']: r['cost'] for r in order}
    best = baseline
    trials = []
    complete = True
    failure = None
    for row in order:
        candidate_id = row['id']
        if candidate_id == baseline or costs[candidate_id] >= costs[baseline]: continue
        # One replay uses materialization, execution and at most two typed-check
        # requests. Reserve one worst-case trial plus the fresh best replay.
        if (len(trials) >= project.data['limits']['attempts'] or time.monotonic() >= deadline or
                project.budget.available() < (4 +
                    (len(project.candidates[candidate_id]['schedule']['steps']) + 4101) // 4096 +
                    (len(project.candidates[best]['schedule']['steps']) + 4101) // 4096) *
                    project.data['limits']['outputBytes']):
            complete = False
            break
        try:
            verdict, fingerprint, _ = project.replay(candidate_id, output / ('trial-' + str(len(trials))), deadline)
            disposition = 'same_failure' if verdict == 'step_mismatch' and same_json(fingerprint, first[1]) else verdict
            if verdict == 'step_mismatch' and not same_json(fingerprint, first[1]): disposition = 'different_failure'
            if disposition == 'same_failure' and costs[candidate_id] < costs[best]: best = candidate_id
            trials.append({'candidateId': candidate_id, 'cost': costs[candidate_id], 'disposition': disposition})
        except (Refusal, OSError, subprocess.TimeoutExpired) as error:
            failure = str(error)[:4096]
            trials.append({'candidateId': candidate_id, 'cost': costs[candidate_id], 'disposition': 'unresolved', 'detail': failure})
            complete = False
            break  # Cleanup independence or model evidence may have been lost.
    best_replay = None
    if failure is None:
        try:
            result = project.replay(best, output / 'best-replay', deadline)
            if not same_json(result[:2], first[:2]): raise Refusal('best candidate did not reproduce')
            best_replay = 'confirmed'
        except (Refusal, OSError, subprocess.TimeoutExpired) as error:
            failure = str(error); complete = False
    report = {'schema': 'mirrors.dpm-reduction/v1', 'status': 'incomplete' if failure else 'completed',
        'projectSha256': project.digest, 'baseline': baseline, 'baselineCost': costs[baseline],
        'best': best, 'bestCost': costs[best], 'signature': first[1], 'trials': trials,
        'claim': 'minimal_in_admitted_catalog' if complete else 'best_observed',
        'scope': 'admitted-catalog-only', 'bestReplay': best_replay,
        'freshModelCheck': False, 'failure': failure}
    return report, 2 if failure else 0
