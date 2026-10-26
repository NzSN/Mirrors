# Windows service upgrade evidence — 2026-10-26

This directory retains the raw record of the scoped `ModelMirrors` Windows
service upgrade. It is separate from the frozen M5 candidate and from the
October 26 compiler/temporary-path repair evidence.

## Observed result

- The service on `DESKTOP-6DKB5JD` was upgraded from `Mirrors 0.0.2` to
  Mirrors `v0.1.0`, source `b243b37774a34fa1bb5b1174b519d2fed98c162b`.
- `deployment.json` and `final-verification.json` observed the replacement
  service running in automatic-start mode on port 8999, with no remaining test
  or backend processes at that observation.
- Baseline, staged-candidate and production synchronous/asynchronous positive
  checks returned `valid`; their negative controls returned `invalid` with the
  expected nonzero exit. TLS 1.3 and the server-leaf fingerprint are recorded
  in the corresponding JSON files.
- Service configuration and runtime dependencies were preserved. The previous
  executable and its hash remain identified for rollback.

These are retained October 26 observations, not a current service-health probe.

## Validation and limits

`runtime-gates.json` records passes for `fixtures_replay`,
`async_resource_spec`, `transport_spec`, `diff_cross`, `stdio_smoke` and
`jobstore_spec`.

`model_interface_spec` exited 1 with eight Windows assertions failing. Its
output is retained unchanged in `gate-model_interface_spec.log`; it is not
counted as passing. The focused repair and its separate validation are in
`../windows-compiler-temp-path-fix-evidence-20261026/README.md`.

The runtime version probe did not support the attempted metadata flag. Full
`lake test`, the full cross-client matrix and reboot testing were not performed.
This record therefore grants no full-framework, service-manager lifecycle,
current-release or v0.1.1 qualification.
