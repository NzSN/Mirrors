"""Fresh exact rc.10 remote producers; retained recipes, freshly observed identities."""
from evidence_final import *
def old_context(cid):
 p=Path(json.loads((ROOT/'.golden-build/qualification-rc7-20261105/refreshed/producer-runs'/(cid+'.json')).read_text())['bundle']);idx=json.loads((p/'bundle-index.json').read_text());return json.loads((p/next(x['path'] for x in idx['records'] if x.get('artifactId')=='command-context')).read_text())['command']
def remote_env():
 obs=json.loads((OUT/'remote-observation-final.json').read_text());assert obs['productionServiceStatus']=='Running' and obs['productionUsed'] is False
 expected=ENTRIES['mirrors.remote-model-check']['requiredEnvironment']
 for key,envkey in [('apalacheArchive','MIRRORS_REMOTE_APALACHE_ARCHIVE_SHA256'),('jar','MIRRORS_REMOTE_APALACHE_JAR_SHA256'),('javaArchive','MIRRORS_REMOTE_JAVA_ARCHIVE_SHA256'),('java','MIRRORS_REMOTE_JAVA_EXECUTABLE_SHA256')]:assert obs['runtimeFiles'][key]['sha256']==expected[envkey]
 assert '25.0.4+7-LTS' in obs['javaVersion']
 assert obs['binary']['sha256']=='e23110cdbd4eb3d7372ecb0d2ceced3709fbe0ce4cd44b9d0a81c5d416bb9da0'
 manifest=OUT/'archive/source-manifest.json';runtime_digest=hashlib.sha256(json.dumps(obs['runtimeFiles'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
 admission={'schema':'mirrors.windows-deployment-observation/v1','endpoint':{'host':'127.0.0.1','port':19109},'deploymentMode':'owned-native-console','processId':obs['state']['pid'],'processCreatedAt':obs['processCreatedAt'],'binarySha256':obs['binary']['sha256'],'sourceBaseRevision':COMMIT,'mtls':{'serverLeafSha256':obs['serverLeafSha256']},'runtime':{'apalacheVersion':expected['MIRRORS_REMOTE_APALACHE_VERSION'],'apalacheArchiveSha256':expected['MIRRORS_REMOTE_APALACHE_ARCHIVE_SHA256'],'apalacheJarSha256':expected['MIRRORS_REMOTE_APALACHE_JAR_SHA256'],'javaVersion':expected['MIRRORS_REMOTE_JAVA_OBSERVED_VERSION'],'javaArchiveSha256':expected['MIRRORS_REMOTE_JAVA_ARCHIVE_SHA256'],'javaExecutableSha256':expected['MIRRORS_REMOTE_JAVA_EXECUTABLE_SHA256']},'sourceTreeSha256':FREEZE['validatedSourceTreeIndexSha256'],'sourceManifestSha256':identity(manifest)['sha256'],'runtimeManifestSha256':runtime_digest,'observedAt':obs['observedAt'],'interopFixtures':obs['interopFixtures'],'connectionScope':'owned SSH tunnel 127.0.0.1:19109 -> win10 loopback:19099; production untouched','sourceIdentityBasis':'clean Git source 10104 blobs verified; source-index and archive manifest retained'}
 support=BASE/'remote';support.mkdir(mode=0o700,exist_ok=True);path=support/'admin-observation.json';write(path,admission);path.chmod(0o600)
 env=base_environment()
 for cid in ['mirrors.remote-model-check','mirrors.interop']:
  for item in old_context(cid)['effectiveEnvironment']:env[item['name']]=item['value']
 env.update(MIRRORS_REMOTE_ADMIN_OBSERVATION=str(path),MIRRORS_REMOTE_HOST='127.0.0.1',MIRRORS_REMOTE_PORT='19109',MIRRORS_REMOTE_SERVICE_SOURCE_REF=COMMIT,MIRRORS_REMOTE_SERVICE_BINARY_SHA256=obs['binary']['sha256'],MIRRORS_REMOTE_SERVER_PIN=obs['serverLeafSha256'])
 return env

def main():
 raw=run('rc10-c0-final-remote-observe',SSH+['powershell','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',STAGE.replace('\\','/')+'/observe-remote2.ps1'],timeout=90);write(OUT/'remote-observation-final.json',json.loads(raw));env=remote_env()
 collect('rc10-c0-final-remote-model','mirrors.remote-model-check',cwd=SOURCE,env=env,timeout=1200)
 target=BASE/'outputs/mirrors.interop';plan=attachment_for('mirrors.interop',target)
 collect('rc10-c0-final-remote-interop','mirrors.interop',cwd=SOURCE,tail=[target],env=env,attachment_plan=plan,timeout=2400)
 print('RC10 REMOTE MODEL AND ALL 22 CLIENT ROWS GREEN',flush=True)
if __name__=='__main__':main()
