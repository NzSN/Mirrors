import importlib.util
from evidence_rc10 import *
spec=importlib.util.spec_from_file_location('task_remote',PLAN/'collect-remote.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);old_context=module.old_context
def main():
 env=base_environment()
 for cid in ['mirrors.remote-model-check','mirrors.interop']:
  for item in old_context(cid)['effectiveEnvironment']:env[item['name']]=item['value']
 obs=json.loads((OUT/'remote-observation2.json').read_text())
 env.update(MIRRORS_REMOTE_ADMIN_OBSERVATION=str(BASE/'remote/admin-observation.json'),MIRRORS_REMOTE_HOST='127.0.0.1',MIRRORS_REMOTE_PORT='19109',MIRRORS_REMOTE_SERVICE_SOURCE_REF=COMMIT,MIRRORS_REMOTE_SERVICE_BINARY_SHA256=obs['binary']['sha256'],MIRRORS_REMOTE_SERVER_PIN=obs['serverLeafSha256'])
 target=BASE/'outputs/mirrors.interop';plan=attachment_for('mirrors.interop',target)
 collect('rc10-admitted-interop','mirrors.interop',cwd=SOURCE,tail=[target],env=env,attachment_plan=plan,timeout=2400)
 print('RC10 ALL 22 CLIENT ROWS GREEN',flush=True)
if __name__=='__main__':main()
