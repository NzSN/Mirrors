"""Bounded remote comparison for one reviewed finite controlled-resource mapping.

Raw SDK receipts retain modelComparison:false. This separate composite result
can claim a match only after pure witness admission and actual pinned mTLS
Mirrors validation. The evaluator selects every input digest independently.
"""
import base64
import hashlib
import json
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path

PROFILE = 'mirrors.controlled-mutex-fifo-model/v1'
RESULT = 'mirrors.controlled-sync-model-comparison/v1'
HEX = re.compile(r'[0-9a-f]{64}')


def require(condition, message, refusal=ValueError):
    if not condition:
        raise refusal(message)


def closed(value, keys, description):
    require(type(value) is dict and set(value) == set(keys), description + ' has missing or unknown fields')
    return value


def digest(value):
    require(type(value) is str and HEX.fullmatch(value) is not None, 'invalid selected digest')
    return value


def mapping(value):
    closed(value, ['schema', 'profile', 'modelSourceSha256', 'implementationSha256',
                   'actors', 'resources', 'observations', 'maxDecisions'], 'controlled mapping')
    require(value['schema'] == 'mirrors.controlled-model-mapping/v1' and value['profile'] == PROFILE,
            'unsupported finite controlled mapping')
    require(value['actors'] == ['consumer', 'producer'] and value['resources'] ==
            [{'id': 'mutex', 'kind': 'mutex', 'capacity': 0}, {'id': 'queue', 'kind': 'queue', 'capacity': 1}]
            and all(type(resource['capacity']) is int for resource in value['resources'])
            and value['observations'] == ['count', 'received'] and type(value['maxDecisions']) is int
            and value['maxDecisions'] == 32, 'controlled mapping differs from the reviewed finite profile')
    digest(value['modelSourceSha256']); digest(value['implementationSha256'])
    return value


def witness_module(witness):
    closed(witness, ['schema', 'executionId', 'modelComparison', 'cost', 'actors', 'operations', 'resources',
                     'values', 'enabled', 'counts', 'received'], 'admitted witness')
    require(witness['schema'] == 'mirrors.controlled-sync-witness/v1' and witness['modelComparison'] is False,
            'witness claims comparison before model validation')
    count = len(witness['actors'])
    require(0 < count <= 32 and all(len(witness[name]) == count for name in
            ['operations', 'resources', 'values', 'enabled']) and
            len(witness['counts']) == count + 1 and len(witness['received']) == count + 1,
            'admitted witness cardinality differs')

    def text(value):
        require(type(value) is str and value.isascii() and all(32 <= ord(c) < 127 for c in value),
                'unsupported model witness text')
        return json.dumps(value, ensure_ascii=True)

    def integer(value):
        require(type(value) is int and -(2**63) <= value < 2**63, 'unsupported model witness integer')
        return str(value)

    def sequence(values, render):
        require(type(values) is list, 'model witness sequence must be an array')
        return '<<' + ','.join(render(value) for value in values) + '>>'

    def enabled(values):
        require(type(values) is list and all(type(value) is str for value in values) and
                len(values) == len(set(values)) and
                all(value in ['consumer', 'producer'] for value in values), 'invalid enabled witness')
        return '{' + ','.join(text(value) for value in sorted(values)) + '}'

    assignments = [
        ('WitnessActors', sequence(witness['actors'], text)),
        ('WitnessOperations', sequence(witness['operations'], text)),
        ('WitnessResources', sequence(witness['resources'], text)),
        ('WitnessValues', sequence(witness['values'], integer)),
        ('WitnessEnabled', sequence(witness['enabled'], enabled)),
        ('WitnessCounts', sequence(witness['counts'], integer)),
        ('WitnessReceived', sequence(witness['received'], lambda values: sequence(values, integer))),
    ]
    return ('---- MODULE ControlledWitnessCase ----\nEXTENDS ControlledMutexFifo\n'
            'ConstInit ==\n' + '\n'.join('  /\\ ' + name + ' = ' + value for name, value in assignments)
            + '\n====\n')


