#!/usr/bin/env bash
# Local qualification gates for memory-constrained coordinators.
#
# This runner intentionally does not call `lake test`: that aggregate probes a
# local Apalache fallback and runs tools/check-async-protocol.py (TLC). Keep the
# exclusions below explicit. Model checking is a separate remote qualification
# obligation owned by tools/evidence/run_remote_model_check.py.
set -euo pipefail

unset APALACHE_MC APALACHE_JAR TLA2TOOLS_JAR MIRRORS_ASYNC_RESOURCE_E2E

run() {
  printf '== %s ==\n' "$1"
  shift
  "$@"
}

run "build" lake build
run "async emitter" python3 tools/check-async-emitter.py
run "suite bundle" python3 tools/check-suite-bundle.py
run "validate source closure" python3 tools/check-validate-closure.py
run "validate async protocol codec" python3 tools/check-validate-async.py

# Deliberately excluded model checks:
#   python3 tools/check-async-protocol.py --quick  (TLC)
#   ApalacheCliSpec.integration                     (live Apalache)
#   ExplorerSpec integration                       (live Apalache)
#   CounterSpec                                    (live Apalache)
#   AsyncSpec                                      (live Apalache)
#   tools/check-async-server-resources.py           (live Apalache)
# The four Lean executables below are invoked with APALACHE_MC absent so their
# pure/unit portions run and their documented live portions self-skip.

run "fixture replay" .lake/build/bin/fixtures_replay
run "cross-codec diff" .lake/build/bin/diff_cross
run "model-interface spec" .lake/build/bin/model_interface_spec
run "model-interface distribution spec" .lake/build/bin/model_interface_distribution_spec
run "framework catalog spec" .lake/build/bin/framework_catalog_spec
run "distribution contract" python3 -m unittest discover -s tools/distribution -p 'test_*.py'
run "distribution manifest" tools/distribution/manifest-check validate distribution/reference-node
run "durable evidence" python3 -m unittest discover -s tools/evidence/tests -p 'test_*.py'
run "model-interface scaffold CLI" .lake/build/bin/model_interface_scaffold_cli_spec
run "model-interface evidence" .lake/build/bin/model_interface_evidence_spec
run "TLA lexer" .lake/build/bin/tla_lexer_spec
run "TLA parser" .lake/build/bin/tla_parser_spec
run "TLA module resolver" .lake/build/bin/tla_module_resolver_spec
run "TLA elaboration" .lake/build/bin/tla_elaboration_spec
run "TLA frontend" .lake/build/bin/tla_frontend_spec
run "TLA frontend CLI" .lake/build/bin/tla_frontend_cli_spec
run "TLA differential offline" python3 -m unittest discover -s tools/tla-differential/tests
run "model-interface scaffold" .lake/build/bin/model_interface_scaffold_spec
run "trace projection CLI" .lake/build/bin/model_interface_trace_projection_cli_spec
run "trace projection" .lake/build/bin/model_interface_trace_projection_spec

mi=(--spec specs/Counter.tla
  --contract test/fixtures/model-interface/counter/Counter.mirror-interface.json
  --evidence test/fixtures/model-interface/counter/counter.itf.json
  --param-var parameters
  --lock test/fixtures/model-interface/counter/Counter.mirror-interface.lock.json)
run "model-interface TypeScript golden" .lake/build/bin/model_interface_gen check \
  "${mi[@]}" --target mirrorecma-v1 \
  --out test/fixtures/model-interface/counter/generated
run "model-interface async TypeScript golden" .lake/build/bin/model_interface_gen check \
  "${mi[@]}" --target mirrorecma-async-v1 \
  --out test/fixtures/model-interface/counter/generated-async
run "model-interface C++ golden" .lake/build/bin/model_interface_gen check \
  "${mi[@]}" --target mirrorcpp-v1 \
  --out test/fixtures/model-interface/counter/generated-cpp
run "model-interface Rust golden" .lake/build/bin/model_interface_gen check \
  "${mi[@]}" --target mirrorrust-v1 \
  --out test/fixtures/model-interface/counter/generated-rust
run "model-interface Rust checks" bash tools/model-interface-rust/check.sh

coverage="$(.lake/build/bin/model_interface_gen preflight \
  --lock test/fixtures/model-interface/counter/Counter.mirror-interface.lock.json \
  --trace test/fixtures/model-interface/counter/counter.itf.json \
  --require-all-actions)"
printf '%s\n' "$coverage"
if [[ "$coverage"$'\n' != "$(<test/fixtures/model-interface/counter/Counter.mirror-interface.coverage.json)"$'\n' ]]; then
  echo "model_interface_gen preflight coverage differed from exact golden bytes" >&2
  exit 1
fi

run "stdio replay smoke" .lake/build/bin/stdio_smoke
run "async resource proofs" .lake/build/bin/async_resource_spec
run "job store" .lake/build/bin/jobstore_spec
run "Apalache CLI pure/unit" env -u APALACHE_MC .lake/build/bin/apalache_cli_spec
run "explorer pure/unit" env -u APALACHE_MC .lake/build/bin/explorer_spec
run "transport" .lake/build/bin/transport_spec
run "trace transport failure fixture" env \
  APALACHE_MC="$PWD/test/fixtures/trace-generation/apalache-failure.sh" \
  .lake/build/bin/trace_generation_transport_repro_spec
run "registry" .lake/build/bin/registry_spec
run "Counter live tier self-skip" env -u APALACHE_MC .lake/build/bin/counter_spec
run "async live tier self-skip" env -u APALACHE_MC .lake/build/bin/async_spec

echo "ALL LOCAL NON-MODEL GATES GREEN"
