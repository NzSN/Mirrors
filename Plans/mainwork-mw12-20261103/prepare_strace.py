"""Prepare a hash-guarded userspace tracer without inherited library overrides."""

import hashlib
import json
import re
import shlex
import subprocess
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
phase = Path(__file__).resolve().parent
inputs = json.loads((phase / "acquisition/inputs.json").read_text())
tracer = next(item for item in inputs["acquired"] if item["id"] == "strace")
binary = (repo / tracer["path"]).resolve(strict=True)
libraries = (repo / tracer["libraryPath"]).resolve(strict=True)
loader = Path("/lib64/ld-linux-x86-64.so.2").resolve(strict=True)
assert hashlib.sha256(binary.read_bytes()).hexdigest() == tracer["sha256"]
listed = subprocess.check_output(
    [str(loader), "--library-path", str(libraries), "--list", str(binary)], text=True)
paths = {binary, loader}
for token in re.findall(r"(?:=>\s+)?(/[^\s]+)", listed):
    path = Path(token)
    if path.is_file():
        paths.add(path)
records = [{"path": str(path), "resolvedPath": str(path.resolve(strict=True)),
            "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
           for path in sorted(paths)]
checks = "\n".join(item["sha256"] + "  " + item["path"] for item in records)
script = ("#!/bin/sh\nset -eu\n"
          "/usr/bin/sha256sum --check --status <<'MIRRORS_TRACER_PINS'\n"
          + checks + "\nMIRRORS_TRACER_PINS\nexec " + shlex.quote(str(loader))
          + " --library-path " + shlex.quote(str(libraries)) + " "
          + shlex.quote(str(binary)) + ' "$@"\n')
out = repo / ".golden-build/mw12-20261103/integration-runtime"
out.mkdir(mode=0o700, parents=True, exist_ok=True)
out.chmod(0o700)
wrapper = out / "strace-pinned"
with wrapper.open("x") as stream:
    stream.write(script)
wrapper.chmod(0o555)
(phase / "integration/strace-closure.json").write_text(json.dumps({
    "schemaVersion": "mirrors.mw12.tracer-closure/v1",
    "wrapper": str(wrapper), "wrapperSha256": hashlib.sha256(wrapper.read_bytes()).hexdigest(),
    "dependencies": records,
    "loaderInvocation": [str(loader), "--library-path", str(libraries), str(binary)],
    "environmentOverrides": {}, "qualificationClaim": False,
}, indent=2) + "\n")
print(str(wrapper))
