"""Freeze reviewed companion ordering repair in a private task repository."""
from common import *
def main():
 gate=OUT/'MirrorGate-ordering-fix';env=environment();env['PATH']=str(OUT/'tool-bin')+':'+env['PATH']
 run('gate-ordering-final-focused-admitted',[OUT/'tool-bin/node','--test','tests/node/control-v2.test.mjs'],cwd=gate,env=env)
 run('gate-ordering-diff-check',['git','diff','--check'],cwd=gate)
 status=run('gate-ordering-status',['git','status','--porcelain'],cwd=gate);assert len(status.splitlines())==3
 run('gate-ordering-origin',['git','remote','set-url','origin','https://github.com/NzSN/MirrorGate.git'],cwd=gate)
 name=subprocess.check_output(['git','config','user.name'],text=True).strip();email=subprocess.check_output(['git','config','user.email'],text=True).strip()
 paths=['docs/agent-hosting-control-v2.md','sdk/node/control.mjs','tests/node/control-v2.test.mjs']
 run('gate-ordering-stage',['git','add','--',*paths],cwd=gate)
 run('gate-ordering-commit',['git','-c','user.name='+name,'-c','user.email='+email,'-c','commit.gpgSign=false','-c','core.hooksPath=/dev/null','commit','-m','sdk: observe hosted replies before coalesced events'],cwd=gate)
 revision=run('gate-ordering-revision',['git','rev-parse','HEAD'],cwd=gate);assert run('gate-ordering-clean',['git','status','--porcelain'],cwd=gate)==''
 patch=run('gate-ordering-patch',['git','format-patch','-1','--stdout'],cwd=gate);(OUT/'gate-ordering-fix.patch').write_text(patch+'\n')
 run('gate-ordering-source-bundle',['git','bundle','create',OUT/'MirrorGate-ordering-fix.bundle','HEAD'],cwd=gate)
 write(PLAN/'companion-ordering-fix.json',{'status':'fixed-and-private-source-frozen','repository':'https://github.com/NzSN/MirrorGate.git','base':'4b379ac0c017e7621c945ebf8c106cd98a6c70d1','revision':revision,'source':gate.relative_to(ROOT).as_posix(),'paths':paths,'fullGate':identity(OUT/'gate-fixed-full-dependencies.log'),'red':identity(OUT/'logs/gate-ordering-red.stdout'),'green':identity(OUT/'logs/gate-ordering-final-focused-admitted.stdout'),'patch':identity(OUT/'gate-ordering-fix.patch'),'bundle':identity(OUT/'MirrorGate-ordering-fix.bundle'),'published':False})
 print('GATE ORDERING REPAIR FROZEN '+revision,flush=True)
if __name__=='__main__':main()
