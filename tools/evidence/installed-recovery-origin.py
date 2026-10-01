#!/usr/bin/env python3
"""Produce a genuine interrupted installed Gate origin on an owned fixture."""
import json
import os
from pathlib import Path
import subprocess
import sys
from hashlib import sha256

runtime=Path(os.environ['MIRRORS_INSTALLED_GATE_RUNTIME']).resolve()
assert Path.cwd()==runtime
assert len(sys.argv)==2,'Usage: installed-recovery-origin.py OUTPUT_ROOT'
output=Path(sys.argv[1]).resolve();assert output.is_dir() and output.stat().st_mode&0o777==0o700
assert output.stat().st_uid==os.getuid()
from mirrorgate.control_policy import example_policy_document
from mirrorgate.recovery_journal import inspect_records
fixture=output/'fixture';fixture.mkdir(mode=0o700)
state=fixture/'state';state.mkdir(mode=0o700)
submission=fixture/'submissions/app';submission.mkdir(parents=True)
(submission/'adapter.mjs').write_text('export function createAdapter(){return {actions:{},observe(){return {}}}}\n')
policy=fixture/'policy.json';policy.write_text(json.dumps(example_policy_document(
    submission_root=fixture/'submissions',node_shim_root=runtime/'gate/mirrorgate-runtime',
    node_runtime_root=runtime/'runtimes/node'),separators=(',',':')));policy.chmod(0o600)
# The operator-provided public-port manifest is part of the origin's pinned inputs.
manifest=output/'recovery-manifest.json';assert manifest.is_file() and manifest.stat().st_mode&0o777==0o600
script=r'''
import json,os,threading,time
from pathlib import Path
from mirrorgate.preparation import BackendOwner,ControlBackend
from mirrorgate.recovery_journal import inspect_records
backend=ControlBackend(os.environ['M5_RECOVERY_POLICY'],state_root=os.environ['M5_RECOVERY_STATE'])
state=backend.open_session(owner=BackendOwner('connection',os.getuid(),'m5-recovery-fixture'),
    policy_id='test.node',submission={'kind':'source','input':{'rootId':'submission','relativePath':'app'},
      'buildPlanId':'copy','authoring':True},runtime='node-v1',
    manifest_bytes=Path(os.environ['M5_RECOVERY_MANIFEST']).read_bytes())
records=inspect_records(Path(os.environ['M5_RECOVERY_STATE'])).records
assert records and all(r['kind']=='filesystem' for r in records)
print('owned controller interrupted after snapshot preparation, before worker launch',flush=True)
os._exit(74)
'''
env=dict(os.environ,M5_RECOVERY_POLICY=str(policy),M5_RECOVERY_STATE=str(state),M5_RECOVERY_MANIFEST=str(manifest))
process=subprocess.run([sys.executable,'-c',script],env=env,text=True,capture_output=True,timeout=30)
(output/'interruption.log').write_text(process.stdout+process.stderr);(output/'interruption.log').chmod(0o600)
if process.returncode!=74:raise RuntimeError('real interruption fixture failed: '+(process.stdout+process.stderr)[-2500:])
records=inspect_records(state).records
pending=[r for r in records if r['phase']!='reclaimed'];assert len(pending)>=3 and all(r['kind']=='filesystem' for r in pending)
result={'schema':'mirrors.recovery-origin/v1','controllerExit':74,'behavior':'failed','cleanup':'unconfirmed',
    'interruptionStage':'prepared-before-worker-start','resourceCount':len(pending),'resourceKinds':sorted({r['kind'] for r in pending}),
    'stateRoot':str(state),'manifestSha256':sha256(manifest.read_bytes()).hexdigest()}
with (output/'recovery-origin.json').open('x') as stream:json.dump(result,stream,separators=(',',':'));stream.write('\n')
(output/'recovery-origin.json').chmod(0o600)
print(json.dumps(result),flush=True)
raise SystemExit(74)
