from evidence_rc11 import *
def main():
 cleanup=json.loads((OUT/'oracle-cleanup-admitted.json').read_text());assert cleanup['ownedModelChildrenBeforeStop']==0 and cleanup['ownedConsoleChildrenAfterStop']==0 and cleanup['ownedRemaining']==[] and cleanup['ownedListeners']==[]
 result=json.loads(run('rc11-q2-after-oracle-stop',json.loads((OUT/'q2-command.json').read_text()),timeout=1800))
 before=json.loads((PLAN/'independent-q2-result.json').read_text());assert result==before,'offline acceptance changed after oracle shutdown'
 write(PLAN/'offline-after-shutdown.json',{'status':'byte-identical-independent-Q2-after-oracle-shutdown','bundlesVerified':result['selectedBundlesVerified'],'negativeControls':len(result['negativeControls']),'cleanup':identity(OUT/'oracle-cleanup-admitted.json'),'verification':identity(OUT/'logs/rc11-q2-after-oracle-stop.stdout'),'productionModified':False})
 print('OFFLINE Q2 IDENTICAL AFTER ORACLE SHUTDOWN',flush=True)
if __name__=='__main__':main()
