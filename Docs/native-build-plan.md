# Native build implementation plan

Owner: `native_build` subagent. Scope: `lakefile.lean`, native build regression,
`Ffi/README.md`, and this design/plan pair. Other agents own CI and interop.

1. [x] Inspect the pinned Lake source and document the source/object/link graph.
2. [x] Replace side-effect compilation with traced `buildO` targets and connect
   executable `moreLinkObjs` dependencies.
3. [x] Preserve platform/compiler settings and trace OpenSSL library overrides.
4. [x] Add an isolated regression for source/header/compiler changes and no-op
   rebuilds; document its prerequisites and invocation.
5. [x] Execute baseline/rebuild checks and record evidence and platform limits.
6. [x] Run the transport runtime gate as part of the parent integration run.

Acceptance: both C-only edits propagate through the object and executable
edges; TLS-only edits do not relink socket-only clients; unchanged builds leave
outputs stable; original C sources remain unchanged. No commits or pushes.

## Verification evidence (2026-09-06)

`bash tools/check-native-rebuild.sh` passed with exit code 0 on Linux, using
Lean 4.33.0, GCC 13.3.0, and OpenSSL 3.0.13. It built `mirror`,
`transport_spec`, and `apalache_cli_spec` in an isolated copy and verified:

- Socket-only and TLS-only C changes alter the object SHA-256 and cause every
  requested affected executable to link; TLS edits preserve socket-only output.
- Included local header changes reach native objects and executable links.
- Changing `CC` after lakefile caching changes compiled behavior and relinks.
- Changing `OSSL_INC` selects a copied header with different test behavior,
  recompiles the TLS object, and relinks TLS executables only.
- Changing `OSSL_LIB` after lakefile caching relinks TLS executables without
  rebuilding either C object or the socket-only executable.
- Every immediate no-op rebuild preserves object/executable hashes and mtimes.
- Original repository shim source hashes remain unchanged.

`bash -n tools/check-native-rebuild.sh` and `git diff --check` passed.
Windows execution was not available. Arbitrary system-header/compiler-binary
upgrades outside the documented trace inputs still call for a clean build.
The parent agent coordinates runtime transport checks and CI integration.


Coordinator integration: the full `APALACHE_MC=... lake test` driver passed on
2026-09-06, including transport/TLS and registry runtime suites after the native
link dependency change. The prior runtime-smoke handoff is now complete;
Windows execution remains unverified.
