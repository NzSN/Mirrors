#!/usr/bin/env node
/** Capture the actual installed LeaseService baseline and expired-token origin. */
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {constants} from 'node:fs';
import {lstat,open} from 'node:fs/promises';
import {dirname,resolve,join} from 'node:path';
import {fileURLToPath} from 'node:url';
const [argument]=process.argv.slice(2);
assert(argument&&process.argv.length===3,'Usage: installed-lease-origin.mjs OUTPUT_ROOT');
const runtime=resolve(dirname(fileURLToPath(import.meta.url)),'../../../..');
assert.equal(process.cwd(),runtime,'run from the selected installed runtime');
const output=resolve(argument),info=await lstat(output);
assert(info.isDirectory()&&!info.isSymbolicLink()&&(info.mode&0o777)===0o700,'output must be a mode-0700 directory');
assert.equal(info.uid,process.getuid(),'output owner differs');
const cleanup={scope:'local',status:'succeeded',quiescence:'confirmed',bindingStatus:'succeeded'};
async function read(path){
  const handle=await open(path,constants.O_RDONLY|constants.O_NOFOLLOW);
  try{const stat=await handle.stat();assert(stat.isFile()&&stat.size<=16*1024*1024);return JSON.parse(await handle.readFile('utf8'));}
  finally{await handle.close();}
}
async function replay(mode,filename,expectedExit){
  const argv=[join(runtime,'packages/mirrorecma/dist/cli.js'),'replay','--project',
    join(runtime,'applications/lease-project',`mirror.${mode}.project.json`),'--framework-input',
    join(runtime,'framework-input.json'),'--combination','candidate.local-node-checked',
    '--result-file',join(output,filename)];
  const result=await new Promise((done,reject)=>{
    const child=spawn(process.execPath,argv,{stdio:['ignore','pipe','pipe'],shell:false});
    const chunks=[];let size=0;
    for(const stream of [child.stdout,child.stderr])stream.on('data',chunk=>{
      size+=chunk.length;if(size>8*1024*1024)child.kill('SIGKILL');else chunks.push(chunk);
    });
    child.once('error',reject);child.once('close',(code,signal)=>done({code,signal,log:Buffer.concat(chunks).toString('utf8')}));
  });
  assert.equal(result.code,expectedExit,`installed ${mode} replay failed (${result.code??result.signal}): ${result.log}`);
  const suite=await read(join(output,filename));
  assert.equal(suite.schema,'mirrorecma.suite-result/v1');
  assert.equal(suite.suiteId,'lease-service.reference-installed/v1');
  assert.deepEqual(suite.cleanup,cleanup);
  return suite;
}
try{
const baseline=await replay('correct','lease-baseline.json',0);
assert.equal(baseline.outcome,'passed');assert.equal(baseline.conformance,'matched');assert.equal(baseline.acceptance.status,'met');
const fault=await replay('faulty','lease-origin.json',1);
assert.equal(fault.outcome,'mismatch');assert.equal(fault.conformance,'mismatch');
assert.equal(fault.failure.kind,'mismatch');assert.equal(fault.failure.code,'model_mismatch');
assert.equal(fault.failure.traceIndex,0);assert.equal(fault.failure.stateIndex,5);assert.equal(fault.failure.action,'write');
console.log(JSON.stringify({baseline:'passed',origin:'mismatch',action:'write',stateIndex:5,cleanup:'confirmed'}));
process.exitCode=1;

}catch(error){console.error(error);process.exitCode=2;}
