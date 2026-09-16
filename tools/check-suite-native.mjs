#!/usr/bin/env node
// Execute freshly compiled Counter bundle output; the installed consumer gate
// separately checks TypeScript compatibility against the public runtime API.
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';
import {validateNativeConversions} from './suite-native-vectors.mjs';

if (!process.argv[2]) throw new Error('usage: node tools/check-suite-native.mjs COMPILED_COUNTER_SUITE');
const {CounterModel, convertNativeValue} = await import(pathToFileURL(resolve(process.argv[2])).href);
validateNativeConversions(
  (shape, value) => convertNativeValue(shape, value, true).value,
  (shape, value) => convertNativeValue(shape, value, false).value,
);
assert(Object.isFrozen(CounterModel));
assert(Object.isFrozen(CounterModel.descriptor.actions));
let count = 0n;
let calls = 0;
const adapter = {
  actions: {
    Initialize() { count = 0n; calls++; },
    Tick({Stride}) { count += Stride; calls++; },
  },
  observe() { return {Count: count}; },
};
const config = {paramVars: 'parameters'};
const binding = CounterModel.bindLocal(adapter, config);
const controller = new AbortController();
const context = () => ({signal: controller.signal, deadline: performance.now() + 1000});
const initial = await binding.computer({action: 'init', payload: {}, previous: null}, context());
assert.equal(initial.count.val, 0n);
const tick = stride => ({action: 'tick', payload: {parameters: {tag: 'record', val: {stride}}}, previous: initial});
const next = await binding.computer(tick({tag: 'int', val: 1n << 160n}), context());
assert.equal(next.count.val, 1n << 160n);
await assert.rejects(binding.computer(tick({tag: 'str', val: 'wrong'}), context()));
assert.equal(calls, 2, 'invalid input reached the application handler');
await assert.rejects(binding.computer(tick({tag: 'int', val: 1n}), context()));
assert.equal(calls, 2, 'poisoned binding invoked the application');
const malformedObservation = CounterModel.bindLocal({...adapter, observe: () => ({Count: 3})}, config);
await assert.rejects(malformedObservation.computer({action: 'init', payload: {}, previous: null}, context()));
assert.throws(() => CounterModel.bindLocal({...adapter, actions: {Initialize() {}}}, config));
for (const returned of [null, 7, {}]) {
  let observations = 0;
  const invalidReturn = CounterModel.bindLocal({actions: {Initialize() {return returned;}, Tick() {}},
    observe() {observations++; return {Count: 0n};}}, config);
  await assert.rejects(invalidReturn.computer({action: 'init', payload: {}, previous: null}, context()),
    error => error.code === 'adapter_failure');
  assert.equal(observations, 0, 'invalid native operation return reached observation');
}
console.log('Suite native bridge: recursive shared vectors, complete validation, bigint replay, inert metadata and binding poison passed.');
