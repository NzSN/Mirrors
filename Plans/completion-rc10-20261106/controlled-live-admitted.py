from evidence_rc10 import *
def main():
 base=OUT/'controlled-live-admitted';base.mkdir(mode=0o700)
 obs=json.loads(run('rc10-controlled-remote-observe2',SSH+['powershell','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',STAGE.replace('\\','/')+'/observe-remote2.ps1'],timeout=90))
 previous=json.loads((BASE/'remote/admin-observation.json').read_text());assert obs['binary']['sha256']==previous['binarySha256'] and obs['state']['sourceRevision']==COMMIT
 selected={'schema':'mirrors.controlled-model-remote/v1','host':'127.0.0.1','port':19109,'pin':obs['serverLeafSha256'],'cert':str(ROOT/'.golden-build/qualification-rc7-20261105/private-pki/linux-client.crt'),'key':str(ROOT/'.golden-build/qualification-rc7-20261105/private-pki/linux-client.key'),'ca':str(ROOT/'.golden-build/qualification-rc7-20261105/private-pki/ca.crt'),'observation':str(base/'observation.json'),'serverExecutableSha256':obs['binary']['sha256'],'sourceCommit':COMMIT,'apalacheJarSha256':obs['runtimeFiles']['jar']['sha256'],'javaExecutableSha256':obs['runtimeFiles']['java']['sha256'],'javaVersion':'25.0.4+7-LTS'}
 observed={'schema':'mirrors.controlled-model-observation/v1','host':selected['host'],'port':selected['port'],'serverCertificateSha256':selected['pin'],**{k:selected[k] for k in ['serverExecutableSha256','sourceCommit','apalacheJarSha256','javaExecutableSha256','javaVersion']},'processId':obs['state']['pid'],'observedAtUtc':obs['observedAt'],'certificateNotAfterUtc':obs['certificateNotAfter']}
 write(base/'observation.json',observed);write(base/'remote.json',selected)
 runtime,_=installed('checked-replay-local')
 run('rc10-controlled-live-comparison',['python3','-I','-S','-B',SOURCE/'tools/check-controlled-model.py','--prefix',ROOT/'.golden-build/qualification-rc7-20261105/cpp-prefix-windows-fix','--mirror',runtime/'bin/ModelMirrors','--remote',base/'remote.json','--remote-sha256',identity(base/'remote.json')['sha256'],'--require-remote','--reduce-count','--out',base/'campaign'],env=base_environment(),timeout=1800)
 write(PLAN/'controlled-model-result.json',{'status':'passed-finite-controlled-model-comparison','sourceRevision':COMMIT,'acceptance':identity(base/'campaign/acceptance.json'),'reduction':identity(base/'campaign/reduction.json'),'modelComparison':True,'genericNativeSchedulingOrProductionQualification':False})
 print('RC10 CONTROLLED LIVE COMPARISON GREEN',flush=True)
if __name__=='__main__':main()
