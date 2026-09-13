"""Qualified Apalache SanyParser outcomes, with bounded native IR evidence."""
from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

from corpus import OBSERVATION_SCHEMA
from normalize import supported
from process import ProcessRequest, run_process


def classify(result, parsed):
    if result.status.value != 'completed':
        return result.status.value, 'unknown'
    text = result.stdout.decode('utf-8', errors='replace')
    parser_ran = 'PASS #0: SanyParser' in text
    if result.returncode == 0 and parser_ran and 'Parsed successfully' in text and 'EXITCODE: OK' in text:
        if not isinstance(parsed, dict) or parsed.get('name') != 'ApalacheIR' or parsed.get('version') != '1.0' or not isinstance(parsed.get('modules'), list) or not parsed['modules']:
            return 'invalid_output', 'unknown'
        return 'completed', 'accepted'
    if result.returncode == 255 and parser_ran and 'Parser has failed' in text and 'EXITCODE: ERROR (255)' in text and 'Parsing error:' in text:
        return 'completed', 'rejected'
    return 'invalid_output', 'unknown'


def observe(*, fixture, materialized, config, limits, artifact_dir):
    jar = Path(str(config['apalache_jar'])).resolve()
    java = str(config.get('java', 'java'))
    scratch = materialized.root_path.parent / '.dv-apalache'
    scratch.mkdir()
    parsed_path = scratch / 'parsed.json'
    argv = [java, '-XX:-UsePerfData', '-Xmx1g', '-Djava.io.tmpdir=' + str(scratch), '-Duser.home=' + str(materialized.input_dir), '-jar', str(jar), '--out-dir=' + str(scratch), 'parse', '--output=' + str(parsed_path), materialized.root_path.name]
    result = run_process(ProcessRequest(argv, materialized.root_path.parent, artifact_dir=scratch), limits)
    parsed = None
    if result.status.value == 'completed' and parsed_path.is_file():
        try:
            parsed = json.loads(parsed_path.read_text())
        except (ValueError, OSError):
            pass
    execution, outcome = classify(result, parsed)
    output_root = artifact_dir.parents[3]
    refs = []
    for stream, content in [('stdout', result.stdout), ('stderr', result.stderr)]:
        path = artifact_dir / (stream + '.txt')
        path.write_bytes(content)
        refs.append({'path': path.relative_to(output_root).as_posix(), 'sha256': hashlib.sha256(content).hexdigest()})
    # Preserve every bounded output, with portable relative artifact references.
    for path in sorted(scratch.rglob('*')):
        if path.is_file() and not path.is_symlink():
            destination = artifact_dir / 'native' / path.relative_to(scratch)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination)
            refs.append({'path': destination.relative_to(output_root).as_posix(), 'sha256': hashlib.sha256(destination.read_bytes()).hexdigest()})
    facts = {key: {'capability': 'unqualified'} for key in ('source_closure', 'variables', 'resolution', 'substitution', 'levels', 'stage')}
    if outcome != 'unknown':
        facts['outcome'] = supported(outcome)
    text = result.stdout.decode('utf-8', errors='replace')
    # Native SanyParser mixes loading and import transformations; unknown mapping
    # remains explicit even when its own phase ran successfully.
    return {'schema': OBSERVATION_SCHEMA, 'fixture': fixture.id, 'engine': 'apalache', 'provider': fixture.provider,
            'inputDigest': materialized.input_digest, 'adapter': {'id': 'apalache', 'version': '1'},
            'tool': {'id': 'apalache', 'version': str(config['version']), 'fingerprint': hashlib.sha256(jar.read_bytes()).hexdigest()},
            'invocation': {'argv': argv, 'exitCode': result.returncode}, 'execution': execution, 'outcome': outcome,
            'nativePhase': 'SanyParser' if 'PASS #0: SanyParser' in text else None, 'stage': None,
            'diagnostics': [{'kind': 'native_log', 'artifact': refs[0]['path']}], 'facts': facts, 'rawArtifacts': refs}
