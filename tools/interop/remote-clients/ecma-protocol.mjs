import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';
const env=process.env;
const sdk=await import(pathToFileURL(resolve(env.ECMA_REPO,'dist/index.js')));
const {connectTlsMirror,runClient,runClientWithTraces,runClientGenTraces,
  runClientExplore,startExploreSession,specFromFile,specFromFiles,presetClient,
  asInt,getParam}=sdk;
const connect=()=>connectTlsMirror('172.20.208.1',8999,{
  caPath:env.MIRRORS_REMOTE_CA,certPath:env.MIRRORS_REMOTE_CLIENT_CERT,
  keyPath:env.MIRRORS_REMOTE_CLIENT_KEY,pin:env.MIRRORS_REMOTE_SERVER_PIN});
const winRoot='C:\\Users\\ayden\\Desktop\\Workspace\\MirrorsRemote\\interop';
const config={specPath:winRoot+'\\Counter.tla',invariant:'TraceComplete',
  lengthBound:6,constInit:'CInit',paramVars:'parameters'};
const generation={numTraces:4,view:'View'};
const counter=(wrong=false)=>{
  let count=0n;
  return (_action,params,previous)=>{
    if (!previous.count) count=0n;
    else count+=asInt(getParam(params,'parameters')?.stride)??0n;
    return {count:{tag:'int',val:count},...(wrong?{unexpected:{tag:'bool',val:true}}:{})};
  };
};
const rows=[];
const check=async(name,fn)=>{await fn();rows.push({case:name,status:'passed'});console.log('remote ECMA '+name+': PASS');};
await check('register',async()=>runClient(await connect(),config,generation,counter()));
await check('mismatch',async()=>{
  await assert.rejects(()=>connect().then(t=>runClient(t,config,generation,counter(true))),
    error=>/step mismatch/.test(error.message)&&/unexpected/.test(error.message));
});
await check('register_traces',async()=>{
  const states=[0n,2n,4n,6n,8n,10n,13n].map(val=>({count:{tag:'int',val}}));
  await runClientWithTraces(await connect(),config,[winRoot+'\\violation.itf.json'],presetClient(states));
});
await check('register_trace_gen',async()=>{
  const result=await runClientGenTraces(await connect(),config,null,generation);
  assert(result.itfTraces.length>0);assert.equal(result.itfTraces.length,result.itfTracePaths.length);
  for(const [i,trace] of result.itfTraces.entries()){
    assert(Array.isArray(trace.states)&&trace.states.length>0);
    await writeFile(resolve(env.M5_INTEROP_OUTPUT,'ecma-generated-'+i+'.itf.json'),JSON.stringify(trace)+'\n',{flag:'wx',mode:0o600});
  }
});
const hourClock=await specFromFile(resolve(env.ECMA_REPO,'specs/HourClock.tla'));
await check('register_explore',async()=>runClientExplore(await connect(),hourClock,['Inv'],[],4,(_action,params,previous)=>{
  if(!previous.hr)return params;
  const hr=asInt(previous.hr),step=asInt(previous.step_count);
  return {hr:{tag:'int',val:hr===12n?1n:hr+1n},latest_hr:{tag:'int',val:hr},
    ticked:{tag:'bool',val:true},action_taken:{tag:'str',val:'tick'},
    nondet_picks:previous.nondet_picks,step_count:{tag:'int',val:step+1n}};
}));
await check('register_explore_session',async()=>{
  const session=await startExploreSession(await connect(),hourClock,['Inv'],[]);
  try{
    assert.equal(session.ready.initTransitions,1);assert(session.ready.nextTransitions>0);
    assert.equal(session.ready.stateInvariants,1);
    assert.equal(await session.assumeTransition(0),'ENABLED');assert.equal(await session.nextStep(),1);
    const state=await session.queryState();assert(state.hr);
    assert.equal(await session.checkInvariant(0),'SATISFIED');
    assert.equal(await session.assumeState({hr:state.hr}),'ENABLED');assert.equal(await session.rollback(0),0);
  }finally{await session.done();}
});
await check('inline_multimodule',async()=>{
  const spec=await specFromFiles(resolve(env.ECMA_REPO,'specs/ExtMain.tla'));assert.equal(spec.sources.length,2);
  await runClient(await connect(),{specPath:'/nonexistent/ExtMain.tla',invariant:'TraceComplete',lengthBound:3},
    {numTraces:1},(_action,params,previous)=>previous.count?{
      count:{tag:'int',val:asInt(previous.count)+1n},action_taken:{tag:'str',val:'tick'}}:params,{spec});
});
await writeFile(resolve(env.M5_INTEROP_OUTPUT,'ecma-protocol-receipt.json'),
  JSON.stringify({schema:'mirrors.remote-ecma-protocol/v1',transport:'pinned-mtls',rows},null,2)+'\n',
  {flag:'wx',mode:0o600});
