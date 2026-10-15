import pathlib,subprocess,concurrent.futures,hashlib,json,time
D=pathlib.Path('/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015/downloads')
C='/mnt/c/Program Files/Git/mingw64/bin/curl.exe'
W='D:/Desktop/Workspaces/Mirrors-client-fixes-20261015/downloads/'
G='ghc-9.14.1-x86_64-deb11-linux.tar.xz'
I='hackage-01-index.tar.gz'
records=[];jobs=[]
for name,total,url in [(G,307306404,'https://downloads.haskell.org/~ghc/9.14.1/'+G),(I,139442315,'https://hackage.haskell.org/01-index.tar.gz')]:
 segs=[(0,(D/name).stat().st_size,name)]
 if name==G:
  step=(307306404-122605568+3)//4
  for i in range(4):
   p=D/(name+'.part'+str(i));segs.append((122605568+i*step,p.stat().st_size,p.name))
 segs.sort();allsegs=[]
 for j,(start,size,file) in enumerate(segs):
  allsegs.append((start,size,file));end=segs[j+1][0] if j+1<len(segs) else total
  for off in range(start+size,end,1048576):
   n=min(1048576,end-off);fn=name+'.seg'+str(off);allsegs.append((off,n,fn));jobs.append((url,off,n,fn))
 records.append((name,total,sorted(allsegs)))
def download(job):
 url,off,n,fn=job;p=D/fn
 if p.exists() and p.stat().st_size==n:return
 subprocess.run([C,'-fsSL','--retry','3','--connect-timeout','15','--max-time','90','--range',f'{off}-{off+n-1}',url,'-o',W+fn],check=True)
 if p.stat().st_size!=n:raise RuntimeError((fn,p.stat().st_size,n))
with concurrent.futures.ThreadPoolExecutor(4) as ex:
 for i,_ in enumerate(ex.map(download,jobs)):
  if i%10==0:print('segments',i+1,'/',len(jobs),flush=True)
for name,total,segs in records:
 out=D/(name+'.assembled')
 with out.open('wb') as w:
  for off,n,fn in segs:
   assert w.tell()==off,(name,w.tell(),off)
   with (D/fn).open('rb') as f:
    while b:=f.read(1048576):w.write(b)
 assert out.stat().st_size==total
 sha=hashlib.sha256(out.read_bytes()).hexdigest()
 if name==G:
  official=next(line.split()[0] for line in (D/'ghc-SHA256SUMS').read_text().splitlines() if line.split()[-1]==G)
  assert sha==official,(sha,official)
 out.replace(D/name)
 print(name,total,sha,flush=True)
(D/'segmented-summary.json').write_text(json.dumps({'segments':len(jobs),'files':[{'name':n,'bytes':t,'sha256':hashlib.sha256((D/n).read_bytes()).hexdigest()} for n,t,_ in records]},indent=2)+'\n')
