"""Retain one MW-12 command's actual output, exit and artifact hashes."""

import argparse
import hashlib
import json
import os
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("label")
parser.add_argument("--tmp-root", type=Path)
parser.add_argument("--timeout", type=float, default=300)
parser.add_argument("command", nargs=argparse.REMAINDER)
args = parser.parse_args()
command = args.command[1:] if args.command[:1] == ["--"] else args.command
if not command:
    parser.error("a command is required")
repo = Path(__file__).resolve().parents[2]
out = Path(__file__).resolve().parent / "integration"
logs = out / "logs"
logs.mkdir(parents=True, exist_ok=True)
environment = os.environ.copy()
overrides = {}
if args.tmp_root is not None:
    temporary = args.tmp_root.resolve()
    temporary.mkdir(mode=0o700, parents=True, exist_ok=True)
    overrides["TMPDIR"] = str(temporary)
environment.update(overrides)
started = datetime.now(timezone.utc).isoformat()
begin = time.monotonic()
with (logs / (args.label + ".stdout")).open("xb") as stdout, (
    logs / (args.label + ".stderr")
).open("xb") as stderr:
    result = subprocess.run(command, cwd=repo, env=environment, stdout=stdout,
                            stderr=stderr, timeout=args.timeout)
record = {
    "schemaVersion": "mirrors.mw12.command/v1", "argv": command,
    "cwd": str(repo), "startedAt": started,
    "finishedAt": datetime.now(timezone.utc).isoformat(),
    "monotonicDurationSeconds": time.monotonic() - begin,
    "environmentOverrides": overrides, "exitCode": result.returncode,
    "logs": [],
}
for stream in ("stdout", "stderr"):
    path = logs / (args.label + "." + stream)
    raw = path.read_bytes()
    record["logs"].append({"path": str(path.relative_to(out)),
                           "bytes": len(raw),
                           "sha256": hashlib.sha256(raw).hexdigest()})
(out / (args.label + ".json")).write_text(json.dumps(record, indent=2) + "\n")
print(json.dumps({"label": args.label, "exitCode": result.returncode}))
raise SystemExit(result.returncode)
