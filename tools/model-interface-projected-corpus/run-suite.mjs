#!/usr/bin/env node
// Public M6 acceptance: one reviewed corpus and generated model exercise the
// mutable implementation locally and through Gate's production worker bridge.
import assert from 'node:assert/strict';
import {mkdir, mkdtemp, readFile, writeFile, stat, access, cp, appendFile} from 'node:fs/promises';
import {resolve, join, dirname} from 'node:path';
import {pathToFileURL} from 'node:url';

const options = new Map();
for (let index = 2; index < process.argv.length; index += 2) {
  const flag = process.argv[index], value = process.argv[index + 1];
  assert(['--application', '--mirror', '--mirrorgate'].includes(flag) && value && !options.has(flag),
    'usage: run-suite.mjs [--application DIR] [--mirror PATH] [--mirrorgate PATH]');
  options.set(flag, value);
}
const application = resolve(options.get('--application') ?? process.cwd());
const operator = join(dirname(application), 'operator');
const mirror = resolve(options.get('--mirror') ?? join(operator, 'bin/mirror'));
const mirrorgate = resolve(options.get('--mirrorgate') ?? join(operator, 'bin/mirrorgate'));
const packageModule = (name, file = 'dist/index.js') =>
  import(pathToFileURL(join(application, 'node_modules', name, file)).href);
const [ecma, gate, kit, generated] = await Promise.all([
  packageModule('mirrorecma'), packageModule('mirrorgate-mirrorecma'),
  packageModule('mirrorgate', 'sdk/node/adapter-kit.mjs'),
  import(pathToFileURL(join(application, 'generated/ProjectedCells.suite.js')).href),
]);
const {defineSuite, loadProjectedCorpus, preflightSuite, runSuite, ReplayMismatchError} = ecma;
const {evaluateSuite} = gate;
const {ProjectedCellsModel: model} = generated;
assert.equal((await kit.checkAdapterKit(model.publicManifest, {directory: join(application, 'public-kit')})).current, true,
  'the actual worker public kit must match the generated manifest');

await mkdir(join(application, 'receipts'), {recursive: true, mode: 0o700});
const receiptDirectory = await mkdtemp(join(application, 'receipts', 'run-'));
const oracleMarker = join(receiptDirectory, 'forbidden-model-check.invoked');
const oracleSentinel = join(receiptDirectory, 'forbidden-model-check');
const shellQuote = value => "'" + value.replaceAll("'", "'\\''") + "'";
await writeFile(oracleSentinel,
  '#!/bin/sh\nprintf \'forbidden model-check invocation\\n\' >> ' + shellQuote(oracleMarker) + '\nexit 86\n',
  {mode: 0o700, flag: 'wx'});
process.env.APALACHE_MC = oracleSentinel;

const modelPath = join(application, 'source/test/fixtures/model-interface/projected-cells/ProjectedCells.tla');
const config = {specPath: modelPath, invariant: 'Inv', lengthBound: 6, paramVars: 'parameters'};
const loaded = await loadProjectedCorpus({directory: join(application, 'corpus'),
  lockPath: join(application, 'ProjectedCells.lock.json'), sourceRoot: join(application, 'source'), model, config});
const suite = defineSuite({id: 'projected-cells', adapterId: 'suite.projected-cells', model,
  replay: loaded.replay, acceptance: {requiredActions: ['Update'], requiredPairs: [['Update', 'Update']]}});
const preflight = await preflightSuite(suite);
assert.equal(preflight.traceDigests.length, loaded.identity.memberCount);
const expectedUpdates = preflight.actions.reduce((total, actions) => total + actions.filter(action => action === 'Update').length, 0);
const expectedPairs = preflight.actions.reduce((total, actions) => total + actions.filter((action, index) =>
  index > 0 && action === 'Update' && actions[index - 1] === 'Update').length, 0);
