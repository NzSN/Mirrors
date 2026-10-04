import {createHash} from 'node:crypto';
import {readFileSync,readdirSync,statSync,writeFileSync} from 'node:fs';
import {dirname,resolve,relative} from 'node:path';
import {fileURLToPath} from 'node:url';
import {isDeepStrictEqual} from 'node:util';
import {AsyncCompiledAdapterRegistry,semanticDigestFromHex,ScheduleBindingSession,parseCheckpointSchedule,replayScheduledTraces,WORKER_SCHEDULE_PROFILE,SCHEDULE_SCHEMA,spawnMirror,exploreFiniteSchedules,localWorkerExplorationRunner} from 'mirrorecma';
import {fromWire} from './value-bridge.mjs';
import * as counter from './generated/counter/ScheduledCounterMirror.generated.js';
import * as native from './generated/native/WriteSentryMBTMirror.generated.js';
const here=dirname(fileURLToPath(import.meta.url));
const requireValue=(v,message)=>{if(!v)throw new Error(message);};
const read=p=>JSON.parse(readFileSync(p,'utf8'));
const hash=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
function closureHash(worker){
 const packageDir=dirname(fileURLToPath(import.meta.resolve('mirrorecma'))),files=[];
 const collect=(dir)=>{for(const name of readdirSync(dir).sort()){const p=resolve(dir,name);if(statSync(p).isDirectory())collect(p);else if(name.endsWith('.js'))files.push(['sdk/'+relative(packageDir,p),hash(p)]);}};
 collect(packageDir);
 for(const name of ['runner.mjs','counter-worker.mjs','native-worker.mjs','value-bridge.mjs','generated/counter/ScheduledCounterMirror.generated.js','generated/native/WriteSentryMBTMirror.generated.js'])files.push([name,hash(resolve(here,name))]);
 files.push(['sdk/package.json',hash(resolve(packageDir,'../package.json'))]);files.push(['node',hash(process.execPath)]);if(worker)files.push(['native-worker',hash(worker)]);
 return createHash('sha256').update(JSON.stringify(files)).digest('hex');
}
const args=Object.create(null);for(let i=2;i<process.argv.length;i++){const key=process.argv[i];if(!key.startsWith('--')||Object.hasOwn(args,key))throw new Error('invalid/duplicate option');if(key==='--describe'){args[key]=true;continue;}if(++i===process.argv.length)throw new Error('missing option value');args[key]=process.argv[i];}
const kind=args['--kind']??'counter',mode=args['--mode']??'ok';
requireValue(['counter','native','explore'].includes(kind),'unknown consumer kind');
const mapping=read(args['--mapping']);
const expectedCounterMapping={schema:'mirrors.dpm-counter-mapping/v1',profile:WORKER_SCHEDULE_PROFILE,actors:[{actor:'a',operation:'increment-a'},{actor:'b',operation:'increment-b'}],actions:{read:'read',write:'write',finish:'$done'}};
function exact(value,keys){requireValue(value&&typeof value==='object'&&!Array.isArray(value)&&isDeepStrictEqual(Object.keys(value).sort(),[...keys].sort()),'invalid native mapping fields');}
const nativePhases=new Set(['Reserve','ArmLock','ArmSelect','PublishOdd','PublishPayload','PublishEven','ArmUnlock','ArmTarget','ArmFinishLock','ArmFinishUnlock','ArmOutcome','Release','CallDone','WriteBegin','TrapEntry','SnapshotProbe','SnapshotNoAdmission','SnapshotAdmissionChecked','SnapshotLease','SnapshotAdmissionLost','SnapshotAdmissionValidated','SnapshotSeq1','SnapshotInvalid','SnapshotPayload','SnapshotSeq2','SnapshotTorn','SnapshotAccepted','ContextRejected','OwnerRejected','LoadRejected','Filtered','Hit','HitReleased','WriteDone']);
function validateNative(value){
 exact(value,['schema','profile','roles','modelSteps']);requireValue(value.schema==='mirrors.dpm3-native-mapping/v1'&&value.profile==='dpm-writesentry-two-operation/v1'&&Array.isArray(value.modelSteps)&&value.modelSteps.length>0&&value.modelSteps.length<=150,'unsupported native pilot');exact(value.roles,['arm','write']);
 for(const role of ['arm','write']){exact(value.roles[role],['nativeActor','operation']);requireValue(['t1','t2'].includes(value.roles[role].nativeActor)&&value.roles[role].operation===(role==='arm'?'Arm':'Write'),'invalid native role');}
 const started={arm:false,write:false},done={arm:false,write:false},active={t1:null,t2:null};
 for(const step of value.modelSteps){exact(step,['role','request','parameters']);const role=step.role,p=step.parameters,q=step.request;requireValue(Object.hasOwn(started,role)&&!done[role],'unknown or reused native role');exact(p,['action','thread','command','address','value','writer','span','entry','slot','target']);
  requireValue(p.thread===value.roles[role].nativeActor&&p.command===value.roles[role].operation&&p.address==='A1'&&p.value===(role==='arm'?'good':'bad')&&p.writer==='allowed'&&p.span===1&&nativePhases.has(p.action),'unsupported native concrete inputs');
  requireValue([p.entry,p.slot].every(x=>Number.isInteger(x)&&x>=0&&x<=4)&&['t1','t2','noThread'].includes(p.target),'native index/target outside scope');
  if(!started[role]){exact(q,['op','thread','command','address','value','writer','span']);requireValue(q.op==='Begin'&&active[p.thread]===null&&p.action===(role==='arm'?'Reserve':'WriteBegin'),'invalid native begin');for(const k of ['thread','command','address','value','writer','span'])requireValue(q[k]===p[k],'native/model input mismatch');started[role]=true;active[p.thread]=role;}
  else{exact(q,['op','thread']);requireValue(q.op==='Advance'&&q.thread===p.thread&&active[p.thread]===role,'invalid native continuation');}
  if(p.action==='CallDone'){done[role]=true;active[p.thread]=null;}
 }
 requireValue(done.arm&&done.write,'pilot operations incomplete');
}
if(kind==='native')validateNative(mapping);else requireValue(isDeepStrictEqual(mapping,expectedCounterMapping),'unsupported counter mapping');
const model=kind==='native'?native:counter;
const digest=kind==='native'?native.WriteSentryMBTSemanticDigest:counter.ScheduledCounterSemanticDigest;
const identity={modelSemanticDigest:digest,mappingSha256:hash(args['--mapping']),implementationSha256:closureHash(args['--worker'])};
if(args['--launcher'])identity.implementationSha256=createHash('sha256').update(identity.implementationSha256+'\n'+hash(args['--launcher'])).digest('hex');
if(args['--describe']){console.log(JSON.stringify({profile:WORKER_SCHEDULE_PROFILE,identity}));process.exit(0);}
const stats={acquisitions:0,enteredWorkers:0,teardowns:0},stop=new AbortController();
const big=n=>({'#bigint':String(n)}),map=values=>({'#map':[['a',big(values[0])],['b',big(values[1])]]});
function counterAdapter(){return{identity,actors:expectedCounterMapping.actors,checkpoints:['read','write'],factory(inputs){
 requireValue(inputs&&[0,5].includes(inputs.initial)&&['ok','mutate','teardown-fail','mutate-and-teardown-fail','unexpected-checkpoint','cancel','bad-observation','denied-negotiation','reentrant'].includes(inputs.mode),'invalid counter input');stats.acquisitions++;const buffer=new SharedArrayBuffer(40),state=new Int32Array(buffer);state[0]=inputs.initial;
 return{workers:['a','b'].map((actor,index)=>({actor,module:new URL('./counter-worker.mjs',import.meta.url),data:{buffer,index,mode:inputs.mode==='mutate-and-teardown-fail'?'mutate':inputs.mode==='unexpected-checkpoint'?'unknown':inputs.mode}})),
  observe(){return{count:big(state[0]),saved:map([state[3],state[4]]),phase:map([state[5],state[6]])};},
  teardown(){stats.enteredWorkers+=state[1];stats.teardowns++;if(['teardown-fail','mutate-and-teardown-fail'].includes(inputs.mode))throw new Error('deliberate teardown failure');}
 };
}};}
class NativeContext {
 transport;iterator;state;identity;transcript=[];acquisitions=0;cleanups=0;closed=false;quitAcknowledged=false;exitCode=-1;
 async invoke(request){const wire=JSON.stringify(request);this.transport.send(wire);const next=await this.iterator.next();if(next.done)throw new Error('native peer ended');const reply=JSON.parse(next.value);this.transcript.push({request,reply});requireValue(this.transcript.length<=512,'native transcript cap');if(reply.error)throw new Error(reply.error);const actual=reply.nativeIdentity;
  if(!this.identity){requireValue(actual&&actual.imageSha256===(mode==='wrong-image'?'0'.repeat(64):hash(args['--worker']))&&Number.isInteger(actual.processId)&&actual.processId>0&&typeof actual.createdFileTime==='string'&&actual.createdFileTime.length>0,'native image/process mismatch');requireValue(actual.actors&&Object.keys(actual.actors).length===2&&['t1','t2'].every(k=>Number.isInteger(actual.actors[k])&&actual.actors[k]>0)&&actual.actors.t1!==actual.actors.t2,'native thread identity invalid');this.identity=actual;}
  else requireValue(isDeepStrictEqual(actual,this.identity),'native process/thread identity changed');
  if(reply.state)this.state=reply.state;return reply;
 }
 async start(){requireValue(!this.acquisitions,'native context is single-use');this.acquisitions++;this.transport=spawnMirror(args['--launcher']);this.iterator=this.transport[Symbol.asyncIterator]();try{await this.invoke({op:'Initialize'});}catch(error){try{await this.finish();}catch{}throw error;}}
 async finish(){if(this.closed)return;this.closed=true;this.cleanups++;let failure;
  try{const reply=await this.invoke({op:'Quit'});this.quitAcknowledged=reply.closed===true;if(!this.quitAcknowledged)failure=new Error('native quit acknowledgement missing');}catch(error){failure=error;}
  try{this.exitCode=await this.transport.close();}catch(error){failure??=error;}this.transport=undefined;requireValue(this.exitCode===0&&!failure,failure?.message??'native worker exit failed');
 }
 receipt(){return{schema:'mirrors.dpm-native-bridge/v1',identity:this.identity??null,acquisitions:this.acquisitions,cleanups:this.cleanups,quitAcknowledged:this.quitAcknowledged,exitCode:this.exitCode,closed:this.closed,transcript:this.transcript};}
}
const nativeContext=new NativeContext();
function nativeAdapter(){const commands={arm:[],write:[]};for(const step of mapping.modelSteps)commands[step.role].push(step.request);return{identity,actors:[{actor:'arm',operation:'native-arm-operation'},{actor:'write',operation:'native-write-operation'}],checkpoints:[...new Set(mapping.modelSteps.map(s=>s.parameters.action))].sort(),async factory(){await nativeContext.start();return{
 workers:['arm','write'].map(actor=>({actor,module:new URL('./native-worker.mjs',import.meta.url),data:{commands:commands[actor]}})),
 request(_actor,input){return nativeContext.invoke(input);},observe(){return nativeContext.state;},teardown(){return nativeContext.finish();}
};}};}
if(kind==='explore'){
 const initialMode=args['--fixture-mode']??'ok';const adapter=counterAdapter(),runner=localWorkerExplorationRunner(adapter,{executionTimeoutMs:5_000,cleanupTimeoutMs:2_000});
 const space={identity,actors:expectedCounterMapping.actors.map(actor=>({actor,checkpoints:['read','write','$done']})),inputs:[{initial:0,mode:initialMode},{initial:5,mode:initialMode}],maxPreemptions:Number(args['--preemptions']??64),requireModelComparison:args['--require-comparison']==='true',baseVariables:['count','saved','phase'],instrumentationVariables:[]};
 const result=await exploreFiniteSchedules(space,async(candidate,signal)=>{const sample=await runner(candidate,signal);if(initialMode==='cancel')stop.abort();return sample;},{maxRuns:Number(args['--max-runs']??4096),maxEnumeratedSchedules:Number(args['--max-enumerated']??4096),timeBudgetMs:Number(args['--time-ms']??30_000),maxEvidenceBytes:Number(args['--evidence-bytes']??16*1_048_576)},stop.signal);result.sut=stats;writeFileSync(args['--out'],JSON.stringify(result,null,2)+'\n');process.exit(0);
}
const schedule=parseCheckpointSchedule(readFileSync(args['--schedule'],'utf8'));
if(kind==='native'){const expected=[];for(const step of mapping.modelSteps){expected.push({actor:step.role,checkpoint:step.parameters.action});if(step.parameters.action==='CallDone')expected.push({actor:step.role,checkpoint:'$done'});}requireValue(isDeepStrictEqual(schedule.inputs,{})&&isDeepStrictEqual(schedule.steps,expected),'native schedule correspondence differs');}
const session=new ScheduleBindingSession(schedule,kind==='native'?nativeAdapter():counterAdapter(),{executionTimeoutMs:kind==='native'?240_000:5_000,cleanupTimeoutMs:kind==='native'?15_000:2_000},stop.signal);
let nativeIndex=0,currentBinding;
const publicPort={async invoke(operation,inputs,context){
 if(operation==='Initialize'){nativeIndex=0;await session.initialize();return;}
 if(kind==='native'){
  const next=mapping.modelSteps[nativeIndex];requireValue(next,'extra native operation');const parameters=Object.fromEntries(Object.entries(inputs).map(([k,v])=>[k[0].toLowerCase()+k.slice(1),typeof v==='bigint'?Number(v):v]));requireValue(operation===parameters.action&&isDeepStrictEqual(parameters,next.parameters),'generated native input differs from mapping');
  if(mode==='cancel'&&nativeIndex===1)stop.abort();await session.advance({actor:next.role,checkpoint:operation});if(operation==='CallDone')await session.advance({actor:next.role,checkpoint:'$done'});nativeIndex++;
 }else{if(schedule.inputs.mode==='reentrant'&&operation==='Read'){try{await currentBinding.computer({action:'read',payload:{parameters:{tag:'record',val:{actor:{tag:'str',val:inputs.Actor}}}},previous:{}},context);}catch{}return;}await session.advance({actor:inputs.Actor,checkpoint:{Read:'read',Write:'write',Finish:'$done'}[operation]});if(schedule.inputs.mode==='cancel')stop.abort();}
},async observe(){const state=fromWire(session.observation());if(kind==='native')return Object.fromEntries(native.WriteSentryMBTModelInterface.contract.observations.map(o=>[o.id,state[o.wireName]]));return{Count:schedule.inputs.mode==='bad-observation'?'wrong':state.count,Phase:state.phase,Saved:state.saved};}};
const metadata=kind==='native'?native.WriteSentryMBTModelInterface:counter.ScheduledCounterModelInterface;
const targetProfile=kind==='native'?native.WriteSentryMBTAsyncTargetProfile:counter.ScheduledCounterAsyncTargetProfile;
const semanticDigest=semanticDigestFromHex(digest),adapterId='dpm-'+kind;
const registry=new AsyncCompiledAdapterRegistry([{key:{semanticDigest:kind!=='native'&&schedule.inputs.mode==='denied-negotiation'?semanticDigestFromHex('f'.repeat(64)):semanticDigest,adapterId,targetProfile,stateComputerContractVersion:'mirrors.async-state-computer/v1'},factory:async config=>{
 const binding=kind==='native'?native.bindWriteSentryMBTAsyncPublicPort(publicPort,config):counter.bindScheduledCounterAsyncPublicPort(publicPort,config);
 currentBinding=binding;return{semanticDigest,computer:binding.computer,assertCompatibleConfig:binding.assertCompatibleConfig,coverage:binding.coverage,dispose:()=>session.dispose()};
}}]);
const selectedMetadata=kind!=='native'&&schedule.inputs.mode==='denied-negotiation'?{...metadata,semanticDigest:'f'.repeat(64)}:metadata;
const selection={execution:'async',metadata:selectedMetadata,adapterId,targetProfile,stateComputerContractVersion:'mirrors.async-state-computer/v1',registry,policy:'require'};
const config={specPath:resolve(args['--spec']),paramVars:'parameters',invariant:kind==='native'?'MBTSafety':'Safety',initPredicate:kind==='native'?'MBTInit':'Init',nextPredicate:kind==='native'?'MBTNext':'Next',lengthBound:6};
const repeats=Number(args['--repeats']??1);requireValue(Number.isInteger(repeats)&&repeats>=1&&repeats<=4,'invalid repeats');
const result=await replayScheduledTraces(args['--mirror'],config,Array.from({length:repeats},()=>resolve(args['--trace'])),selection,session,{deadlines:{registrationMs:60_000,stepMs:30_000,receiveMs:60_000}});
const evidence={...result.evidence,actualIdentity:identity,mode:kind==='native'?mode:schedule.inputs.mode,sut:stats,...(kind==='native'?{native:nativeContext.receipt(),profile:'dpm-writesentry-two-operation/v1',fullProductionQualified:false}:{})};
writeFileSync(args['--out'],JSON.stringify(evidence,null,2)+'\n');console.log(`${kind}: ${evidence.comparison}; passed=${evidence.passed}`);
