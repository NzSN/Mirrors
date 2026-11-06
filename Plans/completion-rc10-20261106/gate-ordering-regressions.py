"""Add deterministic response/event coalescing regressions before the fix."""
from common import *
gate=OUT/'MirrorGate-ordering-fix';path=gate/'tests/node/control-v2.test.mjs'
with path.open('a') as stream:stream.write('''

for (const method of ['status', 'agentStatus', 'cancel']) {
  test(`hosted ${method} observes coalesced response before finished event`, async t => {
    const {client} = await clientFor(t, (request, {readable}) => {
      if (!['agent.status', 'agent.cancel'].includes(request.op)) return false;
      const snapshot = method === 'cancel'
        ? {...submitted(), phase: 'cleaning', cleanup: {status: 'pending', remainingResources: []}}
        : running();
      readable.write(Buffer.concat([
        controlFrame({v: 2, kind: 'response', id: request.id, ok: true, result: {run: snapshot}}),
        controlFrame({v: 2, kind: 'event', seq: 1, sessionId, event: 'agent.finished', data: {run: submitted()}}),
      ]));
      return true;
    });
    const session = await client.openSession(openArgs);
    const run = await session.startAgent(startArgs);
    const observed = method === 'agentStatus' ? await session.agentStatus() : await run[method]();
    assert.equal(observed.phase, 'finished');
    assert.equal(run.latest.phase, 'finished');
    assert.deepEqual(observed.submission, submitted().submission);
  });
}
''')
