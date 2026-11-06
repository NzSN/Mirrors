"""Repackage current launcher/helpers; build fresh consumers inside isolation."""
from evidence_rc10 import *
def main():
 base=OUT/'dpm-current';base.mkdir(mode=0o700)
 old=ROOT/'.golden-build/qualification-rc7-20261105'
 env=base_environment();env['TMPDIR']='/tmp/mrc10-dpm2';Path(env['TMPDIR']).mkdir(mode=0o700,exist_ok=False)
 args=json.loads((old/'logs/rc8-dpm-prepare-complete-generators.json').read_text())['argv']
 args[4]=str(SOURCE/'tools/deterministic-scheduling/prepare_cli.py');args[-1]=str(base/'prepared')
 run('rc10-current-dpm-prepare',args,env=env,timeout=1200)
 helper=SOURCE/'tools/deterministic-scheduling/install_cli.py'
 run('rc10-current-dpm-manifest',['python3','-I','-S','-B',helper,'manifest','--source',base/'prepared','--out',base/'installation.json'],env=env)
 digest=identity(base/'installation.json')['sha256']
 run('rc10-current-dpm-install',['python3','-I','-S','-B',helper,'install','--source',base/'prepared','--manifest',base/'installation.json','--manifest-sha256',digest,'--dest',base/'installed'],env=env)
 args=json.loads((old/'logs/rc8-dpm-three-installed-profiles.json').read_text())['argv'];args[4]=str(SOURCE/'tools/deterministic-scheduling/check_cli_installed.py');args[6]=str(base/'installed');args[10]=str(base/'acceptance')
 run('rc10-current-dpm-three-installed-profiles',args,env=env,timeout=1800)
 accepted=json.loads((base/'acceptance/acceptance.json').read_text());assert accepted['status']=='passed' and accepted['freshModelCheck'] is False and accepted['sourceHidden'] and accepted['networkNamespaceIsolated']
 write(PLAN/'installed-dpm-result.json',{'status':'all-three-installed-profiles-passed-at-exact-source','sourceRevision':COMMIT,'acceptance':identity(base/'acceptance/acceptance.json'),'manifest':identity(base/'installation.json'),'freshConsumersBuilt':True,'freshModelCheck':False,'retainedSdkInputs':'exact previous pinned CPPc95/ECMA919/Rust6b devkits; current launcher and all five helpers; fresh acceptance results'})
 print('RC10 ALL THREE INSTALLED DPM PROFILES GREEN',flush=True)
if __name__=='__main__':main()
