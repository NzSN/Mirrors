"""Run the repository archive checker from an empty, Lean-free runtime context."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

record = Path(__file__).resolve().parent
repo = record.parents[1]
work = repo / ".golden-build/completion-rc5-20261031"
archive = work / "dist-linux/mirrors-v0.2.0-rc.5-linux-x86_64.tar.gz"
script = work / "source/tools/release/release.py"
with tempfile.TemporaryDirectory(prefix="isolated-archive-", dir=work / "tmp") as tmp:
    root = Path(tmp)
    root.chmod(0o700)
    runtime = root / "runtime"
    runtime.mkdir(mode=0o700)
    copied_script = root / "release.py"
    shutil.copyfile(script, copied_script)
    env = {"PATH": "/usr/bin:/bin", "HOME": str(root), "TMPDIR": str(root),
           "LC_ALL": "C.UTF-8"}
    assert shutil.which("lean", path=env["PATH"]) is None
    assert shutil.which("lake", path=env["PATH"]) is None
    # The packaged check does not resolve source files. Only the standalone
    # repository checker is copied; no Lean source/build tree is in this cwd.
    before = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.chmod(0o444)
    subprocess.run(["/usr/bin/python3", "-I", "-S", "-B", str(copied_script),
                    "check-archive", "--tag", "v0.2.0-rc.5", "--archive", str(archive)],
                   cwd=runtime, env=env, check=True)
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == before
    result = {"schema": "mirrors.completion-isolated-archive/v1",
              "tag": "v0.2.0-rc.5", "archiveSha256": before, "exitCode": 0,
              "path": env["PATH"], "leanVisible": False, "lakeVisible": False,
              "workingDirectoryEmpty": not any(runtime.iterdir()),
              "temporaryMode": oct(root.stat().st_mode & 0o777),
              "osRelease": Path("/etc/os-release").read_text(),
              "scope": "Ubuntu 24.04.3 WSL2 isolated packaged-runtime smoke"}
    (record / "isolated-archive.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