assert(expectedUpdates > 0 && expectedPairs > 0, 'the supplied corpus must exercise Update and Update/Update');
const timeouts = {registrationMs: 30000, actionMs: 5000, receiveMs: 30000, cleanupMs: 10000};
const printable = value => JSON.stringify(value, (_key, item) => typeof item === 'bigint' ? item.toString() : item);
const checks = [];
function checked(name) { checks.push(name); }
function assertCoverage(result, context) {
  assert.equal(result.conformance, 'matched', printable({context, result}));
  assert.equal(result.acceptance.status, 'met', printable({context, result}));
  assert.equal(result.evidence.complete, true);
  assert.equal(result.evidence.exact, true);
  assert.equal(result.evidence.tracesCompleted, loaded.identity.memberCount);
  assert.equal(result.evidence.initializationsMatched, String(loaded.identity.memberCount));
  assert.equal(result.evidence.transitionsMatched, String(expectedUpdates));
  assert.equal(result.evidence.actionCounts.Update, String(expectedUpdates));
  assert.equal(result.evidence.pairCounts['["Update","Update"]'], String(expectedPairs));
}
function assertMismatch(result, context) {
  assert.equal(result.outcome, 'mismatch', printable({context, result}));
  assert.equal(result.conformance, 'mismatch');
  assert.equal(result.failure?.code, 'model_mismatch');
  assert.equal(result.failure?.kind, 'mismatch');
  const error = result.trustedError;
  assert(error instanceof ReplayMismatchError, 'a real model comparison must produce ReplayMismatchError');
  assert.equal(error.traceIndex, 0);
  assert.equal(error.stateIndex, 0);
  assert.equal(error.action, 'init');
  const firstEntry = state => {
    assert.equal(state.cells.tag, 'seq');
    assert.equal(state.cells.val[0].tag, 'record');
    assert.equal(state.cells.val[0].val.entry.tag, 'record');
    return state.cells.val[0].val.entry.val;
  };
  const expected = firstEntry(error.expected), actual = firstEntry(error.actual);
  assert.equal(expected.count.tag, 'int'); assert.equal(actual.count.tag, 'int');
  assert.equal(expected.count.val, 0n); assert.equal(actual.count.val, 1n);
  assert.equal(expected.labels.tag, 'set'); assert.equal(actual.labels.tag, 'set');
  assert.equal(expected.weights.tag, 'map'); assert.equal(actual.weights.tag, 'map');
  return {code: result.failure.code, traceIndex: error.traceIndex, stateIndex: error.stateIndex,
    expected: error.toJSON().expected, actual: error.toJSON().actual};
}
function resultSummary(result) {
  return {outcome: result.outcome, conformance: result.conformance, acceptance: result.acceptance.status,
    actionCounts: result.evidence.actionCounts, pairCounts: result.evidence.pairCounts, cleanup: result.cleanup,
    ...(result.failure ? {failure: result.failure} : {})};
}

const local = {};
for (const variant of ['correct', 'faulty', 'dispose-failure']) {
  let acquisitions = 0, disposals = 0, adapter;
  const result = await runSuite(suite, {mirror, timeouts, implementation: async () => {
    acquisitions++;
    const implementation = await import(pathToFileURL(join(application, 'adapter.mjs')).href);
    assert.equal(typeof implementation.createAdapter, 'function');
    adapter = implementation.createAdapter({faulty: variant === 'faulty', disposeFailure: variant === 'dispose-failure',
      onDispose: () => { disposals++; }});
    return {port: adapter, dispose: () => adapter.dispose()};
  }});
  assert.equal(acquisitions, 1, printable({variant, result}));
  assert.equal(disposals, 1, printable({variant, result}));
  assert.equal(result.cleanup.quiescence, 'confirmed');
  assert.throws(() => adapter.observe(), /disposed/, 'disposed implementation state must be inaccessible');
  let mismatch;
  if (variant === 'correct') {
    assert.equal(result.outcome, 'passed', printable(result)); assertCoverage(result, 'local correct');
    assert.equal(result.cleanup.status, 'succeeded');
    checked('local mutable implementation, native collections, complete action/pair coverage and cleanup');
  } else if (variant === 'faulty') {
    mismatch = assertMismatch(result, 'local faulty observer');
    assert.equal(result.cleanup.status, 'succeeded');
    checked('local well-typed observer error produces real expected/actual model mismatch');
  } else {
    assertCoverage(result, 'local dispose failure');
    assert.equal(result.outcome, 'failed'); assert.equal(result.failure?.kind, 'cleanup');
    assert.equal(result.cleanup.status, 'failed');
    checked('local cleanup failure prevents overall acceptance after matching replay');
  }
  local[variant] = {...resultSummary(result), acquisitions, disposals, ...(mismatch ? {mismatch} : {})};
}

