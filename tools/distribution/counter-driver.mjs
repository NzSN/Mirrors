import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { defineSuite, runSuite } from "/tmp/runtime/packages/mirrorecma/dist/index.js";
import { CounterModel } from "/tmp/runtime/examples/counter-suite/Counter.suite.js";
import { installedCounterPort } from "./installed-counter.mjs";

const variant = process.argv[2];
if (!['correct', 'faulty'].includes(variant)) throw new Error('variant');
const sha256 = async (path) => createHash('sha256').update(await readFile(path)).digest('hex');
const suite = defineSuite({
  id: 'installed-counter/v1',
  adapterId: 'installed-counter.adapter/v1',
  model: CounterModel,
  replay: {
    kind: 'corpus',
    config: {specPath:'/tmp/runtime/examples/Counter.tla',constInit:'CInit',invariant:'TraceComplete',lengthBound:6,paramVars:'parameters'},
    traces: [{path:'/tmp/runtime/examples/counter.itf.json',sha256:await sha256('/tmp/runtime/examples/counter.itf.json')}],
    provenance: {interfaceDigest:CounterModel.semanticDigest,modelSha256:await sha256('/tmp/runtime/examples/Counter.tla')},
  },
  acceptance: {requiredActions:['Tick'],requiredPairs:[['Tick','Tick']]},
});
const result = await runSuite(suite, {
  mirror: '/tmp/runtime/bin/ModelMirrors',
  timeouts: {registrationMs:10000,actionMs:1000,receiveMs:10000,cleanupMs:5000},
  implementation: async () => ({port: installedCounterPort(variant), dispose() {}}),
});
console.log(JSON.stringify({variant,result}, (_key,value)=>typeof value==='bigint'?value.toString():value));
