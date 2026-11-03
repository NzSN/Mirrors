#!/usr/bin/env python3
"""Compare a Windows source manifest with the Phase A source manifest. Read-only."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PHASE_A = ROOT / ".golden-build/mainwork-s3-rc6-20261103/archive/source-manifest.json"
observed = Path(sys.argv[1])
label = sys.argv[2]
expected = {row["path"]: row for row in json.loads(PHASE_A.read_text(encoding="utf-8"))["files"]}
rows = [json.loads(line) for line in observed.read_text(encoding="utf-8").splitlines() if line.strip()]
seen = {row["path"]: row for row in rows}
missing = sorted(set(expected) - set(seen))
changed = sorted(
    path for path, row in expected.items()
    if path in seen and (seen[path]["bytes"] != row["bytes"] or seen[path]["sha256"] != row["sha256"])
)
extra = sorted(path for path in seen if path not in expected and not path.startswith(".lake/"))
result = {
    "schema": "mirrors.s3-rc6.windows-source-check/v1",
    "published": False,
    "deployed": False,
    "label": label,
    "observedFiles": len(rows),
    "expectedFiles": len(expected),
    "missing": missing,
    "changed": changed,
    "extraOutsideLake": extra,
    "matched": not missing and not changed and not extra and len(expected) == 9833,
}
out = Path(sys.argv[3])
out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
print(json.dumps({k: result[k] for k in ("label", "observedFiles", "expectedFiles", "matched", "missing", "changed", "extraOutsideLake")}))
if not result["matched"]:
    raise SystemExit(1)
