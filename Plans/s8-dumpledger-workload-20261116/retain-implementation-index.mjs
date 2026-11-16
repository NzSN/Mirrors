import assert from 'node:assert/strict';
import {readFileSync,readdirSync,statSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
const stage=String.raw`D:\ModelMirrors\staging\s8-dumpledger-workload-20261116\private\observations-v2`;
const root=String.raw`D:\Services\dump-ledger\dist\src`;
const hash=raw=>createHash('sha256').update(raw).digest('hex');
const walk=dir=>readdirSync(dir,{withFileTypes:true}).flatMap(item=>{
  assert(!item.isSymbolicLink());const path=join(dir,item.name);
  return item.isDirectory()?walk(path):item.isFile()&&item.name.endsWith('.js')?[path]:[];
});
const files=walk(root).sort().map(path=>({path,bytes:statSync(path).size,sha256:hash(readFileSync(path))}));
const raw=Buffer.from(JSON.stringify(files));
const producer=JSON.parse(readFileSync(join(stage,'receipt.json'),'utf8'));
assert.equal(files.length,producer.implementationFileCount);
assert.equal(hash(raw),producer.implementationTreeIndexSha256);
writeFileSync(join(stage,'implementation-index.json'),raw,{flag:'wx'});
console.log(JSON.stringify({status:'implementation-index-matches-producer-before-and-after-digest',
  files:files.length,artifact:{name:'implementation-index.json',bytes:raw.length,sha256:hash(raw)},
  productionModified:false,dumpBytesRead:false}));
