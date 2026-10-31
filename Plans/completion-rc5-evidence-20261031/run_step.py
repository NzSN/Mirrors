#!/usr/bin/env python3
"""Capture an actual bounded command and its exit without granting stage credit."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument("name")
parser.add_argument("--cwd", required=True, type=Path)
parser.add_argument("--timeout", type=int, default=3600)
parser.add_argument("argv", nargs=argparse.REMAINDER)
args = parser.parse_args()
argv = args.argv[1:] if args.argv[:1] == ["--"] else args.argv
if not argv:
    parser.error("command required after --")
record = Path(__file__).resolve().parent
log = record / "logs" / (args.name + ".log")
receipt = record / (args.name + ".json")
if log.exists() or receipt.exists():
    parser.error("refusing to overwrite an earlier attempt")
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
timed_out = False
with log.open("wb") as output:
    try:
        proc = subprocess.run(argv, cwd=args.cwd.resolve(), stdout=output,
                              stderr=subprocess.STDOUT, timeout=args.timeout)
        code = proc.returncode
    except subprocess.TimeoutExpired:
        timed_out = True
        code = 124
    except OSError as error:
        output.write((str(error) + "\n").encode())
        code = 127
result = {
    "schema": "mirrors.completion-command/v1", "name": args.name,
    "argv": argv, "cwd": str(args.cwd.resolve()), "startedAt": started,
    "finishedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "timeoutSeconds": args.timeout, "timedOut": timed_out, "exitCode": code,
    "log": str(log.relative_to(record)), "logBytes": log.stat().st_size,
    "logSha256": hashlib.sha256(log.read_bytes()).hexdigest(),
    "environment": {key: os.environ.get(key) for key in
                    ("TMPDIR", "MIRRORS_DPM_PYTHON", "CC", "OSSL_INC", "OSSL_LIB")},
}
receipt.write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2), flush=True)
sys.exit(code)
