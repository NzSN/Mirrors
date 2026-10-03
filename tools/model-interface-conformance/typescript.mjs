// Execute fresh generated TypeScript through its public binding interface.
// The only JSON/Value conversion is the client SDK's ordinary wire codec.
import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
import {join} from 'node:path';

const [fixtures, generated, sdk, target] = process.argv.slice(2);
if (!['ts', 'async'].includes(target)) throw new Error('expected ts or async');
const rows = async (name) => (await readFile(join(fixtures, name), 'utf8')).trim().split('\n').map(JSON.parse);
const load = async (file) => import('data:text/javascript;base64,' + Buffer.from(
  stripTypeScriptTypes(await readFile(file, 'utf8'), {mode:'transform', sourceUrl:file}),
).toString('base64'));
const {decodeMirrorMessage, encodeState, encodeReportState} = await load(join(sdk, 'src/protocol.ts'));
const decode = (state) => decodeMirrorMessage(JSON.stringify({proto_step:'initial_state', action:'init', state})).state;
const lower = (name) => name[0].toLowerCase() + name.slice(1);
const modules = new Map();
async function module(name) {
  if (!modules.has(name)) modules.set(name, await load(join(generated, target, name, name + 'Mirror.generated.ts')));
  return modules.get(name);
}
async function bind(name, port, valid=true) {
  const source = await module(name);
  return source['bind' + name + (target === 'async' ? 'Async' : '')](port, {paramVars:valid?'parameters':'wrong'});
}
async function compute(binding, action, payload) {
  const state=decode(payload);
  if (target === 'async') return binding.computer({action,payload:state,previous:{}},
    {signal:new AbortController().signal,deadline:performance.now()+10000});
  return binding.computer(action,state,{});
}
const emit = (family, id, result) => console.log(JSON.stringify({family,id,...result}));
for(const name of ['Portable','Recording']) {
  const identity=(await module(name))[name+'ModelInterface'];
  emit('identity',name,{semanticDigest:identity.semanticDigest,contract:identity.contract});
}
const types = (await rows('mitl-types.jsonl')).filter(row=>row.portable);
const defaults = Object.fromEntries(types.map(row=>[lower(row.id),row.default]));

async function roundtrip(typeId, value, mutation) {
  let saved, effects=0;
  const binding=await bind('Portable', {
    initialize(input) { effects++; saved=input; },
    observe() {
      effects++;
      if(mutation==='duplicate-set') saved={...saved,integers:[1n,1n]};
      if(mutation==='duplicate-nested-set') saved={...saved,nestedSets:[[1n,2n],[2n,1n]]};
      return saved;
    },
  });
  try {
    const result=encodeState(await compute(binding,'init',{...defaults,[lower(typeId)]:value}));
    const again=encodeState(await compute(binding,'init',result));
    return {accepted:true,output:result[lower(typeId)],again:again[lower(typeId)],effects};
  } catch(error) {
    const firstEffects=effects;
    let poisoned=false;
    try { await compute(binding,'init',defaults); }
    catch(next) { poisoned=next.code==='binding_poisoned' && effects===firstEffects; }
    return {accepted:false,error:error.code,effects,poisoned};
  }
}
for(const row of await rows('mitl-values.jsonl')) emit('value',row.id,await roundtrip(row.typeId,row.value));
for(const row of await rows('mitl-equivalence.jsonl')) emit('equivalence',row.id,{
  left:await roundtrip(row.typeId,row.left),right:await roundtrip(row.typeId,row.right),
});
for(const row of await rows('native-encoding.jsonl')) emit('encode',row.id,
  await roundtrip(row.field,defaults[lower(row.field)],row.mutation));
for(const row of await rows('mitl-paths.jsonl')) {
  if(row.static===false || row.generatedPortable===false) continue;
  let saved,effects=0;
  const binding=await bind('Path'+row.id,{
    initialize(input) {effects++; saved=input.value;},
    observe() {effects++; return {value:saved};},
  });
  try {
    const result=encodeState(await compute(binding,'init',row.stateRoot?row.value:{root:row.value}));
    emit('path',row.id,{accepted:true,output:result.value,effects});
  } catch(error) {emit('path',row.id,{accepted:false,error:error.code,effects});}
}
for(const row of await rows('counter-binding-events.jsonl')) {
  if(row.targets && !row.targets.includes(target)) continue;
  const events=[],errors=[],wireFrames=[];
  let count=0n,mode='ok',binding;
  const bigint=(n)=>({'#bigint':String(n)});
  try {
    binding=await bind('Recording',{
      initialize() {
        events.push({event:'action',id:'Initialize',inputs:{}});
        if(mode==='adapter_failure') throw new Error('deliberate adapter failure');
        count=0n;
      },
      tick({enabled,stride}) {
        events.push({event:'action',id:'Tick',inputs:{Enabled:enabled,Stride:bigint(stride)}});
        if(mode==='adapter_failure') throw new Error('deliberate adapter failure');
        if(enabled) count+=stride;
      },
      observe() {
        if(mode==='observer_failure') {events.push({event:'observe_failure'});throw new Error('deliberate observer failure');}
        events.push({event:'observe',values:{Count:bigint(count)}});
        if(mode==='missing_observation') return {};
        if(mode==='extra_observation') return {count,extra:true};
        if(mode==='mistyped_observation') return {count:'wrong'};
        return {count};
      },
    },row.configValid);
  } catch(error) {errors.push(error.code);}
  if(binding) for(const step of row.steps) {
    mode=step.mode;
    try {
      const result=await compute(binding,step.action,step.payload);
      wireFrames.push(encodeReportState(result));
      events.push({event:'report',state:encodeState(result)});errors.push(null);
    } catch(error) {errors.push(error.code);}
  }
  emit('recording',row.id,{events,errors,coverage:binding?binding.coverage():{Initialize:0,Tick:0},wireFrames});
}
