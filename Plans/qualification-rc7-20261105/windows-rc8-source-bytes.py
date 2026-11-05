import hashlib,json,subprocess,stat
from pathlib import Path
stage=Path(r'D:\ModelMirrors\staging\qualification-rc7-20261105');git=r'C:\Program Files\Git\cmd\git.exe'
results=[]
for name,expected in [('Mirrors-rc8-f328e32','f328e328d6f961b49ccffefc0a6d0250bec2fb3c'),('MirrorCPP-rc8-c95f0e1','c95f0e185436f145af9fad8895430e899bc479a3')]:
 root=stage/name
 assert subprocess.check_output([git,'-C',str(root),'rev-parse','HEAD'],text=True).strip()==expected
 entries=subprocess.check_output([git,'-C',str(root),'ls-tree','-rz','--full-tree','HEAD']).split(b'\0')
 process=subprocess.Popen([git,'-C',str(root),'cat-file','--batch'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 rows=[]
 try:
  for entry in entries:
   if not entry:continue
   metadata,path=entry.split(b'\t',1);mode,kind,object_id=metadata.split();assert mode in [b'100644',b'100755'] and kind==b'blob'
   process.stdin.write(object_id+b'\n');process.stdin.flush();header=process.stdout.readline().split();assert header[1]==b'blob'
   length=int(header[2]);blob=process.stdout.read(length);assert len(blob)==length and process.stdout.read(1)==b'\n'
   relative=path.decode('utf-8');physical=Path('\\\\?\\'+str(root/relative))
   assert stat.S_ISREG(physical.lstat().st_mode) and not physical.is_symlink()
   data=physical.read_bytes();assert data==blob,relative
   rows.append({'path':relative,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'mode':mode.decode()})
 finally:
  process.stdin.close();process.wait(timeout=30)
 assert process.returncode==0
 status=subprocess.check_output([git,'-C',str(root),'status','--porcelain'],text=True);assert not status.strip(),status
 record={'source':name,'revision':expected,'gitBlobBytesMatched':len(rows),'files':rows}
 path=stage/'logs'/('rc8-source-bytes-'+name+'.json');path.write_text(json.dumps(record,indent=2),encoding='utf-8')
 results.append({'source':name,'revision':expected,'files':len(rows),'manifestSha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(stage/'logs/rc8-source-byte-results.json').write_text(json.dumps(results,indent=2),encoding='utf-8');print(json.dumps(results),flush=True)
