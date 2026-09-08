# Tracked native shim builds

## Problem and intended behavior

The socket and TLS targets currently run a shell timestamp probe, compile an
object as a side effect, and expose the object through `extraDepTargets`.
Executable link commands mention the object paths as plain strings. A C-only
change therefore lacks a dependable object-to-link trace edge, and developers
have been instructed to delete objects and executables manually.

A normal `lake build <target>` must compile a changed shim and relink every
requested executable that consumes it. An unchanged build must leave both
objects and executables alone. C source contents, compiler selection/options,
and explicitly tracked header contents determine object freshness.

## Build graph

Use the pinned Lean/Lake 4.33 implementation directly:

1. `inputTextFile` and `inputDir` create content-traced C/header inputs.
2. `buildO` compiles each shim, caching its artifact through Lake's trace.
3. `moreLinkObjs` fetches those jobs into executable link information, so the
   object trace participates in the executable's own freshness calculation.
4. TLS executables use fetched `Dynlib` targets for OpenSSL. Their library
   directory is read on every invocation and traced; changing `OSSL_LIB`
   therefore changes linker arguments even when lakefile elaboration is cached.

The socket-only executables continue to depend only on the socket object;
executables that use TLS depend on both. The existing object target names and
`.lake/build/*_shim.o` paths remain available for external scripts. No shim ABI,
runtime operation, Lean proof, or wire protocol changes.

The implementation uses `moreLinkObjs` rather than deprecated `extern_lib`.
In the local pinned toolchain, the relevant evidence is
`Lake/Build/Common.lean` (`buildO`), `Lake/Build/Module.lean`
(`recComputeModuleLinkInfo`), and `Lake/Build/Executable.lean`
(`LeanExe.recBuildExe`).

## Compiler and platform configuration

Preserve `CC` (default `cc` on Unix and `gcc` on Windows), the Lean include
directory, Unix `pkg-config` OpenSSL discovery, and Windows `ws2_32` linkage.
Keep existing Windows OpenSSL defaults and honor `OSSL_INC` / `OSSL_LIB` on
both platforms. Configuration is read while targets are fetched, not frozen
by elaboration-time `run_io`.

Compiler command and version, compile arguments, Lean toolchain identity,
local `Ffi/*.h` files, Lean include headers, and the selected OpenSSL header
tree are tracked. Arbitrary system C library headers and replacing a compiler
binary without changing its reported identity are outside this bounded change;
clean builds remain appropriate after such system upgrades.

## Regression and acceptance

An isolated temporary copy protects the working tree and concurrent work.
Build representative socket-only and TLS executables, record object/executable
hashes and mtimes, then edit only the copied socket shim and only the copied
TLS shim. Each affected object must change and each affected executable must
relink; a linked executable may retain identical bytes when it discards the
changed unused function. Socket-only output must remain unchanged for a
TLS-only edit. An immediate second build must do no work. Also check a local
included header change, compiler selection, and both OpenSSL directory overrides.
The original repository's shim bytes must never be edited by the regression.

Run the actual mirror plus transport executables to verify linkage. Linux
execution validates the current host; Windows linkage is preserved in source
but requires a Windows runner to claim execution coverage.
