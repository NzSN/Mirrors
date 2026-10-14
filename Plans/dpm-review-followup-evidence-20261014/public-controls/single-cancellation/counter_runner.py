import json,os,signal,sys,time
from pathlib import Path
request=Path(sys.argv[sys.argv.index('--request')+1])
mode=sys.argv[1]
signal.signal(signal.SIGTERM,signal.SIG_IGN)
ready=request.parent/'runner-control.json'
temp=ready.with_suffix('.tmp')
temp.write_text(json.dumps({'pid':os.getpid(),'pgid':os.getpgrp(),'hostPid':os.getppid(),'argv':sys.argv[1:]}))
temp.replace(ready)
print('public-runner-ready',flush=True)
time.sleep(0.1 if mode=='' else 10)