def timestamp(value):
    require(type(value) is str, 'missing observation timestamp')
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    require(parsed.tzinfo is not None, 'observation timestamp needs a timezone')
    return parsed


def admit_remote(config, observation, now=None):
    fields = ['schema', 'host', 'port', 'pin', 'cert', 'key', 'ca', 'observation',
              'serverExecutableSha256', 'sourceCommit', 'apalacheJarSha256', 'javaExecutableSha256', 'javaVersion']
    closed(config, fields + (['execution'] if 'execution' in config else []) +
           (['clockSkewSeconds'] if 'clockSkewSeconds' in config else []), 'selected remote configuration')
    require(config['schema'] == 'mirrors.controlled-model-remote/v1', 'unknown remote configuration')
    require(type(config['host']) is str and re.fullmatch(r'[A-Za-z0-9.-]{1,253}', config['host']) is not None
            and type(config['port']) is int and 0 < config['port'] < 65536, 'invalid remote endpoint')
    require(config['javaVersion'] in ['25.0.4+7', '25.0.4+7-LTS'], 'remote Java does not match the selected qualification runtime')
    require(type(config['sourceCommit']) is str and re.fullmatch(r'[0-9a-f]{40}', config['sourceCommit']) is not None,
            'remote source commit is not frozen')
    for name in ['pin', 'serverExecutableSha256', 'apalacheJarSha256', 'javaExecutableSha256']:
        digest(config[name])
    closed(observation, ['schema', 'host', 'port', 'serverCertificateSha256', 'serverExecutableSha256',
                         'sourceCommit', 'apalacheJarSha256', 'javaExecutableSha256', 'javaVersion',
                         'processId', 'observedAtUtc', 'certificateNotAfterUtc'], 'remote observation')
    require(observation['schema'] == 'mirrors.controlled-model-observation/v1' and
            type(observation['processId']) is int and observation['processId'] > 0 and
            type(observation['port']) is int, 'remote observation lacks an owned process or endpoint')
    for name in ['host', 'port', 'serverExecutableSha256', 'sourceCommit', 'apalacheJarSha256', 'javaExecutableSha256', 'javaVersion']:
        require(observation[name] == config[name], 'observed remote identity differs: ' + name)
    require(observation['serverCertificateSha256'] == config['pin'], 'observed TLS leaf differs from selected pin')
    now = now or datetime.now(timezone.utc)
    age = (now - timestamp(observation['observedAtUtc'])).total_seconds()
    skew = config.get('clockSkewSeconds', 0)
    require(type(skew) is int and 0 <= skew <= 5, 'unsupported remote clock tolerance')
    require(-skew <= age <= 300, 'remote observation is stale or outside the selected clock tolerance')
    require(timestamp(observation['certificateNotAfterUtc']) > now, 'remote certificate has expired')
    return observation


def ssh_execution(value):
    closed(value, ['kind', 'ssh', 'sshSha256', 'config', 'configSha256', 'alias', 'script', 'scriptSha256'],
           'in-place validator execution')
    require(value['kind'] == 'ssh-windows' and type(value['alias']) is str and
            re.fullmatch(r'[A-Za-z0-9._-]{1,64}', value['alias']) is not None, 'unsupported validator execution host')
    for name in ['sshSha256', 'configSha256', 'scriptSha256']: digest(value[name])
    require(type(value['script']) is str and re.fullmatch(r'[A-Za-z]:[/\\][A-Za-z0-9_./\\-]{1,240}', value['script']) is not None,
            'unsafe in-place validator script path')
    return value


