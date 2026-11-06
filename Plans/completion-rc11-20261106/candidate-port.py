"""Validate both actual packaged binaries over the owned mTLS candidate port."""
from evidence_rc11 import *
def main():
 obs=json.loads((BASE/'remote/admin-observation.json').read_text());linux=json.loads((PLAN/'linux-package.json').read_text());client=OUT/'linux-smoke-admitted'/('mirrors-'+TAG+'-linux-x86_64')/'bin/mirror'
 meta=json.loads((ROOT/linux['externalManifest']['path']).read_text());assert identity(client)['sha256']==meta['binaries']['mirror']['sha256']
 creds=ROOT/'.golden-build/qualification-rc7-20261105/private-pki'
 common=[client,'validate','--host','127.0.0.1','--port','19109','--tls','--cert',creds/'linux-client.crt','--key',creds/'linux-client.key','--ca',creds/'ca.crt','--pin',obs['mtls']['serverLeafSha256'],'--spec',SOURCE/'test/specs/HourClock.tla','--init','Init','--next','Next']
 rows=[]
 for asynchronous in [False,True]:
  for case,inv,bound,code in [('valid','Inv',3,0),('invalid','TraceComplete',13,1)]:
   name='rc11-packaged-'+('async' if asynchronous else 'sync')+'-'+case
   args=common+['--inv',inv,'--bound',str(bound)]+(['--async'] if asynchronous else [])
   out=run(name,args,env=base_environment(),timeout=240,ok=(code,));assert out.splitlines()[0]==case.upper(),out
   rows.append({'case':case,'async':asynchronous,'exitCode':code,'receipt':identity(OUT/'logs'/(name+'.json'))})
 args=list(common);args[args.index('--pin')+1]='0'*64
 out=run('rc11-packaged-wrong-pin',args+['--inv','Inv','--bound','3'],env=base_environment(),timeout=60,ok=(2,));assert 'VALID' not in out
 assert 'certificate fingerprint mismatch' in (OUT/'logs/rc11-packaged-wrong-pin.stderr').read_text().lower()
 write(PLAN/'candidate-port.json',{'status':'packaged-four-way-mtls-and-wrong-pin-passed','sourceRevision':COMMIT,'serverBinarySha256':obs['binarySha256'],'clientBinary':identity(client),'cases':rows,'wrongPinRejected':True,'productionModified':False,'credentialScope':'owned task PKI; production PKI acceptance remains a deployment control'})
 print('RC11 PACKAGED FOUR-WAY MTLS GREEN',flush=True)
if __name__=='__main__':main()
