#!/usr/bin/env bash
# Exercise C -> object -> executable freshness without editing this checkout.
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$repo_dir" <<'PY'
import hashlib
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile

source = Path(sys.argv[1])
targets = ("mirror", "transport_spec", "apalache_cli_spec")
socket_outputs = ("socket_shim.o", "bin/mirror", "bin/transport_spec", "bin/apalache_cli_spec")
tls_outputs = ("tls_shim.o", "bin/mirror", "bin/transport_spec")
outputs = tuple(dict.fromkeys(socket_outputs + tls_outputs))


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


original_sources = {name: digest(source / "Ffi" / name)
                    for name in ("socket_shim.c", "tls_shim.c")}


def snapshot(work):
    return {name: (digest(work / ".lake/build" / name),
                   (work / ".lake/build" / name).stat().st_mtime_ns)
            for name in outputs}


def build(work, env):
    result = subprocess.run(["lake", "build", *targets], cwd=work, env=env,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        print(result.stdout, end="", flush=True)
        raise RuntimeError(f"lake build failed ({result.returncode})")
    for line in result.stdout.splitlines():
        if "Built " in line or line.startswith("Build completed"):
            print(line, flush=True)
    return result.stdout


def changed(before, after, affected, log):
    for name in outputs:
        if name in affected:
            if name.endswith(".o") and before[name][0] == after[name][0]:
                raise AssertionError(f"{name}: content did not change")
            if name.startswith("bin/") and f"Built {Path(name).name}:exe" not in log:
                raise AssertionError(f"{name}: executable was not relinked")
        elif before[name] != after[name]:
            raise AssertionError(f"{name}: unrelated output changed")


def no_op(work, env):
    before = snapshot(work)
    build(work, env)
    if before != snapshot(work):
        raise AssertionError("an unchanged rebuild modified outputs")


try:
    with tempfile.TemporaryDirectory(prefix="mirrors-native-rebuild-") as temporary:
        work = Path(temporary) / "repo"
        print(f"Native rebuild regression uses {work}", flush=True)
        # Copy caches as well as sources: no shared writable artifacts or source
        # mutations, and existing builds make this check inexpensive. copy2 keeps
        # timestamps, which are themselves part of the no-op assertions below.
        def ignore(directory, names):
            skipped = {".agent-teams", ".agent-teams-results", "_apalache-out", "tmp"}
            if Path(directory) == source:
                skipped.add(".git")
            # Dependency .git metadata must stay: Lake checks its origin/revision
            # and otherwise attempts to re-clone an already available package.
            return skipped.intersection(names)
        shutil.copytree(source, work, ignore=ignore)
        env = os.environ.copy()
        build(work, env)
        no_op(work, env)

        before = snapshot(work)
        socket = work / "Ffi/socket_shim.c"
        socket_text = socket.read_text()
        marker = "LEAN_EXPORT uint64_t dsh_socket_tcp(void) {"
        if socket_text.count(marker) != 1:
            raise AssertionError("socket probe insertion point changed")
        socket.write_text(socket_text.replace(marker, marker +
            "\n    volatile unsigned native_build_probe = 37; (void)native_build_probe;"))
        log = build(work, env)
        changed(before, snapshot(work), socket_outputs, log)
        no_op(work, env)
        print("PASS: socket C edit rebuilt all requested socket consumers", flush=True)

        before = snapshot(work)
        tls = work / "Ffi/tls_shim.c"
        tls_text = tls.read_text()
        marker = "LEAN_EXPORT uint64_t dsh_tls_errmsg(lean_object *outobj, uint64_t cap, uint64_t unused) {"
        if tls_text.count(marker) != 1:
            raise AssertionError("TLS probe insertion point changed")
        tls.write_text(tls_text.replace(marker, marker +
            "\n    volatile unsigned native_build_probe = 41; (void)native_build_probe;"))
        log = build(work, env)
        changed(before, snapshot(work), tls_outputs, log)
        no_op(work, env)
        print("PASS: TLS C edit rebuilt TLS consumers and preserved socket-only output", flush=True)

        header = work / "Ffi/native_rebuild_probe.h"
        header.write_text("#define MIRRORS_NATIVE_BUILD_PROBE 43\n")
        socket.write_text('#include "native_rebuild_probe.h"\n' + socket.read_text().replace(
            "native_build_probe = 37", "native_build_probe = MIRRORS_NATIVE_BUILD_PROBE"))
        log = build(work, env)
        before = snapshot(work)
        header.write_text("#define MIRRORS_NATIVE_BUILD_PROBE 47\n")
        log = build(work, env)
        # Both objects conservatively track Ffi headers; the TLS artifact may
        # be recompiled to identical bytes because this header is socket-only.
        after = snapshot(work)
        if before["socket_shim.o"][0] == after["socket_shim.o"][0]:
            raise AssertionError("header-only edit did not change socket object content")
        for target in targets:
            if f"Built {target}:exe" not in log:
                raise AssertionError(f"{target}: header-only edit did not trigger linking")
        no_op(work, env)
        print("PASS: header-only edit reached linked executables", flush=True)

        # Change CC after the lakefile has already been cached. The wrapper's
        # forced header changes a used macro so content hashes prove propagation.
        compiler = shutil.which(env.get("CC", "cc"))
        if compiler is None:
            raise AssertionError("could not resolve C compiler for wrapper probe")
        forced = Path(temporary) / "compiler-option.h"
        forced.write_text("#define MIRRORS_COMPILER_PROBE 53\n")
        socket.write_text(socket.read_text().replace("native_build_probe = MIRRORS_NATIVE_BUILD_PROBE",
            "native_build_probe = MIRRORS_NATIVE_BUILD_PROBE + MIRRORS_COMPILER_PROBE"))
        with socket.open("r+") as stream:
            text = stream.read()
            stream.seek(0)
            stream.write("#ifndef MIRRORS_COMPILER_PROBE\n#define MIRRORS_COMPILER_PROBE 0\n#endif\n" + text)
        log = build(work, env)
        before = snapshot(work)
        wrapper = Path(temporary) / "cc-wrapper"
        wrapper.write_text("#!/bin/sh\nexec " + shlex.quote(compiler) + " -include " +
                           shlex.quote(str(forced)) + ' "$@"\n')
        wrapper.chmod(0o755)
        env["CC"] = str(wrapper)
        log = build(work, env)
        after = snapshot(work)
        if before["socket_shim.o"][0] == after["socket_shim.o"][0]:
            raise AssertionError("changed CC did not change socket object content")
        for target in targets:
            if f"Built {target}:exe" not in log:
                raise AssertionError(f"{target}: changed CC did not trigger linking")
        no_op(work, env)
        print("PASS: compiler selection/options invalidate cached build configuration", flush=True)

        # The include override must also work without re-elaborating lakefile.
        include_source = env.get("OSSL_INC")
        if include_source is None:
            include_source = subprocess.check_output(
                ["pkg-config", "--variable=includedir", "openssl"], text=True).strip()
        include_override = Path(temporary) / "openssl-include"
        shutil.copytree(Path(include_source) / "openssl", include_override / "openssl")
        with (include_override / "openssl/ssl.h").open("a") as stream:
            stream.write("\n#define MIRRORS_OPENSSL_INC_PROBE 59\n")
        tls.write_text(tls.read_text().replace("#include <openssl/ssl.h>",
            "#include <openssl/ssl.h>\n#ifndef MIRRORS_OPENSSL_INC_PROBE\n"
            "#define MIRRORS_OPENSSL_INC_PROBE 0\n#endif").replace(
            "native_build_probe = 41", "native_build_probe = 41 + MIRRORS_OPENSSL_INC_PROBE"))
        build(work, env)
        env["OSSL_INC"] = str(include_override)
        before = snapshot(work)
        log = build(work, env)
        after = snapshot(work)
        if "Built mirrors/tls_shim_o" not in log:
            raise AssertionError("OSSL_INC did not recompile the TLS shim")
        changed(before, after, tls_outputs, log)
        no_op(work, env)
        print("PASS: OSSL_INC changes rebuild TLS consumers after lakefile caching", flush=True)

        # An empty -L directory still resolves OpenSSL from the normal system
        # search path, but must alter the TLS link trace in this cached lakefile.
        override = Path(temporary) / "openssl-libs"
        override.mkdir()
        env["OSSL_LIB"] = str(override)
        before = snapshot(work)
        log = build(work, env)
        after = snapshot(work)
        for name in ("socket_shim.o", "tls_shim.o", "bin/apalache_cli_spec"):
            if before[name] != after[name]:
                raise AssertionError(f"OpenSSL library override rebuilt unrelated output {name}")
        for target in ("mirror", "transport_spec"):
            if f"Built {target}:exe" not in log:
                raise AssertionError(f"OSSL_LIB did not relink {target}")
        no_op(work, env)
        print("PASS: OSSL_LIB changes relink TLS consumers after lakefile caching", flush=True)
finally:
    for name, original in original_sources.items():
        if digest(source / "Ffi" / name) != original:
            raise AssertionError(f"original {name} changed during isolated regression")

print("All native rebuild checks passed; original shim sources unchanged.", flush=True)
PY