def remote_validation(config, execution, model, query, mirror_sha, bound, output, budget, host):
    request_id = uuid.uuid4().hex
    request = {'schema': 'mirrors.controlled-model-query/v1', 'requestId': request_id,
               'modelSourceSha256': hashlib.sha256(model.encode()).hexdigest(),
               'querySourceSha256': hashlib.sha256(query.encode()).hexdigest(),
               'modelBase64': base64.b64encode(model.encode()).decode(),
               'queryBase64': base64.b64encode(query.encode()).decode(),
               'mirrorSha256': mirror_sha, 'bound': bound,
               'credentialPaths': {name: config[name] for name in ['cert', 'key', 'ca']}}
    directory = output/'relay'; directory.mkdir()
    budget.write(directory/'request.json', request)
    script = execution['script'].replace("'", "''")
    bootstrap = ("$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';"
                 "[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false);"
                 "$p='" + script + "';if((Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower() -ne '" +
                 execution['scriptSha256'] + "'){throw 'validator script differs'};& $p")
    encoded = base64.b64encode(bootstrap.encode('utf-16le')).decode()
    host.owned_process([execution['ssh'], '-F', execution['config'], '-T', '-o', 'BatchMode=yes',
                        '-o', 'ConnectTimeout=15', execution['alias'], 'powershell.exe', '-NoProfile',
                        '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', encoded],
                       directory, 120, 512*1024, budget, input_path=directory/'request.json')
    envelope = host.strict(directory/'stdout.log', 512*1024)
    closed(envelope, ['schema', 'requestId', 'modelSourceSha256', 'querySourceSha256', 'mirrorSha256',
                      'javaExecutableSha256', 'exitCode', 'stdoutBase64', 'stderrBase64', 'cleanup', 'observation'], 'remote validator receipt')
    require(envelope['schema'] == 'mirrors.controlled-model-query-result/v1' and
            envelope['requestId'] == request_id and envelope['cleanup'] == 'confirmed' and
            type(envelope['exitCode']) is int and envelope['exitCode'] in [0, 1], 'incomplete remote validator receipt')
    for name in ['modelSourceSha256', 'querySourceSha256', 'mirrorSha256']:
        require(envelope[name] == request[name], 'remote validator input identity differs: ' + name)
    require(envelope['javaExecutableSha256'] == config['javaExecutableSha256'],
            'actual remote Java identity differs from selection')
    for role in ['stdout', 'stderr']:
        raw = base64.b64decode(envelope[role+'Base64'], validate=True)
        require(len(raw) <= 256*1024 and len(raw) <= budget.available(), 'remote verdict output bound exceeded')
        with (output/'validation'/(role+'.log')).open('xb') as stream: stream.write(raw)
    budget.audit()
    return envelope['exitCode'], admit_remote(config, envelope['observation'])


