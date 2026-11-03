"""Read-only structural lock review and bounded local socket probes."""

import hashlib
import json
import shutil
import socket
import sys
import tempfile
from pathlib import Path

repo = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(repo / "tools/distribution"))
from install import filesystem_type
from manifest_check import validate_locks

verifier = repo / ".lake/build/bin/framework_catalog"
verifier_sha = hashlib.sha256(verifier.read_bytes()).hexdigest()
results = []
for name, catalog in (
    ("reference-node", "framework-catalog.json"),
    ("reference-node-wsl2-26.04", "framework-catalog-wsl2-26.04.json"),
):
    root = repo / "distribution" / name
    paths = [root / part for part in (
        "profiles.json", "component-lock.json", "dependency-lock.json"
    )]
    before = {str(p.relative_to(repo)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in paths}
    value = validate_locks(root, verifier, verifier_sha,
                           repo / "catalog" / catalog)
    after = {str(p.relative_to(repo)): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in paths}
    assert before == after
    results.append({"root": str(root.relative_to(repo)), "validated": True,
                    "catalog": catalog, "lockSha256": before,
                    "returnedFields": sorted(value)})

probes = []
with tempfile.TemporaryDirectory(
    prefix="socket-review-", dir=repo / ".golden-build/mainwork-20261103-review-tmp"
) as temporary:
    for family, address in (
        (socket.AF_INET, ("127.0.0.1", 0)),
        (socket.AF_UNIX, str(Path(temporary) / "probe.sock")),
    ):
        try:
            with socket.socket(family, socket.SOCK_STREAM) as stream:
                stream.bind(address)
                stream.listen(1)
            probes.append({"family": family.name, "bindListen": True})
        except OSError as error:
            probes.append({"family": family.name, "bindListen": False,
                           "errno": error.errno, "error": str(error)})

carrier = repo / (
    ".golden-build/batteries-repin-20261031/artifacts/sha256/"
    "73130433fb6388cd66847fc9c865bfece7b2ad389c174b55b61a00d60a7fac5a/"
    "batteries-v4.33.0.bundle"
)
print(json.dumps({
    "schemaVersion": "mirrors.mainwork-admission-review/v1",
    "claim": "structural checks and capability probes only; not S5 admission",
    "existingVerifierSha256": verifier_sha,
    "verifierProvenance": "existing local binary; not a newly frozen build",
    "locks": results, "repositoryFilesystem": filesystem_type(repo),
    "defaultTmpFilesystem": filesystem_type(Path(tempfile.gettempdir())),
    "socketProbes": probes, "straceOnPath": shutil.which("strace"),
    "recordedCarrierExists": carrier.exists(),
}, indent=2))
