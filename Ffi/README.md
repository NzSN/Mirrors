# Ffi/ — C shims (TCB)

C shims for capabilities with no Lean ecosystem package (design §5.4):

- TLS 1.3 mutual auth via OpenSSL (or s2n-tls): `serveTlsOn` /
  `connectTlsPinned`-shaped entry points.
- Sockets: `socket`/`bind`/`accept` for the TCP transport.
- POSIX signal handling (SIGINT/SIGTERM deregistration).

Everything under `Ffi/` is trusted, not proved; keep it small, boring,
and line-auditable (§5.4, §9.1).

## Building and checking native changes

Run `lake build` after editing a shim. Lake tracks C source/header contents and
compiler settings, compiles `.lake/build/socket_shim.o` and `tls_shim.o`, and
relinks executables through their `moreLinkObjs` dependencies. Manual object or
executable deletion is unnecessary.

`CC` selects the C compiler. `OSSL_INC` and `OSSL_LIB` override the OpenSSL
include and library directories. Unix builds otherwise discover OpenSSL
headers with `pkg-config`; Windows retains the MSYS2 UCRT defaults under
`/d/Programs/msys2/ucrt64` and links `ws2_32`.

Run `bash tools/check-native-rebuild.sh` on Linux to check C-only, header-only,
compiler, library-directory, and no-op rebuilds. It requires Python 3.11+,
the pinned Lean toolchain, a C compiler, OpenSSL development files, and enough
temporary space for a copy of the checkout including build caches. It mutates
only a disposable copy. The gate builds `mirror`, `transport_spec`, and
`apalache_cli_spec`; runtime transport gates remain part of `lake test`.

See [native build design](../Docs/native-build-design.md) for trace coverage and
system-upgrade limitations. Windows execution needs a Windows runner; the
regression script currently targets Unix hosts.
