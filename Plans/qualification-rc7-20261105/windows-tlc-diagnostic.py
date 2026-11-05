import json,subprocess,shutil,zipfile,hashlib
from pathlib import Path
stage=Path(r'D:\ModelMirrors\staging\qualification-rc7-20261105')
work=stage/'async-tlc-no-fairness-diagnostic';work.mkdir()
for name in ['MirrorProtocol.tla','MirrorProtocolFaults.tla','MirrorProtocolWitness.tla']:shutil.copyfile(stage/'Mirrors/specs'/name,work/name)
with zipfile.ZipFile(stage/'runtime-inputs/apalache.jar') as z:(work/'Apalache.tla').write_bytes(z.read('tla2sany/StandardModules/Apalache.tla'))
(work/'check.cfg').write_text((stage/'Mirrors/specs/MirrorProtocolAsyncLiveness.cfg').read_text().replace('AsyncFairSpec','AsyncSpec'))
cmd=[r'D:\Programs\jdk-25.0.4+7\bin\java.exe','-Xmx2g','-cp',str(stage/'tla2tools-1.8.0.jar'),'tlc2.TLC','-workers','2','-config','check.cfg','MirrorProtocol']
log=stage/'logs/tlc-no-fairness-diagnostic.log'
with log.open('xb') as out:p=subprocess.run(cmd,cwd=work,stdout=out,stderr=subprocess.STDOUT,timeout=300)
record={'command':cmd,'exitCode':p.returncode,'logSha256':hashlib.sha256(log.read_bytes()).hexdigest()}
(stage/'logs/tlc-no-fairness-diagnostic.json').write_text(json.dumps(record,indent=2))
print(json.dumps(record))
