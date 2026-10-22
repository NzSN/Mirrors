import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';

const sdk = await import(pathToFileURL(process.env.COMPAT_ECMA_INDEX).href);
const mode = process.env.COMPAT_TRANSPORT;
const scenario = process.env.COMPAT_CASE;
let calls = 0;
try {
  const target = mode === 'stdio' ? process.env.COMPAT_MIRROR
    : mode === 'tcp' ? sdk.connectMirror('127.0.0.1', Number(process.env.COMPAT_PORT))
    : await sdk.connectTlsMirror('localhost', Number(process.env.COMPAT_PORT), {
        caPath: process.env.COMPAT_CA, certPath: process.env.COMPAT_CERT,
        keyPath: process.env.COMPAT_KEY,
        pin: scenario === 'wrong-pin' ? '0'.repeat(64) : process.env.COMPAT_PIN,
      });
  await sdk.runClientWithTraces(target, {
    specPath: 'Counter.tla', invariant: 'TraceComplete', lengthBound: 6,
    constInit: 'CInit', paramVars: 'parameters',
  }, [process.env.COMPAT_TRACE], () => {
    const index = calls++;
    return {count: {tag: 'int', val: scenario === 'mismatch' && index === 1 ? 99n : [0n, 2n, 5n][index]}};
  });
  assert.equal(scenario, 'match');
  assert.equal(calls, 3);
  console.log(JSON.stringify({outcome: 'match', calls}));
} catch (error) {
  if (scenario === 'mismatch' && error instanceof sdk.ReplayMismatchError && calls === 2) {
    console.log(JSON.stringify({outcome: 'step_mismatch', calls}));
  } else if (scenario === 'wrong-pin' && calls === 0 && /fingerprint mismatch/.test(String(error))) {
    console.log(JSON.stringify({outcome: 'pin_mismatch', calls}));
  } else {
    throw error;
  }
}
