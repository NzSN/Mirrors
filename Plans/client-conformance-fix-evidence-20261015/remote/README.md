# Remote client remediation validation

All accepted implementation gates passed on the owned `windows-dev` Ubuntu WSL
host. This is remediation acceptance under the October 15 plan; it does not
qualify a complete M5 or native platform profile. No local compilation/tests,
Apalache/TLC, production service operations, original-checkout commits or pushes
were performed.

Final results:

- MirrorLean: final root suite 125 tests, zero failures; async and model-interface
  gates; native server-mode and discovery TLS/key-policy gates; no-change build.
  Original closure/decoder/TLS audit reproductions now pass the corrected behavior.
- Mirrors: transport, trace capture and jobstore focused suites; maintained framing,
  trace-capture and async validation; native rebuild graph checks; full offline
  suite ending `ALL LOCAL NON-MODEL GATES GREEN`. The cross-client native integer
  map gate ran with the newly installed corrected C++ SDK.
- MirrorECMA: three typechecks, seven focused Jest suites, repeat build, complete
  pinned non-live `pnpm run ci`, fresh package consumers and original invalid-pair
  controls. Synchronous generated and wire inputs retain their source identities.
- C++/Gate: fresh Werror SDK/CTests and real workers; fresh TLS Debug/Werror
  key-mode 103 assertions and full TLS 167 assertions; installed and rebuilt
  consumers; final real Gate matrix 37 rows (18 owned/19 attached), all 19 sibling
  sessions survive. Two deliberate cleanup failures and four broker protocol
  injections retain their exact observable SDK classification. Repeated builds
  and binaries remain unchanged. See [cpp-gate/README.md](cpp-gate/README.md).
- Haskell: H1's 16 non-model gates and paired actual old-Core/fixed send boundary
  reproduction; conditional reviewed H2 actual TLS baseline red and 18 final
  non-model gates twice, including SAN-only/CN, pin, CA and IP controls. H1 and H2
  remain distinct source/evidence identities. See [haskell/README.md](haskell/README.md)
  and [haskell-h2/README.md](haskell-h2/README.md).
- Unchanged Rust: four transport controls pass from a fresh target/vendor tree
  against hash-verified locked archives.

The final immutable producer is
`/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015/cpp-gate/immutable/mirror`,
mode `0555`, SHA256
`6e06ecd3d4d2975a42db2a1822b2d28d9e382f6d5b9bf48fa36c6c9ce27fa77d`.
Its complete selected source set and native objects were checked before copying.
Final framing and original CLI controls were rerun against this copy. The original
LF control passes, unterminated EOF is refused, and terminal protocol errors do
not emit a cancellation request. All bounded peers/children close.

Only ephemeral remote validation checkouts have new snapshot commits:
Mirrors `0a65f7ff7804ddafaa520eaeb5af7624e7852ed1` and MirrorECMA
`4cf1ea5a5cc4cef64fb2f4b6dbc142cbb3ca72af`. They bind corrected working-tree
content for the full-SHA CI interface; actual repository HEADs are unchanged.
The final portability-only `tools/check-client-framing.py` delta (SHA256
`fe2b77b8e24bdff58f9b08dc1b594174ce2b0ece765fab76a382e4fbc7df0dca`)
postdates CI's snapshot. It changes detached-socket closure and Windows linger
packing only; compiled inputs are unchanged and its final focused gate passed.

Explicit tool paths and exceptions:

- Lean 4.33.0: `/home/jlc/.elan/toolchains/leanprover--lean4---v4.33.0/bin`,
  `ELAN_TOOLCHAIN=leanprover/lean4:v4.33.0`.
- GCC/G++ 12.3: `/usr/bin/gcc-12`, `/usr/bin/g++-12`. This is an observed
  environment override; the documented GCC13 baseline remains unqualified.
- CMake 3.28.4:
  `/home/jlc/Tools/mirrors-dpm-remediation-toolchain-20261013/cmake-python/cmake/data/bin/cmake`.
- Official Node 24.15.0: new image `tools/node/bin/node`; pnpm11.22.0:
  `tools/pnpm-11.22.0/package/bin/pnpm.cjs`; private npm/npx use bundled11.12.1.
- Actual Python3.12.14:
  `/home/jlc/.local/share/uv/python/cpython-3.12.14-linux-x86_64-gnu/bin/python3.12`;
  private launcher prevents cache writes to historical evidence dependencies.
- GHC9.14.1/Cabal3.16.1.0 under new `tools/haskell`; signed Hackage index state
  `2026-09-01T00:00:00Z`, TLS2.4.3 and x509-validation1.9.1. Official hashes
  verified even when the same artifacts came through a regional mirror.
- Real privately built Bubblewrap0.9.0 is overlaid only in a private mount
  namespace, then runs as `jlc` with zero effective/ambient capabilities.
  System0.6.1 bytes remain unchanged. Release/tag metadata and observed hashes
  are retained; no unverified release signature is claimed.
- Rust/cargo1.96.0 use the existing stable toolchain and fresh owned targets.
  No project compiler pin exists for this unchanged control.

Native compilation was bounded to two jobs per independent C++/Haskell stream,
with aggregate heavy compilation normally at most four. Main phases were
sequenced around those slots. Heavy outputs stay on D-backed storage. No
build-system migration was introduced.

Earlier failed attempts remain diagnostics, explicitly superseded: Lean and
Mirrors test record/layout parse corrections; online policy metadata needed for
pnpm; noninteractive CI/store setup; missing private npm entrypoint; DPM helper
cache placement; transient Haskell package setup; two Gate harness expectation
corrections; and strict producer hash refusal after an environment compiler
relink. Final CI explicitly restored GCC12 before the immutable freeze. No new
broker protocol/status channel was introduced to satisfy an over-specific test.

Excluded tiers: live/model-checker generation and comparison; production
services; native Windows/macOS TLS/ACL runtime; hosted CI and GCC13 parity; other
Gate backends; current-source Rust worker replay; broader M5/platform admission.
Haskell case-sensitive pin behavior remains the separately documented exception.

Raw main evidence is under `main/`; child streams retain separate manifests.
No private keys, compiled binaries, image files or dependency caches are copied
into this dossier. Parent reviews/final documentation are bound separately by
the parent's global manifest. Final image/keeper state and exact recovery steps
are recorded in `cleanup-receipt.json` and `workflow/recover-new-image.sh`.
