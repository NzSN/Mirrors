# `tla_frontend` CLI fixtures

`inspect-generic-transfer-variables.json` pins the exact
`inspect --variables --format json` output for
`../accepted/generic-transfer/GenericTransfer.tla`, the public corpus fixture
with twelve inherited plus seven local variables.

`tools/TlaFrontendCliSpec.lean` compares the built executable's bytes to this
file, so a schema or fact change fails the gate until the fixture is reviewed
and regenerated deliberately:

```bash
lake build tla_frontend
.lake/build/bin/tla_frontend inspect \
  --spec test/fixtures/tla-frontend/accepted/generic-transfer/GenericTransfer.tla \
  --variables --format json \
  > test/fixtures/tla-frontend/cli/inspect-generic-transfer-variables.json
```

The fixture is not a model-interface artifact, so `model_interface_gen` does
not own it; it belongs to the TF8 inspection-CLI package.
