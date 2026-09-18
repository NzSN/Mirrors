# Concurrent async server resource E2E

Run from the Mirrors root on Linux with OpenSSL, Python 3, and real Apalache:

```sh
lake build mirror
APALACHE_MC=/path/to/apalache-mc python3 tools/check-async-server-resources.py \
  --concurrency 3 --batches 6 --evidence /tmp/mirrors-async-server-resources.json
```

The test starts an isolated production `--server --tls` listener with temporary
mutual-TLS credentials. Three independent owner connections submit inline TLA+
validation jobs before awaiting results. A fourth connection observes cleanup;
`--jobs` reserves a slot for it. Simultaneous backend children must be observed,
so accepting several job IDs alone cannot pass the concurrency assertion.

Two completion batches warm up the server. Subsequent batches rotate successful
completion, explicit cancellation, and disconnect while jobs are active. Each
batch must recover before the next begins:

- Every submitted job becomes `unknown` after its owner disconnects.
- All direct backend children exit and are reaped.
- All owned `modelmirrors-*` temporary directories disappear.
- Server file descriptors return to no more than the warm baseline.
- Server resident memory stays within `--rss-budget-mib` (default 16 MiB)
  of the warm baseline.

The default run submits 24 jobs, including warm-up. JSON evidence contains every
quiescent RSS/descriptor sample, observed backend concurrency, and the server log
tail. Failures exit nonzero; missing dependencies do not silently skip. Increase
`--batches` for a longer soak. `MIRRORS_ASYNC_RESOURCE_E2E=1 lake test` enables this
otherwise optional expensive gate.

This is a resource-cleanup and bounded-memory-growth regression test. RSS includes
allocator caches and does not identify unreachable heap allocations; a finite run
cannot prove absence of all memory leaks. The backend JVM's heap is not measured;
backend process exit is checked. Direct-child accounting does not establish that
an arbitrary external backend never detaches grandchildren. Pair this evidence
with the [Lean resource safety proofs](async-resource-lean-proofs.md) and
[TLA+ resource model](async-protocol-resource-model.md), whose effectful-runtime
and progress assumptions still apply. This test covers async validation over
local mTLS; the existing `async_spec` additionally exercises trace generation.
