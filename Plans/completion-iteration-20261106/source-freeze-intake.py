"""Inventory the scoped rc.9 source payload without touching the shared index."""
import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];PLAN=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'tools/evidence'))
from source_policy import is_planning_documentation

def record(path):
 raw=path.read_bytes();return {'path':path.relative_to(ROOT).as_posix(),'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}

def main():
 paths=subprocess.check_output(['git','diff','--name-only'],cwd=ROOT,text=True).splitlines()
 paths+=subprocess.check_output(['git','ls-files','--others','--exclude-standard','tools','Docs/windows-tooling.md'],cwd=ROOT,text=True).splitlines()
 source=[path for path in sorted(set(paths)) if not is_planning_documentation('mirrors',path)]
 old=json.loads((ROOT/'Plans/source-freeze-rc7-20261104/intake.json').read_text())['preservedUnrelatedFiles']
 for entry in old:assert record(ROOT/entry['path'])==entry
 value={'baseRevision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
        'productVersion':'0.2.0-rc.9','sourceEdits':[record(ROOT/path) for path in source],
        'preservedUnrelatedFiles':old,'sourceAuthoring':'direct Codex; no unrelated worktree cleanup',
        'localSourceCommitAndCandidateConstructionAuthorizedBy':'user requested iterating through the remaining release roadmap'}
 with (PLAN/'rc9-intake.json').open('x') as stream:stream.write(json.dumps(value,indent=2)+'\n')
 print(json.dumps({'sourceFiles':len(source),'preservedUnrelatedFiles':len(old),'baseRevision':value['baseRevision']}))
if __name__=='__main__':main()