def validate_result(value):
    closed(value, ['schema', 'profile', 'executionId', 'comparison', 'modelComparison', 'cleanup', 'cost',
                   'nativeReceiptSha256', 'mappingSha256', 'modelSourceSha256', 'implementationSha256',
                   'mirrorSha256', 'policySha256', 'querySourceSha256', 'observationSha256',
                   'oracle', 'artifacts'], 'controlled comparison result')
    require(value['schema'] == RESULT and value['profile'] == PROFILE and
            value['comparison'] in ['matched', 'rejected'] and value['cleanup'] == 'confirmed' and
            value['modelComparison'] is True, 'incomplete controlled comparison result')
    require(type(value['executionId']) is str and 0 < len(value['executionId']) <= 256, 'invalid execution identity')
    require(type(value['cost']) is list and len(value['cost']) == 4 and
            all(type(item) is int and 0 <= item <= 4096 for item in value['cost']) and
            value['cost'][0] == 2 and value['cost'][1] == 0, 'invalid finite catalog cost')
    for name in ['nativeReceiptSha256', 'mappingSha256', 'modelSourceSha256', 'implementationSha256',
                 'mirrorSha256', 'policySha256', 'querySourceSha256', 'observationSha256']:
        digest(value[name])
    oracle = closed(value['oracle'], ['transport', 'host', 'port', 'pin', 'verdict', 'exitCode',
                                      'serverExecutableSha256', 'sourceCommit', 'apalacheJarSha256',
                                      'javaExecutableSha256', 'javaVersion', 'observedAtUtc', 'clockSkewSeconds'], 'comparison oracle')
    require(oracle['transport'] == 'mtls' and
            type(oracle['exitCode']) is int and type(oracle['port']) is int and
            0 < oracle['port'] < 65536 and
            ((value['comparison'] == 'matched' and oracle['verdict'] == 'valid' and oracle['exitCode'] == 0)
             or (value['comparison'] == 'rejected' and oracle['verdict'] == 'invalid' and oracle['exitCode'] == 1)),
            'remote verdict and comparison disagree')
    require(type(oracle['clockSkewSeconds']) is int and 0 <= oracle['clockSkewSeconds'] <= 5,
            'unsupported retained clock tolerance')
    for name in ['pin', 'serverExecutableSha256', 'apalacheJarSha256', 'javaExecutableSha256']:
        digest(oracle[name])
    require(type(oracle['sourceCommit']) is str and re.fullmatch(r'[0-9a-f]{40}', oracle['sourceCommit']) is not None
            and oracle['javaVersion'] in ['25.0.4+7', '25.0.4+7-LTS'], 'unsupported oracle identity')
    roles = {'admission.json', 'admission/stdout.log', 'admission/stderr.log', 'witness.json',
             'native-receipt.json', 'mapping.json', 'remote-observation.json',
             'model/ControlledMutexFifo.tla', 'model/ControlledWitnessCase.tla',
             'validation/stdout.log', 'validation/stderr.log'}
    actual_roles = set(value['artifacts']) if type(value['artifacts']) is dict else set()
    relay_roles = {'relay/request.json', 'relay/stdout.log', 'relay/stderr.log'}
    require(actual_roles in [roles, roles | relay_roles], 'invalid comparison artifact inventory')
    for name, selected in value['artifacts'].items():
        path = Path(name)
        require(not path.is_absolute() and path.parts and '..' not in path.parts, 'unsafe comparison artifact path')
        digest(selected)
    for artifact, selected in [('native-receipt.json', 'nativeReceiptSha256'), ('mapping.json', 'mappingSha256'),
                               ('remote-observation.json', 'observationSha256'),
                               ('model/ControlledMutexFifo.tla', 'modelSourceSha256'),
                               ('model/ControlledWitnessCase.tla', 'querySourceSha256')]:
        require(value['artifacts'][artifact] == value[selected], 'comparison artifact identity disagrees: ' + artifact)
    return value


