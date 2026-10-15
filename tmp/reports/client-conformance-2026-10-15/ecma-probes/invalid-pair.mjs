// Run only on the selected remote WSL host:
// node invalid-pair.mjs /absolute/prepared/MirrorECMA
// Uses the existing compiled client; never builds or launches a model checker.
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';

const root = process.argv[2];
if (!root) throw new Error('Expected prepared MirrorECMA root argument');
const client = await import(pathToFileURL(resolve(root, 'dist/client.js')).href);
const model = await import(pathToFileURL(resolve(root, 'dist/model-interface.js')).href);
const semanticDigest = model.semanticDigestFromHex('a'.repeat(64));
const metadata = {
  semanticDigest: 'a'.repeat(64),
  contract: {
    schema: 'mirrors.model-interface/v1', interfaceVersion: '1.0.0',
    model: {module: 'Counter', source: 'Counter.tla'},
    wire: {actionVariable: 'action_taken', parameterVariable: null},
    initializers: [{id: 'Initialize', wireAction: 'init', wireAliases: [], inputs: []}],
    actions: [], observations: [{id: 'Count', wireName: 'count', provenance: 'implementation'}],
  },
};
const results = [];
for (const [name, contract, explicit] of [
  ['callback-valid-control', 'mirrors.state-computer/v1', false],
  ['callback-invalid-pair', 'mirrors.async-state-computer/v1', false],
  ['explicit-sync-invalid-pair', 'mirrors.async-state-computer/v1', true],
]) {
  const counts = {factory: 0, computer: 0, dispose: 0, close: 0, sends: 0};
  const key = {semanticDigest, adapterId: 'counter', targetProfile: 'mirrorecma-v1',
    stateComputerContractVersion: contract};
  const registry = new client.CompiledAdapterRegistry([{key, factory: () => {
    counts.factory++;
    return {semanticDigest, computer: () => { counts.computer++; return {}; },
      assertCompatibleConfig: () => {}, dispose: () => { counts.dispose++; }};
  }}]);
  const transport = {
    mode: 'network', send: () => { counts.sends++; }, close: async () => { counts.close++; return 0; },
    async *[Symbol.asyncIterator]() {
      yield JSON.stringify({proto_step: 'spec_validated', result: 'valid', modelInterface: {
        schema: 'mirrors.model-interface-negotiation/v1', status: 'matched',
        descriptorSchema: 'mirrors.model-interface-descriptor/v1', semanticDigest: `sha256:${semanticDigest}`,
      }});
      yield JSON.stringify({proto_step: 'initial_state', action: 'init', state: {}});
      yield JSON.stringify({proto_step: 'step_ok'});
      yield JSON.stringify({proto_step: 'all_steps_done'});
    },
  };
  const selection = {metadata, adapterId: key.adapterId, targetProfile: key.targetProfile,
    stateComputerContractVersion: key.stateComputerContractVersion, registry,
    ...(explicit ? {execution: 'sync'} : {})};
  try {
    const report = await client.runClientWithTracesNegotiatedWithReport(transport,
      {specPath: 'Counter.tla', invariant: 'TraceComplete', lengthBound: 2}, [], selection);
    results.push({name, outcome: 'accepted', reportStatus: report.status, counts});
  } catch (error) {
    results.push({name, outcome: 'rejected', code: error.code, message: error.message, counts});
  }
}
console.log(JSON.stringify({probe: 'ECMA-MI4-target-computer-pair', root, results}, null, 2));
