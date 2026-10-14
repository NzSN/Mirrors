import {isMainThread} from 'node:worker_threads';
export async function run({buffer}) { if(isMainThread)throw new Error('actual worker required'); Atomics.add(new Int32Array(buffer),1,1); }
