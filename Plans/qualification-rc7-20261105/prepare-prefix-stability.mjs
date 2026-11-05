import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const [runtime,bundlePath,envelopePath,out]=process.argv.slice(2);
const api=await import(pathToFileURL(join(runtime,'packages/mirrorecma/dist/index.js')));
const projectApi=await import(pathToFileURL(join(runtime,'packages/mirrorecma/dist/project.js')));
const bytes=await readFile(bundlePath),bundle=api.decodeReproductionBundle(bytes);
const raw=await readFile(envelopePath),envelope=JSON.parse(raw);
const sha=b=>createHash('sha256').update(b).digest('hex');
const input=JSON.parse(await readFile(join(runtime,'framework-input.json')));
const installation={...input.installation,
 executables:input.installation.executables.map(x=>({...x,path:resolve(runtime,x.path)})),
 packages:input.installation.packages.map(x=>({...x,root:resolve(runtime,x.root),manifest:{...x.manifest,path:resolve(runtime,x.manifest.path)}})),
 runtimeTrees:input.installation.runtimeTrees.map(x=>({...x,root:resolve(runtime,x.root)}))};
const options={combinationId:'candidate.local-node-checked',catalogSelection:input.selectionRef,catalogRaw:input.catalogRaw,frameworkObserved:input.observed,installation,
 tools:{server:join(runtime,'bin/ModelMirrors')},admittedResolvers:new Set(),
 ...(input.approval?{frameworkApproval:input.approval}:{}),validateEvidenceLinks:links=>{
 assert.equal(sha(raw),links.runRef.envelopeSha256);assert.equal(envelope.runId,links.runRef.runId);
 for(const ref of links.artifactRefs){const a=envelope.artifacts.find(x=>x.artifactId===ref.artifactId);assert(a);assert.equal(a.sha256,ref.sha256);assert.equal(a.bytes,ref.bytes);}}};
const project=join(runtime,'applications/reference-project/mirror.faulty.project.json');
const stability=await api.classifyReproductionStability(bundle,{policy:{attemptLimit:3,totalBudgetMs:180000,perAttemptBudgetMs:45000,cleanupBudgetMs:10000},resettable:true,
 attempt:(_number,signal)=>projectApi.reproduceProjectWithCatalog(project,bundle,{...options,signal})});
await writeFile(out,JSON.stringify(stability)+'\n',{flag:'wx',mode:0o600});
console.log(JSON.stringify(stability));
assert.equal(stability.classification,'stable');assert.equal(stability.independence,'confirmed');assert.equal(stability.attempts.length,3);
console.log(JSON.stringify({classification:stability.classification,independence:stability.independence,attempts:stability.attempts.length}));
