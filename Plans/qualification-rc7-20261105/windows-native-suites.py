import hashlib,json,os,subprocess,time
from pathlib import Path
stage=Path(r'D:\ModelMirrors\staging\qualification-rc7-20261105');source=stage/'Mirrors'
names=['fixtures_replay','diff_cross','model_interface_spec','dpm_spec','dpm_evidence_spec','dpm_sync_spec','model_interface_language_spec','model_interface_lean_spec','model_interface_workflow_spec','model_interface_workflow_cli_spec','model_interface_workflow_provenance_spec','model_interface_corpus_spec','model_interface_migration_spec','model_interface_distribution_spec','framework_catalog_spec','model_interface_scaffold_cli_spec','model_interface_evidence_spec','tla_lexer_spec','tla_parser_spec','tla_module_resolver_spec','tla_elaboration_spec','model_interface_scaffold_spec','model_interface_trace_projection_cli_spec','model_interface_trace_projection_spec','stdio_smoke','async_resource_spec','jobstore_spec','apalache_cli_spec','explorer_spec','transport_spec','trace_generation_transport_repro_spec','registry_spec','counter_spec','async_spec']
rows=[]
for name in names:
 log=stage/'logs'/('native-inventory-'+name+'.log')
 command=[str(source/'.lake/build/bin'/(name+'.exe'))]
 began=time.time()
 try:
  with log.open('xb') as out:p=subprocess.run(command,cwd=source,stdout=out,stderr=subprocess.STDOUT,timeout=300)
  code=p.returncode
 except subprocess.TimeoutExpired:code='timeout'
 rows.append({'name':name,'exitCode':code,'seconds':round(time.time()-began,3),'logSha256':hashlib.sha256(log.read_bytes()).hexdigest()})
 (stage/'logs/native-suite-inventory.json').write_text(json.dumps(rows,indent=2))
 print(name,code,flush=True)
print('Finished',sum(r['exitCode']==0 for r in rows),'of',len(rows),flush=True)
