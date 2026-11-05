import hashlib,json,os,subprocess,time
from pathlib import Path
stage=Path(r'D:\ModelMirrors\staging\qualification-rc7-20261105');source=stage/'Mirrors-rc8-f328e32'
job=stage/'runtime-inputs/native-test-job.exe'
git=r'C:\Program Files\Git\cmd\git.exe'
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
assert subprocess.check_output([git,'-C',str(source),'rev-parse','HEAD'],text=True).strip()=='f328e328d6f961b49ccffefc0a6d0250bec2fb3c'
assert not subprocess.check_output([git,'-C',str(source),'status','--porcelain'],text=True).strip()
names=['fixtures_replay', 'diff_cross', 'model_interface_spec', 'dpm_spec', 'dpm_evidence_spec', 'dpm_sync_spec', 'model_interface_language_spec', 'model_interface_lean_spec', 'model_interface_workflow_spec', 'model_interface_workflow_cli_spec', 'model_interface_workflow_provenance_spec', 'model_interface_corpus_spec', 'model_interface_migration_spec', 'model_interface_distribution_spec', 'framework_catalog_spec', 'model_interface_scaffold_cli_spec', 'model_interface_evidence_spec', 'tla_lexer_spec', 'tla_parser_spec', 'tla_module_resolver_spec', 'tla_elaboration_spec', 'model_interface_scaffold_spec', 'model_interface_trace_projection_cli_spec', 'model_interface_trace_projection_spec', 'stdio_smoke', 'async_resource_spec', 'jobstore_spec', 'apalache_cli_spec', 'explorer_spec', 'transport_spec', 'trace_generation_transport_repro_spec', 'registry_spec', 'counter_spec', 'async_spec']
rows=[]
for name in names:
 log=stage/'logs'/('rc8-native-'+name+'.log');binary=source/'.lake/build/bin'/(name+'.exe')
 frozen=digest(binary);env=dict(os.environ)
 env['APALACHE_MC']=str(binary) if name=='trace_generation_transport_repro_spec' else str(stage/'runtime-inputs/apalache-qualify-job.exe')
 began=time.time()
 try:
  with log.open('xb') as out:p=subprocess.run([str(job),str(binary)],cwd=source,env=env,stdout=out,stderr=subprocess.STDOUT,timeout=300)
  code=p.returncode
 except subprocess.TimeoutExpired:code='timeout'
 assert digest(binary)==frozen
 rows.append({'name':name,'exitCode':code,'seconds':round(time.time()-began,3),'binarySha256':frozen,'logSha256':digest(log),'jobWrapperSha256':digest(job)})
 (stage/'logs/rc8-native-suite-results.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
 print(name,code,flush=True)
assert not subprocess.check_output([git,'-C',str(source),'status','--porcelain'],text=True).strip()
print('Finished',sum(r['exitCode']==0 for r in rows),'of',len(rows),flush=True)
raise SystemExit(0 if all(r['exitCode']==0 for r in rows) else 1)
