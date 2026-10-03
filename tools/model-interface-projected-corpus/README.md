# Projected corpus integration gate

Run from the Mirrors repository root:

```sh
python3 tools/model-interface-projected-corpus/test_check.py
PYTHONOPTIMIZE=1 python3 tools/model-interface-projected-corpus/check.py \
  --out /tmp/projected-cells-acceptance
```

The output directory must not exist. Optional `--compiler`, `--mirror`,
`--ecma-repo`, and `--gate-repo` arguments select the prepared tools and sibling
checkouts. Required dependencies are Node, the SDKs' installed TypeScript
dependencies, npm/tar, Python, Bubblewrap, and the normal Gate Node sandbox
prerequisites. This is an explicit cross-repository gate.

`adapter.mjs` is the public mutable implementation. `run-suite.mjs` contains
the shared local/Gate behavioral assertions. `check.py` generates and checks
the reviewed artifacts through the CLI, prepares local npm packages and the
operator runtime, relocates them, and invokes the runtime with checkout mounts
hidden and the network isolated. The source-hiding check uses explicit errors
and remains active under Python optimization.

The final `receipt.json` identifies the fixture, harness, compiler, packages,
executables, corpus, and retained command logs. Gate receipts include their
independent cleanup outcomes. Raw/projected trace hashes, workflow provenance,
and the ordered ECMA corpus digest remain distinct. The test includes no
private model, external service request, or local Apalache/TLC invocation.
