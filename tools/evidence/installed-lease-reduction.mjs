#!/usr/bin/env node
/** Installed R5: remote model validity, then original/baseline/candidate replay. */
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {constants} from 'node:fs';
import {open,writeFile} from 'node:fs/promises';
import {resolve,dirname,join} from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {decodeReproductionBundle,inspectProjectReproductionWithCatalog,
  signatureFromSuiteResult,signaturesEqual} from 'mirrorecma';
import {reproduceProjectWithCatalog,replayProject,checkProject} from 'mirrorecma/project';
const runtime=resolve(dirname(fileURLToPath(import.meta.url)),'../../../..');
assert.equal(process.cwd(),runtime,'run from the selected installed runtime');
const args=process.argv.slice(2),flags=Object.fromEntries(args.reduce((out,value,index)=>{
  if(index%2===0)out.push([value,args[index+1]]);return out;
},[]));
assert.equal(args.length,26,'expected the registered R5 arguments');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
async function bytes(path,limit=16*1024*1024){
  const h=await open(resolve(path),constants.O_RDONLY|constants.O_NOFOLLOW);
  try{const s=await h.stat();assert(s.isFile()&&s.size<=limit,'input is not a bounded regular file');return await h.readFile();}
  finally{await h.close();}
}
async function json(path){return JSON.parse(await bytes(path));}
const bundleBytes=await bytes(flags['--bundle']),bundle=decodeReproductionBundle(bundleBytes);
// Model validity and confirmed remote cleanup precede every application factory.
const materializer=join(runtime,'packages/mirrorecma/scripts/materialize-lease-reduction.mjs');
const result=await new Promise((done,reject)=>{
  const child=spawn(process.execPath,[materializer,...args],{stdio:['ignore','pipe','pipe'],shell:false});
  const chunks=[];let size=0;
  for(const stream of [child.stdout,child.stderr])stream.on('data',chunk=>{
    size+=chunk.length;if(size>8*1024*1024)child.kill('SIGKILL');else chunks.push(chunk);
  });
  child.once('error',reject);child.once('close',(code,signal)=>done({code,signal,log:Buffer.concat(chunks).toString('utf8')}));
});
assert.equal(result.code,0,`remote materializer failed (${result.code??result.signal}): ${result.log}`);
const oracleBytes=await bytes(flags['--receipt']),oracle=JSON.parse(oracleBytes);
assert.equal(oracle.status,'model_valid');assert.deepEqual(oracle.cleanup,{status:'confirmed',method:'explore_done'});
const candidateBytes=await bytes(flags['--out']),candidateHash=sha(candidateBytes);
assert.equal(candidateHash,oracle.materialization.candidateTraceSha256);
assert.equal(sha(bundleBytes),oracle.materialization.originalBundleSha256);
const input=await json(join(runtime,'framework-input.json'));
const installation={...input.installation,
  executables:input.installation.executables.map(x=>({...x,path:resolve(runtime,x.path)})),
  packages:input.installation.packages.map(x=>({...x,root:resolve(runtime,x.root),manifest:{...x.manifest,path:resolve(runtime,x.manifest.path)}})),
  runtimeTrees:input.installation.runtimeTrees.map(x=>({...x,root:resolve(runtime,x.root)}))};
const options={combinationId:'candidate.local-node-checked',catalogSelection:input.selectionRef,
  catalogRaw:input.catalogRaw,frameworkObserved:input.observed,installation,
  ...(input.approval===undefined?{}:{frameworkApproval:input.approval}),
  admittedResolvers:new Set(),validateEvidenceLinks:links=>{
    const capture=bundle.captures.find(c=>c.role==='evidence-envelope'&&c.kind==='inline');
    assert(capture,'finalized original evidence must be captured inline');
    const raw=Buffer.from(capture.base64,'base64'),envelope=JSON.parse(raw);
    assert.equal(sha(raw),links.runRef.envelopeSha256);assert.equal(envelope.runId,links.runRef.runId);
    assert.deepEqual(envelope.catalogSelectionRef,input.selectionRef);
    for(const ref of links.artifactRefs){const artifact=envelope.artifacts.find(a=>a.artifactId===ref.artifactId);assert(artifact);assert.equal(artifact.sha256,ref.sha256);assert.equal(artifact.bytes,ref.bytes);}
  }};
