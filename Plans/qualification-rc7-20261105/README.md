# rc.7 installed/platform qualification — 2026-11-05

Status: executing the user's request to complete the pending qualification work.
Start with the admitted rc.7 source/C0 and clean package set, then complete both
installed audits, native/client inputs, live-model and full Windows gates, and
linked/independent evidence verification as their prerequisites become available.
No skipped or historical tier receives new credit.

Exact source is `f525c6349dc5a5e457757fa040c89312c6703e3a`; selected WSL2 C0 is
`e673c65e1220d3d71f0ba200db77210267e342a7614d51a17168460afb02ff88`.
Main `fbbe45a` holds the published records; it is not substituted for the selected
source. The base Ubuntu 24.04 C0 is a structural control only.

The rc.7 baseline has now produced both passing strict installed audits, native
integer-map/preparation results, 13 fresh finite controlled-model executions
with mutation/refusal/reduction controls, and all 22 live client rows. See
`local-installed-diagnostic.json`, `gate-installed-diagnostic.json`,
`native-controlled-live.json` and `live-client-diagnostic.json`. Registered
framework credit still requires refreshed clean source/C0 and the evidence DAG.

Native Windows testing exposed source and test portability defects, repaired
with Linux regressions and a passing native rebuild-graph gate. The owned
Windows clone builds, expanded CMake link-preservation tests pass, integer maps
pass over stdio/TCP/mTLS, and required TLC safety/liveness/mutant cases pass.
Full `lake test` remains failed at POSIX-specific DPM process/installation
helpers; `named-tlc-full-lake-test.log` retains that result. No required row is
silently skipped. Further native suites are inventoried independently.

Source prepares rc.8 for the repairs and the explicit input rebinding in
`selection-rebinding.json`. This does not change the old rc.7 tag. The selected
Apalache container `765f6105…` is a new selection with the same JAR, not recovery
of `7cfadf6e…`. Fixed C++ source is retained in
`third_party/mirrorcpp/mirrorcpp-windows-v0.1.1.bundle`; it clones offline and
contains no compiled SDK or private key.

Outputs are task-owned, owner-only and fresh under ignored
`.golden-build/qualification-rc7-20261105/`. Preserve older evidence and unrelated
files, retain failures, and never bypass an identity or namespace refusal.
No local Apalache/TLC runs on this coordinator. Live operations use a freshly
observed owned remote fixture through the Mirrors CLI. Production service,
release/tag publication, deployment and reboot remain separate boundaries.