const firstTrace = loaded.replay.traces[0];
assert.equal(typeof firstTrace, 'object');
const denied = defineSuite({...suite, replay: {...loaded.replay,
  traces: [{...firstTrace, sha256: '0'.repeat(64)}, ...loaded.replay.traces.slice(1)]}});
let deniedMirrors = 0, deniedImplementations = 0;
const rejectedLocal = await runSuite(denied, {timeouts,
  mirror: () => { deniedMirrors++; throw new Error('admission failure must not acquire a mirror'); },
  implementation: () => { deniedImplementations++; throw new Error('admission failure must not acquire implementation'); },
});
assert.equal(rejectedLocal.outcome, 'failed'); assert.equal(rejectedLocal.failure?.kind, 'configuration');
assert.equal(rejectedLocal.conformance, 'not_evaluated');
assert.equal(rejectedLocal.cleanup.bindingStatus, 'not_started');
assert.equal(deniedMirrors, 0); assert.equal(deniedImplementations, 0);
local.admissionFailure = {...resultSummary(rejectedLocal), mirrorAcquisitions: deniedMirrors,
  implementationAcquisitions: deniedImplementations};
checked('local stale trace identity rejects before transport and implementation acquisition');

const environment = {taskRef: 'projected-cells', policyId: 'suite.projected-cells', runtime: 'node-v1',
  gate: {kind: 'owned', launcher: {command: mirrorgate}, policyFile: join(application, 'operator.json')}};
const gateOptions = variant => ({environment, mirror, timeouts,
  submission: {kind: 'source', input: {rootId: 'submission', relativePath: variant}, buildPlanId: 'node', authoring: false}});

