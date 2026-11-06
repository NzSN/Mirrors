from evidence_rc10 import *
import shutil
def main():
 base=OUT/'dpm-final';base.mkdir(mode=0o700);node=Path('/tmp/mrc10-node-final/bin/node');node.parent.mkdir(mode=0o700,parents=True,exist_ok=False);runtime,_=installed('checked-replay-local');shutil.copy2(runtime/'runtimes/node/bin/node',node)
 env=base_environment();env['PATH']=str(node.parent)+':'+env['PATH'];env['TMPDIR']='/tmp/mrc10-dpm4';Path(env['TMPDIR']).mkdir(mode=0o700)
 old=ROOT/'.golden-build/qualification-rc7-20261105'
 args=json.loads((old/'logs/rc8-dpm-prepare-complete-generators.json').read_text())['argv'];args[4]=str(SOURCE/'tools/deterministic-scheduling/prepare_cli.py');args[-1]=str(base/'prepared');run('rc10-final-dpm-prepare',args,env=env,timeout=1200)
 sample=ROOT/'.golden-build/qualification-rc7-20261105/inputs/MirrorCPP-windows/examples/controlled_sync.cpp';assert sample.is_file();shutil.copy2(sample,base/'prepared/cpp/devkit/consumer/controlled_sync.cpp')
 helper=SOURCE/'tools/deterministic-scheduling/install_cli.py';run('rc10-final-dpm-manifest',['python3','-I','-S','-B',helper,'manifest','--source',base/'prepared','--out',base/'installation.json'],env=env)
 run('rc10-final-dpm-install',['python3','-I','-S','-B',helper,'install','--source',base/'prepared','--manifest',base/'installation.json','--manifest-sha256',identity(base/'installation.json')['sha256'],'--dest',base/'installed'],env=env)
 args=json.loads((old/'logs/rc8-dpm-three-installed-profiles.json').read_text())['argv'];args[4]=str(SOURCE/'tools/deterministic-scheduling/check_cli_installed.py');args[6]=str(base/'installed');args[10]=str(base/'acceptance');run('rc10-final-dpm-acceptance',args,env=env,timeout=1800)
 a=base/'acceptance/acceptance.json';v=json.loads(a.read_text());assert v['status']=='passed' and v['freshModelCheck'] is False and v['sourceHidden'] and v['networkNamespaceIsolated']
 write(PLAN/'installed-dpm-result.json',{'status':'all-three-installed-profiles-passed-at-exact-source','sourceRevision':COMMIT,'acceptance':identity(a),'manifest':identity(base/'installation.json'),'freshConsumersBuilt':True,'freshModelCheck':False,'nodeSha256':hashlib.sha256(node.read_bytes()).hexdigest()})
 print('RC10 THREE INSTALLED DPM PROFILES GREEN',flush=True)
if __name__=='__main__':main()
