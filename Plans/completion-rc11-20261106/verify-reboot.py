"""Wait for an observed new boot, then verify AUTO_START and live controls."""
from common import *
import time

def main():
 before=json.loads((OUT/'deployed-observation.json').read_text());deadline=time.monotonic()+900
 ssh=['ssh','-F',str(Path.home()/'.ssh/config'),'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=5','-o','ConnectionAttempts=1','win10']
 command=ssh+['powershell','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',STAGE.replace('\\','/')+'/observe-deployment.ps1']
 attempts=[];after=None
 while time.monotonic()<deadline:
  number=len(attempts);started=datetime.now(timezone.utc).isoformat()
  try:p=subprocess.run(command,capture_output=True,timeout=40)
  except subprocess.TimeoutExpired:
   attempts.append({'attempt':number,'at':started,'timeout':True});time.sleep(8);continue
  (OUT/f'reboot-observation-{number}.stdout').write_bytes(p.stdout);(OUT/f'reboot-observation-{number}.stderr').write_bytes(p.stderr)
  row={'attempt':number,'at':started,'exitCode':p.returncode};attempts.append(row)
  if p.returncode==0:
   observed=json.loads(p.stdout.decode('utf-8-sig'))
   if observed['lastBootUpTimeUtc']!=before['lastBootUpTimeUtc']:
    after=observed;break
  elif any(text in p.stderr.decode('utf-8','replace') for text in ['deployed executable differs','production configuration drifted','certificate identity/validity differs','runtime pins differ']):
   raise ValueError('post-reboot identity refusal; inspect retained observation')
  print('post-reboot observation pending '+str(number),flush=True);time.sleep(8)
 write(OUT/'reboot-poll-receipt.json',attempts)
 assert after is not None,'new boot not observed within deadline'
 assert after['binary']['sha256']==before['binary']['sha256'] and after['configurationPreserved']
 assert after['service']['state']=='Running' and after['service']['startMode']=='Auto'
 assert datetime.fromisoformat(after['lastBootUpTimeUtc'].replace('Z','+00:00'))>datetime.fromisoformat(before['lastBootUpTimeUtc'].replace('Z','+00:00'))
 write(OUT/'post-reboot-observation.json',after)
 health=json.loads(run('s7-post-reboot-health',ssh+['D:/ModelMirrors/staging/windows-fixes-20261106/python312-completion/python3.exe','-I','-S','-B',STAGE.replace('\\','/')+'/production-health-v2.py','post-reboot'],timeout=1200))
 assert health['status']=='passed' and health['wrongPinRejected'] and len(health['cases'])==4
 write(PLAN/'reboot-result.json',{'status':'reboot-auto-start-and-live-controls-passed','beforeBootUtc':before['lastBootUpTimeUtc'],'afterBootUtc':after['lastBootUpTimeUtc'],'after':after,'health':health,'userApproved':True})
 print('REBOOT AUTO_START AND FOUR-WAY MTLS VERIFIED',flush=True)
if __name__=='__main__':main()