def compare(args, policy, host):
    paths = {name: host.regular(getattr(args, name)) for name in
             ['receipt', 'mapping', 'model', 'implementation', 'mirror', 'remote']}
    for name in ['receipt', 'mapping', 'mirror', 'remote']:
        require(host.sha(paths[name]) == digest(getattr(args, name + '_sha256')),
                'selected ' + name + ' digest differs', host.Refusal)
    selected = mapping(host.strict(paths['mapping'], 16384))
    require(host.sha(paths['model']) == selected['modelSourceSha256'] and
            host.sha(paths['implementation']) == selected['implementationSha256'], 'selected model or implementation differs', host.Refusal)
    config = host.strict(paths['remote'], 16384)
    observation_path = host.regular(config.get('observation', ''))
    observed = host.strict(observation_path, 16384)
    execution = ssh_execution(config['execution']) if 'execution' in config else None
    if execution:
        # The fixed remote helper reobserves the owned endpoint before use and
        # returns a fresh observation. Credentials remain on that same host.
        admit_remote(config, observed, now=timestamp(observed['observedAtUtc']))
        credentials = []
        ssh = host.regular(execution['ssh']); ssh_config = host.regular(execution['config'])
        require(host.sha(ssh) == execution['sshSha256'] and host.sha(ssh_config) == execution['configSha256'],
                'selected SSH runtime or configuration differs', host.Refusal)
        extra = [ssh, ssh_config]
    else:
        observed = admit_remote(config, observed)
        credentials = [host.regular(config[name]) for name in ['cert', 'key', 'ca']]
        extra = []
    frozen = {path: host.sha(path) for path in [*paths.values(), observation_path, *credentials, *extra, Path(policy)]}
    output = args.out.absolute()
    output.mkdir(parents=True, exist_ok=False)
    budget = host.EvidenceBudget(output, 2*1024*1024, reserve=16384)
    copies = [('native-receipt.json', paths['receipt']), ('mapping.json', paths['mapping'])]
    if not execution: copies.append(('remote-observation.json', observation_path))
    for name, source in copies:
        raw = source.read_bytes()
        require(len(raw) <= budget.available(), 'comparison input exceeds evidence budget', host.Refusal)
        with (output/name).open('xb') as stream:
            stream.write(raw)
        budget.audit()
    request = {'schema': 'mirrors.controlled-sync-check/v1', 'identity': {
        'modelSemanticDigest': selected['modelSourceSha256'], 'mappingSha256': args.mapping_sha256,
        'implementationSha256': selected['implementationSha256']}, 'receipt': host.strict(paths['receipt'], 1024*1024)}
    budget.write(output/'admission.json', request)
    admission = output/'admission'; admission.mkdir()
    host.owned_process([str(policy), '_sync-check', str(output/'admission.json')], admission, 30, 1024*1024, budget)
    witness = host.strict(admission/'stdout.log', 1024*1024)
    query = witness_module(witness)
    model = paths['model'].read_bytes().decode('utf-8')
    require(len(json.dumps([model, query], ensure_ascii=False).encode()) <= 48*1024,
            'model witness exceeds the inline request budget', host.Refusal)
    directory = output/'model'; directory.mkdir()
    (directory/'ControlledMutexFifo.tla').write_bytes(model.encode('utf-8'))
    (directory/'ControlledWitnessCase.tla').write_text(query, encoding='utf-8')
    budget.write(output/'witness.json', witness)
    validation = output/'validation'; validation.mkdir()
    if execution:
        code, observed = remote_validation(config, execution, model, query, args.mirror_sha256,
                                            len(witness['actors'])+1, output, budget, host)
        budget.write(output/'remote-observation.json', observed)
    else:
        command = [str(paths['mirror']), 'validate', '--host', config['host'], '--port', str(config['port']),
                   '--tls', '--pin', config['pin'], '--cert', str(credentials[0]), '--key', str(credentials[1]),
                   '--ca', str(credentials[2]), '--spec', str(directory/'ControlledWitnessCase.tla'),
                   '--cinit', 'ConstInit', '--init', 'Init', '--next', 'Next', '--inv', 'Conforms',
                   '--bound', str(len(witness['actors'])+1), '--async']
        code = host.owned_process(command, validation, 90, 256*1024, budget, accepted_exits=(0, 1))
    stdout = (validation/'stdout.log').read_text(encoding='utf-8')
    require((code == 0 and stdout.strip() == 'VALID') or (code == 1 and stdout.startswith('INVALID\n')),
            'remote validator did not return the expected model verdict', host.Refusal)
    for path, expected in frozen.items():
        require(host.sha(path) == expected, 'selected comparison input changed during execution', host.Refusal)
    admit_remote(config, observed)
    artifacts = {str(path.relative_to(output)): host.sha(path) for path in sorted(output.rglob('*')) if path.is_file()}
    result = {
        'schema': RESULT, 'profile': PROFILE, 'executionId': witness['executionId'],
        'cost': witness['cost'],
        'comparison': 'matched' if code == 0 else 'rejected', 'modelComparison': True, 'cleanup': 'confirmed',
        'nativeReceiptSha256': args.receipt_sha256, 'mappingSha256': args.mapping_sha256,
        'modelSourceSha256': selected['modelSourceSha256'], 'implementationSha256': selected['implementationSha256'],
        'mirrorSha256': args.mirror_sha256, 'policySha256': frozen[Path(policy)],
        'querySourceSha256': hashlib.sha256(query.encode()).hexdigest(), 'observationSha256': host.sha(output/'remote-observation.json'),
        'oracle': {**{name: observed[name] for name in ['host', 'port', 'serverExecutableSha256', 'sourceCommit',
            'apalacheJarSha256', 'javaExecutableSha256', 'javaVersion', 'observedAtUtc']},
            'transport': 'mtls', 'pin': config['pin'], 'verdict': 'valid' if code == 0 else 'invalid', 'exitCode': code},
        'artifacts': artifacts,
    }
    result['oracle']['clockSkewSeconds'] = config.get('clockSkewSeconds', 0)
    validate_result(result)
    budget.write(output/'result.json', result, final=True)
    return result, code
