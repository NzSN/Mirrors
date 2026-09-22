# Model-validated reduction profiles

The first domain profile is
`mirrors.reduction-candidate/lease-service-input-shrink/v1`. It is a narrow
trusted-evaluator contract for reducing a fixed LeaseService failure; it is not a
general trace solver.

The strict request binds the model SHA-256, semantic interface digest, original
ordered-corpus digest, original reproduction-bundle digest, selected trace zero,
the selected trace byte digest, its exact ordered occurrences `[0, 1]`, and at
most 16 input edits. Version 1 accepts only `2 -> 1` for:

- `Acquire.Client`;
- `Renew.Client` / `Renew.Token`;
- `Release.Client` / `Release.Token`;
- `Write.Client` / `Write.Token`.

Unknown fields, duplicate edits, initialization edits, other actions/inputs,
other values, malformed identities, another trace index, or a changed occurrence
list fail closed. The pure
contract lives in [`Core/ModelInterface/Reduction.lean`](../Core/ModelInterface/Reduction.lean);
[`Codec/ModelInterfaceReductionJson.lean`](../Codec/ModelInterfaceReductionJson.lean)
owns bounded duplicate-aware JSON decoding. `model_interface_spec` covers accepted
and rejected requests.

Contract validation alone does not establish model validity. The evaluator owns
the private LeaseService source, interface lock, selected Apalache/Java tools and
materializer. It must generate the candidate trace, run ordinary model-interface
preflight, verify each requested action/input in the materialized trace, and only
then construct a fresh SUT. Application output is never the model oracle. The
result records model/interface/original/candidate corpus identities and the exact
validator, Apalache JAR/launcher, Java executable/archive, and qualification
reference. A matching version string never implies distribution qualification.

On 2026-09-22 the development oracle used cached Apalache 0.61.0 to change the
deterministic LeaseService state-2 `Acquire.Client` input from 2 to 1. Snowcat
typechecking passed and the complete 10-step candidate trace was produced by the
model (intentional `TraceComplete` exit 12). The known
`overlapping-ownership` mismatch remained at `(trace 0, state 2, acquire)` through
the real local suite, with fresh factory/disposal and confirmed cleanup.

The development oracle was also run with cached Microsoft OpenJDK
`25.0.4+7-LTS` from the
archive whose SHA-256 is
`75894d107e474ffb6c947ab050e3893e0a1d3d40d36f107d42936ac6088769c1`;
the pinned tool verifier accepted it with Apalache 0.61.0/SANY. The shipped
materializer now rechecks those exact bytes, the model, interface lock, original
trace, and candidate request before and after the original `Init`/`Next` oracle;
it uses bounded no-follow reads and a total explorer deadline with separate
cleanup settlement. This establishes selected development tool identities only.
Installed-distribution qualification still depends on an explicit finalized
I2/C5/E4 qualification reference. Other
applications return `reduction_profile_unsupported` without mutation. The result
never claims a global minimum.
