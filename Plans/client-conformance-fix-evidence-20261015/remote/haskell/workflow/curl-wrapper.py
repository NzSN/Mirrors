#!/usr/bin/python3
import subprocess,sys,os
args=[]
for a in sys.argv[1:]:
 if a.startswith('/') and not a.startswith('//'):
  a=subprocess.check_output(['/usr/bin/wslpath','-w',a],text=True).strip()
 args.append(a)
raise SystemExit(subprocess.call(['/mnt/c/Program Files/Git/mingw64/bin/curl.exe',*args]))
