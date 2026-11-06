"""Observe the existing upload; never retry or overwrite an asset blindly."""
from common import *
import time

def main():
 deadline=time.monotonic()+2400;observations=[];name='mirrors-'+TAG+'-windows-x86_64.zip'
 while time.monotonic()<deadline:
  p=subprocess.run(['gh','api','repos/NzSN/Mirrors/releases/tags/'+TAG],capture_output=True,timeout=120)
  row={'at':datetime.now(timezone.utc).isoformat(),'exitCode':p.returncode}
  if p.returncode==0:
   release=json.loads(p.stdout);asset=next((a for a in release['assets'] if a['name']==name),None)
   row['asset']=None if asset is None else {k:asset.get(k) for k in ['name','state','size','digest']}
   if asset is not None and asset['state']=='uploaded':
    assert asset['digest']=='sha256:f5ec1c9ba3204be04f797acb9086c3a6edd00dce81d7f478c5292b377b7c7df0' and asset['size']==73727146,'uploaded Windows bytes differ'
    observations.append(row);break
  observations.append(row);print('Windows upload still progressing; observation '+str(len(observations)),flush=True);time.sleep(40)
 else:raise RuntimeError('Windows upload did not finish within observation deadline; retained attempt must be inspected')
 write(OUT/'windows-upload-observations.json',observations)
 run('s7-verify-complete-publication',['python3',PLAN/'verify-published-release.py'],timeout=2400)
 print('WINDOWS UPLOAD AND COMPLETE PUBLICATION VERIFICATION FINISHED',flush=True)
if __name__=='__main__':main()
