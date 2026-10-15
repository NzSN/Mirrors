import pathlib,os,signal
me=os.getpid();pids=[]
for p in pathlib.Path('/proc').iterdir():
 if not p.name.isdigit() or int(p.name)==me:continue
 try:c=(p/'cmdline').read_bytes().replace(b'\0',b' ').decode(errors='replace')
 except OSError:continue
 if (c.startswith('python3 /mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015/haskell-segmented.py') or ('curl.exe' in c and 'Mirrors-client-fixes-20261015/downloads/' in c and '.seg' in c)):
  pids.append((int(p.name),c))
for pid,c in pids:
 try:os.kill(pid,signal.SIGTERM);print('stopped',pid,c)
 except ProcessLookupError:pass
