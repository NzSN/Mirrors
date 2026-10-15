import hashlib,json,os,shutil,subprocess,tarfile
from pathlib import Path
root=Path('/home/jlc/Tools/mirrors-client-fixes-20261015')
build=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015')
probe=build/'postfix-probes';probe.mkdir()
with tarfile.open(build/'original-audit-probes.tar') as archive:archive.extractall(probe)
node=root/'tools/node/bin/node'
ecma_command=[str(node),str(probe/'ecma-probes/invalid-pair.mjs'),str(root/'source/MirrorECMA')]
ecma=subprocess.run(ecma_command,capture_output=True,timeout=30)
(build/'logs/postfix-ecma.stdout.json').write_bytes(ecma.stdout)
(build/'logs/postfix-ecma.stderr.log').write_bytes(ecma.stderr)
assert ecma.returncode==0
rows=json.loads(ecma.stdout)['results']
assert rows[0]['outcome']=='accepted'
assert all(row['outcome']=='rejected' and row['counts']['factory']==0 and row['counts']['sends']==0 for row in rows[1:])
reference=probe/'cli-probes/source-reference.json'
selection=json.loads(reference.read_text());selection['purpose']='Post-fix relevant source bytes; full source manifest separately binds candidate'
selection['baseHead']=selection.pop('head')
for row in selection['files']:row['sha256']=hashlib.sha256((root/'source/Mirrors'/row['path']).read_bytes()).hexdigest()
reference.write_text(json.dumps(selection,indent=2)+'\n')
work=build/'postfix-cli-work';work.mkdir()
command=[str(root/'tools/bin/python3'),str(probe/'cli-probes/probe.py'),
    '--mirror',str(root/'source/Mirrors/.lake/build/bin/mirror'),'--source-root',str(root/'source/Mirrors'),'--work-root',str(work)]
cli=subprocess.run(command,capture_output=True,timeout=90)
(build/'logs/postfix-cli.stdout.json').write_bytes(cli.stdout)
(build/'logs/postfix-cli.stderr.log').write_bytes(cli.stderr)
assert cli.returncode==0,cli.stderr.decode()
result=json.loads(cli.stdout)
assert result['valid_lf_control_passed'] and result['all_owned_processes_reaped']
assert not result['missing_lf_finding_reproduced'] and not result['post_terminal_cancel_finding_reproduced']
record={'status':'passed','ecmaCommand':ecma_command,'ecmaOriginalInvalidPairNowRefused':True,
        'cliCommand':command,'cliOriginalMissingLfNowRefused':True,'cliOriginalTerminalErrorNoCancel':True,
        'cliProbeSourceUnchanged':hashlib.sha256((probe/'cli-probes/probe.py').read_bytes()).hexdigest(),
        'cliReferenceOverlaySha256':hashlib.sha256(reference.read_bytes()).hexdigest(),
        'cliWorkRoot':result['work_root'],'newSourceInterfaceNotOldHead':True}
(build/'postfix-ecma-cli.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2),flush=True)
