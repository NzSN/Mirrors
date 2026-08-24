# Final Review — Lean 4 ModelMirrors Port

> Reviewer: team captain (independent of the implementing members)
> Date: project completion, commit 5734c12
> Method: claim-by-claim verification against the design doc
> (Docs/lean4-refactor-design.md), source inspection, #print axioms
> audits, and live runtime checks.

## Verdict: ACCEPT — all design goals met; two open items are documented, not hidden

## 1. Verification claims — independently audited

| Claim | Audit | Result |
| ----- | ----- | ------ |
| Zero sorry/admit | regex scan of all .lean in Core/Codec/Shell/Ffi/tools | PASS, no matches |
| Proofs are real, not axiom-injected | #print axioms on 10 representative theorems across all proof modules | PASS: none depend on sorryAx; max is the standard triple (propext, Classical.choice, Quot.sound); step_refines_tla / no_unsolicited_output need only propext; traceSteps_length is fully constructive (no axioms) |
| lake build green | 473 jobs | PASS |
| 8 test gates | fixtures_replay, diff_cross, stdio_smoke, jobstore_spec, apalache_cli (real 0.57), explorer_spec, transport_spec, registry_spec | ALL GREEN |
| Wire compatibility | unmodified MirrorECMA over stdio/TCP/mTLS + Haskell validate client; 70 fixture cases byte-identical; diff engine 500/500 ORDERED + 5000-case sweeps | PASS |
| TLA+ fidelity | step_refines_tla vs specs/MirrorProtocol.tla@3496251, incl. PhaseOk + ClientNeverStuck obligations; async-job steps marked as explicit extensions | PASS |

## 2. Goal-by-goal vs the design doc

- **Goal 1 (verified pure core):** met. sec 6.1-6.6 all machine-checked, incl. the message-level round-trips (t19) and the proven Core-Codec tag bridge (t22) that closes the two-vocabulary seam.
- **Goal 2 (wire compatibility):** met with evidence; strengthened during the port — hint-order byte parity (t20), bare-number decode parity (t23), absent-vs-null .:? semantics + per-constructor omission asymmetry pinned by fixtures.
- **Goal 3 (feature parity):** met. stdio/--serve/--server --tls/registry/validate all present and live-tested; --jobs accepted (reserved). --bind honors arbitrary addresses with loud failure (t27).
- **Goal 4 (TLA+ link):** met — the headline achievement. The shipped session machine is proven to refine the TLA+ spec; the model+hope gap is closed.

## 3. TCB inventory (honest accounting, doc sec 5.4/9)

- **OpenSSL + Ffi/tls_shim.c** — largest TCB addition, as predicted. Mitigated by: minimal shim surface, adversarial review (Docs/tls-ffi-review.md: 1 blocker + 3 majors found and fixed, re-review PASS), 8+8 negative tests.
- **Ffi/socket_shim.c** (~150 lines) — connect/bind/accept/read/write, hostname resolution, signals.
- **Trusted Lean shell (Shell/)** — drivers, HTTP client, job store, CLI; kept thin; oracle calls injected so the proven core never mentions IO.
- **External:** apalache/JVM, OS. Two runtime-only behaviors remain unproven by design (sec 9.5): locale/cwd isolation (covered by regression tests instead) and the sequential accept loop (liveness, per non-goals).

## 4. Bugs the process caught (evidence the gates work)

11 real bugs found after the proof stage: TLS finalizer segfault + 3 majors (review), bare-number decode, absent-vs-null keys, destPath lifecycle, swapped explorer args, hint order, TLS re-accept wedge (ABI + blocking shutdown), --bind silently wildcard, startup expired-cert policy. Every one is now covered by a fixture, gate, or negative test — none can silently regress.

## 5. Open items (documented in Docs/cutover.md — none blocking)

1. **MirrorRust leg** — client unavailable in this environment; Haskell validate client substituted. Cutover must not claim MirrorRust coverage until run.
2. **Pre-register job-message error tag** — Lean answers register_error, Haskell protocol_error; error-path only, unreachable by conforming clients. Candidate for harmonization.
3. **Wildcard scope** — stricter than Haskell's x509-validation (fail-closed); accepted divergence.

## 6. Risks carried forward

- **Proof maintenance** (sec 9.4): protocol growth now requires updating TlaStep + refinement — intended by design.
- **/proc/self/cmdline argv** (Linux-only; Lean 4.33 lacks IO.getArgs) — fine for the POSIX target, blocks non-Linux ports.
- **Lake relink gotcha:** exes do not relink on C-only shim edits (rm the exe + .o); documented in INTEROP.md.
- **GC finalizers at the FFI boundary** are the sole ownership backstop (sec 9.7 as designed); the t26 NULL-guard bug shows this seam needs review on any future FFI addition.

## Summary

The port delivers the doc's central promise: the shipping binary IS the verified artifact. ~14.5k lines of Lean + C, 27 completed tasks, 6 milestone commits, zero proof holes, byte-level parity with the Haskell implementation it replaces, and a deprecation plan ready in Docs/cutover.md. Recommended: run the MirrorRust leg and harmonize the job-message error tag before the Haskell build is formally deprecated.
