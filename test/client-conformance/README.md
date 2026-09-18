# Client regression vectors

`async-replies.json` is an additive client-hardening corpus, separate from the
frozen Haskell golden transcripts in `../fixtures/`. Set
`MIRRORS_CLIENT_CONFORMANCE` to its absolute path when running client tests.

The `mirrors.client-async-replies/v1` schema lists named request/reply exchanges
and whether a client should accept the reply. Requests identify the operation
under test; submission cases omit model configuration because the fixture is
about reply classification, not complete request encoding. Rejection means a
protocol failure and poisoned connection; accepted terminal error outcomes
remain backend errors, never validation success or a direct-Apalache fallback.

Each client vendors an identical copy under its test fixtures for standalone
builds. `tools/interop/clients.sh` checks byte equality against this source before
running coordinated acceptance. Update all copies together.
