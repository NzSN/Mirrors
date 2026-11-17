# Source review fixes — 2026-11-17

All three findings reviewed at `cc35fd44d1879af80bc9b415f7327a30c71dbdbd`
are corrected in the working tree. [The receipt](result.json) binds the changed
implementation/test bytes, relevant rebuilt executables and retained logs.
This is local source acceptance, not a frozen candidate or release qualification.

1. **Numeric exponent panic:** strict JSON admission now limits the sum of
   absolute explicit decimal exponents to 65,535 before invoking Lean's parser.
   The value decoder handles zero directly and rejects nonintegral scales using
   the mantissa's bit length before computing a power. The existing
   `decValueF_num_integral` theorem keeps its original statement and premises;
   its proof and the codec round-trip proofs compile. Regressions cover both
   exponent signs, aggregate/boundary budgets, direct `JsonNumber` construction,
   valid integer semantics, and shared-daemon survival.
2. **Explorer JSON bypass:** automatic and interactive messages now use strict
   decoding and the bounded `invalid client message` diagnostic. Duplicate and
   escaped duplicate keys, malformed syntax, invalid Unicode, excessive depth
   and oversized exponents cannot produce acceptance or an `assumeState` call.
3. **Explorer socket leak:** startup polling and both flows use scoped RPC
   clients with guaranteed connection cleanup. HTTP close is idempotent, and
   closed connections cannot access a subsequently reused descriptor. Tests
   cover normal/exception exits and repeated close. Twelve complete production
   explorer sessions against a scripted backend now hold at 12 descriptors,
   compared with 14 → 38 before the fix. The sequence includes automatic and
   interactive success, malformed input, and client EOF.

The new descriptor gate is registered in `lakefile.lean` and the maintained
local non-model runner. It explicitly skips descriptor counting outside Linux
with `/proc`; the Lean input/cleanup tests remain part of `explorer_spec`.
The backend used by the lifecycle gate is a Python fixture, not Apalache.

## Validation and retained failures

- [Before-fix numeric results](numeric-before.json) and
  [daemon termination](daemon-before.json) reproduce the panic.
- [Before-fix explorer regressions](explorer-before.log) contain six failed
  assertions; [before-fix lifecycle](lifecycle-before.log) records the leak.
- [Explorer](explorer-after.log), [codec/model-interface](codec-after.log),
  [lifecycle](lifecycle-after.log) and [framing](framing-after.log) focused checks
  pass after the fixes. The focused build passed 553 jobs.
- [The full local gate](local-gate.log) exits 0 after a successful 744-job build
  and ends with `ALL LOCAL NON-MODEL GATES GREEN`.
- [The first focused framing attempt](framing-first-attempt.log) failed at
  `tls-complete-json-eof` with `SSLV3_ALERT_BAD_CERTIFICATE`. The repeat and the
  full gate passed without a TLS implementation change. This failure remains
  recorded; no root-cause or TLS-remediation claim is made.

Run the local gate from the repository root:

```sh
bash tools/run-local-no-model-check.sh
```

Live Apalache/TLC, native Windows execution and optional prepared MirrorCPP
checks were not exercised. This work does not establish new package/installed,
M5/Q, release or deployment acceptance. Those gates require the corrected
candidate's own identity and evidence; historical rc.12 credit is unchanged.
