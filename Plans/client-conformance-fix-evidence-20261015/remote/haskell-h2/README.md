# H2 SAN-only follow-up acceptance — 2026-10-15

The separately reviewed H2 candidate passed remote WSL validation. It enforces
existing C25 SAN-only client identity while retaining default CA/time/chain
validation, original signed certificates, cache behavior after the mandatory
SAN guard, and the documented case-sensitive pin comparison.

The pre-H2 qualified H1 source and binaries remain unchanged. H1's CN-only
acceptance was an observation that triggered this follow-up; it was not SAN-only
qualification. `preserved-h1.json` rechecks all 120 H1 source files and its
retained binaries. H2 has separate sources and build directories.

## Normal, original failure and integration controls

The baseline is the actual pre-H2 TLS module from qualified H1 with only the new
Cabal and test overlays. Its TLS source SHA256 is
`23d6b57db6d8f0b212e7aeaf3fffcf9028d5cba565d92e5ae5085fb5db6b703b`.
The H2 candidate TLS source SHA256 is
`afc5618b129a0cebc6ee4d5237f40f6fb55e6b79e8832d788fdeeb3ff3ecaba0`.

- Baseline CN-only identity was accepted: **one client protocol write and 35
  decrypted application bytes**. The negative test failed explicitly in 0.77s.
- Baseline correct IP-only SAN with a different CN failed a real TLS handshake
  with `NameMismatch`, in 0.65s. Neither red result was a timeout.
- The candidate compiled and passed **18 NonModel tests twice**, in 6.05s and
  6.21s. Both runs contain **17 TLS rejection receipts**, each with zero client
  protocol writes and zero decrypted application bytes.
- The corrected IP-only SAN/different-CN case completed its protocol round trip.
  DNS SAN precedence, typed SAN mismatches, IPv4/IPv6 address equality,
  equivalent IPv6 spellings, wildcard depth, CN-only refusal, cache controls,
  wrong CA, pin additivity and all prior framing/session/client/key-mode tests
  passed.
- A no-change build preserved test-binary SHA256
  `018e3f698eb5b5aed5762752fed30d285ab3a700f5afc3a8e335339ec2c0c384`.
- Cleanup found no owned Haskell compiler/test processes or session temporary
  directories. No production edits were made by the remote validator/reviewer.

[Independent source review](source-review-h2.md) found no remaining confirmed
findings across the five frozen H2 files and the installed dependency APIs.

## Identities and execution

The source manifest binds all **120 candidate files**. GHC **9.14.1**, Cabal
**3.16.1.0**, signed Hackage index-state **2026-09-01T00:00:00Z**, TLS **2.4.3**,
crypton-x509-validation **1.9.1** and iproute **1.7.15** match the privately owned
H1 toolchain/dependency cache. Native compilation used at most two workers.

Candidate sources are at
`/home/jlc/Tools/mirrors-client-fixes-20261015/source/ModelMirros-h2`;
baseline sources use the separate `ModelMirros-h2-baseline` directory. New
builds/logs live under
`D:/Desktop/Workspaces/Mirrors-client-fixes-20261015/haskell-h2`.
`workflow/phases.py`, `phases.json` and raw logs retain exact commands/results;
`dist-dependency-plan.json` and `baseline-dist-dependency-plan.json` retain both
resolved package plans.

The retrieved remote evidence archive SHA256 is
`095fbeb1fdf9ec40cecfd128228974a3ad8edd9b299619abb51331c076b9ad1d`.
`evidence-manifest.json` binds **34 files / 378,309 bytes**, all verified locally;
its SHA256 is
`c19d799201cebffc08917d56c64b4d91600ef4658de6216c5b9f037babe246b3`.
This README and the independent source review are coordinator additions outside
that remote manifest. The enclosing final manifest should bind them too.

No local build/test, model checker, live service call, certificate/key mutation,
commit or push was performed. Private keys, toolchain caches and binaries remain
remote. Native Windows/macOS behavior, hosted CI and unselected historical or
model-backed suites remain outside this scoped WSL acceptance.