// The corpus loader is the outer admission boundary. A changed file must fail
// before either local runtime acquisition or Gate control/provider preparation.
const tamperedCorpus = join(receiptDirectory, 'tampered-corpus');
await cp(join(application, 'corpus'), tamperedCorpus, {recursive: true});
const corpusManifest = JSON.parse(await readFile(join(tamperedCorpus, 'manifest.json'), 'utf8'));
await appendFile(join(tamperedCorpus, corpusManifest.members[0].trace.path), ' ');
const admissionCounts = {gatePreparations: 0, mirrorAcquisitions: 0, implementationAcquisitions: 0};
for (const runtime of ['local', 'gate']) {
  await assert.rejects(async () => {
    const admitted = await loadProjectedCorpus({directory: tamperedCorpus,
      lockPath: join(application, 'ProjectedCells.lock.json'), sourceRoot: join(application, 'source'), model, config});
    const admittedSuite = defineSuite({...suite, replay: admitted.replay});
    const acquireMirror = () => { admissionCounts.mirrorAcquisitions++; throw new Error('invalid corpus acquired a mirror'); };
    if (runtime === 'local') return runSuite(admittedSuite, {mirror: acquireMirror, timeouts,
      implementation: () => { admissionCounts.implementationAcquisitions++; throw new Error('invalid corpus acquired implementation'); }});
    admissionCounts.gatePreparations++;
    return evaluateSuite(admittedSuite, {...gateOptions('correct'), mirror: acquireMirror});
  }, error => error.code === 'projected_corpus_invalid' && /hash|length/.test(error.message));
}
assert.deepEqual(admissionCounts, {gatePreparations: 0, mirrorAcquisitions: 0, implementationAcquisitions: 0});
checked('tampered corpus rejects before any Gate preparation, model transport or implementation acquisition');
async function evaluateGate(selectedSuite, variant, name, overrides = {}) {
  const receiptPath = join(receiptDirectory, `${name}.json`);
  const result = await evaluateSuite(selectedSuite, {...gateOptions(variant), ...overrides, receipt: {path: receiptPath}});
  assert.equal(result.persistence.status, 'written', printable(result));
  const persisted = JSON.parse(await readFile(receiptPath, 'utf8'));
  assert.equal(persisted.schema, 'mirrorgate.suite-receipt/v1');
  assert.equal((await stat(receiptPath)).mode & 0o777, 0o600);
  assert.equal(persisted.evaluation.runId, result.receipt.runId);
  assert.equal(persisted.evaluation.status, result.outcome);
  assert.deepEqual(result.receipt.cleanup.remainingResources, []);
  assert.deepEqual(persisted.evaluation.cleanup.remainingResources, []);
  assert.equal(persisted.evaluation.cleanup.status, result.receipt.cleanup.status);
  assert(result.suiteResult, printable(result));
  return {result, persisted, receiptPath};
}
const restricted = {};
for (const variant of ['correct', 'faulty', 'dispose-failure']) {
  const {result, persisted, receiptPath} = await evaluateGate(suite, variant, variant);
  assert(result.receipt.implementation?.artifactHash, 'real Gate must prepare an identified worker artifact');
  assert.equal(result.receipt.implementation.runtime, 'node-v1');
  let mismatch;
  if (variant === 'correct') {
    assert.equal(result.outcome, 'passed', printable(result));
    assert.equal(result.suiteResult.outcome, 'passed'); assertCoverage(result.suiteResult, 'Gate correct');
    assert.equal(result.receipt.cleanup.status, 'confirmed');
    assert.equal(persisted.evaluation.cleanup.status, 'confirmed');
    checked('real Gate worker collection bridge passes same reviewed corpus and coverage');
  } else if (variant === 'faulty') {
    assert.equal(result.outcome, 'mismatch', printable(result));
    mismatch = assertMismatch(result.suiteResult, 'Gate faulty observer');
    assert.equal(result.receipt.cleanup.status, 'confirmed');
    checked('real Gate worker faulty observer produces model mismatch with confirmed physical cleanup');
  } else {
    assert.equal(result.outcome, 'failed', printable(result));
    assertCoverage(result.suiteResult, 'Gate dispose failure');
    assert.notEqual(result.receipt.cleanup.status, 'confirmed');
    checked('Gate cleanup failure prevents overall acceptance and is retained in the receipt');
  }
  restricted[variant] = {...resultSummary(result.suiteResult), evaluationOutcome: result.outcome,
    cleanupReceipt: persisted.evaluation.cleanup, receiptPath, ...(mismatch ? {mismatch} : {})};
}
let deniedGateMirrors = 0;
const {result: rejectedGate, persisted: rejectedReceipt, receiptPath: deniedReceiptPath} =
  await evaluateGate(denied, 'correct', 'admission-failure', {mirror: () => {
    deniedGateMirrors++; throw new Error('admission failure must not acquire a mirror');
  }});
assert.equal(rejectedGate.outcome, 'failed');
assert.equal(rejectedGate.suiteResult.failure?.kind, 'configuration');
assert.equal(rejectedGate.suiteResult.conformance, 'not_evaluated');
assert.equal(rejectedGate.suiteResult.cleanup.bindingStatus, 'not_started');
assert.equal(deniedGateMirrors, 0);
assert.equal(rejectedGate.receipt.cleanup.status, 'confirmed');
restricted.admissionFailure = {...resultSummary(rejectedGate.suiteResult), mirrorAcquisitions: deniedGateMirrors,
  cleanupReceipt: rejectedReceipt.evaluation.cleanup, receiptPath: deniedReceiptPath};
checked('Gate admission failure starts no model transport or implementation binding and joins control cleanup');

let oracleInvoked = false;
try { await access(oracleMarker); oracleInvoked = true; }
catch (error) { if (error.code !== 'ENOENT') throw error; }
assert.equal(oracleInvoked, false, 'runtime supplied-trace validation must never invoke a model checker');
checked('all replay used supplied traces with the forbidden model-check sentinel untouched');
console.log(printable({schema: 'mirrors.projected-corpus-runtime/v1', passed: true,
  identity: loaded.identity, suiteId: suite.id, expectedUpdates, expectedPairs, oracleInvocations: 0,
  receiptDirectory, checks, loaderAdmissionFailure: admissionCounts, local, gate: restricted}));
