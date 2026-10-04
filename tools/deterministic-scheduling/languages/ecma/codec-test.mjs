import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {performance} from 'node:perf_hooks';
import {fromWire} from './value-bridge.mjs';
import * as generated from './generated/native/WriteSentryMBTMirror.generated.js';
const probe=JSON.parse(readFileSync(process.argv[2],'utf8'));
const raw=probe.records[0].reply.state;
const observation=()=>{const state=fromWire(raw);return Object.fromEntries(generated.WriteSentryMBTModelInterface.contract.observations.map(o=>[o.id,state[o.wireName]]));};
const context=()=>({signal:new AbortController().signal,deadline:performance.now()+5_000});
const input={action:'init',payload:{},previous:{}};
for(const mode of ['valid','wrong-key-kind','duplicate-key','wrong-integer-value']){
 const values=observation();
 if(mode==='wrong-key-kind')values.Dr[0][1][0][0]='4';
 if(mode==='duplicate-key')values.Dr[0][1].push(values.Dr[0][1][0]);
 if(mode==='wrong-integer-value')values.Budget=10;
 const binding=generated.bindWriteSentryMBTAsyncPublicPort({invoke:async()=>{},observe:async()=>values},{paramVars:'parameters'});
 if(mode==='valid'){const state=await binding.computer(input,context());assert.equal(state.dr.tag,'map');assert.equal(state.dr.val[0][1].val[0][0].tag,'int');}
 else{await assert.rejects(binding.computer(input,context()),{code:'observation_shape_mismatch'});await assert.rejects(binding.computer(input,context()),{code:'binding_poisoned'});}
}
assert.throws(()=>fromWire(Number.MAX_SAFE_INTEGER+1));
assert.equal(fromWire({'#bigint':'1208925819614629174706176'}),1208925819614629174706176n);
console.log('async-v2 native map codecs: valid, wrong-key, duplicate, integer type, poison and precision gates pass');