const faulty=join(runtime,'applications/lease-project/mirror.faulty.project.json');
const authority=await inspectProjectReproductionWithCatalog(faulty,options);
// The inert bundle decoder uses null-prototype records. Compare the complete
// JSON identity data rather than record prototypes.
assert.deepEqual(JSON.parse(JSON.stringify(bundle.identities)),authority.identities,
  'R5 bundle must have actual LeaseService project authority');
assert.equal(sha(await bytes(flags['--model'])),sha(await bytes(authority.project.declaration.model.source)),'oracle model differs from admitted project');
assert.equal(sha(await bytes(flags['--lock'])),sha(await bytes(authority.project.declaration.model.lock)),'oracle lock differs from admitted project');
assert.equal(authority.project.replay.traces.length,2);
for(const trace of authority.project.replay.traces)assert.equal(
  sha(await bytes(typeof trace==='string'?trace:trace.path)),sha(await bytes(flags['--original-trace'])),
  'oracle original trace differs from admitted project');
const original=await reproduceProjectWithCatalog(faulty,bundle,options);
assert.equal(original.status,'reproduced');
const framework={catalogRaw:input.catalogRaw,selectionRef:input.selectionRef,combinationId:options.combinationId,
  observed:input.observed,installation,...(input.approval===undefined?{}:{approval:input.approval})};
const correct=await inspectProjectReproductionWithCatalog(join(runtime,'applications/lease-project/mirror.correct.project.json'),options);
const traces=[{path:resolve(flags['--out']),sha256:candidateHash},{path:resolve(flags['--out']),sha256:candidateHash}];
// Populate both required tools before selecting the candidate corpus: an
// incomplete LoadedProject would be reloaded from its original declaration.
const correctPrepared=await checkProject(correct.project,{framework});
const faultyPrepared=await checkProject(authority.project,{framework});
const baseline=await replayProject({...correctPrepared,replay:{...correctPrepared.replay,traces}}, {framework});
assert.equal(baseline.outcome,'passed');assert.equal(baseline.acceptance.status,'met');
const candidate=await replayProject({...faultyPrepared,replay:{...faultyPrepared.replay,traces}}, {framework});
assert.equal(baseline.identities.corpusDigest,oracle.candidateCorpusSha256,'baseline did not use the reduced corpus');
assert.equal(candidate.identities.corpusDigest,oracle.candidateCorpusSha256,'fault did not use the reduced corpus');
const observed=signatureFromSuiteResult(candidate);
assert.equal(candidate.outcome,'mismatch');assert(signaturesEqual(bundle.signature,observed),'candidate changed the original failure signature');
for(const suite of [original.suiteResult,baseline,candidate])assert.deepEqual(suite.cleanup,{scope:'local',status:'succeeded',quiescence:'confirmed',bindingStatus:'succeeded'});
assert.equal(sha(await bytes(flags['--out'])),candidateHash,'candidate changed during replay');
assert.equal(sha(await bytes(flags['--bundle'])),sha(bundleBytes),'original bundle changed');
assert.deepEqual((await inspectProjectReproductionWithCatalog(faulty,options)).identities,authority.identities,'project authority changed');
const acceptance={schema:'mirrors.lease-reduction-acceptance/v1',status:'reduced',globalMinimumClaim:false,
  originalBundleSha256:sha(bundleBytes),candidateTraceSha256:candidateHash,oracleReceiptSha256:sha(oracleBytes),
  originalSignature:bundle.signature,candidateSignature:observed,originalReplayStatus:original.status,
  baseline,candidate};
await writeFile(join(dirname(resolve(flags['--receipt'])),'lease-reduction-acceptance.json'),JSON.stringify(acceptance)+'\n',{flag:'wx',mode:0o600});
console.log(JSON.stringify({status:'reduced',sameSignature:true,modelValidity:'confirmed',cleanup:'confirmed'}));
