# rc.8 qualification continuation — 2026-11-05

Current result: **M5, both installed audits, native C++/live-model work and
three installed DPM profiles pass at the exact private rc.8 source. Full
Windows `lake test` remains unaccepted.** `result.json` is the scope summary.

| Gate | Result |
| --- | --- |
| Both strict installed audits | Qualified, finalized, offline verified |
| M5 profile | All 18 required commands / 16 tiers pass |
| Linked Q1 / independent installed Q2 | Pass; 19 linked nodes / 20 bundles |
| Actual negative controls | All six rejected; inputs remain read-only |
| Live client matrix | All 22 verdict/pin/protocol rows pass |
| Controlled C++ model comparison | 13 fresh executions plus mutation/refusal/reduction controls pass |
| Installed C++ / Node-worker / Rust-thread DPM | All three pass with source hidden and networking isolated |
| Native Windows executables | All 34 pass with descendant cleanup checked |
| Windows native integer maps | stdio, TCP and authenticated TLS pass |
| Windows source integrity | All 10,034 Mirrors and 183 C++ SDK Git blobs match |
| Full native Windows `lake test` | **Open:** POSIX process/activation/evidence/storage helpers need Windows support; one tooling test also assumes POSIX path separators |

Exact source is private commit
`f328e328d6f961b49ccffefc0a6d0250bec2fb3c`, product `0.2.0-rc.8`.
Selected C0 is
`23625d60c29b8a6265171bbd818eadeba8505d03807bba8e504e9bef2bc14656`.
The qualified catalog, sealed evidence store and installed runtimes are retained
under `.golden-build/qualification-rc7-20261105/refreshed/`.
`rc8-q1-result.json`, `rc8-q2-result.json` and
`rc8-q2-after-backend-stop.json` bind complete-profile acceptance. Q2 imports
only installed verifier/schema/profile bytes and its exact bundled wheel
closure, with source and producer scratch hidden, network unshared and inputs
read-only. The six controls exercise missing payload, changed bytes, wrong D,
wrong R0/R1, wrong R1/R5 and a self-consistently sealed incomplete profile.

`rc8-installed-dpm-result.json` keeps `freshModelCheck:false` for the three
installed replay/reduction profiles. The separate
`rc8-controlled-model-result.json` records an actual finite model comparison;
it does not claim generic or exhaustive native scheduling. Native rebuild
checks and adversarial output-link preservation regressions pass.

The isolated Windows oracle and owned SSH tunnel have been stopped. No task
Java/binary/listener remains; production PID 9920, executable hash and
Running/Automatic service state are unchanged. Offline Q2 still passes after
backend shutdown. Operator keys remain host-local and outside Git payloads.

The full Windows gate was kept strict. An asynchronous scope question remains
unanswered: implement the full Windows port for the Linux-specific helpers, or
qualify the Windows checker/live backend while retaining those tools' Linux
scope. No narrowed full-suite claim is assumed. The correct Python 3.12
prerequisite is staged task-locally and Authenticode-valid; its remaining TLA
tooling failure is a path-regex assertion after a correctly rejected corrupted
launcher. `pending-windows-tool-test-fix.patch` is reviewable and unapplied.

This result does not grant full Windows, W3, native M4, release or production
admission. Source/main publication, a new hosted release and deployment remain
separate. The shared branch/index and previous tags retain their starting
state; all 240 older unrelated files remain preserved.

The rc.7 baseline and retained intermediate attempts follow below. Their
original identities and limitations remain historical.

## Starting rc.7 admission

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
